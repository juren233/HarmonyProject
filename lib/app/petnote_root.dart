import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/add_sheet.dart';
import 'package:petnote/app/android_native_dock.dart';
import 'package:petnote/app/ai_settings_page.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/ios_native_dock.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/app/overview_bottom_cta.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/logging/app_log_controller.dart';
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
    this.aiSettingsCoordinator,
    this.aiInsightsService,
    this.appLogController,
    this.iosDockBuilder,
    this.storeLoader,
    this.notificationAdapter,
    this.nativePetPhotoPicker,
  });

  final AppSettingsController? settingsController;
  final AiSettingsCoordinator? aiSettingsCoordinator;
  final AiInsightsService? aiInsightsService;
  final AppLogController? appLogController;
  final IosDockBuilder? iosDockBuilder;
  final Future<PetNoteStore> Function()? storeLoader;
  final NotificationPlatformAdapter? notificationAdapter;
  final NativePetPhotoPicker? nativePetPhotoPicker;

  @override
  State<PetNoteRoot> createState() => _PetNoteRootState();
}

enum _OnboardingEntryPoint { intro, manual }

enum _OverlayTransition { none, introToOnboarding, introToShell }

class _PetNoteRootState extends State<PetNoteRoot>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  PetNoteStore? _store;
  NotificationCoordinator? _notificationCoordinator;
  DataStorageCoordinator? _dataStorageCoordinator;
  String _activeChecklistKey = 'today';
  String? _highlightedChecklistItemKey;
  bool _showFirstLaunchIntro = false;
  bool _showOnboarding = false;
  bool _shouldPrewarmBottomNavDuringIntro = false;
  bool _hasCompletedIntroBottomNavPrewarm = false;
  _OnboardingEntryPoint _onboardingEntryPoint = _OnboardingEntryPoint.manual;
  _OverlayTransition _overlayTransition = _OverlayTransition.none;
  late final AnimationController _overlayTransitionController;
  late final OverviewBottomCtaController _overviewBottomCtaController;
  Timer? _timeRefreshTimer;
  int? _lastNotificationSyncVersion;
  Future<void> _pendingNotificationSync = Future<void>.value();
  Future<void>? _notificationInitializationTask;
  bool _isNotificationSyncScheduled = false;

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
    _overviewBottomCtaController = OverviewBottomCtaController();
    _loadStore();
  }

  @override
  void didUpdateWidget(covariant PetNoteRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final store = _store;
    if (store == null) {
      return;
    }
    if (!identical(oldWidget.settingsController, widget.settingsController)) {
      _dataStorageCoordinator = widget.settingsController == null
          ? null
          : DataStorageCoordinator(
              store: store,
              settingsController: widget.settingsController!,
              appLogController: widget.appLogController,
            );
    }
  }

  Future<void> _loadStore() async {
    final store = await (widget.storeLoader ?? PetNoteStore.load)();
    if (!mounted) {
      return;
    }
    final oldStore = _store;
    oldStore?.removeListener(_handleStoreChanged);
    oldStore?.setNotificationSyncHandler(null);
    store.addListener(_handleStoreChanged);
    setState(() {
      _store = store;
      _dataStorageCoordinator = widget.settingsController == null
          ? null
          : DataStorageCoordinator(
              store: store,
              settingsController: widget.settingsController!,
              appLogController: widget.appLogController,
            );
      _notificationCoordinator = null;
      _showFirstLaunchIntro =
          store.pets.isEmpty && store.shouldAutoShowFirstLaunchIntro;
      _showOnboarding = false;
      _shouldPrewarmBottomNavDuringIntro = _showFirstLaunchIntro &&
          supportsAndroidLiquidGlassDock(defaultTargetPlatform);
      _hasCompletedIntroBottomNavPrewarm = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _overlayTransition = _OverlayTransition.none;
    });
    store.setNotificationSyncHandler(() => _flushNotificationSync(store));
    _overlayTransitionController.value = 0;
    _startTimeRefreshTicker();
    _notificationInitializationTask = _initializeNotifications(store);
    unawaited(_notificationInitializationTask!);
  }

  Future<void> _initializeNotifications(PetNoteStore store) async {
    final coordinator = NotificationCoordinator(
      adapter: widget.notificationAdapter ??
          MethodChannelNotificationPlatformAdapter(
            appLogController: widget.appLogController,
          ),
      appLogController: widget.appLogController,
    );
    await coordinator.init();
    final launchIntent = await coordinator.consumeLaunchIntent();
    if (!mounted || !identical(_store, store)) {
      coordinator.dispose();
      return;
    }
    setState(() {
      _notificationCoordinator = coordinator;
    });
    try {
      await coordinator.syncFromStore(store);
      if (mounted && identical(_store, store)) {
        _lastNotificationSyncVersion = store.notificationSyncVersion;
      }
    } catch (error, stackTrace) {
      widget.appLogController?.error(
        category: AppLogCategory.notifications,
        title: '通知初始化同步失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }
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
    final appLogController = widget.appLogController;
    if (state == AppLifecycleState.resumed) {
      appLogController?.updateCrashMonitoringHeartbeat(reason: 'resumed');
      if (mounted) {
        setState(() {});
      }
      unawaited(_handleAppResumed());
      return;
    }
    if (state == AppLifecycleState.inactive) {
      appLogController?.updateCrashMonitoringHeartbeat(reason: 'inactive');
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      appLogController?.updateCrashMonitoringHeartbeat(reason: 'paused');
      final store = _store;
      if (store != null) {
        unawaited(_flushNotificationSync(store));
      }
      return;
    }
    appLogController?.endCrashMonitoringSession(reason: 'detached');
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
    final platform = Theme.of(context).platform;
    final useAndroidDockOverlay =
        !_showOnboarding && supportsAndroidLiquidGlassDock(platform);
    final showBottomNavigation = !_showOnboarding &&
        (useAndroidDockOverlay ||
            !_showFirstLaunchIntro ||
            _overlayTransition == _OverlayTransition.introToShell);
    final showBottomNavigationInBody = useAndroidDockOverlay ||
        _overlayTransition == _OverlayTransition.introToShell;
    final useNativeAndroidDock =
        showBottomNavigation && supportsAndroidLiquidGlassDock(platform);
    final shouldPrewarmBottomNavDuringIntro = useNativeAndroidDock &&
        (_shouldPrewarmBottomNavDuringIntro ||
            (_showFirstLaunchIntro &&
                !_showOnboarding &&
                _overlayTransition == _OverlayTransition.none &&
                !_hasCompletedIntroBottomNavPrewarm));
    final shouldStartFirstLaunchIntroAnimation =
        !useNativeAndroidDock || _hasCompletedIntroBottomNavPrewarm;
    final useNativeIosDock =
        showBottomNavigation && supportsIosNativeDock(platform);
    final dockNavigation = !showBottomNavigation
        ? null
        : useNativeAndroidDock
            ? _buildAndroidNativeDock(
                context,
                store,
                shouldPrewarmBottomNavDuringIntro,
              )
            : useNativeIosDock
                ? _buildIosNativeDock(context, store)
                : _PetNoteBottomNav(
                    store: store,
                    onAdd: () => _openAddSheet(context, store),
                  );
    final bottomNavigation = dockNavigation == null
        ? null
        : _ShellBottomChrome(
            store: store,
            controller: _overviewBottomCtaController,
            dock: dockNavigation,
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
          aiSettingsCoordinator: widget.aiSettingsCoordinator,
          aiInsightsService: widget.aiInsightsService,
          appLogController: widget.appLogController,
          notificationCoordinator: _notificationCoordinator,
          highlightedChecklistItemKey: _highlightedChecklistItemKey,
          dataStorageCoordinator: _dataStorageCoordinator,
          onSectionChanged: (value) =>
              setState(() => _activeChecklistKey = value),
          onAddFirstPet: _openManualOnboarding,
          onStartOnboardingFromIntro: _openOnboardingFromIntro,
          onExploreFirstLaunchIntro: _dismissFirstLaunchIntro,
          shouldStartFirstLaunchIntroAnimation:
              shouldStartFirstLaunchIntroAnimation,
          onEditPet: (pet) => _openEditPetSheet(context, store, pet),
          onSubmitOnboarding: _submitOnboarding,
          onDeferOnboarding: _deferOnboarding,
          onReturnToIntroFromOnboarding:
              _onboardingEntryPoint == _OnboardingEntryPoint.intro
                  ? _returnToIntroFromOnboarding
                  : null,
          nativePetPhotoPicker: widget.nativePetPhotoPicker,
          overviewBottomCtaController: _overviewBottomCtaController,
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

  Widget _buildAndroidNativeDock(
    BuildContext context,
    PetNoteStore store,
    bool shouldPrewarmBottomNavDuringIntro,
  ) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return AndroidLiquidGlassDockHost(
          selectedTab: store.activeTab,
          onTabSelected: store.setActiveTab,
          onAddTap: () => _openAddSheet(context, store),
          onFirstInteractionPrewarmed: _handleIntroBottomNavPrewarmCompleted,
          shouldPrewarmFirstInteraction: shouldPrewarmBottomNavDuringIntro,
        );
      },
    );
  }

  Future<void> _openAddSheet(BuildContext context, PetNoteStore store) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      builder: (context) => AddActionSheet(
        store: store,
        nativePetPhotoPicker: widget.nativePetPhotoPicker,
      ),
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
      builder: (context) => PetEditSheet(
        store: store,
        pet: pet,
        nativePetPhotoPicker: widget.nativePetPhotoPicker,
      ),
    );
  }

  void _openManualOnboarding() {
    _resetOverlayTransition();
    setState(() {
      _showFirstLaunchIntro = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _shouldPrewarmBottomNavDuringIntro = false;
      _hasCompletedIntroBottomNavPrewarm = false;
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
      _shouldPrewarmBottomNavDuringIntro = !_hasCompletedIntroBottomNavPrewarm;
      _showOnboarding = true;
      _overlayTransition = _OverlayTransition.introToOnboarding;
    });
    await _overlayTransitionController.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _showFirstLaunchIntro = false;
      _shouldPrewarmBottomNavDuringIntro = false;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
  }

  void _handleIntroBottomNavPrewarmCompleted() {
    if (!_showFirstLaunchIntro ||
        _showOnboarding ||
        _overlayTransition != _OverlayTransition.none ||
        _hasCompletedIntroBottomNavPrewarm) {
      return;
    }
    setState(() {
      _shouldPrewarmBottomNavDuringIntro = false;
      _hasCompletedIntroBottomNavPrewarm = true;
    });
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
      _shouldPrewarmBottomNavDuringIntro = !_hasCompletedIntroBottomNavPrewarm;
      _overlayTransition = _OverlayTransition.introToShell;
    });
    await _overlayTransitionController.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _showFirstLaunchIntro = false;
      _shouldPrewarmBottomNavDuringIntro = false;
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
      _shouldPrewarmBottomNavDuringIntro = !_hasCompletedIntroBottomNavPrewarm;
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
      photoPath: result.photoPath,
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
      _shouldPrewarmBottomNavDuringIntro = false;
      _hasCompletedIntroBottomNavPrewarm = false;
      _overlayTransition = _OverlayTransition.none;
    });
    _overlayTransitionController.value = 0;
  }

  Future<void> _deferOnboarding() async {
    _resetOverlayTransition();
    setState(() {
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
      _shouldPrewarmBottomNavDuringIntro = false;
      _hasCompletedIntroBottomNavPrewarm = false;
    });
  }

  void _handleStoreChanged() {
    final store = _store;
    if (store == null) {
      return;
    }
    if (_lastNotificationSyncVersion != store.notificationSyncVersion) {
      unawaited(_flushNotificationSync(store));
    }
    unawaited(_consumeForegroundNotificationTap(store));
  }

  Future<void> _handleAppResumed() async {
    final store = _store;
    final coordinator = _notificationCoordinator;
    if (store == null || coordinator == null) {
      return;
    }
    final stateChanged = await coordinator.refreshPlatformState();
    if (!mounted ||
        !identical(store, _store) ||
        !identical(coordinator, _notificationCoordinator)) {
      return;
    }
    if (stateChanged && coordinator.hasGrantedPermission) {
      await _flushNotificationSync(store);
    }
    await _consumeForegroundNotificationTap(store);
  }

  Future<void> _flushNotificationSync(PetNoteStore store) {
    if (_isNotificationSyncScheduled) {
      return _pendingNotificationSync;
    }
    _isNotificationSyncScheduled = true;
    _pendingNotificationSync = _pendingNotificationSync
        .catchError((Object _, StackTrace __) {})
        .then((_) async {
      final initializationTask = _notificationInitializationTask;
      if (initializationTask != null) {
        await initializationTask;
      }
      while (mounted) {
        final currentStore = _store;
        final coordinator = _notificationCoordinator;
        if (!identical(currentStore, store) ||
            currentStore == null ||
            coordinator == null) {
          return;
        }
        final targetVersion = currentStore.notificationSyncVersion;
        await coordinator.syncFromStore(currentStore);
        if (_lastNotificationSyncVersion == null ||
            _lastNotificationSyncVersion! < targetVersion) {
          _lastNotificationSyncVersion = targetVersion;
        }
        if (!mounted) {
          return;
        }
        final latestStore = _store;
        if (!identical(latestStore, store) || latestStore == null) {
          return;
        }
        if (latestStore.notificationSyncVersion == targetVersion) {
          return;
        }
      }
    }).catchError((Object error, StackTrace stackTrace) {
      widget.appLogController?.error(
        category: AppLogCategory.notifications,
        title: '通知同步失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }).whenComplete(() {
      _isNotificationSyncScheduled = false;
    });
    return _pendingNotificationSync;
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
      _shouldPrewarmBottomNavDuringIntro = false;
      _hasCompletedIntroBottomNavPrewarm = false;
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
    widget.appLogController?.endCrashMonitoringSession(reason: 'dispose');
    _timeRefreshTimer?.cancel();
    _store?.removeListener(_handleStoreChanged);
    _store?.setNotificationSyncHandler(null);
    _notificationCoordinator?.dispose();
    _overviewBottomCtaController.dispose();
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

class _PetNoteBody extends StatefulWidget {
  const _PetNoteBody({
    required this.store,
    required this.activeChecklistKey,
    required this.showFirstLaunchIntro,
    required this.showOnboarding,
    required this.overlayTransition,
    required this.overlayTransitionProgress,
    required this.settingsController,
    required this.aiSettingsCoordinator,
    required this.aiInsightsService,
    required this.appLogController,
    required this.notificationCoordinator,
    required this.highlightedChecklistItemKey,
    required this.dataStorageCoordinator,
    required this.onSectionChanged,
    required this.onAddFirstPet,
    required this.onStartOnboardingFromIntro,
    required this.onExploreFirstLaunchIntro,
    required this.shouldStartFirstLaunchIntroAnimation,
    required this.onEditPet,
    required this.onSubmitOnboarding,
    required this.onDeferOnboarding,
    required this.onReturnToIntroFromOnboarding,
    this.nativePetPhotoPicker,
    required this.overviewBottomCtaController,
    this.bottomNavigationOverlay,
  });

  final PetNoteStore store;
  final String activeChecklistKey;
  final bool showFirstLaunchIntro;
  final bool showOnboarding;
  final _OverlayTransition overlayTransition;
  final double overlayTransitionProgress;
  final AppSettingsController? settingsController;
  final AiSettingsCoordinator? aiSettingsCoordinator;
  final AiInsightsService? aiInsightsService;
  final AppLogController? appLogController;
  final NotificationCoordinator? notificationCoordinator;
  final String? highlightedChecklistItemKey;
  final DataStorageCoordinator? dataStorageCoordinator;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onAddFirstPet;
  final Future<void> Function() onStartOnboardingFromIntro;
  final Future<void> Function() onExploreFirstLaunchIntro;
  final bool shouldStartFirstLaunchIntroAnimation;
  final ValueChanged<Pet> onEditPet;
  final Future<void> Function(PetOnboardingResult result) onSubmitOnboarding;
  final Future<void> Function() onDeferOnboarding;
  final VoidCallback? onReturnToIntroFromOnboarding;
  final NativePetPhotoPicker? nativePetPhotoPicker;
  final OverviewBottomCtaController overviewBottomCtaController;
  final Widget? bottomNavigationOverlay;

  @override
  State<_PetNoteBody> createState() => _PetNoteBodyState();
}

class _PetNoteBodyState extends State<_PetNoteBody> {
  static const List<AppTab> _tabOrder = <AppTab>[
    AppTab.checklist,
    AppTab.overview,
    AppTab.pets,
    AppTab.me,
  ];

  final Set<AppTab> _visitedTabs = <AppTab>{};
  late AppTab _activeTab;
  bool _hasScheduledTabPrewarm = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.store.activeTab;
    _visitedTabs.add(_activeTab);
    widget.store.addListener(_handleStoreChanged);
    _queueDeferredTabPrewarm();
  }

  @override
  void didUpdateWidget(covariant _PetNoteBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
    _activeTab = widget.store.activeTab;
    _visitedTabs.add(_activeTab);
    _queueDeferredTabPrewarm();
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    final activeTab = widget.store.activeTab;
    if (_activeTab == activeTab) {
      return;
    }
    setState(() {
      _activeTab = activeTab;
      _visitedTabs.add(activeTab);
    });
    _queueDeferredTabPrewarm();
  }

  bool get _canPrewarmTabs {
    return !widget.showFirstLaunchIntro &&
        !widget.showOnboarding &&
        widget.overlayTransition == _OverlayTransition.none;
  }

  void _queueDeferredTabPrewarm() {
    if (_hasScheduledTabPrewarm || !_canPrewarmTabs) {
      return;
    }
    _hasScheduledTabPrewarm = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prewarmPersistentTabs());
    });
  }

  Future<void> _prewarmPersistentTabs() async {
    for (final tab in _deferredPrewarmTabs(_activeTab)) {
      await Future<void>.delayed(const Duration(milliseconds: 48));
      if (!mounted) {
        return;
      }
      if (!_canPrewarmTabs) {
        _hasScheduledTabPrewarm = false;
        _queueDeferredTabPrewarm();
        return;
      }
      if (_visitedTabs.contains(tab)) {
        continue;
      }
      setState(() {
        _visitedTabs.add(tab);
      });
    }
  }

  Iterable<AppTab> _deferredPrewarmTabs(AppTab activeTab) sync* {
    for (final tab in const <AppTab>[
      AppTab.overview,
      AppTab.pets,
      AppTab.me,
      AppTab.checklist,
    ]) {
      if (tab != activeTab) {
        yield tab;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final introToOnboarding =
        widget.overlayTransition == _OverlayTransition.introToOnboarding;
    final introToShell =
        widget.overlayTransition == _OverlayTransition.introToShell;
    final introShellExitProgress = introToShell
        ? Curves.easeOutQuart.transform(
            (widget.overlayTransitionProgress / 0.34).clamp(0.0, 1.0))
        : 0.0;
    final introShellExitOffset =
        introToShell ? -introShellExitProgress * 260 : 0.0;
    final introOpacity = introToShell ? 1 - introShellExitProgress : 1.0;
    final shouldIgnoreBottomNavigation = widget.showOnboarding ||
        (widget.showFirstLaunchIntro && (!introToShell || introOpacity > 0.05));
    return RepaintBoundary(
      key: const ValueKey('page_content_boundary'),
      child: Stack(
        children: [
          HyperPageBackground(
            child: IndexedStack(
              index: _tabOrder.indexOf(activeTab),
              children: _tabOrder
                  .map(
                    (tab) => _buildPersistentTabPage(
                      context,
                      tab,
                      isActive: tab == activeTab,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          if (widget.bottomNavigationOverlay != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: shouldIgnoreBottomNavigation,
                child: widget.bottomNavigationOverlay!,
              ),
            ),
          Positioned.fill(
            key: const ValueKey('onboarding_overlay_layer'),
            child: widget.showOnboarding
                ? IgnorePointer(
                    ignoring: introToOnboarding &&
                        widget.overlayTransitionProgress < 0.96,
                    child: PetOnboardingOverlay(
                      animateInitialEntry: !introToOnboarding,
                      externalRevealProgress: introToOnboarding
                          ? widget.overlayTransitionProgress
                          : null,
                      nativePetPhotoPicker: widget.nativePetPhotoPicker,
                      onSubmit: widget.onSubmitOnboarding,
                      onDefer: widget.onDeferOnboarding,
                      onReturnToIntro: widget.onReturnToIntroFromOnboarding,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned.fill(
            key: const ValueKey('intro_overlay_layer'),
            child: widget.showFirstLaunchIntro
                ? IgnorePointer(
                    ignoring:
                        widget.overlayTransition != _OverlayTransition.none,
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
                                ? widget.overlayTransitionProgress
                                : 0,
                            shouldStartLaunchAnimation:
                                widget.shouldStartFirstLaunchIntroAnimation,
                            onStartOnboarding:
                                widget.onStartOnboardingFromIntro,
                            onExploreFirst: widget.onExploreFirstLaunchIntro,
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
  }

  Widget _buildPersistentTabPage(
    BuildContext context,
    AppTab tab, {
    required bool isActive,
  }) {
    if (!_visitedTabs.contains(tab)) {
      return const SizedBox.shrink();
    }
    return TickerMode(
      enabled: isActive,
      child: KeyedSubtree(
        key: ValueKey<String>('persistent_tab_${tab.name}'),
        child: switch (tab) {
          AppTab.checklist => _StoreDrivenPageHost(
              store: widget.store,
              isActive: isActive,
              builder: (context) => ChecklistPage(
                store: widget.store,
                activeSectionKey: widget.activeChecklistKey,
                highlightedChecklistItemKey: widget.highlightedChecklistItemKey,
                onSectionChanged: widget.onSectionChanged,
                onAddFirstPet: widget.onAddFirstPet,
              ),
            ),
          AppTab.overview => _StoreDrivenPageHost(
              store: widget.store,
              isActive: isActive,
              builder: (context) => OverviewPage(
                store: widget.store,
                onAddFirstPet: widget.onAddFirstPet,
                bottomCtaController: widget.overviewBottomCtaController,
                onOpenAiSettings: widget.settingsController == null ||
                        widget.aiSettingsCoordinator == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => AiSettingsPage(
                              settingsController: widget.settingsController!,
                              coordinator: widget.aiSettingsCoordinator!,
                            ),
                          ),
                        ),
                aiInsightsService: widget.aiInsightsService,
              ),
            ),
          AppTab.pets => _StoreDrivenPageHost(
              store: widget.store,
              isActive: isActive,
              builder: (context) => PetsPage(
                store: widget.store,
                onAddFirstPet: widget.onAddFirstPet,
                onEditPet: widget.onEditPet,
                aiInsightsService: widget.aiInsightsService,
              ),
            ),
          AppTab.me => _StoreDrivenPageHost(
              store: widget.store,
              isActive: isActive,
              builder: (context) => MePage(
                themePreference: widget.settingsController?.themePreference ??
                    AppThemePreference.system,
                onThemePreferenceChanged: (value) =>
                    widget.settingsController?.setThemePreference(value),
                settingsController: widget.settingsController,
                appLogController: widget.appLogController,
                aiSettingsCoordinator: widget.aiSettingsCoordinator,
                dataStorageCoordinator: widget.dataStorageCoordinator,
                notificationPermissionState:
                    widget.notificationCoordinator?.permissionState ??
                        NotificationPermissionState.unknown,
                notificationCapabilities:
                    widget.notificationCoordinator?.capabilities ??
                        const NotificationPlatformCapabilities(),
                notificationPushToken:
                    widget.notificationCoordinator?.pushToken,
                onRequestNotificationPermission:
                    widget.notificationCoordinator == null
                        ? null
                        : () async {
                            await widget.notificationCoordinator!
                                .requestPermission();
                          },
                onOpenNotificationSettings:
                    widget.notificationCoordinator == null
                        ? null
                        : () async {
                            await widget.notificationCoordinator!
                                .openNotificationSettings();
                          },
                onOpenExactAlarmSettings: widget.notificationCoordinator == null
                    ? null
                    : () async {
                        await widget.notificationCoordinator!
                            .openExactAlarmSettings();
                      },
              ),
            ),
        },
      ),
    );
  }
}

class _StoreDrivenPageHost extends StatefulWidget {
  const _StoreDrivenPageHost({
    required this.store,
    required this.isActive,
    required this.builder,
  });

  final PetNoteStore store;
  final bool isActive;
  final WidgetBuilder builder;

  @override
  State<_StoreDrivenPageHost> createState() => _StoreDrivenPageHostState();
}

class _StoreDrivenPageHostState extends State<_StoreDrivenPageHost> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant _StoreDrivenPageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
    if (!oldWidget.isActive && widget.isActive) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!widget.isActive || !mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
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
                          width: 60,
                          child: Center(
                            child: SizedBox(
                              key: const ValueKey('dock_add_button'),
                              width: 52,
                              height: 52,
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
                                        size: 26,
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

class _ShellBottomChrome extends StatelessWidget {
  const _ShellBottomChrome({
    required this.store,
    required this.controller,
    required this.dock,
  });

  final PetNoteStore store;
  final OverviewBottomCtaController controller;
  final Widget dock;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, controller]),
      builder: (context, _) {
        final ctaState = overviewBottomCtaFallbackState(
          store: store,
          activeTab: store.activeTab,
          syncedState: controller.value,
        );
        final hasVisibleCta = ctaState?.visible ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasVisibleCta)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  overviewBottomCtaHorizontalMargin,
                  0,
                  overviewBottomCtaHorizontalMargin,
                  overviewBottomCtaDockGap,
                ),
                child: OverviewBottomCtaBar(state: ctaState!),
              ),
            dock,
          ],
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? accent.fill : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? Colors.white : tokens.navIconInactive,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
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


