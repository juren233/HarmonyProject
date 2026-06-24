import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_care_scorecard_builder.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  test('scorecard builder gives high score to stable well-tracked care', () {
    final scorecard = const AiCareScorecardBuilder().build(_stableContext());

    expect(scorecard.overallScore, greaterThanOrEqualTo(75));
    expect(scorecard.scoreConfidence, isNot(AiScoreConfidence.low));
    expect(
        scorecard.petScorecards.single.overallScore, greaterThanOrEqualTo(75));
  });

  test('scorecard builder treats future todos and reminders as planned items',
      () {
    final scorecard =
        const AiCareScorecardBuilder().build(_futureTimelineContext());
    final taskDimension = scorecard.scoreBreakdown
        .firstWhere((item) => item.key == 'taskExecution');
    final reminderDimension = scorecard.scoreBreakdown
        .firstWhere((item) => item.key == 'reminderFollowThrough');

    expect(taskDimension.score, 25);
    expect(taskDimension.reason, contains('未来待办1条'));
    expect(reminderDimension.score, 25);
    expect(reminderDimension.reason, contains('未来提醒1条'));
    expect(scorecard.riskCandidates.join(' '), isNot(contains('逾期')));
  });

  test('scorecard builder penalizes overdue skipped and missing-record periods',
      () {
    final scorecard = const AiCareScorecardBuilder().build(_highRiskContext());

    expect(scorecard.overallScore, lessThan(60));
    expect(scorecard.riskCandidates, isNotEmpty);
    expect(scorecard.petScorecards.single.overallScore, lessThan(60));
  });

  test('scorecard builder lowers confidence when data is sparse', () {
    final scorecard = const AiCareScorecardBuilder().build(_sparseContext());

    expect(scorecard.scoreConfidence, AiScoreConfidence.low);
    expect(scorecard.dataQualityNotes.join(' '), contains('样本'));
  });

  test('scorecard builder changes result across different time windows', () {
    final shortRange = const AiCareScorecardBuilder().build(_stableContext());
    final longRange = const AiCareScorecardBuilder().build(_longRangeContext());

    expect(longRange.overallScore, isNot(shortRange.overallScore));
  });
}

