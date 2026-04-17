import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
      'notification launch intent switches to checklist and highlights target item',
      (tester) async {
    final store = PetNoteStore.seeded()..setActiveTab(AppTab.me);
    final adapter = _RootFakeNotificationPlatformAdapter(
      initialIntent: const NotificationLaunchIntent(
        payload: NotificationPayload(
          sourceType: NotificationSourceType.todo,
          sourceId: 'todo-1',
          petId: 'pet-1',
          routeTarget: NotificationRouteTarget.checklist,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsWidgets);
    expect(store.activeTab, AppTab.checklist);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 220));
  });

  testWidgets(
      'root does not request notification permission on launch when platform state is unknown',
      (tester) async {
    final store = PetNoteStore.seeded();
    final adapter = _RootFakeNotificationPlatformAdapter(
      permissionState: NotificationPermissionState.unknown,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.requestPermissionCallCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 220));
  });
}

class _RootFakeNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  _RootFakeNotificationPlatformAdapter({
    this.initialIntent,
    this.permissionState = NotificationPermissionState.authorized,
  });

  final NotificationLaunchIntent? initialIntent;
  final NotificationPermissionState permissionState;
  int requestPermissionCallCount = 0;

  @override
  Future<void> cancelNotification(String key) async {}

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<NotificationPermissionState> getPermissionState() async {
    return permissionState;
  }

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async =>
      initialIntent;

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async {
    return const NotificationPlatformCapabilities();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async {
    return NotificationSettingsOpenResult.opened;
  }

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    requestPermissionCallCount += 1;
    return NotificationPermissionState.authorized;
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {}
}
