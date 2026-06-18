import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('未配对时 ensureStarted 不建立连接', () async {
    final settings = await AppSettingsController.load();
    final service = SyncService(
      settings: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => FakeSyncTransport(),
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(service.isActive, isFalse);
  });

  test('owner 配对完整时建立连接、启动 owner engine 并发送 hello', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setDeviceName('主人手机');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(service.isActive, isTrue);
    expect(service.ownerEngine, isNotNull);
    expect(transport.connected, isTrue);
    expect(transport.sent.first.type, SyncMessageTypes.hello);
    expect(transport.sent.first.payload['role'], 'owner');
    expect(transport.sent.first.payload['authToken'], 'auth-token-1');
    expect(
      transport.sent
          .skip(1)
          .any((message) => message.type == SyncMessageTypes.snapshotPush),
      isTrue,
    );

    await service.stop();
  });

  test('pet 配对完整时启动宠物端 controller', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(service.isActive, isTrue);
    expect(service.petController, isNotNull);
    expect(transport.sent.first.type, SyncMessageTypes.hello);
    expect(transport.sent.first.payload['role'], 'pet');
    expect(transport.sent.first.payload['authToken'], 'auth-token-1');
    expect(
      transport.sent.map((message) => message.type),
      containsAllInOrder([
        SyncMessageTypes.snapshotRequest,
        SyncMessageTypes.snapshotPush,
      ]),
    );
    expect(
      transport.sent.any((message) =>
          message.type == SyncMessageTypes.hello &&
          message.payload['role'] == 'pet'),
      isTrue,
    );

    await service.stop();
  });

  test('owner 选择以另一台设备为准时主动请求 remoteWins 快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.remoteWins);
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    await service.stop();
  });

  test('pet 选择以另一台设备为准时主动请求 remoteWins 快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.remoteWins);
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    await service.stop();
  });

  test('导入备份推送覆盖快照时不会夹带启动 merge 快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.pushLocalSnapshotToAllDevices(store: PetNoteStore.seeded());

    final snapshotPushes = transport.sent
        .where((message) => message.type == SyncMessageTypes.snapshotPush)
        .toList(growable: false);
    expect(snapshotPushes, hasLength(1));
    expect(
      snapshotPushes.single.payload['dataPolicy'],
      SyncDataPolicy.remoteWins.name,
    );
    expect(
      transport.sent.map((message) => message.type),
      isNot(contains(SyncMessageTypes.snapshotRequest)),
    );

    await service.stop();
  });

  test('导入备份覆盖快照未建立同步连接时不登记待回执', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => transport,
    );

    await service.pushLocalSnapshotToAllDevices(store: PetNoteStore.seeded());

    expect(settings.pendingResetSnapshotSyncId, isNull);
    expect(service.failedSyncCount?.value, 0);
    expect(
      transport.sent.where(
        (message) => message.type == SyncMessageTypes.snapshotPush,
      ),
      isEmpty,
    );

    await service.stop();
  });

  test('导入备份覆盖快照断线后会跨服务重启继续待发送', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();

    await service.ensureStarted(store: store, pushStartupSnapshot: false);
    final firstTransport = transports.single;
    firstTransport.setState(SyncConnectionState.disconnected);
    await service.pushLocalSnapshotToAllDevices(store: store);

    expect(service.failedSyncCount?.value, 1);
    expect(
      firstTransport.sent.where(
        (message) => message.type == SyncMessageTypes.snapshotPush,
      ),
      isEmpty,
    );
    await service.stop();

    final restartedService = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );

    await restartedService.ensureStarted(
      store: store,
      pushStartupSnapshot: false,
    );

    final secondTransport = transports.last;
    final snapshotPushes = secondTransport.sent
        .where((message) => message.type == SyncMessageTypes.snapshotPush)
        .toList(growable: false);
    expect(snapshotPushes, hasLength(1));
    expect(
      snapshotPushes.single.payload['dataPolicy'],
      SyncDataPolicy.remoteWins.name,
    );
    expect(restartedService.failedSyncCount?.value, 1);

    secondTransport.incoming.add(SyncMessage(SyncMessageTypes.syncReceived, {
      'syncId': snapshotPushes.single.payload['syncId'],
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.pendingResetSnapshotSyncId, isNull);
    expect(restartedService.failedSyncCount?.value, 0);

    await restartedService.stop();
  });

  test('pet 已有同步连接时新配对的远端覆盖策略仍会重启并请求快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setHouseholdId('new-house');
    await settings.setHouseholdAuthToken('new-auth-token');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.remoteWins);
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    final request = transports.last.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(settings.pendingInitialSyncPolicy, isNull);

    await service.stop();
  });

  test('owner 已有同步连接时新配对的远端覆盖策略仍会重启并请求快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setHouseholdId('new-house');
    await settings.setHouseholdAuthToken('new-auth-token');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.remoteWins);
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    final request = transports.last.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(settings.pendingInitialSyncPolicy, isNull);

    await service.stop();
  });

  test('pet 选择以当前设备为准时主动推送 remoteWins 快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    final push = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(
      transport.sent.map((message) => message.type),
      isNot(contains(SyncMessageTypes.snapshotRequest)),
    );

    await service.stop();
  });

  test('owner 选择以当前设备为准时主动推送 remoteWins 快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    final push = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(
      transport.sent.map((message) => message.type),
      isNot(contains(SyncMessageTypes.snapshotRequest)),
    );

    await service.stop();
  });

  test('pet 已有同步连接时新配对的本机覆盖策略仍会重启并推送快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setHouseholdId('new-house');
    await settings.setHouseholdAuthToken('new-auth-token');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    final push = transports.last.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(
      transports.last.sent.map((message) => message.type),
      isNot(contains(SyncMessageTypes.snapshotRequest)),
    );
    expect(settings.pendingInitialSyncPolicy, isNull);

    await service.stop();
  });

  test('owner 已有同步连接时新配对的本机覆盖策略仍会重启并推送快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setHouseholdId('new-house');
    await settings.setHouseholdAuthToken('new-auth-token');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    final push = transports.last.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(
      transports.last.sent.map((message) => message.type),
      isNot(contains(SyncMessageTypes.snapshotRequest)),
    );
    expect(settings.pendingInitialSyncPolicy, isNull);

    await service.stop();
  });

  test('owner 解绑后重绑不会用旧一次性策略提前重启同步', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    final secretStore = InMemorySyncSecretStore();
    final oldCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final oldSharedKey = await oldCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(oldSharedKey);
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    expect(settings.pendingInitialSyncPolicy, isNull);
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    await settings.clearSyncPairing();
    final newCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '654321',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final newSharedKey = await newCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(newSharedKey);
    await settings.saveSyncPairing(
      serverUrl: 'ws://127.0.0.1/ws',
      householdId: 'new-house',
      sharedKeyBase64: newSharedKey,
      householdAuthToken: 'new-auth-token',
      deviceName: '主人手机',
    );
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.connected, isTrue);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    expect(
      transports.last.sent.map((message) => message.type),
      contains(SyncMessageTypes.snapshotRequest),
    );

    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.localWins);
    await service.ensureStarted(store: store);

    expect(transports, hasLength(3));
    expect(transports[1].connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    final push = transports.last.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(push.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    final ciphertext = push.payload['ciphertext'] as String;
    expect(await newCrypto.decryptString(ciphertext), contains('pets'));
    await expectLater(
      oldCrypto.decryptString(ciphertext),
      throwsA(isA<Object>()),
    );
    expect(settings.pendingInitialSyncPolicy, isNull);

    await service.stop();
  });

  test('owner 清除配对后再次启动会停止旧同步连接', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.clearSyncPairing();
    await service.ensureStarted(store: store);

    expect(transport.connected, isFalse);
    expect(service.isActive, isFalse);

    await service.stop();
  });

  test('owner 清除配对后安全密钥不可读也会停止旧同步连接', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final secretStore = _ToggleableSyncSecretStore(
      await crypto.exportKeyBase64(),
    );
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.clearSyncPairing();
    secretStore.shouldThrowOnLoad = true;
    await service.ensureStarted(store: store);

    expect(transport.connected, isFalse);
    expect(service.isActive, isFalse);

    await service.stop();
  });

  test('App 更新后安全密钥不可读时使用设置中的备份密钥继续启动同步', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final sharedKey = await crypto.exportKeyBase64();
    await settings.setSharedKeyBase64(sharedKey);
    final secretStore = _ToggleableSyncSecretStore(null)
      ..shouldThrowOnLoad = true;
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(service.isActive, isTrue);
    expect(transport.connected, isTrue);
    expect(transport.sent.first.type, SyncMessageTypes.hello);
    expect(transport.sent.first.payload['authToken'], 'auth-token-1');

    await service.stop();
  });

  test('owner 重新配对后即使没有一次性策略也会切换到新家庭配置', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final oldCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final oldSharedKey = await oldCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(oldSharedKey);
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (url) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.clearSyncPairing();
    final newCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '654321',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final newSharedKey = await newCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(newSharedKey);
    await settings.saveSyncPairing(
      serverUrl: 'ws://127.0.0.1/ws',
      householdId: 'new-house',
      sharedKeyBase64: newSharedKey,
      householdAuthToken: 'new-auth-token',
      deviceName: '主人手机',
    );
    await service.ensureStarted(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(
      transports.first.sent.map((message) => message.type),
      contains(SyncMessageTypes.hello),
    );
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    expect(transports.last.sent.first.payload['authToken'], 'new-auth-token');
    expect(
      transports.last.sent.map((message) => message.type),
      contains(SyncMessageTypes.snapshotRequest),
    );
    expect(await secretStore.loadSharedKey(), newSharedKey);

    await service.stop();
  });

  test('owner 配对配置变更后再次启动会切换到新家庭配置', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final oldCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final oldSharedKey = await oldCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(oldSharedKey);
    final transports = <FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setHouseholdId('new-house');
    await settings.setHouseholdAuthToken('new-auth-token');
    await settings.setSharedKeyBase64(oldSharedKey);
    await service.ensureStartedForOwner(store: store);

    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
    expect(transports.last.sent.first.type, SyncMessageTypes.hello);
    expect(transports.last.sent.first.payload['householdId'], 'new-house');
    expect(transports.last.sent.first.payload['authToken'], 'new-auth-token');
    expect(transports.last.sent.first.payload['deviceId'],
        transports.first.sent.first.payload['deviceId']);

    await service.stop();
  });

  test('owner 配对合并时会透传保留冲突 ID 的合并模式', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.merge);
    await service.ensureStartedForOwner(store: store);

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    final push = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.merge.name);
    expect(request.payload['mergeMode'], 'preserveConflictingIds');
    expect(push.payload['mergeMode'], 'preserveConflictingIds');

    await service.stop();
  });

  test('pet 配对合并时会透传保留冲突 ID 的合并模式', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.merge);
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    await service.ensureStarted(store: PetNoteStore.seeded());

    final request = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotRequest,
    );
    final push = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(request.payload['dataPolicy'], SyncDataPolicy.merge.name);
    expect(request.payload['mergeMode'], 'preserveConflictingIds');
    expect(push.payload['mergeMode'], 'preserveConflictingIds');

    await service.stop();
  });

  test('owner 收到当前设备被移除配置时清除本地配对与安全密钥', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.householdId, isNull);
    expect(settings.householdAuthToken, isNull);
    expect(await secretStore.loadSharedKey(), isNull);

    await service.stop();
  });

  test('pet 收到主人端移除配置时清除本地配对与安全密钥', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.householdId, isNull);
    expect(settings.householdAuthToken, isNull);
    expect(await secretStore.loadSharedKey(), isNull);
    expect(service.isActive, isFalse);

    await service.stop();
  });

  test('owner 收到当前设备被移除配置时停止服务并取消重连 hello', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final helloCountAfterRemove = transport.sent
        .where((message) => message.type == SyncMessageTypes.hello)
        .length;
    transport.setState(SyncConnectionState.disconnected);
    transport.setState(SyncConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    expect(service.isActive, isFalse);
    expect(transport.connected, isFalse);
    expect(
      transport.sent.where((message) => message.type == SyncMessageTypes.hello),
      hasLength(helloCountAfterRemove),
    );

    await service.stop();
  });

  test('连接恢复后重新发送 hello 并主动请求同步', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    final initialHelloCount = transport.sent
        .where((message) => message.type == SyncMessageTypes.hello)
        .length;

    transport.setState(SyncConnectionState.disconnected);
    transport.setState(SyncConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    expect(initialHelloCount, 1);
    expect(
      transport.sent.where((message) => message.type == SyncMessageTypes.hello),
      hasLength(2),
    );
    expect(
      transport.sent
          .skipWhile((message) => message.type != SyncMessageTypes.hello)
          .skip(1)
          .map((message) => message.type),
      contains(SyncMessageTypes.snapshotRequest),
    );

    await service.stop();
  });

  test('重连时 hello 先于断线期间排队的业务消息发出', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setDeviceName('主人手机');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = QueuedFakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    final store = PetNoteStore.seeded();

    await service.ensureStarted(store: store);
    transport.sent.clear();
    transport.setDisconnected();
    await store.addTodo(
      petId: store.pets.first.id,
      title: '断线期间新增',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    await service.ownerEngine!.pushSnapshotNow();

    transport.reconnectAndFlushQueue();
    await Future<void>.delayed(Duration.zero);

    expect(transport.sent.map((message) => message.type).take(2), [
      SyncMessageTypes.hello,
      SyncMessageTypes.snapshotPush,
    ]);
    expect(
      transport.sent.map((message) => message.type),
      contains(SyncMessageTypes.snapshotRequest),
    );

    await service.stop();
  });

  test('官方模式启动同步前解析服务器地址', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    String? resolvedUrl;
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      officialServerResolver: OfficialSyncServerResolver(
        fetcher: (_) async => '{"server_domain":"petnote.juren233.top"}',
      ),
      transportFactory: (url) {
        resolvedUrl = url;
        return transport;
      },
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(resolvedUrl, 'wss://petnote.juren233.top/ws');
    expect(settings.syncServerUrl, 'wss://petnote.juren233.top/ws');
    expect(service.isActive, isTrue);

    await service.stop();
  });

  test('旧配对缺认证 token 时启动同步并从 hello_ack 补回 token', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());

    expect(service.isActive, isTrue);
    final hello = transport.sent.firstWhere(
      (message) => message.type == SyncMessageTypes.hello,
    );
    expect(hello.payload.containsKey('authToken'), isFalse);

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.helloAck, {
        'snapshotVersion': 0,
        'authToken': 'restored-auth-token',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(settings.householdAuthToken, 'restored-auth-token');

    transport.setState(SyncConnectionState.disconnected);
    transport.setState(SyncConnectionState.connected);
    final reconnectedHello = transport.sent.lastWhere(
      (message) => message.type == SyncMessageTypes.hello,
    );
    expect(reconnectedHello.payload['authToken'], 'restored-auth-token');

    await service.stop();
  });

  test('同步握手认证失败时停止服务并暴露失败状态', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('stale-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.pairError, {
        'message': 'auth failed',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.isActive, isFalse);
    expect(service.failedSyncCount?.value, 1);
  });

  test('同步握手家庭不存在时停止服务并暴露失败状态', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.pairError, {
        'message': 'unknown household',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.isActive, isFalse);
    expect(service.failedSyncCount?.value, 1);
  });

  test('同步握手导入新服务器家庭组后推送本机权威快照', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(
      store: PetNoteStore.seeded(),
      pushStartupSnapshot: false,
    );
    transport.sent.clear();
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.helloAck, {
        'snapshotVersion': 0,
        'restoredHousehold': true,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final snapshotPush = transport.sent.firstWhere(
      (message) => message.type == SyncMessageTypes.snapshotPush,
    );
    expect(snapshotPush.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    expect(settings.pendingResetSnapshotSyncId, isNotNull);

    await service.stop();
  });

  test('清除配对后不保留旧握手失败状态', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('stale-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    await service.ensureStarted(store: PetNoteStore.seeded());
    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.pairError, {
        'message': 'auth failed',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.failedSyncCount?.value, 1);

    await settings.clearSyncPairing();

    expect(service.failedSyncCount?.value, 0);
  });

  testWidgets('同步失败胶囊在 owner engine 首次创建后订阅失败数', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    final secretStore = InMemorySyncSecretStore();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await secretStore.saveSharedKey(await crypto.exportKeyBase64());
    final transport = FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );
    addTearDown(() async {
      await service.stop();
      SyncService.instance = null;
    });
    SyncService.instance = service;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncFailureChip(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sync_failure_chip')), findsNothing);

    await service.ensureStartedForOwner(store: PetNoteStore.seeded());
    await tester.pump();
    transport.setState(SyncConnectionState.disconnected);
    service.ownerEngine?.requestSnapshot();
    await tester.pump();

    expect(find.byKey(const ValueKey('sync_failure_chip')), findsOneWidget);
  });
}

