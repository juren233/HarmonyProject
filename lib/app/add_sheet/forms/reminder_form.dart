import 'package:flutter/material.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/interaction_feedback.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/state/petnote_store.dart';

import '../form_controls/adaptive_date_time_field.dart';
import '../form_controls/form_scaffold.dart';
import '../form_controls/pet_selector.dart';
import '../pickers/date_time_pickers.dart';
import 'notification_permission_guard.dart';
import 'semantic_form_support.dart';

class ReminderForm extends StatefulWidget {
  const ReminderForm({
    super.key,
    required this.store,
    this.notificationCoordinator,
    this.notificationCoordinatorLoader,
  });

  final PetNoteStore store;
  final NotificationCoordinator? notificationCoordinator;
  final Future<NotificationCoordinator?> Function()?
      notificationCoordinatorLoader;

  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  static const List<NotificationLeadTime> _availableLeadTimes =
      <NotificationLeadTime>[
    NotificationLeadTime.oneDay,
    NotificationLeadTime.threeDays,
    NotificationLeadTime.sevenDays,
  ];

  final _title = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  late DateTime _scheduledAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.oneDay;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _scheduledAt = defaultFutureDateTime();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      actionLabel: '保存提醒',
      actionColor: const Color(0xFFF2A65A),
      onSubmit: _handleSubmit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: '核心信息',
            children: [
              const SectionLabel(text: '标题'),
              HyperTextField(
                controller: _title,
                hintText: '例如：年度疫苗补打、下周复查',
              ),
              const SectionLabel(text: '关联爱宠'),
              PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value),
              ),
              const SectionLabel(text: '时间'),
              AdaptiveDateTimeField(
                materialFieldKey: const ValueKey('reminder_scheduled_at_field'),
                iosDateFieldKey:
                    const ValueKey('reminder_scheduled_date_field'),
                iosTimeFieldKey:
                    const ValueKey('reminder_scheduled_time_field'),
                value: _scheduledAt,
                onChanged: (value) => setState(() => _scheduledAt = value),
              ),
              const SectionLabel(text: '提前通知'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _availableLeadTimes
                    .map(
                      (value) => _ReminderChipOption(
                        key: ValueKey(
                          'reminder-notification-chip-${value.name}',
                        ),
                        label: notificationLeadTimeLabel(value),
                        selected: _notificationLeadTime == value,
                        onTap: () => setState(
                          () => _notificationLeadTime = value,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
          SectionCard(
            title: '补充信息',
            children: [
              const SectionLabel(text: '补充说明'),
              HyperTextField(
                controller: _note,
                hintText: '补充提醒背景、准备事项或注意点',
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!mounted) {
      return;
    }
    final hasPermission = await ensureNotificationPermissionBeforeChecklistSave(
      context: context,
      notificationCoordinator: widget.notificationCoordinator,
      notificationCoordinatorLoader: widget.notificationCoordinatorLoader,
    );
    if (!hasPermission) {
      return;
    }
    final title = _title.text.trim();
    final note = _note.text.trim();
    const recurrence = '单次';
    final draft = inferReminderDraft(
      title: title,
      note: note,
      recurrence: recurrence,
      scheduledAt: _scheduledAt,
    );
    await widget.store.addReminder(
      title: title,
      petId: _petId,
      scheduledAt: _scheduledAt,
      notificationLeadTime: _notificationLeadTime,
      kind: draft.kind,
      recurrence: recurrence,
      note: note,
      semantic: draft.semantic,
    );
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
  }
}

class _ReminderChipOption extends StatefulWidget {
  const _ReminderChipOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ReminderChipOption> createState() => _ReminderChipOptionState();
}

class _ReminderChipOptionState extends State<_ReminderChipOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        triggerSelectionHaptic();
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        offset: _pressed ? const Offset(0.015, 0) : Offset.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: _pressed ? 15 : 18,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFFF2A65A)
                : const Color(0xFFF6F7FA),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0x18F2A65A),
                blurRadius: _pressed ? 6 : 14,
                offset: Offset(_pressed ? 1 : 0, _pressed ? 3 : 8),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color:
                      widget.selected ? Colors.white : const Color(0xFF6C7280),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}
