import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'dart:async';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'syncFromStore schedules open todos and pending reminders then cancels resolved ones',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );
    final store = PetNoteStore.seeded();

    await coordinator.init();
    await coordinator.syncFromStore(store);

    expect(
      adapter.scheduled.map((job) => job.key).toSet(),
      containsAll(<String>{
        'todo:todo-1',
        'todo:todo-2',
        'reminder:reminder-1',
        'reminder:reminder-2'
      }),
    );
    expect(
      adapter.scheduled.map((job) => job.key).toSet(),
      isNot(contains('reminder:reminder-3')),
    );
    expect(
      adapter.scheduled.map((job) => job.key).toSet(),
      isNot(contains('todo:todo-3')),
    );

    store.markChecklistDone('todo', 'todo-1');
    await coordinator.syncFromStore(store);

    expect(adapter.cancelled, contains('todo:todo-1'));
  });
  test('syncFromStore uses item title and pet-note body for notifications',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );
    final store = PetNoteStore.seeded();

    await coordinator.init();
    await coordinator.syncFromStore(store);

    final todoJob = adapter.currentScheduled['todo:todo-1']!;
    final reminderJob = adapter.currentScheduled['reminder:reminder-1']!;

    expect(todoJob.title, '补充冻干库存');
    expect(todoJob.body, 'Luna · 检查低敏口味。');
    expect(reminderJob.title, '三联疫苗加强');
    expect(reminderJob.body, 'Luna · 提前准备免疫本。');
  });

  test('syncFromStore uses only pet name when notification note is blank',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final now = DateTime.parse('2026-03-27T10:00:00+08:00');
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => now,
    );
    final store = await PetNoteStore.load(nowProvider: () => now);

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

    await store.addTodo(
      title: '补充主粮',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-27T18:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '   ',
    );
    await store.addReminder(
      title: '耳道复查',
      petId: store.pets.single.id,
      scheduledAt: DateTime.parse('2026-03-27T20:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      kind: ReminderKind.review,
      recurrence: '单次',
      note: '   ',
    );

    await coordinator.init();
    await coordinator.syncFromStore(store);

    final todoJob = adapter.currentScheduled['todo:todo-1']!;
    final reminderJob = adapter.currentScheduled['reminder:reminder-1']!;

    expect(todoJob.title, '补充主粮');
    expect(todoJob.body, 'Mochi');
    expect(reminderJob.title, '耳道复查');
    expect(reminderJob.body, 'Mochi');
  });

  test(
      'notification lead time schedules five-minute-early triggers and skips overdue jobs',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final now = DateTime.parse('2026-03-27T10:00:00+08:00');
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => now,
    );
    final store = await PetNoteStore.load(nowProvider: () => now);

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

    await store.addReminder(
      title: '体内驱虫',
      petId: store.pets.single.id,
      scheduledAt: DateTime.parse('2026-03-27T10:30:00+08:00'),
      notificationLeadTime: NotificationLeadTime.fiveMinutes,
      kind: ReminderKind.deworming,
      recurrence: '单次',
      note: '',
    );
    await store.addTodo(
      title: '已经逾期的待办',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-27T09:30:00+08:00'),
      notificationLeadTime: NotificationLeadTime.oneHour,
      note: '',
    );

    await coordinator.init();
    await coordinator.syncFromStore(store);

    final reminderJob = adapter.scheduled.singleWhere(
      (job) => job.key == 'reminder:reminder-1',
    );
    expect(
      reminderJob.scheduledAt,
      DateTime.parse('2026-03-27T10:25:00+08:00'),
    );
    expect(
      reminderJob.eventScheduledAt,
      DateTime.parse('2026-03-27T10:30:00+08:00'),
    );
    expect(reminderJob.reminderLeadTimeMinutes, 5);
    expect(
      adapter.scheduled.map((job) => job.key),
      isNot(contains('todo:todo-1')),
    );
  });

  test(
      'syncFromStore stays idempotent when store notification data is unchanged',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );
    final store = PetNoteStore.seeded();

    await coordinator.init();
    await coordinator.syncFromStore(store);
    final firstScheduleCount = adapter.scheduleCallCount;

    await coordinator.syncFromStore(store);

    expect(adapter.scheduleCallCount, firstScheduleCount);
    expect(adapter.cancelCallCount, 0);
  });

  test('syncFromStore reschedules when persisted snapshot is missing on platform',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );
    final store = PetNoteStore.seeded();

    await coordinator.init();
    await coordinator.syncFromStore(store);
    final firstScheduleCount = adapter.scheduleCallCount;
    adapter.currentScheduled.remove('todo:todo-1');

    await coordinator.syncFromStore(store);

    expect(adapter.scheduleCallCount, firstScheduleCount + 1);
    expect(adapter.cancelled, contains('todo:todo-1'));
    expect(adapter.currentScheduled, contains('todo:todo-1'));
  });

  test('syncFromStore keeps nearest jobs when platform has a schedule limit',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      capabilities: const NotificationPlatformCapabilities(
        maxScheduledNotificationCount: 30,
      ),
    );
    final now = DateTime.parse('2026-03-27T10:00:00+08:00');
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => now,
    );
    final store = await PetNoteStore.load(nowProvider: () => now);

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
    for (var index = 0; index < 35; index += 1) {
      await store.addTodo(
        title: '提醒 $index',
        petId: store.pets.single.id,
        dueAt: now.add(Duration(minutes: index + 1)),
        notificationLeadTime: NotificationLeadTime.none,
        note: '',
      );
    }

    await coordinator.init();
    await coordinator.syncFromStore(store);

    expect(adapter.resetCallCount, 1);
    expect(adapter.currentScheduled.length, 30);
    expect(adapter.currentScheduled.keys, contains('todo:todo-1'));
    expect(adapter.currentScheduled.keys, contains('todo:todo-30'));
    expect(adapter.currentScheduled.keys, isNot(contains('todo:todo-31')));
  });

  test(
      'lead time catch-up notification is only scheduled once inside reminder window',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final now = DateTime.parse('2026-03-27T10:00:00+08:00');
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => now,
    );
    final store = await PetNoteStore.load(nowProvider: () => now);

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

    await store.addTodo(
      title: '窗口内补发提醒',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-27T10:30:00+08:00'),
      notificationLeadTime: NotificationLeadTime.oneHour,
      note: '',
    );

    await coordinator.init();
    await coordinator.syncFromStore(store);
    final firstJob = adapter.scheduled.singleWhere(
      (job) => job.key == 'todo:todo-1',
    );
    final firstScheduleCount = adapter.scheduleCallCount;

    await coordinator.syncFromStore(store);

    expect(firstJob.scheduledAt, now.add(const Duration(seconds: 1)));
    expect(adapter.scheduleCallCount, firstScheduleCount);
    expect(adapter.cancelCallCount, 0);
  });

  test('changed todo schedule cancels previous job and schedules updated job',
      () async {
    final adapter = _FakeNotificationPlatformAdapter();
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );
    final store = PetNoteStore.seeded();

    await coordinator.init();
    await coordinator.syncFromStore(store);

    final originalJob = adapter.currentScheduled['todo:todo-1']!;
    await store.postponeChecklist('todo', 'todo-1');
    await coordinator.syncFromStore(store);

    final updatedJob = adapter.currentScheduled['todo:todo-1']!;
    expect(adapter.cancelled, contains('todo:todo-1'));
    expect(updatedJob.scheduledAt, isNot(originalJob.scheduledAt));
    expect(updatedJob.scheduledAt.isAfter(originalJob.scheduledAt), isTrue);
  });

  test('open notification settings forwards platform result', () async {
    final adapter = _FakeNotificationPlatformAdapter(
      openSettingsResult: NotificationSettingsOpenResult.failed,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    final result = await coordinator.openNotificationSettings();

    expect(result, NotificationSettingsOpenResult.failed);
  });

  test('open exact alarm settings forwards platform result', () async {
    final adapter = _FakeNotificationPlatformAdapter(
      openExactAlarmSettingsResult: NotificationSettingsOpenResult.failed,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    final result = await coordinator.openExactAlarmSettings();

    expect(result, NotificationSettingsOpenResult.failed);
  });

  test('refreshPlatformState updates permission and exact alarm capability',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    await coordinator.init();
    adapter.permissionState = NotificationPermissionState.authorized;
    adapter.capabilities = const NotificationPlatformCapabilities(
      exactAlarmStatus: NotificationExactAlarmStatus.unavailable,
    );

    final changed = await coordinator.refreshPlatformState();

    expect(changed, isTrue);
    expect(coordinator.permissionState, NotificationPermissionState.authorized);
    expect(
      coordinator.capabilities.exactAlarmStatus,
      NotificationExactAlarmStatus.unavailable,
    );
  });

  test('init uses platform prompt interaction state to decide settings routing',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
      platformHandledPrompt: true,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    await coordinator.init();

    expect(coordinator.hasHandledPermissionPrompt, isTrue);
    expect(coordinator.shouldOpenSettingsForPermissionRequest, isTrue);
  });

  test('init remains available when push token registration fails', () async {
    final adapter = _FakeNotificationPlatformAdapter(
      failRegisterPushToken: true,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    await expectLater(coordinator.init(), completes);

    expect(coordinator.isInitialized, isTrue);
    expect(coordinator.pushToken, isNull);
  });

  test('init remains available when notification snapshot preferences time out',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      maxScheduledNotifications: false,
    );
    SharedPreferences.setMockInitialValues({});
    final coordinator = NotificationCoordinator(
      adapter: adapter,
      nowProvider: () => DateTime.parse('2026-03-24T12:00:00+08:00'),
    );

    final originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _HangingSharedPreferencesStore();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalStore;
    });

    await expectLater(coordinator.init(), completes);

    expect(coordinator.isInitialized, isTrue);
  });

  test('request permission keeps requesting when system dialog was not handled',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    await coordinator.init();

    final firstResult = await coordinator.requestPermission();

    expect(firstResult, NotificationPermissionState.denied);
    expect(coordinator.hasHandledPermissionPrompt, isFalse);
    expect(coordinator.shouldOpenSettingsForPermissionRequest, isFalse);
    expect(adapter.requestPermissionCallCount, 1);
    expect(adapter.openSettingsCallCount, 0);

    final secondResult = await coordinator.requestPermission();

    expect(secondResult, NotificationPermissionState.denied);
    expect(adapter.requestPermissionCallCount, 2);
    expect(adapter.openSettingsCallCount, 0);
  });

  test(
      'request permission opens settings after system dialog was really handled',
      () async {
    final adapter = _FakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
      requestResult: const PermissionRequestOutcome(
        state: NotificationPermissionState.denied,
        promptHandledSystemDialog: true,
      ),
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    await coordinator.init();

    final firstResult = await coordinator.requestPermission();

    expect(firstResult, NotificationPermissionState.denied);
    expect(coordinator.hasHandledPermissionPrompt, isTrue);
    expect(coordinator.shouldOpenSettingsForPermissionRequest, isTrue);
    expect(adapter.requestPermissionCallCount, 1);
    expect(adapter.openSettingsCallCount, 0);

    final secondResult = await coordinator.requestPermission();

    expect(secondResult, NotificationPermissionState.denied);
    expect(adapter.requestPermissionCallCount, 1);
    expect(adapter.openSettingsCallCount, 1);
  });
}

