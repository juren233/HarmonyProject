import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_failure_queue.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class OwnerSyncEngine {
  OwnerSyncEngine({
    required this.store,
    required this.transport,
    required this.crypto,
    this.resolveMergeConflict,
    this.throttle = const Duration(seconds: 2),
    int? initialVersion,
  }) : _version =
            initialVersion ?? DateTime.now().toUtc().microsecondsSinceEpoch;

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final SyncMergeConflictResolver? resolveMergeConflict;
  final Duration throttle;

  final ValueNotifier<List<SyncedDeviceInfo>> devices =
      ValueNotifier<List<SyncedDeviceInfo>>(const <SyncedDeviceInfo>[]);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);
  final ValueNotifier<int> failedSyncCount = ValueNotifier<int>(0);

  StreamSubscription<SyncMessage>? _subscription;
  Timer? _pushTimer;
  late final SyncFailureQueue _failureQueue = SyncFailureQueue(
    transport: transport,
    failedCount: failedSyncCount,
    lastError: lastError,
  );
  String? _lastPushedSnapshotKey;
  int _version;
  var _started = false;

  void start({bool pushInitialSnapshot = true}) {
    if (_started) {
      return;
    }
    _started = true;
    store.addListener(_onStoreChanged);
    _subscription = transport.messages.listen((message) {
      unawaited(_onMessage(message));
    }, onError: (Object error) {
      lastError.value = error;
    });
    if (pushInitialSnapshot) {
      unawaited(pushSnapshotNow());
    }
  }

  Future<void> pushSnapshotNow({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) async {
    _pushTimer?.cancel();
    _pushTimer = null;
    await _pushSnapshot(dataPolicy: dataPolicy);
  }

  void _onStoreChanged() {
    _pushTimer?.cancel();
    _pushTimer = Timer(throttle, () {
      unawaited(_pushSnapshot());
    });
  }

  Future<void> _pushSnapshot({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) async {
    try {
      retryFailedSync();
      final json = jsonEncode(store.exportDataState().toJson());
      final snapshotKey = '${dataPolicy.name}:$json';
      if (snapshotKey == _lastPushedSnapshotKey) {
        return;
      }
      _lastPushedSnapshotKey = snapshotKey;
      _version += 1;
      _failureQueue.sendOrQueue(
        SyncMessage(SyncMessageTypes.snapshotPush, {
          'version': _version,
          'ciphertext': await crypto.encryptString(json),
          'dataPolicy': dataPolicy.name,
          'completedItemKeys': store.completedItemKeys(),
        }),
      );
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<void> _onMessage(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageTypes.helloAck:
        _applyHelloAck(message);
      case SyncMessageTypes.action:
        await _applyAction(message);
      case SyncMessageTypes.snapshot:
        await _applySnapshot(message);
      case SyncMessageTypes.snapshotRequest:
        await pushSnapshotNow(
          dataPolicy: _snapshotRequestDataPolicy(message),
        );
      case SyncMessageTypes.devices:
        _applyDevices(message);
      case SyncMessageTypes.syncReceived:
        break;
    }
  }

  void _applyHelloAck(SyncMessage message) {
    final snapshotVersion = message.payload['snapshotVersion'];
    if (snapshotVersion is num && snapshotVersion.toInt() > _version) {
      _version = snapshotVersion.toInt();
    }
  }

  void _applyDevices(SyncMessage message) {
    final rawDevices = message.payload['devices'];
    if (rawDevices is! List) {
      lastError.value = const FormatException('invalid devices payload');
      return;
    }
    try {
      devices.value = rawDevices
          .whereType<Map>()
          .map((item) =>
              SyncedDeviceInfo.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<void> _applyAction(SyncMessage message) async {
    final actionId = message.payload['actionId'];
    try {
      if (actionId is! String || actionId.isEmpty) {
        throw const FormatException('missing action id');
      }
      final ciphertext = message.payload['ciphertext'];
      if (ciphertext is! String) {
        throw const FormatException('missing action ciphertext');
      }
      final decoded = jsonDecode(await crypto.decryptString(ciphertext));
      final action =
          PetAction.fromJson(Map<String, dynamic>.from(decoded as Map));
      await store.applyPetAction(action);
      _sendReceivedIfNeeded(message);
      _failureQueue.sendOrQueue(
        SyncMessage(SyncMessageTypes.actionAck, {'actionId': actionId}),
      );
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<void> _applySnapshot(SyncMessage message) async {
    try {
      final ciphertext = message.payload['ciphertext'];
      if (ciphertext is! String) {
        throw const FormatException('missing snapshot ciphertext');
      }
      final decoded = jsonDecode(await crypto.decryptString(ciphertext));
      final state =
          PetNoteDataState.fromJson(Map<String, dynamic>.from(decoded as Map));
      if (message.payload['dataPolicy'] == SyncDataPolicy.remoteWins.name) {
        await store.replaceAllData(state);
      } else {
        await store.mergeData(state, resolveConflict: resolveMergeConflict);
      }
      final version = (message.payload['version'] as num?)?.toInt();
      if (version != null && version > _version) {
        _version = version;
      }
      _sendReceivedIfNeeded(message);
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  void requestDevices() {
    retryFailedSync();
    _failureQueue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.devicesRequest, {}),
    );
  }

  void requestSnapshot({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) {
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': dataPolicy.name,
      }),
    );
  }

  void renameDevice(String deviceId, String name) {
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'name': name,
      }),
    );
  }

  void assignPet(String deviceId, String? petId) {
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'servedPetId': petId,
      }),
    );
  }

  void removeDevice(String deviceId) {
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceRemove, {'deviceId': deviceId}),
    );
  }

  void retryFailedSync() {
    _failureQueue.retry();
  }

  void _sendReceivedIfNeeded(SyncMessage message) {
    final syncId = message.payload['syncId'];
    if (syncId is! String || syncId.isEmpty) {
      return;
    }
    _failureQueue.sendOrQueue(SyncMessage(SyncMessageTypes.syncReceived, {
      'syncId': syncId,
      'originDeviceId': message.payload['originDeviceId'],
    }));
  }

  SyncDataPolicy _snapshotRequestDataPolicy(SyncMessage message) {
    final rawPolicy = message.payload['dataPolicy'];
    return SyncDataPolicy.values.firstWhere(
      (policy) => policy.name == rawPolicy,
      orElse: () => SyncDataPolicy.merge,
    );
  }

  void dispose() {
    _pushTimer?.cancel();
    _subscription?.cancel();
    store.removeListener(_onStoreChanged);
    _failureQueue.dispose();
    devices.dispose();
    lastError.dispose();
    failedSyncCount.dispose();
  }
}
