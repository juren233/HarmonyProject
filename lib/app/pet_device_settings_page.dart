import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_service.dart';

class PetDeviceSettingsPage extends StatelessWidget {
  const PetDeviceSettingsPage({
    super.key,
    required this.settingsController,
    required this.keepScreenOn,
    required this.onKeepScreenOnChanged,
    required this.onRepair,
    SyncSecretStore? secretStore,
  }) : _secretStore = secretStore;

  final AppSettingsController settingsController;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOnChanged;
  final VoidCallback onRepair;
  final SyncSecretStore? _secretStore;

  @override
  Widget build(BuildContext context) {
    return HyperPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('宠物端设置'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: petNoteOverlayStyleForTheme(Theme.of(context)),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              SectionCard(
                title: 'App 模式',
                children: [
                  RadioGroup<DeviceRole>(
                    groupValue: settingsController.deviceRole,
                    onChanged: (value) {
                      if (value == DeviceRole.owner) {
                        _confirmOwnerMode(context);
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile<DeviceRole>(
                          key: ValueKey('settings_mode_pet'),
                          value: DeviceRole.pet,
                          title: Text('宠物端'),
                        ),
                        RadioListTile<DeviceRole>(
                          key: ValueKey('settings_mode_owner'),
                          value: DeviceRole.owner,
                          title: Text('主人端'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SectionCard(
                title: '配对',
                children: [
                  ListRow(
                    title: '服务器地址',
                    subtitle: settingsController.syncServerUrl ?? '未配置',
                  ),
                  ListRow(
                    title: '家庭组',
                    subtitle: settingsController.householdId ?? '未配对',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const ValueKey('settings_repair'),
                      onPressed: () => _confirmRepair(context),
                      child: const Text('重新配对'),
                    ),
                  ),
                ],
              ),
              SectionCard(
                title: '屏幕',
                children: [
                  SwitchListTile(
                    key: const ValueKey('settings_keep_screen_on'),
                    value: keepScreenOn,
                    onChanged: onKeepScreenOnChanged,
                    title: const Text('屏幕常亮'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmOwnerMode(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换主人端'),
        content: const Text('切换后此设备将进入完整管理界面'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await SyncService.instance?.stop();
    await settingsController.setDeviceRole(DeviceRole.owner);
  }

  Future<void> _confirmRepair(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新配对'),
        content: const Text('当前配对会被清除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await settingsController.clearSyncPairing();
    await (_secretStore ?? MethodChannelSyncSecretStore()).deleteSharedKey();
    onRepair();
  }
}
