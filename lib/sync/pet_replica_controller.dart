import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PetReplicaController {
  PetReplicaController({
    required this.store,
    required this.transport,
    required this.crypto,
    this.settings,
  });

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final AppSettingsController? settings;

  final ValueNotifier<int> lastSyncedVersion = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<Set<String>> pendingItemKeys =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<String?> servedPetIdOverride =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> removedByOwner = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);

  final Random _random = Random.secure();
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

  void requestSnapshot() {
    transport.send(const SyncMessage(SyncMessageTypes.snapshotRequest, {}));
  }

  Future<void> _onMessage(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageTypes.snapshot:
        await _applySnapshot(message);
      case SyncMessageTypes.deviceConfig:
        await _applyDeviceConfig(message);
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
      await store.replaceAllData(state);
      lastSyncedVersion.value =
          (message.payload['version'] as num?)?.toInt() ?? 0;
      lastSyncedAt.value = DateTime.now();
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
    final actionId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';
    transport.send(
      SyncMessage(SyncMessageTypes.actionPush, {
        'actionId': actionId,
        'ciphertext': await crypto.encryptString(jsonEncode(action.toJson())),
      }),
    );
    pendingItemKeys.value = <String>{
      ...pendingItemKeys.value,
      '${action.sourceType}:${action.itemId}',
    };
  }

  void dispose() {
    _subscription?.cancel();
    lastSyncedVersion.dispose();
    lastSyncedAt.dispose();
    pendingItemKeys.dispose();
    servedPetIdOverride.dispose();
    removedByOwner.dispose();
    lastError.dispose();
  }
}
