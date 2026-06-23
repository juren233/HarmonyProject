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
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';

class PetDeviceHome extends StatefulWidget {
  const PetDeviceHome({
    super.key,
    required this.settingsController,
    this.storeLoader,
    this.syncService,
    this.keepAlive,
    this.remoteVideoPermissionCoordinator,
  });

  final AppSettingsController settingsController;
  final Future<PetNoteStore> Function()? storeLoader;
  final SyncService? syncService;
  final DeviceKeepAlive? keepAlive;
  final RtcMediaPermissionCoordinator? remoteVideoPermissionCoordinator;

  @override
  State<PetDeviceHome> createState() => _PetDeviceHomeState();
}

class _PetDeviceHomeState extends State<PetDeviceHome>
    with WidgetsBindingObserver {
  PetNoteStore? _store;
  SyncService? _syncService;
  late final DeviceKeepAlive _keepAlive;
  RtcSignalingController? _rtcSignalingController;
  RtcIncomingCallController? _incomingCallController;
  SyncTransport? _incomingCallTransport;
  String? _incomingCallDeviceId;
  bool _keepAliveStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    widget.settingsController.removeListener(_handleSettingsChanged);
    unawaited(_disposeIncomingCallController());
    _store?.dispose();
    unawaited(_stopKeepAlive());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restartSync());
    }
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
    final service = await _syncServiceForCurrentSettings();
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
    await service.ensureStarted(store: store);
    await _syncIncomingCallController(service, store);
    await _syncKeepAlive();
    if (mounted) {
      setState(() {});
    }
  }

  Future<SyncService> _syncServiceForCurrentSettings() async {
    final injected = widget.syncService;
    if (injected != null) {
      return injected;
    }
    final existing = SyncService.instance;
    if (existing != null &&
        !identical(existing.settings, widget.settingsController)) {
      if (identical(SyncService.instance, existing)) {
        SyncService.instance = null;
      }
      await existing.stop();
      existing.dispose();
    }
    return SyncService.instance ??=
        SyncService(settings: widget.settingsController);
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

    final controller = _syncService?.syncController;
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
        final effectiveServedPetId = controller?.servedPetIdOverride.value ??
            widget.settingsController.servedPetId;
        final servedPetName = store.petById(effectiveServedPetId ?? '')?.name;
        return PetDeviceDashboard(
          store: store,
          servedPetId: effectiveServedPetId,
          syncStatusLabel: _syncStatusLabel(_syncService),
          pendingItemKeys:
              controller?.pendingItemKeys.value ?? const <String>{},
          onSelectServedPet: widget.settingsController.setServedPetId,
          onMarkDone: (action) => controller?.sendAction(action),
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
    final controller = service?.syncController;
    final sessionState = service?.sessionState;

    if (sessionState == SyncSessionState.handshaking) {
      return '同步中...';
    }
    if (sessionState == SyncSessionState.blocked) {
      return '同步异常';
    }

    // 首次同步判断：连接成功但还没有收到过数据
    if (sessionState == SyncSessionState.authenticated &&
        transport?.state.value == SyncConnectionState.connected &&
        controller?.lastSyncedAt.value == null) {
      return '同步中...';
    }

    return switch (sessionState) {
      SyncSessionState.authenticated => '已连接',
      SyncSessionState.connecting => '连接中',
      SyncSessionState.backingOff => '重连中',
      _ => switch (transport?.state.value) {
          SyncConnectionState.connected => '同步中...',
      SyncConnectionState.connecting => '连接中',
          _ => '重连中',
        },
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
