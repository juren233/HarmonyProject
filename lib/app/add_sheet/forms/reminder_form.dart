import 'package:flutter/material.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/petnote_store.dart';

import '../form_controls/adaptive_date_time_field.dart';
import '../form_controls/choice_wrap.dart';
import '../form_controls/form_scaffold.dart';
import '../form_controls/pet_selector.dart';
import '../pickers/date_time_pickers.dart';
import 'semantic_form_support.dart';

class ReminderForm extends StatefulWidget {
  const ReminderForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _recurrence = TextEditingController(text: '单次');
  late String _petId;
  late DateTime _scheduledAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;
  SemanticTopicKey _topicKey = SemanticTopicKey.review;
  SemanticActionIntent _intent = SemanticActionIntent.review;
  DateTime? _followUpAt;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _scheduledAt = defaultFutureDateTime();
    _followUpAt = _scheduledAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _recurrence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      actionLabel: '保存提醒',
      actionColor: const Color(0xFFF2A65A),
      onSubmit: () async {
        await widget.store.addReminder(
          title: _title.text.trim(),
          petId: _petId,
          scheduledAt: _scheduledAt,
          notificationLeadTime: _notificationLeadTime,
          kind: reminderKindForTopic(_topicKey),
          recurrence: _recurrence.text.trim(),
          note: _note.text.trim(),
          semantic: SemanticEventDetails(
            topicKey: _topicKey,
            signal: SemanticSignal.scheduled,
            tags: semanticTagsForTopic(_topicKey),
            evidenceSummary: todoEvidenceSummary(
              title: _title.text.trim(),
              note: _note.text.trim(),
            ),
            actionSummary: intentActionSummary(_intent, _scheduledAt),
            followUpAt: _followUpAt ?? _scheduledAt,
            measurements: const <SemanticMeasurement>[],
            intent: _intent,
            source: null,
          ),
        );
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: SectionCard(
        title: '提醒信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(
            controller: _title,
            hintText: '可留空，默认按结构化信息生成',
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
            iosDateFieldKey: const ValueKey('reminder_scheduled_date_field'),
            iosTimeFieldKey: const ValueKey('reminder_scheduled_time_field'),
            value: _scheduledAt,
            onChanged: (value) => setState(() {
              _scheduledAt = value;
              _followUpAt ??= value;
            }),
          ),
          const SectionLabel(text: '提前通知'),
          ChoiceWrap<NotificationLeadTime>(
            values: NotificationLeadTime.values,
            selected: _notificationLeadTime,
            labelBuilder: notificationLeadTimeLabel,
            onChanged: (value) => setState(() => _notificationLeadTime = value),
          ),
          const SectionLabel(text: '主题'),
          ChoiceWrap<SemanticTopicKey>(
            values: reminderTopicOptions,
            selected: _topicKey,
            labelBuilder: semanticTopicLabel,
            onChanged: (value) => setState(() {
              _topicKey = value;
              _intent = defaultReminderIntentForTopic(value);
            }),
          ),
          const SectionLabel(text: '执行意图'),
          ChoiceWrap<SemanticActionIntent>(
            values: reminderIntentOptions,
            selected: _intent,
            labelBuilder: semanticIntentLabel,
            onChanged: (value) => setState(() => _intent = value),
          ),
          const SectionLabel(text: '跟进时间（可选）'),
          OptionalAdaptiveDateTimeField(
            materialFieldKey: const ValueKey('reminder_follow_up_field'),
            iosDateFieldKey: const ValueKey('reminder_follow_up_date_field'),
            iosTimeFieldKey: const ValueKey('reminder_follow_up_time_field'),
            value: _followUpAt,
            placeholder: '默认跟随提醒时间',
            onPickDateTime: _pickFollowUpAt,
            onPickDate: _pickFollowUpDateOnIos,
            onPickTime: _pickFollowUpTimeOnIos,
            clearButtonKey: const ValueKey('reminder_clear_follow_up_button'),
            onClear: () => setState(() => _followUpAt = null),
          ),
          const SectionLabel(text: '重复规则'),
          HyperTextField(controller: _recurrence),
          const SectionLabel(text: '补充说明'),
          HyperTextField(
            controller: _note,
            hintText: '补充说明，不是主要事实字段',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Future<void> _pickFollowUpAt() async {
    final nextDateTime = await pickAdaptiveDateTime(
      context,
      initialValue: _followUpAt ?? _scheduledAt,
    );
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _followUpAt = nextDateTime;
    });
  }

  Future<void> _pickFollowUpDateOnIos() async {
    final nextDate = await pickCupertinoDatePart(
      context,
      initialValue: _followUpAt ?? _scheduledAt,
    );
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _scheduledAt;
      _followUpAt = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        current.hour,
        current.minute,
      );
    });
  }

  Future<void> _pickFollowUpTimeOnIos() async {
    final nextDateTime = await pickCupertinoTimePart(
      context,
      initialValue: _followUpAt ?? _scheduledAt,
    );
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _scheduledAt;
      _followUpAt = DateTime(
        current.year,
        current.month,
        current.day,
        nextDateTime.hour,
        nextDateTime.minute,
      );
    });
  }
}
