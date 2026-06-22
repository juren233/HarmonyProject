import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PetDeviceDashboard extends StatefulWidget {
  const PetDeviceDashboard({
    super.key,
    required this.store,
    required this.servedPetId,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onSelectServedPet,
    required this.onMarkDone,
    required this.onOpenSettings,
    this.nowProvider,
  });

  final PetNoteStore store;
  final String? servedPetId;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
  final ValueChanged<String?> onSelectServedPet;
  final ValueChanged<PetAction> onMarkDone;
  final VoidCallback onOpenSettings;
  final DateTime Function()? nowProvider;

  @override
  State<PetDeviceDashboard> createState() => _PetDeviceDashboardState();
}

class _PetDeviceDashboardState extends State<PetDeviceDashboard>
    with WidgetsBindingObserver {
  Timer? _clockTimer;
  late DateTime _now;

  DateTime get _currentNow => (widget.nowProvider ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = _currentNow;
    _scheduleNextClockRefresh();
  }

  @override
  void didUpdateWidget(covariant PetDeviceDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nowProvider, widget.nowProvider)) {
      _now = _currentNow;
      _scheduleNextClockRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshClockNow();
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  void _scheduleNextClockRefresh() {
    _clockTimer?.cancel();
    final now = _currentNow;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final delay = nextMinute.difference(now);
    _clockTimer = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      _handleClockRefresh,
    );
  }

  void _handleClockRefresh() {
    if (!mounted) {
      return;
    }
    _refreshClockNow();
  }

  void _refreshClockNow() {
    setState(() {
      _now = _currentNow;
    });
    _scheduleNextClockRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final pets = widget.store.pets;
    final selectedPet = _findPet(pets, widget.servedPetId);
    final tokens = context.petNoteTokens;
    return Scaffold(
      backgroundColor: tokens.pageGradientTop,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: selectedPet == null
                ? _PetSelector(
                    now: _now,
                    pets: pets,
                    syncStatusLabel: widget.syncStatusLabel,
                    onSelectServedPet: widget.onSelectServedPet,
                    onOpenSettings: widget.onOpenSettings,
                  )
                : _DashboardContent(
                    now: _now,
                    store: widget.store,
                    pet: selectedPet,
                    syncStatusLabel: widget.syncStatusLabel,
                    pendingItemKeys: widget.pendingItemKeys,
                    onReturnToPetSelection: () =>
                        widget.onSelectServedPet(null),
                    onMarkDone: widget.onMarkDone,
                    onOpenSettings: widget.onOpenSettings,
                  ),
          ),
        ),
      ),
    );
  }
}

Pet? _findPet(List<Pet> pets, String? petId) {
  for (final pet in pets) {
    if (pet.id == petId) {
      return pet;
    }
  }
  return null;
}

class _PetSelector extends StatelessWidget {
  const _PetSelector({
    required this.now,
    required this.pets,
    required this.syncStatusLabel,
    required this.onSelectServedPet,
    required this.onOpenSettings,
  });

