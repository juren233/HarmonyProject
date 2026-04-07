import 'package:flutter_test/flutter_test.dart';
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
      expect(reloaded.pets.single.breed, '英短');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.neutered);
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
      expect(reloaded.pets.single.breed, '柯基');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.notNeutered);
      expect(reloaded.pets.single.note, '喜欢追球');
    });

    test('dismissing first-launch intro persists auto-show disabled', () async {
      final store = await PetNoteStore.load();

      await store.dismissFirstLaunchIntro();

      final reloaded = await PetNoteStore.load();
      expect(reloaded.shouldAutoShowFirstLaunchIntro, isFalse);
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
