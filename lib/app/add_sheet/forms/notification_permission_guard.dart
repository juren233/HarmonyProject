import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';

Future<bool> ensureNotificationPermissionBeforeChecklistSave({
  required BuildContext context,
  required NotificationCoordinator? notificationCoordinator,
  Future<NotificationCoordinator?> Function()? notificationCoordinatorLoader,
}) async {
  final coordinator = notificationCoordinator;
  if (coordinator != null && coordinator.hasGrantedPermission) {
    return true;
  }

  final permissionName = defaultTargetPlatform.name == 'ohos' ? '日历权限' : '通知权限';
  final shouldOpenSettings =
      coordinator?.shouldOpenSettingsForPermissionRequest ?? false;
  final actionLabel = shouldOpenSettings ? '去设置' : '去授权';
  final shouldRequestPermission = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('需要开启$permissionName'),
            content: Text(shouldOpenSettings
                ? '创建待办或提醒前，需要先授权$permissionName。授权成功后才能保存并接收系统提醒。请前往App设置页手动开启后，再回来保存。'
                : '创建待办或提醒前，需要先授权$permissionName。授权成功后才能保存并接收系统提醒。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('暂不授权'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(actionLabel),
              ),
            ],
          );
        },
      ) ??
      false;

  if (!shouldRequestPermission) {
    return false;
  }

  var nextCoordinator = coordinator;
  if (nextCoordinator == null || !nextCoordinator.isInitialized) {
    nextCoordinator =
        await notificationCoordinatorLoader?.call() ?? nextCoordinator;
  }
  if (nextCoordinator == null) {
    if (!context.mounted) {
      return false;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('通知能力初始化中，请稍后再试。')),
    );
    return false;
  }

  if (nextCoordinator.shouldOpenSettingsForPermissionRequest) {
    final openResult = await nextCoordinator.openNotificationSettings();
    if (openResult != NotificationSettingsOpenResult.opened) {
      if (!context.mounted) {
        return false;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('未能打开系统设置，请稍后重试。')),
      );
      return false;
    }
    await nextCoordinator.refreshPlatformState();
    return nextCoordinator.hasGrantedPermission;
  }

  final nextState = await nextCoordinator.requestPermission();
  if (nextState.name == 'authorized' || nextState.name == 'provisional') {
    return true;
  }

  await nextCoordinator.refreshPlatformState();
  if (nextCoordinator.hasGrantedPermission) {
    return true;
  }

  await Future<void>.delayed(const Duration(milliseconds: 220));
  await nextCoordinator.refreshPlatformState();
  return nextCoordinator.hasGrantedPermission;
}