  final DateTime now;
  final List<Pet> pets;
  final String syncStatusLabel;
  final ValueChanged<String> onSelectServedPet;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= 640;
        if (isLandscape) {
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: _PetSelectorSidePanel(
                  now: now,
                  syncStatusLabel: syncStatusLabel,
                  onOpenSettings: onOpenSettings,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 7,
                child: _PetSelectorListPanel(
                  pets: pets,
                  onSelectServedPet: onSelectServedPet,
                  landscape: true,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _PetSelectorTopBar(
              now: now,
              syncStatusLabel: syncStatusLabel,
              onOpenSettings: onOpenSettings,
            ),
            const SizedBox(height: 14),
            const _PetSelectorHero(),
            const SizedBox(height: 14),
            Expanded(
              child: _PetSelectorListPanel(
                pets: pets,
                onSelectServedPet: onSelectServedPet,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PetSelectorTopBar extends StatelessWidget {
  const _PetSelectorTopBar({
    required this.now,
    required this.syncStatusLabel,
    required this.onOpenSettings,
  });

  final DateTime now;
  final String syncStatusLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatClock(now),
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.primaryText,
                    fontSize: 44,
                    height: 0.95,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatWeekday(now)} · 家中设备',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.secondaryText,
                  fontSize: 14,
                  height: 1.35,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _ConnectionPill(label: syncStatusLabel),
        const SizedBox(width: 8),
        _IconSurfaceButton(
          key: const ValueKey('pet_dashboard_settings'),
          onPressed: onOpenSettings,
          icon: Icons.settings_rounded,
          semanticLabel: '设置',
        ),
      ],
    );
  }
}

class _PetSelectorHero extends StatelessWidget {
  const _PetSelectorHero();

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return _SelectorSurface(
      key: const ValueKey('pet_selector_hero'),
      padding: const EdgeInsets.all(24),
      fill: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这台设备照顾谁？',
            style: TextStyle(
              color: tokens.primaryText,
              fontSize: 32,
              height: 1.4,
              letterSpacing: 0,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PetSelectorSidePanel extends StatelessWidget {
  const _PetSelectorSidePanel({
    required this.now,
    required this.syncStatusLabel,
    required this.onOpenSettings,
  });

  final DateTime now;
  final String syncStatusLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Column(
      key: const ValueKey('pet_selector_side_panel'),
      children: [
        _SelectorLandscapeTopBar(
          now: now,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SelectorSurface(
            key: const ValueKey('pet_selector_status_card'),
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final logoSize =
                    (constraints.maxHeight * 0.24).clamp(64.0, 82.0).toDouble();
                final topGap =
                    (constraints.maxHeight * 0.05).clamp(6.0, 14.0).toDouble();
                final brandBottomGap =
                    (constraints.maxHeight * 0.05).clamp(8.0, 16.0).toDouble();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: topGap),
                    Center(child: _SelectorBrandHeader(logoSize: logoSize)),
                    SizedBox(height: brandBottomGap),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '这台设备照顾谁？',
                                maxLines: 1,
                                style: TextStyle(
                                  color: tokens.primaryText,
                                  fontSize: 32,
                                  height: 1.18,
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: double.infinity),
                              child: _ConnectionPill(label: syncStatusLabel),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectorBrandHeader extends StatelessWidget {
  const _SelectorBrandHeader({required this.logoSize});

  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Column(
      key: const ValueKey('pet_selector_brand_header'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _SelectorAppLogo(size: logoSize),
        const SizedBox(height: 10),
        Text(
          '宠记',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.primaryText,
            fontSize: 20,
            height: 1.1,
            letterSpacing: 0,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PetNote',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.secondaryText,
            fontSize: 11,
            height: 1.1,
            letterSpacing: 0,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SelectorAppLogo extends StatelessWidget {
  const _SelectorAppLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoBoxBackground = isDark ? const Color(0xFF111111) : Colors.white;
    final logoBoxBorderColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEAE6E0);
    final logoShadowColor =
        isDark ? Colors.black.withValues(alpha: 0.28) : const Color(0x0D000000);
    final logoColorFilter =
        isDark ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;

    return Container(
      key: const ValueKey('pet_selector_app_logo_box'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: logoBoxBackground,
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: logoBoxBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: logoShadowColor,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size - 2,
            maxHeight: size - 2,
          ),
          child: SvgPicture.asset(
            'assets/images/intro/first_page_hero.svg',
            fit: BoxFit.contain,
            colorFilter: logoColorFilter,
          ),
        ),
      ),
    );
  }
}

class _SelectorLandscapeTopBar extends StatelessWidget {
  const _SelectorLandscapeTopBar({
    required this.now,
    required this.onOpenSettings,
  });

  final DateTime now;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatClock(now),
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.primaryText,
                    fontSize: 42,
                    height: 1.0,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatWeekday(now)} · 家中设备',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.secondaryText,
                  fontSize: 13,
                  height: 1.35,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _IconSurfaceButton(
          key: const ValueKey('pet_dashboard_settings'),
          onPressed: onOpenSettings,
          icon: Icons.settings_rounded,
          semanticLabel: '设置',
        ),
      ],
    );
  }
}

class _PetSelectorListPanel extends StatelessWidget {
  const _PetSelectorListPanel({
    required this.pets,
    required this.onSelectServedPet,
    this.landscape = false,
  });

  final List<Pet> pets;
  final ValueChanged<String> onSelectServedPet;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return _SelectorSurface(
      key: const ValueKey('pet_selector_list_panel'),
      padding: EdgeInsets.all(landscape ? 24 : 18),
      strong: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!landscape) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择宠物',
                    style: TextStyle(
                      color: tokens.primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _SelectorCountChip(count: pets.length),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: pets.isEmpty
                ? const _PetSelectorEmptyState()
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      landscape ? 4 : 0,
                      0,
                      landscape ? 4 : 0,
                      landscape ? 12 : 4,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: landscape ? 2 : 1,
                      mainAxisSpacing: landscape ? 16 : 12,
                      crossAxisSpacing: 16,
                      mainAxisExtent: landscape ? 112 : 86,
                    ),
                    itemCount: pets.length,
                    itemBuilder: (context, index) {
                      final pet = pets[index];
                      return _PetSelectionCard(
                        pet: pet,
                        prominent: index == 0,
                        landscape: landscape,
                        onTap: () => onSelectServedPet(pet.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PetSelectionCard extends StatelessWidget {
  const _PetSelectionCard({
    required this.pet,
    required this.prominent,
    required this.landscape,
    required this.onTap,
  });

  final Pet pet;
  final bool prominent;
  final bool landscape;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Material(
      key: ValueKey('dashboard_select_pet_${pet.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(landscape ? 28 : 24),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panelBackground,
            borderRadius: BorderRadius.circular(landscape ? 28 : 24),
            border: Border.all(
              color: prominent
                  ? tokens.navAddGradientEnd.withValues(alpha: 0.34)
                  : tokens.panelBorder,
              width: 1.1,
            ),
          ),
          child: Row(
            children: [
              PetPhotoAvatar(
                photoPath: pet.photoPath,
                fallbackText: petAvatarFallbackForPet(pet),
                radius: landscape ? 31 : 27,
                backgroundColor: tokens.segmentedSelectedBackground,
                foregroundColor: Colors.white,
                fallbackTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: landscape ? 27 : 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: landscape ? 16 : 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.primaryText,
                        fontSize: landscape ? 25 : 21,
                        height: 1.4,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _petMetaLabel(pet),
                      maxLines: landscape ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.secondaryText,
                        fontSize: 14,
                        height: 1.45,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorCountChip extends StatelessWidget {
  const _SelectorCountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final label = count == 0 ? '等待同步' : '$count 只可服务';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.secondarySurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PetSelectorEmptyState extends StatelessWidget {
  const _PetSelectorEmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pets_rounded,
            color: tokens.emptyStateForeground,
            size: 46,
          ),
          const SizedBox(height: 14),
          Text(
            '正在等待宠物资料',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.primaryText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '主人端同步完成后，这里会出现可服务的宠物。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.secondaryText,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorSurface extends StatelessWidget {
  const _SelectorSurface({
    super.key,
    required this.child,
    required this.padding,
    this.strong = false,
    this.fill = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      width: double.infinity,
      height: fill ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? tokens.panelStrongBackground : tokens.panelBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tokens.panelBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: tokens.panelShadow,
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.now,
    required this.store,
    required this.pet,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onReturnToPetSelection,
    required this.onMarkDone,
    required this.onOpenSettings,
  });

  final DateTime now;
  final PetNoteStore store;
  final Pet pet;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
  final VoidCallback onReturnToPetSelection;
  final ValueChanged<PetAction> onMarkDone;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final items = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .take(5)
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= 640;
        if (isLandscape) {
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _DashboardTopBar(
                      now: now,
                      onOpenSettings: onOpenSettings,
                      isLandscape: true,
                      syncStatusLabel: syncStatusLabel,
                      showConnectionStatus: false,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _PetStatusPanel(
                        pet: pet,
                        compact: true,
                        syncStatusLabel: syncStatusLabel,
                        onReturnToPetSelection: onReturnToPetSelection,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 7,
                child: _TodoPanel(
                  items: items,
                  pendingItemKeys: pendingItemKeys,
                  onMarkDone: onMarkDone,
                  landscape: true,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _DashboardTopBar(
              now: now,
              onOpenSettings: onOpenSettings,
              isLandscape: false,
              syncStatusLabel: syncStatusLabel,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: _PetStatusPanel(
                      pet: pet,
                      compact: true,
                      onReturnToPetSelection: onReturnToPetSelection,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    flex: 7,
                    child: _TodoPanel(
                      items: items,
                      pendingItemKeys: pendingItemKeys,
                      onMarkDone: onMarkDone,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar({
    required this.now,
    required this.onOpenSettings,
    required this.isLandscape,
    required this.syncStatusLabel,
    this.showConnectionStatus = true,
  });

  final DateTime now;
  final VoidCallback onOpenSettings;
  final bool isLandscape;
  final String syncStatusLabel;
  final bool showConnectionStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatClock(now),
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.primaryText,
                    fontSize: isLandscape ? 42 : 44,
                    height: 0.95,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatWeekday(now)} · 家中设备',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.secondaryText,
                  fontSize: 14,
                  height: 1.35,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (showConnectionStatus) ...[
          const SizedBox(width: 8),
          _ConnectionPill(label: syncStatusLabel),
        ],
        const SizedBox(width: 8),
        _IconSurfaceButton(
          key: const ValueKey('pet_dashboard_settings'),
          onPressed: onOpenSettings,
          icon: Icons.settings_rounded,
          semanticLabel: '设置',
        ),
      ],
    );
  }
}

class _PetStatusPanel extends StatelessWidget {
  const _PetStatusPanel({
    required this.pet,
    required this.compact,
    required this.onReturnToPetSelection,
    this.syncStatusLabel,
  });

  final Pet pet;
  final bool compact;
  final VoidCallback onReturnToPetSelection;
  final String? syncStatusLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final foreground = tokens.primaryText;
    return _SoftPanel(
      key: const ValueKey('pet_dashboard_pet_card'),
      padding: EdgeInsets.all(compact ? 16 : 18),
      child: Column(
        mainAxisAlignment: syncStatusLabel == null
            ? MainAxisAlignment.center
            : MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    button: true,
                    label: '返回宠物选择',
                    child: GestureDetector(
                      key: const ValueKey(
                        'pet_dashboard_avatar_return_selection',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: onReturnToPetSelection,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PetPhotoAvatar(
                          photoPath: pet.photoPath,
                          fallbackText: petAvatarFallbackForPet(pet),
                          radius: compact ? 45 : 54,
                          backgroundColor: tokens.segmentedSelectedBackground,
                          foregroundColor: Colors.white,
                          fallbackTextStyle: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 36 : 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 9 : 14),
                Text(
                  pet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 25 : 34,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _petMetaLabel(pet),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.secondaryText,
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (syncStatusLabel != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: double.infinity),
              child: _ConnectionPill(label: syncStatusLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodoPanel extends StatelessWidget {
  const _TodoPanel({
    required this.items,
    required this.pendingItemKeys,
    required this.onMarkDone,
    this.landscape = false,
  });

  final List<ChecklistItemViewModel> items;
  final Set<String> pendingItemKeys;
  final ValueChanged<PetAction> onMarkDone;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final firstItem = items.isEmpty ? null : items.first;
    return _SoftPanel(
      key: const ValueKey('pet_dashboard_todo_panel'),
      padding: EdgeInsets.all(landscape ? 20 : 22),
      strong: true,
      child: firstItem == null
          ? const _EmptyTodoState()
          : _TodoFocusContent(
              item: firstItem,
              remainingCount: items.length - 1,
              pending: pendingItemKeys.contains(
                '${firstItem.sourceType}:${firstItem.id}',
              ),
              onMarkDone: onMarkDone,
              landscape: landscape,
            ),
    );
  }
}

class _TodoFocusContent extends StatelessWidget {
  const _TodoFocusContent({
    required this.item,
    required this.remainingCount,
    required this.pending,
    required this.onMarkDone,
    required this.landscape,
  });

  final ChecklistItemViewModel item;
  final int remainingCount;
  final bool pending;
  final ValueChanged<PetAction> onMarkDone;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final titleSize = landscape ? 44.0 : 34.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '下一件事',
              style: TextStyle(
                color: tokens.navAddGradientEnd,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            _TimeBadge(text: item.dueLabel),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          item.title,
          maxLines: landscape ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.primaryText,
            fontSize: titleSize,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${item.kindLabel} · ${item.statusLabel}',
          style: TextStyle(
            color: tokens.secondaryText,
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (item.note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            item.note,
            maxLines: landscape ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.secondaryText,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const Spacer(),
        if (remainingCount > 0) ...[
          _QuietHint(text: '后面还有 $remainingCount 件待办'),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: ValueKey('dashboard_item_${item.sourceType}_${item.id}'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.segmentedSelectedBackground,
                  foregroundColor: Colors.white,
                  minimumSize: Size.fromHeight(landscape ? 48 : 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: pending
                    ? null
                    : () => onMarkDone(
                          PetAction(
                            kind: PetActionKind.markDone,
                            sourceType: item.sourceType,
                            itemId: item.id,
                          ),
                        ),
                icon: pending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(pending ? '同步中' : '完成'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyTodoState extends StatelessWidget {
  const _EmptyTodoState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: tokens.emptyStateForeground,
            size: 46,
          ),
          const SizedBox(height: 14),
          Text(
            '今天没有待办',
            style: TextStyle(
              color: tokens.primaryText,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '设备保持在线，异常状态再突出显示',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final service = SyncService.instance;
    if (service == null) {
      return _ConnectionPillBody(label: label);
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final failedCount = service.failedSyncCount;
        if (failedCount == null) {
          return _ConnectionPillBody(label: label);
        }
        return ValueListenableBuilder<int>(
          valueListenable: failedCount,
          builder: (context, count, _) {
            final issueKind = service.currentIssueKind;
            if (count <= 0 || issueKind == SyncIssueKind.none) {
              return _ConnectionPillBody(label: label);
            }
            return _ConnectionPillBody(
              label: syncIssueChipLabel(issueKind),
              issueKind: issueKind,
              issueCount: count,
            );
          },
        );
      },
    );
  }
}

class _ConnectionPillBody extends StatelessWidget {
  const _ConnectionPillBody({
    required this.label,
    this.issueKind = SyncIssueKind.none,
    this.issueCount = 0,
  });

  final String label;
  final SyncIssueKind issueKind;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    final hasIssue = issueKind != SyncIssueKind.none;
    final connected = label.contains('已连接') || label.contains('同步中');
    final tokens = context.petNoteTokens;
    final foreground = hasIssue
        ? tokens.badgeGoldForeground
        : connected
            ? tokens.emptyStateForeground
            : tokens.badgeGoldForeground;
    final dotColor = connected && !hasIssue
        ? const Color(0xFF52B788)
        : tokens.badgeGoldForeground;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: connected && !hasIssue
            ? tokens.emptyStateBackground
            : tokens.badgeGoldBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                height: 1.4,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (!hasIssue) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showSyncIssueDialog(
          context,
          count: issueCount,
          issueKind: issueKind,
        ),
        child: content,
      ),
    );
  }
}

class _QuietHint extends StatelessWidget {
  const _QuietHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.secondarySurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tokens.secondaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  const _TimeBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.badgeGoldBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tokens.badgeGoldForeground,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IconSurfaceButton extends StatelessWidget {
  const _IconSurfaceButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.semanticLabel,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return IconButton(
      tooltip: semanticLabel,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: tokens.panelBackground,
        foregroundColor: tokens.primaryText,
        fixedSize: const Size.square(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.panelBorder),
        ),
      ),
      icon: Icon(icon),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({
    super.key,
    required this.child,
    required this.padding,
    this.strong = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? tokens.panelStrongBackground : tokens.panelBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tokens.panelBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tokens.panelShadow,
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: tokens.panelHighlightShadow,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

String _formatClock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatWeekday(DateTime value) {
  return switch (value.weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    _ => '周日',
  };
}

String _petMetaLabel(Pet pet) {
  final breed = pet.breed.trim();
  final age = pet.ageLabel.trim();
  if (age.isEmpty || age == '新加入') {
    return breed;
  }
  if (breed.isEmpty) {
    return age;
  }
  return '$breed · $age';
}
