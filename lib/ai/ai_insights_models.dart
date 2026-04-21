import 'dart:convert';

import 'package:petnote/state/petnote_store.dart';

class AiGenerationContext {
  const AiGenerationContext({
    required this.title,
    required this.rangeLabel,
    required this.rangeStart,
    required this.rangeEnd,
    required this.languageTag,
    required this.pets,
    required this.todos,
    required this.reminders,
    required this.records,
  });

  final String title;
  final String rangeLabel;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String languageTag;
  final List<Pet> pets;
  final List<TodoItem> todos;
  final List<ReminderItem> reminders;
  final List<PetRecord> records;

  String get cacheKey => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'rangeLabel': rangeLabel,
      'rangeStart': rangeStart.toIso8601String(),
      'rangeEnd': rangeEnd.toIso8601String(),
      'languageTag': languageTag,
      'pets': pets
          .map(
            (pet) => {
              'id': pet.id,
              'name': pet.name,
              'type': petTypeLabel(pet.type),
              'breed': pet.breed,
              'sex': pet.sex,
              'birthday': pet.birthday,
              'ageLabel': pet.ageLabel,
              'weightKg': pet.weightKg,
              'neuterStatus': petNeuterStatusLabel(pet.neuterStatus),
              'feedingPreferences': _compactText(pet.feedingPreferences, 80),
              'allergies': _compactText(pet.allergies, 80),
              'note': _compactText(pet.note, 120),
            },
          )
          .toList(),
      'todos': todos
          .map(
            (todo) => {
              'petId': todo.petId,
              'title': todo.title,
              'dueAt': todo.dueAt.toIso8601String(),
              'status': todo.status.name,
              'notificationLeadTime': todo.notificationLeadTime.name,
              'note': _compactText(todo.note, 120),
            },
          )
          .toList(),
      'reminders': reminders
          .map(
            (reminder) => {
              'petId': reminder.petId,
              'kind': reminder.kind.name,
              'title': reminder.title,
              'scheduledAt': reminder.scheduledAt.toIso8601String(),
              'status': reminder.status.name,
              'recurrence': reminder.recurrence,
              'notificationLeadTime': reminder.notificationLeadTime.name,
              'note': _compactText(reminder.note, 120),
            },
          )
          .toList(),
      'records': records
          .map(
            (record) => {
              'petId': record.petId,
              'type': record.type.name,
              'title': record.title,
              'recordDate': record.recordDate.toIso8601String(),
              'summary': _compactText(record.summary, 120),
              'note': _compactText(record.note, 160),
            },
          )
          .toList(),
    };
  }
}

class AiPortableSummaryPackage {
  const AiPortableSummaryPackage({
    required this.schemaVersion,
    required this.packageType,
    required this.title,
    required this.generatedAt,
    required this.range,
    required this.pets,
    required this.globalStats,
    required this.topicRollups,
    required this.activeItems,
    required this.keyEvidence,
    required this.measurements,
    required this.riskCandidates,
    required this.dataQualityNotes,
  });