AiGenerationContext _stableContext() {
  return AiGenerationContext(
    title: '最近 7 天的总结',
    rangeLabel: '最近 7 天',
    rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [_pet()],
    todos: [
      TodoItem(
        id: 'todo-1',
        petId: 'pet-1',
        title: '补充饮食记录',
        dueAt: DateTime.parse('2026-04-07T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.done,
        note: '',
      ),
      TodoItem(
        id: 'todo-2',
        petId: 'pet-1',
        title: '环境清洁',
        dueAt: DateTime.parse('2026-04-08T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.done,
        note: '',
      ),
    ],
    reminders: [
      ReminderItem(
        id: 'reminder-1',
        petId: 'pet-1',
        kind: ReminderKind.deworming,
        title: '驱虫',
        scheduledAt: DateTime.parse('2026-04-06T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '每月',
        status: ReminderStatus.done,
        note: '',
      ),
    ],
    records: [
      PetRecord(
        id: 'record-1',
        petId: 'pet-1',
        type: PetRecordType.medical,
        title: '状态观察',
        recordDate: DateTime.parse('2026-04-08T20:00:00+08:00'),
        summary: '状态稳定',
        note: '',
      ),
      PetRecord(
        id: 'record-2',
        petId: 'pet-1',
        type: PetRecordType.other,
        title: '饮食记录',
        recordDate: DateTime.parse('2026-04-05T20:00:00+08:00'),
        summary: '食欲稳定',
        note: '',
      ),
    ],
  );
}

AiGenerationContext _futureTimelineContext() {
  return AiGenerationContext(
    title: '未来 7 天的总结',
    rangeLabel: '未来 7 天',
    rangeStart: DateTime.parse('2026-04-09T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-16T23:59:59+08:00'),
    referenceNow: DateTime.parse('2026-04-09T10:00:00+08:00'),
    languageTag: 'zh-CN',
    pets: [_pet()],
    todos: [
      TodoItem(
        id: 'todo-future',
        petId: 'pet-1',
        title: '补充主粮',
        dueAt: DateTime.parse('2026-04-10T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.open,
        note: '',
      ),
    ],
    reminders: [
      ReminderItem(
        id: 'reminder-future',
        petId: 'pet-1',
        kind: ReminderKind.vaccine,
        title: '疫苗复查',
        scheduledAt: DateTime.parse('2026-04-11T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '单次',
        status: ReminderStatus.pending,
        note: '',
      ),
    ],
    records: [
      PetRecord(
        id: 'record-1',
        petId: 'pet-1',
        type: PetRecordType.other,
        title: '近期观察',
        recordDate: DateTime.parse('2026-04-09T08:00:00+08:00'),
        summary: '状态稳定',
        note: '',
      ),
    ],
  );
}

AiGenerationContext _highRiskContext() {
  return AiGenerationContext(
    title: '最近 1 个月的总结',
    rangeLabel: '最近 1 个月',
    rangeStart: DateTime.parse('2026-03-10T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [_pet()],
    todos: [
      TodoItem(
        id: 'todo-1',
        petId: 'pet-1',
        title: '体重跟踪',
        dueAt: DateTime.parse('2026-04-03T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.overdue,
        note: '',
      ),
      TodoItem(
        id: 'todo-2',
        petId: 'pet-1',
        title: '环境清洁',
        dueAt: DateTime.parse('2026-04-04T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.skipped,
        note: '',
      ),
    ],
    reminders: [
      ReminderItem(
        id: 'reminder-1',
        petId: 'pet-1',
        kind: ReminderKind.review,
        title: '复查',
        scheduledAt: DateTime.parse('2026-04-01T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '单次',
        status: ReminderStatus.overdue,
        note: '',
      ),
    ],
    records: const [],
  );
}

AiGenerationContext _sparseContext() {
  return AiGenerationContext(
    title: '最近 6 个月的总结',
    rangeLabel: '最近 6 个月',
    rangeStart: DateTime.parse('2025-10-10T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [_pet()],
    todos: const [],
    reminders: const [],
    records: const [],
  );
}

AiGenerationContext _longRangeContext() {
  return AiGenerationContext(
    title: '最近 6 个月的总结',
    rangeLabel: '最近 6 个月',
    rangeStart: DateTime.parse('2025-10-10T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [_pet()],
    todos: [
      TodoItem(
        id: 'todo-1',
        petId: 'pet-1',
        title: '补充饮食记录',
        dueAt: DateTime.parse('2026-01-07T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.done,
        note: '',
      ),
      TodoItem(
        id: 'todo-2',
        petId: 'pet-1',
        title: '环境清洁',
        dueAt: DateTime.parse('2026-03-08T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.postponed,
        note: '',
      ),
    ],
    reminders: [
      ReminderItem(
        id: 'reminder-1',
        petId: 'pet-1',
        kind: ReminderKind.deworming,
        title: '驱虫',
        scheduledAt: DateTime.parse('2026-02-06T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '每月',
        status: ReminderStatus.done,
        note: '',
      ),
    ],
    records: [
      PetRecord(
        id: 'record-1',
        petId: 'pet-1',
        type: PetRecordType.other,
        title: '阶段记录',
        recordDate: DateTime.parse('2026-01-10T20:00:00+08:00'),
        summary: '阶段性稳定',
        note: '',
      ),
    ],
  );
}

Pet _pet() {
  return Pet(
    id: 'pet-1',
    name: 'Mochi',
    avatarText: 'MO',
    type: PetType.cat,
    breed: '英短',
    sex: '母',
    birthday: '2024-02-12',
    ageLabel: '2岁',
    weightKg: 4.2,
    neuterStatus: PetNeuterStatus.neutered,
    feedingPreferences: '主粮+冻干',
    allergies: '鸡肉敏感',
    note: '偶尔紧张',
  );
}
