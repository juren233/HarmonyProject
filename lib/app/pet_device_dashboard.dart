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
    final tokens = context.petNoteTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '这台设备为谁服务？',
                style: TextStyle(
                  color: tokens.primaryText,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SyncFailureChip(),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: Icon(Icons.settings_rounded, color: tokens.primaryText),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (pets.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  if (syncStatusLabel.contains('同步中') ||
                      syncStatusLabel.contains('连接中'))
                    const CircularProgressIndicator()
                  else
                    Icon(Icons.pets, size: 64, color: tokens.secondaryText),
                  const SizedBox(height: 16),
                  Text(
                    syncStatusLabel.contains('同步中') ||
                            syncStatusLabel.contains('连接中')
                        ? '正在从主人端同步数据...'
                        : '还没有添加宠物',
                    style: TextStyle(fontSize: 18, color: tokens.secondaryText),
                  ),
                ],
              ),
            ),
          )
        else
          for (final pet in pets)
            Card(
              key: ValueKey('dashboard_select_pet_${pet.id}'),
              child: ListTile(
                leading: CircleAvatar(child: Text(pet.avatarText)),
                title: Text(pet.name),
                subtitle: Text('${pet.breed} · ${pet.ageLabel}'),
                onTap: () => onSelectServedPet(pet.id),
              ),
            ),
      ],
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
