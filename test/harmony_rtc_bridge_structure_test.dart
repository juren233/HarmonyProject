import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('harmony rtc permissions and bridge registration exist', () {
    final module = File('ohos/entry/src/main/module.json5').readAsStringSync();
    final ohPackage = File('ohos/entry/oh-package.json5').readAsStringSync();
    final registrant =
        File('ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets')
            .readAsStringSync();
    final bridge = File('ohos/entry/src/main/ets/plugins/PetNoteRtcPlugin.ets')
        .readAsStringSync();
    final rtcVideoView = File('lib/rtc/rtc_video_view.dart').readAsStringSync();

    expect(module, contains('ohos.permission.CAMERA'));
    expect(module, contains('ohos.permission.MICROPHONE'));
    expect(ohPackage, contains('"@dingrtc/dingrtc": "3.5.0"'));
    expect(registrant, contains('PetNoteRtcPlugin'));
    expect(bridge, contains('DingRtcConstants.RtcEngineVideoEncoderConfiguration'));
    expect(bridge, contains('AbilityAware'));
    expect(bridge, contains('abilityAccessCtrl'));
    expect(bridge, contains("'getMediaPermissionState'"));
    expect(bridge, contains("'requestMediaPermission'"));
    expect(bridge, contains("'openMediaPermissionSettings'"));
    expect(bridge, contains("'ohos.permission.CAMERA'"));
    expect(bridge, contains("'ohos.permission.MICROPHONE'"));
    expect(bridge,
        contains('requestPermissionsFromUser(ability.context, permissions)'));
    expect(bridge,
        contains('requestPermissionOnSetting(ability.context, permissions)'));
    expect(bridge, contains("const CHANNEL_NAME = 'petnote/rtc'"));
    expect(
        bridge, contains("const VIDEO_VIEW_TYPE = 'petnote/rtc_video_view'"));
    expect(bridge, contains('DingRtcVideoView'));
    expect(bridge, contains('DingRtcSDK.create(context)'));
    expect(bridge, contains('DingRtcEventListener'));
    expect(bridge, contains('new PetNoteDingRtcEventListener(this)'));
    expect(bridge, contains('setEventListener(this.ensureRtcEventListener())'));
    expect(bridge, contains('onJoinChannelResult'));
    expect(bridge, contains('onOccurError'));
    expect(bridge, contains('onRemoteUserOnLineNotify'));
    expect(bridge, contains('onRemoteTrackAvailableNotify'));
    expect(bridge, contains('private pendingJoinResult: MethodResult | null'));
    expect(bridge, contains('private joinTimeoutId: number = -1'));
    expect(bridge, contains('this.pendingJoinResult = result'));
    expect(bridge, contains('this.scheduleJoinTimeout()'));
    expect(bridge, contains('handleJoinChannelResult'));
    expect(bridge, contains('completeJoinWithError'));
    expect(bridge, contains("'rtc_join_failed'"));
    expect(bridge, contains('join rtc channel timed out'));
    expect(bridge, contains('deferRemoteMediaAvailable(uid)'));
    expect(bridge, contains('handleRemoteMediaAvailable(uid)'));
    expect(bridge, contains('this.activeRemoteUserId = uid'));
    expect(
        bridge,
        contains(
            'this.activeRemoteUserId ?? fallback ?? this.expectedRemoteUserId'));
    expect(bridge, isNot(contains('if (uid !== this.remoteUserId)')));
    expect(bridge, contains('StandardMessageCodec'));
    expect(bridge, contains('PlatformViewFactory'));
    expect(bridge, contains('registerViewFactory'));
    expect(bridge, contains('DingRtcVideoView({'));
    expect(bridge, contains('DingRtcSDK.create(context)'));
    expect(bridge, contains("this.requireString(call, 'token')"));
    expect(bridge, contains("this.requireString(call, 'appId')"));
    expect(bridge, contains("this.requireString(call, 'channelId')"));
    expect(bridge, contains("this.requireString(call, 'userId')"));
    expect(bridge, contains("this.requireString(call, 'remoteUserId')"));
    expect(bridge, contains('this.configureVideoEncoder(call, engine)'));
    expect(bridge, contains("width !== 1280 || height !== 720"));
    expect(bridge, contains(
        'new DingRtcConstants.RtcEngineVideoEncoderConfiguration(width, height)'));
    expect(bridge, contains('engine.setVideoEncoderConfiguration(config)'));
    expect(bridge, isNot(contains('frameRate')));
    expect(bridge, isNot(contains('fps')));
    expect(bridge, contains('attachLocalView(engine)'));
    expect(bridge, contains('attachRemoteView(engine)'));
    expect(bridge, contains('new DingRtcConstants.AuthInfo()'));
    expect(bridge, contains('engine.joinChannel(authInfo, userId)'));
    expect(bridge, contains("this.logResult('joinChannel'"));
    expect(bridge, contains("this.logResult('publishLocalVideoStream'"));
    expect(bridge, contains("this.logResult('publishLocalAudioStream'"));
    expect(bridge, contains("'subscribeRemoteVideoStream'"));
    expect(bridge, contains("'setRemoteViewConfig'"));
    expect(bridge, contains('publishLocalVideoStream'));
    expect(bridge, contains('publishLocalAudioStream'));
    expect(bridge, contains('subscribeAllRemoteAudioStreams(true)'));
    expect(bridge, contains('subscribeAllRemoteVideoStreams(true)'));
    expect(bridge, contains('subscribeRemoteVideoStream'));
    expect(bridge, contains('setLocalViewConfig'));
    expect(bridge, contains('setRemoteViewConfig'));
    expect(bridge, contains('RtcEngineVideoTrackCamera'));
    expect(bridge, contains('enableSpeakerphone'));
    expect(bridge, contains('engine?.release()'));
    expect(bridge, isNot(contains('@aliyun_video_cloud/alivcsdk_artc')));
    expect(bridge, isNot(contains('AliRtc')));
    expect(rtcVideoView, contains('HarmonyOhosView'));
    expect(rtcVideoView, contains("targetPlatform.name == 'ohos'"));
    expect(rtcVideoView, contains('creationParams: _creationParams'));
  });
}
