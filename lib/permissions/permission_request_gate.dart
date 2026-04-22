import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionRequestOutcome<T> {
  const PermissionRequestOutcome({
    required this.state,
    this.promptHandledSystemDialog = false,
  });

  final T state;
  final bool promptHandledSystemDialog;
}

class PermissionRequestGate<T> {
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  PermissionRequestGate({
    required this.promptHandledStorageKey,
    required this.isGranted,
    required Future<PermissionRequestOutcome<T>> Function() requestPermission,
    required Future<void> Function() openPermissionSettings,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _requestPermission = requestPermission,
        _openPermissionSettings = openPermissionSettings,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final String promptHandledStorageKey;
  final bool Function(T state) isGranted;
  final Future<PermissionRequestOutcome<T>> Function() _requestPermission;
  final Future<void> Function() _openPermissionSettings;
  final Future<SharedPreferences> Function() _preferencesLoader;

  bool _hasHandledPermissionPrompt = false;

  bool get hasHandledPermissionPrompt => _hasHandledPermissionPrompt;

  bool shouldOpenSettingsForPermissionRequest(T state) {
    return !isGranted(state) && _hasHandledPermissionPrompt;
  }

  Future<void> load() async {
    final preferences = await _loadPreferences();
    if (preferences == null) {
      _hasHandledPermissionPrompt = false;
      return;
    }
    _hasHandledPermissionPrompt =
        preferences.getBool(promptHandledStorageKey) ?? false;
  }

  Future<T> requestOrOpenSettings(T currentState) async {
    if (isGranted(currentState)) {
      return currentState;
    }
    if (shouldOpenSettingsForPermissionRequest(currentState)) {
      await _openPermissionSettings();
      return currentState;
    }
    final outcome = await _requestPermission();
    if (outcome.promptHandledSystemDialog && !_hasHandledPermissionPrompt) {
      _hasHandledPermissionPrompt = true;
      await _persistPromptHandled();
    }
    return outcome.state;
  }

  Future<bool> rememberHandledPromptFromSystem(bool hasHandledPrompt) async {
    if (!hasHandledPrompt || _hasHandledPermissionPrompt) {
      return false;
    }
    _hasHandledPermissionPrompt = true;
    await _persistPromptHandled();
    return true;
  }

  Future<void> _persistPromptHandled() async {
    final preferences = await _loadPreferences();
    if (preferences == null) {
      return;
    }
    await preferences.setBool(promptHandledStorageKey, true);
  }

  Future<SharedPreferences?> _loadPreferences() async {
    try {
      return await _preferencesLoader().timeout(_preferencesLoadTimeout);
    } on TimeoutException catch (error) {
      debugPrint('PermissionRequestGate SharedPreferences timed out: $error');
    } catch (error) {
      debugPrint('PermissionRequestGate SharedPreferences unavailable: $error');
    }
    return null;
  }
}
