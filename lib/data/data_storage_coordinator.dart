import 'dart:convert';

import 'package:petnote/ai/ai_insights_models.dart';
import 'package:flutter/foundation.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

class DataStorageCoordinator extends ChangeNotifier {
  DataStorageCoordinator({
    required this.store,
    required this.settingsController,
    this.appLogController,
    AiSecretStore? secretStore,
  }) : secretStore = secretStore ??
            MethodChannelAiSecretStore(appLogController: appLogController);

  final PetNoteStore store;
  final AppSettingsController settingsController;
  final AppLogController? appLogController;
  final AiSecretStore secretStore;

  PetNoteDataPackage? _latestSnapshotPackage;
  DataOperationResult? _latestOperationResult;

  DataOperationResult? get latestOperationResult => _latestOperationResult;

  String get dataSummary {
    return '宠物 ${store.pets.length} 只 · 待办 ${store.todos.length} 条 · '
        '提醒 ${store.reminders.length} 条 · 记录 ${store.records.length} 条';
  }

  Future<PetNoteDataPackage> createBackupPackage({
    required String packageName,
    required String description,
    DataExportOptions options = const DataExportOptions(),
  }) async {
    final sensitiveSettings = options.includeSensitiveSettings
        ? await _exportSensitiveSettings()
        : null;
    final package = PetNoteDataPackage(
      schemaVersion: PetNoteDataPackage.currentSchemaVersion,
      packageType: PetNoteDataPackageType.backup,
      packageName: packageName,
      description: description,
      createdAt: DateTime.now(),
      appVersion: '1.0.0-beta.2+3',
      data: store.exportDataState(),
      settings: settingsController.exportNonSensitiveSettings(),
      sensitiveSettings: sensitiveSettings,
      meta: const <String, Object?>{'source': 'manual_export'},
    );
    _latestOperationResult = _resultForPackage(
      kind: DataOperationKind.backupExported,
      package: package,
      message: '完整备份已生成。',
      snapshotCreated: false,
      restoredSettings: false,
      isSuccess: true,
    );
    appLogController?.info(
      category: AppLogCategory.dataStorage,
      title: '生成完整备份',
      message: '完整备份包已生成。',
      details:
          'pets=${package.data.pets.length}, todos=${package.data.todos.length}, reminders=${package.data.reminders.length}, records=${package.data.records.length}',
    );
    notifyListeners();
    return package;
  }

  AiPortableSummaryPackage createAiSummaryPackage({
    String packageName = 'PetNote AI 摘要',
  }) {
    final package = store.buildAiPortableSummary(title: packageName);
    _latestOperationResult = DataOperationResult(
      kind: DataOperationKind.backupExported,
      isSuccess: true,
      message: 'AI 摘要数据已生成。',
      snapshotCreated: false,
      restoredSettings: false,
      packageType: null,
      petsCount: store.pets.length,
      todosCount: store.todos.length,
      remindersCount: store.reminders.length,
      recordsCount: store.records.length,
    );
    appLogController?.info(
      category: AppLogCategory.dataStorage,
      title: '生成 AI 摘要',
      message: 'AI 摘要数据包已生成。',
      details: jsonEncode(package.globalStats),
    );
    notifyListeners();
    return package;
  }

  Future<DataOperationResult> importPackage({
    required PetNoteDataPackage package,
    DataImportOptions options = const DataImportOptions(),
  }) async {
    final validationError = validatePackage(package);
    if (validationError != null) {
      appLogController?.warning(
        category: AppLogCategory.dataStorage,
        title: '数据包校验失败',
        message: validationError,
        details: 'package=${package.packageName}',
      );
      return _setOperation(
        DataOperationResult(
          kind: DataOperationKind.validationFailed,
          isSuccess: false,
          message: validationError,
          snapshotCreated: false,
          restoredSettings: false,
          packageType: package.packageType,
          petsCount: package.data.pets.length,
          todosCount: package.data.todos.length,
          remindersCount: package.data.reminders.length,
          recordsCount: package.data.records.length,
        ),
      );
    }

    try {
      final snapshot = await _captureSnapshot();
      await store.replaceAllData(package.data);
      final restoredSettings =
          options.restoreSettings && package.settings != null;
      final restoredSensitiveSettings =
          options.restoreSensitiveSettings && restoredSettings;
      if (restoredSettings) {
        await settingsController.restoreNonSensitiveSettings(package.settings!);
      }
      if (restoredSensitiveSettings) {
        await _restoreSensitiveSettings(package);
      }
      final successMessage = _successMessage(
        restoredSettings: restoredSettings,
        restoredSensitiveSettings: restoredSensitiveSettings,
      );
      appLogController?.info(
        category: AppLogCategory.dataStorage,
        title: '备份恢复完成',
        message: successMessage,
        details:
            'package=${package.packageName}\nrestoreSettings=$restoredSettings\nrestoreSensitiveSettings=$restoredSensitiveSettings',
      );
      return _setOperation(
        _resultForPackage(
          kind: DataOperationKind.importedReplace,
          package: package,
          message: successMessage,
          snapshotCreated: snapshot != null,
          restoredSettings: restoredSettings,
          isSuccess: true,
        ),
      );
    } on StateError catch (error) {
      appLogController?.error(
        category: AppLogCategory.dataStorage,
        title: '导入失败',
        message: error.message,
        details: 'package=${package.packageName}',
      );
      return _setOperation(
        _resultForPackage(
          kind: DataOperationKind.validationFailed,
          package: package,
          message: error.message,
          snapshotCreated: false,
          restoredSettings: false,
          isSuccess: false,
        ),
      );
    }
  }