  final int schemaVersion;
  final String packageType;
  final String title;
  final DateTime generatedAt;
  final Map<String, Object?> range;
  final List<Map<String, Object?>> pets;
  final Map<String, Object?> globalStats;
  final List<Map<String, Object?>> topicRollups;
  final List<Map<String, Object?>> activeItems;
  final List<Map<String, Object?>> keyEvidence;
  final List<Map<String, Object?>> measurements;
  final List<String> riskCandidates;
  final List<String> dataQualityNotes;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'packageType': packageType,
      'title': title,
      'generatedAt': generatedAt.toIso8601String(),
      'range': range,
      'pets': pets,
      'globalStats': globalStats,
      'topicRollups': topicRollups,
      'activeItems': activeItems,
      'keyEvidence': keyEvidence,
      'measurements': measurements,
      'riskCandidates': riskCandidates,
      'dataQualityNotes': dataQualityNotes,
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class AiPortableSummaryBuilder {
  const AiPortableSummaryBuilder({
    this.maxEvidencePerTopic = 3,
    this.maxActiveItems = 8,
    this.maxRiskCandidates = 6,
  });

  final int maxEvidencePerTopic;
  final int maxActiveItems;
  final int maxRiskCandidates;

  AiPortableSummaryPackage build({
    required String title,
    required AiGenerationContext context,
    required DateTime generatedAt,
  }) {
    final enrichedTodos = context.todos
        .map(
          (item) => _SummaryEvent(
            petId: item.petId,
            petName: _petNameFor(context, item.petId),
            happenedAt: item.dueAt,
            semantic: item.semantic ?? _fallbackTodoSemantic(item),
            rawTitle: item.title,
            rawNote: item.note,
            rawType: 'todo',
            isActive: item.status != TodoStatus.done,
            rawStatus: item.status.name,
          ),
        )
        .toList(growable: false);
    final enrichedReminders = context.reminders
        .map(
          (item) => _SummaryEvent(
            petId: item.petId,
            petName: _petNameFor(context, item.petId),
            happenedAt: item.scheduledAt,
            semantic: item.semantic ?? _fallbackReminderSemantic(item),
            rawTitle: item.title,
            rawNote: item.note,
            rawType: 'reminder',
            isActive: item.status != ReminderStatus.done,
            rawStatus: item.status.name,
          ),
        )
        .toList(growable: false);
    final enrichedRecords = context.records
        .map(
          (item) => _SummaryEvent(
            petId: item.petId,
            petName: _petNameFor(context, item.petId),
            happenedAt: item.recordDate,
            semantic: item.semantic ?? _fallbackRecordSemantic(item),
            rawTitle: item.title,
            rawNote: item.note,
            rawType: 'record',
            isActive: false,
            rawStatus: item.type.name,
          ),
        )
        .toList(growable: false);
    final events = <_SummaryEvent>[
      ...enrichedTodos,
      ...enrichedReminders,
      ...enrichedRecords,
    ];

    final topicRollups = _buildTopicRollups(events);
    final activeItems = _buildActiveItems(events);
    final keyEvidence = _buildKeyEvidence(events);
    final measurements = _buildMeasurements(context, events);
    final riskCandidates = _buildRiskCandidates(context, activeItems);
    final dataQualityNotes = _buildDataQualityNotes(context, events);

    return AiPortableSummaryPackage(
      schemaVersion: 1,
      packageType: 'ai_summary',
      title: title,
      generatedAt: generatedAt,
      range: {
        'label': context.rangeLabel,
        'start': context.rangeStart.toIso8601String(),
        'end': context.rangeEnd.toIso8601String(),
        'days': context.rangeEnd.difference(context.rangeStart).inDays,
      },
      pets: context.pets
          .map(
            (pet) => <String, Object?>{
              'petId': pet.id,
              'petName': pet.name,
              'type': petTypeLabel(pet.type),
              'ageLabel': pet.ageLabel,
              'weightKg': pet.weightKg,
              'allergies': _compactText(pet.allergies, 32),
            },
          )
          .toList(growable: false),
      globalStats: {
        'petCount': context.pets.length,
        'todoCount': context.todos.length,
        'reminderCount': context.reminders.length,
        'recordCount': context.records.length,
        'topicCount': topicRollups.length,
      },
      topicRollups: topicRollups,
      activeItems: activeItems,
      keyEvidence: keyEvidence,
      measurements: measurements,
      riskCandidates: riskCandidates,
      dataQualityNotes: dataQualityNotes,
    );
  }

  List<Map<String, Object?>> _buildTopicRollups(List<_SummaryEvent> events) {
    final grouped = <String, _TopicAccumulator>{};
    for (final event in events) {
      final key =
          '${event.semantic.topicKey.name}:${event.semantic.signal.name}';
      grouped.update(
        key,
        (current) => current.add(event),
        ifAbsent: () => _TopicAccumulator.fromEvent(event),
      );
    }
    final results = grouped.values.toList()
      ..sort((a, b) => b.latestAt.compareTo(a.latestAt));
    return results
        .map(
          (item) => <String, Object?>{
            'topicKey': item.topicKey.name,
            'signal': item.signal.name,
            'count': item.count,
            'latestAt': item.latestAt.toIso8601String(),
            'petNames': item.petNames.toList(growable: false),
          },
        )
        .toList(growable: false);
  }

  List<Map<String, Object?>> _buildActiveItems(List<_SummaryEvent> events) {
    final filtered = events.where((item) => item.isActive).toList()
      ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
    return filtered.take(maxActiveItems).map((item) {
      return <String, Object?>{
        'petId': item.petId,
        'petName': item.petName,
        'type': item.rawType,
        'title': _compactText(item.rawTitle, 28),
        'topicKey': item.semantic.topicKey.name,
        'signal': item.semantic.signal.name,
        'status': item.rawStatus,
        'at': item.happenedAt.toIso8601String(),
      };
    }).toList(growable: false);
  }

  List<Map<String, Object?>> _buildKeyEvidence(List<_SummaryEvent> events) {
    final grouped = <SemanticTopicKey, List<_SummaryEvent>>{};
    for (final event in events) {
      grouped
          .putIfAbsent(event.semantic.topicKey, () => <_SummaryEvent>[])
          .add(event);
    }
    final results = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final sorted = List<_SummaryEvent>.from(entry.value)
        ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
      for (final event in sorted.take(maxEvidencePerTopic)) {
        results.add(
          <String, Object?>{
            'topicKey': entry.key.name,
            'petName': event.petName,
            'at': event.happenedAt.toIso8601String(),
            'summary': _compactText(event.semantic.evidenceSummary, 72),
          },
        );
      }
    }
    results.sort((a, b) => (b['at'] as String).compareTo((a['at'] as String)));
    return results;
  }

