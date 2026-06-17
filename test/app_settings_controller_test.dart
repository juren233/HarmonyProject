import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system theme mode', () async {
    final controller = await AppSettingsController.load();

    expect(controller.themePreference, AppThemePreference.system);
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.updateReminderEnabled, isTrue);
  });

  test('persists dark theme preference across reload', () async {
    final controller = await AppSettingsController.load();
    await controller.setThemePreference(AppThemePreference.dark);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.themePreference, AppThemePreference.dark);
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('restores light theme preference from storage', () async {
    SharedPreferences.setMockInitialValues({
      AppSettingsController.themeModeStorageKey: 'light',
    });

    final controller = await AppSettingsController.load();

    expect(controller.themePreference, AppThemePreference.light);
    expect(controller.themeMode, ThemeMode.light);
  });

  test('persists update reminder preference across reload', () async {
    final controller = await AppSettingsController.load();

    await controller.setUpdateReminderEnabled(false);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.updateReminderEnabled, isFalse);
  });

  test('reset non-sensitive settings restores update reminder default',
      () async {
    final controller = await AppSettingsController.load();

    await controller.setUpdateReminderEnabled(false);
    await controller.resetNonSensitiveSettings();

    final reloaded = await AppSettingsController.load();
    expect(controller.updateReminderEnabled, isTrue);
    expect(reloaded.updateReminderEnabled, isTrue);
  });

  test('清除配对时同步清除一次性同步状态', () async {
    final controller = await AppSettingsController.load();
    await controller.saveSyncPairing(
      serverUrl: 'wss://sync.example.test',
      householdId: 'house-old',
      sharedKeyBase64: 'shared-key-old',
      householdAuthToken: 'auth-token-old',
      servedPetId: 'pet-old',
      pendingInitialSyncPolicy: SyncDataPolicy.localWins,
    );
    await controller.setPendingResetSnapshotSyncId('reset-old');

    await controller.clearSyncPairing();

    expect(controller.householdId, isNull);
    expect(controller.sharedKeyBase64, isNull);
    expect(controller.householdAuthToken, isNull);
    expect(controller.servedPetId, isNull);
    expect(controller.pendingInitialSyncPolicy, isNull);
    expect(controller.pendingResetSnapshotSyncId, isNull);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.householdId, isNull);
    expect(reloaded.sharedKeyBase64, isNull);
    expect(reloaded.householdAuthToken, isNull);
    expect(reloaded.servedPetId, isNull);
    expect(reloaded.pendingInitialSyncPolicy, isNull);
    expect(reloaded.pendingResetSnapshotSyncId, isNull);
  });
}
