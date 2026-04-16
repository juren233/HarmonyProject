import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('load migrates legacy todo reminder and record data into semantic fields',
      () async {
    SharedPreferences.setMockInitialValues({
      'pets_v1': jsonEncode([
        {
          'id': 'pet-1',
          'name': 'Mochi',
          'avatarText': 'MO',
          'type': 'cat',
          'breed': '米克斯',
          'sex': '母',
          'birthday': '2024-01-01',
          'ageLabel': '2岁',
          'weightKg': 4.2,
          'neuterStatus': 'neutered',
          'feedingPreferences': '主粮',
          'allergies': '无',
          'note': '旧档案',
        },
      ]),
      'todos_v1': jsonEncode([
        {
          'id': 'todo-1',
          'petId': 'pet-1',
          'title': '补货主粮',
          'dueAt': '2026-04-15T09:00:00+08:00',
          'notificationLeadTime': 'none',
          'status': 'open',
          'note': '旧待办备注',
        },
      ]),
      'reminders_v1': jsonEncode([
        {
          'id': 'reminder-1',
          'petId': 'pet-1',
          'kind': 'deworming',
          'title': '体内驱虫提醒',
          'scheduledAt': '2026-04-20T09:00:00+08:00',
          'notificationLeadTime': 'none',
          'recurrence': '每月',
          'status': 'pending',
          'note': '旧提醒备注',
        },
      ]),
      'records_v1': jsonEncode([
        {
          'id': 'record-1',
          'petId': 'pet-1',
          'type': 'medical',
          'title': '耳道复查',
          'recordDate': '2026-04-14T20:00:00+08:00',
          'summary': '抓耳次数略有增加，准备复查。',
          'note': '旧记录备注',
        },
      ]),
    });

    final store = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-04-15T19:05:00+08:00'),
    );

    expect(store.todos, hasLength(1));
    expect(store.reminders, hasLength(1));
    expect(store.records, hasLength(1));

    final todoSemantic = store.todos.single.semantic;
    expect(todoSemantic, isNotNull);
    expect(todoSemantic!.topicKey, SemanticTopicKey.purchase);
    expect(todoSemantic.intent, SemanticActionIntent.buy);
    expect(todoSemantic.signal, SemanticSignal.attention);
    expect(store.todos.single.note, '旧待办备注');

    final reminderSemantic = store.reminders.single.semantic;
    expect(reminderSemantic, isNotNull);
    expect(reminderSemantic!.topicKey, SemanticTopicKey.deworming);
    expect(reminderSemantic.intent, SemanticActionIntent.administer);
    expect(reminderSemantic.signal, SemanticSignal.scheduled);

    final recordSemantic = store.records.single.semantic;
    expect(recordSemantic, isNotNull);
    expect(recordSemantic!.topicKey, SemanticTopicKey.earCare);
    expect(recordSemantic.source, SemanticEvidenceSource.vet);
    expect(recordSemantic.signal, SemanticSignal.attention);
    expect(recordSemantic.evidenceSummary, contains('抓耳次数略有增加'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos_v1'), contains('"semantic"'));
    expect(prefs.getString('reminders_v1'), contains('"semantic"'));
    expect(prefs.getString('records_v1'), contains('"semantic"'));
  });
}
