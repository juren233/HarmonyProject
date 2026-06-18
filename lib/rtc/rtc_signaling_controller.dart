import 'dart:async';

import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class RtcSignalingController {
  RtcSignalingController({required SyncTransport transport})
      : _transport = transport {
    _subscription = _transport.messages.listen(_handleMessage);
  }

  final SyncTransport _transport;
  final StreamController<RtcCallSignal> _signals =
      StreamController<RtcCallSignal>.broadcast();
  StreamSubscription<SyncMessage>? _subscription;
  bool _isDisposed = false;

  Stream<RtcCallSignal> get signals => _signals.stream;

  void sendInvite({
    required String callId,
    required RtcCallMode mode,
    required String callerDeviceId,
    required String targetDeviceId,
    required String sdp,
  }) {
    _send(RtcCallInvite(
      callId: callId,
      mode: mode,
      callerDeviceId: callerDeviceId,
      targetDeviceId: targetDeviceId,
      sdp: sdp,
    ));
  }

  void sendAnswer({
    required String callId,
    required String targetDeviceId,
    required String sdp,
  }) {
    _send(RtcCallAnswer(
      callId: callId,
      targetDeviceId: targetDeviceId,
      sdp: sdp,
    ));
  }

  void sendReject({
    required String callId,
    required String targetDeviceId,
    required String reason,
  }) {
    _send(RtcCallReject(
      callId: callId,
      targetDeviceId: targetDeviceId,
      reason: reason,
    ));
  }

  void sendEnd({
    required String callId,
    required String targetDeviceId,
  }) {
    _send(RtcCallEnd(
      callId: callId,
      targetDeviceId: targetDeviceId,
    ));
  }

  void sendIceCandidate({
    required String callId,
    required String targetDeviceId,
    required Map<String, dynamic> candidate,
  }) {
    _send(RtcIceCandidate(
      callId: callId,
      targetDeviceId: targetDeviceId,
      candidate: candidate,
    ));
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _subscription?.cancel();
    await _signals.close();
  }

  void _send(RtcCallSignal signal) {
    if (_isDisposed) {
      return;
    }
    _transport.send(signal.toSyncMessage());
  }

  void _handleMessage(SyncMessage message) {
    if (_isDisposed) {
      return;
    }
    if (!isRtcCallMessage(message)) {
      return;
    }
    try {
      _signals.add(RtcCallSignal.fromSyncMessage(message));
    } on FormatException {
      return;
    }
  }
}
