import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/sync/sync_engine_mode.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

enum DeviceRole { undecided, owner, pet }

enum SyncServerMode { official, custom }

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._({
    required SharedPreferences? preferences,
    AppThemePreference themePreference = AppThemePreference.system,
    bool updateReminderEnabled = true,
    DeviceRole deviceRole = DeviceRole.undecided,
    SyncServerMode syncServerMode = SyncServerMode.official,
    String? syncServerUrl,
    String? householdId,
    String? deviceId,
    String? deviceName,
    String? sharedKeyBase64,
    String? householdAuthToken,
    String? servedPetId,
    SyncEngineMode syncEngineMode = _defaultSyncEngineMode,
    SyncDataPolicy? pendingInitialSyncPolicy,
    String? pendingResetSnapshotSyncId,
    bool petKeepScreenOn = true,
  })  : _preferences = preferences,
        _themePreference = themePreference,
        _updateReminderEnabled = updateReminderEnabled,
        _deviceRole = deviceRole,
        _syncServerMode = syncServerMode,
        _syncServerUrl = syncServerUrl,
        _householdId = householdId,
        _deviceId = deviceId,
        _deviceName = deviceName,
        _sharedKeyBase64 = sharedKeyBase64,
        _householdAuthToken = householdAuthToken,
        _servedPetId = servedPetId,
        _syncEngineMode = syncEngineMode,
        _pendingInitialSyncPolicy = pendingInitialSyncPolicy,
        _pendingResetSnapshotSyncId = pendingResetSnapshotSyncId,
        _petKeepScreenOn = petKeepScreenOn;

  static const String themeModeStorageKey = 'app_theme_mode_v1';
  static const String aiProviderConfigsStorageKey = 'ai_provider_configs_v1';
  static const String activeAiProviderConfigIdStorageKey =
      'active_ai_provider_config_id_v1';
  static const String updateReminderEnabledStorageKey =
      'update_reminder_enabled_v1';
  static const String deviceRoleStorageKey = 'device_role_v1';
  static const String syncServerModeStorageKey = 'sync_server_mode_v1';
  static const String syncServerUrlStorageKey = 'sync_server_url_v1';
  static const String syncHouseholdIdStorageKey = 'sync_household_id_v1';
  static const String deviceIdStorageKey = 'device_id_v1';
  static const String deviceNameStorageKey = 'device_name_v1';
  static const String sharedKeyBase64StorageKey = 'shared_key_base64_v1';
  static const String householdAuthTokenStorageKey =
      'sync_household_auth_token_v1';
  static const String servedPetIdStorageKey = 'served_pet_id_v1';
  static const String syncEngineModeStorageKey = 'sync_engine_mode_v1';
  static const String pendingInitialSyncPolicyStorageKey =
      'pending_initial_sync_policy_v1';
  static const String pendingResetSnapshotSyncIdStorageKey =
      'pending_reset_snapshot_sync_id_v1';
  static const String petKeepScreenOnStorageKey = 'pet_keep_screen_on_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);
  static const SyncEngineMode _defaultSyncEngineMode =
      bool.fromEnvironment('PETNOTE_POWERSYNC_SPIKE')
          ? SyncEngineMode.powersyncSpike
          : SyncEngineMode.legacy;

  final SharedPreferences? _preferences;
  AppThemePreference _themePreference;
  bool _updateReminderEnabled;
  DeviceRole _deviceRole;
  SyncServerMode _syncServerMode;
  String? _syncServerUrl;
  String? _householdId;
  String? _deviceId;
  String? _deviceName;
  String? _sharedKeyBase64;
  String? _householdAuthToken;
  String? _servedPetId;
  SyncEngineMode _syncEngineMode;
  SyncDataPolicy? _pendingInitialSyncPolicy;
  String? _pendingResetSnapshotSyncId;
  bool _petKeepScreenOn;
  final List<AiProviderConfig> _aiProviderConfigs = <AiProviderConfig>[];
  String? _activeAiProviderConfigId;

  AppThemePreference get themePreference => _themePreference;
  bool get updateReminderEnabled => _updateReminderEnabled;
  DeviceRole get deviceRole => _deviceRole;
  SyncServerMode get syncServerMode => _syncServerMode;
  String? get syncServerUrl => _syncServerUrl;
  String? get householdId => _householdId;
  String? get syncHouseholdId => _householdId;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  String? get sharedKeyBase64 => _sharedKeyBase64;
  String? get householdAuthToken => _householdAuthToken;
  String? get servedPetId => _servedPetId;
  SyncEngineMode get syncEngineMode => _syncEngineMode;
  SyncDataPolicy? get pendingInitialSyncPolicy => _pendingInitialSyncPolicy;
  String? get pendingResetSnapshotSyncId => _pendingResetSnapshotSyncId;
  bool get petKeepScreenOn => _petKeepScreenOn;
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
    bool hasExistingLocalData = false,
  }) async {
    final preferences = await _loadPreferences(preferencesLoader);
    final storedTheme = preferences?.getString(themeModeStorageKey);
    final storedConfigs = decodeAiProviderConfigs(
        preferences?.getString(aiProviderConfigsStorageKey));
    final activeConfigId =
        preferences?.getString(activeAiProviderConfigIdStorageKey);
    final storedSyncServerUrl =
        _nonBlank(preferences?.getString(syncServerUrlStorageKey));
    return AppSettingsController._(
      preferences: preferences,
      themePreference: _themePreferenceFromName(storedTheme),
      updateReminderEnabled:
          preferences?.getBool(updateReminderEnabledStorageKey) ?? true,
      deviceRole: resolveLoadedDeviceRole(
        storedRoleName: preferences?.getString(deviceRoleStorageKey),
        hasExistingData: hasExistingLocalData,
      ),
      syncServerMode: _syncServerModeFromName(
        preferences?.getString(syncServerModeStorageKey),
        hasStoredServerUrl: storedSyncServerUrl != null,
      ),
      syncServerUrl: storedSyncServerUrl,
      householdId: _nonBlank(preferences?.getString(syncHouseholdIdStorageKey)),
      deviceId: _nonBlank(preferences?.getString(deviceIdStorageKey)),
      deviceName: _nonBlank(preferences?.getString(deviceNameStorageKey)),
      sharedKeyBase64:
          _nonBlank(preferences?.getString(sharedKeyBase64StorageKey)),
      householdAuthToken:
          _nonBlank(preferences?.getString(householdAuthTokenStorageKey)),
      servedPetId: _nonBlank(preferences?.getString(servedPetIdStorageKey)),
      syncEngineMode: _syncEngineModeFromName(
        preferences?.getString(syncEngineModeStorageKey),
      ),
      pendingInitialSyncPolicy: _syncDataPolicyFromName(
        preferences?.getString(pendingInitialSyncPolicyStorageKey),
      ),
      pendingResetSnapshotSyncId: _nonBlank(
          preferences?.getString(pendingResetSnapshotSyncIdStorageKey)),
      petKeepScreenOn: preferences?.getBool(petKeepScreenOnStorageKey) ?? true,
    ).._restoreAiProviderConfigs(storedConfigs, activeConfigId);
  }

  static DeviceRole resolveLoadedDeviceRole({
    required String? storedRoleName,
    required bool hasExistingData,
  }) {
    final stored = _deviceRoleFromName(storedRoleName);
    if (stored != DeviceRole.undecided) {
      return stored;
    }
    return hasExistingData ? DeviceRole.owner : DeviceRole.undecided;
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

  Future<void> setDeviceRole(DeviceRole value) async {
    if (_deviceRole == value) {
      return;
    }
    _deviceRole = value;
    await _preferences?.setString(deviceRoleStorageKey, value.name);
    notifyListeners();
  }

  Future<void> setSyncServerMode(SyncServerMode value) async {
    if (_syncServerMode == value) {
      return;
    }
    _syncServerMode = value;
    await _preferences?.setString(syncServerModeStorageKey, value.name);
    notifyListeners();
  }

  Future<void> setSyncServerUrl(String? value) async {
    final normalized = _nonBlank(value);
    if (_syncServerUrl == normalized) {
      return;
    }
    _syncServerUrl = normalized;
    await _writeOptionalString(syncServerUrlStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setHouseholdId(String? value) async {
    final normalized = _nonBlank(value);
    if (_householdId == normalized) {
      return;
    }
    _householdId = normalized;
    await _writeOptionalString(syncHouseholdIdStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setDeviceName(String? value) async {
    final normalized = _nonBlank(value);
    if (_deviceName == normalized) {
      return;
    }
    _deviceName = normalized;
    await _writeOptionalString(deviceNameStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setSharedKeyBase64(String? value) async {
    final normalized = _nonBlank(value);
    if (_sharedKeyBase64 == normalized) {
      return;
    }
    _sharedKeyBase64 = normalized;
    await _writeOptionalString(sharedKeyBase64StorageKey, normalized);
    notifyListeners();
  }

  Future<void> setHouseholdAuthToken(String? value) async {
    final normalized = _nonBlank(value);
    if (_householdAuthToken == normalized) {
      return;
    }
    _householdAuthToken = normalized;
    await _writeOptionalString(householdAuthTokenStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setServedPetId(String? value) async {
    final normalized = _nonBlank(value);
    if (_servedPetId == normalized) {
      return;
    }
    _servedPetId = normalized;
    await _writeOptionalString(servedPetIdStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setSyncEngineMode(SyncEngineMode value) async {
    if (_syncEngineMode == value) {
      return;
    }
    _syncEngineMode = value;
    await _preferences?.setString(syncEngineModeStorageKey, value.name);
    notifyListeners();
  }

  Future<void> setPendingInitialSyncPolicy(SyncDataPolicy? value) async {
    if (_pendingInitialSyncPolicy == value) {
      return;
    }
    _pendingInitialSyncPolicy = value;
    await _writeOptionalString(
      pendingInitialSyncPolicyStorageKey,
      value?.name,
    );
    notifyListeners();
  }

  Future<void> setPendingResetSnapshotSyncId(String? value) async {
    final normalized = _nonBlank(value);
    if (_pendingResetSnapshotSyncId == normalized) {
      return;
    }
    _pendingResetSnapshotSyncId = normalized;
    await _writeOptionalString(
        pendingResetSnapshotSyncIdStorageKey, normalized);
    notifyListeners();
  }

  Future<void> setPetKeepScreenOn(bool value) async {
    if (_petKeepScreenOn == value) {
      return;
    }
    _petKeepScreenOn = value;
    await _preferences?.setBool(petKeepScreenOnStorageKey, value);
    notifyListeners();
  }

  Future<String> ensureDeviceId() async {
    final existing = _deviceId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final nextId = _generateDeviceId();
    _deviceId = nextId;
    await _preferences?.setString(deviceIdStorageKey, nextId);
    notifyListeners();
    return nextId;
  }

  Future<void> saveSyncPairing({
    required String serverUrl,
    required String householdId,
    String? sharedKeyBase64,
    String? householdAuthToken,
    String? servedPetId,
    String? deviceName,
    SyncDataPolicy? pendingInitialSyncPolicy,
  }) async {
    _syncServerUrl = _nonBlank(serverUrl);
    _householdId = _nonBlank(householdId);
    _sharedKeyBase64 = _nonBlank(sharedKeyBase64) ?? _sharedKeyBase64;
    _householdAuthToken = _nonBlank(householdAuthToken) ?? _householdAuthToken;
    _servedPetId = _nonBlank(servedPetId);
    _deviceName = _nonBlank(deviceName) ?? _deviceName;
    _pendingInitialSyncPolicy =
        pendingInitialSyncPolicy ?? _pendingInitialSyncPolicy;
    await _writeOptionalString(syncServerUrlStorageKey, _syncServerUrl);
    await _writeOptionalString(syncHouseholdIdStorageKey, _householdId);
    await _writeOptionalString(sharedKeyBase64StorageKey, _sharedKeyBase64);
    await _writeOptionalString(
        householdAuthTokenStorageKey, _householdAuthToken);
    await _writeOptionalString(servedPetIdStorageKey, _servedPetId);
    await _writeOptionalString(deviceNameStorageKey, _deviceName);
    await _writeOptionalString(
      pendingInitialSyncPolicyStorageKey,
      _pendingInitialSyncPolicy?.name,
    );
    notifyListeners();
  }

  Future<void> clearSyncPairing() async {
    _householdId = null;
    _sharedKeyBase64 = null;
    _householdAuthToken = null;
    _servedPetId = null;
    _pendingInitialSyncPolicy = null;
    _pendingResetSnapshotSyncId = null;
    await _preferences?.remove(syncHouseholdIdStorageKey);
    await _preferences?.remove(sharedKeyBase64StorageKey);
    await _preferences?.remove(householdAuthTokenStorageKey);
    await _preferences?.remove(servedPetIdStorageKey);
    await _preferences?.remove(pendingInitialSyncPolicyStorageKey);
    await _preferences?.remove(pendingResetSnapshotSyncIdStorageKey);
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

  Future<void> _writeOptionalString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _preferences?.remove(key);
      return;
    }
    await _preferences?.setString(key, value);
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

DeviceRole _deviceRoleFromName(String? value) => switch (value) {
      'owner' => DeviceRole.owner,
      'pet' => DeviceRole.pet,
      _ => DeviceRole.undecided,
    };

SyncDataPolicy? _syncDataPolicyFromName(String? value) => switch (value) {
      'remoteWins' => SyncDataPolicy.remoteWins,
      'localWins' => SyncDataPolicy.localWins,
      'merge' => SyncDataPolicy.merge,
      _ => null,
    };

SyncServerMode _syncServerModeFromName(
  String? value, {
  required bool hasStoredServerUrl,
}) =>
    switch (value) {
      'custom' => SyncServerMode.custom,
      'official' => SyncServerMode.official,
      _ => hasStoredServerUrl ? SyncServerMode.custom : SyncServerMode.official,
    };

SyncEngineMode _syncEngineModeFromName(String? value) => switch (value) {
      'powersyncSpike' => SyncEngineMode.powersyncSpike,
      'legacy' => SyncEngineMode.legacy,
      _ => AppSettingsController._defaultSyncEngineMode,
    };

String? _nonBlank(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _generateDeviceId() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix = List<int>.generate(6, (_) => random.nextInt(36))
      .map((value) => value.toRadixString(36))
      .join();
  return 'device-$timestamp-$suffix';
}
