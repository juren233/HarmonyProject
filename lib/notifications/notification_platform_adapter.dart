import 'package:petnote/notifications/notification_models.dart';

abstract class NotificationPlatformAdapter {
  Future<void> initialize();

  Future<NotificationPermissionState> getPermissionState();

  Future<NotificationPermissionState> requestPermission();

  Future<void> scheduleLocalNotification(NotificationJob job);

  Future<void> cancelNotification(String key);

  Future<NotificationLaunchIntent?> getInitialLaunchIntent();

  Future<NotificationLaunchIntent?> consumeForegroundTap();

  Future<String?> registerPushToken();

  Future<NotificationSettingsOpenResult> openNotificationSettings();
}
