import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_pairing_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/pairing_flow.dart';
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
      '123456',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.tap(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.pump();

    expect(flow.serverUrl, 'wss://petnote.juren233.top/ws');
    expect(flow.code, '123456');
    expect(flow.deviceName, '客厅的小屏幕');
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
      '123456',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('pairing_submit_button')));
    await tester.tap(find.byKey(const ValueKey('pairing_submit_button')));
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

  @override
  Future<void> joinAsPet({
    required String serverUrl,
    required String code,
    required String deviceName,
  }) async {
    this.serverUrl = serverUrl;
    this.code = code;
    this.deviceName = deviceName;
  }
}
