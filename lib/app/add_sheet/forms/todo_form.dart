import 'package:flutter/material.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/petnote_store.dart';

import '../form_controls/adaptive_date_time_field.dart';
import '../form_controls/choice_wrap.dart';
import '../form_controls/form_scaffold.dart';
import '../form_controls/measurement_editor_section.dart';
import '../form_controls/pet_selector.dart';
import '../pickers/date_time_pickers.dart';
import 'semantic_form_support.dart';

class TodoForm extends StatefulWidget {
  const TodoForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<TodoForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final List<MeasurementDraft> _measurementDrafts = <MeasurementDraft>[];
  late String _petId;
  late DateTime _dueAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;
  SemanticTopicKey _topicKey = SemanticTopicKey.other;
  SemanticActionIntent _intent = SemanticActionIntent.custom;
  DateTime? _followUpAt;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _dueAt = defaultFutureDateTime();
    _followUpAt = _dueAt;
    _measurementDrafts.add(MeasurementDraft());
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final draft in _measurementDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      actionLabel: '保存待办',
      actionColor: const Color(0xFF4F7BFF),
      onSubmit: () async {
        await widget.store.addTodo(
          title: _title.text.trim(),
          petId: _petId,
          dueAt: _dueAt,
          notificationLeadTime: _notificationLeadTime,
          note: _note.text.trim(),
          semantic: SemanticEventDetails(
            topicKey: _topicKey,
            signal: SemanticSignal.attention,
            tags: semanticTagsForTopic(_topicKey),
            evidenceSummary: todoEvidenceSummary(
              title: _title.text.trim(),
              note: _note.text.trim(),
            ),
            actionSummary: intentActionSummary(_intent, _dueAt),
            followUpAt: _followUpAt ?? _dueAt,
            measurements: _buildMeasurements(),
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
        title: '基础信息',
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
            materialFieldKey: const ValueKey('todo_due_at_field'),
            iosDateFieldKey: const ValueKey('todo_due_date_field'),
            iosTimeFieldKey: const ValueKey('todo_due_time_field'),
            value: _dueAt,
            onChanged: (value) => setState(() {
              _dueAt = value;
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
            values: todoTopicOptions,
            selected: _topicKey,
            labelBuilder: semanticTopicLabel,
            onChanged: (value) => setState(() {
              _topicKey = value;
              _intent = defaultIntentForTopic(value);
            }),
          ),
          const SectionLabel(text: '执行意图'),
          ChoiceWrap<SemanticActionIntent>(
            values: todoIntentOptions,
            selected: _intent,
            labelBuilder: semanticIntentLabel,
            onChanged: (value) => setState(() => _intent = value),
          ),
          const SectionLabel(text: '跟进时间（可选）'),
          OptionalAdaptiveDateTimeField(
            materialFieldKey: const ValueKey('todo_follow_up_field'),
            iosDateFieldKey: const ValueKey('todo_follow_up_date_field'),
            iosTimeFieldKey: const ValueKey('todo_follow_up_time_field'),
            value: _followUpAt,
            placeholder: '默认跟随待办时间',
            onPickDateTime: _pickFollowUpAt,
            onPickDate: _pickFollowUpDateOnIos,
            onPickTime: _pickFollowUpTimeOnIos,
            clearButtonKey: const ValueKey('todo_clear_follow_up_button'),
            onClear: () => setState(() => _followUpAt = null),
          ),
          const SectionLabel(text: '关键指标（可选）'),
          MeasurementEditorSection(
            prefix: 'todo',
            drafts: _measurementDrafts,
            onAdd: () =>
                setState(() => _measurementDrafts.add(MeasurementDraft())),
            onRemove: (index) => setState(() {
              final draft = _measurementDrafts.removeAt(index);
              draft.dispose();
            }),
          ),
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
      initialValue: _followUpAt ?? _dueAt,
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
      initialValue: _followUpAt ?? _dueAt,
    );
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _dueAt;
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
      initialValue: _followUpAt ?? _dueAt,
    );
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _dueAt;
      _followUpAt = DateTime(
        current.year,
        current.month,
        current.day,
        nextDateTime.hour,
        nextDateTime.minute,
      );
    });
  }

  List<SemanticMeasurement> _buildMeasurements() {
    return _measurementDrafts
        .map((draft) => draft.toMeasurement())
        .whereType<SemanticMeasurement>()
        .toList(growable: false);
  }
}
