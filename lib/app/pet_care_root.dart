import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/add_sheet.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';
import 'package:pet_care_harmony/app/navigation_palette.dart';
import 'package:pet_care_harmony/app/pet_care_pages.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class PetCareRoot extends StatefulWidget {
  const PetCareRoot({super.key});

  @override
  State<PetCareRoot> createState() => _PetCareRootState();
}

class _PetCareRootState extends State<PetCareRoot> {
  late final PetCareStore _store;
  String _activeChecklistKey = 'today';

  @override
  void initState() {
    super.initState();
    _store = PetCareStore.seeded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final insets = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(insets);
        return Scaffold(
          extendBody: true,
          body: HyperPageBackground(
            child: switch (_store.activeTab) {
              AppTab.checklist => ChecklistPage(
                  store: _store,
                  activeSectionKey: _activeChecklistKey,
                  onSectionChanged: (value) => setState(() => _activeChecklistKey = value),
                ),
              AppTab.overview => OverviewPage(store: _store),
              AppTab.pets => PetsPage(store: _store),
              AppTab.me => const MePage(),
            },
          ),
          bottomNavigationBar: Padding(
            padding: dockLayout.outerMargin,
            child: SizedBox(
              height: dockLayout.shellHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    key: const ValueKey('bottom_nav_blur'),
                    filter: ImageFilter.blur(sigmaX: dockBlurSigma, sigmaY: dockBlurSigma),
                    child: Container(
                    key: const ValueKey('bottom_nav_panel'),
                    height: dockLayout.panelHeight,
                    padding: dockLayout.innerPadding,
                    decoration: BoxDecoration(
                      color: const Color(0xCCFFFFFF),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xD9FFFFFF), width: 1.1),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 26,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _TabButton(
                          accent: tabAccentFor(AppTab.checklist),
                          icon: Icons.checklist_rounded,
                          label: '清单',
                          selected: _store.activeTab == AppTab.checklist,
                          onTap: () => _store.setActiveTab(AppTab.checklist),
                        ),
                        _TabButton(
                          accent: tabAccentFor(AppTab.overview),
                          icon: Icons.auto_awesome_rounded,
                          label: '总览',
                          selected: _store.activeTab == AppTab.overview,
                          onTap: () => _store.setActiveTab(AppTab.overview),
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
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF90CE9B), Color(0xFF6AB57A)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x226AB57A),
                                      blurRadius: 18,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                  border: Border.all(color: const Color(0xAAFFFFFF), width: 1.4),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => _openAddSheet(context),
                                    child: const Center(
                                      child: Icon(Icons.add, size: 24, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _TabButton(
                          accent: tabAccentFor(AppTab.pets),
                          icon: Icons.pets_rounded,
                          label: '爱宠',
                          selected: _store.activeTab == AppTab.pets,
                          onTap: () => _store.setActiveTab(AppTab.pets),
                        ),
                        _TabButton(
                          accent: tabAccentFor(AppTab.me),
                          icon: Icons.person_rounded,
                          label: '我的',
                          selected: _store.activeTab == AppTab.me,
                          onTap: () => _store.setActiveTab(AppTab.me),
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

  Future<void> _openAddSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => AddActionSheet(store: _store),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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
                color: selected ? Colors.white : const Color(0xFF7E8492),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent.label : const Color(0xFF7E8492),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
