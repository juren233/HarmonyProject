import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android update reminder switch uses native liquid glass platform view',
      () {
    final source = File('lib/app/me_page.dart').readAsStringSync();

    expect(source, contains("import 'dart:async';"));
    expect(source, contains("import 'package:flutter/gestures.dart';"));
    expect(
        source,
        contains(
            "const _androidLiquidGlassToggleViewType = 'petnote/android_liquid_glass_toggle'"));
    expect(source, contains('PlatformViewLink('));
    expect(source, contains('AndroidViewSurface('));
    expect(source, contains('PlatformViewsService.initSurfaceAndroidView('));
    expect(source, contains('PlatformViewHitTestBehavior.opaque'));
    expect(source, contains('gestureRecognizers:'));
    expect(source, contains('Factory<OneSequenceGestureRecognizer>('));
    expect(source, contains('EagerGestureRecognizer.new'));
    expect(source, contains('Timer? _pendingSelectionCommit;'));
    expect(source, contains('_maybeRequestFirstInteractionPrewarm();'));
    expect(source, contains('MethodChannel('));
    expect(source, contains("'petnote/android_liquid_glass_toggle_\$viewId'"));
    expect(
      source,
      contains('const double _androidLiquidGlassToggleSlotWidth = 112;'),
    );
    expect(
      source,
      contains('const double _androidLiquidGlassToggleSlotHeight = 72;'),
    );
    expect(source, contains('class _UpdateReminderToggleSlot'));
    expect(source, contains('PositionedDirectional('));
    expect(source, contains('RepaintBoundary('));
    expect(source, contains('width: _androidLiquidGlassToggleSlotWidth'));
    expect(source, contains('height: _androidLiquidGlassToggleSlotHeight'));
    expect(source, contains("'setSelected'"));
    expect(source, contains("'selectedChanged'"));
    expect(source, isNot(contains('class _AndroidLiquidGlassSwitch')));
    expect(source, isNot(contains('AnimatedContainer(')));
  });

  test('android registers liquid glass toggle factory', () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('AndroidLiquidGlassToggleFactory('));
    expect(source, contains('"petnote/android_liquid_glass_toggle"'));
  });

  test('native android toggle follows Kyant LiquidToggle structure', () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/AndroidLiquidGlassToggleFactory.kt',
    ).readAsStringSync();

    expect(source, contains('fun AndroidLiquidGlassToggle('));
    expect(
        source, contains('composeView.setOnTouchListener(::onComposeTouch)'));
    expect(
        source,
        contains(
            'private fun onComposeTouch(view: View, event: MotionEvent): Boolean'));
    expect(source, contains('requestParentsDisallowInterceptTouchEvent(true)'));
    expect(source, contains('ViewTreeObserver.OnGlobalLayoutListener'));
    expect(source, contains('"prewarmFirstInteraction" -> {'));
    expect(source, contains('DampedDragAnimation('));
    expect(source,
        contains('lateinit var dampedDragAnimation: DampedDragAnimation'));
    expect(source, contains('val toggleSelection: () -> Unit = {'));
    expect(source, contains('.pointerInput(Unit) {'));
    expect(source, contains('detectTapGestures('));
    expect(source, contains('dampedDragAnimation.updateValue(fraction)'));
    expect(source, isNot(contains('LaunchedEffect(dampedDragAnimation)')));
    expect(source, isNot(contains('snapshotFlow { fraction }')));
    expect(source, contains('Modifier.size(96f.dp, 64f.dp)'));
    expect(source, contains('.size(72f.dp, 48f.dp)'));
    expect(source, isNot(contains('dampedDragAnimation.animateToValue(')));
    expect(source,
        isNot(contains('import androidx.compose.foundation.clickable')));
    expect(source, isNot(contains('MutableInteractionSource')));
    expect(source, isNot(contains('.clickable(')));
    expect(source, isNot(contains('InteractiveHighlight(')));
    expect(source, isNot(contains('interactiveHighlight.gestureModifier')));
    expect(source, isNot(contains('interactiveHighlight.modifier')));
    expect(
        source,
        isNot(contains(
            'else {\n                    fraction = if (selected())')));
    expect(source, contains('pressedScale = 1.5f'));
    expect(source, isNot(contains('drawBackdrop(')));
    expect(source, isNot(contains('rememberCombinedBackdrop(')));
    expect(source, isNot(contains('blur(')));
    expect(source, isNot(contains('lens(')));
    expect(source, isNot(contains('Highlight.Ambient.copy(')));
    expect(source, isNot(contains('InnerShadow(')));
    expect(source, isNot(contains('Shadow(')));
    expect(source, contains('role = Role.Switch'));
    expect(source, contains('LaunchedEffect(prewarmRequestToken)'));
    expect(source, contains('dampedDragAnimation.prewarmReleaseCycle()'));
    expect(
      source,
      contains(
        'toggleableState = if (selected()) ToggleableState.On else ToggleableState.Off',
      ),
    );
    expect(source, contains('contentAlignment = Alignment.Center'));
    final trackGestureIndex =
        source.indexOf('.then(dampedDragAnimation.modifier)');
    final thumbDrawIndex = source.indexOf('.background(Color.White)');
    expect(trackGestureIndex, greaterThanOrEqualTo(0));
    expect(thumbDrawIndex, greaterThanOrEqualTo(0));
    expect(trackGestureIndex, lessThan(thumbDrawIndex));
    expect(source, contains('.size(64f.dp, 28f.dp)'));
    expect(source, contains('.size(40f.dp, 24f.dp)'));
    expect(source, contains('Color(0xFF34C759)'));
    expect(source, contains('Color(0xFF30D158)'));
  });
}
