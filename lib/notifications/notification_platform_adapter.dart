import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/permissions/permission_request_gate.dart';

abstract class NotificationPlatformAdapter {
  Future<void> initialize();

  Future<NotificationPermissionState> getPermissionState();

  Future<bool> hasHandledPermissionPrompt();

  Future<PermissionRequestOutcome<NotificationPermissionState>>
      requestPermission();

  Future<void> scheduleLocalNotification(NotificationJob job);

  Future<bool> hasScheduledNotification(String key);

  Future<void> cancelNotification(String key);

  Future<void> resetScheduledNotifications();

  Future<NotificationLaunchIntent?> getInitialLaunchIntent();

  Future<NotificationLaunchIntent?> consumeForegroundTap();

  Future<String?> registerPushToken();

  Future<NotificationSettingsOpenResult> openNotificationSettings();

  Future<NotificationSettingsOpenResult> openExactAlarmSettings();

  Future<NotificationPlatformCapabilities> getCapabilities();
}
