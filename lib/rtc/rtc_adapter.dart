import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';

class RtcJoinConfig {
  const RtcJoinConfig({
    required this.appId,
    required this.channelId,
    required this.userId,
    required this.remoteUserId,
    required this.role,
    required this.token,
    required this.singleToken,
    required this.nonce,
    required this.timestamp,
    required this.gslb,
  });

  static const int videoWidth720P = 1280;
  static const int videoHeight720P = 720;

  final String appId;
  final String channelId;
  final String userId;
  final String remoteUserId;
  final String role;
  final String token;
  final String singleToken;
  final String nonce;
  final int timestamp;
  final List<String> gslb;
  Map<String, Object?> toJson() => {
        'appId': appId,
        'channelId': channelId,
        'userId': userId,
        'remoteUserId': remoteUserId,
        'role': role,
        'token': token,
        'singleToken': singleToken,
        'nonce': nonce,
        'timestamp': timestamp,
        'gslb': gslb,
        'videoWidth': videoWidth720P,
        'videoHeight': videoHeight720P,
      };
}

abstract class RtcAdapter {
  Future<void> initialize();

  Future<RtcMediaPermissionState> getMediaPermissionState();

  Future<PermissionRequestOutcome<RtcMediaPermissionState>>
      requestMediaPermission();

  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings();

  Future<void> join(RtcJoinConfig config);

  Future<void> leave();

  Future<void> toggleCamera({required bool enabled});

  Future<void> toggleMicrophone({required bool enabled});

  Future<void> toggleSpeaker({required bool enabled});

  Future<void> switchCamera();

  Future<void> dispose();
}
