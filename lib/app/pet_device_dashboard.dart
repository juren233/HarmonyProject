import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PetDeviceDashboard extends StatelessWidget {
  const PetDeviceDashboard({
    super.key,
    required this.store,
    required this.servedPetId,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onSelectServedPet,
    required this.onMarkDone,
    required this.onOpenSettings,
  });

  final PetNoteStore store;
  final String? servedPetId;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
  final ValueChanged<String> onSelectServedPet;
  final ValueChanged<PetAction> onMarkDone;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final pets = store.pets;
    final selectedPet = _findPet(pets, servedPetId);
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
                    pets: pets,
                    syncStatusLabel: syncStatusLabel,
                    onSelectServedPet: onSelectServedPet,
                    onOpenSettings: onOpenSettings,
                  )
                : _DashboardContent(
                    store: store,
                    pet: selectedPet,
                    syncStatusLabel: syncStatusLabel,
                    pendingItemKeys: pendingItemKeys,
                    onMarkDone: onMarkDone,
                    onOpenSettings: onOpenSettings,
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
    required this.pets,
    required this.syncStatusLabel,
    required this.onSelectServedPet,
    required this.onOpenSettings,
  });

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
              syncStatusLabel: syncStatusLabel,
              onOpenSettings: onOpenSettings,
            ),
            const SizedBox(height: 14),
            _PetSelectorHero(syncStatusLabel: syncStatusLabel),
            const SizedBox(height: 14),
            Expanded(
              child: _PetSelectorListPanel(
                pets: pets,
                onSelectServedPet: onSelectServedPet,
              ),
            ),
            const SizedBox(height: 10),
            const _SelectorQuietLine(text: '稍后可在设置中重新选择'),
          ],
        );
      },
    );
  }
}

class _PetSelectorTopBar extends StatelessWidget {
  const _PetSelectorTopBar({
    required this.syncStatusLabel,
    required this.onOpenSettings,
  });

