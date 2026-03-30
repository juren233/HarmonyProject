import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_care_harmony/app/add_sheet.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/ios_native_dock.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';
import 'package:pet_care_harmony/app/me_page.dart';
import 'package:pet_care_harmony/app/navigation_palette.dart';
import 'package:pet_care_harmony/notifications/method_channel_notification_adapter.dart';
import 'package:pet_care_harmony/notifications/notification_coordinator.dart';
import 'package:pet_care_harmony/notifications/notification_models.dart';
import 'package:pet_care_harmony/notifications/notification_platform_adapter.dart';
import 'package:pet_care_harmony/app/pet_care_pages.dart' hide MePage;
import 'package:pet_care_harmony/app/pet_edit_sheet.dart';
import 'package:pet_care_harmony/app/pet_first_launch_intro.dart';
import 'package:pet_care_harmony/app/pet_onboarding_overlay.dart';
import 'package:pet_care_harmony/state/app_settings_controller.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class PetCareRoot extends StatefulWidget {
  const PetCareRoot({
    super.key,
    this.settingsController,
    this.iosDockBuilder,
    this.storeLoader,
    this.notificationAdapter,
  });

  final AppSettingsController? settingsController;
  final IosDockBuilder? iosDockBuilder;
  final Future<PetCareStore> Function()? storeLoader;
  final NotificationPlatformAdapter? notificationAdapter;

  @override
  State<PetCareRoot> createState() => _PetCareRootState();
}

enum _OnboardingEntryPoint { intro, manual }

enum _DockPresentationMode { liveNative, frozenSnapshot }

enum _FirstLaunchTransition {
  idle,
  introToOnboarding,
  onboardingToIntro,
  introToHome,
  deferToHome,
}

