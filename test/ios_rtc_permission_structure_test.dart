import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ios rtc permissions, sdk dependency, and bridge exist', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(infoPlist, contains('NSCameraUsageDescription'));
    expect(infoPlist, contains('NSMicrophoneUsageDescription'));
    expect(podfile, contains("pod 'DingRTC_iOS'"));
    expect(appDelegate, contains('import DingRTC'));
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
    expect(appDelegate, contains('DingRtcEngine.sharedInstance'));
    expect(appDelegate, contains('DingRtcAuthInfo()'));
    expect(appDelegate, contains('authInfo.appId = appId'));
    expect(appDelegate, contains('authInfo.channelId = channelId'));
    expect(appDelegate, contains('authInfo.userId = userId'));
    expect(appDelegate, contains('authInfo.token = token'));
    expect(appDelegate, contains('authInfo.gslbServer = gslbServer'));
    expect(appDelegate, contains('remoteUserId'));
    expect(appDelegate, contains('DingRtcVideoCanvas()'));
    expect(appDelegate, contains('setLocalViewConfig'));
    expect(appDelegate, contains('setRemoteViewConfig'));
    expect(appDelegate, contains('startPreview()'));
    expect(appDelegate, contains('subscribeAllRemoteAudioStreams(true)'));
    expect(appDelegate, contains('subscribeAllRemoteVideoStreams(false)'));
    expect(appDelegate, contains('subscribeRemoteVideoStream'));
    expect(appDelegate, contains('private var pendingJoinResult: FlutterResult?'));
    expect(appDelegate, contains('private var joinTimeoutWorkItem: DispatchWorkItem?'));
    expect(appDelegate, contains('try join(arguments: arguments, result: result)'));
    expect(appDelegate, contains('scheduleJoinTimeout()'));
    expect(appDelegate, contains('handleJoinChannelResult'));
    expect(appDelegate, contains('completeJoinWithError'));
    expect(appDelegate, contains('rtc_join_failed'));
    expect(appDelegate, contains('join rtc channel timed out'));
    expect(appDelegate, contains('subscribeRemoteMedia(engine, uid: remoteUserId)'));
    expect(appDelegate, contains('subscribeRemoteMedia(engine, uid: uid)'));
    expect(appDelegate, contains('onRemoteTrackAvailableNotify'));
    expect(appDelegate, contains('activeRemoteUserId = uid'));
    expect(appDelegate,
        contains('activeRemoteUserId ?? expectedRemoteUserId'));
    expect(appDelegate, isNot(contains('if uid == remoteUserId')));
    expect(appDelegate, contains('DispatchQueue.main.async'));
    expect(appDelegate,
        contains('configureVideoEncoder(rtcEngine, arguments: arguments)'));
    expect(appDelegate, contains('width == 1280'));
    expect(appDelegate, contains('height == 720'));
    expect(appDelegate, contains('DingRtcVideoEncoderConfiguration()'));
    expect(appDelegate, contains('config.dimensions = CGSize'));
    expect(appDelegate, contains('CGFloat(width)'));
    expect(appDelegate, contains('CGFloat(height)'));
    expect(appDelegate, contains('setVideoEncoderConfiguration(config)'));
    expect(appDelegate, isNot(contains('frameRate')));
    expect(appDelegate, isNot(contains('fps')));
    expect(appDelegate, contains('joinChannel(authInfo'));
    expect(appDelegate, isNot(contains('joinChannel(singleToken')));
    expect(appDelegate, contains('onResultWithUserId'));
    expect(appDelegate, contains('rtcLog("join result'));
    expect(appDelegate, contains('onOccurError'));
    expect(appDelegate, contains('onRemoteUserOnLineNotify'));
    expect(appDelegate, contains('onFirstVideoPacketReceivedWithUid'));
    expect(appDelegate, contains('onFirstAudioPacketReceivedWithUid'));
    expect(appDelegate, contains('onFirstRemoteVideoFrameDrawn'));
    expect(appDelegate, contains('logResult("setRemoteViewConfig"'));
    expect(appDelegate, contains('logResult("subscribeRemoteVideoStream"'));
    expect(appDelegate, contains('logResult("stopPreview"'));
    expect(appDelegate, contains('logResult("leaveChannel"'));
    expect(appDelegate, contains('publishLocalVideoStream:'));
    expect(appDelegate, contains('publishLocalAudioStream:'));
    expect(appDelegate, isNot(contains('AliRtcEngine')));
    expect(appDelegate, isNot(contains('AliRtcAuthInfo')));
    expect(appDelegate, isNot(contains('AliVCSDK_ARTC')));
  });
}
