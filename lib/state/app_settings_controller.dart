import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._({
    required SharedPreferences? preferences,
    AppThemePreference themePreference = AppThemePreference.system,
  })  : _preferences = preferences,
        _themePreference = themePreference;

  static const String themeModeStorageKey = 'app_theme_mode_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  final SharedPreferences? _preferences;
  AppThemePreference _themePreference;

  AppThemePreference get themePreference => _themePreference;

  ThemeMode get themeMode => switch (_themePreference) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };

  static Future<AppSettingsController> load({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) async {
    final preferences = await _loadPreferences(preferencesLoader);
    final storedTheme = preferences?.getString(themeModeStorageKey);
    return AppSettingsController._(
      preferences: preferences,
      themePreference: _themePreferenceFromName(storedTheme),
    );
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (_themePreference == value) {
      return;
    }
    _themePreference = value;
    await _preferences?.setString(themeModeStorageKey, value.name);
    notifyListeners();
  }

  static Future<SharedPreferences?> _loadPreferences(
    Future<SharedPreferences> Function()? preferencesLoader,
  ) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    try {
      return await loader().timeout(_preferencesLoadTimeout);
    } on TimeoutException catch (error) {
      debugPrint(
          'SharedPreferences timed out during app settings load: $error');
    } catch (error) {
      debugPrint('SharedPreferences unavailable for app settings: $error');
    }
    return null;
  }
}

AppThemePreference _themePreferenceFromName(String? value) => switch (value) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
