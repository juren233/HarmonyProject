import 'package:flutter/material.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum RemoteVideoMode { call, watch }

class RemoteVideoPillButton extends StatelessWidget {
  const RemoteVideoPillButton({super.key, required this.pet});

  // 连接对象固定为爱宠页当前展示的宠物。
  final Pet pet;

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
                  _openPlaceholder(context, sheetContext, RemoteVideoMode.call),
            ),
            ListTile(
              key: const ValueKey('remote_video_option_watch'),
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('先看看它'),
              onTap: () => _openPlaceholder(
                  context, sheetContext, RemoteVideoMode.watch),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openPlaceholder(
    BuildContext context,
    BuildContext sheetContext,
    RemoteVideoMode mode,
  ) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RemoteVideoPlaceholderPage(mode: mode, pet: pet),
      ),
    );
  }
}

class RemoteVideoPlaceholderPage extends StatelessWidget {
  const RemoteVideoPlaceholderPage({
    super.key,
    required this.mode,
    required this.pet,
    this.devicesOverride,
  });

  final RemoteVideoMode mode;
  final Pet pet;
  // 测试注入用；为空时读取同步引擎的实时设备列表。
  final List<SyncedDeviceInfo>? devicesOverride;

  @override
  Widget build(BuildContext context) {
    final devices = devicesOverride ??
        SyncService.instance?.ownerEngine?.devices.value ??
        const [];
    // 只连当前宠物：明确指派给它的宠物端优先；未指派宠物的设备视为可服务它；
    // 指派给其他宠物的设备一律不算。
    final assignedDevices = devices.where(
      (device) => device.role == 'pet' && device.servedPetId == pet.id,
    );
    final unassignedDevices = devices.where(
      (device) => device.role == 'pet' && device.servedPetId == null,
    );
    final petDevices = [...assignedDevices, ...unassignedDevices];
    final connectedDevice = petDevices.isEmpty
        ? null
        : petDevices.firstWhere(
            (device) => device.online,
            orElse: () => petDevices.first,
          );
    final statusLabel = connectedDevice == null
        ? '未配对宠物端'
        : '${connectedDevice.name} ${connectedDevice.online ? '在线' : '离线'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(mode == RemoteVideoMode.call ? '视频通话' : '先看看它'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.ondemand_video_rounded,
              size: 58,
              color: Color(0xFF9AA3B2),
            ),
            const SizedBox(height: 14),
            Text(
              statusLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '连接对象：${pet.name}',
              key: const ValueKey('remote_video_target_pet'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6C7280),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '实时画面功能即将上线',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6C7280),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
