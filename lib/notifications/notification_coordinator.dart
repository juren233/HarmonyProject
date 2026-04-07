import 'package:flutter/foundation.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';

class NotificationCoordinator extends ChangeNotifier {
  NotificationCoordinator({
    required NotificationPlatformAdapter adapter,
    DateTime Function()? nowProvider,
  })  : _adapter = adapter,
        _nowProvider = nowProvider ?? DateTime.now;

  final NotificationPlatformAdapter _adapter;
  final DateTime Function() _nowProvider;
  final Set<String> _scheduledKeys = <String>{};

  NotificationPermissionState _permissionState =
      NotificationPermissionState.unknown;
  String? _pushToken;
  bool _initialized = false;

  NotificationPermissionState get permissionState => _permissionState;
  String? get pushToken => _pushToken;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    await _adapter.initialize();
    _permissionState = await _adapter.getPermissionState();
    _pushToken = await _adapter.registerPushToken();
    _initialized = true;
    notifyListeners();
  }

  Future<NotificationPermissionState> requestPermission() async {
    _permissionState = await _adapter.requestPermission();
    notifyListeners();
    return _permissionState;
  }

  Future<void> syncFromStore(PetNoteStore store) async {
    final jobs = _buildJobsFromStore(store);
    final nextKeys = jobs.map((job) => job.key).toSet();
    final staleKeys = _scheduledKeys.difference(nextKeys);

    for (final key in staleKeys) {
      await _adapter.cancelNotification(key);
    }
    for (final job in jobs) {
      await _adapter.scheduleLocalNotification(job);
    }

    _scheduledKeys
      ..clear()
      ..addAll(nextKeys);
  }

  Future<NotificationLaunchIntent?> consumeLaunchIntent() {
    return _adapter.getInitialLaunchIntent();
  }

  Future<NotificationLaunchIntent?> consumeForegroundTap() {
    return _adapter.consumeForegroundTap();
  }

  Future<NotificationSettingsOpenResult> openNotificationSettings() {
    return _adapter.openNotificationSettings();
  }

  List<NotificationJob> _buildJobsFromStore(PetNoteStore store) {
    final jobs = <NotificationJob>[];
    final now = _nowProvider();

    for (final todo in store.todos) {
      if (todo.status == TodoStatus.done ||
          todo.status == TodoStatus.skipped ||
          todo.dueAt.isBefore(now)) {
        continue;
      }
      final triggerAt = _notificationTriggerAt(
        scheduledAt: todo.dueAt,
        leadTime: todo.notificationLeadTime,
        now: now,
      );
      if (triggerAt == null) {
        continue;
      }
      final pet = store.petById(todo.petId);
      jobs.add(
        NotificationJob(
          payload: NotificationPayload(
            sourceType: NotificationSourceType.todo,
            sourceId: todo.id,
            petId: todo.petId,
            routeTarget: NotificationRouteTarget.checklist,
          ),
          scheduledAt: triggerAt,
          title: '${pet?.name ?? '爱宠'}待办提醒',
          body: todo.title,
        ),
      );
    }

    for (final reminder in store.reminders) {
      if (reminder.status == ReminderStatus.done ||
          reminder.status == ReminderStatus.skipped ||
          reminder.scheduledAt.isBefore(now)) {
        continue;
      }
      final triggerAt = _notificationTriggerAt(
        scheduledAt: reminder.scheduledAt,
        leadTime: reminder.notificationLeadTime,
        now: now,
      );
      if (triggerAt == null) {
        continue;
      }
      final pet = store.petById(reminder.petId);
      jobs.add(
        NotificationJob(
          payload: NotificationPayload(
            sourceType: NotificationSourceType.reminder,
            sourceId: reminder.id,
            petId: reminder.petId,
            routeTarget: NotificationRouteTarget.checklist,
          ),
          scheduledAt: triggerAt,
          title: '${pet?.name ?? '爱宠'}提醒',
          body: reminder.title,
        ),
      );
    }

    return jobs;
  }

  DateTime? _notificationTriggerAt({
    required DateTime scheduledAt,
    required NotificationLeadTime leadTime,
    required DateTime now,
  }) {
    if (!scheduledAt.isAfter(now)) {
      return null;
    }
    final triggerAt = scheduledAt.subtract(leadTimeDuration(leadTime));
    if (triggerAt.isAfter(now)) {
      return triggerAt;
    }
    return now.add(const Duration(seconds: 1));
  }
}
