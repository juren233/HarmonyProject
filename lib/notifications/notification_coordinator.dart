import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCoordinator extends ChangeNotifier {
  static const String persistedJobsStorageKey = 'notification_jobs_snapshot_v1';

  NotificationCoordinator({
    required NotificationPlatformAdapter adapter,
    DateTime Function()? nowProvider,
    this.appLogController,
  })  : _adapter = adapter,
        _nowProvider = nowProvider ?? DateTime.now;

  final NotificationPlatformAdapter _adapter;
  final DateTime Function() _nowProvider;
  final AppLogController? appLogController;
  final Map<String, _PersistedNotificationJobSnapshot> _scheduledSnapshots =
      <String, _PersistedNotificationJobSnapshot>{};

  NotificationPermissionState _permissionState =
      NotificationPermissionState.unknown;
  NotificationPlatformCapabilities _capabilities =
      const NotificationPlatformCapabilities();
  String? _pushToken;
  bool _initialized = false;

  NotificationPermissionState get permissionState => _permissionState;
  NotificationPlatformCapabilities get capabilities => _capabilities;
  String? get pushToken => _pushToken;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    await _adapter.initialize();
    await _refreshPlatformState(notify: false, includeCapabilities: true);
    _pushToken = await _adapter.registerPushToken();
    final persistedSnapshots = await _loadPersistedSnapshots();
    _scheduledSnapshots
      ..clear()
      ..addEntries(
        persistedSnapshots.map((snapshot) => MapEntry(snapshot.key, snapshot)),
      );
    _initialized = true;
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '通知中心初始化',
      message: '通知初始化完成，权限状态：${_permissionState.name}',
      details: [
        if (_pushToken != null) 'pushToken: 已注册',
        if (_capabilities.supportsExactAlarms)
          'exactAlarm: ${_capabilities.exactAlarmStatus.name}',
      ].join('，').ifEmptyAsNull(),
    );
    notifyListeners();
  }

  Future<NotificationPermissionState> requestPermission() async {
    _permissionState = await _adapter.requestPermission();
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '通知权限更新',
      message: '通知权限请求结果：${_permissionState.name}',
    );
    notifyListeners();
    return _permissionState;
  }

  Future<void> syncFromStore(PetNoteStore store) async {
    final snapshots = _buildJobsFromStore(store);
    final nextKeys = snapshots.keys.toSet();
    final staleKeys = _scheduledSnapshots.keys.toSet().difference(nextKeys);

    for (final key in staleKeys) {
      await _adapter.cancelNotification(key);
    }
    for (final entry in snapshots.entries) {
      final previous = _scheduledSnapshots[entry.key];
      final next = entry.value;
      if (previous == next) {
        continue;
      }
      if (previous != null) {
        await _adapter.cancelNotification(entry.key);
      }
      await _adapter.scheduleLocalNotification(next.toNotificationJob());
    }

    _scheduledSnapshots
      ..clear()
      ..addAll(snapshots);
    await _persistSnapshots(_scheduledSnapshots.values);
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '同步通知任务',
      message: '已同步 ${snapshots.length} 条通知任务，取消 ${staleKeys.length} 条旧任务。',
    );
  }

  Future<NotificationLaunchIntent?> consumeLaunchIntent() {
    return _adapter.getInitialLaunchIntent();
  }

  Future<NotificationLaunchIntent?> consumeForegroundTap() {
    return _adapter.consumeForegroundTap();
  }

  Future<NotificationSettingsOpenResult> openNotificationSettings() {
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '打开通知设置',
      message: '准备打开系统通知设置。',
    );
    return _adapter.openNotificationSettings();
  }

  Future<bool> refreshPlatformState() {
    return _refreshPlatformState(notify: true, includeCapabilities: true);
  }

  bool get hasGrantedPermission =>
      _permissionState == NotificationPermissionState.authorized ||
      _permissionState == NotificationPermissionState.provisional;

  Map<String, _PersistedNotificationJobSnapshot> _buildJobsFromStore(
    PetNoteStore store,
  ) {
    final jobs = <String, _PersistedNotificationJobSnapshot>{};
    final now = _nowProvider();

    for (final todo in store.todos) {
      if (todo.status == TodoStatus.done ||
          todo.status == TodoStatus.skipped ||
          todo.dueAt.isBefore(now)) {
        continue;
      }
      final payload = NotificationPayload(
        sourceType: NotificationSourceType.todo,
        sourceId: todo.id,
        petId: todo.petId,
        routeTarget: NotificationRouteTarget.checklist,
      );
      final triggerAt = _notificationTriggerAt(
        scheduledAt: todo.dueAt,
        leadTime: todo.notificationLeadTime,
        now: now,
        existingSnapshot: _scheduledSnapshots[payload.key],
      );
      if (triggerAt == null) {
        continue;
      }
      final pet = store.petById(todo.petId);
      jobs[payload.key] = _PersistedNotificationJobSnapshot(
        payload: payload,
        scheduledAt: triggerAt,
        sourceScheduledAt: todo.dueAt,
        leadTime: todo.notificationLeadTime,
        title: '${pet?.name ?? '爱宠'}待办提醒',
        body: todo.title,
      );
    }

    for (final reminder in store.reminders) {
      if (reminder.status == ReminderStatus.done ||
          reminder.status == ReminderStatus.skipped ||
          reminder.scheduledAt.isBefore(now)) {
        continue;
      }
      final payload = NotificationPayload(
        sourceType: NotificationSourceType.reminder,
        sourceId: reminder.id,
        petId: reminder.petId,
        routeTarget: NotificationRouteTarget.checklist,
      );
      final triggerAt = _notificationTriggerAt(
        scheduledAt: reminder.scheduledAt,
        leadTime: reminder.notificationLeadTime,
        now: now,
        existingSnapshot: _scheduledSnapshots[payload.key],
      );
      if (triggerAt == null) {
        continue;
      }
      final pet = store.petById(reminder.petId);
      jobs[payload.key] = _PersistedNotificationJobSnapshot(
        payload: payload,
        scheduledAt: triggerAt,
        sourceScheduledAt: reminder.scheduledAt,
        leadTime: reminder.notificationLeadTime,
        title: '${pet?.name ?? '爱宠'}提醒',
        body: reminder.title,
      );
    }

    return jobs;
  }

  DateTime? _notificationTriggerAt({
    required DateTime scheduledAt,
    required NotificationLeadTime leadTime,
    required DateTime now,
    _PersistedNotificationJobSnapshot? existingSnapshot,
  }) {
    if (!scheduledAt.isAfter(now)) {
      return null;
    }
    final triggerAt = scheduledAt.subtract(leadTimeDuration(leadTime));
    if (triggerAt.isAfter(now)) {
      return triggerAt;
    }
    if (existingSnapshot != null &&
        existingSnapshot.sourceScheduledAt.isAtSameMomentAs(scheduledAt) &&
        existingSnapshot.leadTime == leadTime) {
      return existingSnapshot.scheduledAt;
    }
    return now.add(const Duration(seconds: 1));
  }

  Future<bool> _refreshPlatformState({
    required bool notify,
    required bool includeCapabilities,
  }) async {
    final nextPermissionState = await _adapter.getPermissionState();
    final nextCapabilities =
        includeCapabilities ? await _adapter.getCapabilities() : _capabilities;
    final changed = nextPermissionState != _permissionState ||
        nextCapabilities != _capabilities;
    if (!changed) {
      return false;
    }
    _permissionState = nextPermissionState;
    _capabilities = nextCapabilities;
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '通知平台状态刷新',
      message:
          '权限：${_permissionState.name}，exact alarm：${_capabilities.exactAlarmStatus.name}',
    );
    if (notify) {
      notifyListeners();
    }
    return true;
  }

  Future<List<_PersistedNotificationJobSnapshot>>
      _loadPersistedSnapshots() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(persistedJobsStorageKey);
    if (raw == null || raw.isEmpty) {
      return const <_PersistedNotificationJobSnapshot>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <_PersistedNotificationJobSnapshot>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (entry) => _PersistedNotificationJobSnapshot.fromMap(
            Map<String, dynamic>.from(entry),
          ),
        )
        .where((entry) => entry.key.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _persistSnapshots(
    Iterable<_PersistedNotificationJobSnapshot> snapshots,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      snapshots.map((snapshot) => snapshot.toMap()).toList(growable: false),
    );
    await preferences.setString(persistedJobsStorageKey, payload);
  }
}

