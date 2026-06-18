import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ios rtc permissions, sdk dependency, and bridge exist', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(infoPlist, contains('NSCameraUsageDescription'));
    expect(infoPlist, contains('NSMicrophoneUsageDescription'));
    expect(podfile, contains("pod 'AliVCSDK_ARTC'"));
    expect(appDelegate, contains('import AliVCSDK_ARTC'));
    expect(appDelegate, contains('import AVFoundation'));
    expect(appDelegate, contains('PetNoteRtcPlugin.register'));
    expect(appDelegate, contains('static let channelName = "petnote/rtc"'));
    expect(appDelegate, contains('getMediaPermissionState'));
    expect(appDelegate, contains('requestMediaPermission'));
    expect(appDelegate, contains('openMediaPermissionSettings'));
    expect(appDelegate,
        contains('AVCaptureDevice.authorizationStatus(for: .video)'));
    expect(appDelegate, contains('AVCaptureDevice.requestAccess(for: .audio)'));
    expect(appDelegate, contains('UIApplication.openSettingsURLString'));
    expect(appDelegate, contains('petnote/rtc_video_view'));
    expect(appDelegate, contains('PetNoteRtcVideoViewFactory'));
    expect(appDelegate, contains('AliRtcEngine.sharedInstance'));
    expect(appDelegate, contains('AliRtcChannelParam'));
    expect(appDelegate, contains('singleToken'));
    expect(appDelegate, contains('remoteUserId'));
    expect(appDelegate, contains('AliVideoCanvas()'));
    expect(appDelegate, contains('setLocalViewConfig'));
    expect(appDelegate, contains('setRemoteViewConfig'));
    expect(appDelegate, contains('startPreview()'));
    expect(appDelegate, contains('AliRtcChannelProfile.interactivelive'));
    expect(appDelegate, contains('AliRtcClientRole.roleInteractive'));
    expect(appDelegate,
        contains('setDefaultSubscribeAllRemoteAudioStreams(true)'));
    expect(appDelegate,
        contains('setDefaultSubscribeAllRemoteVideoStreams(true)'));
    expect(appDelegate, contains('subscribeAllRemoteAudioStreams(true)'));
    expect(appDelegate, contains('subscribeAllRemoteVideoStreams(true)'));
    expect(appDelegate, contains('subscribeRemoteMediaStream'));
    expect(appDelegate, contains('onRemoteTrackAvailableNotify'));
    expect(appDelegate,
        contains('configureVideoEncoder(rtcEngine, arguments: arguments)'));
    expect(appDelegate, contains('width == 1280'));
    expect(appDelegate, contains('height == 720'));
    expect(appDelegate, contains('AliRtcVideoEncoderConfiguration()'));
    expect(appDelegate, contains('config.dimensions = CGSize'));
    expect(appDelegate, contains('CGFloat(width)'));
    expect(appDelegate, contains('CGFloat(height)'));
    expect(appDelegate, contains('setVideoEncoderConfiguration(config)'));
    expect(appDelegate, isNot(contains('frameRate')));
    expect(appDelegate, isNot(contains('fps')));
    expect(appDelegate,
        contains('joinChannel(singleToken, channelParam: channelParam)'));
    expect(appDelegate, contains('publishLocalVideoStream:'));
    expect(appDelegate, contains('publishLocalAudioStream:'));
    expect(appDelegate, contains('AliRtcEngine.destroy()'));
  });
}
