import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PetNote root routes Harmony bottom navigation through native dock host',
      () {
    final source = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source.contains("import 'package:petnote/app/harmony_native_dock.dart';"),
        isTrue);
    expect(source.contains('supportsHarmonyNativeDock('), isTrue);
    expect(source.contains('HarmonyNativeDockHost('), isTrue);
  });

  test('Harmony native dock host file defines an Ohos platform view bridge', () {
    final source = File('lib/app/harmony_native_dock.dart').readAsStringSync();

    expect(source.contains("const _harmonyNativeDockViewType = 'petnote/harmony_native_dock'"),
        isTrue);
    expect(source.contains('class HarmonyNativeDockHost extends StatefulWidget'),
        isTrue);
    expect(source.contains('OhosView('), isTrue);
    expect(source.contains("MethodChannel('petnote/harmony_native_dock_\$viewId')"),
        isTrue);
    expect(source.contains("'setSelectedTab'"), isTrue);
    expect(source.contains("'setBrightness'"), isTrue);
  });

  test('Harmony native dock plugin registers the platform view factory', () {
    final registrant = File(
      'ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets',
    ).readAsStringSync();
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    expect(registrant.contains('PetNoteHarmonyNativeDockPlugin'), isTrue);
    expect(source.contains('PetNoteHarmonyNativeDockPlugin'), isTrue);
    expect(source.contains("const VIEW_TYPE = 'petnote/harmony_native_dock'"),
        isTrue);
    expect(source.contains('registerViewFactory(VIEW_TYPE,'), isTrue);
  });

  test('Harmony native dock anchors to the window bottom avoid area', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    // The dock must measure the bottom safe area (gesture indicator /
    // 3-button nav bar) from the window itself instead of trusting a
    // hard-coded fallback forwarded over the platform channel.
    expect(source.contains("import { window } from '@kit.ArkUI'"), isTrue);
    expect(source.contains('window.getLastWindow('), isTrue);
    expect(
        source.contains(
            'window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR'),
        isTrue);
    expect(source.contains('window.AvoidAreaType.TYPE_SYSTEM'), isTrue);
    expect(source.contains("'avoidAreaChange'"), isTrue);
    expect(source.contains('px2vp('), isTrue);
    expect(source.contains("'bottomInsetMeasured'"), isTrue);
    // The legacy hard-coded 56vp minimum inset must stay gone.
    expect(source.contains('Math.max(bottomInset, 56)'), isFalse);
    expect(source.contains('buildCenteredAddButton'), isTrue);
  });

  test('Harmony native dock uses the system Tabs component bridged to Flutter', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    // The bar must be the ArkUI system-native Tabs component (not a
    // hand-written Row), driven by a TabsController so Flutter can sync the
    // selection programmatically.
    expect(source.contains('new TabsController()'), isTrue);
    expect(source.contains('Tabs({'), isTrue);
    expect(source.contains('barPosition: BarPosition.End'), isTrue);
    expect(source.contains('TabContent()'), isTrue);
    expect(source.contains('.tabBar(this.buildTabBarItem('), isTrue);
    expect(source.contains('.barOverlap(true)'), isTrue);
    // User taps bridge to Flutter via onTabBarClick (not the echo-prone
    // onChange), and programmatic selection flows through changeIndex.
    expect(source.contains('.onTabBarClick('), isTrue);
    expect(source.contains('this.tabsController.changeIndex('), isTrue);
    expect(source.contains("invokeMethod('tabSelected'"), isTrue);
    expect(source.contains("invokeMethod('addTapped'"), isTrue);
  });

  test('Harmony native dock preserves Flutter tab colors icons and add button styling', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    expect(source.contains("'#F2A65A'"), isTrue);
    expect(source.contains("'#9B84E8'"), isTrue);
    expect(source.contains("'#FFA79B'"), isTrue);
    expect(source.contains("'#A5C6FF'"), isTrue);
    expect(source.contains("'#7E8492'"), isTrue);
    expect(source.contains("'#A1A8B4'"), isTrue);
    expect(source.contains("'#90CE9B'"), isTrue);
    expect(source.contains("'#6AB57A'"), isTrue);
    expect(source.contains("'#73B87F'"), isTrue);
    expect(source.contains("'#528F63'"), isTrue);
    expect(source.contains('const ADD_BUTTON_SIZE = 52'), isTrue);
    expect(source.contains('.width(ADD_BUTTON_SIZE)'), isTrue);
    expect(source.contains('.height(ADD_BUTTON_SIZE)'), isTrue);
    expect(source.contains("Text('+')"), isTrue);
    expect(source.contains('PetNoteMaterialIcons'), isFalse);
    expect(source.contains('font.registerFont({'), isFalse);
    expect(source.contains("\$r('app.media.icon')"), isFalse);
    expect(source.contains("\$r('app.media.ic_tab_checklist')"), isTrue);
    expect(source.contains("\$r('app.media.ic_tab_overview')"), isTrue);
    expect(source.contains("\$r('app.media.ic_tab_pets')"), isTrue);
    expect(source.contains("\$r('app.media.ic_tab_me')"), isTrue);
    expect(source.contains("\$r('app.media.ic_tab_add_placeholder')"), isTrue);
    expect(source.contains('const TAB_BAR_HEIGHT = 78'), isTrue);
    expect(source.contains('.barHeight(TAB_BAR_HEIGHT)'), isTrue);
    // Native bar blur on the system Tabs component, with opaque fallback
    // when the device predates barBackgroundBlurStyle (API < 15).
    expect(source.contains('.barBackgroundBlurStyle('), isTrue);
    expect(source.contains('NATIVE_BLUR_SUPPORTED'), isTrue);
    expect(source.contains('BlurStyle.COMPONENT_THICK'), isTrue);
    expect(source.contains('LIGHT_BLUR_BACKGROUND'), isTrue);
    expect(source.contains('DARK_BLUR_BACKGROUND'), isTrue);
    expect(source.contains('LIGHT_SOLID_BACKGROUND'), isTrue);
    expect(source.contains('DARK_SOLID_BACKGROUND'), isTrue);
    expect(source.contains("label: '爱宠'"), isTrue);

    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_checklist.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_overview.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_pets.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_me.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_add_placeholder.svg').existsSync(), isTrue);
  });
}
