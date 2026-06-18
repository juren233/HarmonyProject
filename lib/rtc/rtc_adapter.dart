class RtcJoinConfig {
  const RtcJoinConfig({
    required this.appId,
    required this.channelId,
    required this.userId,
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
  final String token;
  final String singleToken;
  final String nonce;
  final int timestamp;
  final List<String> gslb;
  Map<String, Object?> toJson() => {
        'appId': appId,
        'channelId': channelId,
        'userId': userId,
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

  Future<void> join(RtcJoinConfig config);

  Future<void> leave();

  Future<void> toggleCamera({required bool enabled});

  Future<void> toggleMicrophone({required bool enabled});

  Future<void> toggleSpeaker({required bool enabled});

  Future<void> switchCamera();

  Future<void> dispose();
}
