import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Android 通知设置页显示更新提醒开关', (tester) async {
    final settingsController = await AppSettingsController.load();

    await _pumpHost(
      tester,
      settingsController: settingsController,
      platformNameOverride: 'android',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('me_notification_entry')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    expect(find.text('更新提醒'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification_update_reminder_toggle')),
      findsOneWidget,
    );
  });

  testWidgets('iOS 通知设置页显示更新提醒开关', (tester) async {
    final settingsController = await AppSettingsController.load();

    await _pumpHost(
      tester,
      settingsController: settingsController,
      platformNameOverride: 'iOS',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('me_notification_entry')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    expect(find.text('更新提醒'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification_update_reminder_toggle')),
      findsOneWidget,
    );
    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(platformView.viewType, 'petnote/ios_update_reminder_switch');
    final gestureRecognizerFactory = platformView.gestureRecognizers!.single;
    final gestureRecognizer = gestureRecognizerFactory.constructor();
    addTearDown(gestureRecognizer.dispose);
    expect(gestureRecognizer, isA<EagerGestureRecognizer>());
    final creationParams =
        platformView.creationParams! as Map<Object?, Object?>;
    expect(creationParams['value'], isTrue);
  });

  testWidgets('Harmony 通知设置页不显示更新提醒开关', (tester) async {
    final settingsController = await AppSettingsController.load();

    await _pumpHost(
      tester,
      settingsController: settingsController,
      platformNameOverride: 'ohos',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('me_notification_entry')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    expect(find.text('更新提醒'), findsNothing);
    expect(
      find.byKey(const ValueKey('notification_update_reminder_toggle')),
      findsNothing,
    );
  });

  testWidgets('点击更新提醒开关会持久化设置', (tester) async {
    final settingsController = await AppSettingsController.load();

    await _pumpHost(
      tester,
      settingsController: settingsController,
      platformNameOverride: 'android',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('me_notification_entry')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('notification_update_reminder_toggle')),
    );
    await tester.pumpAndSettle();

    expect(settingsController.updateReminderEnabled, isFalse);
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required AppSettingsController settingsController,
  String? platformNameOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPetNoteTheme(Brightness.light),
      home: Scaffold(
        body: MePage(
          themePreference: AppThemePreference.system,
          onThemePreferenceChanged: (_) {},
          notificationPermissionState: NotificationPermissionState.unknown,
          notificationPushToken: null,
          onRequestNotificationPermission: null,
          onOpenNotificationSettings: null,
          onOpenExactAlarmSettings: null,
          settingsController: settingsController,
          aiSettingsCoordinator: null,
          dataStorageCoordinator: null,
          platformNameOverride: platformNameOverride,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}
