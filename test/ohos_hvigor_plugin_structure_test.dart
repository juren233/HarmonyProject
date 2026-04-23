import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'OHOS hvigor plugin is owned by this repo and guards missing ohos plugin lists',
      () {
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
      ownedPlugin.contains(
          'ohosPlugins.filter(plugin => plugin.native_build !== false)'),
      isTrue,
    );
    expect(
      ownedPlugin.contains('function ensureFlutterPackages('),
      isTrue,
    );
    expect(
      ownedPlugin
          .contains('Refresh Flutter package config for OHOS IDE run start'),
      isTrue,
    );
    expect(
      ownedPlugin.contains(
          'ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)'),
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
      ownedPlugin
          .contains("console.info('Switch to OHOS Flutter state start')"),
      isTrue,
    );
    expect(
      ownedPlugin
          .contains("console.info('Restore Flutter shared state start')"),
      isTrue,
    );
    expect(
      ownedPlugin
          .contains("restoreNamedFlutterState(flutterProjectPath, 'ohos')"),
      isTrue,
    );
    expect(
      ownedPlugin.contains(
          'restoreManagedFlutterState(flutterProjectPath, sessionStateBackupRoot)'),
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
    expect(patch.contains("console.info('Backup Flutter shared state start')"),
        isTrue);
    expect(patch.contains("console.info('Switch to OHOS Flutter state start')"),
        isTrue);
    expect(patch.contains("console.info('Restore Flutter shared state start')"),
        isTrue);
  });

  test('OHOS helper script patches backup and restore hooks too', () {
    final script = File('scripts/flutter-ohos.ps1').readAsStringSync();

    expect(
        script.contains(
            "\$backupStateMarker = \"console.info('Backup Flutter shared state start')\""),
        isTrue);
    expect(
        script.contains(
            'const sessionStateBackupRoot = switchToOhosFlutterState('),
        isTrue);
    expect(
        script.contains(
            'restoreFlutterSharedState(flutterProjectPath, sessionStateBackupRoot)'),
        isTrue);
    expect(
      script.contains(r'if ($content -eq $originalContent) {'),
      isTrue,
    );
  });

  test('OHOS hvigor plugin refreshes stale package_graph snapshots for the current app package', () {
    final ownedPlugin = File(
      'tooling/ohos-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts',
    ).readAsStringSync();

    expect(ownedPlugin.contains('function getFlutterProjectPackageName('), isTrue);
    expect(ownedPlugin.contains("const packageGraphPath = path.join(flutterProjectPath, '.dart_tool', 'package_graph.json')"), isTrue);
    expect(ownedPlugin.contains('const projectPackageName = getFlutterProjectPackageName(flutterProjectPath)'), isTrue);
    expect(ownedPlugin.contains("const packageGraph = JSON.parse(fs.readFileSync(packageGraphPath, 'utf-8'))"), isTrue);
    expect(ownedPlugin.contains('const roots = Array.isArray(packageGraph.roots) ? packageGraph.roots : []'), isTrue);
    expect(ownedPlugin.contains('roots.includes(projectPackageName)'), isTrue);
    expect(ownedPlugin.contains('pkg.name === projectPackageName'), isTrue);
    expect(ownedPlugin.contains('Array.isArray(projectPackage.dependencies)'), isTrue);
  });

  test('OHOS hvigor plugin resolves app version metadata from root pubspec first', () {
    final ownedPlugin = File(
      'tooling/ohos-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts',
    ).readAsStringSync();

    expect(ownedPlugin.contains('function getFlutterProjectVersionInfo('), isTrue);
    expect(ownedPlugin.contains("const pubspecPath = path.join(flutterProjectPath, 'pubspec.yaml')"), isTrue);
    expect(ownedPlugin.contains(r"const versionMatch = pubspecContent.match(/^version:\s*([^\s#]+)\s*$/m)"), isTrue);
    expect(ownedPlugin.contains("const [versionName, buildNumber = '1'] = versionValue.split('+', 2)"), isTrue);
    expect(ownedPlugin.contains('const flutterVersionInfo = getFlutterProjectVersionInfo(flutterProjectPath)'), isTrue);
    expect(ownedPlugin.contains("appJsonOpt['app']['versionCode'] = Number("), isTrue);
    expect(ownedPlugin.contains("flutterVersionInfo.versionCode ?? properties['flutter.versionCode'] ?? 1"), isTrue);
    expect(ownedPlugin.contains("appJsonOpt['app']['versionName'] ="), isTrue);
    expect(ownedPlugin.contains("flutterVersionInfo.versionName ?? properties['flutter.versionName'] ?? '1.0'"), isTrue);
  });


  test('OHOS hvigor plugin clears stale flutter_ohos ArkTS cache when OHPM store path changes', () {
    final ownedPlugin = File(
      'tooling/ohos-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts',
    ).readAsStringSync();
    final helperScript = File('scripts/flutter-ohos.ps1').readAsStringSync();

    expect(ownedPlugin.contains('function getFlutterOhosStorePath('), isTrue);
    expect(ownedPlugin.contains("oh_modules', '.ohpm', 'lock.json5'"), isTrue);
    expect(ownedPlugin.contains("const entryBuildPath = path.join(getOhosRoot(flutterProjectPath), 'entry', 'build')"), isTrue);
    expect(ownedPlugin.contains("fileContent.includes('@ohos/flutter_ohos')"), isTrue);
    expect(ownedPlugin.contains("fileContent.includes('pkg_modules/.ohpm/')"), isTrue);
    expect(ownedPlugin.contains("path.join(entryBuildPath, 'default', 'cache')"), isTrue);
    expect(ownedPlugin.contains("path.join(entryBuildPath, 'default', 'intermediates', 'loader_out')"), isTrue);
    expect(ownedPlugin.contains('clearStaleFlutterOhosArkTsCache(flutterProjectPath, flutterOhosStorePath)'), isTrue);
    expect(helperScript.contains('function getFlutterOhosStorePath('), isTrue);
    expect(helperScript.contains("const entryBuildPath = path.join(getOhosRoot(flutterProjectPath), 'entry', 'build')"), isTrue);
    expect(helperScript.contains("path.join(entryBuildPath, 'default', 'intermediates', 'loader')"), isTrue);
    expect(helperScript.contains("path.join(entryBuildPath, 'default', 'outputs')"), isTrue);
    expect(helperScript.contains('clearStaleFlutterOhosArkTsCache(flutterProjectPath, flutterOhosStorePath)'), isTrue);
  });

  test('OHOS local.properties stays outside shared Flutter state rollback', () {
    final flutterStateScript = File('scripts/flutter-state.ps1').readAsStringSync();
    final ownedPlugin = File(
      'tooling/ohos-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts',
    ).readAsStringSync();
    final helperScript = File('scripts/flutter-ohos.ps1').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(flutterStateScript.contains("'android/local.properties'"), isTrue);
    expect(flutterStateScript.contains("'ohos/local.properties'"), isFalse);
    expect(ownedPlugin.contains("const MANAGED_FLUTTER_STATE_FILES = ["), isTrue);
    expect(ownedPlugin.contains("'android/local.properties'"), isTrue);
    expect(ownedPlugin.contains("'ohos/local.properties'"), isFalse);
    expect(ownedPlugin.contains("const LOCKFILE_HOSTED_URL = 'https://pub.flutter-io.cn'"), isTrue);
    expect(ownedPlugin.contains("normalizePubspecLockHostedUrl(destinationPath)"), isTrue);
    expect(helperScript.contains("const MANAGED_FLUTTER_STATE_FILES = ["), isTrue);
    expect(helperScript.contains("'android/local.properties',"), isTrue);
    expect(helperScript.contains("'ohos/local.properties',"), isFalse);
    expect(helperScript.contains("const LOCKFILE_HOSTED_URL = 'https://pub.flutter-io.cn'"), isTrue);
    expect(helperScript.contains("normalizePubspecLockHostedUrl(destinationPath)"), isTrue);
    expect(flutterStateScript.contains("function Normalize-PubspecLockHostedUrl {"), isTrue);
    expect(flutterStateScript.contains("Normalize-PubspecLockHostedUrl -Path \$DestinationPath"), isTrue);
    expect(readme.contains('ohos/local.properties) 是 Harmony 本地配置，不属于 `official` / `ohos` 共享 Flutter 状态快照'), isTrue);
  });

  test('README documents the repo-owned OHOS hvigor plugin workflow', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme.contains('tooling/ohos-hvigor-plugin'), isTrue);
    expect(readme.contains('不再直接修改 OHOS Flutter 子模块里的 hvigor 插件源码'), isTrue);
    expect(readme.contains('DevEco Studio 直接运行会使用仓库内自管的 OHOS hvigor 插件副本'),
        isTrue);
    expect(readme.contains('ohos/hvigorfile.ts'), isTrue);
    expect(readme.contains('ohos/hvigorconfig.ts'), isTrue);
  });

  test('README documents OHOS version metadata syncing from root pubspec.yaml', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme.contains('Harmony 安装包的版本号和构建号默认跟随根目录'), isTrue);
    expect(readme.contains('DevEco 一键编译 / 运行也会优先读取根目录'), isTrue);
    expect(readme.contains('pubspec.yaml'), isTrue);
    expect(readme.contains('ohos/local.properties'), isTrue);
  });

  test('OHOS registers repo-owned shared preferences plugin for persistence',
      () {
    final registrant = File(
      'ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets',
    ).readAsStringSync();
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/SharedPreferencesPlugin.ets',
    ).readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(
      registrant.contains(
          "import SharedPreferencesPlugin from './SharedPreferencesPlugin';"),
      isTrue,
    );
    expect(
      registrant.contains(
          'flutterEngine.getPlugins()?.add(new SharedPreferencesPlugin());'),
      isTrue,
    );
    expect(
        plugin.contains(
            "const CHANNEL_NAME = 'plugins.flutter.io/shared_preferences';"),
        isTrue);
    expect(
        plugin
            .contains("import dataPreferences from '@ohos.data.preferences';"),
        isTrue);
    expect(plugin.contains("case 'getAll':"), isTrue);
    expect(plugin.contains("case 'setString':"), isTrue);
    expect(plugin.contains("case 'setBool':"), isTrue);
    expect(plugin.contains("case 'setInt':"), isTrue);
    expect(plugin.contains("case 'setDouble':"), isTrue);
    expect(plugin.contains("case 'setStringList':"), isTrue);
    expect(plugin.contains("case 'remove':"), isTrue);
    expect(plugin.contains("case 'clear':"), isTrue);
    expect(plugin.contains("case 'getAllWithParameters':"), isTrue);
    expect(plugin.contains("case 'clearWithParameters':"), isTrue);
    expect(plugin.contains('.flushSync()'), isTrue);
    expect(RegExp(r'const\s+\w+\s*=\s*call\.argument').hasMatch(plugin),
        isFalse);
    expect(
      gitignore.contains(
          '!ohos/entry/src/main/ets/plugins/SharedPreferencesPlugin.ets'),
      isTrue,
    );
  });
}
