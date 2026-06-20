import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android registers interaction haptics bridge with rich fallbacks', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt',
    ).readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteInteractionHapticsBridge.kt',
    ).readAsStringSync();

    expect(mainActivity.contains('PetNoteInteractionHapticsBridge?'), isTrue);
    expect(mainActivity.contains('PetNoteInteractionHapticsBridge('), isTrue);
    expect(bridge.contains('"petnote/interaction_haptics"'), isTrue);
    expect(bridge.contains('playDeleteHoldRamp'), isTrue);
    expect(bridge.contains('stopDeleteHoldRamp'), isTrue);
    expect(bridge.contains('playDeleteConfirmImpact'), isTrue);
    expect(
      bridge.indexOf('hasAmplitudeControl()'),
      lessThan(bridge.indexOf('supportsRampPrimitives(vibrator)')),
    );
    expect(bridge.contains('.startComposition()'), isTrue);
    expect(bridge.contains('VibrationEffect.createWaveform'), isTrue);
    expect(bridge.contains('hasAmplitudeControl()'), isTrue);
    expect(bridge.contains('vibrator?.cancel()'), isTrue);
  });

  test('iOS interaction haptics plugin uses Core Haptics ramp and impact', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source.contains('PetNoteInteractionHapticsPlugin'), isTrue);
    expect(source.contains('"petnote/interaction_haptics"'), isTrue);
    expect(source.contains('makeDeleteHoldRampPattern'), isTrue);
    expect(source.contains('hapticContinuous'), isTrue);
    expect(source.contains('CHHapticParameterCurve'), isTrue);
    expect(source.contains('makeDeleteConfirmImpactPattern'), isTrue);
    expect(source.contains('hapticTransient'), isTrue);
    expect(
        source.contains('UIImpactFeedbackGenerator(style: .medium)'), isTrue);
  });

  test('Harmony interaction haptics plugin is registered and tracked', () {
    final registrant = File(
      'ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets',
    ).readAsStringSync();
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/PetNoteInteractionHapticsPlugin.ets',
    ).readAsStringSync();
    final module = File('ohos/entry/src/main/module.json5').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(
      registrant.contains(
          "import PetNoteInteractionHapticsPlugin from './PetNoteInteractionHapticsPlugin';"),
      isTrue,
    );
    expect(
      registrant.contains(
          'flutterEngine.getPlugins()?.add(new PetNoteInteractionHapticsPlugin());'),
      isTrue,
    );
    expect(plugin.contains("import vibrator from '@ohos.vibrator';"), isTrue);
    expect(
        plugin.contains("const CHANNEL_NAME = 'petnote/interaction_haptics';"),
        isTrue);
    expect(plugin.contains("case 'playDeleteHoldRamp':"), isTrue);
    expect(plugin.contains("case 'stopDeleteHoldRamp':"), isTrue);
    expect(plugin.contains("case 'playDeleteConfirmImpact':"), isTrue);
    expect(plugin.contains('cancelScheduledRamp();'), isTrue);
    expect(plugin.contains('vibrator.stopVibration'), isTrue);
    expect(module.contains('ohos.permission.VIBRATE'), isTrue);
    expect(
      gitignore.contains(
          '!ohos/entry/src/main/ets/plugins/PetNoteInteractionHapticsPlugin.ets'),
      isTrue,
    );
  });
}
