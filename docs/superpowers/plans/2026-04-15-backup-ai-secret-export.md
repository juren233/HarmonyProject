# Backup AI Secret Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为完整备份增加“可选导出 API Key”能力，并在导出与导入恢复时都加入明确的二次确认。

**Architecture:** 在 `PetNoteDataPackage` 上新增可选 `sensitiveSettings` 载荷，默认不写入。`DataStorageCoordinator` 接入 `AiSecretStore`，按导出/导入选项读写敏感字段；页面层新增导出确认对话框和导入敏感恢复确认流程，确保普通数据恢复与 API Key 覆盖是两个独立动作。

**Tech Stack:** Flutter, Dart, flutter_test, SharedPreferences mock, 现有 `AiSecretStore` 抽象

---

## File Map

- Modify: `lib/data/data_storage_models.dart`
- Modify: `lib/data/data_storage_coordinator.dart`
- Modify: `lib/app/data_storage_page.dart`
- Modify: `test/data_storage_coordinator_test.dart`
- Modify: `test/data_storage_widget_test.dart`

### Task 1: 扩展备份数据模型以容纳敏感设置

**Files:**
- Modify: `lib/data/data_storage_models.dart`
- Test: `test/data_storage_coordinator_test.dart`

- [ ] **Step 1: 先写失败测试，约束敏感字段的 JSON 编解码**

```dart
test('backup package encodes and decodes optional sensitive settings', () {
  final package = PetNoteDataPackage(
    schemaVersion: PetNoteDataPackage.currentSchemaVersion,
    packageType: PetNoteDataPackageType.backup,
    packageName: '敏感备份',
    description: '包含 API Key',
    createdAt: DateTime.parse('2026-04-15T10:00:00+08:00'),
    appVersion: '1.0.0-test',
    data: const PetNoteDataState(
      pets: <Pet>[],
      todos: <TodoItem>[],
      reminders: <ReminderItem>[],
      records: <PetRecord>[],
    ),
    settings: const PetNoteSettingsState(
      themePreferenceName: 'system',
      aiProviderConfigs: <AiProviderConfig>[],
      activeAiProviderConfigId: null,
    ),
    sensitiveSettings: const PetNoteSensitiveSettingsState(
      aiSecrets: <PetNoteAiSecretSnapshot>[
        PetNoteAiSecretSnapshot(configId: 'cfg-openai', apiKey: 'sk-test-123'),
      ],
    ),
    meta: const <String, Object?>{},
  );

  final decoded = PetNoteDataPackage.fromJson(package.toJson());

  expect(decoded.sensitiveSettings, isNotNull);
  expect(decoded.sensitiveSettings!.aiSecrets.single.configId, 'cfg-openai');
  expect(decoded.sensitiveSettings!.aiSecrets.single.apiKey, 'sk-test-123');
});
```

- [ ] **Step 2: 运行单测，确认它因模型缺失而失败**

Run: `flutter test test/data_storage_coordinator_test.dart`

Expected: FAIL，提示 `sensitiveSettings` / `PetNoteSensitiveSettingsState` / `PetNoteAiSecretSnapshot` 未定义或构造参数不存在。

- [ ] **Step 3: 在数据模型中补最小实现**

```dart
class PetNoteAiSecretSnapshot {
  const PetNoteAiSecretSnapshot({
    required this.configId,
    required this.apiKey,
  });

  final String configId;
  final String apiKey;

  Map<String, dynamic> toJson() {
    return {
      'configId': configId,
      'apiKey': apiKey,
    };
  }

  factory PetNoteAiSecretSnapshot.fromJson(Map<String, dynamic> json) {
    return PetNoteAiSecretSnapshot(
      configId: json['configId'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
    );
  }
}

class PetNoteSensitiveSettingsState {
  const PetNoteSensitiveSettingsState({
    required this.aiSecrets,
  });

  final List<PetNoteAiSecretSnapshot> aiSecrets;

  Map<String, dynamic> toJson() {
    return {
      'aiSecrets': aiSecrets.map((secret) => secret.toJson()).toList(),
    };
  }

  factory PetNoteSensitiveSettingsState.fromJson(Map<String, dynamic> json) {
    final rawSecrets = json['aiSecrets'];
    return PetNoteSensitiveSettingsState(
      aiSecrets: rawSecrets is List
          ? rawSecrets
              .whereType<Map>()
              .map((item) => PetNoteAiSecretSnapshot.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const <PetNoteAiSecretSnapshot>[],
    );
  }
}
```

