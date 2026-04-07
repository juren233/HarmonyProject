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

  test('open notification settings forwards platform result', () async {
    final adapter = _FakeNotificationPlatformAdapter(
      openSettingsResult: NotificationSettingsOpenResult.failed,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);

    final result = await coordinator.openNotificationSettings();

    expect(result, NotificationSettingsOpenResult.failed);
  });
}

class _FakeNotificationPlatformAdapter implements NotificationPlatformAdapter {
  _FakeNotificationPlatformAdapter({
    this.openSettingsResult = NotificationSettingsOpenResult.opened,
  });

  final List<NotificationJob> scheduled = <NotificationJob>[];
  final List<String> cancelled = <String>[];
  final NotificationSettingsOpenResult openSettingsResult;

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    return NotificationPermissionState.denied;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async => null;

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    return openSettingsResult;
  }

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<void> cancelNotification(String key) async {
    cancelled.add(key);
  }

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    return NotificationPermissionState.denied;
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    scheduled.removeWhere((existing) => existing.key == job.key);
    scheduled.add(job);
  }
}
