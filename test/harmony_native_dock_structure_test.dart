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

  test('Harmony native dock uses official HdsTabs floating bottom bar API', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    expect(source.contains("import { hdsMaterial } from '@hms.hds.hdsMaterial'"),
        isTrue);
    expect(source.contains("from '@kit.UIDesignKit'"), isTrue);
    expect(source.contains('HdsTabs({'), isTrue);
    expect(source.contains('.tabBar(() => {'), isFalse);
    expect(source.contains('new BottomTabBarStyle('), isTrue);
    expect(source.contains('.barOverlap(true)'), isTrue);
    expect(source.contains('.barPosition(BarPosition.End)'), isTrue);
    expect(source.contains('.vertical(false)'), isTrue);
    expect(source.contains('.barFloatingStyle({'), isTrue);
    expect(source.contains('miniBarBuilder:'), isFalse);
    expect(source.contains('buildVisibleDockOverlay'), isFalse);
    expect(source.contains('buildCenteredAddButton'), isTrue);
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
    expect(source.contains("label: '爱宠'"), isTrue);

    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_checklist.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_overview.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_pets.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_me.svg').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/resources/base/media/ic_tab_add_placeholder.svg').existsSync(), isTrue);
  });
}
