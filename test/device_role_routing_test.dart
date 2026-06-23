import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('settings load 接收真实本地数据标记后解析为 owner', () async {
    final controller = await AppSettingsController.load(
      hasExistingLocalData: true,
    );

    expect(controller.deviceRole, DeviceRole.owner);
  });

  test('PetNoteApp 启动时用 store 真值判断老用户角色', () {
    final source = File('lib/app/petnote_app.dart').readAsStringSync();

    expect(
      source,
      contains('final storeFuture = _loadStore();'),
    );
    expect(
        source, contains('hasExistingLocalData: _hasExistingLocalData(store)'));
    expect(source, contains('settingsController.deviceRole == DeviceRole.pet'));
    expect(source, contains('PetDeviceHome('));
  });

  test('PetNoteRoot 应用级入口启动多设备同步服务', () {
    final source = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source, contains('SyncService.instance ??='));
    expect(source, contains('ensureStarted(store: store)'));
    expect(source, isNot(contains('ensureStartedForOwner(store: store)')));
  });
}
