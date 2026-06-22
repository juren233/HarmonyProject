import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_photo_attachment.dart';
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

  test('收到快照时会把主人端宠物头像写成本机图片路径', () async {
    final sourceDirectory = Directory.systemTemp.createTempSync(
      'petnote_owner_photo_',
    );
    final replicaDirectory = Directory.systemTemp.createTempSync(
      'petnote_replica_photo_',
    );
    addTearDown(() async {
      if (sourceDirectory.existsSync()) {
        await sourceDirectory.delete(recursive: true);
      }
      if (replicaDirectory.existsSync()) {
        await replicaDirectory.delete(recursive: true);
      }
    });
    final sourcePhoto = File('${sourceDirectory.path}/strong.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final sourceStore = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );
    await sourceStore.addPet(
      name: '强',
      type: PetType.dog,
      photoPath: sourcePhoto.path,
      breed: '兔兔混合描述',
      sex: '弟弟',
      birthday: '2025-01-01',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '主人端头像',
    );
    final replicaStore = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
      photoAttachmentCodec: SyncPhotoAttachmentCodec(
        directoryLoader: () async => replicaDirectory.path,
      ),
    )..start(requestInitialSnapshot: false);
    final ownerCodec = SyncPhotoAttachmentCodec(
      directoryLoader: () async => sourceDirectory.path,
    );
    final state = sourceStore.exportDataState();
    final payload = {
      'data': state.toJson(),
      petPhotoAttachmentsPayloadKey: [
        for (final attachment in await ownerCodec.collectFromState(state))
          attachment.toJson(),
      ],
    };

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'ciphertext': await crypto.encryptString(jsonEncode(payload)),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final syncedPet = replicaStore.pets.single;
    expect(syncedPet.photoPath, isNot(sourcePhoto.path));
    expect(syncedPet.photoPath, isNotNull);
    expect(File(syncedPet.photoPath!).readAsBytesSync(), [1, 2, 3, 4]);
    expect(syncedPet.photoPath, startsWith(replicaDirectory.path));

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

  test('收到完成动作后会清掉同事项的其他待确认操作', () async {
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

    controller.pendingItemKeys.value = {'todo:${todo.id}'};
    await controller.sendAction(
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.action, {
        'actionId': 'done-1',
        'syncId': 'sync-done-1',
        'originDeviceId': 'owner-1',
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
    expect(replicaStore.pendingLocalMutations, isEmpty);

    controller.dispose();
  });

  test('普通合并快照遇到同 id 差异时不弹冲突选择', () async {
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

    expect(conflict, isNull);
    expect(replicaStore.todoById(todo.id)?.title, todo.title);

    controller.dispose();
  });

  test('普通合并快照会应用主人端标记完成', () async {
    final ownerStore = PetNoteStore.seeded();
    final replicaStore = PetNoteStore.seeded();
    final todo = replicaStore.todoById('todo-1')!;
    await ownerStore.markChecklistDone('todo', todo.id);
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
        return SyncMergeSide.local;
      },
    )..start(requestInitialSnapshot: false);

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'dataPolicy': SyncDataPolicy.merge.name,
        'ciphertext': await crypto
            .encryptString(jsonEncode(ownerStore.exportDataState().toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(conflict, isNull);
    expect(replicaStore.todoById(todo.id)?.status, TodoStatus.done);

    controller.dispose();
  });

  test('completedItemKeys 会包含延后和跳过状态', () {
    final store = PetNoteStore.seeded();
    final todo = store.todoById('todo-2')!;
    final reminder = store.reminderById('reminder-2')!;

    todo.status = TodoStatus.postponed;
    reminder.status = ReminderStatus.skipped;

    expect(
      store.completedItemKeys(),
      containsAll(<String>[
        'todo:${todo.id}',
        'reminder:${reminder.id}',
      ]),
    );
  });

  test('恢复前台重复收到同源新增快照不会生成两份数据', () async {
    final ownerStore = PetNoteStore.seeded();
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
    await ownerStore.addTodo(
      petId: ownerStore.pets.first.id,
      title: '主人端恢复重复待办',
      dueAt: DateTime.parse('2026-03-31T12:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      note: '恢复前台重复快照',
    );
    final sourceTodo = ownerStore.todos.firstWhere(
      (item) => item.title == '主人端恢复重复待办',
    );
    final state = ownerStore.exportDataState();
    final encryptedSnapshot =
        await crypto.encryptString(jsonEncode(state.toJson()));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 1,
        'syncId': 'snapshot-initial-merge',
        'originDeviceId': 'owner-1',
        'mergeMode': 'preserveConflictingIds',
        'ciphertext': encryptedSnapshot,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'syncId': 'snapshot-resume-repeat',
        'originDeviceId': 'owner-1',
        'ciphertext': encryptedSnapshot,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final importedTodos = replicaStore.todos
        .where((item) => item.title == '主人端恢复重复待办')
        .toList(growable: false);
    expect(importedTodos, hasLength(1));
    expect(importedTodos.single.id, 'todo-merge-owner-1-${sourceTodo.id}');
    expect(replicaStore.todoById(sourceTodo.id), isNull);
    expect(
      transport.sent.where((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          (message.payload['syncId'] == 'snapshot-initial-merge' ||
              message.payload['syncId'] == 'snapshot-resume-repeat')),
      hasLength(2),
    );

    controller.dispose();
  });

  test('收到主人端新增待办操作后应用到本地', () async {
    final replicaStore = PetNoteStore.seeded();
    final currentPet = replicaStore.pets.last;
    replicaStore
      ..setActiveTab(AppTab.pets)
      ..selectPet(currentPet.id);
    final observedTabs = <AppTab>[];
    replicaStore.addListener(() {
      observedTabs.add(replicaStore.activeTab);
    });
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
    final todo = TodoItem(
      id: 'todo-remote',
      petId: replicaStore.pets.first.id,
      title: '主人端新增待办',
      dueAt: DateTime.parse('2026-03-29T12:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      status: TodoStatus.open,
      note: '远端操作',
    );
    final mutation = PetNoteMutation(
      id: 'mutation-1',
      entityType: PetNoteEntityType.todo,
      entityId: todo.id,
      kind: PetNoteMutationKind.upsert,
      data: todo.toJson(),
    );

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.mutation, {
        'mutationId': mutation.id,
        'syncId': 'sync-mutation-1',
        'originDeviceId': 'owner-1',
        'entityType': mutation.entityType.name,
        'entityId': mutation.entityId,
        'kind': mutation.kind.name,
        'ciphertext': await crypto.encryptString(jsonEncode(mutation.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.todoById(todo.id)?.title, '主人端新增待办');
    expect(replicaStore.activeTab, AppTab.pets);
    expect(replicaStore.selectedPetId, currentPet.id);
    expect(observedTabs, isNot(contains(AppTab.checklist)));
    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.syncReceived &&
          message.payload['syncId'] == 'sync-mutation-1'),
      isTrue,
    );

    controller.dispose();
  });

  test('收到主人端宠物 upsert 时会同步头像附件', () async {
    final sourceDirectory = Directory.systemTemp.createTempSync(
      'petnote_owner_mutation_photo_',
    );
    final replicaDirectory = Directory.systemTemp.createTempSync(
      'petnote_replica_mutation_photo_',
    );
    addTearDown(() async {
      if (sourceDirectory.existsSync()) {
        await sourceDirectory.delete(recursive: true);
      }
      if (replicaDirectory.existsSync()) {
        await replicaDirectory.delete(recursive: true);
      }
    });
    final sourcePhoto = File('${sourceDirectory.path}/strong.png')
      ..writeAsBytesSync([9, 8, 7]);
    final replicaStore = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );
    final remotePet = Pet(
      id: 'pet-remote-photo',
      name: '强',
      avatarText: '强',
      photoPath: sourcePhoto.path,
      type: PetType.dog,
      breed: '法斗',
      sex: '弟弟',
      birthday: '2025-01-01',
      ageLabel: '新加入',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '主人端头像',
    );
    final mutation = PetNoteMutation(
      id: 'mutation-pet-photo',
      entityType: PetNoteEntityType.pet,
      entityId: remotePet.id,
      kind: PetNoteMutationKind.upsert,
      data: remotePet.toJson(),
    );
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
      photoAttachmentCodec: SyncPhotoAttachmentCodec(
        directoryLoader: () async => replicaDirectory.path,
      ),
    )..start(requestInitialSnapshot: false);
    final attachment =
        await const SyncPhotoAttachmentCodec().collectForPet(remotePet);
    final mutationPayload = mutation.toJson()
      ..[petPhotoAttachmentPayloadKey] = attachment!.toJson();

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.mutation, {
        'mutationId': mutation.id,
        'syncId': 'sync-pet-photo',
        'originDeviceId': 'owner-1',
        'entityType': mutation.entityType.name,
        'entityId': mutation.entityId,
        'kind': mutation.kind.name,
        'ciphertext': await crypto.encryptString(jsonEncode(mutationPayload)),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final syncedPet = replicaStore.petById(remotePet.id)!;
    expect(syncedPet.photoPath, isNot(sourcePhoto.path));
    expect(syncedPet.photoPath, startsWith(replicaDirectory.path));
    expect(File(syncedPet.photoPath!).readAsBytesSync(), [9, 8, 7]);
    expect(syncedPet.type, PetType.dog);
    expect(petAvatarFallbackForPet(syncedPet), '🐶');

    controller.dispose();
  });

  test('收到主人端删除记录操作后不打断当前查看的宠物', () async {
    final replicaStore = PetNoteStore.seeded();
    final currentPet = replicaStore.pets.last;
    replicaStore
      ..setActiveTab(AppTab.checklist)
      ..selectPet(currentPet.id);
    final record = replicaStore.records.first;
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
    final mutation = PetNoteMutation(
      id: 'mutation-delete-record',
      entityType: PetNoteEntityType.record,
      entityId: record.id,
      kind: PetNoteMutationKind.delete,
    );

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.mutation, {
        'mutationId': mutation.id,
        'syncId': 'sync-delete-record',
        'originDeviceId': 'owner-1',
        'entityType': mutation.entityType.name,
        'entityId': mutation.entityId,
        'kind': mutation.kind.name,
        'ciphertext': await crypto.encryptString(jsonEncode(mutation.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.recordById(record.id), isNull);
    expect(replicaStore.activeTab, AppTab.checklist);
    expect(replicaStore.selectedPetId, currentPet.id);

    controller.dispose();
  });

  test('收到主人端更新宠物提醒和记录时不打断当前查看位置', () async {
    final replicaStore = PetNoteStore.seeded();
    final currentPet = replicaStore.pets.last;
    replicaStore
      ..setActiveTab(AppTab.checklist)
      ..selectPet(currentPet.id);
    final observedStates = <({AppTab tab, String petId})>[];
    replicaStore.addListener(() {
      observedStates.add(
        (tab: replicaStore.activeTab, petId: replicaStore.selectedPetId),
      );
    });
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
    final remotePet = Pet(
      id: 'pet-remote',
      name: '主人端新增宠物',
      avatarText: '主',
      type: PetType.cat,
      breed: '狸花',
      sex: '妹妹',
      birthday: '2024-01-01',
      ageLabel: '2 岁',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '远端宠物',
    );
    final remoteReminder = ReminderItem(
      id: 'reminder-remote',
      petId: replicaStore.pets.first.id,
      kind: ReminderKind.review,
      title: '主人端复查提醒',
      scheduledAt: DateTime.parse('2026-03-30T10:00:00+08:00'),
      notificationLeadTime: NotificationLeadTime.none,
      recurrence: '单次',
      status: ReminderStatus.pending,
      note: '远端提醒',
    );
    final remoteRecord = PetRecord(
      id: 'record-remote',
      petId: replicaStore.pets.first.id,
      type: PetRecordType.medical,
      title: '主人端健康记录',
      recordDate: DateTime.parse('2026-03-30T09:00:00+08:00'),
      summary: '精神正常',
      note: '远端记录',
      purpose: RecordPurpose.health,
    );

    await _sendMutation(
      transport: transport,
      crypto: crypto,
      mutation: PetNoteMutation(
        id: 'mutation-remote-pet',
        entityType: PetNoteEntityType.pet,
        entityId: remotePet.id,
        kind: PetNoteMutationKind.upsert,
        data: remotePet.toJson(),
      ),
      syncId: 'sync-remote-pet',
    );
    await _sendMutation(
      transport: transport,
      crypto: crypto,
      mutation: PetNoteMutation(
        id: 'mutation-remote-reminder',
        entityType: PetNoteEntityType.reminder,
        entityId: remoteReminder.id,
        kind: PetNoteMutationKind.upsert,
        data: remoteReminder.toJson(),
      ),
      syncId: 'sync-remote-reminder',
    );
    await _sendMutation(
      transport: transport,
      crypto: crypto,
      mutation: PetNoteMutation(
        id: 'mutation-remote-record',
        entityType: PetNoteEntityType.record,
        entityId: remoteRecord.id,
        kind: PetNoteMutationKind.upsert,
        data: remoteRecord.toJson(),
      ),
      syncId: 'sync-remote-record',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.petById(remotePet.id)?.name, '主人端新增宠物');
    expect(replicaStore.reminderById(remoteReminder.id)?.title, '主人端复查提醒');
    expect(replicaStore.recordById(remoteRecord.id)?.title, '主人端健康记录');
    expect(replicaStore.activeTab, AppTab.checklist);
    expect(replicaStore.selectedPetId, currentPet.id);
    expect(
      observedStates,
      everyElement((state) =>
          state.tab == AppTab.checklist && state.petId == currentPet.id),
    );
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.syncReceived)
          .map((message) => message.payload['syncId']),
      containsAll(
        ['sync-remote-pet', 'sync-remote-reminder', 'sync-remote-record'],
      ),
    );

    controller.dispose();
  });

  test('初始合并快照遇到同 id 差异时调用冲突选择', () async {
    final ownerStore = PetNoteStore.seeded();
    final replicaStore = PetNoteStore.seeded();
    final todo = replicaStore.todoById('todo-1')!;
    await ownerStore.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '主人端待办标题',
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: '主人端备注',
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

    controller.requestSnapshot(
      dataPolicy: SyncDataPolicy.merge,
      resolveConflicts: true,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto
            .encryptString(jsonEncode(ownerStore.exportDataState().toJson())),
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
    expect(replicaStore.todoById(todo.id)?.title, '主人端待办标题');

    controller.dispose();
  });

  test('sendAction 会写入持久 checklist mutation 并上行', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final replicaStore = await PetNoteStore.load(storage: storage);
    final todo = replicaStore.todos.first;
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
      PetAction(
        kind: PetActionKind.markDone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final actionMessages = transport.sent
        .where((message) => message.type == SyncMessageTypes.actionPush)
        .toList();
    expect(actionMessages, hasLength(1));
    expect(actionMessages.single.payload['actionId'], isNotEmpty);
    expect(actionMessages.single.payload['kind'], PetActionKind.markDone.name);
    expect(actionMessages.single.payload['sourceType'], 'todo');
    expect(actionMessages.single.payload['itemId'], todo.id);
    expect(replicaStore.todoById(todo.id)?.status, TodoStatus.done);
    expect(controller.pendingItemKeys.value, contains('todo:${todo.id}'));
    expect(
      replicaStore.pendingLocalMutations.where(
        (mutation) =>
            mutation.kind == PetNoteMutationKind.checklistAction &&
            mutation.entityType == PetNoteEntityType.todo &&
            mutation.entityId == todo.id &&
            mutation.actionKind == PetActionKind.markDone,
      ),
      hasLength(1),
    );

    controller.dispose();
  });

  test('replaceAllData 会清理宠物端 outbox 的运行时待发送状态', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final replicaStore = await PetNoteStore.load(storage: storage);
    final todo =
        replicaStore.todos.firstWhere((item) => item.status == TodoStatus.open);
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
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.pendingItemKeys.value, contains('todo:${todo.id}'));
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(1),
    );

    await replicaStore.replaceAllData(PetNoteStore.seeded().exportDataState());

    expect(controller.pendingItemKeys.value, isEmpty);
    expect(replicaStore.pendingLocalMutations, isEmpty);

    await controller.sendAction(
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(2),
    );
    expect(controller.pendingItemKeys.value, contains('todo:${todo.id}'));

    await replicaStore.clearAllData();

    expect(controller.pendingItemKeys.value, isEmpty);
    expect(replicaStore.pendingLocalMutations, isEmpty);

    controller.dispose();
  });

  test('普通合并快照不会清理宠物端未回执 outbox 状态', () async {
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
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: 'todo-1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));
    expect(replicaStore.pendingLocalMutations, hasLength(1));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 3,
        'ciphertext': await crypto.encryptString(
          jsonEncode(replicaStore.exportDataState().toJson()),
        ),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));
    expect(replicaStore.pendingLocalMutations, hasLength(1));
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(1),
    );

    controller.dispose();
  });

  test('远端覆盖快照不会清理宠物端未回执 outbox 状态', () async {
    final sourceStore = PetNoteStore.seeded();
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

    await replicaStore.markChecklistDone('todo', 'todo-1');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));
    expect(replicaStore.pendingLocalMutations, hasLength(1));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.remoteWins.name,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));
    expect(replicaStore.pendingLocalMutations, hasLength(1));
    expect(replicaStore.todoById('todo-1')?.status, TodoStatus.done);

    controller.dispose();
  });

  test('replaceAllData 会丢弃失败队列和进行中的旧 mutation flush', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final firstStore = await PetNoteStore.load(storage: storage);
    final todo = firstStore.todos.first;
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final firstController = PetReplicaController(
      store: firstStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);

    await firstController.sendAction(
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(firstStore.pendingLocalMutations, hasLength(1));
    firstController.dispose();

    final secondStore = await PetNoteStore.load(storage: storage);
    transport.sent.clear();
    await transport.disconnect();
    final secondController = PetReplicaController(
      store: secondStore,
      transport: transport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondController.failedSyncCount.value, 1);

    await secondStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    await transport.connect();
    secondController.retryFailedSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(secondController.failedSyncCount.value, 0);
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      isEmpty,
    );

    secondController.dispose();
  });

  test('replaceAllData 会清掉失败队列里已排队的旧 actionPush', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final replicaStore = await PetNoteStore.load(storage: storage);
    final todo =
        replicaStore.todos.firstWhere((item) => item.status == TodoStatus.open);
    final transport = FakeSyncTransport()
      ..setState(SyncConnectionState.disconnected);
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
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.failedSyncCount.value, 1);

    await replicaStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    await transport.connect();
    controller.retryFailedSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.failedSyncCount.value, 0);
    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      isEmpty,
    );

    controller.dispose();
  });

  test('宠物端普通修改会按同一套 mutation outbox 上行', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final replicaStore = await PetNoteStore.load(storage: storage);
    final todo = replicaStore.todos.first;
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

    await replicaStore.updateTodo(
      todoId: todo.id,
      petId: todo.petId,
      title: '宠物端改过的标题',
      dueAt: todo.dueAt.add(const Duration(hours: 1)),
      notificationLeadTime: todo.notificationLeadTime,
      note: '宠物端改过的备注',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final mutationMessages = transport.sent
        .where((message) => message.type == SyncMessageTypes.mutationPush)
        .toList();
    expect(mutationMessages, hasLength(1));
    final mutation = PetNoteMutation.fromJson(Map<String, dynamic>.from(
      jsonDecode(
        await crypto.decryptString(
          mutationMessages.single.payload['ciphertext'] as String,
        ),
      ) as Map,
    ));
    expect(mutation.entityType, PetNoteEntityType.todo);
    expect(mutation.entityId, todo.id);
    expect(mutation.kind, PetNoteMutationKind.upsert);
    expect(mutation.data?['title'], '宠物端改过的标题');
    expect(mutation.data?['note'], '宠物端改过的备注');
    expect(replicaStore.pendingLocalMutations, hasLength(1));

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.syncReceived, {
        'syncId': 'sync-mutation-1',
        'mutationId': mutationMessages.single.payload['mutationId'],
        'receivedDeviceId': 'owner-1',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(replicaStore.pendingLocalMutations, isEmpty);

    controller.dispose();
  });

  test('宠物端重启后会重发未确认的 checklist action', () async {
    final storage = PetNoteLocalStorage.memory();
    final seedStore = await PetNoteStore.load(storage: storage);
    await seedStore.replaceAllData(PetNoteStore.seeded().exportDataState());
    final firstStore = await PetNoteStore.load(storage: storage);
    final todo = firstStore.todos.first;
    final firstTransport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final firstController = PetReplicaController(
      store: firstStore,
      transport: firstTransport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);

    await firstController.sendAction(
      PetAction(
        kind: PetActionKind.postpone,
        sourceType: 'todo',
        itemId: todo.id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      firstTransport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      hasLength(1),
    );
    expect(firstStore.pendingLocalMutations, hasLength(1));

    firstController.dispose();

    final secondStore = await PetNoteStore.load(storage: storage);
    final secondTransport = FakeSyncTransport();
    final secondController = PetReplicaController(
      store: secondStore,
      transport: secondTransport,
      crypto: crypto,
    )..start(requestInitialSnapshot: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final restartedMessages = secondTransport.sent
        .where((message) => message.type == SyncMessageTypes.actionPush)
        .toList();
    expect(restartedMessages, hasLength(1));
    expect(restartedMessages.single.payload['actionId'], isNotEmpty);
    expect(secondStore.pendingLocalMutations, hasLength(1));

    secondTransport.incoming.add(
      SyncMessage(SyncMessageTypes.syncReceived, {
        'syncId': 'sync-action-1',
        'actionId': restartedMessages.single.payload['actionId'],
        'kind': PetActionKind.postpone.name,
        'sourceType': 'todo',
        'itemId': todo.id,
        'receivedDeviceId': 'owner-1',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondStore.pendingLocalMutations, isEmpty);

    secondController.dispose();
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
      expect(controller.pendingItemKeys.value, contains('todo:todo-1'));
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
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
    expect(replicaStore.pendingLocalMutations, isEmpty);

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

  test('首次远端覆盖快照会刷新 lastSyncedAt', () async {
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
    final sourceStore = PetNoteStore.seeded();

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 2,
        'ciphertext': await crypto
            .encryptString(jsonEncode(sourceStore.exportDataState().toJson())),
        'dataPolicy': SyncDataPolicy.remoteWins.name,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.lastSyncedAt.value, isNotNull);
    expect(replicaStore.todoById('todo-1'), isNotNull);

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

  test('device_config removed 后不再推送宠物端操作', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setServedPetId('pet-1');
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
      settings: settings,
    )..start(requestInitialSnapshot: false);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    transport.sent.clear();
    await controller.sendAction(PetAction(
      kind: PetActionKind.markDone,
      sourceType: 'todo',
      itemId: replicaStore.todos.first.id,
    ));

    expect(
      transport.sent
          .where((message) => message.type == SyncMessageTypes.actionPush),
      isEmpty,
    );

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

  void setState(SyncConnectionState value) {
    _state.value = value;
  }
}

Future<void> _sendMutation({
  required FakeSyncTransport transport,
  required SyncCrypto crypto,
  required PetNoteMutation mutation,
  required String syncId,
}) async {
  transport.incoming.add(
    SyncMessage(SyncMessageTypes.mutation, {
      'mutationId': mutation.id,
      'syncId': syncId,
      'originDeviceId': 'owner-1',
      'entityType': mutation.entityType.name,
      'entityId': mutation.entityId,
      'kind': mutation.kind.name,
      'ciphertext': await crypto.encryptString(jsonEncode(mutation.toJson())),
    }),
  );
}
