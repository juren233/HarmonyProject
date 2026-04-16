import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_care_scorecard_builder.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final baseline = DateTime.parse('2026-04-09T23:59:59+08:00');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('1 month sample backup fixture parses and stays above 80 score',
      () async {
    await _expectFixtureIsValid(
      fixturePath: 'docs/examples/petnote-ai-history-backup-1m.json',
      baseline: baseline,
      expectedWindowDays: 30,
      nameKeyword: '1个月',
      rangeLabel: '最近 1 个月',
    );
  });

  test('3 month sample backup fixture parses and stays above 80 score',
      () async {
    await _expectFixtureIsValid(
      fixturePath: 'docs/examples/petnote-ai-history-backup-3m.json',
      baseline: baseline,
      expectedWindowDays: 90,
      nameKeyword: '3个月',
      rangeLabel: '最近 3 个月',
    );
  });
}

Future<void> _expectFixtureIsValid({
  required String fixturePath,
  required DateTime baseline,
  required int expectedWindowDays,
  required String nameKeyword,
  required String rangeLabel,
}) async {
  final rawJson = File(fixturePath).readAsStringSync();
  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: await AppSettingsController.load(),
  );

  final package = coordinator.parsePackageJson(rawJson);
  final createdAt = package.createdAt;
  final historyStart = createdAt.subtract(Duration(days: expectedWindowDays));
  final historicalTodos = package.data.todos
      .where((item) => !item.dueAt.isAfter(createdAt))
      .toList(growable: false);
  final historicalReminders = package.data.reminders
      .where((item) => !item.scheduledAt.isAfter(createdAt))
      .toList(growable: false);
  final futureTodos = package.data.todos
      .where((item) => item.dueAt.isAfter(baseline))
      .toList(growable: false);
  final futureReminders = package.data.reminders
      .where((item) => item.scheduledAt.isAfter(baseline))
      .toList(growable: false);
  final futureRecords = package.data.records
      .where((item) => item.recordDate.isAfter(baseline))
      .toList(growable: false);

  expect(package.packageType, PetNoteDataPackageType.backup);
  expect(package.packageName, contains(nameKeyword));
  expect(package.data.pets, hasLength(1));
  expect(historicalTodos, isNotEmpty);
  expect(historicalReminders, isNotEmpty);
  expect(package.data.records, isNotEmpty);
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
  expect(
    historicalTodos.every((item) => !item.dueAt.isBefore(historyStart)),
    isTrue,
  );
  expect(
    historicalReminders.every((item) => !item.scheduledAt.isBefore(historyStart)),
    isTrue,
  );
  expect(
    package.data.records.every((item) => !item.recordDate.isBefore(historyStart)),
    isTrue,
  );
  expect(
    package.data.records.every((item) => !item.recordDate.isAfter(createdAt)),
    isTrue,
  );
  expect(futureTodos, isNotEmpty);
  expect(futureReminders, isNotEmpty);
  expect(futureRecords, isEmpty);

  final scorecard = const AiCareScorecardBuilder().build(
    AiGenerationContext(
      title: package.packageName,
      rangeLabel: rangeLabel,
      rangeStart: historyStart,
      rangeEnd: createdAt,
      languageTag: 'zh-CN',
      pets: package.data.pets,
      todos: package.data.todos,
      reminders: package.data.reminders,
      records: package.data.records,
    ),
  );

  expect(scorecard.overallScore, greaterThan(80));
  expect(scorecard.petScorecards.single.overallScore, greaterThan(80));
  expect(scorecard.overallScoreLabel, anyOf('稳定', '可控'));
}
