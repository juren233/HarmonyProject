import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS intro haptics plugin uses Core Haptics continuous playback', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source.contains('import CoreHaptics'), isTrue);
    expect(source.contains('PetNoteIntroHapticsPlugin'), isTrue);
    expect(source.contains('"petnote/intro_haptics"'), isTrue);
    expect(source.contains('hapticContinuous'), isTrue);
    expect(source.contains('CHHapticParameterCurve'), isTrue);
    expect(source.contains('supportsHaptics'), isTrue);
    expect(
        source.contains('parameterID: .hapticIntensity, value: 0.24'), isTrue);
    expect(
        source.contains('parameterID: .hapticSharpness, value: 0.15'), isTrue);
    expect(source.contains('duration: 0.40'), isTrue);
    expect(source.contains('playIntroToOnboardingContinuous'), isTrue);
    expect(source.contains('stopIntroToOnboardingContinuous'), isTrue);
    expect(source.contains('playIntroPrimaryButtonTap'), isTrue);
    expect(source.contains('makeIntroToOnboardingPattern'), isTrue);
  });
}
