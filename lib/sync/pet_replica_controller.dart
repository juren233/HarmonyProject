import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_failure_queue.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PetReplicaController {
  PetReplicaController({
    required this.store,
    required this.transport,
    required this.crypto,
    this.resolveMergeConflict,
    this.settings,
  });

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final SyncMergeConflictResolver? resolveMergeConflict;
  final AppSettingsController? settings;

  final ValueNotifier<int> lastSyncedVersion = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<Set<String>> pendingItemKeys =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<String?> servedPetIdOverride =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> removedByOwner = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);
  final ValueNotifier<int> failedSyncCount = ValueNotifier<int>(0);

  final Random _random = Random.secure();
  late final SyncFailureQueue _failureQueue = SyncFailureQueue(
    transport: transport,
    failedCount: failedSyncCount,
    lastError: lastError,
  );
  final Set<String> _pendingActionKeys = <String>{};
  StreamSubscription<SyncMessage>? _subscription;
  var _started = false;

  void start({bool requestInitialSnapshot = true}) {
    if (_started) {
      return;
    }
    _started = true;
    _subscription = transport.messages.listen((message) {
      unawaited(_onMessage(message));
    }, onError: (Object error) {
      lastError.value = error;
    });
    if (requestInitialSnapshot) {
      requestSnapshot();
    }
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

  Future<void> pushSnapshotNow({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) async {
    try {
      retryFailedSync();
      final json = jsonEncode(store.exportDataState().toJson());
      _failureQueue.sendOrQueue(
        SyncMessage(SyncMessageTypes.snapshotPush, {
          'version': DateTime.now().toUtc().microsecondsSinceEpoch,
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
      case SyncMessageTypes.snapshot:
        await _applySnapshot(message);
      case SyncMessageTypes.snapshotRequest:
        await pushSnapshotNow(
          dataPolicy: _snapshotRequestDataPolicy(message),
        );
      case SyncMessageTypes.action:
        await _applyAction(message);
      case SyncMessageTypes.deviceConfig:
        await _applyDeviceConfig(message);
      case SyncMessageTypes.syncReceived:
        break;
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
      _sendReceivedIfNeeded(message);
      lastSyncedVersion.value =
          (message.payload['version'] as num?)?.toInt() ?? 0;
      lastSyncedAt.value = DateTime.now();
      _pendingActionKeys.clear();
      pendingItemKeys.value = const <String>{};
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<void> _applyDeviceConfig(SyncMessage message) async {
    if (message.payload['removed'] == true) {
      removedByOwner.value = true;
      await settings?.clearSyncPairing();
      return;
    }
    if (message.payload.containsKey('servedPetId')) {
      final servedPetId = message.payload['servedPetId'] as String?;
      servedPetIdOverride.value = servedPetId;
      await settings?.setServedPetId(servedPetId);
    }
  }

  Future<void> sendAction(PetAction action) async {
    if (_pendingActionKeys.contains(action.dedupeKey) ||
        store.isPetActionApplied(action)) {
      return;
    }
    final actionId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';
    final outgoing = PetAction(
      kind: action.kind,
      sourceType: action.sourceType,
      itemId: action.itemId,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.actionPush, {
        'actionId': actionId,
        'ciphertext': await crypto.encryptString(jsonEncode(outgoing.toJson())),
        'kind': outgoing.kind.name,
        'sourceType': outgoing.sourceType,
        'itemId': outgoing.itemId,
      }),
    );
    _pendingActionKeys.add(outgoing.dedupeKey);
    pendingItemKeys.value = <String>{
      ...pendingItemKeys.value,
      '${outgoing.sourceType}:${outgoing.itemId}',
    };
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
      _pendingActionKeys.remove(action.dedupeKey);
      pendingItemKeys.value = {
        for (final key in pendingItemKeys.value)
          if (key != '${action.sourceType}:${action.itemId}') key,
      };
    } on Object catch (error) {
      lastError.value = error;
    }
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
    _subscription?.cancel();
    _failureQueue.dispose();
    _pendingActionKeys.clear();
    lastSyncedVersion.dispose();
    lastSyncedAt.dispose();
    pendingItemKeys.dispose();
    servedPetIdOverride.dispose();
    removedByOwner.dispose();
    lastError.dispose();
    failedSyncCount.dispose();
  }
}
