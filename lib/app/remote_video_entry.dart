import 'package:flutter/material.dart';
import 'package:petnote/app/remote_video_call_page.dart';
import 'package:petnote/rtc/rtc_media_permission_coordinator.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';
import 'package:petnote/state/petnote_store.dart';

enum RemoteVideoMode { call, watch }

class RemoteVideoPillButton extends StatelessWidget {
  const RemoteVideoPillButton({
    super.key,
    required this.pet,
    this.permissionCoordinator,
  });

  // 连接对象固定为爱宠页当前展示的宠物。
  final Pet pet;
  final RtcMediaPermissionCoordinator? permissionCoordinator;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('remote_video_pill'),
      color: const Color(0xFFF2A65A),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showOptions(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '远程视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('remote_video_option_call'),
              leading: const Icon(Icons.video_call_rounded),
              title: const Text('视频通话'),
              onTap: () =>
                  _openCallPage(context, sheetContext, RemoteVideoMode.call),
            ),
            ListTile(
              key: const ValueKey('remote_video_option_watch'),
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('先看看它'),
              onTap: () =>
                  _openCallPage(context, sheetContext, RemoteVideoMode.watch),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openCallPage(
    BuildContext context,
    BuildContext sheetContext,
    RemoteVideoMode mode,
  ) async {
    Navigator.of(sheetContext).pop();
    final canStart = await ensureRtcMediaPermissionBeforeRemoteVideo(
      context: context,
      permissionCoordinator: permissionCoordinator,
    );
    if (!canStart || !context.mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RemoteVideoCallPage(mode: mode, pet: pet),
      ),
    );
  }
}

Future<bool> ensureRtcMediaPermissionBeforeRemoteVideo({
  required BuildContext context,
  RtcMediaPermissionCoordinator? permissionCoordinator,
}) async {
  final coordinator =
      permissionCoordinator ?? DefaultRtcMediaPermissionCoordinator();
  if (!coordinator.isInitialized) {
    await coordinator.initialize();
  }
  if (!context.mounted) {
    return false;
  }
  if (coordinator.hasGrantedPermission) {
    return true;
  }

  final shouldOpenSettings = coordinator.shouldOpenSettingsForPermissionRequest;
  final shouldRequestPermission = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('需要开启摄像头和麦克风权限'),
            content: Text(
              shouldOpenSettings
                  ? '远程视频需要摄像头和麦克风权限。请前往App设置页手动开启后，再回来发起通话。'
                  : '远程视频需要摄像头和麦克风权限。授权成功后才能发起通话。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('暂不授权'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(shouldOpenSettings ? '去设置' : '去授权'),
              ),
            ],
          );
        },
      ) ??
      false;
  if (!shouldRequestPermission) {
    return false;
  }

  if (coordinator.shouldOpenSettingsForPermissionRequest) {
    final openResult = await coordinator.openMediaPermissionSettings();
    if (openResult != RtcMediaSettingsOpenResult.opened) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('未能打开系统设置，请稍后重试。')),
        );
      }
      return false;
    }
    await coordinator.refreshPlatformState();
    return coordinator.hasGrantedPermission;
  }

  final nextState = await coordinator.requestPermission();
  if (!context.mounted) {
    return false;
  }
  if (nextState == RtcMediaPermissionState.authorized) {
    return true;
  }
  await coordinator.refreshPlatformState();
  if (!context.mounted) {
    return false;
  }
  if (coordinator.hasGrantedPermission) {
    return true;
  }
  await Future<void>.delayed(const Duration(milliseconds: 220));
  await coordinator.refreshPlatformState();
  return coordinator.hasGrantedPermission;
}
