import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/app/pet_device_settings_page.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/pet_pairing_page.dart';
import 'package:petnote/app/remote_video_call_page.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/platform/device_keep_alive.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_incoming_call_controller.dart';
import 'package:petnote/rtc/rtc_media_permission_coordinator.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/powersync/powersync_spike_service.dart';
import 'package:petnote/sync/sync_engine_mode.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';

class PetDeviceHome extends StatefulWidget {
  const PetDeviceHome({
    super.key,
    required this.settingsController,
    this.storeLoader,
    this.syncService,
    this.powerSyncService,
    this.keepAlive,
    this.remoteVideoPermissionCoordinator,
  });

  final AppSettingsController settingsController;
  final Future<PetNoteStore> Function()? storeLoader;
  final SyncService? syncService;
  final PowerSyncSpikeService? powerSyncService;
  final DeviceKeepAlive? keepAlive;
  final RtcMediaPermissionCoordinator? remoteVideoPermissionCoordinator;

  @override
  State<PetDeviceHome> createState() => _PetDeviceHomeState();
}

class _PetDeviceHomeState extends State<PetDeviceHome> {
  PetNoteStore? _store;
  SyncService? _syncService;
  PowerSyncSpikeService? _powerSyncService;
  late final DeviceKeepAlive _keepAlive;
  RtcSignalingController? _rtcSignalingController;
  RtcIncomingCallController? _incomingCallController;
  SyncTransport? _incomingCallTransport;
  String? _incomingCallDeviceId;
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
    unawaited(_disposeIncomingCallController());
    unawaited(_powerSyncService?.stop());
    _powerSyncService?.dispose();
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
    if (widget.settingsController.syncEngineMode ==
        SyncEngineMode.powersyncSpike) {
      await _restartPowerSync(store);
      return;
    }
    await _powerSyncService?.stop();
    final service = widget.syncService ??
        SyncService.instance ??
        SyncService(settings: widget.settingsController);
    SyncService.instance = service;
    _syncService = service;
    service.resolveMergeConflict = (conflict) async {
      if (!mounted) {
        return SyncMergeSide.local;
      }
      return showSyncMergeConflictDialog(context, conflict);
    };
    if (widget.settingsController.householdId == null) {
      await service.stop();
      await _disposeIncomingCallController();
      await _stopKeepAlive();
      return;
    }
    await service.ensureStartedForPet(store: store);
    await _syncIncomingCallController(service, store);
    await _syncKeepAlive();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _restartPowerSync(PetNoteStore store) async {
    final legacyService = _syncService;
    _syncService = null;
    await legacyService?.stop();
    await _disposeIncomingCallController();
    final service = widget.powerSyncService ??
        _powerSyncService ??
        PowerSyncSpikeService(settings: widget.settingsController);
    _powerSyncService = service;
    if (widget.settingsController.householdId == null) {
      await service.stop();
      await _stopKeepAlive();
      return;
    }
    await service.ensureStarted(store: store);
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
    final powerSyncService = _powerSyncService;
    final listenables = <Listenable>[
      widget.settingsController,
      store,
      if (powerSyncService != null) ...[
        powerSyncService.connectionStatus,
        powerSyncService.failedSyncCount,
        powerSyncService.lastError,
      ],
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
        final effectiveServedPetId = controller?.servedPetIdOverride.value ??
            widget.settingsController.servedPetId;
        final servedPetName = store.petById(effectiveServedPetId ?? '')?.name;
        return PetDeviceDashboard(
          store: store,
          servedPetId: effectiveServedPetId,
          syncStatusLabel: powerSyncService == null
              ? _syncStatusLabel(_syncService)
              : _powerSyncStatusLabel(powerSyncService),
          pendingItemKeys:
              controller?.pendingItemKeys.value ?? const <String>{},
          onSelectServedPet: widget.settingsController.setServedPetId,
          onMarkDone: (action) async {
            if (controller != null) {
              await controller.sendAction(action);
              return;
            }
            await store.applyLocalSyncedPetAction(action);
          },
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => PetDeviceSettingsPage(
                settingsController: widget.settingsController,
                servedPetName: servedPetName,
                keepScreenOn: widget.settingsController.petKeepScreenOn,
                onKeepScreenOnChanged: (value) async {
                  await widget.settingsController.setPetKeepScreenOn(value);
                  await _syncKeepAlive();
                },
                onReturnToPetSelection: () async {
                  controller?.servedPetIdOverride.value = null;
                  await widget.settingsController.setServedPetId(null);
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
    final controller = service?.petController;

    // 首次同步判断：连接成功但还没有收到过数据
    if (transport?.state.value == SyncConnectionState.connected &&
        controller?.lastSyncedAt.value == null) {
      return '同步中...';
    }

    return switch (transport?.state.value) {
      SyncConnectionState.connected => '已连接',
      SyncConnectionState.connecting => '连接中',
      _ => '重连中',
    };
  }

  String _powerSyncStatusLabel(PowerSyncSpikeService service) {
    if (service.failedSyncCount.value > 0) {
      return '同步异常';
    }
    final status = service.connectionStatus.value;
    if (status.connected) {
      return 'PowerSync 已连接';
    }
    if (status.connecting || service.isActive) {
      return 'PowerSync 连接中';
    }
    return '同步中...';
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

  Future<void> _syncIncomingCallController(
    SyncService service,
    PetNoteStore store,
  ) async {
    final transport = service.debugTransport;
    if (transport == null) {
      await _disposeIncomingCallController();
      return;
    }
    final localDeviceId = await widget.settingsController.ensureDeviceId();
    if (_rtcSignalingController != null &&
        _incomingCallController != null &&
        identical(_incomingCallTransport, transport) &&
        _incomingCallDeviceId == localDeviceId) {
      return;
    }
    await _disposeIncomingCallController();
    final signaling = RtcSignalingController(transport: transport);
    _rtcSignalingController = signaling;
    _incomingCallTransport = transport;
    _incomingCallDeviceId = localDeviceId;
    _incomingCallController = RtcIncomingCallController(
      signalingController: signaling,
      localDeviceId: localDeviceId,
      onStartCall: (invite) => unawaited(_openIncomingCall(invite, store)),
    );
  }

  Future<void> _openIncomingCall(
      RtcCallInvite invite, PetNoteStore store) async {
    if (!mounted) {
      return;
    }
    final pet = store.petById(widget.settingsController.servedPetId ?? '') ??
        store.selectedPet ??
        (store.pets.isEmpty ? null : store.pets.first);
    if (pet == null) {
      return;
    }
    final canStart = await ensureRtcMediaPermissionBeforeRemoteVideo(
      context: context,
      permissionCoordinator: widget.remoteVideoPermissionCoordinator,
    );
    if (!canStart || !mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RemoteVideoCallPage(
          mode: invite.mode == RtcCallMode.watch
              ? RemoteVideoMode.watch
              : RemoteVideoMode.call,
          pet: pet,
          callId: invite.callId,
          targetDeviceId: invite.callerDeviceId,
          signalingController: _rtcSignalingController,
          sendInviteOnJoin: false,
        ),
      ),
    );
  }

  Future<void> _disposeIncomingCallController() async {
    await _incomingCallController?.dispose();
    _incomingCallController = null;
    await _rtcSignalingController?.dispose();
    _rtcSignalingController = null;
    _incomingCallTransport = null;
    _incomingCallDeviceId = null;
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
