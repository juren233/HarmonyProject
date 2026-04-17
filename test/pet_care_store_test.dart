import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PetNoteStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'load with empty preferences starts with no pets and auto intro enabled',
        () async {
      final store = await PetNoteStore.load();

      expect(store.pets, isEmpty);
      expect(store.shouldAutoShowFirstLaunchIntro, isTrue);
      expect(store.checklistSections.length, 5);
    });

    test('adding a pet persists its typed profile fields', () async {
      final store = await PetNoteStore.load();

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        photoPath: '/tmp/mochi.png',
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final reloaded = await PetNoteStore.load();

      expect(reloaded.pets, hasLength(1));
      expect(reloaded.pets.single.name, 'Mochi');
      expect(reloaded.pets.single.type, PetType.cat);
      expect(reloaded.pets.single.photoPath, '/tmp/mochi.png');
      expect(reloaded.pets.single.breed, '英短');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.neutered);
    });

    test('adding and updating a pet persists its photo path', () async {
      final store = await PetNoteStore.load();

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        photoPath: '/tmp/mochi.png',
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      var reloaded = await PetNoteStore.load();

      expect(reloaded.pets.single.photoPath, '/tmp/mochi.png');

      await reloaded.updatePet(
        petId: reloaded.pets.single.id,
        name: 'Mochi',
        type: PetType.cat,
        photoPath: null,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      reloaded = await PetNoteStore.load();

      expect(reloaded.pets.single.photoPath, isNull);
    });

    test('notification sync version changes only when schedulable data changes',
        () async {
      final store = await PetNoteStore.load();

      expect(store.notificationSyncVersion, 0);
      store.setActiveTab(AppTab.overview);
      expect(store.notificationSyncVersion, 0);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      expect(store.notificationSyncVersion, 0);

      await store.addTodo(
        title: '补主粮',
        petId: store.pets.single.id,
        dueAt: DateTime.parse('2026-03-28T09:00:00+08:00'),
        note: '低敏',
      );
      expect(store.notificationSyncVersion, 1);

      await store.postponeChecklist('todo', store.todos.single.id);
      expect(store.notificationSyncVersion, 2);
    });

    test('adding todo reminder and record persists all non-pet data', () async {
      final store = await PetNoteStore.load();

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      await store.addTodo(
        title: '补主粮',
        petId: petId,
        dueAt: DateTime.parse('2026-03-28T09:00:00+08:00'),
        note: '低敏',
      );
      await store.addReminder(
        title: '驱虫',
        petId: petId,
        scheduledAt: DateTime.parse('2026-03-29T10:30:00+08:00'),
        kind: ReminderKind.deworming,
        recurrence: '每月',
        note: '饭后',
      );
      await store.addRecord(
        petId: petId,
        type: PetRecordType.medical,
        title: '门诊记录',
        recordDate: DateTime.parse('2026-03-27T14:00:00+08:00'),
        summary: '恢复正常',
        note: '继续观察',
      );

      final reloaded = await PetNoteStore.load();

      expect(reloaded.todos, hasLength(1));
      expect(reloaded.todos.single.title, '补主粮');
      expect(reloaded.reminders, hasLength(1));
      expect(reloaded.reminders.single.title, '驱虫');
      expect(reloaded.records, hasLength(1));
      expect(reloaded.records.single.title, '门诊记录');
    });

    test('updating a pet persists edited profile fields', () async {
      final store = await PetNoteStore.load();
      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      await store.updatePet(
        petId: store.pets.single.id,
        name: 'Tofu',
        type: PetType.dog,
        photoPath: '/tmp/tofu.png',
        breed: '柯基',
        sex: '公',
        birthday: '2023-11-01',
        weightKg: 8.5,
        neuterStatus: PetNeuterStatus.notNeutered,
        feedingPreferences: '一天两餐',
        allergies: '牛肉敏感',
        note: '喜欢追球',
      );

      final reloaded = await PetNoteStore.load();

      expect(reloaded.pets, hasLength(1));
      expect(reloaded.pets.single.name, 'Tofu');
      expect(reloaded.pets.single.type, PetType.dog);
      expect(reloaded.pets.single.photoPath, '/tmp/tofu.png');
      expect(reloaded.pets.single.breed, '柯基');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.notNeutered);
      expect(reloaded.pets.single.note, '喜欢追球');
    });

    test('legacy pet json without photoPath still loads successfully', () {
      final pet = Pet.fromJson(<String, Object?>{
        'id': 'pet-legacy-1',
        'name': 'Luna',
        'avatarText': 'LU',
        'type': 'cat',
        'breed': '英短',
        'sex': '母',
        'birthday': '2024-01-15',
        'ageLabel': '新加入',
        'weightKg': 4.2,
        'neuterStatus': 'neutered',
        'feedingPreferences': '未填写',
        'allergies': '未填写',
        'note': '未填写',
      });

      expect(pet.photoPath, isNull);
      expect(pet.name, 'Luna');
    });

    test('dismissing first-launch intro persists auto-show disabled', () async {
      final store = await PetNoteStore.load();

      await store.dismissFirstLaunchIntro();

      final reloaded = await PetNoteStore.load();
      expect(reloaded.shouldAutoShowFirstLaunchIntro, isFalse);
    });

    test('generated overview report and analysis config persist after reload',
        () async {
      final store = await PetNoteStore.load();

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      store.updateOverviewAnalysisConfig(
        range: OverviewRange.oneMonth,
        selectedPetIds: [petId],
      );

      await store.generateOverviewAiReport(
        (context, {forceRefresh = false}) async => _buildTestAiCareReport(
          petId: petId,
          petName: 'Mochi',
        ),
      );

      final reloaded = await PetNoteStore.load();

      expect(reloaded.overviewRange, OverviewRange.oneMonth);
      expect(reloaded.overviewSelectedPetIds, [petId]);
      expect(reloaded.overviewAiReportState.hasReport, isTrue);
      expect(reloaded.overviewAiReportState.report?.overallScore, 86);
      expect(reloaded.overviewAiReportState.report?.statusLabel, '基本稳定');
      expect(reloaded.overviewAiReportState.report?.oneLineSummary,
          'Mochi 的照护节奏基本稳定，下一步先补齐周期检查。');
    });

    test('overview report is cleared after related data changes and reload',
        () async {
      final store = await PetNoteStore.load();

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      await store.generateOverviewAiReport(
        (context, {forceRefresh = false}) async => _buildTestAiCareReport(
          petId: petId,
          petName: 'Mochi',
        ),
      );

      await store.addRecord(
        petId: petId,
        type: PetRecordType.medical,
        title: '新增复查',
        recordDate: DateTime.parse('2026-03-30T14:00:00+08:00'),
        summary: '补了一次复查记录',
        note: '这次应该让旧总览失效',
      );

      final reloaded = await PetNoteStore.load();

      expect(reloaded.overviewAiReportState.hasReport, isFalse);
    });

    test('load falls back to in-memory mode when preferences are unavailable',
        () async {
      final store = await PetNoteStore.load(
        preferencesLoader: () async => throw Exception('plugin unavailable'),
      );

      expect(store.pets, isEmpty);
      expect(store.shouldAutoShowFirstLaunchIntro, isTrue);
    });

    test('seeded store exposes five checklist sections', () {
      final store = PetNoteStore.seeded();

      expect(store.checklistSections.length, 5);
      expect(store.checklistSections.first.title, '今日待办');
      expect(store.checklistSections[3].title, '已延后');
      expect(store.checklistSections[4].title, '已跳过');
    });

    test(
        'marking a checklist item done removes it from open checklist grouping',
        () {
      final store = PetNoteStore.seeded();
      final firstItem = store.checklistSections.first.items.first;

      store.markChecklistDone(firstItem.sourceType, firstItem.id);

      final ids = store.checklistSections
          .expand((section) => section.items)
          .map((item) => item.id)
          .toList();
      expect(ids.contains(firstItem.id), isFalse);
    });

    test('overview snapshot excludes todos and reminders beyond range end',
        () async {
      final now = DateTime.parse('2026-04-17T12:00:00+08:00');
      final store = await PetNoteStore.load(nowProvider: () => now);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      store.updateOverviewAnalysisConfig(
        range: OverviewRange.sevenDays,
        selectedPetIds: [petId],
      );
      await store.addTodo(
        title: '区间内待办',
        petId: petId,
        dueAt: now.subtract(const Duration(days: 1)),
        note: '应该被纳入总览',
      );
      await store.addTodo(
        title: '未来待办',
        petId: petId,
        dueAt: now.add(const Duration(days: 30)),
        note: '不应该进入最近 7 天总览',
      );
      await store.addReminder(
        title: '区间内提醒',
        petId: petId,
        scheduledAt: now.subtract(const Duration(hours: 12)),
        kind: ReminderKind.custom,
        recurrence: '一次',
        note: '应该被纳入总览',
      );
      await store.addReminder(
        title: '未来提醒',
        petId: petId,
        scheduledAt: now.add(const Duration(days: 14)),
        kind: ReminderKind.custom,
        recurrence: '一次',
        note: '不应该进入最近 7 天总览',
      );

      final summaryItems = store.overviewSnapshot.sections
          .firstWhere((section) => section.title == '关键变化')
          .items;
      final generationContext = store.buildOverviewAiGenerationContext();

      expect(summaryItems, contains('待办 1 条，提醒 1 条，日常照护节奏已经形成。'));
      expect(generationContext.todos.map((item) => item.title), ['区间内待办']);
      expect(
        generationContext.reminders.map((item) => item.title),
        ['区间内提醒'],
      );
    });

    test('overview custom range includes records through the selected end date',
        () async {
      final now = DateTime.parse('2026-04-17T12:00:00+08:00');
      final store = await PetNoteStore.load(nowProvider: () => now);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      store.updateOverviewAnalysisConfig(
        range: OverviewRange.custom,
        selectedPetIds: [petId],
        customRangeStart: DateTime.parse('2026-04-17T00:00:00+08:00'),
        customRangeEnd: DateTime.parse('2026-04-17T00:00:00+08:00'),
      );
      await store.addRecord(
        petId: petId,
        type: PetRecordType.medical,
        title: '当天复查',
        recordDate: DateTime.parse('2026-04-17T18:30:00+08:00'),
        summary: '应该被自定义结束日纳入',
        note: '结束日当天晚上',
      );

      final summaryItems = store.overviewSnapshot.sections
          .firstWhere((section) => section.title == '关键变化')
          .items;
      final generationContext = store.buildOverviewAiGenerationContext();

      expect(summaryItems, contains('最近新增 1 条资料记录，覆盖 1 只爱宠。'));
      expect(generationContext.records.map((item) => item.title), ['当天复查']);
    });

    test('overview risk summary counts effective overdue todos', () async {
      final now = DateTime.parse('2026-04-17T12:00:00+08:00');
      final store = await PetNoteStore.load(nowProvider: () => now);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      final petId = store.pets.single.id;
      await store.addTodo(
        title: '昨天该做的清洁',
        petId: petId,
        dueAt: DateTime.parse('2026-04-16T09:00:00+08:00'),
        note: '状态仍是 open，但已经逾期',
      );

      final riskItems = store.overviewSnapshot.sections
          .firstWhere((section) => section.title == '风险提醒')
          .items;
      final observationItems = store.overviewSnapshot.sections
          .firstWhere((section) => section.title == '照护观察')
          .items;

      expect(riskItems, contains('有 1 条待办已逾期，建议尽快回到清单页处理。'));
      expect(observationItems, contains('当前逾期待办 1 条，需要优先处理。'));
    });
    test('overview snapshot contains four report sections', () {
      final store = PetNoteStore.seeded();

      expect(store.overviewSnapshot.sections.length, 4);
      expect(store.overviewSnapshot.disclaimer, isNotEmpty);
    });

    test('postponing a checklist item moves it into postponed section',
        () async {
      final store = PetNoteStore.seeded();
      final todayItem = store.checklistSections
          .firstWhere((section) => section.key == 'today')
          .items
          .firstWhere((item) => item.sourceType == 'todo');

      await store.postponeChecklist(todayItem.sourceType, todayItem.id);

      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'postponed')
            .items
            .map((item) => item.id),
        contains(todayItem.id),
      );
      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'today')
            .items
            .map((item) => item.id),
        isNot(contains(todayItem.id)),
      );
    });

    test('skipping a checklist item moves it into skipped section', () async {
      final store = PetNoteStore.seeded();
      final upcomingItem = store.checklistSections
          .firstWhere((section) => section.key == 'upcoming')
          .items
          .firstWhere((item) => item.sourceType == 'reminder');

      await store.skipChecklist(upcomingItem.sourceType, upcomingItem.id);

      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'skipped')
            .items
            .map((item) => item.id),
        contains(upcomingItem.id),
      );
      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'upcoming')
            .items
            .map((item) => item.id),
        isNot(contains(upcomingItem.id)),
      );
    });

    test(
        'same-day reminders appear in today and move to overdue after time passes',
        () async {
      DateTime now = DateTime.parse('2026-03-27T10:00:00+08:00');
      final store = await PetNoteStore.load(nowProvider: () => now);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '未填写',
        allergies: '未填写',
        note: '未填写',
      );

      await store.addReminder(
        title: '当天提醒',
        petId: store.pets.single.id,
        scheduledAt: DateTime.parse('2026-03-27T18:00:00+08:00'),
        kind: ReminderKind.custom,
        recurrence: '单次',
        note: '',
      );

      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'today')
            .items
            .map((item) => item.title),
        contains('当天提醒'),
      );

      now = DateTime.parse('2026-03-27T18:30:00+08:00');

      expect(
        store.checklistSections
            .firstWhere((section) => section.key == 'overdue')
            .items
            .map((item) => item.title),
        contains('当天提醒'),
      );
    });
  });
}

