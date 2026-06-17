import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/multi_device_sync_controller.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() async {
  final crypto = await SyncCrypto.deriveFromPairingCode(
    code: '123456',
    saltBase64: SyncCrypto.generateSaltBase64(),
  );

  test('主人端和宠物端同步入口共用同一套多设备控制器底座', () {
    final owner = OwnerSyncEngine(
      store: PetNoteStore.seeded(),
      transport: FakeSyncTransport(),
      crypto: crypto,
    );
    final pet = PetReplicaController(
      store: PetNoteStore.seeded(),
      transport: FakeSyncTransport(),
      crypto: crypto,
    );

    expect(owner, isA<MultiDeviceSyncController>());
    expect(pet, isA<MultiDeviceSyncController>());

    owner.dispose();
    pet.dispose();
  });
}

class FakeSyncTransport implements SyncTransport {
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  ValueListenable<SyncConnectionState> get state => _state;
  final ValueNotifier<SyncConnectionState> _state =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connected);

  @override
  Future<void> connect() async {
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) {}
}
