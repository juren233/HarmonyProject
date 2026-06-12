import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/app/pet_device_settings_page.dart';
import 'package:petnote/app/pet_pairing_page.dart';
import 'package:petnote/platform/device_keep_alive.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';

class PetDeviceHome extends StatefulWidget {
  const PetDeviceHome({
    super.key,
    required this.settingsController,
    this.storeLoader,
    this.syncService,
    this.keepAlive,
  });

  final AppSettingsController settingsController;
  final Future<PetNoteStore> Function()? storeLoader;
  final SyncService? syncService;
  final DeviceKeepAlive? keepAlive;

  @override
  State<PetDeviceHome> createState() => _PetDeviceHomeState();
}

class _PetDeviceHomeState extends State<PetDeviceHome> {
  PetNoteStore? _store;
  SyncService? _syncService;
  late final DeviceKeepAlive _keepAlive;
  bool _keepAliveStarted = false;

  @override
  void initState() {
    super.initState();
    _keepAlive = widget.keepAlive ?? DeviceKeepAlive();
    widget.settingsController.addListener(_handleSettingsChanged);
    unawaited(_loadStore());
  }

  @override
  void didUpdateWidget(covariant PetDeviceHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settingsController, widget.settingsController)) {
      oldWidget.settingsController.removeListener(_handleSettingsChanged);
      widget.settingsController.addListener(_handleSettingsChanged);
      unawaited(_restartSync());
    }
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_handleSettingsChanged);
    _store?.dispose();
    unawaited(_stopKeepAlive());
    super.dispose();
  }

  Future<void> _loadStore() async {
    final store = await (widget.storeLoader ?? PetNoteStore.load)();
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() => _store = store);
    await _restartSync();
  }

  Future<void> _restartSync() async {
    final store = _store;
    if (store == null) {
      return;
    }
    final service = widget.syncService ??
        SyncService.instance ??
        SyncService(settings: widget.settingsController);
    SyncService.instance = service;
    _syncService = service;
    if (widget.settingsController.householdId == null) {
      await service.stop();
      await _stopKeepAlive();
      return;
    }
    await service.ensureStartedForPet(store: store);
    await _syncKeepAlive();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSettingsChanged() {
    unawaited(_restartSync());
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 配对页不依赖 store，优先返回以避免从引导转场进入时闪现加载圈。
    if (widget.settingsController.householdId == null) {
      return PetPairingPage(settingsController: widget.settingsController);
    }
    final store = _store;
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final controller = _syncService?.petController;
    final listenables = <Listenable>[
      widget.settingsController,
      store,
      if (controller != null) ...[
        controller.lastSyncedAt,
        controller.pendingItemKeys,
        controller.servedPetIdOverride,
        controller.removedByOwner,
      ],
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        if (controller?.removedByOwner.value == true) {
          unawaited(widget.settingsController.clearSyncPairing());
        }
        return PetDeviceDashboard(
          store: store,
          servedPetId: controller?.servedPetIdOverride.value ??
              widget.settingsController.servedPetId,
          syncStatusLabel: _syncStatusLabel(_syncService),
          pendingItemKeys:
              controller?.pendingItemKeys.value ?? const <String>{},
          onSelectServedPet: widget.settingsController.setServedPetId,
          onMarkDone: (action) => controller?.sendAction(action),
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => PetDeviceSettingsPage(
                settingsController: widget.settingsController,
                keepScreenOn: widget.settingsController.petKeepScreenOn,
                onKeepScreenOnChanged: (value) async {
                  await widget.settingsController.setPetKeepScreenOn(value);
                  await _syncKeepAlive();
                },
                onRepair: () => setState(() {}),
              ),
            ),
          ),
        );
      },
    );
  }

  String _syncStatusLabel(SyncService? service) {
    final transport = service?.transport;
    return switch (transport?.state.value) {
      SyncConnectionState.connected => '已连接',
      SyncConnectionState.connecting => '连接中',
      _ => '重连中',
    };
  }

  Future<void> _syncKeepAlive() async {
    if (widget.settingsController.deviceRole != DeviceRole.pet ||
        widget.settingsController.householdId == null) {
      await _stopKeepAlive();
      return;
    }
    await _keepAlive.setKeepScreenOn(widget.settingsController.petKeepScreenOn);
    if (!_keepAliveStarted) {
      await _keepAlive.startBackgroundKeepAlive();
      _keepAliveStarted = true;
    }
  }

  Future<void> _stopKeepAlive() async {
    if (_keepAliveStarted) {
      await _keepAlive.stopBackgroundKeepAlive();
      _keepAliveStarted = false;
    }
    await _keepAlive.setKeepScreenOn(false);
  }
}

extension on SyncService {
  SyncTransport? get transport => debugTransport;
}
