import 'package:flutter/services.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/permissions/permission_request_gate.dart';

class MethodChannelNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  MethodChannelNotificationPlatformAdapter({
    MethodChannel? channel,
    this.appLogController,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/notifications';

  final MethodChannel _channel;
  final AppLogController? appLogController;

  @override
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '通知桥接初始化',
        message: '原生通知桥接初始化完成。',
      );
    } on MissingPluginException {
      appLogController?.warning(
        category: AppLogCategory.nativeBridge,
        title: '通知桥接缺失',
        message: '当前平台未接入通知 MethodChannel。',
      );
    }
  }

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    try {
      final result = await _channel.invokeMethod<String>('getPermissionState');
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '读取通知权限',
        message: '原生通知权限状态：$result',
      );
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '读取权限弹窗操作状态',
        message: result == true ? '系统权限弹窗已被用户处理。' : '系统权限弹窗尚未确认被用户处理。',
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '请求通知权限',
        message: '原生通知权限请求结果：${outcome.state.name}',
        details: outcome.promptHandledSystemDialog
            ? 'systemPromptHandled: true'
            : 'systemPromptHandled: false',
      );
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '调度本地通知',
        message: '原生通知已提交调度：${job.key}',
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '回查本地通知',
        message: result == true ? '系统通知仍存在：$key' : '系统通知不存在：$key',
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '取消本地通知',
        message: '原生通知已取消：$key',
      );
    } on MissingPluginException {
      // Unsupported platforms silently skip cancellation for now.
    }
  }

  @override
  Future<void> resetScheduledNotifications() async {
    try {
      await _channel.invokeMethod<void>('resetScheduledNotifications');
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '重置本地通知',
        message: '原生通知已按当前数据准备重建。',
      );
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
      final result = await _channel.invokeMethod<String>('registerPushToken');
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '注册推送 Token',
        message: result == null ? '当前未返回推送 Token。' : '推送 Token 注册完成。',
      );
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '打开通知设置',
        message: '原生通知设置打开结果：$result',
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '打开精确闹钟设置',
        message: '原生精确闹钟设置打开结果：$result',
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
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '读取通知能力',
        message: '原生通知能力：${result?['exactAlarmStatus'] ?? 'unsupported'}',
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