AiCareReport _buildTestAiCareReport({
  required String petId,
  required String petName,
}) {
  return AiCareReport(
    overallScore: 86,
    overallScoreLabel: '基本稳定',
    scoreConfidence: AiScoreConfidence.medium,
    scoreBreakdown: const [
      AiScoreDimension(
        key: 'records',
        label: '记录完整度',
        score: 84,
        reason: '关键记录基本齐全。',
      ),
    ],
    scoreReasons: const ['最近有持续记录，但周期性检查仍有补齐空间。'],
    executiveSummary: '最近一个月的照护执行较稳定，但仍需补齐周期性检查。',
    overallAssessment: const ['整体稳定，建议继续跟进复查节奏。'],
    keyFindings: const ['近期没有新的异常记录，但仍存在待补检查。'],
    trendAnalysis: const ['记录频率稳定，提醒执行有轻微延迟。'],
    riskAssessment: const ['若继续缺少复查，后续风险会被放大。'],
    priorityActions: const ['本周内安排一次复查并同步记录结果。'],
    dataQualityNotes: const ['部分提醒缺少明确完成说明。'],
    perPetReports: [
      AiPetCareReport(
        petId: petId,
        petName: petName,
        score: 84,
        scoreLabel: '基本稳定',
        scoreConfidence: AiScoreConfidence.medium,
        summary: '$petName 近期整体稳定，但复查安排还不够积极。',
        careFocus: '补齐本周期检查并保持记录连续。',
        keyEvents: const ['近 30 天内有常规照护记录。'],
        trendAnalysis: const ['日常照护平稳，暂无明显恶化趋势。'],
        riskAssessment: const ['周期性检查缺口会放大潜在问题。'],
        recommendedActions: const ['安排一次复查。'],
        followUpFocus: '确认复查是否按期完成。',
        statusLabel: '基本稳定',
        whyThisScore: const ['基础照护在做，但复查节奏不够主动。'],
        topPriority: const ['先把复查安排落地。'],
        missedItems: const ['缺少最近一次复查记录。'],
        recentChanges: const ['最近新增了一条常规照护记录。'],
        followUpPlan: const ['复查完成后补记录并观察 7 天。'],
      ),
    ],
    statusLabel: '基本稳定',
    oneLineSummary: '$petName 的照护节奏基本稳定，下一步先补齐周期检查。',
    recommendationRankings: [
      AiRecommendationRanking(
        rank: 1,
        kind: 'follow_up',
        petIds: [petId],
        petNames: [petName],
        title: '优先补齐复查',
        summary: '$petName 当前最需要的是补一次周期性复查。',
        suggestedAction: '本周内预约复查并补全记录。',
      ),
    ],
  );
}
