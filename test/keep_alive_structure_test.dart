import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android 保活通道与前台服务就位', () {
    final bridge = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteKeepAliveBridge.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/KeepAliveService.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(bridge, contains('const val CHANNEL_NAME = "petnote/keep_alive"'));
    expect(bridge, contains('WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON'));
    expect(bridge, contains('startForegroundService(intent)'));
    expect(service, contains('startForeground(NOTIFICATION_ID'));
    expect(service, contains('petnote_keep_alive'));
    expect(activity, contains('PetNoteKeepAliveBridge('));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
        manifest, contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'));
    expect(manifest, contains('android:name=".KeepAliveService"'));
    expect(manifest, contains('android:foregroundServiceType="dataSync"'));
  });

  test('ios 保活通道就位', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(
        source, contains('PetNoteKeepAlivePlugin.register(with: registrar)'));
    expect(source, contains('static let channelName = "petnote/keep_alive"'));
    expect(
        source, contains('UIApplication.shared.isIdleTimerDisabled = enabled'));
    expect(
        source,
        contains(
            'case "startBackgroundKeepAlive", "stopBackgroundKeepAlive":'));
  });

  test('ohos 保活插件与权限就位', () {
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/KeepAlivePlugin.ets',
    ).readAsStringSync();
    final registrant = File(
      'ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets',
    ).readAsStringSync();
    final moduleJson =
        File('ohos/entry/src/main/module.json5').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(plugin, contains("const CHANNEL_NAME = 'petnote/keep_alive'"));
    expect(plugin, contains('setWindowKeepScreenOn(enabled)'));
    expect(plugin, contains('backgroundTaskManager.startBackgroundRunning'));
    expect(
        plugin, contains('backgroundTaskManager.BackgroundMode.DATA_TRANSFER'));
    expect(plugin, contains('backgroundTaskManager.stopBackgroundRunning'));
    expect(registrant,
        contains("import KeepAlivePlugin from './KeepAlivePlugin'"));
    expect(registrant,
        contains('flutterEngine.getPlugins()?.add(new KeepAlivePlugin())'));
    expect(moduleJson, contains('ohos.permission.KEEP_BACKGROUND_RUNNING'));
    expect(moduleJson, contains('"backgroundModes": ['));
    expect(moduleJson, contains('"dataTransfer"'));
    expect(gitignore,
        contains('!ohos/entry/src/main/ets/plugins/KeepAlivePlugin.ets'));
  });
}