  List<Map<String, Object?>> _buildMeasurements(
    AiGenerationContext context,
    List<_SummaryEvent> events,
  ) {
    final grouped = <String, _MeasurementAccumulator>{};
    for (final pet in context.pets) {
      grouped.update(
        'weight',
        (current) => current.addValue(
          pet.weightKg.toStringAsFixed(1),
          'kg',
          pet.name,
        ),
        ifAbsent: () => _MeasurementAccumulator.seed(
          key: 'weight',
          value: pet.weightKg.toStringAsFixed(1),
          unit: 'kg',
          petName: pet.name,
        ),
      );
    }
    for (final event in events) {
      for (final measurement in event.semantic.measurements) {
        grouped.update(
          measurement.key,
          (current) => current.addValue(
            measurement.value,
            measurement.unit,
            event.petName,
          ),
          ifAbsent: () => _MeasurementAccumulator.seed(
            key: measurement.key,
            value: measurement.value,
            unit: measurement.unit,
            petName: event.petName,
          ),
        );
      }
    }
    final results = grouped.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return results
        .map(
          (item) => <String, Object?>{
            'key': item.key,
            'latestValue': item.latestValue,
            'unit': item.unit,
            'sampleCount': item.sampleCount,
            'petNames': item.petNames.toList(growable: false),
          },
        )
        .toList(growable: false);
  }

  List<String> _buildRiskCandidates(
    AiGenerationContext context,
    List<Map<String, Object?>> activeItems,
  ) {
    final results = <String>[];
    final overdueCount = activeItems
        .where((item) => (item['status'] as String?) == 'overdue')
        .length;
    if (overdueCount > 0) {
      results.add('当前有 $overdueCount 条事项已逾期，建议优先处理。');
    }
    for (final pet in context.pets) {
      final hasRecord = context.records.any((item) => item.petId == pet.id);
      if (!hasRecord) {
        results.add('${pet.name} 当前区间缺少新增记录，建议补充最近观察。');
      }
    }
    if (results.isEmpty) {
      results.add('当前没有明显集中风险，继续保持规律记录即可。');
    }
    return results.take(maxRiskCandidates).toList(growable: false);
  }

  List<String> _buildDataQualityNotes(
    AiGenerationContext context,
    List<_SummaryEvent> events,
  ) {
    final withSemanticEvidence = events
        .where((item) => item.semantic.evidenceSummary.trim().isNotEmpty)
        .length;
    return <String>[
      '当前摘要覆盖 ${context.pets.length} 只宠物，共折叠 ${events.length} 条事件。',
      if (withSemanticEvidence < events.length)
        '部分历史数据由旧字段自动迁移，建议后续使用结构化录入获得更稳定分析。'
      else
        '当前事件均已具备结构化摘要，可直接用于模型分析。',
    ];
  }
}

class _SummaryEvent {
  const _SummaryEvent({
    required this.petId,
    required this.petName,
    required this.happenedAt,
    required this.semantic,
    required this.rawTitle,
    required this.rawNote,
    required this.rawType,
    required this.isActive,
    required this.rawStatus,
  });

  final String petId;
  final String petName;
  final DateTime happenedAt;
  final SemanticEventDetails semantic;
  final String rawTitle;
  final String rawNote;
  final String rawType;
  final bool isActive;
  final String rawStatus;
}

class _TopicAccumulator {
  _TopicAccumulator({
    required this.topicKey,
    required this.signal,
    required this.latestAt,
    required Set<String> petNames,
    this.count = 1,
  }) : petNames = petNames;

  factory _TopicAccumulator.fromEvent(_SummaryEvent event) {
    return _TopicAccumulator(
      topicKey: event.semantic.topicKey,
      signal: event.semantic.signal,
      latestAt: event.happenedAt,
      petNames: <String>{event.petName},
    );
  }

  final SemanticTopicKey topicKey;
  final SemanticSignal signal;
  final Set<String> petNames;
  int count;
  DateTime latestAt;

  _TopicAccumulator add(_SummaryEvent event) {
    count += 1;
    if (event.happenedAt.isAfter(latestAt)) {
      latestAt = event.happenedAt;
    }
    petNames.add(event.petName);
    return this;
  }
}

class _MeasurementAccumulator {
  _MeasurementAccumulator({
    required this.key,
    required this.latestValue,
    required this.unit,
    required Set<String> petNames,
    this.sampleCount = 1,
  }) : petNames = petNames;

  factory _MeasurementAccumulator.seed({
    required String key,
    required String value,
    required String unit,
    required String petName,
  }) {
    return _MeasurementAccumulator(
      key: key,
      latestValue: value,
      unit: unit,
      petNames: <String>{petName},
    );
  }

  final String key;
  final Set<String> petNames;
  String latestValue;
  String unit;
  int sampleCount;

  _MeasurementAccumulator addValue(
    String value,
    String nextUnit,
    String petName,
  ) {
    latestValue = value;
    if (nextUnit.isNotEmpty) {
      unit = nextUnit;
    }
    sampleCount += 1;
    petNames.add(petName);
    return this;
  }
}

