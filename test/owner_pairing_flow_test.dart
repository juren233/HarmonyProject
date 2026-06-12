import 'dart:async';

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

  test('已有家庭组但无宠物端时仍可向服务端请求配对码', () async {
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
        'code': '123456',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-1',
        'hasPetDevice': false,
      }),
    );

    final session = await future;

    expect(session.code, '123456');
    expect(
      transport.sent
          .singleWhere((message) => message.type == SyncMessageTypes.pairCreate)
          .payload['householdId'],
      'house-1',
    );
    expect(
      transport.sent
          .singleWhere((message) => message.type == SyncMessageTypes.pairCreate)
          .payload['authToken'],
      isNull,
    );
    expect(settings.householdAuthToken, 'auth-token-1');
    expect(await secretStore.loadSharedKey(), 'existing-key');

    await flow.dispose();
  });

  test('服务端报告已有宠物端时阻止继续生成配对码', () async {
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
        'code': '123456',
        'saltBase64': SyncCrypto.generateSaltBase64(),
        'authToken': 'auth-token-1',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'householdId': 'house-1',
        'hasPetDevice': true,
      }),
    );

    await expectLater(
      future,
      throwsA(
        isA<PairingException>().having(
          (error) => error.message,
          'message',
          '请先解绑现有宠物端设备',
        ),
      ),
    );

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
        'code': '123456',
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
}

class FakePairingTransport implements SyncTransport {
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
