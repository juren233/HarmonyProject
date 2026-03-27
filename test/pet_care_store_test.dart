import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PetCareStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'load with empty preferences starts with no pets and auto intro enabled',
        () async {
      final store = await PetCareStore.load();

      expect(store.pets, isEmpty);
      expect(store.shouldAutoShowFirstLaunchIntro, isTrue);
      expect(store.checklistSections.length, 3);
    });

    test('adding a pet persists its typed profile fields', () async {
      final store = await PetCareStore.load();

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

      final reloaded = await PetCareStore.load();

      expect(reloaded.pets, hasLength(1));
      expect(reloaded.pets.single.name, 'Mochi');
      expect(reloaded.pets.single.type, PetType.cat);
      expect(reloaded.pets.single.breed, '英短');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.neutered);
    });

    test('updating a pet persists edited profile fields', () async {
      final store = await PetCareStore.load();
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

      final reloaded = await PetCareStore.load();

      expect(reloaded.pets, hasLength(1));
      expect(reloaded.pets.single.name, 'Tofu');
      expect(reloaded.pets.single.type, PetType.dog);
      expect(reloaded.pets.single.breed, '柯基');
      expect(reloaded.pets.single.neuterStatus, PetNeuterStatus.notNeutered);
      expect(reloaded.pets.single.note, '喜欢追球');
    });

    test('dismissing first-launch intro persists auto-show disabled', () async {
      final store = await PetCareStore.load();

      await store.dismissFirstLaunchIntro();

      final reloaded = await PetCareStore.load();
      expect(reloaded.shouldAutoShowFirstLaunchIntro, isFalse);
    });

    test('load falls back to in-memory mode when preferences are unavailable',
        () async {
      final store = await PetCareStore.load(
        preferencesLoader: () async => throw Exception('plugin unavailable'),
      );

      expect(store.pets, isEmpty);
      expect(store.shouldAutoShowFirstLaunchIntro, isTrue);
    });

    test('seeded store exposes three checklist sections', () {
      final store = PetCareStore.seeded();

      expect(store.checklistSections.length, 3);
      expect(store.checklistSections.first.title, '今日待办');
    });

    test(
        'marking a checklist item done removes it from open checklist grouping',
        () {
      final store = PetCareStore.seeded();
      final firstItem = store.checklistSections.first.items.first;

      store.markChecklistDone(firstItem.sourceType, firstItem.id);

      final ids = store.checklistSections
          .expand((section) => section.items)
          .map((item) => item.id)
          .toList();
      expect(ids.contains(firstItem.id), isFalse);
    });

    test('overview snapshot contains four report sections', () {
      final store = PetCareStore.seeded();

      expect(store.overviewSnapshot.sections.length, 4);
      expect(store.overviewSnapshot.disclaimer, isNotEmpty);
    });
  });
}
