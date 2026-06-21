import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/system_ui_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OHOS startup policy restores edge-to-edge after immersive pages', () {
    expect(ohosStartupSystemUiPolicy.mode, SystemUiMode.edgeToEdge);
    expect(
      ohosStartupSystemUiPolicy.overlayStyle.statusBarColor,
      const Color(0x00000000),
    );
  });

  test('启动竖屏策略只允许 portraitUp', () {
    expect(appPortraitOrientations, [DeviceOrientation.portraitUp]);
  });

  test('宠物端方向策略允许竖屏和横屏', () {
    expect(petDeviceOrientations, [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });

  test('锁定竖屏策略允许注入方向列表', () async {
    await lockAppToPortrait(orientations: appPortraitOrientations);
  });
}
