import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('RtcSignalingController sends call lifecycle messages', () async {
    final transport = _FakeSyncTransport();
    final controller = RtcSignalingController(transport: transport);

    controller.sendInvite(
      callId: 'call-1',
      mode: RtcCallMode.watch,
      callerDeviceId: 'owner-device',
      targetDeviceId: 'pet-device',
      sdp: 'offer',
    );
    controller.sendAnswer(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
      sdp: 'answer',
    );
    controller.sendReject(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
      reason: 'busy',
    );
    controller.sendEnd(callId: 'call-1', targetDeviceId: 'pet-device');
    controller.sendIceCandidate(
      callId: 'call-1',
      targetDeviceId: 'pet-device',
      candidate: {'candidate': 'candidate-line'},
    );

    expect(transport.sent.map((message) => message.type), [
      SyncMessageTypes.callInvite,
      SyncMessageTypes.callAnswer,
      SyncMessageTypes.callReject,
      SyncMessageTypes.callEnd,
      SyncMessageTypes.iceCandidate,
    ]);
    expect(transport.sent.first.payload['mode'], 'watch');
    expect(transport.sent.first.payload['callerDeviceId'], 'owner-device');
    expect(transport.sent.last.payload['candidate'],
        {'candidate': 'candidate-line'});
    await controller.dispose();
  });

  test('RtcSignalingController streams only rtc call messages', () async {
    final transport = _FakeSyncTransport();
    final controller = RtcSignalingController(transport: transport);
    final received = <RtcCallSignal>[];
    final subscription = controller.signals.listen(received.add);

    transport.incoming.add(const SyncMessage(SyncMessageTypes.devices, {}));
    transport.incoming.add(const SyncMessage(SyncMessageTypes.callEnd, {
      'callId': 'call-1',
      'targetDeviceId': 'owner-device',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single, isA<RtcCallEnd>());
    await subscription.cancel();
    await controller.dispose();
  });

  test('RtcSignalingController dispose 后不再收发信令', () async {
    final transport = _FakeSyncTransport();
    final controller = RtcSignalingController(transport: transport);
    final received = <RtcCallSignal>[];
    final subscription = controller.signals.listen(received.add);

    await controller.dispose();
    controller.sendEnd(callId: 'call-1', targetDeviceId: 'pet-device');
    transport.incoming.add(const SyncMessage(SyncMessageTypes.callEnd, {
      'callId': 'call-1',
      'targetDeviceId': 'owner-device',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(transport.sent, isEmpty);
    expect(received, isEmpty);
    await subscription.cancel();
  });
}

class _FakeSyncTransport implements SyncTransport {
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();
  final ValueNotifier<SyncConnectionState> stateNotifier =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connected);
  final List<SyncMessage> sent = <SyncMessage>[];

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  ValueListenable<SyncConnectionState> get state => stateNotifier;

  @override
  Future<void> connect() async {}

  @override
  void send(SyncMessage message) => sent.add(message);

  @override
  Future<void> disconnect() async {}
}
