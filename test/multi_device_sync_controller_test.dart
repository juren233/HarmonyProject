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

  test('主人端和宠物端同步入口共用同一套多设备控制器底座', () async {
    final ownerTransport = FakeSyncTransport();
    final petTransport = FakeSyncTransport();
    final owner = OwnerSyncEngine(
      store: PetNoteStore.seeded(),
      transport: ownerTransport,
      crypto: crypto,
    );
    final pet = PetReplicaController(
      store: PetNoteStore.seeded(),
      transport: petTransport,
      crypto: crypto,
    );

    expect(owner, isA<MultiDeviceSyncController>());
    expect(pet, isA<MultiDeviceSyncController>());
    await owner.start();
    await pet.start();
    final ownerStartupMessages =
        ownerTransport.sent.map((message) => message.type).toList();
    final petStartupMessages =
        petTransport.sent.map((message) => message.type).toList();
    expect(ownerStartupMessages, petStartupMessages);
    expect(ownerStartupMessages, [
      SyncMessageTypes.snapshotRequest,
      SyncMessageTypes.snapshotPush,
    ]);

    owner.dispose();
    pet.dispose();
  });

  test('重复快照去重使用短指纹且数据变化后仍会重新发送', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final controller = MultiDeviceSyncController(
      store: store,
      transport: transport,
      crypto: crypto,
    );

    await controller.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    await controller.pushSnapshotNow();
    await controller.pushSnapshotNow();

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.snapshotPush),
      hasLength(1),
    );

    await store.addTodo(
      petId: store.pets.first.id,
      title: '短指纹快照变化',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    await controller.pushSnapshotNow();

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.snapshotPush),
      hasLength(2),
    );

    controller.dispose();
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
  final List<SyncMessage> sent = <SyncMessage>[];

  @override
  Future<void> connect() async {
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) {
    sent.add(message);
  }
}
