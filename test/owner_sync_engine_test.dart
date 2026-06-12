import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('启动后立即推送当前全量快照', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
    )..start();

    await Future<void>.delayed(const Duration(milliseconds: 100));

    final pushes = transport.sent
        .where((message) => message.type == SyncMessageTypes.snapshotPush)
        .toList();
    expect(pushes, hasLength(1));
    final decrypted = await crypto
        .decryptString(pushes.single.payload['ciphertext'] as String);
    expect(decrypted, contains(store.pets.first.name));

    engine.dispose();
  });

  test('store 变更后推送加密快照', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start();

    await store.addTodo(
      petId: store.pets.first.id,
      title: '喂饭',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final pushes = transport.sent
        .where((message) => message.type == SyncMessageTypes.snapshotPush)
        .toList();
    expect(pushes, isNotEmpty);
    final decrypted =
        await crypto.decryptString(pushes.last.payload['ciphertext'] as String);
    expect(decrypted, contains('喂饭'));

    engine.dispose();
  });

  test('hello_ack 的服务端版本会抬高下一次快照版本', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
      initialVersion: 0,
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.helloAck, {'snapshotVersion': 7}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await store.addTodo(
      petId: store.pets.first.id,
      title: '补水',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final push = transport.sent
        .lastWhere((message) => message.type == SyncMessageTypes.snapshotPush);
    expect(push.payload['version'], 8);

    engine.dispose();
  });

  test('收到 action 后调用 store 并回发 ack', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start();

    final todo =
        store.todos.firstWhere((item) => item.status == TodoStatus.open);
    final action = PetAction(
      kind: PetActionKind.markDone,
      sourceType: 'todo',
      itemId: todo.id,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'action-1',
        'ciphertext': await crypto.encryptString(jsonEncode(action.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(store.todoById(todo.id)?.status, TodoStatus.done);
    expect(
      transport.sent
          .any((message) => message.type == SyncMessageTypes.actionAck),
      isTrue,
    );

    engine.dispose();
  });

  test('action 解密失败时不回发 ack，避免清掉服务端 pending 队列', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.action, {
        'actionId': 'action-bad',
        'ciphertext': 'not-a-valid-ciphertext',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(engine.lastError.value, isNotNull);
    expect(
      transport.sent
          .any((message) => message.type == SyncMessageTypes.actionAck),
      isFalse,
    );

    engine.dispose();
  });

  test('设备列表和设备管理指令走 transport', () async {
    final store = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
    )..start();

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.devices, {
        'devices': [
          const SyncedDeviceInfo(
            deviceId: 'pet-device',
            name: '客厅平板',
            role: 'pet',
            servedPetId: 'pet-1',
            online: true,
          ).toJson(),
        ],
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.devices.value.single.deviceId, 'pet-device');

    engine.requestDevices();
    engine.renameDevice('pet-device', '卧室平板');
    engine.assignPet('pet-device', 'pet-2');
    engine.removeDevice('pet-device');

    expect(transport.sent.map((message) => message.type),
        contains(SyncMessageTypes.devicesRequest));
    expect(transport.sent.map((message) => message.type),
        contains(SyncMessageTypes.deviceUpdate));
    expect(transport.sent.map((message) => message.type),
        contains(SyncMessageTypes.deviceRemove));

    engine.dispose();
  });
}

class FakeSyncTransport implements SyncTransport {
  final List<SyncMessage> sent = <SyncMessage>[];
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
      ValueNotifier<SyncConnectionState>(SyncConnectionState.disconnected);

  @override
  Future<void> connect() async {
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) => sent.add(message);
}
