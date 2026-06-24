import 'dart:math' as math;

import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/state/petnote_store.dart';

class AiCareScorecardBuilder {
  const AiCareScorecardBuilder();

  static const List<_DimensionSpec> _dimensions = [
    _DimensionSpec('taskExecution', '执行完成度'),
    _DimensionSpec('reminderFollowThrough', '提醒跟进度'),
    _DimensionSpec('recordCompleteness', '记录完整度'),
    _DimensionSpec('stabilityRisk', '稳定性与风险'),
  ];

  AiCareScorecard build(AiGenerationContext context) {
    final petScorecards = context.pets
        .map((pet) => _buildPetScorecard(context, pet))
        .toList(growable: false);

    if (petScorecards.isEmpty) {
      return const AiCareScorecard(
        overallScore: 0,
        overallScoreLabel: '暂无样本',
        scoreConfidence: AiScoreConfidence.low,
        scoreBreakdown: [],
        scoreReasons: ['当前区间暂无可评分数据。'],
        riskCandidates: [],
        dataQualityNotes: ['当前区间样本不足，暂不建议依赖 AI 评分。'],
        petScorecards: [],
        totalTodos: 0,
        totalReminders: 0,
        totalRecords: 0,
      );
    }

    final overallBreakdown = _dimensions.map((dimension) {
      final matching = petScorecards
          .map(
            (scorecard) => scorecard.scoreBreakdown.firstWhere(
              (item) => item.key == dimension.key,
            ),
          )
          .toList(growable: false);
      final score = _average(matching.map((item) => item.score));
      final reason = _summarizeDimensionReason(
        dimension.label,
        score,
        matching.map((item) => item.reason).toList(growable: false),
      );
      return AiScoreDimension(
        key: dimension.key,
        label: dimension.label,
        score: score,
        reason: reason,
      );
    }).toList(growable: false);

    final overallScore = _average(
      petScorecards.map((scorecard) => scorecard.overallScore),
    );
    final overallConfidence = _confidenceForSample(
      context.todos.length + context.reminders.length + context.records.length,
      context.pets.length,
    );
    final riskCandidates = petScorecards
        .expand((item) => item.riskCandidates)
        .toSet()
        .toList(growable: false);
    final dataQualityNotes = _overallDataQualityNotes(
      context: context,
      confidence: overallConfidence,
      petScorecards: petScorecards,
    );
    final scoreReasons = <String>[
      '综合分基于执行完成度、提醒跟进度、记录完整度和稳定性与风险四个维度本地计算。',
      ...overallBreakdown.map(
        (item) => '${item.label}${item.score}分：${item.reason}',
      ),
    ];

    return AiCareScorecard(
      overallScore: overallScore,
      overallScoreLabel: _scoreLabel(overallScore),
      scoreConfidence: overallConfidence,
      scoreBreakdown: overallBreakdown,
      scoreReasons: scoreReasons,
      riskCandidates: riskCandidates,
      dataQualityNotes: dataQualityNotes,
      petScorecards: petScorecards,
      totalTodos: context.todos.length,
      totalReminders: context.reminders.length,
      totalRecords: context.records.length,
    );
  }

