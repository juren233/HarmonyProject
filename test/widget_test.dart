import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/pet_care_app.dart';
import 'package:pet_care_harmony/app/theme_settings_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _petsStorageKey = 'pets_v1';
const _firstLaunchIntroAutoEnabledKey = 'first_launch_intro_auto_enabled_v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('intro shows a gray launch paw before first page content appears',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsNothing);
    expect(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('first_launch_intro_primary_button')),
      findsNothing,
    );
  });

  testWidgets('intro keeps a single paw during launch without a handoff icon',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('intro_launch_handoff_hero')), findsNothing);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsNothing);
    expect(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
      findsNothing,
    );
  });

  testWidgets('shows first-launch intro before pet onboarding', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_intro_overlay')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsNothing);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsOneWidget);
    expect(find.text('欢迎来到宠伴'), findsOneWidget);
    expect(find.text('照顾它的每一天，都能更从容一点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '继续'), findsOneWidget);
    expect(find.text('宠伴'), findsNothing);
    expect(find.text('1 / 3'), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsNWidgets(3));
    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsNothing);
  });

  testWidgets(
      'first page footer chrome waits until intro rows finish before appearing',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      if (find
          .byKey(const ValueKey('intro_launch_paw_icon'))
          .evaluate()
          .isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsNothing);

    expect(find.byKey(const ValueKey('first_launch_intro_indicator')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 680));
    await tester.pump();

    expect(
      _revealOpacity(
        tester,
        const ValueKey('first_page_indicator_reveal'),
      ),
      0,
    );
    expect(
      _revealOpacity(
        tester,
        const ValueKey('first_page_continue_reveal'),
      ),
      0,
    );

    var indicatorElapsed = 0;
    while (indicatorElapsed < 3000 &&
        find
            .byKey(const ValueKey('first_launch_intro_indicator'))
            .evaluate()
            .isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      indicatorElapsed += 40;
    }

    expect(find.byKey(const ValueKey('first_launch_intro_indicator')),
        findsOneWidget);
    expect(
      _revealOpacity(
        tester,
        const ValueKey('first_page_continue_reveal'),
      ),
      0,
    );

    var buttonElapsedAfterIndicator = 0;
    while (buttonElapsedAfterIndicator < 2000 &&
        _nearestOpacity(
              tester,
              find.byKey(const ValueKey('first_launch_intro_continue_button')),
            ) ==
            0) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      buttonElapsedAfterIndicator += 40;
    }

    expect(buttonElapsedAfterIndicator, greaterThanOrEqualTo(320));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_intro_indicator')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'first page indicator stays in place when continue button appears',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      if (find
          .byKey(const ValueKey('intro_launch_paw_icon'))
          .evaluate()
          .isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    while (find
        .byKey(const ValueKey('first_launch_intro_indicator'))
        .evaluate()
        .isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
    }

    final indicatorBeforeButton = tester.getTopLeft(
      find.byKey(const ValueKey('first_launch_intro_indicator')),
    );

    while (find
        .byKey(const ValueKey('first_launch_intro_continue_button'))
        .evaluate()
        .isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
    }

    final indicatorAfterButton = tester.getTopLeft(
      find.byKey(const ValueKey('first_launch_intro_indicator')),
    );

    expect(indicatorAfterButton.dy, closeTo(indicatorBeforeButton.dy, 0.5));
  });

  testWidgets('intro page view uses page spacing without extra end padding',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
    );
    final controller = pageView.controller! as PageController;

    expect(controller.viewportFraction, 1.0);
  });

  testWidgets(
      'second page content reveals when first visited and stays visible',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_page_1_content')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
      const Offset(-400, 0),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('intro_page_1_content')), findsOneWidget);

    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
      const Offset(-400, 0),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('intro_page_1_content')), findsOneWidget);
  });

  testWidgets('intro overlay does not add outer horizontal padding',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
    );
    final pageViewRect = tester.getRect(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
    );

    expect(pageViewRect.left, closeTo(overlayRect.left, 0.5));
    expect(pageViewRect.right, closeTo(overlayRect.right, 0.5));
  });

  testWidgets('intro primary CTA opens pet onboarding on final page',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);
    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsOneWidget);
  });

  testWidgets('final page footer reveals sequentially like the first page',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    expect(find.byKey(const ValueKey('intro_page_2_content')), findsOneWidget);
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_indicator')),
      ),
      0,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_primary_button')),
      ),
      0,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      0,
    );

    await tester.pump(const Duration(milliseconds: 680));
    await tester.pump();

    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_indicator')),
      ),
      0,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_primary_button')),
      ),
      0,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      0,
    );

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(
      _revealOpacity(
        tester,
        const ValueKey('final_page_indicator_reveal'),
      ),
      greaterThan(0),
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_primary_button')),
      ),
      0,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      0,
    );

    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();

    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_primary_button')),
      ),
      greaterThan(0),
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      0,
    );

    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();

    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      greaterThan(0),
    );
  });

  testWidgets('final page privacy rows use animated lock icons',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_page_2_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy_lock_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy_lock_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy_lock_2')), findsOneWidget);
  });

  testWidgets('final page privacy lock stays open long enough to notice',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump(const Duration(milliseconds: 80));

    while (find.byKey(const ValueKey('privacy_lock_0')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(
      _iconDataByKey(tester, const ValueKey('privacy_lock_0')),
      CupertinoIcons.lock_open_fill,
    );

    await tester.pump(const Duration(milliseconds: 1080));

    expect(
      _iconDataByKey(tester, const ValueKey('privacy_lock_0')),
      CupertinoIcons.lock_open_fill,
    );

    await tester.pump(const Duration(milliseconds: 2000));

    expect(
      _iconDataByKey(tester, const ValueKey('privacy_lock_0')),
      CupertinoIcons.lock_fill,
    );
  });

  testWidgets(
      'choosing explore first hides intro, persists dismissal, and still allows manual reopen',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_secondary_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);
    expect(find.text('先添加第一只爱宠'), findsWidgets);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_firstLaunchIntroAutoEnabledKey), isFalse);

    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);

    await tester.tap(find.text('开始添加宠物').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsOneWidget);
  });

  testWidgets(
      'deferring onboarding entered from intro closes to shell without reopening intro',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await _enterOnboardingFromIntro(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding_defer_button')));
    await tester.pumpAndSettle();

    expect(find.text('稍后处理首次引导？'), findsNothing);
    expect(
        find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);
    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
    expect(find.text('先添加第一只爱宠'), findsWidgets);
  });

  testWidgets(
      'top progress stays centered, shorter, and aligned on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('first_launch_onboarding_overlay')),
    );
    final progressRect = tester.getRect(
      find.byKey(const ValueKey('onboarding_progress_bar')),
    );
    final backRect = tester.getRect(find.byIcon(Icons.arrow_back_rounded));
    final deferRect = tester.getRect(
      find.byKey(const ValueKey('onboarding_defer_button')),
    );
    final contentWidth = overlayRect.width - 40;
    final middleWidth = contentWidth - 96;

    expect(find.text('2 / 9'), findsNothing);
    expect(
      (progressRect.center.dx - overlayRect.center.dx).abs(),
      lessThanOrEqualTo(4),
    );
    expect(progressRect.width, closeTo(middleWidth * 0.8, 2));
    expect(
      (progressRect.center.dy - backRect.center.dy).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (progressRect.center.dy - deferRect.center.dy).abs(),
      lessThanOrEqualTo(2),
    );
  });

  testWidgets(
      'can create the first pet through onboarding and land on checklist',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Mochi');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_weight_field')), '4.2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('onboarding_skip_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_skip_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_skip_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_save_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
    expect(find.text('今天 0 项待处理'), findsOneWidget);
    await tester.tap(find.text('爱宠'));
    await tester.pumpAndSettle();
    expect(find.text('Mochi'), findsWidgets);
  });

  testWidgets(
      'requires a custom breed before continuing when choosing other breed',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('onboarding_custom_breed_field')),
        findsOneWidget);
    final continueButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('onboarding_continue_button')),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets(
      'birthday step uses Chinese month text and keeps selected day visible',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('月'), findsWidgets);

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('已选择 '), findsOneWidget);
    expect(find.textContaining('年'), findsWidgets);
    expect(find.textContaining('月'), findsWidgets);
    expect(find.textContaining('日'), findsWidgets);
    expect(find.text('15'), findsWidgets);
  });

  testWidgets(
      'birthday step does not preselect today and uses orange text for selected current day',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final themedCalendar = tester.widget<Theme>(
      find
          .ancestor(
            of: find.byType(CalendarDatePicker),
            matching: find.byType(Theme),
          )
          .first,
    );
    final datePickerTheme = themedCalendar.data.datePickerTheme;

    expect(calendar.initialDate, isNull);
    expect(
      datePickerTheme.dayForegroundColor?.resolve({WidgetState.selected}),
      const Color(0xFFD9822B),
    );
    expect(
      datePickerTheme.dayBackgroundColor?.resolve({WidgetState.selected}),
      Colors.transparent,
    );
    expect(
      datePickerTheme.todayForegroundColor?.resolve({WidgetState.selected}),
      const Color(0xFFD9822B),
    );
    expect(
      datePickerTheme.todayBackgroundColor?.resolve({WidgetState.selected}),
      Colors.transparent,
    );
  });

  testWidgets('birthday step allows dates after the current day',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final now = DateTime.now();

    expect(calendar.lastDate.isAfter(now), isTrue);
  });

  testWidgets('neuter step only shows explicit yes or no options',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_weight_field')), '4.2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    expect(find.text('已绝育'), findsOneWidget);
    expect(find.text('未绝育'), findsOneWidget);
    expect(find.text('暂不确定'), findsNothing);
  });

  testWidgets('note step can be skipped and saves the first pet',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Mochi');
    await tester.tap(find.text('猫'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('英短'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('母'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_weight_field')), '4.2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      final skipButton = find.byKey(const ValueKey('onboarding_skip_button'));
      if (skipButton.evaluate().isEmpty) {
        break;
      }
      await tester.tap(skipButton);
      await tester.pumpAndSettle();
    }
    final saveButton = find.byKey(const ValueKey('onboarding_save_button'));
    if (saveButton.evaluate().isNotEmpty) {
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
    await tester.tap(find.text('爱宠'));
    await tester.pumpAndSettle();
    expect(find.text('未填写'), findsWidgets);
  });

  testWidgets(
      'dock add todo, reminder, and record show add-pet empty state when no pets exist',
      (tester) async {
    for (final action in ['新增待办', '新增提醒', '新增记录']) {
      SharedPreferences.setMockInitialValues({
        _firstLaunchIntroAutoEnabledKey: false,
      });
      await tester.pumpWidget(const PetCareApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      final sheetScope = find.descendant(
        of: find.byKey(const ValueKey('add_sheet_shell')),
        matching: find.byType(EmptyCard),
      );
      expect(
        find.descendant(of: sheetScope, matching: find.text('先添加第一只爱宠')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheetScope, matching: find.text('开始添加宠物')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: sheetScope, matching: find.text('开始添加宠物')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('manual_onboarding_sheet_transition')),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('expanded todo form back returns to action grid', (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('expanded_form_back_button')));
    await tester.pumpAndSettle();

    expect(find.text('新增内容'), findsOneWidget);
    expect(find.text('新增提醒'), findsOneWidget);
    expect(find.byKey(const ValueKey('manual_expanded_form_transition')),
        findsNothing);
  });

  testWidgets('expanded todo form save closes the sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '补货主粮');
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存待办'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_sheet_shell')), findsNothing);
    expect(find.text('今天 0 项待处理'), findsOneWidget);
  });

  testWidgets(
      'dock add reminder and record actions expand into full-height form flow',
      (tester) async {
    for (final action in ['新增提醒', '新增记录']) {
      SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
      await tester.pumpWidget(const PetCareApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pump();

      expect(find.byKey(const ValueKey('manual_expanded_form_transition')),
          findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text(action), findsWidgets);
      expect(find.byKey(const ValueKey('expanded_form_back_button')),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('dock add pet onboarding keeps the original sheet corner radius',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    BorderRadius resolveRadius() {
      final shell = tester.widget<ClipRRect>(
        find.byKey(const ValueKey('add_sheet_shell')),
      );
      return shell.borderRadius.resolve(TextDirection.ltr);
    }

    expect(resolveRadius().topLeft.x, 36);
    expect(resolveRadius().topRight.x, 36);

    await tester.tap(find.text('新增爱宠'));
    await tester.pump();

    expect(resolveRadius().topLeft.x, 36);
    expect(resolveRadius().topRight.x, 36);

    await tester.pumpAndSettle();

    expect(resolveRadius().topLeft.x, 36);
    expect(resolveRadius().topRight.x, 36);
  });

  testWidgets(
      'dock add pet transition clears the action grid before onboarding settles',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('新增待办'), findsNothing);
    expect(find.text('新增提醒'), findsNothing);
    expect(find.byKey(const ValueKey('manual_onboarding_sheet_transition')),
        findsOneWidget);
    expect(find.text('先认识一下'), findsOneWidget);
  });

  testWidgets(
      'manual onboarding from dock defer closes sheet without changing auto-show preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      _firstLaunchIntroAutoEnabledKey: true,
    });
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('onboarding_defer_button')));
    await tester.pumpAndSettle();

    expect(find.text('稍后处理首次引导？'), findsNothing);
    expect(find.text('新增内容'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding_defer_button')), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_firstLaunchIntroAutoEnabledKey), isTrue);
  });

  testWidgets('uses immersive dock with compact centered add button',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
    expect(tester.widget(find.byKey(const ValueKey('bottom_nav_blur'))),
        isA<BackdropFilter>());
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock_add_button')), findsOneWidget);

    final addButtonSize =
        tester.getSize(find.byKey(const ValueKey('dock_add_button')));
    expect(addButtonSize.width, lessThanOrEqualTo(60));
    expect(addButtonSize.height, lessThanOrEqualTo(60));

    final panelRect =
        tester.getRect(find.byKey(const ValueKey('bottom_nav_panel')));
    final addButtonRect =
        tester.getRect(find.byKey(const ValueKey('dock_add_button')));
    expect((panelRect.center.dx - addButtonRect.center.dx).abs(),
        lessThanOrEqualTo(0.5));
    expect(addButtonRect.top, greaterThanOrEqualTo(panelRect.top));
    expect(addButtonRect.bottom, lessThanOrEqualTo(panelRect.bottom));
  });

  testWidgets('keeps blur only on the bottom dock and not on content panels',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
  });

  testWidgets('uses the warm pet orange theme for primary actions',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold));
    final theme = Theme.of(context);
    expect(theme.colorScheme.primary, const Color(0xFFF2A65A));

    final filledStyle = theme.filledButtonTheme.style!;
    expect(filledStyle.backgroundColor!.resolve({}), const Color(0xFFF2A65A));

    final plusDecoratedBox = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byIcon(Icons.add),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = plusDecoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors.first, const Color(0xFF90CE9B));
    expect(gradient.colors.last, const Color(0xFF6AB57A));
  });

  testWidgets(
      'keeps informational highlight cards on the cooler accent palette',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final coolAccentCards = find.byWidgetPredicate((widget) {
      if (widget is! Container) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == const Color(0xFFEAF0FF);
    });

    expect(coolAccentCards, findsWidgets);
  });

  testWidgets('configures transparent immersive status bar wrapper',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final annotated = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(annotated.value.statusBarColor, const Color(0x00000000));
  });

  testWidgets('shows theme settings on the me page and switches to dark mode',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await tester.pumpAndSettle();

    expect(find.text(themeSectionTitle), findsOneWidget);
    expect(find.text(followSystemTitle), findsWidgets);
    expect(find.text(lightModeTitle), findsWidgets);
    expect(find.text(darkModeTitle), findsWidgets);
    expect(find.byKey(const ValueKey('theme_option_system')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_light')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_dark')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('theme_option_dark')),
      120,
    );
    await tester.tap(find.text(darkModeTitle).first);
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(scaffoldContext).brightness, Brightness.dark);
  });

  testWidgets('uses amoled-friendly dark theme when persisted in dark mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'dark',
    });
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(
      Theme.of(scaffoldContext).scaffoldBackgroundColor,
      const Color(0xFF020304),
    );
  });

  testWidgets('adapts add sheet surfaces to dark mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'dark',
    });
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final shell = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byKey(const ValueKey('add_sheet_shell')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final shellGradient =
        (shell.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(shellGradient.colors, [
      darkPetCareTokens.pageGradientTop,
      darkPetCareTokens.pageGradientBottom,
    ]);

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, darkPetCareTokens.pageGradientTop);

    final title = tester.widget<Text>(find.text('新增内容'));
    expect(title.style?.color, darkPetCareTokens.primaryText);

    final subtitle = tester.widget<Text>(find.text('今天要给小宝加点什么新内容？'));
    expect(subtitle.style?.color, darkPetCareTokens.secondaryText);

    final cardTitle = tester.widget<Text>(find.text('新增待办'));
    expect(cardTitle.style?.color, darkPetCareTokens.primaryText);
  });

  testWidgets('adapts first-launch intro surfaces to dark mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
    });
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final overlayMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
    );
    expect(
      overlayMaterial.color,
      buildPetCareTheme(Brightness.dark)
          .scaffoldBackgroundColor
          .withValues(alpha: 0.92),
    );

    final gradientBox = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('first_launch_intro_overlay')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final gradient =
        (gradientBox.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, [
      darkPetCareTokens.pageGradientTop,
      darkPetCareTokens.pageGradientBottom,
    ]);

    final title = tester.widget<Text>(find.text('欢迎来到宠伴'));
    expect(title.style?.color, darkPetCareTokens.primaryText);
  });

  testWidgets('restores persisted system theme preference', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('uses explicit insets instead of nested SafeArea wrappers',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byType(SafeArea), findsNothing);
  });
}

