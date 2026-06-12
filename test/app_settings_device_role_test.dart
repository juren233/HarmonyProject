import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('设备角色默认 undecided，可设置并持久化', () async {
    final controller = await AppSettingsController.load();
    expect(controller.deviceRole, DeviceRole.undecided);

    await controller.setDeviceRole(DeviceRole.pet);
    expect(controller.deviceRole, DeviceRole.pet);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.deviceRole, DeviceRole.pet);
  });

  test('老用户无显式角色但已有数据时解析为 owner', () {
    expect(
      AppSettingsController.resolveLoadedDeviceRole(
        storedRoleName: null,
        hasExistingData: true,
      ),
      DeviceRole.owner,
    );
    expect(
      AppSettingsController.resolveLoadedDeviceRole(
        storedRoleName: null,
        hasExistingData: false,
      ),
      DeviceRole.undecided,
    );
  });

  test('同步配置字段可独立持久化并清除配对', () async {
    final controller = await AppSettingsController.load();

    await controller.setSyncServerMode(SyncServerMode.custom);
    await controller.setSyncServerUrl('wss://example.com/ws');
    await controller.setHouseholdId('house-1');
    await controller.setDeviceName('客厅平板');
    await controller.setSharedKeyBase64('shared-key');
    await controller.setHouseholdAuthToken('auth-token-1');
    await controller.setServedPetId('pet-1');
    await controller.setPetKeepScreenOn(false);

    final deviceId = await controller.ensureDeviceId();
    expect(deviceId, isNotEmpty);
    expect(await controller.ensureDeviceId(), deviceId);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.syncServerMode, SyncServerMode.custom);
    expect(reloaded.syncServerUrl, 'wss://example.com/ws');
    expect(reloaded.householdId, 'house-1');
    expect(reloaded.deviceId, deviceId);
    expect(reloaded.deviceName, '客厅平板');
    expect(reloaded.sharedKeyBase64, 'shared-key');
    expect(reloaded.householdAuthToken, 'auth-token-1');
    expect(reloaded.servedPetId, 'pet-1');
    expect(reloaded.petKeepScreenOn, isFalse);

    await reloaded.clearSyncPairing();
    expect(reloaded.syncServerUrl, 'wss://example.com/ws');
    expect(reloaded.householdId, isNull);
    expect(reloaded.servedPetId, isNull);
    expect(reloaded.sharedKeyBase64, isNull);
    expect(reloaded.householdAuthToken, isNull);
  });

  test('同步服务器模式默认官方，老配置保留为自定义', () async {
    final fresh = await AppSettingsController.load();
    expect(fresh.syncServerMode, SyncServerMode.official);

    await fresh.setSyncServerMode(SyncServerMode.custom);
    final customReloaded = await AppSettingsController.load();
    expect(customReloaded.syncServerMode, SyncServerMode.custom);

    SharedPreferences.setMockInitialValues({
      AppSettingsController.syncServerUrlStorageKey: 'wss://legacy.example/ws',
    });
    final legacy = await AppSettingsController.load();
    expect(legacy.syncServerMode, SyncServerMode.custom);
  });
}