String _petNameFor(AiGenerationContext context, String petId) {
  for (final pet in context.pets) {
    if (pet.id == petId) {
      return pet.name;
    }
  }
  return '未命名爱宠';
}

SemanticEventDetails _fallbackTodoSemantic(TodoItem item) {
  final topic = _fallbackTopicFromText('${item.title} ${item.note}');
  return SemanticEventDetails(
    topicKey: topic,
    signal: switch (item.status) {
      TodoStatus.done => SemanticSignal.completed,
      TodoStatus.skipped => SemanticSignal.missed,
      TodoStatus.open ||
      TodoStatus.postponed ||
      TodoStatus.overdue =>
        SemanticSignal.attention,
    },
    tags: _fallbackTagsForTopic(topic),
    evidenceSummary: _summaryEvidence(item.title, item.note),
    actionSummary: '待办时间 ${item.dueAt.toIso8601String()}',
    followUpAt: item.dueAt,
    measurements: const <SemanticMeasurement>[],
    intent: _fallbackIntentForTopic(topic),
    source: null,
  );
}

SemanticEventDetails _fallbackReminderSemantic(ReminderItem item) {
  final topic = switch (item.kind) {
    ReminderKind.vaccine => SemanticTopicKey.vaccine,
    ReminderKind.deworming => SemanticTopicKey.deworming,
    ReminderKind.medication => SemanticTopicKey.medication,
    ReminderKind.review => SemanticTopicKey.review,
    ReminderKind.grooming => SemanticTopicKey.grooming,
    ReminderKind.custom => _fallbackTopicFromText('${item.title} ${item.note}'),
  };
  return SemanticEventDetails(
    topicKey: topic,
    signal: switch (item.status) {
      ReminderStatus.done => SemanticSignal.completed,
      ReminderStatus.skipped => SemanticSignal.missed,
      ReminderStatus.pending ||
      ReminderStatus.postponed =>
        SemanticSignal.scheduled,
      ReminderStatus.overdue => SemanticSignal.attention,
    },
    tags: _fallbackTagsForTopic(topic),
    evidenceSummary: _summaryEvidence(item.title, item.note),
    actionSummary: '提醒时间 ${item.scheduledAt.toIso8601String()}',
    followUpAt: item.scheduledAt,
    measurements: const <SemanticMeasurement>[],
    intent: _fallbackIntentForTopic(topic),
    source: null,
  );
}

SemanticEventDetails _fallbackRecordSemantic(PetRecord item) {
  final topic =
      _fallbackTopicFromText('${item.title} ${item.summary} ${item.note}');
  final merged = '${item.title} ${item.summary} ${item.note}'.toLowerCase();
  return SemanticEventDetails(
    topicKey: topic,
    signal: merged.contains('复查') || merged.contains('观察')
        ? SemanticSignal.attention
        : merged.contains('稳定') || merged.contains('平稳')
            ? SemanticSignal.stable
            : SemanticSignal.info,
    tags: _fallbackTagsForTopic(topic),
    evidenceSummary: _summaryEvidence(item.summary, item.note, item.title),
    actionSummary: '记录时间 ${item.recordDate.toIso8601String()}',
    followUpAt: null,
    measurements: _fallbackMeasurementsFromText(merged),
    intent: SemanticActionIntent.record,
    source: switch (item.type) {
      PetRecordType.medical => SemanticEvidenceSource.vet,
      PetRecordType.testResult => SemanticEvidenceSource.lab,
      PetRecordType.receipt => SemanticEvidenceSource.receipt,
      _ => SemanticEvidenceSource.home,
    },
  );
}

SemanticTopicKey _fallbackTopicFromText(String rawText) {
  final text = rawText.toLowerCase();
  if (text.contains('驱虫')) return SemanticTopicKey.deworming;
  if (text.contains('疫苗') || text.contains('免疫')) {
    return SemanticTopicKey.vaccine;
  }
  if (text.contains('耳')) return SemanticTopicKey.earCare;
  if (text.contains('饮水') || text.contains('喝水')) {
    return SemanticTopicKey.hydration;
  }
  if (text.contains('皮肤') || text.contains('真菌')) {
    return SemanticTopicKey.skin;
  }
  if (text.contains('补货') ||
      text.contains('库存') ||
      text.contains('购买') ||
      text.contains('小票')) {
    return SemanticTopicKey.purchase;
  }
  if (text.contains('主粮') || text.contains('冻干')) {
    return SemanticTopicKey.diet;
  }
  if (text.contains('洗') || text.contains('指甲') || text.contains('梳毛')) {
    return SemanticTopicKey.grooming;
  }
  if (text.contains('复查') || text.contains('复诊') || text.contains('复盘')) {
    return SemanticTopicKey.review;
  }
  return SemanticTopicKey.other;
}

