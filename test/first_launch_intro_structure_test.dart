import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-launch intro keeps approved brand copy and icon set', () {
    final source =
        File('lib/app/pet_first_launch_intro.dart').readAsStringSync();

    expect(source.contains('欢迎来到宠记'), isTrue);
    expect(source.contains('照顾它的每一天，都能更从容一点'), isTrue);
    expect(source.contains('先认识一下你的毛孩子吧'), isTrue);
    expect(source.contains('那我们开始吧'), isTrue);
    expect(source.contains('先看看宠记'), isTrue);
    expect(source.contains('Icons.pets_rounded'), isTrue);
    expect(source.contains('Icons.done_rounded'), isTrue);
    expect(source.contains('CupertinoIcons.lock_open_fill'), isTrue);
    expect(source.contains('CupertinoIcons.lock_fill'), isTrue);
    expect(source.contains('_AnimatedPrivacyLockIcon'), isTrue);
    expect(source.contains('PageController()'), isTrue);
    expect(source.contains('Icons.checklist_rounded'), isTrue);
    expect(source.contains('Icons.description_rounded'), isTrue);
    expect(source.contains('Icons.favorite_rounded'), isTrue);
    expect(source.contains('Color(0xFFE88FB0)'), isTrue);
    expect(source.contains('boxShadow'), isFalse);
    expect(source.contains("Text(\n            '宠记'"), isFalse);
    expect(source.contains("/ \$pageCount"), isFalse);
    expect(source.contains('_firstPageIndicatorDelay'), isTrue);
    expect(source.contains('_firstPageButtonDelayAfterIndicator'), isTrue);
    expect(
      source.contains('_firstPageIndicatorDelay = Duration(milliseconds: 500)'),
      isTrue,
    );
    expect(
      source.contains('_finalPageIndicatorDelay = Duration(milliseconds: 700)'),
      isTrue,
    );
    expect(
      source.contains('_privacyLockAnimationDuration'),
      isTrue,
    );
    expect(
      source.contains('Duration(milliseconds: 1220)'),
      isTrue,
    );
    expect(source.contains('_privacyLockPeakHoldDuration'), isFalse);
    expect(source.contains('elapsedMs == 0 || scale > 1.0'), isTrue);
    expect(source.contains('Curves.linear'), isTrue);
    expect(source.contains('Curves.easeInQuart'), isTrue);
    expect(source.contains('Curves.easeOutQuart'), isTrue);
    expect(
      source.contains('_segmentValue(elapsedMs, 0, 300, Curves.linear)'),
      isTrue,
    );
    expect(
      source.contains('_segmentValue(elapsedMs, 300, 460, Curves.linear)'),
      isTrue,
    );
    expect(
      source.contains('900,'),
      isTrue,
    );
    expect(
      source.contains('Curves.easeInQuart'),
      isTrue,
    );
    expect(
      source
          .contains('_segmentValue(elapsedMs, 900, 1120, Curves.easeOutQuart)'),
      isTrue,
    );
    expect(source.contains('1.38,'), isTrue);
    expect(source.contains('1.5,'), isTrue);
    expect(source.contains('1.0,'), isTrue);
    expect(source.contains('0.6,'), isTrue);
    expect(source.contains('onboardingExitProgress'), isTrue);
    expect(source.contains('intro_onboarding_exit_hero_scale'), isTrue);
    expect(source.contains('_onboardingHeroScale'), isTrue);
    expect(source.contains('_onboardingHeroOpacity'), isFalse);
  });
}
