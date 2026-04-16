import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/data_storage_page.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/data/data_package_file_access.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('me page exposes data storage center entry', (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.unknown,
            notificationPushToken: null,
            onRequestNotificationPermission: null,
            onOpenNotificationSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: null,
            dataStorageCoordinator: coordinator,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('打开数据与存储'), 200);
    expect(find.text('打开数据与存储'), findsOneWidget);
  });

  testWidgets('data storage page exports backup through file manager',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final store = PetNoteStore.seeded();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );
    final fileAccess = _FakeDataPackageFileAccess(
      saveBackupHandler: (
          {required suggestedFileName, required rawJson}) async {
        return const SavedDataPackageFile(
          displayName: 'petnote_backup.json',
          locationLabel: 'Files',
          byteLength: 512,
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_export_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup_export_confirm_button')));
    await tester.pumpAndSettle();

    expect(fileAccess.savedBackups, hasLength(1));
    expect(
      fileAccess.savedBackups.single.rawJson,
      contains('"packageType": "backup"'),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('备份已保存到 Files · petnote_backup.json'),
        findsOneWidget);
    expect(find.textContaining('petnote_backup.json'), findsWidgets);
    expect(find.textContaining('Files'), findsWidgets);
  });

  testWidgets('export backup requires second confirmation before including api keys',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
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
    final secretStore = InMemoryAiSecretStore();
    await secretStore.writeKey('cfg-openai', 'sk-test-123');
    final coordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
      secretStore: secretStore,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      saveBackupHandler: (
          {required suggestedFileName, required rawJson}) async {
        return const SavedDataPackageFile(
          displayName: 'petnote_backup_sensitive.json',
          locationLabel: 'Files',
          byteLength: 768,
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_export_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('backup_export_include_sensitive_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup_export_confirm_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('backup_export_sensitive_confirm_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('backup_export_sensitive_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(fileAccess.savedBackups, hasLength(1));
    expect(fileAccess.savedBackups.single.rawJson, contains('sk-test-123'));
  });

  testWidgets('data storage actions keep unified button sizing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final store = PetNoteStore.seeded();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: _FakeDataPackageFileAccess(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final exportButton =
        find.byKey(const ValueKey('data_storage_export_button'));
    final restoreButton =
        find.byKey(const ValueKey('data_storage_restore_button'));
    final clearButton = find.byKey(const ValueKey('data_storage_clear_button'));

    await tester.scrollUntilVisible(clearButton, 120);
    await tester.pumpAndSettle();

    expect(exportButton, findsOneWidget);
    expect(restoreButton, findsOneWidget);
    expect(clearButton, findsOneWidget);
    expect(find.text('测试与演示'), findsNothing);
    expect(find.text('恢复最近快照'), findsNothing);
    expect(find.text('导入测试/演示数据'), findsNothing);

    final exportHeight = tester.getSize(exportButton).height;
    expect(exportHeight, closeTo(tester.getSize(restoreButton).height, 0.1));
    expect(exportHeight, closeTo(tester.getSize(clearButton).height, 0.1));
  });

  testWidgets(
      'restore from backup file keeps settings by default and updates confirm copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    await settingsController.setThemePreference(AppThemePreference.dark);
    final store = await PetNoteStore.load();
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.1,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '主粮',
      allergies: '无',
      note: '旧数据',
    );
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => PickedDataPackageFile(
        displayName: 'backup.json',
        rawJson: _backupPackageJson(),
        locationLabel: 'iCloud Drive',
        byteLength: _backupPackageJson().length,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    expect(find.text('导入预览'), findsWidgets);
    expect(find.text('从备份文件恢复'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('data_package_execute_restore_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DangerConfirmDialog), findsOneWidget);
    expect(find.textContaining('当前本地业务数据会被备份内容覆盖，当前设置保留不变'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('danger_confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(store.pets.single.name, 'Mochi');

    await tester.tap(
      find.byKey(const ValueKey('data_package_execute_restore_button')),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('danger_confirm_action_button')));
    await tester.pumpAndSettle();

    expect(store.pets, hasLength(1));
    expect(store.pets.single.name, 'Nova');
    expect(settingsController.themePreference, AppThemePreference.dark);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('data_storage_feedback_banner')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('data_storage_feedback_banner')),
        matching: find.text('备份数据已恢复，当前设置保持不变。'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'restore preview shows optional settings toggle and can restore settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    await settingsController.setThemePreference(AppThemePreference.dark);
    final store = await PetNoteStore.load();
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.1,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '主粮',
      allergies: '无',
      note: '旧数据',
    );
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => PickedDataPackageFile(
        displayName: 'backup_with_settings.json',
        rawJson: _backupPackageJson(
          includeSettings: true,
          themePreferenceName: 'light',
        ),
        locationLabel: 'iCloud Drive',
        byteLength: _backupPackageJson(
          includeSettings: true,
          themePreferenceName: 'light',
        ).length,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('data_package_restore_settings_toggle')),
        findsOneWidget);
    expect(find.text('恢复设置内容'), findsOneWidget);

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('data_package_restore_settings_toggle')),
    );
    expect(toggle.value, isFalse);
    expect(find.textContaining('默认仅恢复宠物、待办、提醒和记录'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('data_package_restore_settings_toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('会额外恢复主题偏好和 AI 配置等普通设置'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('data_package_execute_restore_button')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('当前本地业务数据和普通设置都会被备份内容覆盖'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('danger_confirm_action_button')));
    await tester.pumpAndSettle();

    expect(settingsController.themePreference, AppThemePreference.light);
    expect(find.byKey(const ValueKey('data_storage_feedback_banner')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('data_storage_feedback_banner')),
        matching: find.text('备份数据和普通设置已恢复。'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('legacy scenario package is rejected before preview',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final store = await PetNoteStore.load();
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '母',
      birthday: '2024-02-12',
      weightKg: 4.1,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '主粮',
      allergies: '无',
      note: '旧数据',
    );
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => PickedDataPackageFile(
        displayName: 'scenario.json',
        rawJson: _legacyScenarioPackageJson(),
        locationLabel: 'Downloads',
        byteLength: _legacyScenarioPackageJson().length,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    expect(find.text('导入预览'), findsNothing);
    expect(find.text('当前仅支持完整备份文件。'), findsOneWidget);
    expect(store.pets, hasLength(1));
    expect(store.pets.single.name, 'Mochi');
  });

  testWidgets('restore preview warns when backup contains api keys',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: await PetNoteStore.load(),
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );
    final rawJson = _backupPackageJson(
      includeSettings: true,
      includeSensitiveSettings: true,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => PickedDataPackageFile(
        displayName: 'backup_sensitive.json',
        rawJson: rawJson,
        locationLabel: 'Files',
        byteLength: rawJson.length,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('该备份文件包含 API Key'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('data_package_restore_sensitive_toggle')),
      findsOneWidget,
    );
  });

  testWidgets(
      'restore can skip api key recovery after second confirmation is cancelled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = DataStorageCoordinator(
      store: await PetNoteStore.load(),
      settingsController: settingsController,
      secretStore: secretStore,
    );
    final rawJson = _backupPackageJson(
      includeSettings: true,
      includeSensitiveSettings: true,
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => PickedDataPackageFile(
        displayName: 'backup_sensitive.json',
        rawJson: rawJson,
        locationLabel: 'Files',
        byteLength: rawJson.length,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('data_package_restore_settings_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('data_package_restore_sensitive_toggle')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('data_package_execute_restore_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('danger_confirm_action_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sensitive_restore_cancel_button')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sensitive_restore_cancel_button')));
    await tester.pumpAndSettle();

    expect(await secretStore.readKey('cfg-openai'), isNull);
  });

  testWidgets('clear local data requires second confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final store = PetNoteStore.seeded();
    final coordinator = DataStorageCoordinator(
      store: store,
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: _FakeDataPackageFileAccess(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_clear_button')));
    await tester.pumpAndSettle();

    expect(find.byType(DangerConfirmDialog), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('danger_confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(store.pets, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('data_storage_clear_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('danger_confirm_action_button')));
    await tester.pumpAndSettle();

    expect(store.pets, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('data_storage_feedback_banner')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('data_storage_feedback_banner')),
        matching: find.text('本地业务数据和普通设置已清空。'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'danger confirm dialog buttons keep unified sizing without divider',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: const Scaffold(
          body: SizedBox.shrink(),
        ),
      ),
    );

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(SizedBox)),
        builder: (_) => const DangerConfirmDialog(
          action: DataDangerAction.clearLocalData,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cancelButton =
        find.byKey(const ValueKey('danger_confirm_cancel_button'));
    final confirmButton =
        find.byKey(const ValueKey('danger_confirm_action_button'));

    expect(cancelButton, findsOneWidget);
    expect(confirmButton, findsOneWidget);
    expect(
      tester.getSize(cancelButton).height,
      closeTo(tester.getSize(confirmButton).height, 0.1),
    );
    expect(
      tester.getTopLeft(cancelButton).dy,
      closeTo(tester.getTopLeft(confirmButton).dy, 0.1),
    );
    expect(
      tester.getTopLeft(cancelButton).dx,
      lessThan(tester.getTopLeft(confirmButton).dx),
    );
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('danger confirm dialog stacks buttons on narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(1.35),
          ),
          child: const Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      ),
    );

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(SizedBox)),
        builder: (_) => const DangerConfirmDialog(
          action: DataDangerAction.restoreFromBackupFile,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cancelButton =
        find.byKey(const ValueKey('danger_confirm_cancel_button'));
    final confirmButton =
        find.byKey(const ValueKey('danger_confirm_action_button'));

    expect(cancelButton, findsOneWidget);
    expect(confirmButton, findsOneWidget);
    expect(
      tester.getTopLeft(cancelButton).dy,
      lessThan(tester.getTopLeft(confirmButton).dy),
    );
    expect(
      tester.getSize(cancelButton).width,
      closeTo(tester.getSize(confirmButton).width, 0.1),
    );
  });

  testWidgets('cancelled file selection does not show an error',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );
    final fileAccess = _FakeDataPackageFileAccess(
      pickBackupHandler: () async => null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_restore_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('文件读取失败'), findsNothing);
    expect(find.textContaining('服务不可用'), findsNothing);
    expect(find.text('导入预览'), findsNothing);
  });

  testWidgets('page feedback does not remain after leaving data storage page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );
    final fileAccess = _FakeDataPackageFileAccess(
      saveBackupHandler: (
          {required suggestedFileName, required rawJson}) async {
        return const SavedDataPackageFile(
          displayName: 'petnote_backup.json',
          locationLabel: 'Files',
          byteLength: 512,
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DataStoragePage(
                        coordinator: coordinator,
                        fileAccess: fileAccess,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('data_storage_export_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup_export_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('备份已保存到 Files · petnote_backup.json'),
        findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('备份已保存到 Files · petnote_backup.json'),
        findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}

class _FakeDataPackageFileAccess implements DataPackageFileAccess {
  _FakeDataPackageFileAccess({
    this.pickBackupHandler,
    this.saveBackupHandler,
  });

  final Future<PickedDataPackageFile?> Function()? pickBackupHandler;
  final Future<SavedDataPackageFile?> Function({
    required String suggestedFileName,
    required String rawJson,
  })? saveBackupHandler;

  final List<_SavedBackupRequest> savedBackups = <_SavedBackupRequest>[];

  @override
  Future<PickedDataPackageFile?> pickBackupFile() async {
    return pickBackupHandler?.call();
  }

  @override
  Future<SavedDataPackageFile?> saveBackupFile({
    required String suggestedFileName,
    required String rawJson,
  }) async {
    savedBackups.add(
      _SavedBackupRequest(
        suggestedFileName: suggestedFileName,
        rawJson: rawJson,
      ),
    );
    return saveBackupHandler?.call(
      suggestedFileName: suggestedFileName,
      rawJson: rawJson,
    );
  }
}

class _SavedBackupRequest {
  const _SavedBackupRequest({
    required this.suggestedFileName,
    required this.rawJson,
  });

  final String suggestedFileName;
  final String rawJson;
}

String _backupPackageJson({
  bool includeSettings = false,
  bool includeSensitiveSettings = false,
  String themePreferenceName = 'light',
}) {
  return _packageJson(
    petId: 'pet-restore',
    petName: 'Nova',
    includeSettings: includeSettings,
    includeSensitiveSettings: includeSensitiveSettings,
    themePreferenceName: themePreferenceName,
  );
}

String _legacyScenarioPackageJson() {
  final package = jsonDecode(_packageJson(
    petId: 'pet-legacy',
    petName: 'Nova',
  )) as Map<String, dynamic>;
  package['packageType'] = 'scenario';
  return jsonEncode(package);
}

String _packageJson({
  required String petId,
  required String petName,
  bool includeSettings = false,
  bool includeSensitiveSettings = false,
  String themePreferenceName = 'light',
}) {
  final package = PetNoteDataPackage(
    schemaVersion: PetNoteDataPackage.currentSchemaVersion,
    packageType: PetNoteDataPackageType.backup,
    packageName: '测试数据包',
    description: '用于 widget 测试',
    createdAt: DateTime.parse('2026-04-09T12:00:00+08:00'),
    appVersion: '1.0.0-test',
    data: PetNoteDataState(
      pets: <Pet>[
        Pet(
          id: petId,
          name: petName,
          avatarText: 'NO',
          type: PetType.cat,
          breed: '英短',
          sex: '母',
          birthday: '2024-02-12',
          ageLabel: '新加入',
          weightKg: 4.1,
          neuterStatus: PetNeuterStatus.neutered,
          feedingPreferences: '主粮',
          allergies: '无',
          note: '稳定',
        ),
      ],
      todos: const <TodoItem>[],
      reminders: const <ReminderItem>[],
      records: const <PetRecord>[],
    ),
    settings: includeSettings
        ? PetNoteSettingsState(
            themePreferenceName: themePreferenceName,
            aiProviderConfigs: includeSensitiveSettings
                ? <AiProviderConfig>[
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
                  ]
                : const <AiProviderConfig>[],
            activeAiProviderConfigId:
                includeSensitiveSettings ? 'cfg-openai' : null,
          )
        : null,
    sensitiveSettings: includeSensitiveSettings
        ? const PetNoteSensitiveSettingsState(
            aiSecrets: <PetNoteAiSecretSnapshot>[
              PetNoteAiSecretSnapshot(
                configId: 'cfg-openai',
                apiKey: 'sk-restore-123',
              ),
            ],
          )
        : null,
    meta: const <String, Object?>{},
  );
  return jsonEncode(package.toJson());
}
