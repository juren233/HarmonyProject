import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity registers the Android intro haptics bridge', () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt',
    ).readAsStringSync();

    expect(source.contains('introHapticsBridge: PetNoteIntroHapticsBridge?'),
        isTrue);
    expect(source.contains('PetNoteIntroHapticsBridge('), isTrue);
  });

  test('Android intro haptics bridge supports primitives and waveform fallback',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteIntroHapticsBridge.kt',
    ).readAsStringSync();

    expect(source.contains('"petnote/intro_haptics"'), isTrue);
    expect(source.contains('playIntroLaunchContinuous'), isTrue);
    expect(source.contains('playIntroToOnboardingContinuous'), isTrue);
    expect(source.contains('playIntroPrimaryButtonTap'), isTrue);
    expect(source.contains('.startComposition()'), isTrue);
    expect(
      source.contains('VibrationEffect.Composition.PRIMITIVE_SLOW_RISE'),
      isTrue,
    );
    expect(
      source.contains('VibrationEffect.Composition.PRIMITIVE_QUICK_FALL'),
      isTrue,
    );
    expect(source.contains('VibrationEffect.createWaveform'), isTrue);
    expect(source.contains('arePrimitivesSupported'), isTrue);
    expect(source.contains('vibrator?.cancel()'), isTrue);
    expect(source.contains('Log.'), isFalse);
  });

  test('Android manifest declares vibrate permission for intro haptics', () {
    final source =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      source.contains('android.permission.VIBRATE'),
      isTrue,
    );
  });
}
