import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/rtc/method_channel_rtc_adapter.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannelRtcAdapter 按统一接口调用原生 RTC 方法', () async {
    const channel = MethodChannel('petnote/rtc_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final adapter = MethodChannelRtcAdapter(channel: channel);
    await adapter.initialize();
    await adapter.join(
      RtcJoinConfig(
        appId: 'nml2ycrp',
        channelId: 'petnote-demo',
        userId: 'owner-device',
        remoteUserId: 'pet-device',
        role: 'publisher',
        token: 'signed-token',
        singleToken: 'single-token',
        nonce: 'AK-nonce',
        timestamp: 1710003600,
        gslb: const ['https://rgslb.rtc.aliyuncs.com'],
      ),
    );
    await adapter.toggleMicrophone(enabled: false);
    await adapter.toggleCamera(enabled: false);
    await adapter.toggleSpeaker(enabled: true);
    await adapter.switchCamera();
    await adapter.leave();
    await adapter.dispose();

    expect(calls.map((call) => call.method), [
      'initialize',
      'join',
      'toggleMicrophone',
      'toggleCamera',
      'toggleSpeaker',
      'switchCamera',
      'leave',
      'dispose',
    ]);
    expect(calls[1].arguments, {
      'appId': 'nml2ycrp',
      'channelId': 'petnote-demo',
      'userId': 'owner-device',
      'remoteUserId': 'pet-device',
      'role': 'publisher',
      'token': 'signed-token',
      'singleToken': 'single-token',
      'nonce': 'AK-nonce',
      'timestamp': 1710003600,
      'gslb': ['https://rgslb.rtc.aliyuncs.com'],
      'videoWidth': 1280,
      'videoHeight': 720,
    });
    final joinArguments = calls[1].arguments as Map<Object?, Object?>;
    expect(joinArguments.containsKey('fps'), isFalse);
    expect(joinArguments.containsKey('frameRate'), isFalse);
    expect(joinArguments.containsKey('videoFrameRate'), isFalse);
  });

  test('MethodChannelRtcAdapter 按统一接口调用原生媒体权限方法', () async {
    const channel = MethodChannel('petnote/rtc_permission_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getMediaPermissionState' => 'denied',
        'requestMediaPermission' => <String, Object?>{
            'state': 'authorized',
            'promptHandled': true,
          },
        'openMediaPermissionSettings' => 'opened',
        _ => null,
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final adapter = MethodChannelRtcAdapter(channel: channel);

    expect(await adapter.getMediaPermissionState(),
        RtcMediaPermissionState.denied);
    final requestResult = await adapter.requestMediaPermission();
    expect(requestResult.state, RtcMediaPermissionState.authorized);
    expect(requestResult.promptHandledSystemDialog, isTrue);
    expect(await adapter.openMediaPermissionSettings(),
        RtcMediaSettingsOpenResult.opened);
    expect(calls.map((call) => call.method), [
      'getMediaPermissionState',
      'requestMediaPermission',
      'openMediaPermissionSettings',
    ]);
  });
}
