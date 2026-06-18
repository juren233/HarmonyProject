import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/devices_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/owner_pairing_flow.dart';
import 'package:petnote/sync/pairing_flow.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncService.instance = null;
  });

  tearDown(() async {
    await SyncService.instance?.stop();
    SyncService.instance = null;
  });

  testWidgets('设备页保存服务器地址并展示配对码倒计时', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    final flow = _FakeOwnerPairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          ownerPairingFlow: flow,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('devices_server_field')),
      'petnote.juren233.top',
    );
    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    expect(settings.syncServerUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
    expect(find.text('1234'), findsOneWidget);
    expect(find.textContaining('秒后失效'), findsOneWidget);
  });

  testWidgets('设备页官方服务器解析后生成配对码', (tester) async {
    final settings = await AppSettingsController.load();
    final flow = _FakeOwnerPairingFlow(settings);
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => '{"server_domain":"petnote.juren233.top"}',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          ownerPairingFlow: flow,
          officialServerResolver: resolver,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('devices_server_mode_control')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('devices_server_field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    expect(settings.syncServerMode, SyncServerMode.official);
    expect(settings.syncServerUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets('Settings 通知重建根 App 时保留设备页路由', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakeOwnerPairingFlow(settings, persistPairing: true);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      _SettingsAwareShell(
        settingsController: settings,
        navigatorKey: navigatorKey,
      ),
    );
    await tester.pump();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DevicesPage(
          settingsController: settings,
          ownerPairingFlow: flow,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(DevicesPage), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(settings.householdId, 'house-1');
  });

  testWidgets('配对成功回调只关闭配对码弹窗而不退出设备页', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakeOwnerPairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => DevicesPage(
              settingsController: settings,
              ownerPairingFlow: flow,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    expect(find.text('1234'), findsOneWidget);

    flow.joinPeer('pet-1', '客厅平板');
    await tester.pump();

    expect(find.byType(DevicesPage), findsOneWidget);
    expect(find.text('1234'), findsNothing);
    expect(find.text('客厅平板 已配对 ✓'), findsOneWidget);
  });

  testWidgets('配对成功后按加入端选择保存主人端初始同步策略', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakeOwnerPairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          ownerPairingFlow: flow,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    flow.joinPeer(
      'pet-1',
      '客厅平板',
      dataPolicy: SyncDataPolicy.remoteWins,
    );
    await tester.pump();

    expect(settings.pendingInitialSyncPolicy, SyncDataPolicy.localWins);
  });

  testWidgets('主人端重绑收到宠物端加入后重启同步服务使用新配对配置', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('old-house');
    await settings.setHouseholdAuthToken('old-auth-token');
    final secretStore = InMemorySyncSecretStore();
    final oldCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '1234',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final oldSharedKey = await oldCrypto.exportKeyBase64();
    await secretStore.saveSharedKey(oldSharedKey);
    final newCrypto = await SyncCrypto.deriveFromPairingCode(
      code: '5678',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final newSharedKey = await newCrypto.exportKeyBase64();
    final transports = <_FakeSyncTransport>[];
    final service = SyncService(
      settings: settings,
      secretStore: secretStore,
      transportFactory: (_) {
        final transport = _FakeSyncTransport();
        transports.add(transport);
        return transport;
      },
    );
    SyncService.instance = service;
    final store = PetNoteStore.seeded();
    await service.ensureStarted(store: store);

    await settings.saveSyncPairing(
      serverUrl: 'ws://127.0.0.1/ws',
      householdId: 'new-house',
      sharedKeyBase64: newSharedKey,
      householdAuthToken: 'new-auth-token',
      deviceName: '主人手机',
    );
    await secretStore.saveSharedKey(newSharedKey);
    final flow = _FakeOwnerPairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          store: store,
          ownerPairingFlow: flow,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    flow.joinPeer(
      'pet-1',
      '客厅平板',
      dataPolicy: SyncDataPolicy.remoteWins,
    );
    await tester.pump();

    expect(settings.pendingInitialSyncPolicy, isNull);
    expect(transports, hasLength(2));
    expect(transports.first.connected, isFalse);
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
  });

  testWidgets('配对码过期后关闭弹窗并需要重新生成', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    var now = DateTime(2026, 1, 1, 10);
    final flow = _FakeOwnerPairingFlow(
      settings,
      expiresAfter: const Duration(milliseconds: 50),
      now: () => now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          ownerPairingFlow: flow,
          now: () => now,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('devices_generate_code')));
    await tester.pump();
    await tester.pump();

    expect(find.text('1234'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1234'), findsNothing);
    expect(find.byKey(const ValueKey('devices_generate_code')), findsOneWidget);
  });

  testWidgets('设备列表提供宠物名、重命名和解绑动作', (tester) async {
    final settings = await AppSettingsController.load();
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          store: store,
          initialDevices: [
            SyncedDeviceInfo(
              deviceId: 'pet-device',
              name: '客厅平板',
              role: 'pet',
              servedPetId: pet.id,
              online: true,
            ),
          ],
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('device_item_pet-device')), findsOneWidget);
    expect(find.textContaining(pet.name), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('解绑'), findsOneWidget);
    expect(find.text('更换服务宠物'), findsNothing);
  });

  testWidgets('已配对设备列表顶部展示输入配对码入口', (tester) async {
    final settings = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          initialDevices: [
            SyncedDeviceInfo(
              deviceId: 'pet-device',
              name: '客厅平板',
              role: 'pet',
              online: true,
            ),
          ],
        ),
      ),
    );

    final entryFinder = find.byKey(const ValueKey('devices_join_code_entry'));
    final deviceFinder = find.byKey(const ValueKey('device_item_pet-device'));

    expect(entryFinder, findsOneWidget);
    expect(deviceFinder, findsOneWidget);
    expect(
      tester.getTopLeft(entryFinder).dy,
      lessThan(tester.getTopLeft(deviceFinder).dy),
    );
  });

  testWidgets('主人端可通过已配对列表入口输入配对码', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setDeviceName('我的手机');
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');
    final flow = _FakePairingFlow(settings);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          pairingFlow: flow,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('devices_join_code_entry')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('devices_join_code_field')),
      '4321',
    );
    await tester.tap(find.byKey(const ValueKey('devices_join_policy_remote')));
    await tester.tap(find.byKey(const ValueKey('devices_join_submit')));
    await tester.pump();

    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.code, '4321');
    expect(flow.deviceName, '我的手机');
    expect(flow.dataPolicy, SyncDataPolicy.remoteWins);
    expect(settings.deviceRole, DeviceRole.owner);
  });

  testWidgets('设备列表不展示当前设备', (tester) async {
    final settings = await AppSettingsController.load();
    final currentDeviceId = await settings.ensureDeviceId();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DevicesPage(
          settingsController: settings,
          initialDevices: [
            SyncedDeviceInfo(
              deviceId: currentDeviceId,
              name: '本机',
              role: 'owner',
              online: true,
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(ValueKey('device_item_$currentDeviceId')), findsNothing);
    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.text('未配对'), findsOneWidget);
  });
}

