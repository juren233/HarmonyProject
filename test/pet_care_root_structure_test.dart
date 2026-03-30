import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pet care root uses a dedicated first-launch transition controller', () {
    final source = File('lib/app/pet_care_root.dart').readAsStringSync();

    expect(source.contains('enum _FirstLaunchTransition'), isTrue);
    expect(source.contains('_firstLaunchTransitionController'), isTrue);
    expect(source.contains('_firstLaunchFlipDuration'), isTrue);
    expect(source.contains('_firstLaunchPushUpDuration'), isTrue);
    expect(source.contains('_firstLaunchDeferRevealDuration'), isTrue);
    expect(source.contains('_retainIntroSurface'), isTrue);
    expect(source.contains('first_launch_transition_host'), isTrue);
    expect(source.contains('first_launch_transition_outgoing_intro'), isTrue);
    expect(
        source.contains('first_launch_transition_incoming_onboarding'), isTrue);
    expect(source.contains('first_launch_transition_intro_to_home'), isTrue);
    expect(source.contains('deferToHome'), isTrue);
    expect(source.contains('first_launch_transition_defer_to_home'), isTrue);
    expect(source.contains('first_launch_defer_reveal_clip'), isTrue);
    expect(source.contains('_buildDeferredOnboardingExit'), isTrue);
    expect(
        source.contains('first_launch_transition_outgoing_onboarding'), isTrue);
    expect(source.contains('first_launch_transition_incoming_intro'), isTrue);
    expect(source.contains('flipOutToRight'), isTrue);
    expect(source.contains('flipInFromLeft'), isTrue);
    expect(source.contains('hidden,'), isTrue);
  });
}