  AiPetCareScorecard _buildPetScorecard(AiGenerationContext context, Pet pet) {
    final todos = context.todos.where((item) => item.petId == pet.id).toList();
    final reminders =
        context.reminders.where((item) => item.petId == pet.id).toList();
    final records = context.records
        .where((item) => item.petId == pet.id)
        .toList(growable: false)
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));

    final dimensions = <AiScoreDimension>[
      _taskDimension(todos, context.referenceNow),
      _reminderDimension(reminders, context.referenceNow),
      _recordDimension(context, records),
      _stabilityDimension(todos, reminders, records, context.referenceNow),
    ];
    final overallScore =
        dimensions.fold<int>(0, (sum, item) => sum + item.score);
    final eventCount = todos.length + reminders.length + records.length;
    final confidence = _confidenceForSample(eventCount, 1);
    final riskCandidates = _petRiskCandidates(
      pet,
      todos,
      reminders,
      records,
      context.referenceNow,
    );
    final dataQualityNotes = _petDataQualityNotes(
      pet: pet,
      records: records,
      confidence: confidence,
      eventCount: eventCount,
    );
    final scoreReasons = dimensions
        .map((item) => '${item.label}${item.score}分：${item.reason}')
        .toList(growable: false);
    final recentEventTitles = [
      ...records.take(2).map((item) => item.title),
      ...todos.take(1).map((item) => item.title),
      ...reminders.take(1).map((item) => item.title),
    ].where((item) => item.trim().isNotEmpty).take(3).toList(growable: false);

    return AiPetCareScorecard(
      petId: pet.id,
      petName: pet.name,
      overallScore: overallScore,
      overallScoreLabel: _scoreLabel(overallScore),
      scoreConfidence: confidence,
      scoreBreakdown: dimensions,
      scoreReasons: scoreReasons,
      riskCandidates: riskCandidates,
      dataQualityNotes: dataQualityNotes,
      recentEventTitles: recentEventTitles,
    );
  }

  AiScoreDimension _taskDimension(
    List<TodoItem> todos,
    DateTime referenceNow,
  ) {
    if (todos.isEmpty) {
      return const AiScoreDimension(
        key: 'taskExecution',
        label: '执行完成度',
        score: 18,
        reason: '当前周期待办样本较少，执行表现只能做保守判断。',
      );
    }
    final done = todos.where((item) => item.status == TodoStatus.done).length;
    final overdue =
        todos.where((item) => _isTodoOverdue(item, referenceNow)).length;
    final skipped =
        todos.where((item) => item.status == TodoStatus.skipped).length;
    final postponed =
        todos.where((item) => item.status == TodoStatus.postponed).length;
    final futureOpen = todos
        .where(
          (item) =>
              item.status == TodoStatus.open &&
              item.dueAt.isAfter(referenceNow),
        )
        .length;

    var score = 25 - overdue * 7 - skipped * 6 - postponed * 3;
    score += math.min(done * 2, 4);
    score = score.clamp(0, 25);

    final reason = overdue > 0 || skipped > 0
        ? '当前仍有$overdue条逾期、$skipped条跳过和$postponed条延后待办，执行闭环需要加强。'
        : futureOpen > 0
            ? '待办整体执行顺畅，未来待办$futureOpen条已排入时间线，当前没有明显逾期。'
            : '待办整体执行顺畅，已完成$done条，当前没有明显逾期。';
    return AiScoreDimension(
      key: 'taskExecution',
      label: '执行完成度',
      score: score,
      reason: reason,
    );
  }

  AiScoreDimension _reminderDimension(
    List<ReminderItem> reminders,
    DateTime referenceNow,
  ) {
    if (reminders.isEmpty) {
      return const AiScoreDimension(
        key: 'reminderFollowThrough',
        label: '提醒跟进度',
        score: 18,
        reason: '当前周期提醒样本较少，提醒跟进情况以保守分呈现。',
      );
    }

    final done =
        reminders.where((item) => item.status == ReminderStatus.done).length;
    final overdue = reminders
        .where((item) => _isReminderOverdue(item, referenceNow))
        .length;
    final skipped =
        reminders.where((item) => item.status == ReminderStatus.skipped).length;
    final postponed = reminders
        .where((item) => item.status == ReminderStatus.postponed)
        .length;
    final futurePending = reminders
        .where(
          (item) =>
              item.status == ReminderStatus.pending &&
              item.scheduledAt.isAfter(referenceNow),
        )
        .length;

    var score = 25 - overdue * 7 - skipped * 5 - postponed * 3;
    score += math.min(done * 2, 4);
    score = score.clamp(0, 25);

    final reason = overdue > 0
        ? '提醒侧仍有$overdue条逾期，关键节点需要更及时跟进。'
        : futurePending > 0
            ? '提醒跟进整体稳定，未来提醒$futurePending条已排入时间线。'
            : '提醒跟进整体稳定，已完成$done条，关键节点处理较及时。';
    return AiScoreDimension(
      key: 'reminderFollowThrough',
      label: '提醒跟进度',
      score: score,
      reason: reason,
    );
  }

  AiScoreDimension _recordDimension(
    AiGenerationContext context,
    List<PetRecord> records,
  ) {
    if (records.isEmpty) {
      return const AiScoreDimension(
        key: 'recordCompleteness',
        label: '记录完整度',
        score: 8,
        reason: '当前周期缺少资料记录，AI 只能基于待办和提醒做有限判断。',
      );
    }

    var score = switch (records.length) {
      >= 3 => 25,
      2 => 21,
      1 => 16,
      _ => 8,
    };
    final latest = records.first.recordDate;
    final staleDays = context.rangeEnd.difference(latest).inDays;
    if (staleDays > 14) {
      score -= 4;
    }
    score = score.clamp(0, 25);

    final reason = staleDays > 14
        ? '虽然已有${records.length}条记录，但最近一次更新距离当前已$staleDays天，连续性一般。'
        : '当前周期已补充${records.length}条记录，且最近更新较新，记录完整度较好。';
    return AiScoreDimension(
      key: 'recordCompleteness',
      label: '记录完整度',
      score: score,
      reason: reason,
    );
  }

  AiScoreDimension _stabilityDimension(
    List<TodoItem> todos,
    List<ReminderItem> reminders,
    List<PetRecord> records,
    DateTime referenceNow,
  ) {
    final overdueTodos =
        todos.where((item) => _isTodoOverdue(item, referenceNow)).length;
    final overdueReminders = reminders
        .where((item) => _isReminderOverdue(item, referenceNow))
        .length;
    final skippedTodos =
        todos.where((item) => item.status == TodoStatus.skipped).length;
    final clinicalRecords = records
        .where(
          (item) =>
              item.type == PetRecordType.medical ||
              item.type == PetRecordType.testResult,
        )
        .length;

    var score = 25;
    if (overdueTodos + overdueReminders >= 2) {
      score -= 8;
    }
    if (skippedTodos > 0) {
      score -= 4;
    }
    if (clinicalRecords >= 3) {
      score -= 6;
    } else if (clinicalRecords == 2) {
      score -= 3;
    }
    if (records.isEmpty && (overdueTodos > 0 || overdueReminders > 0)) {
      score -= 4;
    }
    score = score.clamp(0, 25);

    final reason =
        score >= 20 ? '当前周期没有出现集中风险信号，整体稳定性较好。' : '存在逾期事项或复查压力，稳定性较弱，需要提高跟进频率。';
    return AiScoreDimension(
      key: 'stabilityRisk',
      label: '稳定性与风险',
      score: score,
      reason: reason,
    );
  }

  List<String> _petRiskCandidates(
    Pet pet,
    List<TodoItem> todos,
    List<ReminderItem> reminders,
    List<PetRecord> records,
    DateTime referenceNow,
  ) {
    final items = <String>[];
    final overdueTodos =
        todos.where((item) => _isTodoOverdue(item, referenceNow)).length;
    final overdueReminders = reminders
        .where((item) => _isReminderOverdue(item, referenceNow))
        .length;
    final skippedTodos =
        todos.where((item) => item.status == TodoStatus.skipped).length;
    final clinicalRecords = records
        .where(
          (item) =>
              item.type == PetRecordType.medical ||
              item.type == PetRecordType.testResult,
        )
        .length;

    if (overdueTodos > 0) {
      items.add('${pet.name} 当前有$overdueTodos条逾期待办。');
    }
    if (overdueReminders > 0) {
      items.add('${pet.name} 当前有$overdueReminders条逾期提醒。');
    }
    if (skippedTodos > 0) {
      items.add('${pet.name} 有$skippedTodos条任务被跳过。');
    }
    if (records.isEmpty) {
      items.add('${pet.name} 当前周期缺少资料记录。');
    }
    if (clinicalRecords >= 2) {
      items.add('${pet.name} 当前周期医疗/检查记录较多，建议持续观察。');
    }
    if (items.isEmpty) {
      items.add('${pet.name} 当前没有明显集中风险信号。');
    }
    return items;
  }

  bool _isTodoOverdue(TodoItem item, DateTime referenceNow) {
    if (item.status == TodoStatus.overdue) {
      return true;
    }
    return item.status == TodoStatus.open && item.dueAt.isBefore(referenceNow);
  }

  bool _isReminderOverdue(ReminderItem item, DateTime referenceNow) {
    if (item.status == ReminderStatus.overdue) {
      return true;
    }
    return item.status == ReminderStatus.pending &&
        item.scheduledAt.isBefore(referenceNow);
  }

  List<String> _petDataQualityNotes({
    required Pet pet,
    required List<PetRecord> records,
    required AiScoreConfidence confidence,
    required int eventCount,
  }) {
    final notes = <String>[];
    if (eventCount < 4) {
      notes.add('${pet.name} 当前周期样本偏少，结论仅供趋势参考。');
    } else {
      notes.add('${pet.name} 当前周期样本量达到基本分析要求。');
    }
    if (records.isEmpty) {
      notes.add('${pet.name} 缺少资料记录，建议补充客观观察。');
    }
    if (confidence == AiScoreConfidence.high) {
      notes.add('${pet.name} 当前评分可信度较高。');
    }
    return notes;
  }

  List<String> _overallDataQualityNotes({
    required AiGenerationContext context,
    required AiScoreConfidence confidence,
    required List<AiPetCareScorecard> petScorecards,
  }) {
    final notes = <String>[];
    final eventCount = context.todos.length +
        context.reminders.length +
        context.records.length;
    if (eventCount < context.pets.length * 2) {
      notes.add('当前周期样本不足，综合评分仅供方向性参考。');
    } else {
      notes.add('当前周期样本量达到基本分析要求，可用于生成专业总结。');
    }
    final missingRecordPets = petScorecards
        .where((item) =>
            item.dataQualityNotes.any((note) => note.contains('缺少资料记录')))
        .map((item) => item.petName)
        .toList(growable: false);
    if (missingRecordPets.isNotEmpty) {
      notes.add('以下宠物资料记录偏少：${missingRecordPets.join('、')}。');
    }
    notes.add('综合评分${aiScoreConfidenceLabel(confidence)}。');
    return notes;
  }

  AiScoreConfidence _confidenceForSample(int eventCount, int petCount) {
    if (eventCount < math.max(3, petCount * 2)) {
      return AiScoreConfidence.low;
    }
    if (eventCount < math.max(8, petCount * 5)) {
      return AiScoreConfidence.medium;
    }
    return AiScoreConfidence.high;
  }

  int _average(Iterable<int> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) {
      return 0;
    }
    final total = list.fold<int>(0, (sum, item) => sum + item);
    return (total / list.length).round();
  }

  String _scoreLabel(int score) {
    if (score >= 85) {
      return '稳定';
    }
    if (score >= 70) {
      return '可控';
    }
    if (score >= 55) {
      return '需关注';
    }
    return '风险偏高';
  }

  String _summarizeDimensionReason(
    String label,
    int score,
    List<String> reasons,
  ) {
    if (reasons.isEmpty) {
      return '$label暂无可用说明。';
    }
    if (score >= 20) {
      return reasons.first;
    }
    return reasons.last;
  }
}

class _DimensionSpec {
  const _DimensionSpec(this.key, this.label);

  final String key;
  final String label;
}
