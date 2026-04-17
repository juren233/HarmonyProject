import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

class _FakeNotificationPlatformAdapter implements NotificationPlatformAdapter {
  _FakeNotificationPlatformAdapter({
    this.openSettingsResult = NotificationSettingsOpenResult.opened,
    this.permissionState = NotificationPermissionState.denied,
  });

  final List<NotificationJob> scheduled = <NotificationJob>[];
  final Map<String, NotificationJob> currentScheduled =
      <String, NotificationJob>{};
  final List<String> cancelled = <String>[];
  final NotificationSettingsOpenResult openSettingsResult;
  NotificationPermissionState permissionState;
  NotificationPlatformCapabilities capabilities =
      const NotificationPlatformCapabilities();
  int scheduleCallCount = 0;
  int cancelCallCount = 0;

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    return permissionState;
  }

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return capabilities;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async => null;

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return const NotificationPlatformCapabilities();
  }

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    return openSettingsResult;
  }

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<void> cancelNotification(String key) async {
    cancelCallCount += 1;
    cancelled.add(key);
    currentScheduled.remove(key);
  }

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    return permissionState;
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    scheduleCallCount += 1;
    scheduled.removeWhere((existing) => existing.key == job.key);
    scheduled.add(job);
    currentScheduled[job.key] = job;
  }
}
