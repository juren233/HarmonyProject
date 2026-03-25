import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/app/theme_settings_copy.dart';
import 'package:pet_care_harmony/app/pet_care_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _petsStorageKey = 'pets_v1';
const _onboardingAutoEnabledKey = 'first_launch_onboarding_auto_enabled_v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows first-launch onboarding without a dismiss action',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsOneWidget);
    expect(find.text('稍后再说'), findsNothing);
  });

  testWidgets(
      'can create the first pet through onboarding and land on checklist',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

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
      'birthday step uses orange text for selected dates without filled background',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

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

    final themedCalendar = tester.widget<Theme>(
      find
          .ancestor(
            of: find.byType(CalendarDatePicker),
            matching: find.byType(Theme),
          )
          .first,
    );
    final datePickerTheme = themedCalendar.data.datePickerTheme;

    expect(
      datePickerTheme.dayForegroundColor?.resolve({WidgetState.selected}),
      const Color(0xFFD9822B),
    );
    expect(
      datePickerTheme.dayBackgroundColor?.resolve({WidgetState.selected}),
      Colors.transparent,
    );
    expect(
      datePickerTheme.todayForegroundColor?.resolve({}),
      const Color(0xFF17181C),
    );
    expect(
      datePickerTheme.todayBackgroundColor?.resolve({}),
      Colors.transparent,
    );
  });

  testWidgets('birthday step allows dates after the current day',
      (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

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

  testWidgets('can edit pet info from the pets page', (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('爱宠'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit_pet_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('edit_pet_name_field')),
      'Tofu',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit_pet_note_field')),
      '洗澡前会躲起来',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('edit_pet_save_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_pet_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Tofu'), findsWidgets);
    expect(find.text('洗澡前会躲起来'), findsOneWidget);
  });

  testWidgets(
      'renders checklist shell and can switch to overview with saved pets',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsWidgets);
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('爱宠'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('今天 0 项待处理'), findsOneWidget);

    await tester.tap(find.text('总览'));
    await tester.pumpAndSettle();

    expect(find.text('AI 照护总结'), findsOneWidget);
  });

  testWidgets('opens add sheet with four primary actions', (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('新增内容'), findsOneWidget);
    expect(find.text('新增待办'), findsOneWidget);
    expect(find.text('新增提醒'), findsOneWidget);
    expect(find.text('新增记录'), findsOneWidget);
    expect(find.text('新增爱宠'), findsOneWidget);
    expect(find.text('关闭'), findsNothing);
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

Map<String, Object> _persistedSinglePetPreferences() {
  return {
    _onboardingAutoEnabledKey: false,
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
