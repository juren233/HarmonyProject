import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android rtc permissions, sdk dependency, and bridge registration exist',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final appBuildGradle = File('android/app/build.gradle').readAsStringSync();
    final rootBuildGradle = File('android/build.gradle').readAsStringSync();
    final settingsGradle = File('android/settings.gradle').readAsStringSync();
    final mainActivity = File(
            'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt')
        .readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteRtcBridge.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(rootBuildGradle,
        contains('https://maven.aliyun.com/repository/public'));
    expect(
        settingsGradle, contains('https://maven.aliyun.com/repository/public'));
    expect(appBuildGradle, contains('com.aliyun.aio:AliVCSDK_ARTC:7.11.0'));
    expect(mainActivity, contains('rtcBridge'));
    expect(mainActivity, contains('activity = this'));
    expect(
        mainActivity,
        contains(
            'rtcBridge?.handlePermissionResult(requestCode, grantResults)'));
    expect(mainActivity, contains('petnote/rtc_video_view'));
    expect(mainActivity, contains('PetNoteRtcVideoViewFactory'));
    expect(bridge, contains('petnote/rtc'));
    expect(bridge, contains('"getMediaPermissionState"'));
    expect(bridge, contains('"requestMediaPermission"'));
    expect(bridge, contains('"openMediaPermissionSettings"'));
    expect(bridge, contains('Manifest.permission.CAMERA'));
    expect(bridge, contains('Manifest.permission.RECORD_AUDIO'));
    expect(bridge, contains('ActivityCompat.requestPermissions'));
    expect(bridge, contains('requireString(arguments, "channelId")'));
    expect(bridge, contains('AliRtcAuthInfo'));
    expect(bridge, contains('requireString(arguments, "appId")'));
    expect(bridge, contains('requireNullableString(arguments, "nonce")'));
    expect(bridge, contains('requireString(arguments, "role")'));
    expect(bridge, contains('requireLong(arguments, "timestamp")'));
    expect(bridge, contains('requireString(arguments, "token")'));
    expect(bridge, contains('AliRtcVideoTrack.AliRtcVideoTrackCamera'));
    expect(bridge,
        contains('AliRtcMuteLocalAudioMode.AliRtcMuteOnlyMicAudioMode'));
    expect(bridge, contains('createRenderSurfaceView'));
    expect(bridge, contains('setLocalViewConfig'));
    expect(bridge, contains('setRemoteViewConfig'));
    expect(bridge, contains('setRtcEngineNotify(rtcNotify)'));
    expect(bridge, contains('setRtcEngineEventListener(rtcEventListener)'));
    expect(bridge, contains('onJoinChannelResult'));
    expect(bridge, contains('onOccurError'));
    expect(bridge, contains('onRemoteUserOnLineNotify'));
    expect(bridge, contains('onRemoteTrackAvailableNotify'));
    expect(bridge, contains('onFirstVideoPacketReceived'));
    expect(bridge, contains('onFirstAudioPacketReceived'));
    expect(bridge, contains('onFirstRemoteVideoFrameDrawn'));
    expect(bridge, contains('handleRemoteMediaAvailable(uid)'));
    expect(bridge, contains('activeRemoteUserId = uid'));
    expect(
        bridge, contains('return activeRemoteUserId ?: expectedRemoteUserId'));
    expect(bridge, isNot(contains('if (uid != remoteUserId)')));
    expect(bridge, contains('subscribeRemoteMediaStream'));
    expect(bridge, contains('AliRTCSdkInteractiveLive'));
    expect(bridge, contains('AliRTCSdkInteractive'));
    expect(bridge, contains('AliRtcAudioTrack.AliRtcAudioTrackMic'));
    expect(bridge, contains('setDefaultSubscribeAllRemoteAudioStreams'));
    expect(bridge, contains('setDefaultSubscribeAllRemoteVideoStreams'));
    expect(bridge, contains('publishLocalAudioStream(true)'));
    expect(bridge, contains('publishLocalVideoStream(true)'));
    expect(bridge, contains('AliRtcVideoTrack.AliRtcVideoTrackCamera'));
    expect(bridge, contains('AliRtcAudioTrack.AliRtcAudioTrackMic'));
    expect(
        bridge,
        contains(
            'join(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)'));
    expect(bridge, contains('AliRtcVideoEncoderConfiguration'));
    expect(bridge, contains('AliRtcVideoDimensions(width, height)'));
    expect(bridge, contains('width == 1280 && height == 720'));
    expect(bridge, contains('setVideoEncoderConfiguration(config)'));
    expect(bridge, isNot(contains('frameRate')));
    expect(bridge, isNot(contains('fps')));
    expect(
      bridge,
      contains('rtcEngine.joinChannel(authInfo, "")'),
    );
    expect(bridge, isNot(contains('require(joinResult == 0)')));
    expect(bridge, contains('pendingJoinResult'));
    expect(bridge, contains('handleJoinChannelResult(result, channel)'));
    expect(bridge, contains('completeJoinWithError'));
    expect(bridge, contains('joinTimeoutRunnable'));
    expect(bridge, contains('JOIN_TIMEOUT_MS = 15000L'));
    expect(
        bridge, contains('postDelayed(joinTimeoutRunnable, JOIN_TIMEOUT_MS)'));
    expect(bridge, contains('cancelPendingJoin'));
    expect(bridge, contains('resetRtcSession()'));
    expect(bridge, contains('logResult("leaveChannel"'));
    expect(bridge, isNot(contains('.destroy()')));
    expect(bridge, contains('pendingResult.success(null)'));
    expect(bridge, contains('pendingResult.error("rtc_join_failed"'));
    expect(bridge, contains('Log.i(TAG, "join requested'));
    expect(bridge, contains('logResult("publishLocalAudioStream"'));
    expect(bridge, contains('logResult("publishLocalVideoStream"'));
    expect(bridge, contains('"subscribeRemoteMediaStream"'));
    expect(bridge, contains('"setRemoteViewConfig"'));
  });
}