double _nearestOpacity(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return 0;
  }
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(
          of: finder,
          matching: find.byType(Opacity),
        )
        .first,
  );
  return opacity.opacity;
}

double _opacityOrOne(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return 0;
  }
  final opacityAncestors = find.ancestor(
    of: finder,
    matching: find.byType(Opacity),
  );
  if (opacityAncestors.evaluate().isEmpty) {
    return 1;
  }
  final opacity = tester.widget<Opacity>(opacityAncestors.first);
  return opacity.opacity;
}

double _revealOpacity(WidgetTester tester, ValueKey<String> key) {
  if (find.byKey(key).evaluate().isEmpty) {
    return 0;
  }
  final opacityFinder = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Opacity),
  );
  if (opacityFinder.evaluate().isEmpty) {
    return 0;
  }
  final opacity = tester.widget<Opacity>(
    opacityFinder.first,
  );
  return opacity.opacity;
}

IconData _iconDataByKey(WidgetTester tester, ValueKey<String> key) {
  return tester.widget<Icon>(find.byKey(key)).icon!;
}

Future<void> _advanceIntroToFinalPage(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _enterOnboardingFromIntro(WidgetTester tester) async {
  await _advanceIntroToFinalPage(tester);
  await tester
      .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
  await tester.pumpAndSettle();
}

Map<String, Object> _persistedSinglePetPreferences() {
  return {
    _firstLaunchIntroAutoEnabledKey: false,
    _petsStorageKey: jsonEncode([
      {
        'id': 'pet-1',
        'name': 'Luna',
        'avatarText': 'LU',
        'type': 'cat',
        'breed': '英短',
        'sex': '母',
        'birthday': '2024-01-15',
        'ageLabel': '新加入',
        'weightKg': 4.2,
        'neuterStatus': 'neutered',
        'feedingPreferences': '未填写',
        'allergies': '未填写',
        'note': '未填写',
      },
    ]),
  };
}
