import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

typedef SyncTransportFactory = SyncTransport Function(String url);

class SyncService extends ChangeNotifier {
  SyncService({
    required this.settings,
    SyncSecretStore? secretStore,
    OfficialSyncServerResolver? officialServerResolver,
    SyncTransportFactory? transportFactory,
    this.resolveMergeConflict,
  })  : _secretStore = secretStore ?? MethodChannelSyncSecretStore(),
        _officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver(),
        _transportFactory =
            transportFactory ?? ((url) => SyncClient(url: url)) {
    settings.addListener(_refreshFailedSyncCount);
    _refreshFailedSyncCount();
  }

  static SyncService? instance;

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;
  final OfficialSyncServerResolver _officialServerResolver;
  final SyncTransportFactory _transportFactory;
  SyncMergeConflictResolver? resolveMergeConflict;

  SyncTransport? _transport;
  OwnerSyncEngine? ownerEngine;
  PetReplicaController? petController;
  DeviceRole? _activeRole;
  void Function()? _transportStateListener;
  VoidCallback? _engineFailedCountListener;
  ValueListenable<int>? _engineFailedCount;
  final ValueNotifier<int> _failedSyncCount = ValueNotifier<int>(0);
  bool _initialConnectionCompleted = false;

  bool get isActive => _transport != null;
  SyncTransport? get debugTransport => _transport;
  ValueListenable<int>? get failedSyncCount => _failedSyncCount;

