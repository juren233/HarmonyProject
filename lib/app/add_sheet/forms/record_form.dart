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

class RecordForm extends StatefulWidget {
  const RecordForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _note = TextEditingController();
  final List<MeasurementDraft> _measurementDrafts = <MeasurementDraft>[];
  late String _petId;
  PetRecordType _type = PetRecordType.other;
  late DateTime _recordDate;
  SemanticTopicKey _topicKey = SemanticTopicKey.other;
  SemanticSignal _signal = SemanticSignal.info;
  SemanticEvidenceSource _source = SemanticEvidenceSource.other;
  DateTime? _followUpAt;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _recordDate = DateTime.now();
    _measurementDrafts.add(MeasurementDraft());
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _note.dispose();
    for (final draft in _measurementDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      actionLabel: '保存记录',
      actionColor: const Color(0xFF4FB57C),
      onSubmit: () async {
        await widget.store.addRecord(
          petId: _petId,
          type: _type,
          title: _title.text.trim(),
          recordDate: _recordDate,
          summary: _summary.text.trim(),
          note: _note.text.trim(),
          semantic: SemanticEventDetails(
            topicKey: _topicKey,
            signal: _signal,
            tags: semanticTagsForTopic(_topicKey),
            evidenceSummary: recordEvidenceSummary(
              summary: _summary.text.trim(),
              note: _note.text.trim(),
              title: _title.text.trim(),
            ),
            actionSummary: recordActionSummary(_signal, _recordDate),
            followUpAt: _followUpAt,
            measurements: _buildMeasurements(),
            intent: SemanticActionIntent.record,
            source: _source,
          ),
        );
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: SectionCard(
        title: '资料信息',
        children: [
          const SectionLabel(text: '关联爱宠'),
          PetSelector(
            pets: widget.store.pets,
            value: _petId,
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SectionLabel(text: '记录类型'),
          ChoiceWrap<PetRecordType>(
            values: PetRecordType.values,
            selected: _type,
            labelBuilder: _recordTypeLabel,
            onChanged: (value) => setState(() {
              _type = value;
              _source = defaultSourceForRecordType(value);
            }),
          ),
          const SectionLabel(text: '标题'),
          HyperTextField(
            controller: _title,
            hintText: '可留空，默认按结构化信息生成',
          ),
          const SectionLabel(text: '时间'),
          AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('record_date_field'),
            iosDateFieldKey: const ValueKey('record_date_date_field'),
            iosTimeFieldKey: const ValueKey('record_date_time_field'),
            value: _recordDate,
            onChanged: (value) => setState(() => _recordDate = value),
          ),
          const SectionLabel(text: '主题'),
          ChoiceWrap<SemanticTopicKey>(
            values: recordTopicOptions,
            selected: _topicKey,
            labelBuilder: semanticTopicLabel,
            onChanged: (value) => setState(() => _topicKey = value),
          ),
          const SectionLabel(text: '事件信号'),
          ChoiceWrap<SemanticSignal>(
            values: recordSignalOptions,
            selected: _signal,
            labelBuilder: semanticSignalLabel,
            onChanged: (value) => setState(() => _signal = value),
          ),
          const SectionLabel(text: '证据来源'),
          ChoiceWrap<SemanticEvidenceSource>(
            values: recordSourceOptions,
            selected: _source,
            labelBuilder: semanticSourceLabel,
            onChanged: (value) => setState(() => _source = value),
          ),
          const SectionLabel(text: '跟进时间（可选）'),
          OptionalAdaptiveDateTimeField(
            materialFieldKey: const ValueKey('record_follow_up_field'),
            iosDateFieldKey: const ValueKey('record_follow_up_date_field'),
            iosTimeFieldKey: const ValueKey('record_follow_up_time_field'),
            value: _followUpAt,
            placeholder: '点击选择跟进时间',
            onPickDateTime: _pickFollowUpAt,
            onPickDate: _pickFollowUpDateOnIos,
            onPickTime: _pickFollowUpTimeOnIos,
            clearButtonKey: const ValueKey('record_clear_follow_up_button'),
            onClear: () => setState(() => _followUpAt = null),
          ),
          const SectionLabel(text: '事实摘要'),
          HyperTextField(
            controller: _summary,
            hintText: '面向 AI 的核心事实摘要',
            maxLines: 3,
          ),
          const SectionLabel(text: '关键指标（可选）'),
          MeasurementEditorSection(
            prefix: 'record',
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
      initialValue: _followUpAt ?? _recordDate,
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
      initialValue: _followUpAt ?? _recordDate,
    );
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _recordDate;
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
      initialValue: _followUpAt ?? _recordDate,
    );
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      final current = _followUpAt ?? _recordDate;
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

String _recordTypeLabel(PetRecordType type) => switch (type) {
      PetRecordType.medical => '病历',
      PetRecordType.receipt => '票据',
      PetRecordType.image => '图片',
      PetRecordType.testResult => '检查结果',
      PetRecordType.other => '其他',
    };
