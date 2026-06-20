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
    expect(ohPackage,
        contains('"@aliyun_video_cloud/alivcsdk_artc": "6.11.0-beta"'));
    expect(registrant, contains('PetNoteRtcPlugin'));
    expect(bridge, contains('AliRtcVideoEncoderConfiguration'));
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
    expect(bridge, contains('AliRtcXComponentController'));
    expect(bridge, contains('AliRtcVideoCanvas'));
    expect(bridge, contains('AliRtcRenderMode'));
    expect(bridge, contains('AliRtcVideoTrack'));
    expect(bridge, contains('AliRtcChannelProfile'));
    expect(bridge, contains('AliRtcClientRole'));
    expect(bridge, contains('AliRtcEngineEventListener'));
    expect(bridge,
        contains('setRtcEngineEventListener(this.ensureRtcEventListener())'));
    expect(bridge, contains('onJoinChannel'));
    expect(bridge, contains('onOccurError'));
    expect(bridge, contains('onRemoteUserOnline'));
    expect(bridge, contains('onRemoteTrackAvailableNotify'));
    expect(bridge, contains('onFirstVideoPacketReceived'));
    expect(bridge, contains('onFirstAudioPacketReceived'));
    expect(bridge, contains('onFirstRemoteVideoFrameDrawn'));
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
    expect(bridge, contains('XComponent({'));
    expect(bridge, contains("AliRtcEngine.getInstance('', context)"));
    expect(bridge, contains("this.requireString(call, 'singleToken')"));
    expect(bridge, contains("this.requireString(call, 'channelId')"));
    expect(bridge, contains("this.requireString(call, 'userId')"));
    expect(bridge, contains("this.requireString(call, 'remoteUserId')"));
    expect(bridge, contains('this.configureVideoEncoder(call, engine)'));
    expect(bridge, contains("width !== 1280 || height !== 720"));
    expect(bridge, contains('new AliRtcVideoEncoderConfiguration()'));
    expect(bridge, contains('new AliRtcVideoDimensions()'));
    expect(bridge, contains('dimensions.width = width'));
    expect(bridge, contains('dimensions.height = height'));
    expect(bridge, contains('config.dimensions = dimensions'));
    expect(bridge, contains('engine.setVideoEncoderConfiguration(config)'));
    expect(bridge, isNot(contains('frameRate')));
    expect(bridge, isNot(contains('fps')));
    expect(
        bridge,
        contains(
            'setChannelProfile(AliRtcChannelProfile.AliEngineInteractiveLive)'));
    expect(
        bridge,
        contains(
            'setClientRole(AliRtcClientRole.AliEngineClientRoleInteractive)'));
    expect(bridge, contains('attachLocalView(engine)'));
    expect(bridge, contains('attachRemoteView(engine)'));
    expect(
        bridge,
        contains(
            "engine.joinChannelWithToken(singleToken, '', '', userId)"));
    expect(bridge, contains("this.logResult('joinChannelWithToken'"));
    expect(bridge, contains("this.logResult('publishLocalVideoStream'"));
    expect(bridge, contains("this.logResult('publishLocalAudioStream'"));
    expect(bridge, contains("'subscribeRemoteMediaStream'"));
    expect(bridge, contains("'setRemoteViewConfig'"));
    expect(bridge, contains('publishLocalVideoStream'));
    expect(bridge, contains('publishLocalAudioStream'));
    expect(bridge, contains('subscribeAllRemoteAudioStreams(true)'));
    expect(bridge, contains('subscribeAllRemoteVideoStreams(true)'));
    expect(bridge, contains('subscribeRemoteMediaStream'));
    expect(bridge, contains('setLocalViewConfig'));
    expect(bridge, contains('setRemoteViewConfig'));
    expect(bridge, contains('AliEngineRenderModeAuto'));
    expect(bridge, contains('AliEngineVideoTrackCamera'));
    expect(bridge, contains('enableSpeakerphone'));
    expect(bridge, contains('AliRtcEngine.destroyInstance()'));
    expect(rtcVideoView, contains('HarmonyOhosView'));
    expect(rtcVideoView, contains("targetPlatform.name == 'ohos'"));
    expect(rtcVideoView, contains('creationParams: _creationParams'));
  });
}
