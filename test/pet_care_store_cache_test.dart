import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  group('PetNoteStore derived data caching', () {
    test('memoizes checklist sections until checklist data changes', () {
      final store = PetNoteStore.seeded();

      final first = store.checklistSections;
      final second = store.checklistSections;

      expect(identical(first, second), isTrue);

      final item = first
          .expand((section) => section.items)
          .firstWhere((entry) => entry.sourceType == 'todo');
      store.markChecklistDone(item.sourceType, item.id);

      final third = store.checklistSections;
      expect(identical(first, third), isFalse);
    });

    test('memoizes overview snapshot until overview inputs change', () {
      final store = PetNoteStore.seeded();

      final first = store.overviewSnapshot;
      final second = store.overviewSnapshot;

      expect(identical(first, second), isTrue);

      store.setOverviewRange(OverviewRange.oneMonth);

      final third = store.overviewSnapshot;
      expect(identical(first, third), isFalse);
    });

    test('memoizes selected pet reminders until selected pet changes', () {
      final store = PetNoteStore.seeded();

      final first = store.remindersForSelectedPet;
      final second = store.remindersForSelectedPet;

      expect(identical(first, second), isTrue);

      store.selectPet('pet-2');

      final third = store.remindersForSelectedPet;
      expect(identical(first, third), isFalse);
    });

    test('memoizes selected pet records until record data changes', () {
      final store = PetNoteStore.seeded();

      final first = store.recordsForSelectedPet;
      final second = store.recordsForSelectedPet;

      expect(identical(first, second), isTrue);

      store.addRecord(
        petId: 'pet-1',
        type: PetRecordType.other,
        title: '新记录',
        recordDate: DateTime.parse('2026-03-24T20:00:00+08:00'),
        summary: '摘要',
        note: '备注',
      );

      final third = store.recordsForSelectedPet;
      expect(identical(first, third), isFalse);
    });
  });
}