List<String> _fallbackTagsForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.deworming => const <String>['驱虫'],
    SemanticTopicKey.vaccine => const <String>['免疫'],
    SemanticTopicKey.earCare => const <String>['耳道'],
    SemanticTopicKey.hydration => const <String>['饮水'],
    SemanticTopicKey.purchase => const <String>['补货'],
    SemanticTopicKey.review => const <String>['复查'],
    _ => const <String>['日常'],
  };
}

SemanticActionIntent _fallbackIntentForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.purchase ||
    SemanticTopicKey.diet =>
      SemanticActionIntent.buy,
    SemanticTopicKey.deworming ||
    SemanticTopicKey.vaccine ||
    SemanticTopicKey.medication =>
      SemanticActionIntent.administer,
    SemanticTopicKey.review => SemanticActionIntent.review,
    SemanticTopicKey.grooming ||
    SemanticTopicKey.cleaning =>
      SemanticActionIntent.clean,
    _ => SemanticActionIntent.observe,
  };
}

List<SemanticMeasurement> _fallbackMeasurementsFromText(String text) {
  final items = <SemanticMeasurement>[];
  final waterMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|毫升)').firstMatch(text);
  if (waterMatch != null) {
    items.add(
      SemanticMeasurement(
        key: 'hydration',
        value: waterMatch.group(1) ?? '',
        unit: waterMatch.group(2) ?? 'ml',
      ),
    );
  }
  return items;
}

String _summaryEvidence(String first, [String second = '', String third = '']) {
  for (final item in [first, second, third]) {
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) {
      return _compactText(trimmed, 72);
    }
  }
  return '暂无说明';
}

enum AiScoreConfidence { low, medium, high }

String aiScoreConfidenceLabel(AiScoreConfidence confidence) =>
    switch (confidence) {
      AiScoreConfidence.low => '样本偏少',
      AiScoreConfidence.medium => '可信度中等',
      AiScoreConfidence.high => '可信度较高',
    };

class AiScoreDimension {
  const AiScoreDimension({
    required this.key,
    required this.label,
    required this.score,
    required this.reason,
  });

  final String key;
  final String label;
  final int score;
  final String reason;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'score': score,
      'reason': reason,
    };
  }

  factory AiScoreDimension.fromJson(Map<String, dynamic> json) {
    return AiScoreDimension(
      key: _requiredString(json, 'key'),
      label: _requiredString(json, 'label'),
      score: _optionalInt(json['score']) ?? 0,
      reason: _requiredString(json, 'reason'),
    );
  }
}

class AiPetCareScorecard {
  const AiPetCareScorecard({
    required this.petId,
    required this.petName,
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.riskCandidates,
    required this.dataQualityNotes,
    required this.recentEventTitles,
  });

  final String petId;
  final String petName;
  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final List<String> riskCandidates;
  final List<String> dataQualityNotes;
  final List<String> recentEventTitles;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'petName': petName,
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'riskCandidates': riskCandidates,
      'dataQualityNotes': dataQualityNotes,
      'recentEventTitles': recentEventTitles,
    };
  }
}

class AiCareScorecard {
  const AiCareScorecard({
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.riskCandidates,
    required this.dataQualityNotes,
    required this.petScorecards,
    required this.totalTodos,
    required this.totalReminders,
    required this.totalRecords,
  });

  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final List<String> riskCandidates;
  final List<String> dataQualityNotes;
  final List<AiPetCareScorecard> petScorecards;
  final int totalTodos;
  final int totalReminders;
  final int totalRecords;

  Map<String, dynamic> toJson() {
    return {
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'riskCandidates': riskCandidates,
      'dataQualityNotes': dataQualityNotes,
      'totals': {
        'todos': totalTodos,
        'reminders': totalReminders,
        'records': totalRecords,
      },
      'petScorecards': petScorecards.map((item) => item.toJson()).toList(),
    };
  }
}

class AiPetCareReport {
  const AiPetCareReport({
    required this.petId,
    required this.petName,
    required this.score,
    required this.scoreLabel,
    required this.scoreConfidence,
    required this.summary,
    required this.careFocus,
    required this.keyEvents,
    required this.trendAnalysis,
    required this.riskAssessment,
    required this.recommendedActions,
    required this.followUpFocus,
    this.statusLabel = '',
    this.whyThisScore = const [],
    this.topPriority = const [],
    this.missedItems = const [],
    this.recentChanges = const [],
    this.followUpPlan = const [],
  });

