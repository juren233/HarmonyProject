import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_pairing_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
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

  testWidgets('配对页提交服务器地址、配对码与设备名', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakePairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetPairingPage(
          settingsController: settings,
          pairingFlow: flow,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pairing_server_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('pairing_code_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('pairing_submit_button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('pairing_code_field')),
      '1234',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.tap(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.pump();
    expect(find.text('合并数据'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pairing_policy_confirm')));
    await tester.pump();

    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.code, '1234');
    expect(flow.deviceName, '客厅的小屏幕');
    expect(flow.dataPolicy, SyncDataPolicy.merge);
  });

  testWidgets('配对页官方服务器解析后提交配对', (tester) async {
    final settings = await AppSettingsController.load();
    final flow = _FakePairingFlow(settings);
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => '{"server_url":"https://petnote.juren233.top"}',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetPairingPage(
          settingsController: settings,
          pairingFlow: flow,
          officialServerResolver: resolver,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pairing_server_field')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('pairing_code_field')),
      '1234',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.tap(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pairing_policy_confirm')));
    await tester.pump();

    expect(settings.syncServerMode, SyncServerMode.official);
    expect(settings.syncServerUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
  });

  testWidgets('切回主人模式会更新设备角色', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetPairingPage(settingsController: settings),
      ),
    );

    await tester.ensureVisible(find.text('切回主人模式'));
    await tester.tap(find.text('切回主人模式'));
    await tester.pump();

    expect(settings.deviceRole, DeviceRole.owner);
  });

  testWidgets('数据同步弹窗失效后不会继续配对', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakePairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetPairingPage(
          settingsController: settings,
          pairingFlow: flow,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('pairing_code_field')),
      '1234',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.tap(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.pump();
    expect(find.text('数据同步'), findsOneWidget);

    await tester.ensureVisible(find.text('切回主人模式'));
    await settings.setDeviceRole(DeviceRole.owner);
    await tester.tap(find.byKey(const ValueKey('pairing_policy_confirm')));
    await tester.pump();

    expect(flow.serverUrl, isNull);
    expect(flow.code, isNull);
    expect(flow.dataPolicy, isNull);
  });

  test('配对提交保留当前设备角色并发送 4 位配对码', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    final transport = _FakePairingTransport();
    final flow = PairingFlow(
      settingsController: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => transport,
    );

    final future = flow.joinAsPet(
      serverUrl: 'ws://127.0.0.1/ws',
      code: '1234',
      deviceName: '我的手机',
    );
    await Future<void>.delayed(Duration.zero);

    final sent = transport.sent.single;
    expect(sent.payload['code'], '1234');
    expect(sent.payload['role'], 'owner');
    expect(sent.payload['dataPolicy'], SyncDataPolicy.merge.name);

    transport.incoming.add(SyncMessage(SyncMessageTypes.pairJoined, {
      'householdId': 'house-1',
      'saltBase64': SyncCrypto.generateSaltBase64(),
      'authToken': 'auth-token-1',
    }));
    await future;

    expect(settings.deviceRole, DeviceRole.owner);
  });
}

class _FakePairingFlow extends PairingFlow {
  _FakePairingFlow(AppSettingsController settingsController)
      : super(
          settingsController: settingsController,
          transportFactory: (_) => throw StateError('测试不应建立真实同步连接'),
        );

  String? serverUrl;
  String? code;
  String? deviceName;
  SyncDataPolicy? dataPolicy;

  @override
  Future<void> joinAsPet({
    required String serverUrl,
    required String code,
    required String deviceName,
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) async {
    this.serverUrl = serverUrl;
    this.code = code;
    this.deviceName = deviceName;
    this.dataPolicy = dataPolicy;
  }
}

class _FakePairingTransport implements SyncTransport {
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
