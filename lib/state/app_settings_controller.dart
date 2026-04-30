import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._({
    required SharedPreferences? preferences,
    AppThemePreference themePreference = AppThemePreference.system,
    bool updateReminderEnabled = true,
  })  : _preferences = preferences,
        _themePreference = themePreference,
        _updateReminderEnabled = updateReminderEnabled;

  static const String themeModeStorageKey = 'app_theme_mode_v1';
  static const String aiProviderConfigsStorageKey = 'ai_provider_configs_v1';
  static const String activeAiProviderConfigIdStorageKey =
      'active_ai_provider_config_id_v1';
  static const String updateReminderEnabledStorageKey =
      'update_reminder_enabled_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  final SharedPreferences? _preferences;
  AppThemePreference _themePreference;
  bool _updateReminderEnabled;
  final List<AiProviderConfig> _aiProviderConfigs = <AiProviderConfig>[];
  String? _activeAiProviderConfigId;

  AppThemePreference get themePreference => _themePreference;
  bool get updateReminderEnabled => _updateReminderEnabled;
  String? get activeAiProviderConfigId => _activeAiProviderConfigId;
  List<AiProviderConfig> get aiProviderConfigs =>
      List<AiProviderConfig>.unmodifiable(_aiProviderConfigs);
  AiProviderConfig? get activeAiProviderConfig {
    final activeId = _activeAiProviderConfigId;
    if (activeId == null) {
      return null;
    }
    for (final config in _aiProviderConfigs) {
      if (config.id == activeId) {
        return config;
      }
    }
    return null;
  }

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
    final storedConfigs = decodeAiProviderConfigs(
        preferences?.getString(aiProviderConfigsStorageKey));
    final activeConfigId =
        preferences?.getString(activeAiProviderConfigIdStorageKey);
    return AppSettingsController._(
      preferences: preferences,
      themePreference: _themePreferenceFromName(storedTheme),
      updateReminderEnabled:
          preferences?.getBool(updateReminderEnabledStorageKey) ?? true,
    ).._restoreAiProviderConfigs(storedConfigs, activeConfigId);
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (_themePreference == value) {
      return;
    }
    _themePreference = value;
    await _preferences?.setString(themeModeStorageKey, value.name);
    notifyListeners();
  }

  Future<void> setUpdateReminderEnabled(bool value) async {
    if (_updateReminderEnabled == value) {
      return;
    }
    _updateReminderEnabled = value;
    await _preferences?.setBool(updateReminderEnabledStorageKey, value);
    notifyListeners();
  }

  Future<void> upsertAiProviderConfig(AiProviderConfig value) async {
    final existingIndex =
        _aiProviderConfigs.indexWhere((config) => config.id == value.id);
    final shouldActivate = value.isActive ||
        _activeAiProviderConfigId == value.id ||
        (_activeAiProviderConfigId == null && _aiProviderConfigs.isEmpty);
    final normalized = value.copyWith(
      isActive: shouldActivate,
      updatedAt: value.updatedAt,
    );
    if (existingIndex == -1) {
      _aiProviderConfigs.add(normalized);
    } else {
      _aiProviderConfigs[existingIndex] = normalized;
    }
    if (shouldActivate) {
      _activeAiProviderConfigId = normalized.id;
    }
    _synchronizeActiveFlags();
    await _saveAiProviderState();
    notifyListeners();
  }

  Future<void> setActiveAiProviderConfig(String? configId) async {
    _activeAiProviderConfigId = configId;
    _synchronizeActiveFlags();
    await _saveAiProviderState();
    notifyListeners();
  }

  Future<void> deleteAiProviderConfig(String configId) async {
    _aiProviderConfigs.removeWhere((config) => config.id == configId);
    if (_activeAiProviderConfigId == configId) {
      _activeAiProviderConfigId = null;
    }
    _synchronizeActiveFlags();
    await _saveAiProviderState();
    notifyListeners();
  }

  Future<void> updateAiProviderConnectionStatus({
    required String configId,
    required AiConnectionStatus status,
    required DateTime checkedAt,
    String? message,
  }) async {
    final index =
        _aiProviderConfigs.indexWhere((config) => config.id == configId);
    if (index == -1) {
      return;
    }
    _aiProviderConfigs[index] = _aiProviderConfigs[index].copyWith(
      lastConnectionStatus: status,
      lastConnectionCheckedAt: checkedAt,
      lastConnectionMessage: message,
      updatedAt: checkedAt,
    );
    await _saveAiProviderState();
    notifyListeners();
  }

  PetNoteSettingsState exportNonSensitiveSettings() {
    return PetNoteSettingsState(
      themePreferenceName: _themePreference.name,
      aiProviderConfigs:
          List<AiProviderConfig>.unmodifiable(_aiProviderConfigs),
      activeAiProviderConfigId: _activeAiProviderConfigId,
    );
  }

  Future<void> restoreNonSensitiveSettings(PetNoteSettingsState state) async {
    _themePreference = _themePreferenceFromName(state.themePreferenceName);
    _aiProviderConfigs
      ..clear()
      ..addAll(state.aiProviderConfigs);
    _activeAiProviderConfigId = state.activeAiProviderConfigId;
    _synchronizeActiveFlags();
    await _preferences?.setString(themeModeStorageKey, _themePreference.name);
    await _saveAiProviderState();
    notifyListeners();
  }

  Future<void> resetNonSensitiveSettings() async {
    _themePreference = AppThemePreference.system;
    _updateReminderEnabled = true;
    _aiProviderConfigs.clear();
    _activeAiProviderConfigId = null;
    await _preferences?.setString(themeModeStorageKey, _themePreference.name);
    await _preferences?.setBool(updateReminderEnabledStorageKey, true);
    await _saveAiProviderState();
    notifyListeners();
  }

  void _restoreAiProviderConfigs(
    List<AiProviderConfig> configs,
    String? activeConfigId,
  ) {
    _aiProviderConfigs
      ..clear()
      ..addAll(configs);
    _activeAiProviderConfigId = activeConfigId;
    _synchronizeActiveFlags();
  }

  void _synchronizeActiveFlags() {
    final activeId = _activeAiProviderConfigId;
    for (var index = 0; index < _aiProviderConfigs.length; index++) {
      final config = _aiProviderConfigs[index];
      _aiProviderConfigs[index] =
          config.copyWith(isActive: config.id == activeId);
    }
  }

  Future<void> _saveAiProviderState() async {
    await _preferences?.setString(
      aiProviderConfigsStorageKey,
      jsonEncode(_aiProviderConfigs.map((config) => config.toJson()).toList()),
    );
    final activeId = _activeAiProviderConfigId;
    if (activeId == null || activeId.isEmpty) {
      await _preferences?.remove(activeAiProviderConfigIdStorageKey);
    } else {
      await _preferences?.setString(
          activeAiProviderConfigIdStorageKey, activeId);
    }
  }

  static Future<SharedPreferences?> _loadPreferences(
    Future<SharedPreferences> Function()? preferencesLoader,
  ) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    try {
      return await loader().timeout(_preferencesLoadTimeout);
    } on TimeoutException {
      // App settings can fall back to defaults when preferences time out.
    } catch (_) {
      // App settings can fall back to defaults when preferences are unavailable.
    }
    return null;
  }
}

AppThemePreference _themePreferenceFromName(String? value) => switch (value) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
