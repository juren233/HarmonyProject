import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/devices_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('主人端配对时保存宠物端策略的反转版本', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);

    final petPolicy = SyncDataPolicy.remoteWins;

    await settings.setPendingInitialSyncPolicy(
      ownerInitialPolicyForPeerSelection(petPolicy),
    );

    expect(settings.pendingInitialSyncPolicy, SyncDataPolicy.localWins);
  });

  test('宠物端选择 localWins 时主人端保存 remoteWins', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);

    final petPolicy = SyncDataPolicy.localWins;

    await settings.setPendingInitialSyncPolicy(
      ownerInitialPolicyForPeerSelection(petPolicy),
    );

    expect(settings.pendingInitialSyncPolicy, SyncDataPolicy.remoteWins);
  });

  test('宠物端选择 merge 时主人端也保存 merge', () async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);

    final petPolicy = SyncDataPolicy.merge;

    await settings.setPendingInitialSyncPolicy(
      ownerInitialPolicyForPeerSelection(petPolicy),
    );

    expect(settings.pendingInitialSyncPolicy, SyncDataPolicy.merge);
  });

  test('setPendingInitialSyncPolicy 会触发 notifyListeners', () async {
    final settings = await AppSettingsController.load();
    var listenerCalled = false;

    settings.addListener(() {
      listenerCalled = true;
    });

    await settings.setPendingInitialSyncPolicy(SyncDataPolicy.remoteWins);

    expect(listenerCalled, isTrue);
  });
}
