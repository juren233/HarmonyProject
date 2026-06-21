import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('RtcCallInvite round trips through sync message payload', () {
    const invite = RtcCallInvite(
      callId: 'call-1',
      mode: RtcCallMode.call,
      callerDeviceId: 'owner-device',
      targetDeviceId: 'pet-device',
      sdp: 'offer-sdp',
    );

    final message = invite.toSyncMessage();
    final parsed = RtcCallSignal.fromSyncMessage(message);

    expect(message.type, SyncMessageTypes.callInvite);
    expect(message.payload['callId'], 'call-1');
    expect(message.payload['mode'], 'call');
    expect(message.payload['callerDeviceId'], 'owner-device');
    expect(message.payload['targetDeviceId'], 'pet-device');
    expect(message.payload['sdp'], 'offer-sdp');
    expect(parsed, isA<RtcCallInvite>());
    expect((parsed as RtcCallInvite).mode, RtcCallMode.call);
    expect(parsed.callerDeviceId, 'owner-device');
  });

  test('RtcCallMediaState round trips through sync message payload', () {
    const state = RtcCallMediaState(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
      cameraEnabled: false,
    );

    final message = state.toSyncMessage();
    final parsed = RtcCallSignal.fromSyncMessage(message);

    expect(message.type, SyncMessageTypes.callMediaState);
    expect(message.payload['callId'], 'call-1');
    expect(message.payload['targetDeviceId'], 'owner-device');
    expect(message.payload['cameraEnabled'], isFalse);
    expect(parsed, isA<RtcCallMediaState>());
    expect((parsed as RtcCallMediaState).cameraEnabled, isFalse);
  });

  test('RtcCallSignal rejects malformed call payloads', () {
    expect(
      () => RtcCallSignal.fromSyncMessage(
        const SyncMessage(SyncMessageTypes.callEnd, {'targetDeviceId': 'pet'}),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
