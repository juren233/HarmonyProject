import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
      'notification launch intent switches to checklist and highlights target item',
      (tester) async {
    final store = PetNoteStore.seeded()..setActiveTab(AppTab.me);
    final adapter = _RootFakeNotificationPlatformAdapter(
      initialIntent: const NotificationLaunchIntent(
        payload: NotificationPayload(
          sourceType: NotificationSourceType.todo,
          sourceId: 'todo-1',
          petId: 'pet-1',
          routeTarget: NotificationRouteTarget.checklist,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsWidgets);
    expect(store.activeTab, AppTab.checklist);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 220));
  });

  testWidgets(
      'notification-related store mutations wait for native scheduling to finish',
      (tester) async {
    final store = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-03-27T10:00:00+08:00'),
    );
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
    final adapter = _RootFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.authorized,
    );
    final scheduledAt = DateTime.now().add(const Duration(hours: 2));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    adapter.resetScheduleTracking();
    final addReminderFuture = store.addReminder(
      title: '后台提醒闭环',
      petId: store.pets.single.id,
      scheduledAt: scheduledAt,
      notificationLeadTime: NotificationLeadTime.oneHour,
      kind: ReminderKind.custom,
      recurrence: '单次',
      note: '验证保存后立即落地调度',
    );

    await tester.pump();
    expect(adapter.pendingScheduleCompleter, isNotNull);
    expect(adapter.scheduleCallCount, 1);
    expect(adapter.hasPendingSchedule, isTrue);

    var mutationCompleted = false;
    unawaited(addReminderFuture.then((_) => mutationCompleted = true));
    await tester.pump();
    expect(mutationCompleted, isFalse);

    adapter.completePendingSchedule();
    await addReminderFuture;
    await tester.pumpAndSettle();

    expect(mutationCompleted, isTrue);
    expect(adapter.hasPendingSchedule, isFalse);
    expect(
      adapter.scheduled.map((job) => job.key),
      contains('reminder:reminder-1'),
    );
  });

  testWidgets(
      'notification scheduling failure does not fail reminder save flow',
      (tester) async {
    final store = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-03-27T10:00:00+08:00'),
    );
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
    final adapter = _RootFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.authorized,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    adapter.resetScheduleTracking();
    adapter.holdSchedules = false;
    adapter.failNextSchedule = true;

    await expectLater(
      store.addReminder(
        title: '调度失败也保存',
        petId: store.pets.single.id,
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
        notificationLeadTime: NotificationLeadTime.oneHour,
        kind: ReminderKind.custom,
        recurrence: '单次',
        note: '验证保存链路不被通知异常阻断',
      ),
      completes,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.reminders.single.title, '调度失败也保存');
    expect(adapter.scheduleCallCount, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 220));
  });

  testWidgets(
      'root does not request notification permission on launch when platform state is unknown',
      (tester) async {
    final store = PetNoteStore.seeded();
    final adapter = _RootFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.unknown,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.requestPermissionCallCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 220));
  });
}

class _RootFakeNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  _RootFakeNotificationPlatformAdapter({
    this.initialIntent,
    this.permissionState = NotificationPermissionState.authorized,
  });

  final NotificationLaunchIntent? initialIntent;
  final NotificationPermissionState permissionState;
  final List<NotificationJob> scheduled = <NotificationJob>[];
  Completer<void>? pendingScheduleCompleter;
  int requestPermissionCallCount = 0;
  int scheduleCallCount = 0;
  bool failNextSchedule = false;
  bool holdSchedules = false;

  @override
  Future<void> cancelNotification(String key) async {}

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    return permissionState;
  }

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async =>
      initialIntent;

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return const NotificationPlatformCapabilities();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    return NotificationSettingsOpenResult.opened;
  }

  @override
  Future<NotificationSettingsOpenResult> openExactAlarmSettings() async {
    return NotificationSettingsOpenResult.opened;
  }

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    requestPermissionCallCount += 1;
    return NotificationPermissionState.authorized;
  }

  bool get hasPendingSchedule => pendingScheduleCompleter != null;

  void resetScheduleTracking() {
    scheduled.clear();
    pendingScheduleCompleter = null;
    scheduleCallCount = 0;
    holdSchedules = true;
  }

  void completePendingSchedule() {
    pendingScheduleCompleter?.complete();
    pendingScheduleCompleter = null;
    holdSchedules = false;
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    scheduleCallCount += 1;
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('模拟原生通知调度失败');
    }
    scheduled.removeWhere((existing) => existing.key == job.key);
    scheduled.add(job);
    if (!holdSchedules) {
      return;
    }
    final completer = Completer<void>();
    pendingScheduleCompleter = completer;
    await completer.future;
  }
}