class _PetCareRootState extends State<PetCareRoot>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _firstLaunchFlipDuration = Duration(milliseconds: 520);
  static const _firstLaunchPushUpDuration = Duration(milliseconds: 720);
  static const _firstLaunchDeferRevealDuration = Duration(milliseconds: 680);
  static const _introFinalPageIndex = 2;

  PetCareStore? _store;
  NotificationCoordinator? _notificationCoordinator;
  String _activeChecklistKey = 'today';
  String? _highlightedChecklistItemKey;
  bool _showFirstLaunchIntro = false;
  bool _showOnboarding = false;
  _OnboardingEntryPoint _onboardingEntryPoint = _OnboardingEntryPoint.manual;
  _FirstLaunchTransition _firstLaunchTransition = _FirstLaunchTransition.idle;
  late final AnimationController _firstLaunchTransitionController;
  final GlobalKey _firstLaunchIntroSurfaceKey = GlobalKey();
  int _introInitialPage = 0;
  bool _introSkipLaunchAnimation = false;
  bool _retainIntroSurface = false;
  _DockPresentationMode _dockPresentationMode =
      _DockPresentationMode.liveNative;
  Timer? _timeRefreshTimer;

  bool get _isTransitioning =>
      _firstLaunchTransition != _FirstLaunchTransition.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstLaunchTransitionController = AnimationController(
      vsync: this,
      duration: _firstLaunchFlipDuration,
    )..addStatusListener(_handleFirstLaunchTransitionStatus);
    _loadStore();
  }

  Future<void> _loadStore() async {
    final store = await (widget.storeLoader ?? PetCareStore.load)();
    if (!mounted) {
      return;
    }
    final oldStore = _store;
    oldStore?.removeListener(_handleStoreChanged);
    store.addListener(_handleStoreChanged);
    setState(() {
      _store = store;
      _notificationCoordinator = null;
      _showFirstLaunchIntro =
          store.pets.isEmpty && store.shouldAutoShowFirstLaunchIntro;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _firstLaunchTransition = _FirstLaunchTransition.idle;
      _introInitialPage = 0;
      _introSkipLaunchAnimation = false;
      _retainIntroSurface = false;
    });
    _firstLaunchTransitionController.stop();
    _firstLaunchTransitionController.reset();
    _startTimeRefreshTicker();
    unawaited(_initializeNotifications(store));
  }

  Future<void> _initializeNotifications(PetCareStore store) async {
    final coordinator = NotificationCoordinator(
      adapter: widget.notificationAdapter ??
          MethodChannelNotificationPlatformAdapter(),
    );
    await coordinator.init();
    await coordinator.syncFromStore(store);
    final launchIntent = await coordinator.consumeLaunchIntent();
    if (!mounted || !identical(_store, store)) {
      coordinator.dispose();
      return;
    }
    setState(() {
      _notificationCoordinator = coordinator;
    });
    if (launchIntent != null) {
      _applyNotificationIntent(store, launchIntent);
    }
  }

  void _startTimeRefreshTicker() {
    _timeRefreshTimer?.cancel();
    _timeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return Scaffold(
        body: HyperPageBackground(
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final overlayStyle = petCareOverlayStyleForTheme(Theme.of(context));
    final platform = Theme.of(context).platform;
    final canUseIosNativeDock = !_showFirstLaunchIntro &&
        !_showOnboarding &&
        !_isTransitioning &&
        supportsIosNativeDock(platform);
    final useNativeIosDock = canUseIosNativeDock &&
        _dockPresentationMode == _DockPresentationMode.liveNative;
    final useIosDockSnapshot = canUseIosNativeDock &&
        _dockPresentationMode == _DockPresentationMode.frozenSnapshot;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBody: true,
        body: _PetCareBody(
          store: store,
          activeChecklistKey: _activeChecklistKey,
          showFirstLaunchIntro: _showFirstLaunchIntro,
          showOnboarding: _showOnboarding,
          settingsController: widget.settingsController,
          notificationCoordinator: _notificationCoordinator,
          highlightedChecklistItemKey: _highlightedChecklistItemKey,
          onSectionChanged: (value) =>
              setState(() => _activeChecklistKey = value),
          onAddFirstPet: _openManualOnboarding,
          onStartOnboardingFromIntro: _openOnboardingFromIntro,
          onExploreFirstLaunchIntro: _dismissFirstLaunchIntro,
          onEditPet: (pet) => _openEditPetSheet(context, store, pet),
          onSubmitOnboarding: _submitOnboarding,
          onDeferOnboarding: _deferOnboarding,
          onReturnToIntroFromOnboarding:
              _onboardingEntryPoint == _OnboardingEntryPoint.intro
                  ? _returnToIntroFromOnboarding
                  : null,
          firstLaunchTransition: _firstLaunchTransition,
          firstLaunchTransitionController: _firstLaunchTransitionController,
          introInitialPage: _introInitialPage,
          introSkipLaunchAnimation: _introSkipLaunchAnimation,
          retainIntroSurface: _retainIntroSurface,
          introSurfaceKey: _firstLaunchIntroSurfaceKey,
        ),
        bottomNavigationBar: _showFirstLaunchIntro || _showOnboarding
            ? null
            : useIosDockSnapshot
                ? _buildIosDockSnapshot(store)
                : useNativeIosDock
                ? _buildIosNativeDock(context, store)
                : _PetCareBottomNav(
                    store: store,
                    onAdd: () => _openAddSheet(context, store),
                  ),
      ),
    );
  }

  Widget _buildIosNativeDock(BuildContext context, PetCareStore store) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final builder = widget.iosDockBuilder;
        if (builder != null) {
          return builder(
            context,
            store.activeTab,
            store.setActiveTab,
            () => _openAddSheet(context, store),
          );
        }

        return IosNativeDockHost(
          selectedTab: store.activeTab,
          onTabSelected: store.setActiveTab,
          onAddTap: () => _openAddSheet(context, store),
        );
      },
    );
  }

  Widget _buildIosDockSnapshot(PetCareStore store) {
    return _PetCareBottomNav(
      key: const ValueKey('ios_native_dock_snapshot'),
      store: store,
      onAdd: () {},
      interactive: false,
      enableBlur: false,
    );
  }

  Future<void> _openAddSheet(BuildContext context, PetCareStore store) async {
    final tokens = context.petCareTokens;
    final shouldFreezeDock = supportsIosNativeDock(Theme.of(context).platform) &&
        !_showFirstLaunchIntro &&
        !_showOnboarding &&
        !_isTransitioning;
    if (shouldFreezeDock && mounted) {
      setState(() {
        _dockPresentationMode = _DockPresentationMode.frozenSnapshot;
      });
    }
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: tokens.pageGradientTop,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        builder: (context) => AddActionSheet(store: store),
      );
    } finally {
      if (shouldFreezeDock && mounted) {
        setState(() {
          _dockPresentationMode = _DockPresentationMode.liveNative;
        });
      }
    }
  }

  Future<void> _openEditPetSheet(
    BuildContext context,
    PetCareStore store,
    Pet pet,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => PetEditSheet(store: store, pet: pet),
    );
  }

  void _openManualOnboarding() {
    _resetFirstLaunchTransition();
    setState(() {
      _showFirstLaunchIntro = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _showOnboarding = true;
      _introInitialPage = 0;
      _introSkipLaunchAnimation = false;
    });
  }

  Future<void> _openOnboardingFromIntro() async {
    final store = _store;
    if (store == null || _isTransitioning) {
      return;
    }

    await store.dismissFirstLaunchIntro();
    if (!mounted) {
      return;
    }

    setState(() {
      _firstLaunchTransitionController.duration = _firstLaunchFlipDuration;
      _onboardingEntryPoint = _OnboardingEntryPoint.intro;
      _introInitialPage = _introFinalPageIndex;
      _introSkipLaunchAnimation = true;
      _retainIntroSurface = true;
      _firstLaunchTransition = _FirstLaunchTransition.introToOnboarding;
    });
    _firstLaunchTransitionController.forward(from: 0);
  }

  Future<void> _dismissFirstLaunchIntro() async {
    final store = _store;
    if (store == null || _isTransitioning) {
      return;
    }

    await store.dismissFirstLaunchIntro();
    if (!mounted) {
      return;
    }
    store.setActiveTab(AppTab.checklist);
    setState(() {
      _firstLaunchTransitionController.duration = _firstLaunchPushUpDuration;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _retainIntroSurface = false;
      _firstLaunchTransition = _FirstLaunchTransition.introToHome;
    });
    _firstLaunchTransitionController.forward(from: 0);
  }

  void _returnToIntroFromOnboarding() {
    if (_isTransitioning) {
      return;
    }
    setState(() {
      _firstLaunchTransitionController.duration = _firstLaunchFlipDuration;
      _onboardingEntryPoint = _OnboardingEntryPoint.intro;
      _retainIntroSurface = true;
      _firstLaunchTransition = _FirstLaunchTransition.onboardingToIntro;
    });
    _firstLaunchTransitionController.forward(from: 0);
  }

  Future<void> _submitOnboarding(PetOnboardingResult result) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.addPet(
      name: result.name,
      type: result.type,
      breed: result.breed,
      sex: result.sex,
      birthday: result.birthday,
      weightKg: result.weightKg,
      neuterStatus: result.neuterStatus,
      feedingPreferences: result.feedingPreferences,
      allergies: result.allergies,
      note: result.note,
    );
    store.setActiveTab(AppTab.checklist);
    if (!mounted) {
      return;
    }
    _resetFirstLaunchTransition();
    setState(() {
      _showFirstLaunchIntro = false;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _introInitialPage = 0;
      _introSkipLaunchAnimation = false;
      _retainIntroSurface = false;
      _dockPresentationMode = _DockPresentationMode.liveNative;
    });
  }

  Future<void> _deferOnboarding() async {
    if (_onboardingEntryPoint != _OnboardingEntryPoint.intro) {
      _resetFirstLaunchTransition();
      setState(() {
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _introInitialPage = 0;
      _introSkipLaunchAnimation = false;
      _retainIntroSurface = false;
      _dockPresentationMode = _DockPresentationMode.liveNative;
    });
      return;
    }

    final store = _store;
    if (store == null || _isTransitioning) {
      return;
    }

    await store.dismissFirstLaunchIntro();
    if (!mounted) {
      return;
    }
    store.setActiveTab(AppTab.checklist);
    setState(() {
      _firstLaunchTransitionController.duration =
          _firstLaunchDeferRevealDuration;
      _showFirstLaunchIntro = false;
      _retainIntroSurface = false;
      _firstLaunchTransition = _FirstLaunchTransition.deferToHome;
    });
    _firstLaunchTransitionController.forward(from: 0);
  }

  void _handleStoreChanged() {
    final store = _store;
    final coordinator = _notificationCoordinator;
    if (store == null || coordinator == null) {
      return;
    }
    unawaited(coordinator.syncFromStore(store));
    unawaited(_consumeForegroundNotificationTap(store));
  }

  Future<void> _consumeForegroundNotificationTap(PetCareStore store) async {
    final coordinator = _notificationCoordinator;
    if (coordinator == null) {
      return;
    }
    final intent = await coordinator.consumeForegroundTap();
    if (intent != null && mounted) {
      _applyNotificationIntent(store, intent);
    }
  }

  void _applyNotificationIntent(
    PetCareStore store,
    NotificationLaunchIntent intent,
  ) {
    final sectionKey = _sectionKeyForPayload(store, intent.payload);
    _resetFirstLaunchTransition();
    setState(() {
      _showFirstLaunchIntro = false;
      _showOnboarding = false;
      _activeChecklistKey = sectionKey;
      _highlightedChecklistItemKey = intent.payload.key;
      _introInitialPage = 0;
      _introSkipLaunchAnimation = false;
      _retainIntroSurface = false;
      _dockPresentationMode = _DockPresentationMode.liveNative;
    });
    store.setActiveTab(AppTab.checklist);
  }

  void _handleFirstLaunchTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }

    setState(() {
      switch (_firstLaunchTransition) {
        case _FirstLaunchTransition.idle:
          break;
        case _FirstLaunchTransition.introToOnboarding:
          _showFirstLaunchIntro = false;
          _showOnboarding = true;
          _onboardingEntryPoint = _OnboardingEntryPoint.intro;
          _retainIntroSurface = true;
          break;
        case _FirstLaunchTransition.onboardingToIntro:
          _showOnboarding = false;
          _showFirstLaunchIntro = true;
          _onboardingEntryPoint = _OnboardingEntryPoint.intro;
          _retainIntroSurface = false;
          break;
        case _FirstLaunchTransition.introToHome:
          _showFirstLaunchIntro = false;
          _showOnboarding = false;
          _onboardingEntryPoint = _OnboardingEntryPoint.manual;
          _introInitialPage = 0;
          _introSkipLaunchAnimation = false;
          _retainIntroSurface = false;
          _dockPresentationMode = _DockPresentationMode.liveNative;
          break;
        case _FirstLaunchTransition.deferToHome:
          _showFirstLaunchIntro = false;
          _showOnboarding = false;
          _onboardingEntryPoint = _OnboardingEntryPoint.manual;
          _introInitialPage = 0;
          _introSkipLaunchAnimation = false;
          _retainIntroSurface = false;
          _dockPresentationMode = _DockPresentationMode.liveNative;
          break;
      }
      _firstLaunchTransition = _FirstLaunchTransition.idle;
    });
    _firstLaunchTransitionController.reset();
  }

  void _resetFirstLaunchTransition() {
    _firstLaunchTransitionController.stop();
    _firstLaunchTransitionController.duration = _firstLaunchFlipDuration;
    _firstLaunchTransitionController.reset();
    _firstLaunchTransition = _FirstLaunchTransition.idle;
    _dockPresentationMode = _DockPresentationMode.liveNative;
  }

  String _sectionKeyForPayload(
    PetCareStore store,
    NotificationPayload payload,
  ) {
    for (final section in store.checklistSections) {
      for (final item in section.items) {
        final itemKey = '${item.sourceType}:${item.id}';
        if (itemKey == payload.key) {
          return section.key;
        }
      }
    }
    return 'today';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeRefreshTimer?.cancel();
    _store?.removeListener(_handleStoreChanged);
    _notificationCoordinator?.dispose();
    _firstLaunchTransitionController.dispose();
    super.dispose();
  }
}

