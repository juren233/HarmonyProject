import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
          PetNoteAiSecretSnapshot(
            configId: 'cfg-openai',
            apiKey: 'sk-test-123',
          ),
        ],
      ),
      meta: const <String, Object?>{},
    );

    final decoded = PetNoteDataPackage.fromJson(package.toJson());

    expect(decoded.sensitiveSettings, isNotNull);
    expect(decoded.sensitiveSettings!.aiSecrets.single.configId, 'cfg-openai');
    expect(decoded.sensitiveSettings!.aiSecrets.single.apiKey, 'sk-test-123');
  });

  test('exports backup package with business data and non-sensitive settings',
      () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '冻干拌主粮',
      allergies: '鸡肉敏感',
      note: '洗澡会紧张',
    );
    await settingsController.setThemePreference(AppThemePreference.dark);
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai',
        displayName: 'OpenAI 主账号',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
        updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      ),
    );

    final package = await coordinator.createBackupPackage(
      packageName: '手动备份',
      description: '用于迁移',
    );
    final encoded = jsonEncode(package.toJson());

    expect(package.packageType, PetNoteDataPackageType.backup);
    expect(package.packageName, '手动备份');
    expect(package.data.pets.single.name, 'Mochi');
    expect(package.settings?.themePreferenceName, 'dark');
    expect(
        package.settings?.aiProviderConfigs.single.displayName, 'OpenAI 主账号');
    expect(encoded, isNot(contains('sk-')));
  });

  test('exports backup package without sensitive settings by default',
      () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
      secretStore: secretStore,
    );

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai',
        displayName: 'OpenAI 主账号',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
        updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      ),
    );
    await secretStore.writeKey('cfg-openai', 'sk-test-123');

    final package = await coordinator.createBackupPackage(
      packageName: '默认备份',
      description: '不含敏感信息',
    );

    expect(package.sensitiveSettings, isNull);
  });

  test('exports backup package with ai secrets when requested', () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
      secretStore: secretStore,
    );

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai',
        displayName: 'OpenAI 主账号',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
        updatedAt: DateTime.parse('2026-04-09T10:00:00+08:00'),
      ),
    );
    await secretStore.writeKey('cfg-openai', 'sk-test-123');

    final package = await coordinator.createBackupPackage(
      packageName: '敏感备份',
      description: '含 API Key',
      options: const DataExportOptions(includeSensitiveSettings: true),
    );

    expect(package.sensitiveSettings, isNotNull);
    expect(package.sensitiveSettings!.aiSecrets.single.apiKey, 'sk-test-123');
  });

  test(
      'replace import overwrites current data but keeps current settings by default',
      () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '未填写',
      allergies: '未填写',
      note: '旧数据',
    );
    await settingsController.setThemePreference(AppThemePreference.dark);

    final seeded = PetNoteStore.seeded();
    final backupPackage = PetNoteDataPackage(
      schemaVersion: PetNoteDataPackage.currentSchemaVersion,
      packageType: PetNoteDataPackageType.backup,
      packageName: '正式备份包',
      description: '替换为备份数据',
      createdAt: DateTime.parse('2026-04-09T12:00:00+08:00'),
      appVersion: '1.0.0-test',
      data: seeded.exportDataState(),
      settings: const PetNoteSettingsState(
        themePreferenceName: 'light',
        aiProviderConfigs: <AiProviderConfig>[],
        activeAiProviderConfigId: null,
      ),
      meta: const <String, Object?>{},
    );

    final replaceResult = await coordinator.importPackage(
      package: backupPackage,
      options: const DataImportOptions(restoreSettings: false),
    );

    expect(replaceResult.snapshotCreated, isTrue);
    expect(replaceResult.kind, DataOperationKind.importedReplace);
    expect(replaceResult.restoredSettings, isFalse);
    expect(store.pets.map((pet) => pet.name), isNot(contains('Mochi')));
    expect(store.pets.map((pet) => pet.name),
        containsAll(<String>['Luna', 'Milo']));
    expect(replaceResult.message, '备份数据已恢复，当前设置保持不变。');
    expect(settingsController.themePreference, AppThemePreference.dark);
  });

  test('replace import restores settings when the option is enabled', () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '未填写',
      allergies: '未填写',
      note: '旧数据',
    );
    await settingsController.setThemePreference(AppThemePreference.dark);

    final seeded = PetNoteStore.seeded();
    final backupPackage = PetNoteDataPackage(
      schemaVersion: PetNoteDataPackage.currentSchemaVersion,
      packageType: PetNoteDataPackageType.backup,
      packageName: '正式备份包',
      description: '替换为备份数据',
      createdAt: DateTime.parse('2026-04-09T12:00:00+08:00'),
      appVersion: '1.0.0-test',
      data: seeded.exportDataState(),
      settings: const PetNoteSettingsState(
        themePreferenceName: 'light',
        aiProviderConfigs: <AiProviderConfig>[],
        activeAiProviderConfigId: null,
      ),
      meta: const <String, Object?>{},
    );

    final replaceResult = await coordinator.importPackage(
      package: backupPackage,
      options: const DataImportOptions(restoreSettings: true),
    );

    expect(replaceResult.snapshotCreated, isTrue);
    expect(replaceResult.kind, DataOperationKind.importedReplace);
    expect(replaceResult.restoredSettings, isTrue);
    expect(replaceResult.message, '备份数据和普通设置已恢复。');
    expect(settingsController.themePreference, AppThemePreference.light);
  });

  test(
      'import keeps api secrets unchanged until restoreSensitiveSettings is true',
      () async {
    final store = await PetNoteStore.load();
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
      secretStore: secretStore,
    );

    final backupPackage = PetNoteDataPackage(
      schemaVersion: PetNoteDataPackage.currentSchemaVersion,
      packageType: PetNoteDataPackageType.backup,
      packageName: '敏感恢复备份',
      description: '导入恢复 API Key',
      createdAt: DateTime.parse('2026-04-15T12:00:00+08:00'),
      appVersion: '1.0.0-test',
      data: PetNoteStore.seeded().exportDataState(),
      settings: PetNoteSettingsState(
        themePreferenceName: 'light',
        aiProviderConfigs: <AiProviderConfig>[
          AiProviderConfig(
            id: 'cfg-openai',
            displayName: 'OpenAI 主账号',
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
          PetNoteAiSecretSnapshot(
            configId: 'cfg-openai',
            apiKey: 'sk-restore-123',
          ),
        ],
      ),
      meta: const <String, Object?>{},
    );

    await coordinator.importPackage(
      package: backupPackage,
      options: const DataImportOptions(
        restoreSettings: true,
        restoreSensitiveSettings: false,
      ),
    );

    expect(await secretStore.readKey('cfg-openai'), isNull);

    await coordinator.importPackage(
      package: backupPackage,
      options: const DataImportOptions(
        restoreSettings: true,
        restoreSensitiveSettings: true,
      ),
    );

    expect(await secretStore.readKey('cfg-openai'), 'sk-restore-123');
  });

  test('clear all data removes business data and resets settings', () async {
    final store = PetNoteStore.seeded();
    final settingsController = await AppSettingsController.load();
    await settingsController.setThemePreference(AppThemePreference.dark);
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    final clearResult = await coordinator.clearAllData();

    expect(clearResult.isSuccess, isTrue);
    expect(clearResult.snapshotCreated, isTrue);
    expect(store.pets, isEmpty);
    expect(store.todos, isEmpty);
    expect(store.reminders, isEmpty);
    expect(store.records, isEmpty);
    expect(settingsController.themePreference, AppThemePreference.system);
  });

  test('parsePackageJson rejects legacy scenario packages', () async {
    final coordinator = DataStorageCoordinator(
      store: await PetNoteStore.load(),
      settingsController: await AppSettingsController.load(),
    );

    final legacyScenarioJson = jsonEncode(<String, Object?>{
      'schemaVersion': PetNoteDataPackage.currentSchemaVersion,
      'packageType': 'scenario',
      'packageName': '旧演示数据',
      'description': '已废弃',
      'createdAt': '2026-04-09T12:00:00+08:00',
      'appVersion': '1.0.0-test',
      'data': const <String, Object?>{
        'pets': <Object?>[],
        'todos': <Object?>[],
        'reminders': <Object?>[],
        'records': <Object?>[],
      },
      'settings': null,
      'meta': const <String, Object?>{},
    });

    expect(
      () => coordinator.parsePackageJson(legacyScenarioJson),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '当前仅支持完整备份文件。',
        ),
      ),
    );
  });

  test('legacy operation payloads still decode into supported enums', () {
    final result = DataOperationResult.fromJson(<String, Object?>{
      'kind': 'restoredSnapshot',
      'isSuccess': true,
      'message': 'legacy',
      'snapshotCreated': false,
      'packageType': 'scenario',
      'petsCount': 1,
      'todosCount': 2,
      'remindersCount': 3,
      'recordsCount': 4,
    });

    expect(result.kind, DataOperationKind.importedReplace);
    expect(result.packageType, PetNoteDataPackageType.backup);
  });
}