  final String syncStatusLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatClock(now),
                style: TextStyle(
                  color: tokens.primaryText,
                  fontSize: 44,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatWeekday(now)} · 家中设备',
                style: TextStyle(
                  color: tokens.secondaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SyncFailureChip(),
        const SizedBox(width: 8),
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
  const _PetSelectorHero({required this.syncStatusLabel});

  final String syncStatusLabel;

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
            _selectorSyncKicker(syncStatusLabel),
            style: TextStyle(
              color: tokens.navAddGradientEnd,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '这台设备照顾谁？',
            style: TextStyle(
              color: tokens.primaryText,
              fontSize: 32,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '选择后会进入常亮中枢屏，只展示它的状态和待办。',
            style: TextStyle(
              color: tokens.secondaryText,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PetSelectorSidePanel extends StatelessWidget {
  const _PetSelectorSidePanel({
    required this.syncStatusLabel,
    required this.onOpenSettings,
  });

  final String syncStatusLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final now = DateTime.now();
    return _SelectorSurface(
      key: const ValueKey('pet_selector_side_panel'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatClock(now),
                      style: TextStyle(
                        color: tokens.primaryText,
                        fontSize: 48,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatWeekday(now)} · 家中设备',
                      style: TextStyle(
                        color: tokens.secondaryText,
                        fontSize: 13,
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
          ),
          const Spacer(),
          Text(
            _selectorSyncKicker(syncStatusLabel),
            style: TextStyle(
              color: tokens.navAddGradientEnd,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '选择服务宠物',
            style: TextStyle(
              color: tokens.primaryText,
              fontSize: 32,
              height: 1.06,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '横放设备时，左侧保留状态和设置，右侧留给宠物选择。',
            style: TextStyle(
              color: tokens.secondaryText,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _ConnectionPill(label: syncStatusLabel),
          const Spacer(),
          const _SelectorQuietLine(text: '选择后进入常亮中枢屏'),
        ],
      ),
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
          if (landscape) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '这台设备照顾谁？',
                        style: TextStyle(
                          color: tokens.primaryText,
                          fontSize: 30,
                          height: 1.06,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '点击一张宠物卡片即可接管对应待办和观察状态。',
                        style: TextStyle(
                          color: tokens.secondaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _SelectorCountChip(count: pets.length),
              ],
            ),
            const SizedBox(height: 18),
          ] else ...[
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
                    padding: const EdgeInsets.only(bottom: 4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: landscape ? 2 : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 16,
                      mainAxisExtent: landscape ? 126 : 86,
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
          padding: EdgeInsets.all(landscape ? 18 : 14),
          decoration: BoxDecoration(
            color: tokens.panelBackground,
            borderRadius: BorderRadius.circular(landscape ? 28 : 24),
            border: Border.all(
              color: prominent
                  ? tokens.navAddGradientEnd.withValues(alpha: 0.34)
                  : tokens.panelBorder,
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.panelShadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              PetPhotoAvatar(
                photoPath: pet.photoPath,
                fallbackText: petAvatarFallbackForPet(pet),
                radius: landscape ? 33 : 27,
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
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pet.breed} · ${pet.ageLabel}',
                      maxLines: landscape ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.secondaryText,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SelectorArrow(prominent: prominent),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorArrow extends StatelessWidget {
  const _SelectorArrow({required this.prominent});

  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: prominent
            ? tokens.badgeGoldBackground
            : tokens.secondarySurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.chevron_right_rounded,
        color: prominent ? tokens.badgeGoldForeground : tokens.secondaryText,
        size: 28,
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

class _SelectorQuietLine extends StatelessWidget {
  const _SelectorQuietLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: tokens.secondaryText,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.store,
    required this.pet,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onMarkDone,
    required this.onOpenSettings,
  });

  final PetNoteStore store;
  final Pet pet;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
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
        return Column(
          children: [
            _DashboardTopBar(
              onOpenSettings: onOpenSettings,
              isLandscape: isLandscape,
              syncStatusLabel: syncStatusLabel,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: isLandscape
                  ? Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _PetStatusPanel(
                            pet: pet,
                            compact: true,
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
                    )
                  : Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _PetStatusPanel(
                            pet: pet,
                            compact: true,
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
    required this.onOpenSettings,
    required this.isLandscape,
    required this.syncStatusLabel,
  });

  final VoidCallback onOpenSettings;
  final bool isLandscape;
  final String syncStatusLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatClock(now),
                style: TextStyle(
                  color: tokens.primaryText,
                  fontSize: isLandscape ? 42 : 44,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatWeekday(now)} · 家中设备',
                style: TextStyle(
                  color: tokens.secondaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SyncFailureChip(),
        const SizedBox(width: 8),
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

class _PetStatusPanel extends StatelessWidget {
  const _PetStatusPanel({
    required this.pet,
    required this.compact,
  });

  final Pet pet;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final foreground = tokens.primaryText;
    return _SoftPanel(
      key: const ValueKey('pet_dashboard_pet_card'),
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: PetPhotoAvatar(
                photoPath: pet.photoPath,
                fallbackText: petAvatarFallbackForPet(pet),
                radius: compact ? 38 : 54,
                backgroundColor: tokens.segmentedSelectedBackground,
                foregroundColor: Colors.white,
                fallbackTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 32 : 44,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 14),
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
            '${pet.breed} · ${pet.ageLabel}',
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
    final connected = label.contains('已连接') || label.contains('同步中');
    final tokens = context.petNoteTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: connected
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
              color: connected
                  ? const Color(0xFF52B788)
                  : tokens.badgeGoldForeground,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (connected
                          ? const Color(0xFF52B788)
                          : tokens.badgeGoldForeground)
                      .withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              color: connected
                  ? tokens.emptyStateForeground
                  : tokens.badgeGoldForeground,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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

String _selectorSyncKicker(String label) {
  if (label.contains('已连接') || label.contains('同步中')) {
    return '已连接主人端';
  }
  if (label.contains('连接中')) {
    return '正在连接主人端';
  }
  return '等待主人端同步';
}
