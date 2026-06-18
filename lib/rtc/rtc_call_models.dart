import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum RtcCallMode {
  call,
  watch;

  static RtcCallMode parse(String value) {
    return RtcCallMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => throw const FormatException('invalid rtc call mode'),
    );
  }
}

sealed class RtcCallSignal {
  const RtcCallSignal({
    required this.callId,
    required this.targetDeviceId,
  });

  final String callId;
  final String targetDeviceId;

  SyncMessage toSyncMessage();

  static RtcCallSignal fromSyncMessage(SyncMessage message) {
    final payload = message.payload;
    final callId = _readRequiredString(payload, 'callId');
    final targetDeviceId = _readRequiredString(payload, 'targetDeviceId');
    return switch (message.type) {
      SyncMessageTypes.callInvite => RtcCallInvite(
          callId: callId,
          mode: RtcCallMode.parse(_readRequiredString(payload, 'mode')),
          callerDeviceId: _readRequiredString(payload, 'callerDeviceId'),
          targetDeviceId: targetDeviceId,
          sdp: _readRequiredString(payload, 'sdp'),
        ),
      SyncMessageTypes.callAnswer => RtcCallAnswer(
          callId: callId,
          targetDeviceId: targetDeviceId,
          sdp: _readRequiredString(payload, 'sdp'),
        ),
      SyncMessageTypes.callReject => RtcCallReject(
          callId: callId,
          targetDeviceId: targetDeviceId,
          reason: _readRequiredString(payload, 'reason'),
        ),
      SyncMessageTypes.callEnd => RtcCallEnd(
          callId: callId,
          targetDeviceId: targetDeviceId,
        ),
      SyncMessageTypes.iceCandidate => RtcIceCandidate(
          callId: callId,
          targetDeviceId: targetDeviceId,
          candidate: _readRequiredMap(payload, 'candidate'),
        ),
      _ => throw const FormatException('not an rtc call signal'),
    };
  }
}

class RtcCallInvite extends RtcCallSignal {
  const RtcCallInvite({
    required super.callId,
    required this.mode,
    required this.callerDeviceId,
    required super.targetDeviceId,
    required this.sdp,
  });

  final RtcCallMode mode;
  final String callerDeviceId;
  final String sdp;

  @override
  SyncMessage toSyncMessage() => SyncMessage(SyncMessageTypes.callInvite, {
        'callId': callId,
        'mode': mode.name,
        'callerDeviceId': callerDeviceId,
        'targetDeviceId': targetDeviceId,
        'sdp': sdp,
      });
}

class RtcCallAnswer extends RtcCallSignal {
  const RtcCallAnswer({
    required super.callId,
    required super.targetDeviceId,
    required this.sdp,
  });

  final String sdp;

  @override
  SyncMessage toSyncMessage() => SyncMessage(SyncMessageTypes.callAnswer, {
        'callId': callId,
        'targetDeviceId': targetDeviceId,
        'sdp': sdp,
      });
}

class RtcCallReject extends RtcCallSignal {
  const RtcCallReject({
    required super.callId,
    required super.targetDeviceId,
    required this.reason,
  });

  final String reason;

  @override
  SyncMessage toSyncMessage() => SyncMessage(SyncMessageTypes.callReject, {
        'callId': callId,
        'targetDeviceId': targetDeviceId,
        'reason': reason,
      });
}

class RtcCallEnd extends RtcCallSignal {
  const RtcCallEnd({
    required super.callId,
    required super.targetDeviceId,
  });

  @override
  SyncMessage toSyncMessage() => SyncMessage(SyncMessageTypes.callEnd, {
        'callId': callId,
        'targetDeviceId': targetDeviceId,
      });
}

class RtcIceCandidate extends RtcCallSignal {
  const RtcIceCandidate({
    required super.callId,
    required super.targetDeviceId,
    required this.candidate,
  });

  final Map<String, dynamic> candidate;

  @override
  SyncMessage toSyncMessage() => SyncMessage(SyncMessageTypes.iceCandidate, {
        'callId': callId,
        'targetDeviceId': targetDeviceId,
        'candidate': candidate,
      });
}

bool isRtcCallMessage(SyncMessage message) {
  return switch (message.type) {
    SyncMessageTypes.callInvite ||
    SyncMessageTypes.callAnswer ||
    SyncMessageTypes.callReject ||
    SyncMessageTypes.callEnd ||
    SyncMessageTypes.iceCandidate =>
      true,
    _ => false,
  };
}

String _readRequiredString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw const FormatException('invalid rtc call payload');
}

Map<String, dynamic> _readRequiredMap(
    Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('invalid rtc call payload');
}
