import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/devices_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/owner_pairing_flow.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.text('123456'), findsOneWidget);
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
    expect(find.text('123456'), findsOneWidget);
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
  });
}

class _FakeOwnerPairingFlow extends OwnerPairingFlow {
  _FakeOwnerPairingFlow(AppSettingsController settingsController)
      : super(
          settingsController: settingsController,
          transportFactory: (_) => throw StateError('测试不应建立真实同步连接'),
        );

  String? serverUrl;

  @override
  Future<OwnerPairingSession> createAsOwner({
    required String serverUrl,
    required String deviceName,
    PairingPeerJoined? onPeerJoined,
  }) async {
    this.serverUrl = serverUrl;
    return OwnerPairingSession(
      code: '123456',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      householdId: 'house-1',
    );
  }
}
