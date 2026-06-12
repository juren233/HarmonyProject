import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/me_page.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildMePage(AppSettingsController? settings) {
    return MaterialApp(
      theme: buildPetNoteTheme(Brightness.light),
      home: Scaffold(
        body: MePage(
          themePreference: AppThemePreference.system,
          onThemePreferenceChanged: (_) {},
          notificationPermissionState: NotificationPermissionState.unsupported,
          notificationPushToken: null,
          onRequestNotificationPermission: null,
          onOpenNotificationSettings: null,
          onOpenExactAlarmSettings: null,
          settingsController: settings,
          aiSettingsCoordinator: null,
          dataStorageCoordinator: null,
        ),
      ),
    );
  }

  testWidgets('我的页在主题外观上方显示模式切换', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);

    await tester.pumpWidget(buildMePage(settings));
    await tester.pumpAndSettle();

    final modeCard = find.byKey(const ValueKey('me_device_mode_card'));
    final themeCard = find.byKey(const ValueKey('me_theme_appearance_card'));
    expect(modeCard, findsOneWidget);
    expect(themeCard, findsOneWidget);
    expect(
      tester.getTopLeft(modeCard).dy,
      lessThan(tester.getTopLeft(themeCard).dy),
    );
    expect(
      find.byKey(const ValueKey('me_mode_selected_owner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('me_device_mode_slider_control')),
      findsOneWidget,
    );
  });

  testWidgets('切换宠物模式需确认且取消不改变角色', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);

    await tester.pumpWidget(buildMePage(settings));
    await tester.pumpAndSettle();

    // 点击顶层透明 Slider（与主题滑块一致的交互层）。
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('me_mode_pet'))));
    await tester.pumpAndSettle();

    expect(find.text('切换宠物模式'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(settings.deviceRole, DeviceRole.owner);

    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('me_mode_pet'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('me_mode_confirm_pet')));
    await tester.pumpAndSettle();

    expect(settings.deviceRole, DeviceRole.pet);
    expect(find.byKey(const ValueKey('me_mode_selected_pet')), findsOneWidget);
  });

  testWidgets('无 settingsController 时不显示模式卡片', (tester) async {
    await tester.pumpWidget(buildMePage(null));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('me_device_mode_card')), findsNothing);
  });
}
