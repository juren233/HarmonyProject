import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_care_harmony/app/add_sheet.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';
import 'package:pet_care_harmony/app/me_page.dart';
import 'package:pet_care_harmony/app/navigation_palette.dart';
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
  });

  final AppSettingsController? settingsController;

  @override
  State<PetCareRoot> createState() => _PetCareRootState();
}

enum _OnboardingEntryPoint { intro, manual }

class _PetCareRootState extends State<PetCareRoot> {
  PetCareStore? _store;
  String _activeChecklistKey = 'today';
  bool _showFirstLaunchIntro = false;
  bool _showOnboarding = false;
  _OnboardingEntryPoint _onboardingEntryPoint = _OnboardingEntryPoint.manual;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    final store = await PetCareStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _store = store;
      _showFirstLaunchIntro =
          store.pets.isEmpty && store.shouldAutoShowFirstLaunchIntro;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
    });
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
          onSectionChanged: (value) =>
              setState(() => _activeChecklistKey = value),
          onAddFirstPet: _openManualOnboarding,
          onStartOnboardingFromIntro: _openOnboardingFromIntro,
          onExploreFirstLaunchIntro: _dismissFirstLaunchIntro,
          onEditPet: (pet) => _openEditPetSheet(context, store, pet),
          onSubmitOnboarding: _submitOnboarding,
          onDeferOnboarding: _deferOnboarding,
        ),
        bottomNavigationBar: _showFirstLaunchIntro || _showOnboarding
            ? null
            : _PetCareBottomNav(
                store: store,
                onAdd: () => _openAddSheet(context, store),
              ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context, PetCareStore store) async {
    final tokens = context.petCareTokens;
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
      _showFirstLaunchIntro = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.intro;
      _showOnboarding = true;
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
    setState(() {
      _showFirstLaunchIntro = false;
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
    });
  }

  void _openAddPetOnboardingFromSheet() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _openManualOnboarding();
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
    });
  }

  Future<void> _deferOnboarding() async {
    setState(() {
      _showOnboarding = false;
      _onboardingEntryPoint = _OnboardingEntryPoint.manual;
    });
  }
}

class _PetCareBody extends StatelessWidget {
  const _PetCareBody({
    required this.store,
    required this.activeChecklistKey,
    required this.showFirstLaunchIntro,
    required this.showOnboarding,
    required this.settingsController,
    required this.onSectionChanged,
    required this.onAddFirstPet,
    required this.onStartOnboardingFromIntro,
    required this.onExploreFirstLaunchIntro,
    required this.onEditPet,
    required this.onSubmitOnboarding,
    required this.onDeferOnboarding,
  });

  final PetCareStore store;
  final String activeChecklistKey;
  final bool showFirstLaunchIntro;
  final bool showOnboarding;
  final AppSettingsController? settingsController;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onAddFirstPet;
  final Future<void> Function() onStartOnboardingFromIntro;
  final Future<void> Function() onExploreFirstLaunchIntro;
  final ValueChanged<Pet> onEditPet;
  final Future<void> Function(PetOnboardingResult result) onSubmitOnboarding;
  final Future<void> Function() onDeferOnboarding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final activeTab = store.activeTab;
        return RepaintBoundary(
          key: const ValueKey('page_content_boundary'),
          child: Stack(
            children: [
              HyperPageBackground(
                child: switch (activeTab) {
                  AppTab.checklist => ChecklistPage(
                      store: store,
                      activeSectionKey: activeChecklistKey,
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
                    ),
                },
              ),
              if (showFirstLaunchIntro)
                PetFirstLaunchIntro(
                  onStartOnboarding: onStartOnboardingFromIntro,
                  onExploreFirst: onExploreFirstLaunchIntro,
                ),
              if (showOnboarding)
                PetOnboardingOverlay(
                  onSubmit: onSubmitOnboarding,
                  onDefer: onDeferOnboarding,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PetCareBottomNav extends StatelessWidget {
  const _PetCareBottomNav({
    required this.store,
    required this.onAdd,
  });

  final PetCareStore store;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final insets = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(insets);
        final tokens = context.petCareTokens;
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
