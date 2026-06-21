import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android rtc permissions, sdk dependency, and bridge registration exist',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final appBuildGradle = File('android/app/build.gradle').readAsStringSync();
    final proguardRules =
        File('android/app/proguard-rules.pro').readAsStringSync();
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
    expect(manifest, contains('android:extractNativeLibs="true"'));
    expect(rootBuildGradle,
        contains('https://maven.aliyun.com/repository/public'));
    expect(
        settingsGradle, contains('https://maven.aliyun.com/repository/public'));
    expect(appBuildGradle, contains('com.ding.rtc:dingrtc-basic:3.9.0'));
    expect(appBuildGradle, contains('proguard-rules.pro'));
    expect(proguardRules, contains('-keep class com.ding.rtc.** { *; }'));
    expect(proguardRules, contains('-keep class org.webrtc.mozi.** { *; }'));
    expect(appBuildGradle, isNot(contains('com.aliyun.aio:AliVCSDK_ARTC')));
    expect(appBuildGradle, contains('targetSdk = 33'));
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
    expect(bridge, contains('requireString(arguments, "singleToken")'));
    expect(bridge, isNot(contains('com.alivc.rtc')));
    expect(bridge, contains('DingRtcEngine.create(context, "")'));
    expect(bridge, contains('DingRtcAuthInfo'));
    expect(bridge, contains('DingRtcVideoTrack.DingRtcVideoTrackCamera'));
    expect(bridge,
        contains('DingRtcMuteLocalAudioMode.DingRtcMuteOnlyMicAudioMode'));
    expect(bridge, contains('createRenderSurfaceView'));
    expect(bridge, contains('setLocalViewConfig'));
    expect(bridge, contains('setRemoteViewConfig'));
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
    expect(bridge, contains('subscribeRemoteVideoStream'));
    expect(bridge, contains('audioTrack: DingRtcAudioTrack'));
    expect(bridge, contains('subscribeAllRemoteAudioStreams'));
    expect(bridge, contains('subscribeAllRemoteVideoStreams'));
    expect(bridge, contains('publishLocalAudioStream(true)'));
    expect(bridge, contains('publishLocalVideoStream(true)'));
    expect(bridge, contains('DingRtcVideoTrack.DingRtcVideoTrackCamera'));
    expect(bridge, contains('DingRtcRenderMode.DingRtcRenderModeCrop'));
    expect(bridge, isNot(contains('DingRtcRenderMode.DingRtcRenderModeAuto')));
    expect(bridge, contains('audioTrack: DingRtcAudioTrack'));
    expect(
        bridge,
        contains(
            'join(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)'));
    expect(bridge, contains('DingRtcVideoEncoderConfiguration'));
    expect(bridge, contains('DingRtcVideoDimensions(width, height)'));
    expect(bridge, contains('width == 1280 && height == 720'));
    expect(bridge, contains('setVideoEncoderConfiguration(config)'));
    expect(bridge, isNot(contains('frameRate')));
    expect(bridge, isNot(contains('fps')));
    expect(
      bridge,
      contains('rtcEngine.joinChannel(authInfo, userName)'),
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
    expect(bridge, contains('"subscribeRemoteVideoStream"'));
    expect(bridge, contains('"setRemoteViewConfig"'));
  });
}
