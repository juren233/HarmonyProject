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
        _transportFactory = transportFactory ?? ((url) => SyncClient(url: url));

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
  bool _initialConnectionCompleted = false;

  bool get isActive => _transport != null;
  SyncTransport? get debugTransport => _transport;
  ValueListenable<int>? get failedSyncCount =>
      ownerEngine?.failedSyncCount ?? petController?.failedSyncCount;

  Future<void> ensureStarted({required PetNoteStore store}) async {
    switch (settings.deviceRole) {
      case DeviceRole.owner:
        await ensureStartedForOwner(store: store);
      case DeviceRole.pet:
        await ensureStartedForPet(store: store);
      case DeviceRole.undecided:
        return;
    }
  }

  Future<void> ensureStartedForOwner({required PetNoteStore? store}) async {
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
    ownerEngine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
    )..start(pushInitialSnapshot: false);
    _activeRole = DeviceRole.owner;
    notifyListeners();

    final policy = pendingPolicy ?? SyncDataPolicy.merge;
    await settings.setPendingInitialSyncPolicy(null);

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
      ownerEngine?.requestSnapshot();
    }
    _initialConnectionCompleted = true;
  }

  Future<void> ensureStartedForPet({required PetNoteStore store}) async {
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
    petController = PetReplicaController(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
    )..start(requestInitialSnapshot: false);
    _activeRole = DeviceRole.pet;
    notifyListeners();

    final policy = pendingPolicy ?? SyncDataPolicy.merge;
    await settings.setPendingInitialSyncPolicy(null);

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
      petController?.requestSnapshot(dataPolicy: SyncDataPolicy.merge);
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
    ownerEngine?.dispose();
    petController?.dispose();
    ownerEngine = null;
    petController = null;
    await _transport?.disconnect();
    _transport = null;
    _activeRole = null;
    _initialConnectionCompleted = false;
    if (shouldNotify) {
      notifyListeners();
    }
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
