import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PetNote root uses a dedicated first-launch transition controller', () {
    final source = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source.contains('enum _OverlayTransition'), isTrue);
    expect(source.contains('enum _OnboardingEntryPoint'), isTrue);
    expect(source.contains('_overlayTransitionController'), isTrue);
    expect(source.contains('_OverlayTransition.introToOnboarding'), isTrue);
    expect(source.contains('_OverlayTransition.introToShell'), isTrue);
    expect(source.contains('_openOnboardingFromIntro'), isTrue);
    expect(source.contains('_dismissFirstLaunchIntro'), isTrue);
    expect(source.contains('_returnToIntroFromOnboarding'), isTrue);
    expect(source.contains('_resetOverlayTransition'), isTrue);
    expect(source.contains("ValueKey('intro_overlay_layer')"), isTrue);
    expect(source.contains("ValueKey('onboarding_overlay_layer')"), isTrue);
    expect(source.contains("ValueKey('intro_shell_exit_opacity')"), isTrue);
    expect(source.contains("ValueKey('intro_shell_exit_motion')"), isTrue);
    expect(source.contains('showBottomNavigationInBody'), isTrue);
    expect(source.contains('bottomNavigationOverlay:'), isTrue);
    expect(source.contains('bottomNavigationBar:'), isTrue);
  });
}