并把 `PetNoteDataPackage` 扩展为：

```dart
  const PetNoteDataPackage({
    required this.schemaVersion,
    required this.packageType,
    required this.packageName,
    required this.description,
    required this.createdAt,
    required this.appVersion,
    required this.data,
    required this.settings,
    required this.sensitiveSettings,
    required this.meta,
  });

  final PetNoteSensitiveSettingsState? sensitiveSettings;
```

同时更新 `toJson()` / `fromJson()` 以读写可选 `sensitiveSettings`。

- [ ] **Step 4: 再跑模型与协调器测试，确认恢复为绿色**

Run: `flutter test test/data_storage_coordinator_test.dart`

Expected: PASS，且旧备份相关测试继续通过。

- [ ] **Step 5: 提交当前最小模型改动**

```bash
git add lib/data/data_storage_models.dart test/data_storage_coordinator_test.dart
git commit -m "feat: 为备份模型添加敏感设置结构"
```

### Task 2: 让协调器支持按选项导出与恢复 API Key

**Files:**
- Modify: `lib/data/data_storage_coordinator.dart`
- Test: `test/data_storage_coordinator_test.dart`

- [ ] **Step 1: 先写失败测试，约束默认不导出与显式导出才包含密钥**

```dart
test('exports backup package without sensitive settings by default', () async {
  final secretStore = InMemoryAiSecretStore();
  await secretStore.writeKey('cfg-openai', 'sk-test-123');

  final settingsController = await AppSettingsController.load();
  await settingsController.upsertAiProviderConfig(
    AiProviderConfig(
      id: 'cfg-openai',
      displayName: 'OpenAI',
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      isActive: true,
      createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
    ),
  );

  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: settingsController,
    secretStore: secretStore,
  );

  final package = await coordinator.createBackupPackage(
    packageName: '默认备份',
    description: '不含敏感信息',
  );

  expect(package.sensitiveSettings, isNull);
});

test('exports backup package with ai secrets when requested', () async {
  final secretStore = InMemoryAiSecretStore();
  await secretStore.writeKey('cfg-openai', 'sk-test-123');

  final settingsController = await AppSettingsController.load();
  await settingsController.upsertAiProviderConfig(
    AiProviderConfig(
      id: 'cfg-openai',
      displayName: 'OpenAI',
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      isActive: true,
      createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
    ),
  );

  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: settingsController,
    secretStore: secretStore,
  );

  final package = await coordinator.createBackupPackage(
    packageName: '敏感备份',
    description: '含 API Key',
    options: const DataExportOptions(includeSensitiveSettings: true),
  );

  expect(package.sensitiveSettings, isNotNull);
  expect(package.sensitiveSettings!.aiSecrets.single.apiKey, 'sk-test-123');
});
```

- [ ] **Step 2: 运行测试，确认因导出选项和 secret store 注入缺失而失败**

Run: `flutter test test/data_storage_coordinator_test.dart`

Expected: FAIL，提示 `DataExportOptions`、`secretStore`、`options` 等接口未定义。

- [ ] **Step 3: 在协调器中补最小实现**

```dart
class DataExportOptions {
  const DataExportOptions({
    this.includeSensitiveSettings = false,
  });

  final bool includeSensitiveSettings;
}

class DataImportOptions {
  const DataImportOptions({
    this.restoreSettings = false,
    this.restoreSensitiveSettings = false,
  });

  final bool restoreSettings;
  final bool restoreSensitiveSettings;
}
```

在 `DataStorageCoordinator` 中接入：

```dart
  DataStorageCoordinator({
    required this.store,
    required this.settingsController,
    this.appLogController,
    AiSecretStore? secretStore,
  }) : secretStore = secretStore ?? MethodChannelAiSecretStore(
          appLogController: appLogController,
        );

  final AiSecretStore secretStore;
```

并扩展导出逻辑：

```dart
  Future<PetNoteDataPackage> createBackupPackage({
    required String packageName,
    required String description,
    DataExportOptions options = const DataExportOptions(),
  }) async {
    final sensitiveSettings = options.includeSensitiveSettings
        ? await _exportSensitiveSettings()
        : null;
```

新增私有方法：

