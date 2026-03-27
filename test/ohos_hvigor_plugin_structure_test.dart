import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS hvigor plugin is owned by this repo and guards missing ohos plugin lists', () {
    final hvigorFile = File('ohos/hvigorfile.ts').readAsStringSync();
    final hvigorConfig = File('ohos/hvigorconfig.ts').readAsStringSync();
    final ownedPlugin = File(
      'tooling/ohos-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts',
    ).readAsStringSync();

    expect(
      hvigorFile.contains("../tooling/ohos-hvigor-plugin"),
      isTrue,
    );
    expect(
      hvigorConfig.contains("../tooling/ohos-hvigor-plugin"),
      isTrue,
    );
    expect(
      hvigorFile.contains('flutter-hvigor-plugin'),
      isTrue,
    );
    expect(
      hvigorConfig.contains('flutter-hvigor-plugin'),
      isTrue,
    );

    expect(
      ownedPlugin.contains('pluginsByPlatform'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('Array.isArray(pluginsByPlatform.ohos)'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('ohosPlugins.filter(plugin => plugin.native_build !== false)'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('function ensureFlutterPackages('),
      isTrue,
    );
    expect(
      ownedPlugin.contains('Refresh Flutter package config for OHOS IDE run start'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('function backupManagedFlutterState('),
      isTrue,
    );
    expect(
      ownedPlugin.contains('function restoreManagedFlutterState('),
      isTrue,
    );
    expect(
      ownedPlugin.contains("console.info('Backup Flutter shared state start')"),
      isTrue,
    );
    expect(
      ownedPlugin.contains("console.info('Switch to OHOS Flutter state start')"),
      isTrue,
    );
    expect(
      ownedPlugin.contains("console.info('Restore Flutter shared state start')"),
      isTrue,
    );
    expect(
      ownedPlugin.contains("restoreNamedFlutterState(flutterProjectPath, 'ohos')"),
      isTrue,
    );
    expect(
      ownedPlugin.contains('restoreManagedFlutterState(flutterProjectPath, sessionStateBackupRoot)'),
      isTrue,
    );
  });

  test('OHOS tracked hvigor entrypoints import the repo-owned plugin copy', () {
    final hvigorFile = File('ohos/hvigorfile.ts').readAsStringSync();
    final hvigorConfig = File('ohos/hvigorconfig.ts').readAsStringSync();

    expect(hvigorFile.contains("../tooling/ohos-hvigor-plugin"), isTrue);
    expect(hvigorConfig.contains("../tooling/ohos-hvigor-plugin"), isTrue);
  });

  test('OHOS hvigor patch includes automatic backup and restore hooks', () {
    final patch = File(
      'tooling/ohos-flutter/flutter-hvigor-plugin.patch',
    ).readAsStringSync();

    expect(patch.contains('function backupManagedFlutterState('), isTrue);
    expect(patch.contains('function restoreManagedFlutterState('), isTrue);
    expect(patch.contains("console.info('Backup Flutter shared state start')"), isTrue);
    expect(patch.contains("console.info('Switch to OHOS Flutter state start')"), isTrue);
    expect(patch.contains("console.info('Restore Flutter shared state start')"), isTrue);
  });

  test('OHOS helper script patches backup and restore hooks too', () {
    final script = File('scripts/flutter-ohos.ps1').readAsStringSync();

    expect(script.contains("\$backupStateMarker = \"console.info('Backup Flutter shared state start')\""), isTrue);
    expect(script.contains('const sessionStateBackupRoot = switchToOhosFlutterState('), isTrue);
    expect(script.contains('restoreFlutterSharedState(flutterProjectPath, sessionStateBackupRoot)'), isTrue);
  });

  test('README documents the repo-owned OHOS hvigor plugin workflow', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme.contains('tooling/ohos-hvigor-plugin'), isTrue);
    expect(readme.contains('不再直接修改 OHOS Flutter 子模块里的 hvigor 插件源码'), isTrue);
    expect(readme.contains('DevEco Studio 直接运行会使用仓库内自管的 OHOS hvigor 插件副本'), isTrue);
    expect(readme.contains('ohos/hvigorfile.ts'), isTrue);
    expect(readme.contains('ohos/hvigorconfig.ts'), isTrue);
  });
}
