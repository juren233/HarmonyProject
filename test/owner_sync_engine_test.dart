import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('store 变更后推送加密操作', () async {
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
        .where((message) => message.type == SyncMessageTypes.mutationPush)
        .toList();
    expect(pushes, hasLength(1));
    final decrypted = await crypto
        .decryptString(pushes.single.payload['ciphertext'] as String);
    final mutation =
        PetNoteMutation.fromJson(jsonDecode(decrypted) as Map<String, dynamic>);
    expect(mutation.kind, PetNoteMutationKind.upsert);
    expect(mutation.entityType, PetNoteEntityType.todo);
    expect(mutation.data?['title'], '喂饭');

    engine.dispose();
  });

  test('本地新增待办后推送操作而不是普通合并快照', () async {
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

    await store.addTodo(
      petId: store.pets.first.id,
      title: '补充饮水',
      dueAt: DateTime.parse('2026-03-29T12:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '观察饮水量',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final created = store.todos.firstWhere((item) => item.title == '补充饮水');

    final mutationPush = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.mutationPush,
    );
    final decoded = jsonDecode(
      await crypto.decryptString(mutationPush.payload['ciphertext'] as String),
    );
    final mutation =
        PetNoteMutation.fromJson(Map<String, dynamic>.from(decoded as Map));
    expect(mutation.entityType, PetNoteEntityType.todo);
    expect(mutation.kind, PetNoteMutationKind.upsert);
    expect(mutation.entityId, created.id);
    expect(mutation.data?['title'], '补充饮水');
    expect(
      transport.sent.any(
        (message) => message.type == SyncMessageTypes.snapshotPush,
      ),
      isFalse,
    );

    engine.dispose();
  });

  test('重启后仍推送未回执的本地修改操作', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.addPet(
      name: 'Luna',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '',
      allergies: '',
      note: '',
    );
    await seedStore.addTodo(
      title: '原始待办',
      petId: seedStore.pets.first.id,
      dueAt: DateTime.parse('2026-04-01T08:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final storeBeforeRestart = await PetNoteStore.load(storage: storage);
    final todo = storeBeforeRestart.todos.first;
    await storeBeforeRestart.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '离线修改后的标题',
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: todo.note,
    );
    final storeAfterRestart = await PetNoteStore.load(storage: storage);
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: storeAfterRestart,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final mutationPush = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.mutationPush,
    );
    final mutation = PetNoteMutation.fromJson(Map<String, dynamic>.from(
      jsonDecode(
        await crypto.decryptString(
          mutationPush.payload['ciphertext'] as String,
        ),
      ) as Map,
    ));
    expect(mutation.entityType, PetNoteEntityType.todo);
    expect(mutation.entityId, todo.id);
    expect(mutation.data?['title'], '离线修改后的标题');

    engine.dispose();
  });

  test('replaceAllData 会清理主人端 outbox 的失败队列和运行时状态', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final store = await PetNoteStore.load(storage: storage);
    final todo = store.todos.first;
    final transport = FakeSyncTransport()
      ..setState(SyncConnectionState.disconnected);
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

    await store.postponeChecklist('todo', todo.id);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(engine.failedSyncCount.value, 1);

    await store.replaceAllData(PetNoteStore.seeded().exportDataState());
    await transport.connect();
    engine.retryFailedSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.failedSyncCount.value, 0);
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      isEmpty,
    );
    expect(store.pendingLocalMutations, isEmpty);

    final restoredTodo =
        store.todos.firstWhere((item) => item.status == TodoStatus.open);
    await store.postponeChecklist('todo', restoredTodo.id);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(1),
    );

    engine.dispose();
  });

  test('普通合并快照不会清理主人端未回执 outbox 状态', () async {
    final sourceStore = PetNoteStore.seeded();
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

    await store.postponeChecklist('todo', 'todo-1');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(store.pendingLocalMutations, hasLength(1));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto.encryptString(
          jsonEncode(sourceStore.exportDataState().toJson()),
        ),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.pendingLocalMutations, hasLength(1));
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(1),
    );

    engine.dispose();
  });

  test('远端覆盖快照不会清理主人端未回执 outbox 状态', () async {
    final sourceStore = PetNoteStore.seeded();
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
    )..start(pushInitialSnapshot: false);
    final todo = store.todos.first;

    await store.updateTodo(
      todoId: todo.id,
      title: '离线修改后的标题',
      petId: todo.petId,
      dueAt: todo.dueAt,
      note: todo.note,
      notificationLeadTime: todo.notificationLeadTime,
    );
    expect(store.pendingLocalMutations, hasLength(1));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.remoteWins.name,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.pendingLocalMutations, hasLength(1));
    expect(store.todoById(todo.id)?.title, '离线修改后的标题');

    engine.dispose();
  });

  test('本地修改操作收到回执后重启不再重复推送', () async {
    final storage = PetNoteLocalStorage.memory();
    final store = await PetNoteStore.load(storage: storage);
    await store.addPet(
      name: 'Luna',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '',
      allergies: '',
      note: '',
    );
    await store.addTodo(
      title: '原始待办',
      petId: store.pets.first.id,
      dueAt: DateTime.parse('2026-04-01T08:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final todo = store.todos.first;
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

    await store.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '已确认同步的标题',
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: todo.note,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final mutationPushes = transport.sent
        .where((message) => message.type == SyncMessageTypes.mutationPush)
        .toList();
    for (var index = 0; index < mutationPushes.length; index += 1) {
      final mutationPush = mutationPushes[index];
      transport.incoming.add(SyncMessage(SyncMessageTypes.syncReceived, {
        'syncId': 'sync-mutation-$index',
        'originDeviceId': 'pet-1',
        'mutationId': mutationPush.payload['mutationId'],
      }));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    engine.dispose();

    final reloadedStore = await PetNoteStore.load(storage: storage);
    final nextTransport = FakeSyncTransport();
    final nextEngine = OwnerSyncEngine(
      store: reloadedStore,
      transport: nextTransport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      nextTransport.sent
          .where((message) => message.type == SyncMessageTypes.mutationPush),
      isEmpty,
    );

    nextEngine.dispose();
  });

  test('主人端标记完成后推送完成操作', () async {
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
    final todo =
        store.todos.firstWhere((item) => item.status == TodoStatus.open);

    await store.markChecklistDone('todo', todo.id);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final push = transport.sent
        .lastWhere((message) => message.type == SyncMessageTypes.actionPush);
    final decrypted =
        await crypto.decryptString(push.payload['ciphertext'] as String);
    final action =
        PetAction.fromJson(jsonDecode(decrypted) as Map<String, dynamic>);
    expect(action.kind, PetActionKind.markDone);
    expect(action.sourceType, 'todo');
    expect(action.itemId, todo.id);

    engine.dispose();
  });

  test('服务端登记本地完成操作后重启不再重复推送', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.addPet(
      name: 'Luna',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '',
      allergies: '',
      note: '',
    );
    await seedStore.addTodo(
      title: '原始待办',
      petId: seedStore.pets.first.id,
      dueAt: DateTime.parse('2026-04-01T08:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final store = await PetNoteStore.load(storage: storage);
    final todo = store.todos.first;
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

    await store.markChecklistDone('todo', todo.id);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final actionPush = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.actionPush,
    );
    transport.incoming.add(SyncMessage(SyncMessageTypes.syncReceived, {
      'syncId': 'sync-action-registered',
      'originDeviceId': 'owner-1',
      'actionId': actionPush.payload['actionId'],
      'kind': actionPush.payload['kind'],
      'sourceType': actionPush.payload['sourceType'],
      'itemId': actionPush.payload['itemId'],
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    engine.dispose();

    final reloadedStore = await PetNoteStore.load(storage: storage);
    final nextTransport = FakeSyncTransport();
    final nextEngine = OwnerSyncEngine(
      store: reloadedStore,
      transport: nextTransport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      nextTransport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      isEmpty,
    );

    nextEngine.dispose();
  });

  test('收到完成回执后清掉同事项的其他待确认操作', () async {
    final storage = PetNoteLocalStorage.memory();
    final store = await PetNoteStore.load(storage: storage);
    await store.addPet(
      name: 'Luna',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '',
      allergies: '',
      note: '',
    );
    await store.addTodo(
      title: '原始待办',
      petId: store.pets.first.id,
      dueAt: DateTime.parse('2026-04-01T08:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final todo = store.todos.first;
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

    await store.postponeChecklist('todo', todo.id);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      store.pendingLocalMutations.where((mutation) =>
          mutation.kind == PetNoteMutationKind.checklistAction &&
          mutation.entityId == todo.id),
      hasLength(1),
    );

    transport.incoming.add(SyncMessage(SyncMessageTypes.syncReceived, {
      'syncId': 'sync-done-registered',
      'originDeviceId': 'pet-1',
      'actionId': 'done-action',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': todo.id,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      store.pendingLocalMutations.where((mutation) =>
          mutation.kind == PetNoteMutationKind.checklistAction &&
          mutation.entityId == todo.id),
      isEmpty,
    );

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
    await engine.pushSnapshotNow(force: true);

    final push = transport.sent
        .lastWhere((message) => message.type == SyncMessageTypes.snapshotPush);
    expect(push.payload['version'], 8);

    engine.dispose();
  });

  test('收到 action 后调用 store 并回传已收到且不回声快照', () async {
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
        'syncId': 'sync-action-1',
        'originDeviceId': 'pet-1',
        'ciphertext': await crypto.encryptString(jsonEncode(action.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(store.todoById(todo.id)?.status, TodoStatus.done);
    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          message.payload['syncId'] == 'sync-action-1'),
      isTrue,
    );
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.snapshotPush),
      isEmpty,
    );

    engine.dispose();
  });

  test('后到服务器的 action 会覆盖先到状态', () async {
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
    final todo =
        store.todos.firstWhere((item) => item.status == TodoStatus.open);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'action-new',
        'ciphertext': await crypto.encryptString(jsonEncode(
          PetAction(
            kind: PetActionKind.postpone,
            sourceType: 'todo',
            itemId: todo.id,
            occurredAtMs: 100,
          ).toJson(),
        )),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'action-old',
        'ciphertext': await crypto.encryptString(jsonEncode(
          PetAction(
            kind: PetActionKind.markDone,
            sourceType: 'todo',
            itemId: todo.id,
            occurredAtMs: 200,
          ).toJson(),
        )),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.todoById(todo.id)?.status, TodoStatus.done);

    engine.dispose();
  });

  test('已应用的 action 重放时仍回传已收到标记', () async {
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
    final todo =
        store.todos.firstWhere((item) => item.status == TodoStatus.open);
    await store.markChecklistDone('todo', todo.id);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'done-replay',
        'syncId': 'sync-done-1',
        'originDeviceId': 'pet-1',
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

    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          message.payload['syncId'] == 'sync-done-1'),
      isTrue,
    );

    engine.dispose();
  });

  test('收到其他设备快照后写入本地 store', () async {
    final sourceStore = PetNoteStore.seeded();
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

    await sourceStore.addTodo(
      petId: sourceStore.pets.first.id,
      title: '来自另一台设备',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'syncId': 'snapshot-sync-1',
        'originDeviceId': 'pet-1',
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.todos.any((todo) => todo.title == '来自另一台设备'), isTrue);
    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          message.payload['syncId'] == 'snapshot-sync-1'),
      isTrue,
    );
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.snapshotPush),
      isEmpty,
    );

    engine.dispose();
  });

  test('主动请求远端覆盖快照时携带 remoteWins 策略', () async {
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
    )..start(pushInitialSnapshot: false);

    engine.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    engine.dispose();
  });

  test('收到远端覆盖快照请求时用 remoteWins 回传快照', () async {
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
    )..start(pushInitialSnapshot: false);

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

    engine.dispose();
  });

  test('普通合并快照遇到同 id 差异时不弹冲突选择', () async {
    final sourceStore = PetNoteStore.seeded();
    final store = PetNoteStore.seeded();
    final todo = store.todoById('todo-1')!;
    await sourceStore.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '对方待办标题',
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
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      resolveMergeConflict: (value) async {
        conflict = value;
        return SyncMergeSide.remote;
      },
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 4,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(conflict, isNull);
    expect(store.todoById(todo.id)?.title, todo.title);

    engine.dispose();
  });

  test('普通合并快照会应用对方标记完成', () async {
    final sourceStore = PetNoteStore.seeded();
    final store = PetNoteStore.seeded();
    final todo = store.todoById('todo-1')!;
    await sourceStore.markChecklistDone('todo', todo.id);
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    SyncMergeConflict? conflict;
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      resolveMergeConflict: (value) async {
        conflict = value;
        return SyncMergeSide.local;
      },
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 4,
        'dataPolicy': SyncDataPolicy.merge.name,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(conflict, isNull);
    expect(store.todoById(todo.id)?.status, TodoStatus.done);

    engine.dispose();
  });

  test('初始合并快照遇到同 id 差异时调用冲突选择', () async {
    final sourceStore = PetNoteStore.seeded();
    final store = PetNoteStore.seeded();
    final todo = store.todoById('todo-1')!;
    await sourceStore.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '对方待办标题',
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: '对方备注',
    );
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    SyncMergeConflict? conflict;
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      resolveMergeConflict: (value) async {
        conflict = value;
        return SyncMergeSide.remote;
      },
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    engine.requestSnapshot(
      dataPolicy: SyncDataPolicy.merge,
      resolveConflicts: true,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.merge.name,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(conflict?.collectionLabel, '待办');
    expect(conflict?.id, todo.id);
    expect(
        conflict?.differences.map((item) => item.fieldPath), contains('title'));
    expect(
        conflict?.differences.map((item) => item.fieldPath), contains('note'));
    expect(store.todoById(todo.id)?.title, '对方待办标题');

    engine.dispose();
  });

  test('初始配对合并快照保留对方同 id 原数据', () async {
    final sourceStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await sourceStore.addPet(
      name: 'B 设备狗',
      type: PetType.dog,
      breed: '柯基',
      sex: '公',
      birthday: '2023-11-01',
      weightKg: 8.5,
      neuterStatus: PetNeuterStatus.notNeutered,
      feedingPreferences: '一天两餐',
      allergies: '牛肉敏感',
      note: 'B 原数据',
    );
    await store.addPet(
      name: 'A 设备猫',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: 'A 原数据',
    );
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

    engine.requestSnapshot(
      dataPolicy: SyncDataPolicy.merge,
      resolveConflicts: true,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.merge.name,
        'mergeMode': 'preserveConflictingIds',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.pets.map((pet) => pet.name), containsAll(['A 设备猫', 'B 设备狗']));
    expect(store.pets, hasLength(2));

    engine.dispose();
  });

  test('初始配对合并后远端同源修改更新已合并实体', () async {
    final sourceStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await sourceStore.addPet(
      name: 'B 设备狗',
      type: PetType.dog,
      breed: '柯基',
      sex: '公',
      birthday: '2023-11-01',
      weightKg: 8.5,
      neuterStatus: PetNeuterStatus.notNeutered,
      feedingPreferences: '一天两餐',
      allergies: '牛肉敏感',
      note: 'B 原数据',
    );
    await sourceStore.addTodo(
      title: 'B 设备待办',
      petId: sourceStore.pets.single.id,
      dueAt: DateTime.parse('2026-03-29T12:00:00+08:00'),
      note: '',
    );
    await store.addPet(
      name: 'A 设备猫',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: 'A 原数据',
    );
    await store.addTodo(
      title: 'A 设备待办',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-28T12:00:00+08:00'),
      note: '',
    );
    final settings = await AppSettingsController.load();
    await settings.ensureDeviceId();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      settings: settings,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'syncId': 'snapshot-b-1',
        'originDeviceId': 'device-b',
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.merge.name,
        'mergeMode': 'preserveConflictingIds',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final mergedTodo =
        store.todos.singleWhere((item) => item.title == 'B 设备待办');
    final remoteTodo = sourceStore.todos.single;
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.mutation, {
        'syncId': 'mutation-b-1',
        'originDeviceId': 'device-b',
        'mutationId': 'mutation-b-1',
        'entityType': PetNoteEntityType.todo.name,
        'entityId': remoteTodo.id,
        'kind': PetNoteMutationKind.upsert.name,
        'ciphertext': await crypto.encryptString(jsonEncode(
          PetNoteMutation(
            id: 'mutation-b-1',
            entityType: PetNoteEntityType.todo,
            entityId: remoteTodo.id,
            kind: PetNoteMutationKind.upsert,
            data: remoteTodo.toJson()
              ..['title'] = 'B 设备待办已修改'
              ..['note'] = '来自 B 后续修改',
          ).toJson(),
        )),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.todos, hasLength(2));
    expect(store.todoById(mergedTodo.id)?.title, 'B 设备待办已修改');
    expect(store.todoById(mergedTodo.id)?.note, '来自 B 后续修改');

    engine.dispose();
  });

  test('初始配对合并后普通快照继续更新已合并实体', () async {
    final sourceStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await sourceStore.addPet(
      name: 'B 设备狗',
      type: PetType.dog,
      breed: '柯基',
      sex: '公',
      birthday: '2023-11-01',
      weightKg: 8.5,
      neuterStatus: PetNeuterStatus.notNeutered,
      feedingPreferences: '一天两餐',
      allergies: '牛肉敏感',
      note: 'B 原数据',
    );
    await sourceStore.addTodo(
      title: 'B 设备待办',
      petId: sourceStore.pets.single.id,
      dueAt: DateTime.parse('2026-03-29T12:00:00+08:00'),
      note: '',
    );
    await store.addPet(
      name: 'A 设备猫',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: 'A 原数据',
    );
    await store.addTodo(
      title: 'A 设备待办',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-28T12:00:00+08:00'),
      note: '',
    );
    final settings = await AppSettingsController.load();
    await settings.ensureDeviceId();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      settings: settings,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'syncId': 'snapshot-b-1',
        'originDeviceId': 'device-b',
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.merge.name,
        'mergeMode': 'preserveConflictingIds',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final mergedTodo =
        store.todos.singleWhere((item) => item.title == 'B 设备待办');
    final remoteTodo = sourceStore.todos.single;
    await sourceStore.updateTodo(
      todoId: remoteTodo.id,
      petId: remoteTodo.petId,
      title: 'B 设备待办普通快照修改',
      dueAt: remoteTodo.dueAt,
      notificationLeadTime: remoteTodo.notificationLeadTime,
      note: '普通快照回流',
    );

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 4,
        'syncId': 'snapshot-b-2',
        'originDeviceId': 'device-b',
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.merge.name,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.todos, hasLength(2));
    expect(store.todoById(mergedTodo.id)?.title, 'B 设备待办普通快照修改');
    expect(store.todoById(mergedTodo.id)?.note, '普通快照回流');
    expect(
      store.todos.where((item) => item.title.startsWith('B 设备待办')),
      hasLength(1),
    );

    engine.dispose();
  });

  test('稳定合并 id 回传原设备时映射回本机原始数据', () async {
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await store.addPet(
      name: 'A 设备猫',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: 'A 原数据',
    );
    await store.addTodo(
      title: 'A 设备待办',
      petId: store.pets.single.id,
      dueAt: DateTime.parse('2026-03-28T12:00:00+08:00'),
      note: '',
    );
    final settings = await AppSettingsController.load();
    final localDeviceId = await settings.ensureDeviceId();
    final todo = store.todos.single;
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      settings: settings,
      throttle: const Duration(milliseconds: 50),
    )..start(pushInitialSnapshot: false);
    final stablePetId = 'pet-merge-$localDeviceId-${todo.petId}';
    final stableTodoId = 'todo-merge-$localDeviceId-${todo.id}';

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.mutation, {
        'syncId': 'mutation-return-a-1',
        'originDeviceId': 'device-b',
        'mutationId': 'mutation-return-a-1',
        'entityType': PetNoteEntityType.todo.name,
        'entityId': stableTodoId,
        'kind': PetNoteMutationKind.upsert.name,
        'ciphertext': await crypto.encryptString(jsonEncode(
          PetNoteMutation(
            id: 'mutation-return-a-1',
            entityType: PetNoteEntityType.todo,
            entityId: stableTodoId,
            kind: PetNoteMutationKind.upsert,
            data: todo.toJson()
              ..['id'] = stableTodoId
              ..['petId'] = stablePetId
              ..['title'] = 'A 设备待办被对方修改',
          ).toJson(),
        )),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.todos, hasLength(1));
    expect(store.todoById(todo.id)?.title, 'A 设备待办被对方修改');
    expect(store.todoById(stableTodoId), isNull);

    engine.dispose();
  });

  test('action 解密失败时不回发 ack', () async {
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

  test('当前设备被移除时清除本地配对', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setSharedKeyBase64('shared-key');
    await settings.setHouseholdAuthToken('auth-token-1');
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
      settings: settings,
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.householdId, isNull);
    expect(settings.sharedKeyBase64, isNull);
    expect(settings.householdAuthToken, isNull);

    engine.dispose();
  });

  test('当前设备被移除后不再推送本地新增操作', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setSharedKeyBase64('shared-key');
    await settings.setHouseholdAuthToken('auth-token-1');
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
      settings: settings,
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    transport.sent.clear();
    await store.addTodo(
      title: '解绑后本地新增',
      petId: store.pets.first.id,
      dueAt: DateTime.parse('2026-04-01T08:00:00+08:00'),
      note: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.mutationPush),
      isEmpty,
    );

    engine.dispose();
  });

  test('当前设备被移除后不再继续请求设备列表和快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setSharedKeyBase64('shared-key');
    await settings.setHouseholdAuthToken('auth-token-1');
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
      settings: settings,
    )..start(pushInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    transport.sent.clear();
    engine.requestDevices();
    engine.requestSnapshot(resolveConflicts: true);
    engine.renameDevice('device-1', '新名字');

    expect(transport.sent, isEmpty);

    engine.dispose();
  });

  test('入站事件应用失败时 checkpoint 不推进本地水位', () async {
    final settings = await AppSettingsController.load();
    await settings.setHouseholdId('house-1');
    await settings.setLastPulledServerSeq(4);
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
      settings: settings,
    )..start(pushInitialSnapshot: false, requestInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.mutation, {
        'mutationId': 'bad-mutation-1',
        'syncId': 'sync-bad-mutation-1',
        'serverSeq': 5,
        'ciphertext': 'not-valid-ciphertext',
      }),
    );
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.syncCheckpoint, {
        'toServerSeq': 5,
        'sentEventCount': 1,
        'remainingEventCount': 1,
        'hasMore': true,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.lastPulledServerSeq, 4);
    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    // README 同步架构约定：入站事件应用失败后必须触发无 checkpoint 补拉，
    // 不携带 afterServerSeq / maxEvents，由服务端做全量回放。
    expect(request.payload.containsKey('afterServerSeq'), isFalse);
    expect(request.payload.containsKey('maxEvents'), isFalse);

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

  void setState(SyncConnectionState value) {
    _state.value = value;
  }
}