class _PersistedNotificationJobSnapshot {
  const _PersistedNotificationJobSnapshot({
    required this.payload,
    required this.scheduledAt,
    required this.sourceScheduledAt,
    required this.leadTime,
    required this.title,
    required this.body,
  });

  final NotificationPayload payload;
  final DateTime scheduledAt;
  final DateTime sourceScheduledAt;
  final NotificationLeadTime leadTime;
  final String title;
  final String body;

  String get key => payload.key;

  NotificationJob toNotificationJob() {
    return NotificationJob(
      payload: payload,
      scheduledAt: scheduledAt,
      title: title,
      body: body,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'payload': payload.toMap(),
      'scheduledAtEpochMs': scheduledAt.millisecondsSinceEpoch,
      'sourceScheduledAtEpochMs': sourceScheduledAt.millisecondsSinceEpoch,
      'leadTime': leadTime.name,
      'title': title,
      'body': body,
    };
  }

  factory _PersistedNotificationJobSnapshot.fromMap(Map<String, dynamic> map) {
    return _PersistedNotificationJobSnapshot(
      payload: NotificationPayload.fromMap(
        Map<Object?, Object?>.from(
          map['payload'] as Map? ?? const <Object?, Object?>{},
        ),
      ),
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        (map['scheduledAtEpochMs'] as num?)?.toInt() ?? 0,
      ),
      sourceScheduledAt: DateTime.fromMillisecondsSinceEpoch(
        (map['sourceScheduledAtEpochMs'] as num?)?.toInt() ?? 0,
      ),
      leadTime: _leadTimeFromName(map['leadTime'] as String?),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _PersistedNotificationJobSnapshot &&
        other.payload.key == payload.key &&
        other.scheduledAt.isAtSameMomentAs(scheduledAt) &&
        other.sourceScheduledAt.isAtSameMomentAs(sourceScheduledAt) &&
        other.leadTime == leadTime &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(
        payload.key,
        scheduledAt.millisecondsSinceEpoch,
        sourceScheduledAt.millisecondsSinceEpoch,
        leadTime,
        title,
        body,
      );
}

extension on String {
  String? ifEmptyAsNull() {
    return isEmpty ? null : this;
  }
}

NotificationLeadTime _leadTimeFromName(String? value) {
  return switch (value) {
    'fiveMinutes' => NotificationLeadTime.fiveMinutes,
    'fifteenMinutes' => NotificationLeadTime.fifteenMinutes,
    'oneHour' => NotificationLeadTime.oneHour,
    'oneDay' => NotificationLeadTime.oneDay,
    _ => NotificationLeadTime.none,
  };
}
