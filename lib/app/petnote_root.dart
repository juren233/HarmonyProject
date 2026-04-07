import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/app/add_sheet.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/ios_native_dock.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/notifications/method_channel_notification_adapter.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/app/petnote_pages.dart' hide MePage;
import 'package:petnote/app/pet_edit_sheet.dart';
import 'package:petnote/app/pet_first_launch_intro.dart';
import 'package:petnote/app/pet_onboarding_overlay.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

class PetNoteRoot extends StatefulWidget {
  const PetNoteRoot({
    super.key,
    this.settingsController,
    this.iosDockBuilder,
    this.storeLoader,
    this.notificationAdapter,
  });

  final AppSettingsController? settingsController;
  final IosDockBuilder? iosDockBuilder;
  final Future<PetNoteStore> Function()? storeLoader;
  final NotificationPlatformAdapter? notificationAdapter;

  @override
  State<PetNoteRoot> createState() => _PetNoteRootState();
}

enum _OnboardingEntryPoint { intro, manual }

enum _OverlayTransition { none, introToOnboarding, introToShell }

class _PetNoteRootState extends State<PetNoteRoot>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  PetNoteStore? _store;
  NotificationCoordinator? _notificationCoordinator;
  String _activeChecklistKey = 'today';
  String? _highlightedChecklistItemKey;
  bool _showFirstLaunchIntro = false;
  bool _showOnboarding = false;
  _OnboardingEntryPoint _onboardingEntryPoint = _OnboardingEntryPoint.manual;
  _OverlayTransition _overlayTransition = _OverlayTransition.none;
  late final AnimationController _overlayTransitionController;
  Timer? _timeRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overlayTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    _loadStore();
  }

  Future<void> _loadStore() async {
    final store = await (widget.storeLoader ?? PetNoteStore.load)();
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
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
    _startTimeRefreshTicker();
    unawaited(_initializeNotifications(store));
  }

  Future<void> _initializeNotifications(PetNoteStore store) async {
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

    final overlayStyle = petNoteOverlayStyleForTheme(Theme.of(context));
    final showBottomNavigation = !_showOnboarding &&
        (!_showFirstLaunchIntro ||
            _overlayTransition == _OverlayTransition.introToShell);
    final showBottomNavigationInBody =
        _overlayTransition == _OverlayTransition.introToShell;
    final useNativeIosDock = showBottomNavigation &&
        supportsIosNativeDock(Theme.of(context).platform);
    final bottomNavigation = !showBottomNavigation
        ? null
        : useNativeIosDock
            ? _buildIosNativeDock(context, store)
            : _PetNoteBottomNav(
                store: store,
                onAdd: () => _openAddSheet(context, store),
              );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBody: true,
        body: _PetNoteBody(
          store: store,
          activeChecklistKey: _activeChecklistKey,
          showFirstLaunchIntro: _showFirstLaunchIntro,
          showOnboarding: _showOnboarding,
          overlayTransition: _overlayTransition,
          overlayTransitionProgress: _overlayTransitionController.value,
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
          bottomNavigationOverlay:
              showBottomNavigationInBody ? bottomNavigation : null,
        ),
        bottomNavigationBar:
            showBottomNavigationInBody ? null : bottomNavigation,
      ),
    );
  }

  Widget _buildIosNativeDock(BuildContext context, PetNoteStore store) {
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

  Future<void> _openAddSheet(BuildContext context, PetNoteStore store) async {
    final tokens = context.petNoteTokens;
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
  }

  Future<void> _openEditPetSheet(
    BuildContext context,
    PetNoteStore store,
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
    _resetOverlayTransition();
    setState(() {
      _showFirstLaunchIntro = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _showOnboarding = true;
    });
  }

  Future<void> _openOnboardingFromIntro() async {
    final store = _store;
    if (store == null) {
      return;
    }

    await store.dismissFirstLaunchIntro();
    if (!mounted) {
      return;
    }

    setState(() {
      _showFirstLaunchIntro = true;
      _onboardingEntryPoint = _OnboardingEntryPoint.intro;
      _showOnboarding = true;
      _overlayTransition = _OverlayTransition.introToOnboarding;
    });
    await _overlayTransitionController.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _showFirstLaunchIntro = false;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
  }

  Future<void> _dismissFirstLaunchIntro() async {
    final store = _store;
    if (store == null) {
      return;
    }

    await store.dismissFirstLaunchIntro();
    if (!mounted) {
      return;
    }
    store.setActiveTab(AppTab.checklist);
    setState(() {
      _showFirstLaunchIntro = true;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _overlayTransition = _OverlayTransition.introToShell;
    });
    await _overlayTransitionController.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _showFirstLaunchIntro = false;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
  }

  void _returnToIntroFromOnboarding() {
    _resetOverlayTransition();
    setState(() {
      _showOnboarding = false;
      _showFirstLaunchIntro = true;
      _onboardingEntryPoint = _OnboardingEntryPoint.intro;
    });
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
    setState(() {
      _showFirstLaunchIntro = false;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
  }

  Future<void> _deferOnboarding() async {
    _resetOverlayTransition();
    setState(() {
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
    });
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

  Future<void> _consumeForegroundNotificationTap(PetNoteStore store) async {
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
    PetNoteStore store,
    NotificationLaunchIntent intent,
  ) {
    final sectionKey = _sectionKeyForPayload(store, intent.payload);
    setState(() {
      _showFirstLaunchIntro = false;
      _showOnboarding = false;
      _activeChecklistKey = sectionKey;
      _highlightedChecklistItemKey = intent.payload.key;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
    store.setActiveTab(AppTab.checklist);
  }

  String _sectionKeyForPayload(
    PetNoteStore store,
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
    _overlayTransitionController.dispose();
    super.dispose();
  }

  void _resetOverlayTransition() {
    if (_overlayTransitionController.isAnimating) {
      _overlayTransitionController.stop();
    }
    if (_overlayTransitionController.value != 0) {
      _overlayTransitionController.value = 0;
    }
    _overlayTransition = _OverlayTransition.none;
  }
}

class _PetNoteBody extends StatelessWidget {
  const _PetNoteBody({
    required this.store,
    required this.activeChecklistKey,
    required this.showFirstLaunchIntro,
    required this.showOnboarding,
    required this.overlayTransition,
    required this.overlayTransitionProgress,
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
    this.bottomNavigationOverlay,
  });

  final PetNoteStore store;
  final String activeChecklistKey;
  final bool showFirstLaunchIntro;
  final bool showOnboarding;
  final _OverlayTransition overlayTransition;
  final double overlayTransitionProgress;
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
  final Widget? bottomNavigationOverlay;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final activeTab = store.activeTab;
        final notificationCoordinator = this.notificationCoordinator;
        final introToOnboarding =
            overlayTransition == _OverlayTransition.introToOnboarding;
        final introToShell =
            overlayTransition == _OverlayTransition.introToShell;
        final introShellExitProgress = introToShell
            ? Curves.easeOutQuart
                .transform((overlayTransitionProgress / 0.34).clamp(0.0, 1.0))
            : 0.0;
        final introShellExitOffset =
            introToShell ? -introShellExitProgress * 260 : 0.0;
        final introOpacity = introToShell ? 1 - introShellExitProgress : 1.0;
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
                                  await notificationCoordinator
                                      .openNotificationSettings();
                                },
                    ),
                },
              ),
              if (bottomNavigationOverlay != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: true,
                    child: bottomNavigationOverlay!,
                  ),
                ),
              Positioned.fill(
                key: const ValueKey('onboarding_overlay_layer'),
                child: showOnboarding
                    ? IgnorePointer(
                        ignoring: introToOnboarding &&
                            overlayTransitionProgress < 0.96,
                        child: PetOnboardingOverlay(
                          animateInitialEntry: !introToOnboarding,
                          externalRevealProgress: introToOnboarding
                              ? overlayTransitionProgress
                              : null,
                          onSubmit: onSubmitOnboarding,
                          onDefer: onDeferOnboarding,
                          onReturnToIntro: onReturnToIntroFromOnboarding,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned.fill(
                key: const ValueKey('intro_overlay_layer'),
                child: showFirstLaunchIntro
                    ? IgnorePointer(
                        ignoring: overlayTransition != _OverlayTransition.none,
                        child: Opacity(
                          key: const ValueKey('intro_shell_exit_opacity'),
                          opacity: introOpacity,
                          child: SizedBox.expand(
                            key: const ValueKey('intro_shell_exit_motion'),
                            child: Transform.translate(
                              offset: Offset(0, introShellExitOffset),
                              child: PetFirstLaunchIntro(
                                fillParent: false,
                                onboardingExitProgress: introToOnboarding
                                    ? overlayTransitionProgress
                                    : 0,
                                onStartOnboarding: onStartOnboardingFromIntro,
                                onExploreFirst: onExploreFirstLaunchIntro,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PetNoteBottomNav extends StatelessWidget {
  const _PetNoteBottomNav({
    required this.store,
    required this.onAdd,
  });

  final PetNoteStore store;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final insets = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(insets);
        final tokens = context.petNoteTokens;
        final activeTab = store.activeTab;

        return RepaintBoundary(
          key: const ValueKey('bottom_nav_boundary'),
          child: Padding(
            padding: dockLayout.outerMargin,
            child: SizedBox(
              height: dockLayout.shellHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  key: const ValueKey('bottom_nav_blur'),
                  filter: ImageFilter.blur(
                    sigmaX: dockBlurSigma,
                    sigmaY: dockBlurSigma,
                  ),
                  child: Container(
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
                          onTap: () => store.setActiveTab(AppTab.checklist),
                        ),
                        _TabButton(
                          key: const ValueKey('tab_overview'),
                          accent: tabAccentFor(context, AppTab.overview),
                          icon: Icons.auto_awesome_rounded,
                          label: '总览',
                          selected: activeTab == AppTab.overview,
                          onTap: () => store.setActiveTab(AppTab.overview),
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
                                    onTap: onAdd,
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
                          onTap: () => store.setActiveTab(AppTab.pets),
                        ),
                        _TabButton(
                          key: const ValueKey('tab_me'),
                          accent: tabAccentFor(context, AppTab.me),
                          icon: Icons.person_rounded,
                          label: '我的',
                          selected: activeTab == AppTab.me,
                          onTap: () => store.setActiveTab(AppTab.me),
                        ),
                      ],
                    ),
                  ),
                ),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
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
