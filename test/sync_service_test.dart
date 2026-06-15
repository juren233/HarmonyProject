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

  test('owner 收到当前设备被移除配置时清除本地配对', () async {
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
