import 'package:flutter/services.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/permissions/permission_request_gate.dart';

class MethodChannelNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  MethodChannelNotificationPlatformAdapter({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/notifications';

  final MethodChannel _channel;

  @override
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } on MissingPluginException {
      // Unsupported platforms silently skip initialization.
    }
  }

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    try {
      final result = await _channel.invokeMethod<String>('getPermissionState');
      return notificationPermissionStateFromName(result);
    } on MissingPluginException {
      return NotificationPermissionState.unsupported;
    }
  }

  @override
  Future<bool> hasHandledPermissionPrompt() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasHandledPermissionPrompt',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<PermissionRequestOutcome<NotificationPermissionState>>
      requestPermission() async {
    try {
      final result = await _channel.invokeMethod<Object?>('requestPermission');
      final outcome = _permissionRequestOutcomeFromResult(result);
      return outcome;
    } on MissingPluginException {
      return const PermissionRequestOutcome(
        state: NotificationPermissionState.unsupported,
      );
    }
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    try {
      await _channel.invokeMethod<void>(
        'scheduleLocalNotification',
        job.toMap(),
      );
    } on MissingPluginException {
      // Unsupported platforms silently skip scheduling for now.
    }
  }

  @override
  Future<bool> hasScheduledNotification(String key) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasScheduledNotification',
        key,
      );
      return result ?? false;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<void> cancelNotification(String key) async {
    try {
      await _channel.invokeMethod<void>('cancelNotification', key);
    } on MissingPluginException {
      // Unsupported platforms silently skip cancellation for now.
    }
  }

  @override
  Future<void> resetScheduledNotifications() async {
    try {
      await _channel.invokeMethod<void>('resetScheduledNotifications');
    } on MissingPluginException {
      // Unsupported platforms silently skip cancellation for now.
    }
  }

  @override
  Future<void> showUpdateNotification({
    required String title,
    required String body,
    required Uri releaseUrl,
  }) async {
    try {
      await _channel.invokeMethod<void>('showUpdateNotification', {
        'title': title,
        'body': body,
        'releaseUrl': releaseUrl.toString(),
      });
    } on MissingPluginException {
      // 不支持通知桥接的平台跳过更新提醒。
    }
  }

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getInitialLaunchIntent',
      );
      if (result == null) {
        return null;
      }
      return NotificationLaunchIntent.fromMap(result);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'consumeForegroundTap',
      );
      if (result == null) {
        return null;
      }
      return NotificationLaunchIntent.fromMap(result);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> registerPushToken() async {
    try {
      final result = await _channel.invokeMethod<String>('registerPushToken');
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'openNotificationSettings',
      );
      return notificationSettingsOpenResultFromName(result);
    } on MissingPluginException {
      return NotificationSettingsOpenResult.unsupported;
    }
  }

  @override
  Future<NotificationSettingsOpenResult> openExactAlarmSettings() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'openExactAlarmSettings',
      );
      return notificationSettingsOpenResultFromName(result);
    } on MissingPluginException {
      return NotificationSettingsOpenResult.unsupported;
    }
  }

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getCapabilities',
      );
      return NotificationPlatformCapabilities.fromMap(result);
    } on MissingPluginException {
      return const NotificationPlatformCapabilities();
    }
  }

  PermissionRequestOutcome<NotificationPermissionState>
      _permissionRequestOutcomeFromResult(Object? result) {
    if (result is Map) {
      return PermissionRequestOutcome<NotificationPermissionState>(
        state: notificationPermissionStateFromName(result['state'] as String?),
        promptHandledSystemDialog: result['promptHandled'] as bool? ?? false,
      );
    }
    return PermissionRequestOutcome<NotificationPermissionState>(
      state: notificationPermissionStateFromName(result as String?),
    );
  }
}
