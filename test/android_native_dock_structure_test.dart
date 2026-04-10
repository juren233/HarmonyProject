import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PetNote root routes Android bottom navigation through a native dock host',
      () {
    final source = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source.contains('supportsAndroidLiquidGlassDock('), isTrue);
    expect(source.contains('AndroidLiquidGlassDockHost('), isTrue);
  });

  test('android native dock host file defines a platform view bridge', () {
    final source = File('lib/app/android_native_dock.dart').readAsStringSync();

    expect(source.contains("const _androidLiquidGlassDockViewType = 'petnote/android_liquid_glass_dock'"), isTrue);
    expect(source.contains('class AndroidLiquidGlassDockHost extends StatefulWidget'),
        isTrue);
    expect(source.contains('AndroidView('), isTrue);
    expect(source.contains("MethodChannel('petnote/android_liquid_glass_dock_\$viewId')"),
        isTrue);
  });

  test('android liquid glass dock keeps selection in compose state and uses material icons',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/AndroidLiquidGlassDockFactory.kt',
    ).readAsStringSync();

    expect(source.contains('mutableStateOf('), isTrue);
    expect(source.contains('Icons.Rounded.Checklist'), isTrue);
    expect(source.contains('Icons.Rounded.AutoAwesome'), isTrue);
    expect(source.contains('Icons.Rounded.Add'), isTrue);
    expect(source.contains('Icons.Rounded.Pets'), isTrue);
    expect(source.contains('Icons.Rounded.Person'), isTrue);
  });

  test(
      'android liquid glass dock keeps the add button outside the slider track and adapts its colors for dark mode',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/AndroidLiquidGlassDockFactory.kt',
    ).readAsStringSync();

    expect(source.contains('selectionSlotIndexes = listOf(0, 1, 3, 4)'), isTrue);
    expect(source.contains('LiquidBottomPlaceholderSlot()'), isFalse);
    expect(source.contains('effectContent = {'), isTrue);
    expect(source.contains('LiquidBottomVisualSlot {'), isTrue);
    expect(source.contains('LiquidBottomVisualActionSlot {'), isTrue);
    expect(source.contains('LiquidBottomTab(onClick = {})'), isFalse);
    expect(source.contains('key(isDarkTheme, palette.navBackground, palette.backdropColor)'), isTrue);
    expect(source.contains('key(isDarkTheme, selectedAccentColor, palette.navBackground)'),
        isFalse);
    expect(source.contains('foregroundSlotIndex = 2'), isFalse);
    expect(source.contains('AndroidLiquidGlassAddButton('), isTrue);
    expect(source.contains('Color(0xFF90CE9B)'), isTrue);
    expect(source.contains('Color(0xFF73B87F)'), isTrue);
  });

  test('android liquid glass component animates from a stable current index state',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/AndroidLiquidGlassDockComponents.kt',
    ).readAsStringSync();

    expect(source.contains('remember(selectedTabIndex)'), isFalse);
    expect(source.contains(
            'val selectedIndex = selectedTabIndex().coerceIn(0, normalizedSelectionSlotIndexes.lastIndex)'),
        isTrue);
    expect(source.contains('LaunchedEffect(selectedIndex)'), isTrue);
    expect(source.contains('selectionSlotIndexes: List<Int> = List(tabsCount) { it }'),
        isTrue);
    expect(source.contains('effectContent: @Composable RowScope.() -> Unit = content'),
        isTrue);
    expect(source.contains('nearestSelectionIndexForValue('), isTrue);
  });

  test('android liquid glass component keeps the slider above the track and only the add button in the foreground',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/AndroidLiquidGlassDockComponents.kt',
    ).readAsStringSync();

    expect(source.contains('foregroundSlotIndex: Int? = null,'), isFalse);
    expect(source.contains('foregroundContent: @Composable BoxScope.() -> Unit = {}'),
        isFalse);
    expect(source.contains('fun RowScope.LiquidBottomVisualActionSlot('), isTrue);

    final trackRowIndex = source.indexOf('content = content');
    final effectRowIndex = source.indexOf('content = effectContent');
    final sliderIndex = source.indexOf('.fillMaxWidth(1f / tabsCount)');

    expect(trackRowIndex, greaterThanOrEqualTo(0));
    expect(effectRowIndex, greaterThan(trackRowIndex));
    expect(sliderIndex, greaterThan(effectRowIndex));
  });

  test('android app gradle enables compose and backdrop dependencies', () {
    final source = File('android/app/build.gradle').readAsStringSync();

    expect(source.contains('buildFeatures {'), isTrue);
    expect(source.contains('compose true'), isTrue);
    expect(source.contains("id \"org.jetbrains.kotlin.plugin.compose\""),
        isTrue);
    expect(source.contains('implementation "androidx.compose.foundation:foundation:'),
        isTrue);
    expect(source.contains('implementation "androidx.compose.ui:ui:'),
        isTrue);
    expect(source.contains('implementation "io.github.kyant0:backdrop:1.0.6"'),
        isTrue);
  });

  test('android settings expose the compose compiler plugin', () {
    final source = File('android/settings.gradle').readAsStringSync();

    expect(source.contains('org.jetbrains.kotlin.plugin.compose'), isTrue);
  });

  test('MainActivity registers the Android liquid glass dock factory', () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt',
    ).readAsStringSync();

    expect(source.contains('FlutterFragmentActivity'), isTrue);
    expect(source.contains('AndroidLiquidGlassDockFactory('), isTrue);
    expect(source.contains('registerViewFactory('), isTrue);
    expect(source.contains('"petnote/android_liquid_glass_dock"'), isTrue);
  });
}
