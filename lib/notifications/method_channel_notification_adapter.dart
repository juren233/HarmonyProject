import 'package:flutter/services.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';

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
      // Keep the adapter functional on unsupported platforms and tests.
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
  Future<NotificationPermissionState> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<String>('requestPermission');
      return notificationPermissionStateFromName(result);
    } on MissingPluginException {
      return NotificationPermissionState.unsupported;
    }
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    try {
      await _channel.invokeMethod<void>(
          'scheduleLocalNotification', job.toMap());
    } on MissingPluginException {
      // Unsupported platforms silently skip scheduling for now.
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
      return await _channel.invokeMethod<String>('registerPushToken');
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
}