```dart
  Future<PetNoteSensitiveSettingsState?> _exportSensitiveSettings() async {
    if (!await secretStore.isAvailable()) {
      return null;
    }
    final secrets = <PetNoteAiSecretSnapshot>[];
    for (final config in settingsController.aiProviderConfigs) {
      final apiKey = await secretStore.readKey(config.id);
      if (apiKey == null || apiKey.isEmpty) {
        continue;
      }
      secrets.add(
        PetNoteAiSecretSnapshot(configId: config.id, apiKey: apiKey),
      );
    }
    if (secrets.isEmpty) {
      return null;
    }
    return PetNoteSensitiveSettingsState(aiSecrets: secrets);
  }
```

- [ ] **Step 4: 继续补导入恢复密钥的失败测试**

```dart
test('import keeps api secrets unchanged until restoreSensitiveSettings is true',
    () async {
  final secretStore = InMemoryAiSecretStore();
  final settingsController = await AppSettingsController.load();
  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: settingsController,
    secretStore: secretStore,
  );

  final package = PetNoteDataPackage(
    schemaVersion: PetNoteDataPackage.currentSchemaVersion,
    packageType: PetNoteDataPackageType.backup,
    packageName: '敏感备份',
    description: '导入测试',
    createdAt: DateTime.parse('2026-04-15T10:00:00+08:00'),
    appVersion: '1.0.0-test',
    data: PetNoteStore.seeded().exportDataState(),
    settings: const PetNoteSettingsState(
      themePreferenceName: 'system',
      aiProviderConfigs: <AiProviderConfig>[
        AiProviderConfig(
          id: 'cfg-openai',
          displayName: 'OpenAI',
          providerType: AiProviderType.openai,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-5.4',
          isActive: true,
          createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
          updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
        ),
      ],
      activeAiProviderConfigId: 'cfg-openai',
    ),
    sensitiveSettings: const PetNoteSensitiveSettingsState(
      aiSecrets: <PetNoteAiSecretSnapshot>[
        PetNoteAiSecretSnapshot(configId: 'cfg-openai', apiKey: 'sk-restore'),
      ],
    ),
    meta: const <String, Object?>{},
  );

  await coordinator.importPackage(
    package: package,
    options: const DataImportOptions(
      restoreSettings: true,
      restoreSensitiveSettings: false,
    ),
  );

  expect(await secretStore.readKey('cfg-openai'), isNull);
});
```

- [ ] **Step 5: 实现导入敏感恢复并验证全绿**

```dart
      final restoredSensitiveSettings = options.restoreSensitiveSettings &&
          package.sensitiveSettings != null &&
          await secretStore.isAvailable();
      if (restoredSensitiveSettings) {
        await _restoreSensitiveSettings(package);
      }
```

新增：

```dart
  Future<void> _restoreSensitiveSettings(PetNoteDataPackage package) async {
    final configs = package.settings?.aiProviderConfigs ?? const <AiProviderConfig>[];
    final knownConfigIds = configs.map((config) => config.id).toSet();
    for (final secret in package.sensitiveSettings?.aiSecrets ?? const <PetNoteAiSecretSnapshot>[]) {
      if (!knownConfigIds.contains(secret.configId)) {
        continue;
      }
      await secretStore.writeKey(secret.configId, secret.apiKey);
    }
  }
```

同时更新导入成功文案与日志区分普通设置/敏感设置。

