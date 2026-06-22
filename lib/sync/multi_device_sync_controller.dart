import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_failure_queue.dart';
import 'package:petnote/sync/sync_mutation_outbox.dart';
import 'package:petnote/sync/sync_photo_attachment.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class MultiDeviceSyncController {
  MultiDeviceSyncController({
    required this.store,
    required this.transport,
    required this.crypto,
    this.resolveMergeConflict,
    this.settings,
    this.onRemoved,
    this.throttle = const Duration(seconds: 2),
    SyncPhotoAttachmentCodec? photoAttachmentCodec,
    int? initialVersion,
    bool Function()? canSend,
  })  : _photoAttachmentCodec =
            photoAttachmentCodec ?? const SyncPhotoAttachmentCodec(),
        _version =
            initialVersion ?? DateTime.now().toUtc().microsecondsSinceEpoch,
        _canSend = canSend;

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final SyncMergeConflictResolver? resolveMergeConflict;
  final AppSettingsController? settings;
  final VoidCallback? onRemoved;
  final Duration throttle;
  final SyncPhotoAttachmentCodec _photoAttachmentCodec;
  final bool Function()? _canSend;

  final ValueNotifier<List<SyncedDeviceInfo>> devices =
      ValueNotifier<List<SyncedDeviceInfo>>(const <SyncedDeviceInfo>[]);
  final ValueNotifier<int> lastSyncedVersion = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<Set<String>> pendingItemKeys =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<String?> servedPetIdOverride =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> removedByOwner = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);
  final ValueNotifier<int> failedSyncCount = ValueNotifier<int>(0);

  late final SyncFailureQueue _failureQueue = SyncFailureQueue(
    transport: transport,
    failedCount: failedSyncCount,
    lastError: lastError,
    canSend: _canSend,
    loadOutbox: store.readSyncOutboxRows,
    saveOutbox: store.writeSyncOutboxRows,
    scopeKey: settings?.householdId,
  );
  late final SyncMutationOutbox _mutationOutbox = SyncMutationOutbox(
    store: store,
    crypto: crypto,
    failureQueue: _failureQueue,
    lastError: lastError,
    isStopped: () => _pairingRemoved,
    pendingItemKeys: pendingItemKeys,
    beforeSend: retryFailedSync,
  );

  StreamSubscription<SyncMessage>? _subscription;
  Timer? _pushTimer;
  String? _lastPushedSnapshotKey;
  int _version;
  int? _observedDataResetVersion;
  var _started = false;
  var _resolveNextMergeSnapshotConflict = false;
  var _pairingRemoved = false;

  int get pendingOutboxCount => _failureQueue.pendingCount;
  DateTime? get nextOutboxRetryAt => _failureQueue.nextRetryAt;
  Future<void> get debugOutboxPersisted => _failureQueue.persistIdle;
  Future<void> get outboxPersistIdle => _failureQueue.persistIdle;

  Future<void> start({
    bool pushInitialSnapshot = true,
    bool requestInitialSnapshot = true,
  }) async {
    if (_started) {
      return;
    }
    _started = true;
    _observedDataResetVersion = store.dataResetVersion;
    store.addListener(_handleStoreChanged);
    _failureQueue.restore();
    _mutationOutbox.start();
    _subscription = transport.messages.listen((message) {
      unawaited(_onMessage(message));
    }, onError: (Object error) {
      lastError.value = error;
    });
    await _mutationOutbox.flushPendingMutations();
    if (requestInitialSnapshot) {
      requestSnapshot();
    }
    if (pushInitialSnapshot) {
      await pushSnapshotNow();
    }
  }

  Future<void> pushSnapshotNow({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
    bool force = false,
    String? syncId,
    bool preserveConflictingIds = false,
  }) async {
    if (_pairingRemoved) {
      return;
    }
    _pushTimer?.cancel();
    _pushTimer = null;
    await _pushSnapshot(
      dataPolicy: dataPolicy,
      force: force,
      syncId: syncId,
      preserveConflictingIds: preserveConflictingIds,
    );
  }

  Future<void> _pushSnapshot({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
    bool force = false,
    String? syncId,
    bool preserveConflictingIds = false,
  }) async {
    try {
      if (_pairingRemoved) {
        return;
      }
      retryFailedSync();
      final state = store.exportDataState();
      final attachments = await _photoAttachmentCodec.collectFromState(state);
      final snapshotPayload = <String, Object?>{
        'data': state.toJson(),
        if (attachments.isNotEmpty)
          petPhotoAttachmentsPayloadKey:
              attachments.map((item) => item.toJson()).toList(),
      };
      final json = jsonEncode(snapshotPayload);
      final snapshotKey = '${dataPolicy.name}:$preserveConflictingIds:$json';
      if (!force && snapshotKey == _lastPushedSnapshotKey) {
        return;
      }
      _lastPushedSnapshotKey = snapshotKey;
      _version += 1;
      _failureQueue.sendOrQueue(
        SyncMessage(SyncMessageTypes.snapshotPush, {
          'version': _version,
          'ciphertext': await crypto.encryptString(json),
          'dataPolicy': dataPolicy.name,
          if (preserveConflictingIds) 'mergeMode': 'preserveConflictingIds',
          'completedItemKeys': store.completedItemKeys(),
          if (syncId != null && syncId.isNotEmpty) 'syncId': syncId,
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
      case SyncMessageTypes.mutation:
        await _applyMutation(message);
      case SyncMessageTypes.snapshot:
        await _applySnapshot(message);
      case SyncMessageTypes.snapshotRequest:
        await pushSnapshotNow(
          dataPolicy: _snapshotRequestDataPolicy(message),
          preserveConflictingIds: _shouldPreserveConflictingIds(message),
        );
      case SyncMessageTypes.devices:
        _applyDevices(message);
      case SyncMessageTypes.deviceConfig:
        await _applyDeviceConfig(message);
      case SyncMessageTypes.syncReceived:
        await _mutationOutbox.applySyncReceived(message);
        await _markResetSnapshotReceived(message);
      default:
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

  Future<void> _applyDeviceConfig(SyncMessage message) async {
    if (message.payload['removed'] == true) {
      _pairingRemoved = true;
      removedByOwner.value = true;
      await settings?.clearSyncPairing();
      _pushTimer?.cancel();
      _pushTimer = null;
      await _mutationOutbox.stop();
      await _subscription?.cancel();
      _subscription = null;
      _failureQueue.dispose();
      onRemoved?.call();
      return;
    }
    if (message.payload.containsKey('servedPetId')) {
      final servedPetId = message.payload['servedPetId'] as String?;
      servedPetIdOverride.value = servedPetId;
      await settings?.setServedPetId(servedPetId);
    }
  }

  Future<void> sendAction(PetAction action) async {
    if (_pairingRemoved) {
      return;
    }
    if (_mutationOutbox.hasPendingAction(action) ||
        store.isPetActionApplied(action)) {
      return;
    }
    final outgoing = PetAction(
      kind: action.kind,
      sourceType: action.sourceType,
      itemId: action.itemId,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await store.applyLocalSyncedPetAction(outgoing);
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
      final appliedAction = await store.applyRemotePetAction(
        action,
        sourceNamespace: _sourceNamespace(message),
        localNamespace: _localNamespace,
      );
      _sendReceivedIfNeeded(message);
      await _mutationOutbox.markRemoteActionApplied(appliedAction);
      lastSyncedAt.value = DateTime.now();
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<void> _applyMutation(SyncMessage message) async {
    try {
      final mutationId = message.payload['mutationId'];
      if (mutationId is! String || mutationId.isEmpty) {
        throw const FormatException('missing mutation id');
      }
      final ciphertext = message.payload['ciphertext'];
      if (ciphertext is! String) {
        throw const FormatException('missing mutation ciphertext');
      }
      final decoded = jsonDecode(await crypto.decryptString(ciphertext));
      final mutationPayload = Map<String, dynamic>.from(decoded as Map);
      final mutation = PetNoteMutation.fromJson(mutationPayload);
      final resolvedMutation = await _resolveMutationPhotoAttachment(
        mutation,
        mutationPayload[petPhotoAttachmentPayloadKey],
      );
      await store.applyMutation(
        resolvedMutation,
        sourceNamespace: _sourceNamespace(message),
        localNamespace: _localNamespace,
      );
      _sendReceivedIfNeeded(message);
      lastSyncedAt.value = DateTime.now();
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<PetNoteMutation> _resolveMutationPhotoAttachment(
    PetNoteMutation mutation,
    Object? rawAttachment,
  ) async {
    if (mutation.entityType != PetNoteEntityType.pet ||
        mutation.kind != PetNoteMutationKind.upsert ||
        mutation.data == null) {
      return mutation;
    }
    final attachment = syncPhotoAttachmentFromPayload(rawAttachment);
    if (attachment == null) {
      return mutation;
    }
    final state = PetNoteDataState(
      pets: [Pet.fromJson(mutation.data!)],
      todos: const <TodoItem>[],
      reminders: const <ReminderItem>[],
      records: const <PetRecord>[],
    );
    final resolvedState = await _photoAttachmentCodec.applyToState(
      state,
      [attachment],
    );
    if (resolvedState.pets.isEmpty) {
      return mutation;
    }
    return PetNoteMutation(
      id: mutation.id,
      entityType: mutation.entityType,
      entityId: mutation.entityId,
      kind: mutation.kind,
      data: resolvedState.pets.first.toJson(),
      actionKind: mutation.actionKind,
      occurredAtMs: mutation.occurredAtMs,
    );
  }

  Future<void> _applySnapshot(SyncMessage message) async {
    try {
      final ciphertext = message.payload['ciphertext'];
      if (ciphertext is! String) {
        throw const FormatException('missing snapshot ciphertext');
      }
      final decoded = jsonDecode(await crypto.decryptString(ciphertext));
      final snapshotPayload = Map<String, dynamic>.from(decoded as Map);
      final rawData = snapshotPayload['data'];
      final decodedState = PetNoteDataState.fromJson(
        rawData is Map ? Map<String, dynamic>.from(rawData) : snapshotPayload,
      );
      final state = await _photoAttachmentCodec.applyToState(
        decodedState,
        syncPhotoAttachmentsFromPayload(
          snapshotPayload[petPhotoAttachmentsPayloadKey],
        ),
      );
      final shouldResolveMergeConflict = _resolveNextMergeSnapshotConflict &&
          message.payload['dataPolicy'] != SyncDataPolicy.remoteWins.name;
      _resolveNextMergeSnapshotConflict = false;
      if (message.payload['dataPolicy'] == SyncDataPolicy.remoteWins.name) {
        await store.replaceAllDataFromRemote(state);
      } else if (_shouldPreserveConflictingIds(message) ||
          store.hasStableMergedEntitiesForSource(_sourceNamespace(message))) {
        await store.mergeDataPreservingConflictingIds(
          state,
          sourceNamespace: _sourceNamespace(message),
          localNamespace: _localNamespace,
        );
      } else {
        final resolver =
            shouldResolveMergeConflict ? resolveMergeConflict : null;
        await store.mergeData(state, resolveConflict: resolver);
      }
      final version = (message.payload['version'] as num?)?.toInt();
      if (version != null) {
        lastSyncedVersion.value = version;
        if (version > _version) {
          _version = version;
        }
      }
      _sendReceivedIfNeeded(message);
      lastSyncedAt.value = DateTime.now();
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  void requestDevices() {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    _failureQueue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.devicesRequest, {}),
    );
  }

  void requestSnapshot({
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
    bool resolveConflicts = false,
  }) {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    if (dataPolicy == SyncDataPolicy.merge && resolveConflicts) {
      _resolveNextMergeSnapshotConflict = true;
    }
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': dataPolicy.name,
        if (dataPolicy == SyncDataPolicy.merge && resolveConflicts)
          'mergeMode': 'preserveConflictingIds',
      }),
    );
  }

  void renameDevice(String deviceId, String name) {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'name': name,
      }),
    );
  }

  void assignPet(String deviceId, String? petId) {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'servedPetId': petId,
      }),
    );
  }

  void updateServedPetId(String? petId) {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'servedPetId': petId,
      }),
    );
  }

  void removeDevice(String deviceId) {
    if (_pairingRemoved) {
      return;
    }
    retryFailedSync();
    _failureQueue.sendOrQueue(
      SyncMessage(SyncMessageTypes.deviceRemove, {'deviceId': deviceId}),
    );
  }

  void retryFailedSync() {
    if (_pairingRemoved) {
      return;
    }
    _failureQueue.retry();
  }

  void clearFailedSyncQueue() {
    _failureQueue.clear();
  }

  void clearDurableOutbox() {
    _failureQueue.clear();
  }

  Future<void> _markResetSnapshotReceived(SyncMessage message) async {
    final pendingSyncId = settings?.pendingResetSnapshotSyncId;
    final syncId = message.payload['syncId'];
    if (pendingSyncId == null ||
        pendingSyncId.isEmpty ||
        syncId != pendingSyncId) {
      return;
    }
    await settings?.setPendingResetSnapshotSyncId(null);
  }

  void _handleStoreChanged() {
    final currentVersion = store.dataResetVersion;
    if (_observedDataResetVersion == currentVersion) {
      return;
    }
    _observedDataResetVersion = currentVersion;
    _lastPushedSnapshotKey = null;
    _mutationOutbox.clearRuntimeState();
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

  bool _shouldPreserveConflictingIds(SyncMessage message) {
    return message.payload['mergeMode'] == 'preserveConflictingIds';
  }

  String? _sourceNamespace(SyncMessage message) {
    final originDeviceId = message.payload['originDeviceId'];
    return originDeviceId is String && originDeviceId.isNotEmpty
        ? originDeviceId
        : null;
  }

  String? get _localNamespace {
    final deviceId = settings?.deviceId;
    return deviceId == null || deviceId.isEmpty ? null : deviceId;
  }

  void dispose() {
    store.removeListener(_handleStoreChanged);
    _pushTimer?.cancel();
    _subscription?.cancel();
    _mutationOutbox.dispose();
    _failureQueue.dispose();
    devices.dispose();
    lastSyncedVersion.dispose();
    lastSyncedAt.dispose();
    pendingItemKeys.dispose();
    servedPetIdOverride.dispose();
    removedByOwner.dispose();
    lastError.dispose();
    failedSyncCount.dispose();
  }
}
