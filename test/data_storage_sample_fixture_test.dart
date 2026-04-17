import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final baseline = DateTime.parse('2026-04-09T23:59:59+08:00');

  Future<DataStorageCoordinator> createCoordinator() async {
    return DataStorageCoordinator(
      store: await PetNoteStore.load(),
      settingsController: await AppSettingsController.load(),
    );
  }

  Map<String, int> collectMonthBuckets(PetNoteDataPackage package) {
    final monthBuckets = <String, int>{};
    for (final item in package.data.todos) {
      final monthKey = '${item.dueAt.year.toString().padLeft(4, '0')}-'
          '${item.dueAt.month.toString().padLeft(2, '0')}';
      monthBuckets.update(monthKey, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final item in package.data.reminders) {
      final monthKey = '${item.scheduledAt.year.toString().padLeft(4, '0')}-'
          '${item.scheduledAt.month.toString().padLeft(2, '0')}';
      monthBuckets.update(monthKey, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final item in package.data.records) {
      final monthKey = '${item.recordDate.year.toString().padLeft(4, '0')}-'
          '${item.recordDate.month.toString().padLeft(2, '0')}';
      monthBuckets.update(monthKey, (count) => count + 1, ifAbsent: () => 1);
    }
    return monthBuckets;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sample backup fixture parses and passes coordinator validation',
      () async {
    final rawJson =
        File('docs/examples/petnote-ai-history-backup-3m.json')
            .readAsStringSync();
    final coordinator = await createCoordinator();

    final package = coordinator.parsePackageJson(rawJson);
    final monthBuckets = collectMonthBuckets(package);
    final futureTodos = package.data.todos
        .where((item) => item.dueAt.isAfter(baseline))
        .toList();
    final futureReminders = package.data.reminders
        .where((item) => item.scheduledAt.isAfter(baseline))
        .toList();
    final futureRecords = package.data.records
        .where((item) => item.recordDate.isAfter(baseline))
        .toList();

    expect(package.packageType, PetNoteDataPackageType.backup);
    expect(package.packageName, anyOf(contains('3个月'), contains('3 个月')));
    expect(package.data.pets, hasLength(1));
    expect(package.data.todos, hasLength(13));
    expect(package.data.reminders, hasLength(11));
    expect(package.data.records, hasLength(18));
    expect(package.settings?.aiProviderConfigs, isEmpty);
    expect(package.settings?.activeAiProviderConfigId, isNull);
    expect(coordinator.validatePackage(package), isNull);
    expect(
      package.data.todos.every((item) => item.petId == 'pet-mochi-01'),
      isTrue,
    );
    expect(
      package.data.reminders.every((item) => item.petId == 'pet-mochi-01'),
      isTrue,
    );
    expect(
      package.data.records.every((item) => item.petId == 'pet-mochi-01'),
      isTrue,
    );
    expect(monthBuckets.keys, hasLength(2));
    for (final month in <String>[
      '2026-03',
      '2026-04',
    ]) {
      expect(monthBuckets[month], isNotNull,
          reason: 'missing month bucket $month');
      expect(monthBuckets[month]! >= 20, isTrue,
          reason: 'month $month should have at least 20 items');
    }
    expect(futureTodos, isNotEmpty);
    expect(futureReminders, isNotEmpty);
    expect(futureRecords, isEmpty);
  });

  test('dual pet quarterly sample backup fixture parses and validates',
      () async {
    final rawJson =
        File('docs/examples/petnote-ai-quarterly-dual-pets-backup.json')
            .readAsStringSync();
    final coordinator = await createCoordinator();

    final package = coordinator.parsePackageJson(rawJson);
    final monthBuckets = collectMonthBuckets(package);
    final futureTodos = package.data.todos
        .where((item) => item.dueAt.isAfter(baseline))
        .toList();
    final futureReminders = package.data.reminders
        .where((item) => item.scheduledAt.isAfter(baseline))
        .toList();
    final futureRecords = package.data.records
        .where((item) => item.recordDate.isAfter(baseline))
        .toList();

    expect(package.packageType, PetNoteDataPackageType.backup);
    expect(package.packageName, contains('双宠 3 个月'));
    expect(package.data.pets, hasLength(2));
    expect(package.data.todos, hasLength(24));
    expect(package.data.reminders, hasLength(18));
    expect(package.data.records, hasLength(24));
    expect(package.settings?.aiProviderConfigs, isEmpty);
    expect(package.settings?.activeAiProviderConfigId, isNull);
    expect(coordinator.validatePackage(package), isNull);
    expect(
      package.data.todos.map((item) => item.petId).toSet(),
      equals({'pet-luna-01', 'pet-cocoa-02'}),
    );
    expect(
      package.data.reminders.map((item) => item.petId).toSet(),
      equals({'pet-luna-01', 'pet-cocoa-02'}),
    );
    expect(
      package.data.records.map((item) => item.petId).toSet(),
      equals({'pet-luna-01', 'pet-cocoa-02'}),
    );
    expect(monthBuckets.keys, hasLength(3));
    for (final month in <String>[
      '2026-02',
      '2026-03',
      '2026-04',
    ]) {
      expect(monthBuckets[month], isNotNull,
          reason: 'missing month bucket $month');
      expect(monthBuckets[month]! >= 20, isTrue,
          reason: 'month $month should have at least 20 items');
    }
    expect(futureTodos, hasLength(6));
    expect(futureReminders, hasLength(4));
    expect(futureRecords, isEmpty);
  });
}