class FakeSyncTransport implements SyncTransport {
  final List<SyncMessage> sent = <SyncMessage>[];
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();
  var connected = false;

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
    connected = true;
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) => sent.add(message);

  void setState(SyncConnectionState value) {
    _state.value = value;
  }
}

class QueuedFakeSyncTransport implements SyncTransport {
  final List<SyncMessage> sent = <SyncMessage>[];
  final List<SyncMessage> queued = <SyncMessage>[];
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();
  var connected = false;

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
    reconnectAndFlushQueue();
  }

  @override
  Future<void> disconnect() async {
    setDisconnected();
  }

  @override
  void send(SyncMessage message) {
    if (connected) {
      sent.add(message);
      return;
    }
    queued.add(message);
  }

  void setDisconnected() {
    connected = false;
    _state.value = SyncConnectionState.disconnected;
  }

  void reconnectAndFlushQueue() {
    connected = true;
    _state.value = SyncConnectionState.connected;
    sent.addAll(queued);
    queued.clear();
  }
}

class _ToggleableSyncSecretStore implements SyncSecretStore {
  _ToggleableSyncSecretStore(this._sharedKey);

  String? _sharedKey;
  bool shouldThrowOnLoad = false;

  @override
  Future<void> deleteSharedKey() async {
    _sharedKey = null;
  }

  @override
  Future<String?> loadSharedKey() async {
    if (shouldThrowOnLoad) {
      throw const SyncSecretStoreException('secure storage unavailable');
    }
    return _sharedKey;
  }

  @override
  Future<void> saveSharedKey(String keyBase64) async {
    _sharedKey = keyBase64;
  }
}