class _PetCareBody extends StatelessWidget {
  const _PetCareBody({
    required this.store,
    required this.activeChecklistKey,
    required this.showFirstLaunchIntro,
    required this.showOnboarding,
    required this.settingsController,
    required this.notificationCoordinator,
    required this.highlightedChecklistItemKey,
    required this.onSectionChanged,
    required this.onAddFirstPet,
    required this.onStartOnboardingFromIntro,
    required this.onExploreFirstLaunchIntro,
    required this.onEditPet,
    required this.onSubmitOnboarding,
    required this.onDeferOnboarding,
    required this.onReturnToIntroFromOnboarding,
    required this.firstLaunchTransition,
    required this.firstLaunchTransitionController,
    required this.introInitialPage,
    required this.introSkipLaunchAnimation,
    required this.retainIntroSurface,
    required this.introSurfaceKey,
  });

  final PetCareStore store;
  final String activeChecklistKey;
  final bool showFirstLaunchIntro;
  final bool showOnboarding;
  final AppSettingsController? settingsController;
  final NotificationCoordinator? notificationCoordinator;
  final String? highlightedChecklistItemKey;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onAddFirstPet;
  final Future<void> Function() onStartOnboardingFromIntro;
  final Future<void> Function() onExploreFirstLaunchIntro;
  final ValueChanged<Pet> onEditPet;
  final Future<void> Function(PetOnboardingResult result) onSubmitOnboarding;
  final Future<void> Function() onDeferOnboarding;
  final VoidCallback? onReturnToIntroFromOnboarding;
  final _FirstLaunchTransition firstLaunchTransition;
  final AnimationController firstLaunchTransitionController;
  final int introInitialPage;
  final bool introSkipLaunchAnimation;
  final bool retainIntroSurface;
  final GlobalKey introSurfaceKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, firstLaunchTransitionController]),
      builder: (context, _) {
        final firstLaunchTransitionProgress =
            firstLaunchTransitionController.value;
        final activeTab = store.activeTab;
        final notificationCoordinator = this.notificationCoordinator;
        final shouldRenderIntroSurface = showFirstLaunchIntro ||
            retainIntroSurface ||
            firstLaunchTransition == _FirstLaunchTransition.introToHome;
        final shouldRenderOnboardingSurface = showOnboarding &&
            firstLaunchTransition != _FirstLaunchTransition.deferToHome;
        return RepaintBoundary(
          key: const ValueKey('page_content_boundary'),
          child: Stack(
            children: [
              HyperPageBackground(
                child: switch (activeTab) {
                  AppTab.checklist => ChecklistPage(
                      store: store,
                      activeSectionKey: activeChecklistKey,
                      highlightedChecklistItemKey: highlightedChecklistItemKey,
                      onSectionChanged: onSectionChanged,
                      onAddFirstPet: onAddFirstPet,
                    ),
                  AppTab.overview => OverviewPage(
                      store: store,
                      onAddFirstPet: onAddFirstPet,
                    ),
                  AppTab.pets => PetsPage(
                      store: store,
                      onAddFirstPet: onAddFirstPet,
                      onEditPet: onEditPet,
                    ),
                  AppTab.me => MePage(
                      themePreference: settingsController?.themePreference ??
                          AppThemePreference.system,
                      onThemePreferenceChanged: (value) =>
                          settingsController?.setThemePreference(value),
                      notificationPermissionState:
                          notificationCoordinator?.permissionState ??
                              NotificationPermissionState.unknown,
                      notificationPushToken: notificationCoordinator?.pushToken,
                      onRequestNotificationPermission:
                          notificationCoordinator == null
                              ? null
                              : () async {
                                  await notificationCoordinator
                                      .requestPermission();
                                },
                      onOpenNotificationSettings:
                          notificationCoordinator == null
                              ? null
                              : () async {
                                  final result = await notificationCoordinator
                                      .openNotificationSettings();
                                  if (result !=
                                      NotificationSettingsOpenResult.opened) {
                                    debugPrint(
                                      'Open notification settings did not succeed: ${result.name}',
                                    );
                                  }
                                },
                    ),
                },
              ),
              Positioned.fill(
                key: const ValueKey('first_launch_transition_host'),
                child: Stack(
                  children: [
                    if (firstLaunchTransition ==
                        _FirstLaunchTransition.introToOnboarding)
                      _FirstLaunchTransitionSurface(
                        key: const ValueKey(
                          'first_launch_transition_incoming_onboarding',
                        ),
                        mode: _FirstLaunchSurfaceMotion.flipInFromRight,
                        progress: firstLaunchTransitionProgress,
                        motionKey: const ValueKey(
                          'first_launch_transition_incoming_onboarding_motion',
                        ),
                        child: _buildOnboardingOverlay(),
                      ),
                    if (firstLaunchTransition ==
                        _FirstLaunchTransition.deferToHome)
                      _buildDeferredOnboardingExit(
                        progress: firstLaunchTransitionProgress,
                      ),
                    if (shouldRenderIntroSurface)
                      _FirstLaunchTransitionSurface(
                        key: const ValueKey(
                          'first_launch_transition_outgoing_intro',
                        ),
                        mode: switch (firstLaunchTransition) {
                          _FirstLaunchTransition.introToOnboarding =>
                            _FirstLaunchSurfaceMotion.flipOutToLeft,
                          _FirstLaunchTransition.onboardingToIntro =>
                            _FirstLaunchSurfaceMotion.flipInFromLeft,
                          _FirstLaunchTransition.introToHome =>
                            _FirstLaunchSurfaceMotion.pushUp,
                          _ => showFirstLaunchIntro
                              ? _FirstLaunchSurfaceMotion.stationary
                              : _FirstLaunchSurfaceMotion.hidden,
                        },
                        progress: firstLaunchTransitionProgress,
                        motionKey: switch (firstLaunchTransition) {
                          _FirstLaunchTransition.introToOnboarding =>
                            const ValueKey(
                              'first_launch_transition_outgoing_intro_motion',
                            ),
                          _FirstLaunchTransition.onboardingToIntro =>
                            const ValueKey(
                              'first_launch_transition_incoming_intro_motion',
                            ),
                          _FirstLaunchTransition.introToHome => const ValueKey(
                              'first_launch_transition_intro_to_home',
                            ),
                          _ => null,
                        },
                        child: _buildIntroOverlay(
                          initialPage: introInitialPage,
                          skipLaunchAnimation: introSkipLaunchAnimation,
                        ),
                      ),
                    if (shouldRenderOnboardingSurface)
                      _FirstLaunchTransitionSurface(
                        key: const ValueKey(
                          'first_launch_transition_outgoing_onboarding',
                        ),
                        mode: switch (firstLaunchTransition) {
                          _FirstLaunchTransition.onboardingToIntro =>
                            _FirstLaunchSurfaceMotion.flipOutToRight,
                          _ => _FirstLaunchSurfaceMotion.stationary,
                        },
                        progress: firstLaunchTransitionProgress,
                        motionKey: firstLaunchTransition ==
                                _FirstLaunchTransition.onboardingToIntro
                            ? const ValueKey(
                                'first_launch_transition_outgoing_onboarding_motion',
                              )
                            : null,
                        child: _buildOnboardingOverlay(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntroOverlay({
    required int initialPage,
    required bool skipLaunchAnimation,
  }) {
    return KeyedSubtree(
      key: const ValueKey('first_launch_intro_surface'),
      child: PetFirstLaunchIntro(
        key: introSurfaceKey,
        fillParent: false,
        initialPage: initialPage,
        skipLaunchAnimation: skipLaunchAnimation,
        onStartOnboarding: onStartOnboardingFromIntro,
        onExploreFirst: onExploreFirstLaunchIntro,
      ),
    );
  }

  Widget _buildOnboardingOverlay() {
    return PetOnboardingOverlay(
      key: const ValueKey('first_launch_onboarding_surface'),
      onSubmit: onSubmitOnboarding,
      onDefer: onDeferOnboarding,
      onReturnToIntro: onReturnToIntroFromOnboarding,
    );
  }

  Widget _buildDeferredOnboardingExit({
    required double progress,
  }) {
    return IgnorePointer(
      key: const ValueKey('first_launch_transition_defer_ignore_pointer'),
      ignoring: true,
      child: ClipPath(
        key: const ValueKey('first_launch_defer_reveal_clip'),
        clipper: _TopRightFanRevealClipper(progress: progress),
        child: KeyedSubtree(
          key: const ValueKey('first_launch_transition_defer_to_home'),
          child: _buildOnboardingOverlay(),
        ),
      ),
    );
  }
}

enum _FirstLaunchSurfaceMotion {
  stationary,
  hidden,
  flipOutToLeft,
  flipInFromRight,
  flipOutToRight,
  flipInFromLeft,
  pushUp,
}

class _FirstLaunchTransitionSurface extends StatelessWidget {
  const _FirstLaunchTransitionSurface({
    super.key,
    required this.mode,
    required this.progress,
    required this.child,
    this.motionKey,
  });

  final _FirstLaunchSurfaceMotion mode;
  final double progress;
  final Widget child;
  final Key? motionKey;

  @override
  Widget build(BuildContext context) {
    final curvedProgress = Curves.easeInOutCubic.transform(progress);
    final wrappedChild = child;
    final translationY = switch (mode) {
      _FirstLaunchSurfaceMotion.pushUp =>
        -MediaQuery.sizeOf(context).height * curvedProgress,
      _ => 0.0,
    };
    final angle = switch (mode) {
      _FirstLaunchSurfaceMotion.flipOutToLeft =>
        -math.pi * 0.5 * curvedProgress,
      _FirstLaunchSurfaceMotion.flipOutToRight =>
        math.pi * 0.5 * curvedProgress,
      _FirstLaunchSurfaceMotion.flipInFromRight =>
        math.pi * 0.5 * (1 - curvedProgress),
      _FirstLaunchSurfaceMotion.flipInFromLeft =>
        -math.pi * 0.5 * (1 - curvedProgress),
      _ => 0.0,
    };
    final alignment = switch (mode) {
      _FirstLaunchSurfaceMotion.flipOutToLeft => Alignment.centerRight,
      _FirstLaunchSurfaceMotion.flipInFromLeft => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    final shadowOpacity = switch (mode) {
      _FirstLaunchSurfaceMotion.flipOutToLeft => 0.14 * curvedProgress,
      _FirstLaunchSurfaceMotion.flipOutToRight => 0.14 * curvedProgress,
      _FirstLaunchSurfaceMotion.flipInFromRight => 0.18 * (1 - curvedProgress),
      _FirstLaunchSurfaceMotion.flipInFromLeft => 0.18 * (1 - curvedProgress),
      _ => 0.0,
    };
    final opacity = switch (mode) {
      _FirstLaunchSurfaceMotion.pushUp => 1 - (0.08 * curvedProgress),
      _ => 1.0,
    };
    final childVisible = mode != _FirstLaunchSurfaceMotion.hidden;
    final matrix = Matrix4.identity();
    if (translationY != 0) {
      matrix.setTranslationRaw(0, translationY, 0);
    }
    if (angle != 0) {
      matrix.setEntry(3, 2, 0.0014);
      matrix.rotateY(angle);
    }

    return Positioned.fill(
      child: Transform(
        key: motionKey,
        alignment: alignment,
        transform: matrix,
        child: IgnorePointer(
          ignoring: mode != _FirstLaunchSurfaceMotion.stationary,
          child: Opacity(
            opacity: opacity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Visibility(
                  visible: childVisible,
                  maintainState: true,
                  maintainAnimation: true,
                  child: wrappedChild,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: shadowOpacity),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRightFanRevealClipper extends CustomClipper<Path> {
  const _TopRightFanRevealClipper({
    required this.progress,
  });

  final double progress;

  @override
  Path getClip(Size size) {
    final curvedProgress = Curves.easeOutCubic.transform(progress);
    final radius = math.max(size.width, size.height) * 1.6 * curvedProgress;
    final origin = Offset(size.width, 0);
    final sectorRect = Rect.fromCircle(center: origin, radius: radius);

    final clipPath = Path()..addRect(Offset.zero & size);
    final revealPath = Path()
      ..moveTo(origin.dx, origin.dy)
      ..arcTo(sectorRect, math.pi * 0.5, math.pi * 0.5, false)
      ..close();

    clipPath.fillType = PathFillType.evenOdd;
    clipPath.addPath(revealPath, Offset.zero);
    return clipPath;
  }

  @override
  bool shouldReclip(covariant _TopRightFanRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

class _PetCareBottomNav extends StatelessWidget {
  const _PetCareBottomNav({
    super.key,
    required this.store,
    required this.onAdd,
    this.interactive = true,
    this.enableBlur = true,
  });

  final PetCareStore store;
  final VoidCallback onAdd;
  final bool interactive;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final insets = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(insets);
        final tokens = context.petCareTokens;
        final activeTab = store.activeTab;

        final dockPanel = Container(
          key: const ValueKey('bottom_nav_panel'),
          height: dockLayout.panelHeight,
          padding: dockLayout.innerPadding,
          decoration: BoxDecoration(
            color: tokens.navBackground,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: tokens.navBorder,
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.panelShadow,
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _TabButton(
                key: const ValueKey('tab_checklist'),
                accent: tabAccentFor(context, AppTab.checklist),
                icon: Icons.checklist_rounded,
                label: '清单',
                selected: activeTab == AppTab.checklist,
                onTap: interactive ? () => store.setActiveTab(AppTab.checklist) : null,
              ),
              _TabButton(
                key: const ValueKey('tab_overview'),
                accent: tabAccentFor(context, AppTab.overview),
                icon: Icons.auto_awesome_rounded,
                label: '总览',
                selected: activeTab == AppTab.overview,
                onTap: interactive ? () => store.setActiveTab(AppTab.overview) : null,
              ),
              SizedBox(
                width: 56,
                child: Center(
                  child: SizedBox(
                    key: const ValueKey('dock_add_button'),
                    width: 48,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tokens.navAddGradientStart,
                            tokens.navAddGradientEnd,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tokens.navAddShadow,
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xAAFFFFFF),
                          width: 1.4,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: interactive ? onAdd : null,
                          child: const Center(
                            child: Icon(
                              Icons.add,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _TabButton(
                key: const ValueKey('tab_pets'),
                accent: tabAccentFor(context, AppTab.pets),
                icon: Icons.pets_rounded,
                label: '爱宠',
                selected: activeTab == AppTab.pets,
                onTap: interactive ? () => store.setActiveTab(AppTab.pets) : null,
              ),
              _TabButton(
                key: const ValueKey('tab_me'),
                accent: tabAccentFor(context, AppTab.me),
                icon: Icons.person_rounded,
                label: '我的',
                selected: activeTab == AppTab.me,
                onTap: interactive ? () => store.setActiveTab(AppTab.me) : null,
              ),
            ],
          ),
        );

        return RepaintBoundary(
          key: const ValueKey('bottom_nav_boundary'),
          child: Padding(
            padding: dockLayout.outerMargin,
            child: SizedBox(
              height: dockLayout.shellHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: enableBlur
                    ? BackdropFilter(
                        key: const ValueKey('bottom_nav_blur'),
                        filter: ImageFilter.blur(
                          sigmaX: dockBlurSigma,
                          sigmaY: dockBlurSigma,
                        ),
                        child: dockPanel,
                      )
                    : dockPanel,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.accent,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NavigationAccent accent;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petCareTokens;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? accent.fill : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : tokens.navIconInactive,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent.label : tokens.navLabelInactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
