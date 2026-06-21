import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android MainActivity 不在原生层固定竖屏', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest.contains('android:screenOrientation="portrait"'),
      isFalse,
      reason: '宠物端需要横屏，Android 原生入口应允许 Flutter 按角色控制方向。',
    );
  });

  test('Harmony Ability 允许横竖屏旋转', () {
    final moduleJson = File(
      'ohos/entry/src/main/module.json5',
    ).readAsStringSync();

    expect(
      moduleJson.contains('"orientation": "auto_rotation"'),
      isTrue,
      reason: '宠物端需要横屏，Harmony 原生 Ability 应允许旋转。',
    );
  });

  test('iOS 声明竖屏和横屏方向，由 Flutter 按角色锁定', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      infoPlist.contains('<string>UIInterfaceOrientationPortrait</string>'),
      isTrue,
    );
    expect(infoPlist.contains('UIInterfaceOrientationLandscapeLeft'), isTrue);
    expect(infoPlist.contains('UIInterfaceOrientationLandscapeRight'), isTrue);
    expect(
      infoPlist.contains('UIInterfaceOrientationPortraitUpsideDown'),
      isFalse,
    );
  });
}
