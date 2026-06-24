import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_care_scorecard_builder.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/data/data_storage_models.dart';

void main() {
  test('demo high score backup has 150 business items and scores above 85', () {
    final rawJson = File(
      'docs/examples/petnote-ai-demo-high-score-150-backup.json',
    ).readAsStringSync();
    final package = PetNoteDataPackage.fromJson(
      jsonDecode(rawJson) as Map<String, dynamic>,
    );
    final businessItemCount = package.data.todos.length +
        package.data.reminders.length +
        package.data.records.length;

    expect(package.data.pets, hasLength(2));
    expect(package.data.todos, hasLength(60));
    expect(package.data.reminders, hasLength(50));
    expect(package.data.records, hasLength(40));
    expect(businessItemCount, 150);
    expect(
      _statusCounts(package.data.todos.map((item) => item.status.name)),
      equals({
        'done': 57,
        'open': 1,
        'postponed': 1,
        'skipped': 1,
      }),
    );
    expect(
      _statusCounts(package.data.reminders.map((item) => item.status.name)),
      equals({
        'done': 48,
        'pending': 1,
        'skipped': 1,
      }),
    );
    expect(
      package.data.todos
          .singleWhere((item) => item.status.name == 'open')
          .dueAt,
      DateTime.parse('2026-06-25T09:10:00+08:00'),
    );
    expect(
      package.data.reminders
          .singleWhere((item) => item.status.name == 'pending')
          .scheduledAt,
      DateTime.parse('2026-06-25T09:00:00+08:00'),
    );

    final scorecard = const AiCareScorecardBuilder().build(
      AiGenerationContext(
        title: '演示总览',
        rangeLabel: '最近 1 个月',
        rangeStart: DateTime.parse('2026-05-24T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-06-24T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: package.data.pets,
        todos: package.data.todos,
        reminders: package.data.reminders,
        records: package.data.records,
      ),
    );

    expect(scorecard.overallScore, greaterThanOrEqualTo(85));
    expect(scorecard.scoreConfidence, AiScoreConfidence.high);
    expect(
      scorecard.riskCandidates.any((item) => item.contains('跳过')),
      isTrue,
    );
    expect(
      scorecard.riskCandidates.every(
        (item) => !item.contains('逾期'),
      ),
      isTrue,
    );
  });
}

Map<String, int> _statusCounts(Iterable<String> statuses) {
  final counts = <String, int>{};
  for (final status in statuses) {
    counts.update(status, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}
