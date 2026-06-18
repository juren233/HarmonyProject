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
    expect(bridge, contains('AliRtcAuthInfo'));
    expect(bridge, contains('AliRtcVideoTrack.AliRtcVideoTrackCamera'));
    expect(bridge,
        contains('AliRtcMuteLocalAudioMode.AliRtcMuteOnlyMicAudioMode'));
    expect(bridge, contains('createRenderSurfaceView'));
    expect(bridge, contains('setLocalViewConfig'));
    expect(bridge, contains('setRemoteViewConfig'));
    expect(bridge, contains('subscribeRemoteMediaStream'));
    expect(bridge, contains('AliRTCSdkInteractiveLive'));
    expect(bridge, contains('AliRTCSdkInteractive'));
    expect(bridge, contains('AliRtcAudioTrack.AliRtcAudioTrackMic'));
    expect(bridge, contains('setDefaultSubscribeAllRemoteAudioStreams'));
    expect(bridge, contains('setDefaultSubscribeAllRemoteVideoStreams'));
    expect(bridge, contains('publishLocalAudioStream(true)'));
    expect(bridge, contains('publishLocalVideoStream(true)'));
    expect(bridge,
        contains('join(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())'));
    expect(bridge, contains('AliRtcVideoEncoderConfiguration'));
    expect(bridge, contains('AliRtcVideoDimensions(width, height)'));
    expect(bridge, contains('width == 1280 && height == 720'));
    expect(bridge, contains('setVideoEncoderConfiguration(config)'));
    expect(bridge, isNot(contains('frameRate')));
    expect(bridge, isNot(contains('fps')));
    expect(bridge, contains('rtcEngine.joinChannel(authInfo, null)'));
  });
}
