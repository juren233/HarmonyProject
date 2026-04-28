import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCoordinator extends ChangeNotifier {
  static const String persistedJobsStorageKey = 'notification_jobs_snapshot_v1';
  static const String permissionPromptHandledStorageKey =
      'notification_permission_prompt_handled_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

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
  late final PermissionRequestGate<NotificationPermissionState>
      _permissionRequestGate =
      PermissionRequestGate<NotificationPermissionState>(
    promptHandledStorageKey: permissionPromptHandledStorageKey,
    isGranted: _isGrantedPermissionState,
    requestPermission: _requestPlatformPermission,
    openPermissionSettings: () async {
      await openNotificationSettings();
    },
  );

  NotificationPermissionState get permissionState => _permissionState;
  NotificationPlatformCapabilities get capabilities => _capabilities;
  String? get pushToken => _pushToken;
  bool get isInitialized => _initialized;
  bool get hasHandledPermissionPrompt =>
      _permissionRequestGate.hasHandledPermissionPrompt;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    try {
      await _adapter.initialize();
    } catch (error, stackTrace) {
      appLogController?.error(
        category: AppLogCategory.notifications,
        title: '通知桥接初始化失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }
    await _permissionRequestGate.load();
    await _refreshPlatformState(notify: false, includeCapabilities: true);
    try {
      _pushToken = await _adapter.registerPushToken();
    } catch (error, stackTrace) {
      appLogController?.error(
        category: AppLogCategory.notifications,
        title: '注册推送 Token 失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
      _pushToken = null;
    }
    var shouldDiscardPersistedSnapshots = false;
    if (_capabilities.maxScheduledNotificationCount != null) {
      try {
        await _adapter.resetScheduledNotifications();
        shouldDiscardPersistedSnapshots = true;
      } catch (error, stackTrace) {
        appLogController?.error(
          category: AppLogCategory.notifications,
          title: '重置系统通知失败',
          message: error.toString(),
          details: stackTrace.toString(),
        );
      }
    }
    List<_PersistedNotificationJobSnapshot> persistedSnapshots;
    if (shouldDiscardPersistedSnapshots) {
      persistedSnapshots = const <_PersistedNotificationJobSnapshot>[];
    } else {
      try {
        persistedSnapshots = await _loadPersistedSnapshots();
      } catch (error, stackTrace) {
        appLogController?.error(
          category: AppLogCategory.notifications,
          title: '恢复通知快照失败',
          message: error.toString(),
          details: stackTrace.toString(),
        );
        persistedSnapshots = const <_PersistedNotificationJobSnapshot>[];
      }
    }
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
    final previousState = _permissionState;
    final previousHandledPrompt = hasHandledPermissionPrompt;
    _permissionState =
        await _permissionRequestGate.requestOrOpenSettings(_permissionState);
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '通知权限更新',
      message: '通知权限请求结果：${_permissionState.name}',
      details: hasHandledPermissionPrompt ? 'systemPromptHandled: true' : null,
    );
    if (_permissionState != previousState ||
        hasHandledPermissionPrompt != previousHandledPrompt) {
      notifyListeners();
    }
    return _permissionState;
  }

  Future<void> syncFromStore(PetNoteStore store) async {
    final builtSnapshots = _buildJobsFromStore(store);
    final snapshots = _limitJobsToPlatformCapacity(builtSnapshots);
    final nextKeys = snapshots.keys.toSet();
    final staleKeys = _scheduledSnapshots.keys.toSet().difference(nextKeys);
    final skippedForCapacity = builtSnapshots.length - snapshots.length;

    for (final key in staleKeys) {
      await _adapter.cancelNotification(key);
    }
    for (final entry in snapshots.entries) {
      final previous = _scheduledSnapshots[entry.key];
      final next = entry.value;
      if (previous == next && await _hasPlatformNotification(entry.key)) {
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
      message: '已同步 ${snapshots.length} 条通知任务，取消 ${staleKeys.length} 条旧任务。'
          '${skippedForCapacity > 0 ? '因系统上限暂缓 $skippedForCapacity 条较远提醒。' : ''}',
    );
  }

  Future<bool> _hasPlatformNotification(String key) async {
    try {
      return await _adapter.hasScheduledNotification(key);
    } catch (error, stackTrace) {
      appLogController?.warning(
        category: AppLogCategory.notifications,
        title: '回查系统通知失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
      return false;
    }
  }

  Future<NotificationLaunchIntent?> consumeLaunchIntent() {
    return _adapter.getInitialLaunchIntent();
  }

  Future<NotificationLaunchIntent?> consumeForegroundTap() {
    return _adapter.consumeForegroundTap();
  }

  Future<void> showUpdateNotification({
    required String versionLabel,
    required Uri releaseUrl,
  }) {
    return _adapter.showUpdateNotification(
      title: '宠记App新版$versionLabel已发布',
      body: '点击查看更新内容',
      releaseUrl: releaseUrl,
    );
  }

  Future<NotificationSettingsOpenResult> openNotificationSettings() {
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '打开通知设置',
      message: '准备打开系统通知设置。',
    );
    return _adapter.openNotificationSettings();
  }

  Future<NotificationSettingsOpenResult> openExactAlarmSettings() {
    appLogController?.info(
      category: AppLogCategory.notifications,
      title: '打开精确闹钟设置',
      message: '准备打开系统精确闹钟设置。',
    );
    return _adapter.openExactAlarmSettings();
  }

  Future<bool> refreshPlatformState() {
    return _refreshPlatformState(notify: true, includeCapabilities: true);
  }

  bool get hasGrantedPermission => _isGrantedPermissionState(_permissionState);

  bool get shouldOpenSettingsForPermissionRequest => _permissionRequestGate
      .shouldOpenSettingsForPermissionRequest(_permissionState);

  Map<String, _PersistedNotificationJobSnapshot> _buildJobsFromStore(
    PetNoteStore store,
  ) {
    final jobs = <String, _PersistedNotificationJobSnapshot>{};
    final now = _nowProvider();
    final petNamesById = <String, String>{
      for (final pet in store.pets) pet.id: pet.name,
    };

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
      jobs[payload.key] = _PersistedNotificationJobSnapshot(
        payload: payload,
        scheduledAt: triggerAt,
        sourceScheduledAt: todo.dueAt,
        leadTime: todo.notificationLeadTime,
        title: _notificationTitle(todo.title, fallback: '待办提醒'),
        body: _notificationBody(
          petName: petNamesById[todo.petId],
          note: todo.note,
        ),
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
      jobs[payload.key] = _PersistedNotificationJobSnapshot(
        payload: payload,
        scheduledAt: triggerAt,
        sourceScheduledAt: reminder.scheduledAt,
        leadTime: reminder.notificationLeadTime,
        title: _notificationTitle(reminder.title, fallback: '提醒事项'),
        body: _notificationBody(
          petName: petNamesById[reminder.petId],
          note: reminder.note,
        ),
      );
    }

    return jobs;
  }

  Map<String, _PersistedNotificationJobSnapshot> _limitJobsToPlatformCapacity(
    Map<String, _PersistedNotificationJobSnapshot> jobs,
  ) {
    final limit = _capabilities.maxScheduledNotificationCount;
    if (limit == null || limit <= 0 || jobs.length <= limit) {
      return jobs;
    }
    final entries = jobs.entries.toList()
      ..sort((left, right) {
        final scheduledCompare =
            left.value.scheduledAt.compareTo(right.value.scheduledAt);
        if (scheduledCompare != 0) {
          return scheduledCompare;
        }
        return left.key.compareTo(right.key);
      });
    return Map<String, _PersistedNotificationJobSnapshot>.fromEntries(
      entries.take(limit),
    );
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
    var nextPermissionState = _permissionState;
    var nextCapabilities = _capabilities;

    try {
      nextPermissionState = await _adapter.getPermissionState();
    } catch (error, stackTrace) {
      appLogController?.error(
        category: AppLogCategory.notifications,
        title: '读取通知权限失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }

    if (includeCapabilities) {
      try {
        nextCapabilities = await _adapter.getCapabilities();
      } catch (error, stackTrace) {
        appLogController?.error(
          category: AppLogCategory.notifications,
          title: '读取通知能力失败',
          message: error.toString(),
          details: stackTrace.toString(),
        );
      }
    }

    var promptHandledChanged = false;
    try {
      final platformHandledPrompt = await _adapter.hasHandledPermissionPrompt();
      promptHandledChanged = await _permissionRequestGate
          .rememberHandledPromptFromSystem(platformHandledPrompt);
    } catch (error, stackTrace) {
      appLogController?.error(
        category: AppLogCategory.notifications,
        title: '读取权限弹窗操作状态失败',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }

    final changed = nextPermissionState != _permissionState ||
        nextCapabilities != _capabilities ||
        promptHandledChanged;
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
    final preferences = await _loadPreferences();
    if (preferences == null) {
      return const <_PersistedNotificationJobSnapshot>[];
    }
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
    final preferences = await _loadPreferences();
    if (preferences == null) {
      return;
    }
    final payload = jsonEncode(
      snapshots.map((snapshot) => snapshot.toMap()).toList(growable: false),
    );
    await preferences.setString(persistedJobsStorageKey, payload);
  }

  Future<SharedPreferences?> _loadPreferences() async {
    try {
      return await SharedPreferences.getInstance()
          .timeout(_preferencesLoadTimeout);
    } on TimeoutException catch (error) {
      appLogController?.warning(
        category: AppLogCategory.notifications,
        title: '通知偏好读取超时',
        message: error.toString(),
      );
    } catch (error, stackTrace) {
      appLogController?.warning(
        category: AppLogCategory.notifications,
        title: '通知偏好不可用',
        message: error.toString(),
        details: stackTrace.toString(),
      );
    }
    return null;
  }

  Future<PermissionRequestOutcome<NotificationPermissionState>>
      _requestPlatformPermission() {
    return _adapter.requestPermission();
  }
}

bool _isGrantedPermissionState(NotificationPermissionState state) {
  return state == NotificationPermissionState.authorized ||
      state == NotificationPermissionState.provisional;
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
      eventScheduledAt: sourceScheduledAt,
      reminderLeadTimeMinutes: leadTimeDuration(leadTime).inMinutes,
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
    'threeDays' => NotificationLeadTime.threeDays,
    'sevenDays' => NotificationLeadTime.sevenDays,
    _ => NotificationLeadTime.none,
  };
}

String _notificationTitle(String value, {required String fallback}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _notificationBody({required String? petName, required String note}) {
  final normalizedPetName = _notificationTextPart(petName, fallback: '爱宠');
  final normalizedNote = note.trim();
  if (normalizedNote.isEmpty) {
    return normalizedPetName;
  }
  return '$normalizedPetName · $normalizedNote';
}

String _notificationTextPart(String? value, {required String fallback}) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}
