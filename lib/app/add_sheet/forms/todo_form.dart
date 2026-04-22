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

class TodoForm extends StatefulWidget {
  const TodoForm({
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
  State<TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<TodoForm> {
  static const List<NotificationLeadTime> _availableLeadTimes =
      <NotificationLeadTime>[
    NotificationLeadTime.none,
    NotificationLeadTime.fiveMinutes,
    NotificationLeadTime.fifteenMinutes,
    NotificationLeadTime.oneHour,
    NotificationLeadTime.oneDay,
  ];

  final _title = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  late DateTime _dueAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _dueAt = defaultFutureDateTime();
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
      actionLabel: '保存待办',
      actionColor: const Color(0xFF4F7BFF),
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
                hintText: '例如：补货主粮、清洗水碗',
              ),
              const SectionLabel(text: '关联爱宠'),
              PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value),
              ),
              const SectionLabel(text: '时间'),
              AdaptiveDateTimeField(
                materialFieldKey: const ValueKey('todo_due_at_field'),
                iosDateFieldKey: const ValueKey('todo_due_date_field'),
                iosTimeFieldKey: const ValueKey('todo_due_time_field'),
                value: _dueAt,
                onChanged: (value) => setState(() => _dueAt = value),
              ),
              const SectionLabel(text: '提前通知'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _availableLeadTimes
                    .map(
                      (value) => _TodoChipOption(
                        key: ValueKey('todo-notification-chip-${value.name}'),
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
                hintText: '补充这次待办的背景、要求或注意事项',
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
    await widget.store.addTodo(
      title: title,
      petId: _petId,
      dueAt: _dueAt,
      notificationLeadTime: _notificationLeadTime,
      note: note,
      semantic: simplifiedTodoSemantic(
        title: title,
        note: note,
        dueAt: _dueAt,
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
  }
}

class _TodoChipOption extends StatefulWidget {
  const _TodoChipOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TodoChipOption> createState() => _TodoChipOptionState();
}

class _TodoChipOptionState extends State<_TodoChipOption> {
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
                ? const Color(0xFF4F7BFF)
                : const Color(0xFFF6F7FA),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0x144F7BFF),
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
