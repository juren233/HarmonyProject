import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

void main() {
  group('PetCareStore', () {
    test('seeded store exposes three checklist sections', () {
      final store = PetCareStore.seeded();

      expect(store.checklistSections.length, 3);
      expect(store.checklistSections.first.title, '今日待办');
    });

    test('marking a checklist item done removes it from open checklist grouping', () {
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
