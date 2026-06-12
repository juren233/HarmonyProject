import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_device_settings_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页可切换常亮、主人端模式与重新配对', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.saveSyncPairing(
      serverUrl: 'ws://127.0.0.1:8080/ws',
      householdId: 'house-1',
      sharedKeyBase64: 'shared-key',
      householdAuthToken: 'auth-token-1',
    );
    final secretStore = InMemorySyncSecretStore();
    await secretStore.saveSharedKey('shared-key');
    bool? keepScreenOn;
    var repairCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetDeviceSettingsPage(
          settingsController: settings,
          keepScreenOn: true,
          onKeepScreenOnChanged: (value) => keepScreenOn = value,
          onRepair: () => repairCalled = true,
          secretStore: secretStore,
        ),
      ),
    );

    final keepScreenTile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings_keep_screen_on')),
    );
    keepScreenTile.onChanged?.call(false);
    await tester.pump();
    expect(keepScreenOn, isFalse);

    await tester
        .ensureVisible(find.byKey(const ValueKey('settings_mode_owner')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_mode_owner')));
    await tester.pump();
    await tester.tap(find.text('确认切换'));
    await tester.pump();
    expect(settings.deviceRole, DeviceRole.owner);

    await settings.setDeviceRole(DeviceRole.pet);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_repair')),
      160,
    );
    await tester.tap(find.byKey(const ValueKey('settings_repair')));
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pump();

    expect(settings.householdId, isNull);
    expect(await secretStore.loadSharedKey(), isNull);
    expect(repairCalled, isTrue);
  });
}