class _SettingsAwareShell extends StatelessWidget {
  const _SettingsAwareShell({
    required this.settingsController,
    required this.navigatorKey,
  });

  final AppSettingsController settingsController;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: buildPetNoteTheme(Brightness.light),
          home: const Scaffold(body: SizedBox.shrink()),
        );
      },
    );
  }
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

class _FakeOwnerPairingFlow extends OwnerPairingFlow {
  _FakeOwnerPairingFlow(
    AppSettingsController settingsController, {
    this.expiresAfter = const Duration(minutes: 5),
    this.persistPairing = false,
    DateTime Function()? now,
  })  : now = now ?? DateTime.now,
        super(
          settingsController: settingsController,
          transportFactory: (_) => throw StateError('测试不应建立真实同步连接'),
        );

  final Duration expiresAfter;
  final bool persistPairing;
  final DateTime Function() now;
  String? serverUrl;
  PairingPeerJoined? onPeerJoined;

  @override
  Future<OwnerPairingSession> createAsOwner({
    required String serverUrl,
    required String deviceName,
    PairingPeerJoined? onPeerJoined,
  }) async {
    this.serverUrl = serverUrl;
    this.onPeerJoined = onPeerJoined;
    if (persistPairing) {
      await settingsController.saveSyncPairing(
        serverUrl: serverUrl,
        householdId: 'house-1',
        sharedKeyBase64: 'shared-key-1',
        householdAuthToken: 'auth-token-1',
        deviceName: deviceName,
      );
    }
    return OwnerPairingSession(
      code: '1234',
      expiresAtMs: now().add(expiresAfter).millisecondsSinceEpoch,
      householdId: 'house-1',
    );
  }

  void joinPeer(
    String deviceId,
    String deviceName, {
    SyncDataPolicy dataPolicy = SyncDataPolicy.merge,
  }) {
    onPeerJoined?.call(deviceId, deviceName, dataPolicy);
  }
}

class _FakeSyncTransport implements SyncTransport {
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
}
