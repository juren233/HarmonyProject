import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/ai_settings_page.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/app/native_option_picker.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _petsStorageKey = 'pets_v1';
const _firstLaunchIntroAutoEnabledKey = 'first_launch_intro_auto_enabled_v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
  });

  testWidgets('me page shows AI settings section', (tester) async {
    final settingsController = await AppSettingsController.load();
    final appLogController = AppLogController.memory();
    appLogController.info(
      category: AppLogCategory.ai,
      title: 'AI 测试',
      message: '最近一次 API 测试成功。',
    );
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async => AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'data': [
                {'id': 'gpt-5.4'},
              ],
            }),
          ),
        ),
      ),
    );
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
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
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
            appLogController: appLogController,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('me_ai_config_entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('me_notification_entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('me_data_backup_entry')), findsOneWidget);
  });

  testWidgets('me page entry buttons keep unified sizing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final appLogController = AppLogController.memory();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async => AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'data': [
                {'id': 'gpt-5.4'},
              ],
            }),
          ),
        ),
      ),
    );
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
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
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
            appLogController: appLogController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aiEntry = find.byKey(const ValueKey('me_ai_config_entry'));
    final notificationEntry =
        find.byKey(const ValueKey('me_notification_entry'));
    final dataBackupEntry = find.byKey(const ValueKey('me_data_backup_entry'));

    expect(aiEntry, findsOneWidget);
    expect(notificationEntry, findsOneWidget);
    expect(dataBackupEntry, findsOneWidget);

    final baselineHeight = tester.getSize(aiEntry).height;
    expect(
      baselineHeight,
      closeTo(tester.getSize(notificationEntry).height, 0.1),
    );
    expect(
      baselineHeight,
      closeTo(tester.getSize(dataBackupEntry).height, 0.1),
    );
  });

  testWidgets('notification section shows granted badge after authorization',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.authorized,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_request_notification_button')),
        findsNothing);
    final badgeFinder =
        find.byKey(const ValueKey('me_notification_permission_badge'));
    final openSettingsFinder =
        find.byKey(const ValueKey('me_open_notification_settings_button'));

    expect(badgeFinder, findsOneWidget);
    expect(find.text('已授权'), findsOneWidget);
    expect(find.text('待办和提醒会按系统通知展示。'), findsNothing);
    expect(openSettingsFinder, findsOneWidget);

    expect(
      tester.getSize(badgeFinder).height,
      closeTo(tester.getSize(openSettingsFinder).height, 0.1),
    );
  });

  testWidgets('notification section granted badge keeps details in list rows',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.authorized,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.text('已授权'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    final badgeFinder =
        find.byKey(const ValueKey('me_notification_permission_badge'));
    final badgeCenter = tester.getCenter(badgeFinder);
    final textRect = tester.getRect(find.text('已授权'));
    final centeredText = tester.widget<Text>(find.text('已授权'));
    expect(centeredText.textAlign, TextAlign.center);
    expect((textRect.center.dy - badgeCenter.dy).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('notification section shows provisional granted badge copy',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState:
                NotificationPermissionState.provisional,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_request_notification_button')),
        findsNothing);
    expect(find.byKey(const ValueKey('me_notification_permission_badge')),
        findsOneWidget);
    expect(find.text('已临时授权'), findsOneWidget);
    expect(find.text('当前可静默展示通知。'), findsNothing);
  });

  testWidgets('notification section wraps notification actions on narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.authorized,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_request_notification_button')),
        findsNothing);
    final badgeFinder =
        find.byKey(const ValueKey('me_notification_permission_badge'));
    final openSettingsFinder =
        find.byKey(const ValueKey('me_open_notification_settings_button'));

    expect(badgeFinder, findsOneWidget);
    expect(openSettingsFinder, findsOneWidget);
    expect(
      tester.getTopLeft(openSettingsFinder).dy,
      greaterThan(tester.getTopLeft(badgeFinder).dy),
    );
  });

  testWidgets('notification section keeps request button when not granted',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.denied,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_request_notification_button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('me_notification_permission_badge')),
        findsNothing);
  });

  testWidgets('notification section keeps request button when unsupported',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState:
                NotificationPermissionState.unsupported,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_request_notification_button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('me_notification_permission_badge')),
        findsNothing);
  });

  testWidgets(
      'notification section switches request button copy to open settings',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = _testCoordinator(settingsController);
    final dataStorageCoordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: MePage(
            themePreference: settingsController.themePreference,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState: NotificationPermissionState.denied,
            notificationPushToken: null,
            onRequestNotificationPermission: () async {},
            onOpenNotificationSettings: () async {},
            onOpenExactAlarmSettings: null,
            shouldOpenNotificationSettingsForRequest: true,
            settingsController: settingsController,
            aiSettingsCoordinator: coordinator,
            dataStorageCoordinator: dataStorageCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_settings_section')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '前往系统设置'), findsNothing);
    expect(find.text('前往系统设置'), findsOneWidget);
  });

  testWidgets('can add an AI provider config from the editor flow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async => AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'data': [
                {'id': 'gpt-5.4'},
              ],
            }),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => AiConfigEditorPage(
                        settingsController: settingsController,
                        coordinator: coordinator,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai_config_display_name_field')),
      'OpenAI 主账号',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_model_field')),
      'gpt-5.4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_api_key_field')),
      'sk-live-demo',
    );
    await tester.tap(find.byKey(const ValueKey('ai_config_save_button')));
    await tester.pumpAndSettle();

    expect(
        settingsController.activeAiProviderConfig?.displayName, 'OpenAI 主账号');
    expect(settingsController.activeAiProviderConfig?.model, 'gpt-5.4');
  });

  testWidgets(
      'provider field uses native picker on iOS and updates default base url',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final picker = _FakeNativeOptionPicker(
      queuedResults: const [
        NativeOptionPickerResult.success(selectedValue: 'anthropic'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
          nativeOptionPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();

    expect(picker.requests, hasLength(1));
    expect(picker.requests.single.selectedValue, 'openai');
    expect(picker.requests.single.options, hasLength(4));
    expect(find.text('Anthropic'), findsOneWidget);
    expect(
      tester
          .widget<HyperTextField>(
            find.byKey(const ValueKey('ai_config_base_url_field')),
          )
          .controller
          .text,
      'https://api.anthropic.com/v1',
    );
  });

  testWidgets(
      'provider field keeps value on iOS when native picker is cancelled',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final picker = _FakeNativeOptionPicker(
      queuedResults: const [NativeOptionPickerResult.cancelled()],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
          nativeOptionPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI'), findsOneWidget);
    expect(
      tester
          .widget<HyperTextField>(
            find.byKey(const ValueKey('ai_config_base_url_field')),
          )
          .controller
          .text,
      'https://api.openai.com/v1',
    );
  });

  testWidgets(
      'provider field shows floating feedback on iOS when native picker is unavailable',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final picker = _FakeNativeOptionPicker(
      queuedResults: const [
        NativeOptionPickerResult.error(
          errorCode: NativeOptionPickerErrorCode.unavailable,
          errorMessage: '当前平台暂未接入原生选项选择器。',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
          nativeOptionPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('ai_settings_feedback_banner')),
        findsOneWidget);
    expect(find.text('当前平台暂未接入原生选项选择器。'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
  });

  testWidgets(
      'saved config test connection shows inline pending state and floating feedback result',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final completer = Completer<AiHttpResponse>();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: secretStore,
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async {
            if (request.uri.toString() ==
                'https://open.bigmodel.cn/api/paas/v4/models') {
              return AiHttpResponse(
                statusCode: 200,
                body: jsonEncode({
                  'data': [
                    {'id': 'glm-4.7'},
                  ],
                }),
              );
            }
            return completer.future;
          },
        ),
      ),
    );
    final createdAt = DateTime.parse('2026-04-11T18:00:00+08:00');
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-test',
        displayName: 'GLM',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.7',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-test', 'sk-glm');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiSettingsPage(
          settingsController: settingsController,
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ai_config_test_button_cfg-test')),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('测试中...'), findsOneWidget);
    expect(find.text('正在测试连接，请稍候。'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_config_testing_indicator_cfg-test')),
        findsOneWidget);

    completer.complete(
      AiHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'choices': [
            {
              'message': {
                'content': '{"status":"ok"}',
              },
            },
          ],
        }),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai_settings_feedback_banner')),
        findsOneWidget);
    expect(
      settingsController.aiProviderConfigs
          .singleWhere((config) => config.id == 'cfg-test')
          .lastConnectionStatus,
      AiConnectionStatus.success,
    );
  });

  testWidgets(
      'editor test connection shows in-card pending state and floating feedback result',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final completer = Completer<AiHttpResponse>();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) => completer.future,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai_config_display_name_field')),
      'GLM',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_model_field')),
      'glm-4.7',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_api_key_field')),
      'sk-glm',
    );

    await tester.tap(find.byKey(const ValueKey('ai_config_test_button')));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('测试中...'), findsOneWidget);
    expect(find.text('正在测试连接，请稍候。'), findsWidgets);
    expect(find.byKey(const ValueKey('ai_config_editor_testing_indicator')),
        findsOneWidget);

    completer.complete(
      AiHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'data': [
            {'id': 'glm-4.7'},
          ],
        }),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai_settings_feedback_banner')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai_config_editor_testing_indicator')),
        findsNothing);
    expect(find.text('测试连接'), findsOneWidget);
  });

  testWidgets(
      'saved config test connection keeps timeout message instead of generic unreachable copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: secretStore,
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async {
            if (request.uri.toString() ==
                'https://open.bigmodel.cn/api/paas/v4/models') {
              return AiHttpResponse(
                statusCode: 200,
                body: jsonEncode({
                  'data': [
                    {'id': 'glm-5.1'},
                  ],
                }),
              );
            }
            if (request.uri.toString() ==
                    'https://open.bigmodel.cn/api/paas/v4/chat/completions' &&
                request.method == 'POST') {
              throw TimeoutException('probe timeout');
            }
            return const AiHttpResponse(statusCode: 404, body: '{}');
          },
        ),
      ),
    );
    final createdAt = DateTime.parse('2026-04-11T18:00:00+08:00');
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-timeout',
        displayName: 'GLM',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-5.1',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-timeout', 'sk-glm');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiSettingsPage(
          settingsController: settingsController,
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai_config_test_button_cfg-timeout')),
      160,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ai_config_test_button_cfg-timeout')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('结构化'), findsWidgets);
    expect(find.text('连接失败，请检查网络和服务地址。'), findsNothing);
    expect(
      settingsController.aiProviderConfigs
          .singleWhere((config) => config.id == 'cfg-timeout')
          .lastConnectionStatus,
      AiConnectionStatus.timeout,
    );
  });

  testWidgets(
      'saved config test connection shows model unavailable for missing bigmodel target',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: secretStore,
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async {
            if (request.uri.toString() ==
                'https://open.bigmodel.cn/api/paas/v4/models') {
              return AiHttpResponse(
                statusCode: 200,
                body: jsonEncode({
                  'data': [
                    {'id': 'glm-4.7'},
                  ],
                }),
              );
            }
            return const AiHttpResponse(statusCode: 404, body: '{}');
          },
        ),
      ),
    );
    final createdAt = DateTime.parse('2026-04-11T18:00:00+08:00');
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-missing-model',
        displayName: 'GLM',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.7-flashx',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-missing-model', 'sk-glm');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiSettingsPage(
          settingsController: settingsController,
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai_config_test_button_cfg-missing-model')),
      160,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ai_config_test_button_cfg-missing-model')),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前模型不可用，请检查模型名称。'), findsWidgets);
    expect(find.text('连接失败，请检查网络和服务地址。'), findsNothing);
    expect(
      settingsController.aiProviderConfigs
          .singleWhere((config) => config.id == 'cfg-missing-model')
          .lastConnectionStatus,
      AiConnectionStatus.modelUnavailable,
    );
  });

  testWidgets('api key field can toggle visibility without clearing input',
      (tester) async {
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final apiKeyField = find.byKey(const ValueKey('ai_config_api_key_field'));
    final visibilityButton =
        find.byKey(const ValueKey('ai_config_api_key_visibility_button'));

    expect(apiKeyField, findsOneWidget);
    expect(visibilityButton, findsOneWidget);
    expect(tester.widget<TextField>(apiKeyField).obscureText, isTrue);
    expect(find.text('请输入 API Key'), findsOneWidget);

    await tester.enterText(apiKeyField, 'sk-live-demo');
    await tester.tap(visibilityButton);
    await tester.pump();

    expect(tester.widget<TextField>(apiKeyField).obscureText, isFalse);
    expect(
      tester.widget<TextField>(apiKeyField).controller?.text,
      'sk-live-demo',
    );

    await tester.ensureVisible(visibilityButton);
    await tester.tap(visibilityButton);
    await tester.pump();

    expect(tester.widget<TextField>(apiKeyField).obscureText, isTrue);
    expect(
      tester.widget<TextField>(apiKeyField).controller?.text,
      'sk-live-demo',
    );
  });

  testWidgets(
      'existing config keeps saved-key placeholder while toggling api key visibility',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final createdAt = DateTime.parse('2026-04-11T18:00:00+08:00');
    final config = AiProviderConfig(
      id: 'cfg-existing',
      displayName: 'OpenAI 主账号',
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      isActive: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
          initialConfig: config,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final apiKeyField = find.byKey(const ValueKey('ai_config_api_key_field'));
    final visibilityButton =
        find.byKey(const ValueKey('ai_config_api_key_visibility_button'));

    expect(apiKeyField, findsOneWidget);
    expect(visibilityButton, findsOneWidget);
    expect(find.text('已保存，留空则保持不变'), findsOneWidget);
    expect(
      tester.widget<TextField>(apiKeyField).controller?.text,
      isEmpty,
    );

    await tester.tap(visibilityButton);
    await tester.pump();

    expect(tester.widget<TextField>(apiKeyField).obscureText, isFalse);
    expect(
      tester.widget<TextField>(apiKeyField).controller?.text,
      isEmpty,
    );
    expect(find.text('已保存，留空则保持不变'), findsOneWidget);
  });

  testWidgets('provider field uses Flutter bottom sheet on Android',
      (tester) async {
    final settingsController = await AppSettingsController.load();
    final picker = _FakeNativeOptionPicker(
      queuedResults: const [
        NativeOptionPickerResult.success(selectedValue: 'anthropic'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
          nativeOptionPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai_provider_bottom_sheet')), findsOneWidget);
    expect(find.text('选择供应商类型'), findsWidgets);
    expect(picker.requests, isEmpty);

    await tester.tap(find.text('Anthropic').last);
    await tester.pumpAndSettle();

    expect(find.text('Anthropic'), findsOneWidget);
    expect(
      tester
          .widget<HyperTextField>(
            find.byKey(const ValueKey('ai_config_base_url_field')),
          )
          .controller
          .text,
      'https://api.anthropic.com/v1',
    );
  });

  testWidgets('provider picker shows Cloudflare Workers AI option on Android',
      (tester) async {
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();

    expect(find.text('Cloudflare Workers AI'), findsOneWidget);

    await tester.tap(find.text('Cloudflare Workers AI').last);
    await tester.pumpAndSettle();

    expect(find.text('Cloudflare Workers AI'), findsOneWidget);
    expect(
      tester
          .widget<HyperTextField>(
            find.byKey(const ValueKey('ai_config_base_url_field')),
          )
          .controller
          .text,
      '',
    );
    expect(find.text('Cloudflare Account ID'), findsOneWidget);
  });

  testWidgets(
      'cloudflare workers ai editor shows account id label when selected',
      (tester) async {
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare Workers AI').last);
    await tester.pumpAndSettle();

    expect(find.text('Cloudflare Account ID'), findsOneWidget);
    expect(find.text('Base URL'), findsNothing);
  });

  testWidgets('cloudflare workers ai saves generated base url from account id',
      (tester) async {
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare Workers AI').last);
    await tester.pumpAndSettle();

    expect(find.text('只需要填写 Cloudflare Account ID，App 会自动拼接官方 Workers AI 地址。'),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ai_config_display_name_field')),
      'Cloudflare Workers AI',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_base_url_field')),
      'demo-account-id',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_model_field')),
      '@cf/meta/llama-3.1-8b-instruct-fast',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai_config_api_key_field')),
      'cf-test-token',
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_config_save_button')));
    await tester.pumpAndSettle();

    expect(
      settingsController.activeAiProviderConfig?.baseUrl,
      cloudflareWorkersAiBaseUrlForAccountId('demo-account-id'),
    );
  });

  testWidgets(
      'switching away from cloudflare replaces account id with next provider default url',
      (tester) async {
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: AiConfigEditorPage(
          settingsController: settingsController,
          coordinator: _testCoordinator(settingsController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare Workers AI').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai_config_base_url_field')),
      'demo-account-id',
    );

    await tester.tap(find.byKey(const ValueKey('ai_config_provider_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<HyperTextField>(
            find.byKey(const ValueKey('ai_config_base_url_field')),
          )
          .controller
          .text,
      'https://api.openai.com/v1',
    );
  });

  testWidgets('settings pages reuse unified action button sizing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: secretStore,
      connectionTester: AiConnectionTester(
        transport: _FakeAiHttpTransport(
          handler: (request) async => AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'data': [
                {'id': 'glm-4.7'},
              ],
            }),
          ),
        ),
      ),
    );
    final createdAt = DateTime.parse('2026-04-11T18:00:00+08:00');
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-1',
        displayName: 'cf',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.7',
        isActive: false,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-2',
        displayName: 'glm',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.7',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-1', 'sk-1');
    await secretStore.writeKey('cfg-2', 'sk-2');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AiSettingsPage(
          settingsController: settingsController,
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = find.byKey(const ValueKey('ai_add_config_button'));
    final setActiveButton = find.byKey(
      const ValueKey('ai_config_activate_button_cfg-1'),
    );
    final testButton = find.byKey(
      const ValueKey('ai_config_test_button_cfg-1'),
    );
    final editButton = find.byKey(
      const ValueKey('ai_config_edit_button_cfg-1'),
    );
    final deleteButton = find.byKey(
      const ValueKey('ai_config_delete_button_cfg-1'),
    );

    expect(addButton, findsOneWidget);
    expect(setActiveButton, findsOneWidget);
    expect(testButton, findsOneWidget);
    expect(editButton, findsOneWidget);
    expect(deleteButton, findsOneWidget);

    final addHeight = tester.getSize(addButton).height;
    final setActiveHeight = tester.getSize(setActiveButton).height;
    final testHeight = tester.getSize(testButton).height;
    final editHeight = tester.getSize(editButton).height;
    final deleteHeight = tester.getSize(deleteButton).height;

    expect(addHeight, closeTo(setActiveHeight, 0.1));
    expect(setActiveHeight, closeTo(testHeight, 0.1));
    expect(testHeight, closeTo(editHeight, 0.1));
    expect(editHeight, closeTo(deleteHeight, 0.1));

    final deleteStyle = tester.widget<OutlinedButton>(deleteButton).style!;
    expect(
      deleteStyle.shape!.resolve({}),
      isA<RoundedRectangleBorder>(),
    );

    await tester.tap(editButton);
    await tester.pumpAndSettle();

    final editorTestButton =
        find.byKey(const ValueKey('ai_config_test_button'));
    final editorSaveButton =
        find.byKey(const ValueKey('ai_config_save_button'));
    expect(editorTestButton, findsOneWidget);
    expect(editorSaveButton, findsOneWidget);
    expect(
      tester.getSize(editorTestButton).height,
      closeTo(tester.getSize(editorSaveButton).height, 0.1),
    );
  });
}

