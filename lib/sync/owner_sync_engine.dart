import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class OwnerSyncEngine {
  OwnerSyncEngine({
    required this.store,
    required this.transport,
    required this.crypto,
    this.throttle = const Duration(seconds: 2),
    int? initialVersion,
  }) : _version =
            initialVersion ?? DateTime.now().toUtc().microsecondsSinceEpoch;

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final Duration throttle;

  final ValueNotifier<List<SyncedDeviceInfo>> devices =
      ValueNotifier<List<SyncedDeviceInfo>>(const <SyncedDeviceInfo>[]);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);

  StreamSubscription<SyncMessage>? _subscription;
  Timer? _pushTimer;
  String? _lastPushedJson;
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

  Future<void> pushSnapshotNow() async {
    _pushTimer?.cancel();
    _pushTimer = null;
    await _pushSnapshot();
  }

  void _onStoreChanged() {
    _pushTimer?.cancel();
    _pushTimer = Timer(throttle, () {
      unawaited(_pushSnapshot());
    });
  }

  Future<void> _pushSnapshot() async {
    try {
      final json = jsonEncode(store.exportDataState().toJson());
      if (json == _lastPushedJson) {
        return;
      }
      _lastPushedJson = json;
      _version += 1;
      transport.send(
        SyncMessage(SyncMessageTypes.snapshotPush, {
          'version': _version,
          'ciphertext': await crypto.encryptString(json),
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
      case SyncMessageTypes.devices:
        _applyDevices(message);
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
      switch (action.kind) {
        case PetActionKind.markDone:
          await store.markChecklistDone(action.sourceType, action.itemId);
        case PetActionKind.postpone:
          await store.postponeChecklist(action.sourceType, action.itemId);
        case PetActionKind.skip:
          await store.skipChecklist(action.sourceType, action.itemId);
      }
      transport.send(
        SyncMessage(SyncMessageTypes.actionAck, {'actionId': actionId}),
      );
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  void requestDevices() {
    transport.send(const SyncMessage(SyncMessageTypes.devicesRequest, {}));
  }

  void renameDevice(String deviceId, String name) {
    transport.send(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'name': name,
      }),
    );
  }

  void assignPet(String deviceId, String? petId) {
    transport.send(
      SyncMessage(SyncMessageTypes.deviceUpdate, {
        'deviceId': deviceId,
        'servedPetId': petId,
      }),
    );
  }

  void removeDevice(String deviceId) {
    transport.send(
      SyncMessage(SyncMessageTypes.deviceRemove, {'deviceId': deviceId}),
    );
  }

  void dispose() {
    _pushTimer?.cancel();
    _subscription?.cancel();
    store.removeListener(_onStoreChanged);
    devices.dispose();
    lastError.dispose();
  }
}
