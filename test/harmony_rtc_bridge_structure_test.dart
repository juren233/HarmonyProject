import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('harmony rtc permissions and bridge registration exist', () {
    final module = File('ohos/entry/src/main/module.json5').readAsStringSync();
    final ohPackage = File('ohos/entry/oh-package.json5').readAsStringSync();
    final registrant =
        File('ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets')
            .readAsStringSync();
    final bridge =
        File('ohos/entry/src/main/ets/plugins/PetNoteRtcPlugin.ets')
            .readAsStringSync();

    expect(module, contains('ohos.permission.CAMERA'));
    expect(module, contains('ohos.permission.MICROPHONE'));
    expect(ohPackage,
        contains('"@aliyun_video_cloud/alivcsdk_artc": "6.11.0-beta"'));
    expect(registrant, contains('PetNoteRtcPlugin'));
    expect(bridge, contains('AliRtcVideoEncoderConfiguration'));
    expect(bridge, contains("const CHANNEL_NAME = 'petnote/rtc'"));
    expect(bridge, contains("AliRtcEngine.getInstance('', context)"));
    expect(bridge, contains("this.requireString(call, 'singleToken')"));
    expect(bridge, contains("this.requireString(call, 'channelId')"));
    expect(bridge, contains("this.requireString(call, 'userId')"));
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
    expect(bridge, contains("engine.joinChannelWithToken(singleToken, channelId, userId, '')"));
    expect(bridge, contains('publishLocalVideoStream'));
    expect(bridge, contains('publishLocalAudioStream'));
    expect(bridge, contains('enableSpeakerphone'));
    expect(bridge, contains('AliRtcEngine.destroyInstance()'));
  });
}
