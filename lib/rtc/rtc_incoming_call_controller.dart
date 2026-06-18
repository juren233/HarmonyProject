import 'dart:async';

import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';

class RtcIncomingCallController {
  RtcIncomingCallController({
    required RtcSignalingController signalingController,
    required String localDeviceId,
    required void Function(RtcCallInvite invite) onStartCall,
  })  : _signalingController = signalingController,
        _localDeviceId = localDeviceId,
        _onStartCall = onStartCall {
    _subscription = _signalingController.signals.listen(_handleSignal);
  }

  final RtcSignalingController _signalingController;
  final String _localDeviceId;
  final void Function(RtcCallInvite invite) _onStartCall;
  StreamSubscription<RtcCallSignal>? _subscription;
  final Set<String> _handledCallIds = <String>{};
  bool _isDisposed = false;

  Future<void> dispose() async {
    _isDisposed = true;
    await _subscription?.cancel();
  }

  void _handleSignal(RtcCallSignal signal) {
    if (_isDisposed) {
      return;
    }
    if (signal is! RtcCallInvite ||
        signal.targetDeviceId != _localDeviceId ||
        !_handledCallIds.add(signal.callId)) {
      return;
    }
    _signalingController.sendAnswer(
      callId: signal.callId,
      targetDeviceId: signal.callerDeviceId,
      sdp: 'accepted',
    );
    _onStartCall(signal);
  }
}