  final String petId;
  final String petName;
  final int score;
  final String scoreLabel;
  final AiScoreConfidence scoreConfidence;
  final String summary;
  final String careFocus;
  final List<String> keyEvents;
  final List<String> trendAnalysis;
  final List<String> riskAssessment;
  final List<String> recommendedActions;
  final String followUpFocus;
  final String statusLabel;
  final List<String> whyThisScore;
  final List<String> topPriority;
  final List<String> missedItems;
  final List<String> recentChanges;
  final List<String> followUpPlan;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'petName': petName,
      'score': score,
      'scoreLabel': scoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'summary': summary,
      'careFocus': careFocus,
      'keyEvents': keyEvents,
      'trendAnalysis': trendAnalysis,
      'riskAssessment': riskAssessment,
      'recommendedActions': recommendedActions,
      'followUpFocus': followUpFocus,
      'statusLabel': statusLabel,
      'whyThisScore': whyThisScore,
      'topPriority': topPriority,
      'missedItems': missedItems,
      'recentChanges': recentChanges,
      'followUpPlan': followUpPlan,
    };
  }

  factory AiPetCareReport.fromJson(
    Map<String, dynamic> json, {
    AiPetCareScorecard? scorecard,
  }) {
    final petId = _optionalString(json['petId']) ?? scorecard?.petId;
    final petName = _optionalString(json['petName']) ?? scorecard?.petName;
    if (petId == null || petName == null) {
      throw const AiGenerationException('AI 返回的结构化结果缺少宠物标识。');
    }
    final score = _optionalInt(json['score']) ?? scorecard?.overallScore ?? 0;
    final statusLabel = aiStatusLabelForScore(score);
    final whyThisScore = _requiredStringList(json, 'whyThisScore');
    final topPriority = _requiredStringList(json, 'topPriority');
    final missedItems = _requiredStringList(json, 'missedItems');
    final followUpPlan = _requiredStringList(json, 'followUpPlan');
    final summary = _firstString(
      json,
      const ['summary', 'careFocus'],
      fallback: whyThisScore.isNotEmpty ? whyThisScore.first : statusLabel,
    );
    final careFocus = _firstString(
      json,
      const ['careFocus'],
      fallback: topPriority.isNotEmpty ? topPriority.first : summary,
    );
    final trendAnalysis = _stringList(json['trendAnalysis']);
    final riskAssessment = _firstStringList(
      json,
      const ['riskAssessment', 'missedItems'],
    );
    return AiPetCareReport(
      petId: petId,
      petName: petName,
      score: score,
      scoreLabel: statusLabel,
      scoreConfidence: scorecard?.scoreConfidence ?? AiScoreConfidence.medium,
      summary: summary,
      careFocus: careFocus,
      keyEvents: const <String>[],
      trendAnalysis: trendAnalysis,
      riskAssessment: riskAssessment,
      recommendedActions: followUpPlan,
      followUpFocus: _firstString(
        json,
        const ['followUpFocus'],
        fallback: followUpPlan.isNotEmpty ? followUpPlan.first : careFocus,
      ),
      statusLabel: statusLabel,
      whyThisScore: whyThisScore,
      topPriority: topPriority,
      missedItems: missedItems,
      recentChanges: const <String>[],
      followUpPlan: followUpPlan,
    );
  }

  factory AiPetCareReport.fromStoredJson(Map<String, dynamic> json) {
    return AiPetCareReport(
      petId: _requiredString(json, 'petId'),
      petName: _requiredString(json, 'petName'),
      score: _optionalInt(json['score']) ?? 0,
      scoreLabel: _requiredString(json, 'scoreLabel'),
      scoreConfidence:
          _aiScoreConfidenceFromName(json['scoreConfidence'] as String?),
      summary: _requiredString(json, 'summary'),
      careFocus: _requiredString(json, 'careFocus'),
      keyEvents: _stringList(json['keyEvents']),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      recommendedActions: _stringList(json['recommendedActions']),
      followUpFocus: _requiredString(json, 'followUpFocus'),
      statusLabel: _optionalString(json['statusLabel']) ?? '',
      whyThisScore: _stringList(json['whyThisScore']),
      topPriority: _stringList(json['topPriority']),
      missedItems: _stringList(json['missedItems']),
      recentChanges: _stringList(json['recentChanges']),
      followUpPlan: _stringList(json['followUpPlan']),
    );
  }
}

class AiRecommendationRanking {
  const AiRecommendationRanking({
    required this.rank,
    required this.kind,
    required this.petIds,
    required this.petNames,
    required this.title,
    required this.summary,
    required this.suggestedAction,
  });

  final int rank;
  final String kind;
  final List<String> petIds;
  final List<String> petNames;
  final String title;
  final String summary;
  final String suggestedAction;

  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'kind': kind,
      'petIds': petIds,
      'petNames': petNames,
      'title': title,
      'summary': summary,
      'suggestedAction': suggestedAction,
    };
  }

  factory AiRecommendationRanking.fromJson(Map<String, dynamic> json) {
    return AiRecommendationRanking(
      rank: _optionalInt(json['rank']) ?? 0,
      kind: _requiredString(json, 'kind'),
      petIds: _requiredStringList(json, 'petIds'),
      petNames: _requiredStringList(json, 'petNames'),
      title: _requiredString(json, 'title'),
      summary: _requiredString(json, 'summary'),
      suggestedAction: _requiredString(json, 'suggestedAction'),
    );
  }
}

