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
    expect(appDelegate, contains('PetNoteRtcPlugin.register'));
    expect(appDelegate, contains('static let channelName = "petnote/rtc"'));
    expect(appDelegate, contains('AliRtcEngine.sharedInstance'));
    expect(appDelegate, contains('AliRtcChannelParam'));
    expect(appDelegate, contains('singleToken'));
    expect(appDelegate,
        contains('configureVideoEncoder(rtcEngine, arguments: arguments)'));
    expect(appDelegate, contains('width == 1280, height == 720'));
    expect(appDelegate, contains('AliRtcVideoEncoderConfiguration()'));
    expect(appDelegate,
        contains('config.dimensions = CGSize(width: width, height: height)'));
    expect(appDelegate, contains('setVideoEncoderConfiguration(config)'));
    expect(appDelegate, isNot(contains('frameRate')));
    expect(appDelegate, isNot(contains('fps')));
    expect(appDelegate, contains('joinChannel(singleToken, channelParam: channelParam)'));
    expect(appDelegate, contains('publishLocalVideoStream:'));
    expect(appDelegate, contains('publishLocalAudioStream:'));
    expect(appDelegate, contains('AliRtcEngine.destroy()'));
  });
}
