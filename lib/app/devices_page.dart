import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/owner_pairing_flow.dart';
import 'package:petnote/sync/pairing_flow.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class DevicesPage extends StatefulWidget {
  DevicesPage({
    super.key,
    required this.settingsController,
    this.store,
    this.initialDevices,
    this.ownerPairingFlow,
    this.pairingFlow,
    DateTime Function()? now,
    OfficialSyncServerResolver? officialServerResolver,
  })  : officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver(),
        now = now ?? DateTime.now;

  final AppSettingsController settingsController;
  final PetNoteStore? store;
  final List<SyncedDeviceInfo>? initialDevices;
  final OwnerPairingFlow? ownerPairingFlow;
  final PairingFlow? pairingFlow;
  final DateTime Function() now;
  final OfficialSyncServerResolver officialServerResolver;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late final TextEditingController _serverController;
  late SyncServerMode _serverMode;
  OwnerPairingFlow? _pairingFlow;
  Timer? _countdownTimer;
  bool _generating = false;
  BuildContext? _pairingDialogContext;

  @override
  void initState() {
    super.initState();
    _serverMode = widget.settingsController.syncServerMode;
    _serverController =
        TextEditingController(text: widget.settingsController.syncServerUrl);
    SyncService.instance?.ownerEngine?.requestDevices();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pairingFlow?.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = SyncService.instance?.ownerEngine;
    return HyperPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('设备'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: petNoteOverlayStyleForTheme(Theme.of(context)),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: engine?.devices ?? const AlwaysStoppedAnimation(null),
            builder: (context, _) {
              final currentDeviceId = widget.settingsController.deviceId;
              final devices = (widget.initialDevices ??
                      engine?.devices.value ??
                      const <SyncedDeviceInfo>[])
                  .where((device) => device.deviceId != currentDeviceId)
                  .toList(growable: false);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  SectionCard(
                    title: '同步服务器',
                    children: [
                      HyperSegmentedControl(
                        key: const ValueKey('devices_server_mode_control'),
                        items: const [
                          SegmentItem(
                            key: 'official',
                            label: '官方服务器',
                          ),
                          SegmentItem(
                            key: 'custom',
                            label: '自定义',
                          ),
                        ],
                        selectedKey: _serverMode.name,
                        onChanged: _setServerModeByKey,
                      ),
                      if (_serverMode == SyncServerMode.custom)
                        TextField(
                          key: const ValueKey('devices_server_field'),
                          controller: _serverController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: '服务器地址'),
                          onSubmitted: _saveServerUrl,
                          onEditingComplete: () =>
                              _saveServerUrl(_serverController.text),
                        ),
                    ],
                  ),
                  SectionCard(
                    title: '添加设备',
                    children: [
                      const Text('生成 4 位配对码后，在另一台设备输入即可加入当前家庭组。'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('devices_generate_code'),
                          onPressed: _generating ? null : _generateCode,
                          child: Text(_generating ? '生成中' : '生成配对码'),
                        ),
                      ),
                    ],
                  ),
                  SectionCard(
                    title: '已配对设备',
                    children: [
                      ListRow(
                        key: const ValueKey('devices_join_code_entry'),
                        title: '输入配对码',
                        subtitle: '加入另一台设备',
                        onTap: _showJoinCodeDialog,
                      ),
                      if (devices.isEmpty)
                        const ListRow(title: '暂无设备', subtitle: '未配对')
                      else
                        for (final device in devices)
                          _DeviceRow(
                            key: ValueKey('device_item_${device.deviceId}'),
                            device: device,
                            petName: _petName(device.servedPetId),
                            onRename: (name) =>
                                engine?.renameDevice(device.deviceId, name),
                            onAssignPet: (petId) =>
                                engine?.assignPet(device.deviceId, petId),
                            onRemove: () =>
                                engine?.removeDevice(device.deviceId),
                            pets: widget.store?.pets ?? const <Pet>[],
                          ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _saveServerUrl(String value) async {
    await widget.settingsController.setSyncServerUrl(
      normalizeSyncServerUrl(value),
    );
  }

  Future<void> _setServerModeByKey(String key) async {
    final value =
        key == 'custom' ? SyncServerMode.custom : SyncServerMode.official;
    setState(() => _serverMode = value);
    await widget.settingsController.setSyncServerMode(value);
  }

  Future<void> _generateCode() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);
    try {
      final serverUrl = await _resolveServerUrl();
      final flow = widget.ownerPairingFlow ??
          (_pairingFlow ??=
              OwnerPairingFlow(settingsController: widget.settingsController));
      final session = await flow.createAsOwner(
        serverUrl: serverUrl,
        deviceName: widget.settingsController.deviceName ?? '主人设备',
        onPeerJoined: (_, name, petDataPolicy) async {
          final ownerPolicy = ownerInitialPolicyForPeerSelection(petDataPolicy);
          await widget.settingsController.setPendingInitialSyncPolicy(
            ownerPolicy,
          );
          final service = SyncService.instance;
          final store = widget.store;
          if (service != null && store != null) {
            await service.ensureStarted(store: store);
          }
          if (!mounted) {
            return;
          }
          _closePairingDialog();
          messenger.showSnackBar(SnackBar(content: Text('$name 已配对 ✓')));
        },
      );
      if (!mounted) {
        return;
      }
      if (widget.now().millisecondsSinceEpoch >= session.expiresAtMs) {
        if (!identical(flow, widget.ownerPairingFlow)) {
          unawaited(flow.dispose());
          _pairingFlow = null;
        }
        return;
      }
      _showCodeDialog(session);
    } on PairingException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on OfficialSyncServerException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  Future<String> _resolveServerUrl() async {
    if (_serverMode == SyncServerMode.custom) {
      await widget.settingsController.setSyncServerMode(SyncServerMode.custom);
      await _saveServerUrl(_serverController.text);
      final serverUrl = widget.settingsController.syncServerUrl;
      if (serverUrl == null || serverUrl.isEmpty) {
        throw const PairingException('请输入服务器地址');
      }
      return serverUrl;
    }
    await widget.settingsController.setSyncServerMode(SyncServerMode.official);
    final serverUrl = await widget.officialServerResolver.resolve();
    await widget.settingsController.setSyncServerUrl(serverUrl);
    _serverController.text = serverUrl;
    return serverUrl;
  }

  Future<void> _showJoinCodeDialog() async {
    final codeController = TextEditingController();
    var selectedPolicy = SyncDataPolicy.merge;
    var joining = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final messenger = ScaffoldMessenger.of(dialogContext);
              final navigator = Navigator.of(dialogContext);
              setDialogState(() => joining = true);
              var dialogClosed = false;
              try {
                final serverUrl = await _resolveServerUrl();
                final flow = widget.pairingFlow ??
                    PairingFlow(
                      settingsController: widget.settingsController,
                    );
                await flow.joinAsPet(
                  serverUrl: serverUrl,
                  code: codeController.text,
                  deviceName: widget.settingsController.deviceName ?? '当前设备',
                  dataPolicy: selectedPolicy,
                );
                if (!mounted) {
                  return;
                }
                navigator.pop();
                dialogClosed = true;
                messenger.showSnackBar(
                  const SnackBar(content: Text('配对成功')),
                );
              } on PairingException catch (error) {
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              } on OfficialSyncServerException catch (error) {
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              } finally {
                if (mounted && !dialogClosed) {
                  setDialogState(() => joining = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('输入配对码'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('devices_join_code_field'),
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: '配对码',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PairingPolicyRow(
                    key: const ValueKey('devices_join_policy_remote'),
                    title: '以另一台设备为准',
                    selected: selectedPolicy == SyncDataPolicy.remoteWins,
                    onTap: () => setDialogState(
                      () => selectedPolicy = SyncDataPolicy.remoteWins,
                    ),
                  ),
                  _PairingPolicyRow(
                    key: const ValueKey('devices_join_policy_local'),
                    title: '以当前设备为准',
                    selected: selectedPolicy == SyncDataPolicy.localWins,
                    onTap: () => setDialogState(
                      () => selectedPolicy = SyncDataPolicy.localWins,
                    ),
                  ),
                  _PairingPolicyRow(
                    key: const ValueKey('devices_join_policy_merge'),
                    title: '合并数据',
                    selected: selectedPolicy == SyncDataPolicy.merge,
                    onTap: () => setDialogState(
                      () => selectedPolicy = SyncDataPolicy.merge,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      joining ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const ValueKey('devices_join_submit'),
                  onPressed: joining ? null : submit,
                  child: Text(joining ? '配对中' : '开始配对'),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();
  }

  void _showCodeDialog(OwnerPairingSession session) {
    _countdownTimer?.cancel();
    StateSetter? refreshDialog;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.now().millisecondsSinceEpoch >= session.expiresAtMs) {
        _closePairingDialog();
        return;
      }
      if (mounted) {
        setState(() {});
        refreshDialog?.call(() {});
      }
    });
    showDialog<void>(
      context: context,
      builder: (context) {
        _pairingDialogContext = context;
        return AlertDialog(
          title: const Text('配对码'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              refreshDialog = setDialogState;
              final remainingMs =
                  session.expiresAtMs - widget.now().millisecondsSinceEpoch;
              final seconds =
                  remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.code,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('$seconds 秒后失效'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _countdownTimer?.cancel();
      _pairingDialogContext = null;
      unawaited(_pairingFlow?.dispose());
      _pairingFlow = null;
    });
  }

  void _closePairingDialog() {
    _countdownTimer?.cancel();
    final dialogContext = _pairingDialogContext;
    if (dialogContext == null) {
      return;
    }
    _pairingDialogContext = null;
    Navigator.of(dialogContext).pop();
  }

  String _petName(String? petId) {
    if (petId == null) {
      return '未指定';
    }
    for (final pet in widget.store?.pets ?? const <Pet>[]) {
      if (pet.id == petId) {
        return pet.name;
      }
    }
    return '未指定';
  }
}

class _PairingPolicyRow extends StatelessWidget {
  const _PairingPolicyRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : tokens.listRowBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colorScheme.primary : tokens.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

/// 将加入端选择转换为主人端应执行的初始同步策略。
SyncDataPolicy ownerInitialPolicyForPeerSelection(SyncDataPolicy peerPolicy) {
  if (peerPolicy == SyncDataPolicy.remoteWins) {
    return SyncDataPolicy.localWins;
  }
  if (peerPolicy == SyncDataPolicy.localWins) {
    return SyncDataPolicy.remoteWins;
  }
  return SyncDataPolicy.merge;
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.petName,
    required this.onRename,
    required this.onAssignPet,
    required this.onRemove,
    required this.pets,
  });

  final SyncedDeviceInfo device;
  final String petName;
  final ValueChanged<String> onRename;
  final ValueChanged<String?> onAssignPet;
  final VoidCallback onRemove;
  final List<Pet> pets;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: device.name,
      subtitle: '${device.online ? '在线' : '离线'} · $petName',
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'rename':
              _rename(context);
            case 'assign':
              _assignPet(context);
            case 'remove':
              _remove(context);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'assign', child: Text('更换服务宠物')),
          PopupMenuItem(value: 'remove', child: Text('解绑')),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      onRename(name.trim());
    }
  }

  Future<void> _assignPet(BuildContext context) async {
    final petId = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('未指定'),
              onTap: () => Navigator.of(context).pop(null),
            ),
            for (final pet in pets)
              ListTile(
                title: Text(pet.name),
                onTap: () => Navigator.of(context).pop(pet.id),
              ),
          ],
        ),
      ),
    );
    onAssignPet(petId);
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text(device.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onRemove();
    }
  }
}
