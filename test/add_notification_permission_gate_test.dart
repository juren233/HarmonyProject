import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/add_sheet/add_action_sheet_shell.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/notifications/notification_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:petnote/permissions/permission_request_gate.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('未授权通知权限时保存待办会先弹窗并阻止创建', (tester) async {
    final store = PetNoteStore.seeded();
    final adapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);
    await coordinator.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '补货主粮');
    await tester.tap(find.widgetWithText(FilledButton, '保存待办'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsOneWidget);
    expect(adapter.requestPermissionCallCount, 0);
    expect(store.todos.where((todo) => todo.title == '补货主粮'), isEmpty);

    await tester.tap(find.text('暂不授权'));
    await tester.pumpAndSettle();

    expect(store.todos.where((todo) => todo.title == '补货主粮'), isEmpty);
    coordinator.dispose();
  });

  testWidgets('授权成功后保存提醒才会创建提醒', (tester) async {
    final store = PetNoteStore.seeded();
    final adapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
      requestResult: NotificationPermissionState.authorized,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);
    await coordinator.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '年度疫苗');
    await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsOneWidget);
    await tester.tap(find.text('去授权'));
    await tester.pumpAndSettle();

    expect(adapter.requestPermissionCallCount, 1);
    expect(store.reminders.where((reminder) => reminder.title == '年度疫苗'),
        hasLength(1));
    coordinator.dispose();
  });

  testWidgets('去授权会等待通知协调器初始化完成后再请求权限', (tester) async {
    final store = PetNoteStore.seeded();
    final pendingAdapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.unknown,
    );
    final pendingCoordinator = NotificationCoordinator(adapter: pendingAdapter);
    final readyAdapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
      requestResult: NotificationPermissionState.authorized,
    );
    final readyCoordinator = NotificationCoordinator(adapter: readyAdapter);
    await readyCoordinator.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: pendingCoordinator,
            notificationCoordinatorLoader: () async => readyCoordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '等待初始化后授权');
    await tester.tap(find.widgetWithText(FilledButton, '保存待办'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsOneWidget);
    await tester.tap(find.text('去授权'));
    await tester.pumpAndSettle();

    expect(pendingAdapter.requestPermissionCallCount, 0);
    expect(readyAdapter.requestPermissionCallCount, 1);
    expect(
      store.todos.where((todo) => todo.title == '等待初始化后授权'),
      hasLength(1),
    );
    pendingCoordinator.dispose();
    readyCoordinator.dispose();
  });

  testWidgets('通知协调器未就绪时保存会先弹权限弹窗而不是静默无响应', (tester) async {
    final store = PetNoteStore.seeded();
    final pendingAdapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.unknown,
    );
    final pendingCoordinator = NotificationCoordinator(adapter: pendingAdapter);
    final loaderCompleter = Completer<NotificationCoordinator?>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: pendingCoordinator,
            notificationCoordinatorLoader: () => loaderCompleter.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '先弹窗再授权');
    await tester.tap(find.widgetWithText(FilledButton, '保存待办'));
    await tester.pump();

    expect(find.text('需要开启通知权限'), findsOneWidget);
    expect(pendingAdapter.requestPermissionCallCount, 0);
    expect(store.todos.where((todo) => todo.title == '先弹窗再授权'), isEmpty);

    await tester.tap(find.text('暂不授权'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsNothing);
    loaderCompleter.complete(null);
    pendingCoordinator.dispose();
  });

  testWidgets('系统弹窗处理过后保存待办改为引导去设置', (tester) async {
    SharedPreferences.setMockInitialValues({
      NotificationCoordinator.permissionPromptHandledStorageKey: true,
    });
    final store = PetNoteStore.seeded();
    final adapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
    );
    final coordinator = NotificationCoordinator(adapter: adapter);
    await coordinator.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '清洗饮水机');
    await tester.tap(find.widgetWithText(FilledButton, '保存待办'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.textContaining('请前往App设置页手动开启后，再回来保存'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(adapter.requestPermissionCallCount, 0);
    expect(adapter.openSettingsCallCount, 1);
    expect(store.todos.where((todo) => todo.title == '清洗饮水机'), isEmpty);
    coordinator.dispose();
  });

  testWidgets('从设置页返回并完成授权后会自动续上当前保存', (tester) async {
    SharedPreferences.setMockInitialValues({
      NotificationCoordinator.permissionPromptHandledStorageKey: true,
    });
    final store = PetNoteStore.seeded();
    late NotificationCoordinator coordinator;
    late _GateFakeNotificationPlatformAdapter adapter;
    adapter = _GateFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.denied,
      onOpenSettings: () async {
        adapter.permissionState = NotificationPermissionState.authorized;
      },
    );
    coordinator = NotificationCoordinator(adapter: adapter);
    await coordinator.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            notificationCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '设置页返回自动保存');
    await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
    await tester.pumpAndSettle();

    expect(find.text('需要开启通知权限'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(adapter.openSettingsCallCount, 1);
    expect(
      store.reminders.where((reminder) => reminder.title == '设置页返回自动保存'),
      hasLength(1),
    );
    coordinator.dispose();
  });

}

class _GateFakeNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  _GateFakeNotificationPlatformAdapter({
    required this.permissionState,
    this.requestResult,
    this.onOpenSettings,
  });

  NotificationPermissionState permissionState;
  final NotificationPermissionState? requestResult;
  final Future<void> Function()? onOpenSettings;
  int requestPermissionCallCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<void> cancelNotification(String key) async {}

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return const NotificationPlatformCapabilities();
  }

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async => null;

  @override
  Future<NotificationPermissionState> getPermissionState() async =>
      permissionState;

  @override
  Future<bool> hasHandledPermissionPrompt() async => false;

  @override
  Future<bool> hasScheduledNotification(String key) async => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationSettingsOpenResult> openExactAlarmSettings() async {
    return NotificationSettingsOpenResult.opened;
  }

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    openSettingsCallCount += 1;
    await onOpenSettings?.call();
    return NotificationSettingsOpenResult.opened;
  }

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<PermissionRequestOutcome<NotificationPermissionState>>
      requestPermission() async {
    requestPermissionCallCount += 1;
    final outcome = PermissionRequestOutcome<NotificationPermissionState>(
      state: requestResult ?? permissionState,
      promptHandledSystemDialog:
          requestResult == NotificationPermissionState.authorized,
    );
    permissionState = outcome.state;
    return outcome;
  }

  @override
  Future<void> resetScheduledNotifications() async {}

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {}
}