  Future<DataOperationResult> clearAllData() async {
    final snapshot = await _captureSnapshot();
    await store.clearAllData();
    await settingsController.resetNonSensitiveSettings();
    appLogController?.warning(
      category: AppLogCategory.dataStorage,
      title: '清空本地数据',
      message: '本地业务数据和普通设置已清空。',
      details: snapshot == null ? '未执行内部保护' : '已执行内部保护',
    );
    return _setOperation(
      DataOperationResult(
        kind: DataOperationKind.cleared,
        isSuccess: true,
        message: '本地业务数据和普通设置已清空。',
        snapshotCreated: snapshot != null,
        restoredSettings: false,
        packageType: null,
        petsCount: 0,
        todosCount: 0,
        remindersCount: 0,
        recordsCount: 0,
      ),
    );
  }

  PetNoteDataPackage parsePackageJson(String rawValue) {
    final decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, dynamic>) {
      appLogController?.warning(
        category: AppLogCategory.dataStorage,
        title: '解析数据包失败',
        message: 'JSON 顶层结构不是对象。',
      );
      throw const FormatException('JSON 顶层结构必须是对象。');
    }
    final rawPackageType = decoded['packageType'] as String?;
    if (rawPackageType != null && rawPackageType != 'backup') {
      appLogController?.warning(
        category: AppLogCategory.dataStorage,
        title: '解析数据包失败',
        message: '当前仅支持完整备份文件。',
        details: 'packageType=$rawPackageType',
      );
      throw const FormatException('当前仅支持完整备份文件。');
    }
    appLogController?.info(
      category: AppLogCategory.dataStorage,
      title: '解析数据包成功',
      message: '文件内容已解析为数据包对象。',
    );
    return PetNoteDataPackage.fromJson(decoded);
  }

  String? validatePackage(PetNoteDataPackage package) {
    if (package.schemaVersion != PetNoteDataPackage.currentSchemaVersion) {
      return '数据包版本暂不支持。';
    }
    if (package.packageName.trim().isEmpty) {
      return '数据包缺少名称。';
    }
    if (package.data.pets.isEmpty &&
        package.data.todos.isEmpty &&
        package.data.reminders.isEmpty &&
        package.data.records.isEmpty) {
      return '数据包没有任何业务数据。';
    }
    try {
      store.exportDataState();
    } catch (_) {
      return '当前数据状态异常，暂时无法导入。';
    }
    return null;
  }

  Future<PetNoteDataPackage?> _captureSnapshot() async {
    final currentData = store.exportDataState();
    if (currentData.totalCount == 0 &&
        settingsController.aiProviderConfigs.isEmpty &&
        settingsController.themePreference == AppThemePreference.system) {
      _latestSnapshotPackage = null;
      return null;
    }
    _latestSnapshotPackage = PetNoteDataPackage(
      schemaVersion: PetNoteDataPackage.currentSchemaVersion,
      packageType: PetNoteDataPackageType.backup,
      packageName: '内部保护数据',
      description: '危险操作前自动生成，仅用于内部保护',
      createdAt: DateTime.now(),
      appVersion: '1.0.0-beta.2+3',
      data: currentData,
      settings: settingsController.exportNonSensitiveSettings(),
      sensitiveSettings: null,
      meta: const <String, Object?>{'source': 'internal_protection'},
    );
    return _latestSnapshotPackage;
  }

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
        PetNoteAiSecretSnapshot(
          configId: config.id,
          apiKey: apiKey,
        ),
      );
    }
    if (secrets.isEmpty) {
      return null;
    }
    return PetNoteSensitiveSettingsState(aiSecrets: secrets);
  }

  Future<void> _restoreSensitiveSettings(PetNoteDataPackage package) async {
    final sensitiveSettings = package.sensitiveSettings;
    if (sensitiveSettings == null || !sensitiveSettings.hasSecrets) {
      return;
    }
    if (!await secretStore.isAvailable()) {
      return;
    }
    final knownConfigIds = (package.settings?.aiProviderConfigs ?? const [])
        .map((config) => config.id)
        .toSet();
    for (final secret in sensitiveSettings.aiSecrets) {
      if (!knownConfigIds.contains(secret.configId)) {
        continue;
      }
      await secretStore.writeKey(secret.configId, secret.apiKey);
    }
  }

  String _successMessage({
    required bool restoredSettings,
    required bool restoredSensitiveSettings,
  }) {
    if (restoredSensitiveSettings) {
      return '备份数据、普通设置和 API Key 已恢复。';
    }
    if (restoredSettings) {
      return '备份数据和普通设置已恢复。';
    }
    return '备份数据已恢复，当前设置保持不变。';
  }

  DataOperationResult _resultForPackage({
    required DataOperationKind kind,
    required PetNoteDataPackage package,
    required String message,
    required bool snapshotCreated,
    required bool restoredSettings,
    required bool isSuccess,
  }) {
    return DataOperationResult(
      kind: kind,
      isSuccess: isSuccess,
      message: message,
      snapshotCreated: snapshotCreated,
      restoredSettings: restoredSettings,
      packageType: package.packageType,
      petsCount: package.data.pets.length,
      todosCount: package.data.todos.length,
      remindersCount: package.data.reminders.length,
      recordsCount: package.data.records.length,
    );
  }

  DataOperationResult _setOperation(DataOperationResult result) {
    _latestOperationResult = result;
    notifyListeners();
    return result;
  }
}
