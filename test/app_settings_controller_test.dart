import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system theme mode', () async {
    final controller = await AppSettingsController.load();

    expect(controller.themePreference, AppThemePreference.system);
    expect(controller.themeMode, ThemeMode.system);
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
}
