import 'package:flutter/foundation.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/rtc/method_channel_rtc_adapter.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';

abstract class RtcMediaPermissionCoordinator {
  bool get isInitialized;

  RtcMediaPermissionState get state;

  bool get hasGrantedPermission;

  bool get hasHandledPermissionPrompt;

  bool get shouldOpenSettingsForPermissionRequest;

  Future<void> initialize();

  Future<void> refreshPlatformState();

  Future<RtcMediaPermissionState> requestPermission();

  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings();
}

class DefaultRtcMediaPermissionCoordinator extends ChangeNotifier
    implements RtcMediaPermissionCoordinator {
  DefaultRtcMediaPermissionCoordinator({
    RtcAdapter? adapter,
  }) : _adapter = adapter ?? MethodChannelRtcAdapter() {
    _permissionRequestGate = PermissionRequestGate<RtcMediaPermissionState>(
      promptHandledStorageKey: permissionPromptHandledStorageKey,
      isGranted: _isGrantedPermissionState,
      requestPermission: _adapter.requestMediaPermission,
      openPermissionSettings: () async {
        await _adapter.openMediaPermissionSettings();
      },
    );
  }

  static const String permissionPromptHandledStorageKey =
      'rtc_media_permission_prompt_handled_v1';

  final RtcAdapter _adapter;

  late final PermissionRequestGate<RtcMediaPermissionState>
      _permissionRequestGate;

  bool _initialized = false;
  RtcMediaPermissionState _state = RtcMediaPermissionState.unknown;

  @override
  bool get isInitialized => _initialized;

  @override
  RtcMediaPermissionState get state => _state;

  @override
  bool get hasGrantedPermission => _isGrantedPermissionState(_state);

  @override
  bool get hasHandledPermissionPrompt =>
      _permissionRequestGate.hasHandledPermissionPrompt;

  @override
  bool get shouldOpenSettingsForPermissionRequest =>
      _permissionRequestGate.shouldOpenSettingsForPermissionRequest(_state);

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _permissionRequestGate.load();
    await refreshPlatformState();
    _initialized = true;
  }

  @override
  Future<void> refreshPlatformState() async {
    final previousState = _state;
    try {
      _state = await _adapter.getMediaPermissionState();
    } catch (_) {
      _state = previousState;
    }
    if (_state != previousState) {
      notifyListeners();
    }
  }

  @override
  Future<RtcMediaPermissionState> requestPermission() async {
    final previousState = _state;
    _state = await _permissionRequestGate.requestOrOpenSettings(_state);
    if (_state != previousState ||
        hasGrantedPermission != _isGrantedPermissionState(previousState)) {
      notifyListeners();
    }
    return _state;
  }

  @override
  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings() {
    return _adapter.openMediaPermissionSettings();
  }
}

bool _isGrantedPermissionState(RtcMediaPermissionState state) {
  return state == RtcMediaPermissionState.authorized;
}