class AiCareReport {
  const AiCareReport({
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.executiveSummary,
    required this.overallAssessment,
    required this.keyFindings,
    required this.trendAnalysis,
    required this.riskAssessment,
    required this.priorityActions,
    required this.dataQualityNotes,
    required this.perPetReports,
    this.promptPayloadVersion = 'full',
    this.promptPayloadVersionLabel = '所有数据',
    this.statusLabel = '',
    this.oneLineSummary = '',
    this.recommendationRankings = const [],
  });

  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final String executiveSummary;
  final List<String> overallAssessment;
  final List<String> keyFindings;
  final List<String> trendAnalysis;
  final List<String> riskAssessment;
  final List<String> priorityActions;
  final List<String> dataQualityNotes;
  final List<AiPetCareReport> perPetReports;
  final String promptPayloadVersion;
  final String promptPayloadVersionLabel;
  final String statusLabel;
  final String oneLineSummary;
  final List<AiRecommendationRanking> recommendationRankings;

  String get summary =>
      oneLineSummary.isNotEmpty ? oneLineSummary : executiveSummary;

  Map<String, dynamic> toJson() {
    return {
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'executiveSummary': executiveSummary,
      'overallAssessment': overallAssessment,
      'keyFindings': keyFindings,
      'trendAnalysis': trendAnalysis,
      'riskAssessment': riskAssessment,
      'priorityActions': priorityActions,
      'dataQualityNotes': dataQualityNotes,
      'perPetReports': perPetReports.map((item) => item.toJson()).toList(),
      'promptPayloadVersion': promptPayloadVersion,
      'promptPayloadVersionLabel': promptPayloadVersionLabel,
      'statusLabel': statusLabel,
      'oneLineSummary': oneLineSummary,
      'recommendationRankings':
          recommendationRankings.map((item) => item.toJson()).toList(),
    };
  }

