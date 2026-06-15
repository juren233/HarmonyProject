import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/owner_pairing_flow.dart';
import 'package:petnote/sync/pairing_flow.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('已有家庭组但缺少认证 token 时按新家庭组生成配对码', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setSharedKeyBase64('existing-key');
    final transport = FakePairingTransport();
    final secretStore = InMemorySyncSecretStore();
    await secretStore.saveSharedKey('existing-key');
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    final future = flow.createAsOwner(
      serverUrl: 'ws://127.0.0.1/ws',
      deviceName: '主人手机',
    );
    await Future<void>.delayed(Duration.zero);
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.pairCreated, {
        'code': '1234',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-2',
        'hasPetDevice': false,
      }),
    );

    final session = await future;

    expect(session.code, '1234');
    expect(
      transport.sent
          .singleWhere((message) => message.type == SyncMessageTypes.pairCreate)
          .payload['householdId'],
      isNull,
    );
    expect(
      transport.sent
          .singleWhere((message) => message.type == SyncMessageTypes.pairCreate)
          .payload['authToken'],
      isNull,
    );
    expect(settings.householdId, 'house-2');
    expect(settings.householdAuthToken, 'auth-token-1');
    expect(await secretStore.loadSharedKey(), isNot('existing-key'));
    expect(settings.sharedKeyBase64, isNot('existing-key'));

    await flow.dispose();
  });

  test('服务端报告已有宠物端时仍允许继续生成配对码', () async {
    final settings = await AppSettingsController.load();
    final transport = FakePairingTransport();
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => transport,
    );

    final future = flow.createAsOwner(
      serverUrl: 'ws://127.0.0.1/ws',
      deviceName: '主人手机',
    );
    await Future<void>.delayed(Duration.zero);
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.pairCreated, {
        'code': '1234',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-1',
        'hasPetDevice': true,
      }),
    );

    final session = await future;

    expect(session.code, '1234');

    await flow.dispose();
  });

  test('已有家庭组重新生成配对码时带上家庭认证 token', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setSharedKeyBase64('existing-key');
    final transport = FakePairingTransport();
    final secretStore = InMemorySyncSecretStore();
    await secretStore.saveSharedKey('existing-key');
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    final future = flow.createAsOwner(
      serverUrl: 'ws://127.0.0.1/ws',
      deviceName: '主人手机',
    );
    await Future<void>.delayed(Duration.zero);
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.pairCreated, {
        'code': '1234',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-1',
        'hasPetDevice': false,
      }),
    );

    await future;

    final pairCreate = transport.sent.singleWhere(
      (message) => message.type == SyncMessageTypes.pairCreate,
    );
    expect(pairCreate.payload['householdId'], 'house-1');
    expect(pairCreate.payload['authToken'], 'auth-token-1');

    await flow.dispose();
  });

  test('旧家庭认证被拒绝时清除配对并重新生成新家庭配对码', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('removed-house');
    await settings.setHouseholdAuthToken('removed-auth-token');
    await settings.setSharedKeyBase64('removed-shared-key');
    final transports = <FakePairingTransport>[];
    final secretStore = InMemorySyncSecretStore();
    await secretStore.saveSharedKey('removed-shared-key');
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = FakePairingTransport();
        transports.add(transport);
        return transport;
      },
    );

    final future = flow.createAsOwner(
      serverUrl: 'ws://127.0.0.1/ws',
      deviceName: '主人手机',
    );
    await Future<void>.delayed(Duration.zero);
    transports.first.incoming.add(
      const SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}),
    );
    await Future<void>.delayed(Duration.zero);
    transports.last.incoming.add(
      SyncMessage(SyncMessageTypes.pairCreated, {
        'code': '5678',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-2',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-2',
        'hasPetDevice': false,
      }),
    );

    final session = await future;

    expect(session.code, '5678');
    expect(transports, hasLength(2));
    expect(
      transports.first.sent.single.payload['householdId'],
      'removed-house',
    );
    expect(transports.last.sent.single.payload['householdId'], isNull);
    expect(transports.last.sent.single.payload['authToken'], isNull);
    expect(settings.householdId, 'house-2');
    expect(settings.householdAuthToken, 'auth-token-2');
    expect(await secretStore.loadSharedKey(), isNot('removed-shared-key'));

    await flow.dispose();
  });

  test('已配对宠物端重新生成配对码时保留当前设备角色', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token-1');
    await settings.setSharedKeyBase64('existing-key');
    final transport = FakePairingTransport();
    final secretStore = InMemorySyncSecretStore();
    await secretStore.saveSharedKey('existing-key');
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: secretStore,
      transportFactory: (_) => transport,
    );

    final future = flow.createAsOwner(
      serverUrl: 'ws://127.0.0.1/ws',
      deviceName: '客厅平板',
    );
    await Future<void>.delayed(Duration.zero);

    final pairCreate = transport.sent.singleWhere(
      (message) => message.type == SyncMessageTypes.pairCreate,
    );
    expect(pairCreate.payload['role'], 'pet');

    transport.incoming.add(
      SyncMessage(SyncMessageTypes.pairCreated, {
        'code': '5678',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-1',
        'hasPetDevice': true,
      }),
    );
    await future;

    expect(settings.deviceRole, DeviceRole.pet);

    await flow.dispose();
  });

  test('同步服务器握手失败时转换为配对错误并断开连接', () async {
    final settings = await AppSettingsController.load();
    final transport = FakePairingTransport(
      connectError: const HandshakeException('Connection terminated'),
    );
    final flow = OwnerPairingFlow(
      settingsController: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => transport,
    );

    await expectLater(
      flow.createAsOwner(
        serverUrl: 'wss://petnote.juren233.top/ws',
        deviceName: '主人手机',
      ),
      throwsA(
        isA<PairingException>().having(
          (error) => error.message,
          'message',
          '无法连接同步服务器，请检查网络或服务器地址',
        ),
      ),
    );

    expect(transport.disconnected, isTrue);
    expect(transport.sent, isEmpty);
  });
}

class FakePairingTransport implements SyncTransport {
  FakePairingTransport({this.connectError});

  final Object? connectError;
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
  bool disconnected = false;

  @override
  Future<void> connect() async {
    final error = connectError;
    if (error != null) {
      throw error;
    }
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) => sent.add(message);
}