  Future<void> pushLocalSnapshotToAllDevices({
    required PetNoteStore store,
    SyncDataPolicy dataPolicy = SyncDataPolicy.remoteWins,
  }) async {
    await ensureStarted(store: store, pushStartupSnapshot: false);
    switch (_activeRole) {
      case DeviceRole.owner:
        final syncId = dataPolicy == SyncDataPolicy.remoteWins
            ? await _ensurePendingResetSnapshotSyncId()
            : null;
        await ownerEngine?.pushSnapshotNow(
          dataPolicy: dataPolicy,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.pet:
        final syncId = dataPolicy == SyncDataPolicy.remoteWins
            ? await _ensurePendingResetSnapshotSyncId()
            : null;
        await petController?.pushSnapshotNow(
          dataPolicy: dataPolicy,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.undecided:
      case null:
        break;
    }
    _refreshFailedSyncCount();
  }

  Future<void> ensureStarted({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    switch (settings.deviceRole) {
      case DeviceRole.owner:
        await ensureStartedForOwner(
          store: store,
          pushStartupSnapshot: pushStartupSnapshot,
        );
      case DeviceRole.pet:
        await ensureStartedForPet(
          store: store,
          pushStartupSnapshot: pushStartupSnapshot,
        );
      case DeviceRole.undecided:
        return;
    }
  }

  Future<void> ensureStartedForOwner({
    required PetNoteStore? store,
    bool pushStartupSnapshot = true,
  }) async {
    if (store == null) {
      return;
    }
    final pendingPolicy = settings.pendingInitialSyncPolicy;
    if (_activeRole == DeviceRole.pet) {
      await stop();
    }
    if (isActive) {
      if (pendingPolicy == null) {
        return;
      }
      await stop();
    }
    final config = await _loadConfig();
    if (config == null) {
      return;
    }
    final transport = _transportFactory(config.url);
    _transport = transport;
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
      onRemoved: _stopAfterRemoval,
    );
    ownerEngine = engine;
    await engine.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    _attachEngineFailedCount(ownerEngine?.failedSyncCount);
    _activeRole = DeviceRole.owner;
    notifyListeners();

    await transport.connect();
    _sendHello(
      transport: transport,
      config: config,
      role: DeviceRole.owner,
    );
    _attachHelloOnConnect(
      transport: transport,
      config: config,
      role: DeviceRole.owner,
    );

    if (pendingPolicy == null) {
      if (!pushStartupSnapshot) {
        await _pushPendingResetSnapshotIfAny(DeviceRole.owner);
        _initialConnectionCompleted = true;
        return;
      }
      await _pushPendingResetSnapshotIfAny(DeviceRole.owner);
      await ownerEngine?.pushSnapshotNow(dataPolicy: SyncDataPolicy.merge);
      ownerEngine?.requestSnapshot();
      _initialConnectionCompleted = true;
      return;
    }

    final policy = pendingPolicy;
    await settings.setPendingInitialSyncPolicy(null);

    // 首次连接完成后，根据配对时选择的策略执行同步
    if (policy == SyncDataPolicy.remoteWins) {
      // 以对方为准：请求对方数据并覆盖本机
      ownerEngine?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else if (policy == SyncDataPolicy.localWins) {
      // 以本机为准：推送本机数据覆盖对方
      await ownerEngine?.pushSnapshotNow(
        dataPolicy: SyncDataPolicy.remoteWins,
      );
    } else {
      // 合并：双向传输，对方没有的数据会被添加
      await ownerEngine?.pushSnapshotNow(dataPolicy: SyncDataPolicy.merge);
      ownerEngine?.requestSnapshot(resolveConflicts: true);
    }
    _initialConnectionCompleted = true;
  }

  Future<void> ensureStartedForPet({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    final pendingPolicy = settings.pendingInitialSyncPolicy;
    if (_activeRole == DeviceRole.owner) {
      await stop();
    }
    if (isActive) {
      if (pendingPolicy == null) {
        return;
      }
      await stop();
    }
    final config = await _loadConfig();
    if (config == null) {
      return;
    }
    final transport = _transportFactory(config.url);
    _transport = transport;
    final controller = PetReplicaController(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
      onRemoved: _stopAfterRemoval,
    );
    petController = controller;
    await controller.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    _attachEngineFailedCount(petController?.failedSyncCount);
    _activeRole = DeviceRole.pet;
    notifyListeners();

    await transport.connect();
    _sendHello(
      transport: transport,
      config: config,
      role: DeviceRole.pet,
    );
    _attachHelloOnConnect(
      transport: transport,
      config: config,
      role: DeviceRole.pet,
    );

    if (pendingPolicy == null) {
      if (!pushStartupSnapshot) {
        await _pushPendingResetSnapshotIfAny(DeviceRole.pet);
        _initialConnectionCompleted = true;
        return;
      }
      await _pushPendingResetSnapshotIfAny(DeviceRole.pet);
      petController?.requestSnapshot();
      await petController?.pushSnapshotNow(dataPolicy: SyncDataPolicy.merge);
      _initialConnectionCompleted = true;
      return;
    }

    final policy = pendingPolicy;
    await settings.setPendingInitialSyncPolicy(null);

    // 首次连接完成后，根据配对时选择的策略执行同步
    if (policy == SyncDataPolicy.localWins) {
      // 以本机为准：推送本机数据覆盖对方
      await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins);
    } else if (policy == SyncDataPolicy.remoteWins) {
      // 以对方为准：请求对方数据并覆盖本机
      petController?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else {
      // 合并：双向传输，对方没有的数据会被添加
      petController?.requestSnapshot(
        dataPolicy: SyncDataPolicy.merge,
        resolveConflicts: true,
      );
      await petController?.pushSnapshotNow(dataPolicy: SyncDataPolicy.merge);
    }
    _initialConnectionCompleted = true;
  }

  Future<void> stop() async {
    final shouldNotify =
        ownerEngine != null || petController != null || _transport != null;
    final listener = _transportStateListener;
    if (listener != null) {
      _transport?.state.removeListener(listener);
      _transportStateListener = null;
    }
    _attachEngineFailedCount(null);
    ownerEngine?.dispose();
    petController?.dispose();
    ownerEngine = null;
    petController = null;
    await _transport?.disconnect();
    _transport = null;
    _activeRole = null;
    _initialConnectionCompleted = false;
    if (shouldNotify) {
      _refreshFailedSyncCount();
      notifyListeners();
    }
  }

  void _stopAfterRemoval() {
    scheduleMicrotask(() {
      unawaited(stop());
    });
  }

  Future<_SyncConfig?> _loadConfig() async {
    final url = await resolveConfiguredSyncServerUrl(
      settings: settings,
      officialResolver: _officialServerResolver,
    );
    final householdId = settings.householdId;
    final authToken = settings.householdAuthToken;
    final deviceId = await settings.ensureDeviceId();
    final sharedKeyBase64 =
        await _secretStore.loadSharedKey() ?? settings.sharedKeyBase64;
    if (url == null ||
        householdId == null ||
        authToken == null ||
        sharedKeyBase64 == null) {
      return null;
    }
    return _SyncConfig(
      url: url,
      householdId: householdId,
      authToken: authToken,
      deviceId: deviceId,
      sharedKeyBase64: sharedKeyBase64,
    );
  }

  Future<String> _ensurePendingResetSnapshotSyncId() async {
    final existing = settings.pendingResetSnapshotSyncId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final syncId =
        'reset-${DateTime.now().toUtc().microsecondsSinceEpoch}-${await settings.ensureDeviceId()}';
    await settings.setPendingResetSnapshotSyncId(syncId);
    _refreshFailedSyncCount();
    return syncId;
  }

  Future<void> _pushPendingResetSnapshotIfAny(DeviceRole role) async {
    final syncId = settings.pendingResetSnapshotSyncId;
    if (syncId == null || syncId.isEmpty) {
      return;
    }
    switch (role) {
      case DeviceRole.owner:
        await ownerEngine?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.pet:
        await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.undecided:
        break;
    }
    _refreshFailedSyncCount();
  }

  void _attachEngineFailedCount(ValueListenable<int>? failedCount) {
    final listener = _engineFailedCountListener;
    final current = _engineFailedCount;
    if (listener != null && current != null) {
      current.removeListener(listener);
    }
    _engineFailedCount = failedCount;
    if (failedCount == null) {
      _engineFailedCountListener = null;
      _refreshFailedSyncCount();
      return;
    }
    void nextListener() => _refreshFailedSyncCount();
    _engineFailedCountListener = nextListener;
    failedCount.addListener(nextListener);
    _refreshFailedSyncCount();
  }

  void _refreshFailedSyncCount() {
    final baseCount = ownerEngine?.failedSyncCount.value ??
        petController?.failedSyncCount.value ??
        0;
    final nextCount = baseCount > 0
        ? baseCount
        : settings.pendingResetSnapshotSyncId == null
            ? 0
            : 1;
    if (_failedSyncCount.value != nextCount) {
      _failedSyncCount.value = nextCount;
    }
  }

  void _attachHelloOnConnect({
    required SyncTransport transport,
    required _SyncConfig config,
    required DeviceRole role,
  }) {
    void listener() {
      if (transport.state.value != SyncConnectionState.connected) {
        return;
      }
      _sendHello(transport: transport, config: config, role: role);
      if (settings.pendingResetSnapshotSyncId != null) {
        unawaited(_pushPendingResetSnapshotIfAny(role));
      }

      // 只在重连时（非首次连接）主动请求快照
      if (_initialConnectionCompleted) {
        switch (role) {
          case DeviceRole.owner:
            ownerEngine?.retryFailedSync();
            ownerEngine?.requestSnapshot();
          case DeviceRole.pet:
            petController?.retryFailedSync();
            petController?.requestSnapshot();
          case DeviceRole.undecided:
            break;
        }
      }
    }

    transport.state.addListener(listener);
    _transportStateListener = listener;
  }

  void _sendHello({
    required SyncTransport transport,
    required _SyncConfig config,
    required DeviceRole role,
  }) {
    final isOwner = role == DeviceRole.owner;
    transport.send(
      SyncMessage(SyncMessageTypes.hello, {
        'householdId': config.householdId,
        'deviceId': config.deviceId,
        'role': isOwner ? 'owner' : 'pet',
        'authToken': config.authToken,
        'deviceName': settings.deviceName ?? (isOwner ? '主人设备' : '宠物端设备'),
        if (!isOwner) 'servedPetId': settings.servedPetId,
      }),
    );
  }

  @override
  void dispose() {
    settings.removeListener(_refreshFailedSyncCount);
    _attachEngineFailedCount(null);
    _failedSyncCount.dispose();
    super.dispose();
  }
}

class _SyncConfig {
  const _SyncConfig({
    required this.url,
    required this.householdId,
    required this.authToken,
    required this.deviceId,
    required this.sharedKeyBase64,
  });

  final String url;
  final String householdId;
  final String authToken;
  final String deviceId;
  final String sharedKeyBase64;
}