  factory AiCareReport.fromJson(
    Map<String, dynamic> json, {
    required AiCareScorecard scorecard,
  }) {
    final rawPetReports = json['perPetReports'];
    if (rawPetReports is! List) {
      throw const AiGenerationException(
        'AI 返回了 JSON，但结构化输出不完整：缺少 perPetReports。根因更像模型未按 schema 输出，而不是本地解析丢失。',
      );
    }
    final reportsByPetId = <String, Map<String, dynamic>>{};
    for (final item in rawPetReports) {
      if (item is! Map) {
        continue;
      }
      final mapped = item.map((key, value) => MapEntry('$key', value));
      final petId = _requiredString(mapped, 'petId');
      reportsByPetId[petId] = mapped;
    }
    final perPetReports = scorecard.petScorecards.isEmpty
        ? reportsByPetId.values
            .map(AiPetCareReport.fromJson)
            .toList(growable: false)
        : scorecard.petScorecards.map((petScorecard) {
            final rawReport = reportsByPetId[petScorecard.petId];
            if (rawReport == null) {
              throw AiGenerationException(
                'AI 返回了 JSON，但结构化输出不完整：缺少 ${petScorecard.petName} 的专项报告。根因更像模型漏字段，而不是本地解析丢失。',
              );
            }
            return AiPetCareReport.fromJson(
              rawReport,
              scorecard: petScorecard,
            );
          }).toList(growable: false);
    final recommendationRankings = _recommendationRankings(json);
    final oneLineSummary = _firstString(
      json,
      const ['oneLineSummary', 'executiveSummary'],
    );
    final overallScore =
        _optionalInt(json['overallScore']) ?? scorecard.overallScore;
    final statusLabel = aiStatusLabelForScore(overallScore);
    final priorityActions = _firstStringList(
      json,
      const ['priorityActions'],
      fallback: recommendationRankings
          .map((item) => item.suggestedAction)
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    return AiCareReport(
      overallScore: overallScore,
      overallScoreLabel: statusLabel,
      scoreConfidence: scorecard.scoreConfidence,
      scoreBreakdown: scorecard.scoreBreakdown,
      scoreReasons: scorecard.scoreReasons,
      executiveSummary: _firstString(
        json,
        const ['executiveSummary', 'oneLineSummary'],
      ),
      overallAssessment: _firstStringList(
        json,
        const ['overallAssessment'],
        fallback: oneLineSummary.isEmpty ? const [] : [oneLineSummary],
      ),
      keyFindings: _firstStringList(
        json,
        const ['keyFindings'],
        fallback: recommendationRankings
            .map((item) => item.summary)
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      ),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      priorityActions: priorityActions,
      dataQualityNotes: _firstStringList(
        json,
        const ['dataQualityNotes'],
        fallback: scorecard.dataQualityNotes,
      ),
      perPetReports: perPetReports,
      promptPayloadVersion:
          _optionalString(json['promptPayloadVersion']) ?? 'full',
      promptPayloadVersionLabel:
          _optionalString(json['promptPayloadVersionLabel']) ?? '所有数据',
      statusLabel: statusLabel,
      oneLineSummary: oneLineSummary,
      recommendationRankings: recommendationRankings,
    );
  }

  factory AiCareReport.fromStoredJson(Map<String, dynamic> json) {
    final rawScoreBreakdown = json['scoreBreakdown'];
    final rawPetReports = json['perPetReports'];
    final rawRecommendationRankings = json['recommendationRankings'];
    return AiCareReport(
      overallScore: _optionalInt(json['overallScore']) ?? 0,
      overallScoreLabel: _requiredString(json, 'overallScoreLabel'),
      scoreConfidence:
          _aiScoreConfidenceFromName(json['scoreConfidence'] as String?),
      scoreBreakdown: rawScoreBreakdown is List
          ? rawScoreBreakdown
              .whereType<Map>()
              .map((item) =>
                  AiScoreDimension.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiScoreDimension>[],
      scoreReasons: _stringList(json['scoreReasons']),
      executiveSummary: _requiredString(json, 'executiveSummary'),
      overallAssessment: _stringList(json['overallAssessment']),
      keyFindings: _stringList(json['keyFindings']),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      priorityActions: _stringList(json['priorityActions']),
      dataQualityNotes: _stringList(json['dataQualityNotes']),
      perPetReports: rawPetReports is List
          ? rawPetReports
              .whereType<Map>()
              .map((item) => AiPetCareReport.fromStoredJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiPetCareReport>[],
      promptPayloadVersion:
          _optionalString(json['promptPayloadVersion']) ?? 'full',
      promptPayloadVersionLabel:
          _optionalString(json['promptPayloadVersionLabel']) ?? '所有数据',
      statusLabel: _optionalString(json['statusLabel']) ?? '',
      oneLineSummary: _optionalString(json['oneLineSummary']) ?? '',
      recommendationRankings: rawRecommendationRankings is List
          ? rawRecommendationRankings
              .whereType<Map>()
              .map((item) => AiRecommendationRanking.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiRecommendationRanking>[],
    );
  }
}

class AiVisitSummary {
  const AiVisitSummary({
    required this.visitReason,
    required this.timeline,
    required this.medicationsAndTreatments,
    required this.testsAndResults,
    required this.questionsToAskVet,
  });

  final String visitReason;
  final List<String> timeline;
  final List<String> medicationsAndTreatments;
  final List<String> testsAndResults;
  final List<String> questionsToAskVet;

  factory AiVisitSummary.fromJson(Map<String, dynamic> json) {
    return AiVisitSummary(
      visitReason: _requiredString(json, 'visitReason'),
      timeline: _stringList(json['timeline']),
      medicationsAndTreatments: _stringList(json['medicationsAndTreatments']),
      testsAndResults: _stringList(json['testsAndResults']),
      questionsToAskVet: _stringList(json['questionsToAskVet']),
    );
  }
}

class AiGenerationException implements Exception {
  const AiGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _compactText(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength)}…';
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null || value.isEmpty) {
    throw AiGenerationException('AI 返回的结构化结果缺少 $key。');
  }
  return value;
}

String aiStatusLabelForScore(int score) {
  if (score >= 90) {
    return '状态不错';
  }
  if (score >= 80) {
    return '状态还行';
  }
  if (score >= 70) {
    return '需要关注';
  }
  if (score >= 60) {
    return '急需关注';
  }
  return '存在隐患';
}

AiScoreConfidence _aiScoreConfidenceFromName(String? value) {
  return switch (value) {
    'low' => AiScoreConfidence.low,
    'high' => AiScoreConfidence.high,
    _ => AiScoreConfidence.medium,
  };
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value.clamp(0, 100);
  }
  if (value is num) {
    return value.round().clamp(0, 100);
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    return parsed?.clamp(0, 100);
  }
  return null;
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = _optionalString(json[key]);
    if (value != null) {
      return value;
    }
  }
  if (fallback.isNotEmpty) {
    return fallback;
  }
  throw AiGenerationException('AI 返回的结构化结果缺少 ${keys.first}。');
}

List<String> _firstStringList(
  Map<String, dynamic> json,
  List<String> keys, {
  List<String>? fallback,
}) {
  for (final key in keys) {
    final value = _stringList(json[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback ?? const <String>[];
}

List<AiRecommendationRanking> _recommendationRankings(
  Map<String, dynamic> json,
) {
  final rawItems = json['recommendationRankings'];
  if (rawItems is! List) {
    return const <AiRecommendationRanking>[];
  }
  return rawItems
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .map(AiRecommendationRanking.fromJson)
      .toList(growable: false);
}

List<String> _requiredStringList(Map<String, dynamic> json, String key) {
  final value = _stringList(json[key]);
  if (value.isEmpty) {
    throw AiGenerationException('AI 返回的结构化结果缺少 $key。');
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value is String ? value.trim() : null;
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
