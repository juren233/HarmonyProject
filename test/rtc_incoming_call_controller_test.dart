import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_incoming_call_controller.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('RtcIncomingCallController 自动接听 call_invite 并进入通话', () async {
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final startedCalls = <RtcCallInvite>[];
    final controller = RtcIncomingCallController(
      signalingController: signaling,
      localDeviceId: 'pet-device',
      onStartCall: startedCalls.add,
    );
    addTearDown(controller.dispose);

    transport.incoming.add(const SyncMessage(SyncMessageTypes.callInvite, {
      'callId': 'call-1',
      'mode': 'call',
      'callerDeviceId': 'owner-device',
      'targetDeviceId': 'pet-device',
      'sdp': 'offer',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(startedCalls, hasLength(1));
    expect(startedCalls.single.callId, 'call-1');
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.type, SyncMessageTypes.callAnswer);
    expect(transport.sent.single.payload['callId'], 'call-1');
    expect(transport.sent.single.payload['targetDeviceId'], 'owner-device');
  });

  test('RtcIncomingCallController dispose 后不再处理来电', () async {
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final startedCalls = <RtcCallInvite>[];
    final controller = RtcIncomingCallController(
      signalingController: signaling,
      localDeviceId: 'pet-device',
      onStartCall: startedCalls.add,
    );
    await controller.dispose();

    transport.incoming.add(const SyncMessage(SyncMessageTypes.callInvite, {
      'callId': 'call-1',
      'mode': 'call',
      'callerDeviceId': 'owner-device',
      'targetDeviceId': 'pet-device',
      'sdp': 'offer',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(startedCalls, isEmpty);
    expect(transport.sent, isEmpty);
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