Run: `flutter test test/data_storage_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交协调器行为变更**

```bash
git add lib/data/data_storage_coordinator.dart lib/data/data_storage_models.dart test/data_storage_coordinator_test.dart
git commit -m "feat: 支持备份导出与恢复敏感 AI 配置"
```

### Task 3: 给导出流程增加“包含 API Key”双确认

**Files:**
- Modify: `lib/app/data_storage_page.dart`
- Test: `test/data_storage_widget_test.dart`

- [ ] **Step 1: 先写失败 widget 测试，约束默认导出不带密钥**

```dart
testWidgets('export backup keeps api keys excluded unless user opts in',
    (tester) async {
  final settingsController = await AppSettingsController.load();
  final secretStore = InMemoryAiSecretStore();
  await settingsController.upsertAiProviderConfig(
    AiProviderConfig(
      id: 'cfg-openai',
      displayName: 'OpenAI',
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      isActive: true,
      createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
    ),
  );
  await secretStore.writeKey('cfg-openai', 'sk-test-123');

  final coordinator = DataStorageCoordinator(
    store: PetNoteStore.seeded(),
    settingsController: settingsController,
    secretStore: secretStore,
  );
  final fileAccess = _FakeDataPackageFileAccess(
    saveBackupHandler: ({required suggestedFileName, required rawJson}) async {
      return const SavedDataPackageFile(
        displayName: 'petnote_backup.json',
        locationLabel: 'Files',
        byteLength: 512,
      );
    },
  );

  await tester.pumpWidget(MaterialApp(
    theme: buildPetNoteTheme(Brightness.light),
    home: DataStoragePage(coordinator: coordinator, fileAccess: fileAccess),
  ));

  await tester.tap(find.byKey(const ValueKey('data_storage_export_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('backup_export_confirm_button')));
  await tester.pumpAndSettle();

  expect(fileAccess.savedBackups.single.rawJson, isNot(contains('sk-test-123')));
});
```

- [ ] **Step 2: 运行页面测试，确认导出确认弹窗相关控件不存在**

Run: `flutter test test/data_storage_widget_test.dart`

Expected: FAIL，提示 `backup_export_confirm_button` 或确认弹窗不存在。

- [ ] **Step 3: 在页面中加入导出确认模型与对话框**

```dart
class BackupExportDecision {
  const BackupExportDecision({
    required this.includeSensitiveSettings,
  });

  final bool includeSensitiveSettings;
}
```

在 `DataStoragePage` 中新增：

```dart
  Future<BackupExportDecision?> _confirmBackupExport() async {
    return showDialog<BackupExportDecision>(
      context: context,
      builder: (_) => const BackupExportDialog(),
    );
  }
```

并让 `_handleExportBackup()` 先拿确认结果：

```dart
    final decision = await _confirmBackupExport();
    if (!mounted || decision == null) {
      return;
    }
    final package = await widget.coordinator.createBackupPackage(
      packageName: 'PetNote 完整备份',
      description: '手动生成的完整备份包',
      options: DataExportOptions(
        includeSensitiveSettings: decision.includeSensitiveSettings,
      ),
    );
```

- [ ] **Step 4: 继续写失败测试，约束勾选 API Key 后必须第二次确认**

```dart
testWidgets('export backup requires second confirmation before including api keys',
    (tester) async {
  // 初始化同上一例
  await tester.tap(find.byKey(const ValueKey('data_storage_export_button')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('backup_export_include_sensitive_toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('backup_export_confirm_button')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('backup_export_sensitive_confirm_button')), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('backup_export_sensitive_confirm_button')));
  await tester.pumpAndSettle();

  expect(fileAccess.savedBackups.single.rawJson, contains('sk-test-123'));
});
```

- [ ] **Step 5: 实现二次确认并验证页面测试通过**

为包含敏感信息的导出分支新增第二层确认弹窗，至少包含：

```dart
const ValueKey('backup_export_include_sensitive_toggle')
const ValueKey('backup_export_confirm_button')
const ValueKey('backup_export_sensitive_confirm_button')
```

Run: `flutter test test/data_storage_widget_test.dart`

Expected: PASS，且原有导出测试更新为点击确认后继续通过。

- [ ] **Step 6: 提交导出双确认 UI**

```bash
git add lib/app/data_storage_page.dart test/data_storage_widget_test.dart
git commit -m "feat: 为敏感备份导出增加双重确认"
```

### Task 4: 给导入流程增加“恢复 API Key”单独确认

**Files:**
- Modify: `lib/app/data_storage_page.dart`
- Test: `test/data_storage_widget_test.dart`

- [ ] **Step 1: 先写失败 widget 测试，约束含敏感备份会显示额外风险提示**

```dart
testWidgets('restore preview warns when backup contains api keys', (tester) async {
  final settingsController = await AppSettingsController.load();
  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: settingsController,
    secretStore: InMemoryAiSecretStore(),
  );
  final fileAccess = _FakeDataPackageFileAccess(
    pickBackupHandler: () async => PickedDataPackageFile(
      displayName: 'backup_sensitive.json',
      rawJson: _backupPackageJson(
        includeSettings: true,
        includeSensitiveSettings: true,
      ),
      locationLabel: 'Files',
      byteLength: 512,
    ),
  );

  await tester.pumpWidget(MaterialApp(
    theme: buildPetNoteTheme(Brightness.light),
    home: DataStoragePage(coordinator: coordinator, fileAccess: fileAccess),
  ));

  await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
  await tester.pumpAndSettle();

  expect(find.textContaining('该备份文件包含 API Key'), findsOneWidget);
});
```

- [ ] **Step 2: 运行页面测试，确认提示文案尚不存在**

Run: `flutter test test/data_storage_widget_test.dart`

Expected: FAIL，提示找不到风险提示文案。

- [ ] **Step 3: 在导入预览页接入敏感检测与恢复开关**

在 `DataPackageReviewPage` 状态中新增：

```dart
  bool _restoreSensitiveSettings = false;

  bool get _hasSensitiveSettings =>
      widget.package.sensitiveSettings?.aiSecrets.isNotEmpty ?? false;
```

UI 中新增风险卡片或说明文案：

```dart
if (_hasSensitiveSettings) ...[
  const ListRow(
    title: '检测到敏感信息',
    subtitle: '该备份文件包含 API Key，恢复前需要再次确认。',
  ),
]
```

- [ ] **Step 4: 写失败测试，约束用户取消 API Key 恢复时不写入密钥**

```dart
testWidgets('restore can skip api key recovery after second confirmation is cancelled',
    (tester) async {
  final secretStore = InMemoryAiSecretStore();
  final settingsController = await AppSettingsController.load();
  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: settingsController,
    secretStore: secretStore,
  );

  // 进入导入预览并打开恢复设置
  await tester.tap(find.byKey(const ValueKey('data_package_restore_settings_toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('data_package_restore_sensitive_toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('data_package_execute_restore_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('danger_confirm_action_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('sensitive_restore_cancel_button')));
  await tester.pumpAndSettle();

  expect(await secretStore.readKey('cfg-openai'), isNull);
});
```

- [ ] **Step 5: 实现敏感恢复确认并验证页面测试全绿**

在 `_submit()` 中调整流程：

```dart
    final confirmed = await _confirmDanger(
      context,
      action: DataDangerAction.restoreFromBackupFile,
      restoreSettings: _restoreSettings,
    );
    if (!confirmed) {
      return;
    }

    var restoreSensitiveSettings = false;
    if (_restoreSettings && _restoreSensitiveSettings && _hasSensitiveSettings) {
      restoreSensitiveSettings = await _confirmSensitiveRestore(context);
    }
```

并在真正导入时传入：

```dart
    options: DataImportOptions(
      restoreSettings: _restoreSettings,
      restoreSensitiveSettings: restoreSensitiveSettings,
    ),
```

Run: `flutter test test/data_storage_widget_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交导入敏感恢复交互**

```bash
git add lib/app/data_storage_page.dart test/data_storage_widget_test.dart
git commit -m "feat: 为敏感备份恢复增加单独确认"
```

### Task 5: 做收口验证并检查平台构建

**Files:**
- Modify: `lib/data/data_storage_models.dart`
- Modify: `lib/data/data_storage_coordinator.dart`
- Modify: `lib/app/data_storage_page.dart`
- Modify: `test/data_storage_coordinator_test.dart`
- Modify: `test/data_storage_widget_test.dart`

- [ ] **Step 1: 跑数据与页面相关测试**

Run: `flutter test test/data_storage_coordinator_test.dart test/data_storage_widget_test.dart`

Expected: PASS。

- [ ] **Step 2: 跑全量 Flutter 测试，确保没有回归**

Run: `flutter test`

Expected: PASS。

- [ ] **Step 3: 按仓库默认流程验证构建产物**

Run: `flutter build ios --simulator`

Expected: PASS，产出 `build/ios/iphonesimulator/Runner.app`

Run: `xcrun simctl install booted build/ios/iphonesimulator/Runner.app`

Expected: PASS

Run: `flutter build ipa --no-codesign`

Expected: PASS，产出 `build/ios/archive/Runner.xcarchive`

Run: `flutter build apk --target-platform android-arm64 --split-per-abi`

Expected: PASS，产出 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

- [ ] **Step 4: 检查工作区状态并整理变更说明**

Run: `git status --short --branch`

Expected: 仅出现本次计划内文件变更，以及用户本地未纳入版本控制的签名文件/证书目录。

- [ ] **Step 5: 提交最终实现**

```bash
git add lib/data/data_storage_models.dart lib/data/data_storage_coordinator.dart lib/app/data_storage_page.dart test/data_storage_coordinator_test.dart test/data_storage_widget_test.dart
git commit -m "feat: 支持备份可选导出 AI 密钥"
```