class _FakeNotificationPlatformAdapter implements NotificationPlatformAdapter {
  _FakeNotificationPlatformAdapter({
    this.openSettingsResult = NotificationSettingsOpenResult.opened,
    this.openExactAlarmSettingsResult = NotificationSettingsOpenResult.opened,
    this.permissionState = NotificationPermissionState.denied,
    this.failRegisterPushToken = false,
    this.platformHandledPrompt = false,
    this.requestResult = const PermissionRequestOutcome(
      state: NotificationPermissionState.denied,
      promptHandledSystemDialog: false,
    ),
    this.maxScheduledNotifications = true,
    NotificationPlatformCapabilities? capabilities,
  }) : capabilities = capabilities ??
            (maxScheduledNotifications
                ? const NotificationPlatformCapabilities(
                    maxScheduledNotificationCount: 30,
                  )
                : const NotificationPlatformCapabilities());

  final List<NotificationJob> scheduled = <NotificationJob>[];
  final Map<String, NotificationJob> currentScheduled =
      <String, NotificationJob>{};
  final List<String> cancelled = <String>[];
  final NotificationSettingsOpenResult openSettingsResult;
  final NotificationSettingsOpenResult openExactAlarmSettingsResult;
  NotificationPermissionState permissionState;
  final bool failRegisterPushToken;
  final bool platformHandledPrompt;
  final PermissionRequestOutcome<NotificationPermissionState> requestResult;
  final bool maxScheduledNotifications;
  NotificationPlatformCapabilities capabilities;
  int scheduleCallCount = 0;
  int cancelCallCount = 0;
  int resetCallCount = 0;
  int requestPermissionCallCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    return permissionState;
  }

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return capabilities;
  }

  @override
  Future<bool> hasHandledPermissionPrompt() async {
    return platformHandledPrompt;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async => null;

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    openSettingsCallCount += 1;
    return openSettingsResult;
  }

  @override
  Future<NotificationSettingsOpenResult> openExactAlarmSettings() async {
    return openExactAlarmSettingsResult;
  }

  @override
  Future<String?> registerPushToken() async {
    if (failRegisterPushToken) {
      throw StateError('模拟推送 Token 注册失败');
    }
    return null;
  }

  @override
  Future<void> cancelNotification(String key) async {
    cancelCallCount += 1;
    cancelled.add(key);
    currentScheduled.remove(key);
  }

  @override
  Future<bool> hasScheduledNotification(String key) async {
    return currentScheduled.containsKey(key);
  }

  @override
  Future<void> resetScheduledNotifications() async {
    resetCallCount += 1;
    currentScheduled.clear();
    scheduled.clear();
  }

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<PermissionRequestOutcome<NotificationPermissionState>>
      requestPermission() async {
    requestPermissionCallCount += 1;
    permissionState = requestResult.state;
    return requestResult;
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    scheduleCallCount += 1;
    scheduled.removeWhere((existing) => existing.key == job.key);
    scheduled.add(job);
    currentScheduled[job.key] = job;
  }
}

class _HangingSharedPreferencesStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() {
    return Completer<Map<String, Object>>().future;
  }

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async => true;
}
