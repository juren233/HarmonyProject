import 'package:petnote/permissions/permission_request_gate.dart';

enum RtcMediaPermissionState {
  unknown,
  denied,
  authorized,
  unsupported,
}

enum RtcMediaSettingsOpenResult {
  opened,
  failed,
  unsupported,
}

RtcMediaPermissionState rtcMediaPermissionStateFromName(String? value) {
  return switch (value) {
    'denied' => RtcMediaPermissionState.denied,
    'authorized' => RtcMediaPermissionState.authorized,
    'unsupported' => RtcMediaPermissionState.unsupported,
    _ => RtcMediaPermissionState.unknown,
  };
}

RtcMediaSettingsOpenResult rtcMediaSettingsOpenResultFromName(String? value) {
  return switch (value) {
    'opened' => RtcMediaSettingsOpenResult.opened,
    'failed' => RtcMediaSettingsOpenResult.failed,
    _ => RtcMediaSettingsOpenResult.unsupported,
  };
}

PermissionRequestOutcome<RtcMediaPermissionState>
    rtcMediaPermissionRequestOutcomeFromResult(Object? result) {
  if (result is Map) {
    return PermissionRequestOutcome<RtcMediaPermissionState>(
      state: rtcMediaPermissionStateFromName(result['state'] as String?),
      promptHandledSystemDialog: result['promptHandled'] == true,
    );
  }
  return PermissionRequestOutcome<RtcMediaPermissionState>(
    state: rtcMediaPermissionStateFromName(result as String?),
  );
}