AiSettingsCoordinator _testCoordinator(
    AppSettingsController settingsController) {
  return AiSettingsCoordinator(
    settingsController: settingsController,
    secretStore: InMemoryAiSecretStore(),
    connectionTester: AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'data': [
              {'id': 'gpt-5.4'},
            ],
          }),
        ),
      ),
    ),
  );
}

class _FakeNativeOptionPicker implements NativeOptionPicker {
  _FakeNativeOptionPicker({
    List<NativeOptionPickerResult> queuedResults = const [],
  }) : _queuedResults = Queue<NativeOptionPickerResult>.from(queuedResults);

  final Queue<NativeOptionPickerResult> _queuedResults;
  final List<NativeOptionPickerRequest> requests =
      <NativeOptionPickerRequest>[];

  @override
  Future<NativeOptionPickerResult> pickSingleOption(
    NativeOptionPickerRequest request,
  ) async {
    requests.add(request);
    if (_queuedResults.isEmpty) {
      return const NativeOptionPickerResult.cancelled();
    }
    return _queuedResults.removeFirst();
  }
}

class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport({required this.handler});

  final Future<AiHttpResponse> Function(AiHttpRequest request) handler;

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) => handler(request);
}

Map<String, Object> _persistedSinglePetPreferences() {
  return {
    _firstLaunchIntroAutoEnabledKey: false,
    _petsStorageKey: jsonEncode([
      {
        'id': 'pet-1',
        'name': 'Luna',
        'avatarText': 'LU',
        'type': 'cat',
        'breed': '英短',
        'sex': '母',
        'birthday': '2024-01-15',
        'ageLabel': '新加入',
        'weightKg': 4.2,
        'neuterStatus': 'neutered',
        'feedingPreferences': '未填写',
        'allergies': '未填写',
        'note': '未填写',
      },
    ]),
  };
}
