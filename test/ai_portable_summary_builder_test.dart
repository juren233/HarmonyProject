import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  test('portable summary builder folds repeated events into ai friendly package',
      () {
    final context = _heavyCareContext();

    final package = AiPortableSummaryBuilder().build(
      title: context.title,
      context: context,
      generatedAt: DateTime.parse('2026-04-15T19:05:00+08:00'),
    );

    final rawLength = jsonEncode(context.toJson()).length;
    final summaryLength = jsonEncode(package.toJson()).length;

    expect(package.packageType, 'ai_summary');
    expect(package.topicRollups, isNotEmpty);
    expect(package.keyEvidence, isNotEmpty);
    expect(package.activeItems, isNotEmpty);
    expect(package.measurements, isNotEmpty);
    expect(summaryLength, lessThan(rawLength));
  });
}

AiGenerationContext _heavyCareContext() {
  final baseStart = DateTime.parse('2025-10-12T00:00:00+08:00');
  return AiGenerationContext(
    title: '最近 6 个月的总结',
    rangeLabel: '最近 6 个月',
    rangeStart: baseStart,
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [
      Pet(
        id: 'pet-1',
        name: 'Mochi',
        avatarText: 'MO',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        ageLabel: '2岁',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '主粮+冻干',
        allergies: '鸡肉敏感',
        note: '偶尔紧张，需要持续观察肠胃和耳道状态。',
      ),
    ],
    todos: List.generate(90, (index) {
      return TodoItem(
        id: 'todo-$index',
        petId: 'pet-1',
        title: '补货主粮 #$index',
        dueAt: baseStart.add(Duration(days: index * 2)),
        notificationLeadTime: NotificationLeadTime.none,
        status: index % 7 == 0 ? TodoStatus.overdue : TodoStatus.done,
        note: '这是第 $index 条待办，用于模拟长周期照护数据。',
      );
    }),
    reminders: List.generate(85, (index) {
      return ReminderItem(
        id: 'reminder-$index',
        petId: 'pet-1',
        kind: index.isEven ? ReminderKind.deworming : ReminderKind.vaccine,
        title: '提醒事项 $index',
        scheduledAt: baseStart.add(Duration(days: index * 2 + 1)),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '每月',
        status: index % 6 == 0 ? ReminderStatus.overdue : ReminderStatus.done,
        note: '这是第 $index 条提醒，用于模拟长周期照护数据。',
      );
    }),
    records: List.generate(107, (index) {
      return PetRecord(
        id: 'record-$index',
        petId: 'pet-1',
        type: index % 5 == 0 ? PetRecordType.medical : PetRecordType.other,
        title: index.isEven ? '耳道维护检查结果 #$index' : '饮水量记录复盘 #$index',
        recordDate: baseStart.add(Duration(days: index)),
        summary: index.isEven
            ? '耳道清洁后状态平稳，但仍需继续观察抓耳频率。'
            : '饮水量记录相关状态记录完成，精神、食欲和排便已做对照观察。',
        note: '用于模拟最近 6 个月的连续观察和护理记录。',
      );
    }),
  );
}
