import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('PetNoteStore performance guardrails', () {
    test('database range slices avoid materializing full record tables',
        () async {
      final storage = await PetNoteLocalStorage.loadDatabase(
        databaseFactory: databaseFactoryMemory,
        databasePath: 'petnote-performance-slice-test.db',
      );
      expect(storage?.backend, PetNoteLocalStorageBackend.database);

      final rows = List<Map<String, Object?>>.generate(6000, (index) {
        final inActiveRange = index % 600 == 0;
        final date = inActiveRange
            ? DateTime(2026, 3, 10, 12, index % 60)
            : DateTime(2025, 1, 1, 12, index % 60);
        return <String, Object?>{
          'id': 'record-$index',
          'petId': 'pet-1',
          'type': 'medical',
          'title': inActiveRange ? '区间内记录 $index' : '历史记录 $index',
          'recordDate': date.toIso8601String(),
          'summary': 'summary-$index',
          'note': 'note-$index',
        };
      });
      await storage!.writeEntityTable(PetNoteLocalTable.records, rows);

      final fullWatch = Stopwatch()..start();
      final fullRows = storage.readEntityTable(PetNoteLocalTable.records)!;
      fullWatch.stop();

      final sliceWatch = Stopwatch()..start();
      final sliceRows = storage.readEntityTableSlice(
        PetNoteLocalTable.records,
        petIds: {'pet-1'},
        start: DateTime(2026, 3),
        end: DateTime(2026, 3, 31, 23, 59, 59),
      )!;
      sliceWatch.stop();

      // 断言聚焦在避免的工作量，不绑定墙钟耗时：CI 计时会波动，
      // 但数据量缩减才是这次优化的性能契约。
      expect(fullRows, hasLength(6000));
      expect(sliceRows, hasLength(10));
      expect(sliceRows.length, lessThan(fullRows.length ~/ 100));
      expect(
        storage.debugEntitySliceReadCounts[PetNoteLocalTable.records],
        1,
      );
      // 输出耗时作为本地验证证据，但不让测试因机器性能波动而变脆。
      // ignore: avoid_print
      print(
        'PetNote performance probe: full=${fullWatch.elapsedMicroseconds}us '
        'slice=${sliceWatch.elapsedMicroseconds}us '
        'rows=${fullRows.length}->${sliceRows.length}',
      );
    });
  });
}
