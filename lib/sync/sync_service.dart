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
    if (_activeRole == DeviceRole.pet) {
      await stop();
    }
    if (isActive) {
      return;
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
    )..start(pushInitialSnapshot: false);
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
    final policy = settings.pendingInitialSyncPolicy ?? SyncDataPolicy.merge;
    await settings.setPendingInitialSyncPolicy(null);
    if (policy == SyncDataPolicy.remoteWins) {
      ownerEngine?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else {
      await ownerEngine?.pushSnapshotNow(
        dataPolicy: policy == SyncDataPolicy.localWins
            ? SyncDataPolicy.remoteWins
            : SyncDataPolicy.merge,
      );
      if (policy == SyncDataPolicy.merge) {
        ownerEngine?.requestSnapshot();
      }
    }
  }

  Future<void> ensureStartedForPet({required PetNoteStore store}) async {
    if (_activeRole == DeviceRole.owner) {
      await stop();
    }
    if (isActive) {
      return;
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
    final policy = settings.pendingInitialSyncPolicy ?? SyncDataPolicy.merge;
    await settings.setPendingInitialSyncPolicy(null);
    if (policy == SyncDataPolicy.localWins) {
      await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins);
    } else {
      petController?.requestSnapshot(
        dataPolicy: policy == SyncDataPolicy.remoteWins
            ? SyncDataPolicy.remoteWins
            : SyncDataPolicy.merge,
      );
      if (policy == SyncDataPolicy.merge) {
        await petController?.pushSnapshotNow(dataPolicy: SyncDataPolicy.merge);
      }
    }
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
      switch (role) {
        case DeviceRole.owner:
          ownerEngine?.requestSnapshot();
        case DeviceRole.pet:
          petController?.requestSnapshot();
        case DeviceRole.undecided:
          break;
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
