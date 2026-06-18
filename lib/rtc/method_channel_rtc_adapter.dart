import 'package:flutter/services.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';

class MethodChannelRtcAdapter implements RtcAdapter {
  MethodChannelRtcAdapter({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/rtc';

  final MethodChannel _channel;

  @override
  Future<void> initialize() => _channel.invokeMethod<void>('initialize');

  @override
  Future<RtcMediaPermissionState> getMediaPermissionState() async {
    try {
      final result =
          await _channel.invokeMethod<String>('getMediaPermissionState');
      return rtcMediaPermissionStateFromName(result);
    } on MissingPluginException {
      return RtcMediaPermissionState.unsupported;
    }
  }

  @override
  Future<PermissionRequestOutcome<RtcMediaPermissionState>>
      requestMediaPermission() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'requestMediaPermission',
      );
      return rtcMediaPermissionRequestOutcomeFromResult(result);
    } on MissingPluginException {
      return const PermissionRequestOutcome<RtcMediaPermissionState>(
        state: RtcMediaPermissionState.unsupported,
      );
    }
  }

  @override
  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings() async {
    try {
      final result =
          await _channel.invokeMethod<String>('openMediaPermissionSettings');
      return rtcMediaSettingsOpenResultFromName(result);
    } on MissingPluginException {
      return RtcMediaSettingsOpenResult.unsupported;
    }
  }

  @override
  Future<void> join(RtcJoinConfig config) =>
      _channel.invokeMethod<void>('join', config.toJson());

  @override
  Future<void> leave() => _channel.invokeMethod<void>('leave');

  @override
  Future<void> toggleCamera({required bool enabled}) =>
      _channel.invokeMethod<void>('toggleCamera', {'enabled': enabled});

  @override
  Future<void> toggleMicrophone({required bool enabled}) =>
      _channel.invokeMethod<void>('toggleMicrophone', {'enabled': enabled});

  @override
  Future<void> toggleSpeaker({required bool enabled}) =>
      _channel.invokeMethod<void>('toggleSpeaker', {'enabled': enabled});

  @override
  Future<void> switchCamera() => _channel.invokeMethod<void>('switchCamera');

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}
