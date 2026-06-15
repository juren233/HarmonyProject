import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('收到快照解密后写入本地 store', () async {
    final sourceStore = PetNoteStore.seeded();
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start();

    final state = PetNoteDataState(
      pets: sourceStore.pets,
      todos: sourceStore.todos,
      reminders: sourceStore.reminders,
      records: sourceStore.records,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 1,
        'syncId': 'snapshot-sync-1',
        'originDeviceId': 'owner-1',
        'ciphertext': await crypto.encryptString(jsonEncode(state.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.pets.length, sourceStore.pets.length);
    expect(controller.lastSyncedVersion.value, 1);
    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          message.payload['syncId'] == 'snapshot-sync-1'),
      isTrue,
    );

    controller.dispose();
  });

  test('收到主人端标记完成后的快照会同步完成状态', () async {
    final ownerStore = PetNoteStore.seeded();
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);
    final todo =
        ownerStore.todos.firstWhere((item) => item.status == TodoStatus.open);

    await ownerStore.markChecklistDone('todo', todo.id);
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'ciphertext': await crypto
            .encryptString(jsonEncode(ownerStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.todoById(todo.id)?.status, TodoStatus.done);

    controller.dispose();
  });

  test('合并快照遇到同 id 差异时调用冲突选择', () async {
    final ownerStore = PetNoteStore.seeded();
    final replicaStore = PetNoteStore.seeded();
    final todo = replicaStore.todoById('todo-1')!;
    await ownerStore.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '主人端待办标题',
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: todo.note,
    );
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    SyncMergeConflict? conflict;
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
      resolveMergeConflict: (value) async {
        conflict = value;
        return SyncMergeSide.remote;
      },
    )..start(requestInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto
            .encryptString(jsonEncode(ownerStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(conflict?.collectionLabel, '待办');
    expect(conflict?.id, todo.id);
    expect(replicaStore.todoById(todo.id)?.title, '主人端待办标题');

    controller.dispose();
  });

  test('sendAction 加密上行并标记 pending', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start();

    await controller.sendAction(
      const PetAction(
        kind: PetActionKind.markDone,
        sourceType: 'todo',
        itemId: 'todo-1',
      ),
    );

    final actionMessages = transport.sent
        .where((message) => message.type == SyncMessageTypes.actionPush)
        .toList();
    expect(actionMessages, hasLength(1));
    expect(actionMessages.single.payload['kind'], PetActionKind.markDone.name);
    expect(actionMessages.single.payload['sourceType'], 'todo');
    expect(actionMessages.single.payload['itemId'], 'todo-1');
    expect(replicaStore.todoById('todo-1')?.status, TodoStatus.done);
    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));

    controller.dispose();
  });

  test('本地先应用完成延后跳过后收到同状态快照不触发冲突', () async {
    const scenarios = <PetActionKind, TodoStatus>{
      PetActionKind.markDone: TodoStatus.done,
      PetActionKind.postpone: TodoStatus.postponed,
      PetActionKind.skip: TodoStatus.skipped,
    };

    for (final scenario in scenarios.entries) {
      final ownerStore = PetNoteStore.seeded();
      final replicaStore = PetNoteStore.seeded();
      final transport = FakeSyncTransport();
      final crypto = await SyncCrypto.deriveFromPairingCode(
        code: '123456',
        saltBase64: SyncCrypto.generateSaltBase64(),
      );
      var conflictCount = 0;
      final controller = PetReplicaController(
        store: replicaStore,
        transport: transport,
        crypto: crypto,
        resolveMergeConflict: (value) async {
          conflictCount += 1;
          return SyncMergeSide.remote;
        },
      )..start(requestInitialSnapshot: false);
      final action = PetAction(
        kind: scenario.key,
        sourceType: 'todo',
        itemId: 'todo-1',
      );

      await controller.sendAction(action);
      await ownerStore.applyPetAction(action);
      transport.incoming.add(
        SyncMessage(SyncMessageTypes.snapshot, {
          'version': 2,
          'ciphertext': await crypto
              .encryptString(jsonEncode(ownerStore.exportDataState().toJson())),
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await controller.sendAction(action);

      final actionMessages = transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush)
          .toList();
      expect(replicaStore.todoById('todo-1')?.status, scenario.value);
      expect(conflictCount, 0);
      expect(controller.pendingItemKeys.value, isNot(contains('todo:todo-1')));
      expect(actionMessages, hasLength(1));

      controller.dispose();
    }
  });

  test('收到 action 已送达回执后释放 pending', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);

    await controller.sendAction(
      const PetAction(
        kind: PetActionKind.markDone,
        sourceType: 'todo',
        itemId: 'todo-1',
      ),
    );
    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.syncReceived, {
        'syncId': 'sync-action-1',
        'actionId': 'action-1',
        'kind': 'markDone',
        'sourceType': 'todo',
        'itemId': 'todo-1',
        'receivedDeviceId': 'owner-1',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.pendingItemKeys.value, isNot(contains('todo:todo-1')));

    controller.dispose();
  });

  test('推送快照时携带已完成事项摘要', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);
    final todo =
        replicaStore.todos.firstWhere((item) => item.status == TodoStatus.open);

    await replicaStore.markChecklistDone('todo', todo.id);
    await controller.pushSnapshotNow();

    final push = transport.sent
        .lastWhere((message) => message.type == SyncMessageTypes.snapshotPush);
    expect(push.payload['completedItemKeys'], contains('todo:${todo.id}'));

    controller.dispose();
  });

  test('主动请求远端覆盖快照时携带 remoteWins 策略', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);

    controller.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    controller.dispose();
  });

  test('收到远端覆盖快照请求时用 remoteWins 回传快照', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': 'remoteWins',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final push = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    controller.dispose();
  });

  test('收到其他设备 action 后更新本地 store', () async {
    final replicaStore = PetNoteStore.seeded();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);
    final todo =
        replicaStore.todos.firstWhere((item) => item.status == TodoStatus.open);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'action-1',
        'ciphertext': await crypto.encryptString(jsonEncode(
          PetAction(
            kind: PetActionKind.markDone,
            sourceType: 'todo',
            itemId: todo.id,
          ).toJson(),
        )),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.todoById(todo.id)?.status, TodoStatus.done);
    expect(
        controller.pendingItemKeys.value, isNot(contains('todo:${todo.id}')));

    controller.dispose();
  });

  test('device_config 更新 servedPetId，removed 时清除配对', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setServedPetId('pet-1');
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
      settings: settings,
    )..start();

    transport.incoming.add(
      const SyncMessage(
          SyncMessageTypes.deviceConfig, {'servedPetId': 'pet-2'}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(settings.servedPetId, 'pet-2');

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.removedByOwner.value, isTrue);
    expect(settings.householdId, isNull);

    controller.dispose();
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
  void send(SyncMessage message) => sent.add(message);
}
