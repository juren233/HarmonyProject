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

class _PetCareRootState extends State<PetCareRoot> {
  PetCareStore? _store;
  String _activeChecklistKey = 'today';
  bool _showOnboarding = false;

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
      _showOnboarding =
          store.pets.isEmpty && store.shouldAutoShowFirstLaunchOnboarding;
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

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final insets = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(insets);
        final overlayStyle = petCareOverlayStyleForTheme(Theme.of(context));
        final tokens = context.petCareTokens;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Scaffold(
            extendBody: true,
            body: RepaintBoundary(
              key: const ValueKey('page_content_boundary'),
              child: Stack(
                children: [
                  HyperPageBackground(
                    // keep lazy tab construction via switch (_store.activeTab)
                    child: switch (store.activeTab) {
                      AppTab.checklist => ChecklistPage(
                          store: store,
                          activeSectionKey: _activeChecklistKey,
                          onSectionChanged: (value) =>
                              setState(() => _activeChecklistKey = value),
                          onAddFirstPet: _openManualOnboarding,
                        ),
                      AppTab.overview => OverviewPage(
                          store: store,
                          onAddFirstPet: _openManualOnboarding,
                        ),
                      AppTab.pets => PetsPage(
                          store: store,
                          onAddFirstPet: _openManualOnboarding,
                          onEditPet: (pet) =>
                              _openEditPetSheet(context, store, pet),
                        ),
                      AppTab.me => MePage(
                          themePreference:
                              widget.settingsController?.themePreference ??
                                  AppThemePreference.system,
                          onThemePreferenceChanged: (value) => widget
                              .settingsController
                              ?.setThemePreference(value),
                        ),
                    },
                  ),
                  if (_showOnboarding)
                    PetOnboardingOverlay(
                      onSubmit: _submitOnboarding,
                    ),
                ],
              ),
            ),
            bottomNavigationBar: _showOnboarding
                ? null
                : RepaintBoundary(
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
                                    accent:
                                        tabAccentFor(context, AppTab.checklist),
                                    icon: Icons.checklist_rounded,
                                    label: '清单',
                                    selected:
                                        store.activeTab == AppTab.checklist,
                                    onTap: () =>
                                        store.setActiveTab(AppTab.checklist),
                                  ),
                                  _TabButton(
                                    key: const ValueKey('tab_overview'),
                                    accent:
                                        tabAccentFor(context, AppTab.overview),
                                    icon: Icons.auto_awesome_rounded,
                                    label: '总览',
                                    selected:
                                        store.activeTab == AppTab.overview,
                                    onTap: () =>
                                        store.setActiveTab(AppTab.overview),
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
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap: () =>
                                                  _openAddSheet(context, store),
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
                                    selected: store.activeTab == AppTab.pets,
                                    onTap: () =>
                                        store.setActiveTab(AppTab.pets),
                                  ),
                                  _TabButton(
                                    key: const ValueKey('tab_me'),
                                    accent: tabAccentFor(context, AppTab.me),
                                    icon: Icons.person_rounded,
                                    label: '我的',
                                    selected: store.activeTab == AppTab.me,
                                    onTap: () => store.setActiveTab(AppTab.me),
                                  ),
                                ],
                              ),
                            ),
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

  Future<void> _openAddSheet(BuildContext context, PetCareStore store) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
      _showOnboarding = true;
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
      _showOnboarding = false;
    });
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
