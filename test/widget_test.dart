import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/add_sheet.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/intro_haptics.dart';
import 'package:petnote/app/android_native_dock.dart';
import 'package:petnote/app/ios_native_dock.dart';
import 'package:petnote/app/me_page.dart' as settings_page;
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/pet_first_launch_intro.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/pet_onboarding_overlay.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/app/theme_settings_copy.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/notifications/notification_platform_adapter.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _petsStorageKey = 'pets_v1';
const _recordsStorageKey = 'records_v1';
const _firstLaunchIntroAutoEnabledKey = 'first_launch_intro_auto_enabled_v1';

void main() {
  setUp(() {
    debugDisableAndroidLiquidGlassDock = true;
    SharedPreferences.setMockInitialValues({});
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
  });

  tearDown(() {
    debugDisableAndroidLiquidGlassDock = false;
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
  });

  testWidgets('intro shows a gray launch paw before first page content appears',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );

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

  testWidgets(
      'intro waits for prewarm completion before starting launch animation',
      (tester) async {
    var shouldStartLaunchAnimation = false;
    late StateSetter updateIntro;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateIntro = setState;
              return PetFirstLaunchIntro(
                fillParent: false,
                shouldStartLaunchAnimation: shouldStartLaunchAnimation,
                onStartOnboarding: () async {},
                onExploreFirst: () async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));

    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsNothing);

    updateIntro(() => shouldStartLaunchAnimation = true);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_page_0_content')), findsOneWidget);
  });

  testWidgets(
      'intro triggers a single soft haptic window during launch paw motion',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(
          body: PetFirstLaunchIntro(
            fillParent: false,
            introHapticsDriver: driver,
            onStartOnboarding: () async {},
            onExploreFirst: () async {},
          ),
        ),
      ),
    );

    await tester.pump();
    expect(driver.events, <String>['prepare']);
    await tester.pump(const Duration(milliseconds: 260));
    expect(driver.events, <String>['prepare']);

    await tester.pump(const Duration(milliseconds: 220));
    expect(driver.events, <String>['prepare', 'start']);

    await tester.pumpAndSettle();
    expect(driver.events, <String>['prepare', 'start', 'stop']);
  });

  testWidgets(
      'intro triggers a single soft haptic window during launch paw motion on Android',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: PetFirstLaunchIntro(
            fillParent: false,
            introHapticsDriver: driver,
            onStartOnboarding: () async {},
            onExploreFirst: () async {},
          ),
        ),
      ),
    );

    await tester.pump();
    expect(driver.events, <String>['prepare']);
    await tester.pump(const Duration(milliseconds: 260));
    expect(driver.events, <String>['prepare']);

    await tester.pump(const Duration(milliseconds: 220));
    expect(driver.events, <String>['prepare', 'start']);

    await tester.pumpAndSettle();
    expect(driver.events, <String>['prepare', 'start', 'stop']);
  });

  testWidgets('intro stops active haptics if removed before launch paw settles',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var visible = true;
    late StateSetter setVisible;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setVisible = setState;
              if (!visible) {
                return const SizedBox.shrink();
              }
              return PetFirstLaunchIntro(
                fillParent: false,
                introHapticsDriver: driver,
                onStartOnboarding: () async {},
                onExploreFirst: () async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(driver.events, <String>['prepare', 'start']);

    setVisible(() => visible = false);
    await tester.pump();

    expect(driver.events, <String>['prepare', 'start', 'stop']);
  });

  testWidgets(
      'intro does not wait for launch haptics preparation to start animating',
      (tester) async {
    final prepareCompleter = Completer<void>();
    final driver = _FakeIntroHapticsDriver(
      prepareFutureFactory: () => prepareCompleter.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(
          body: PetFirstLaunchIntro(
            fillParent: false,
            introHapticsDriver: driver,
            onStartOnboarding: () async {},
            onExploreFirst: () async {},
          ),
        ),
      ),
    );

    await tester.pump();
    expect(driver.events, <String>['prepare']);
    final initialPawTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );

    await tester.pump(const Duration(milliseconds: 260));
    final animatedPawTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );
    expect(animatedPawTopLeft.dy, lessThan(initialPawTopLeft.dy));

    prepareCompleter.complete();
  });

  testWidgets(
      'intro onboarding transition triggers a single haptic window during hero shrink',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var onboardingExitProgress = 0.0;
    late StateSetter updateIntro;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateIntro = setState;
              return PetFirstLaunchIntro(
                fillParent: false,
                onboardingExitProgress: onboardingExitProgress,
                introHapticsDriver: driver,
                onStartOnboarding: () async {},
                onExploreFirst: () async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _advanceIntroToFinalPage(tester);
    driver.events.clear();

    updateIntro(() => onboardingExitProgress = 0.21);
    await tester.pump();
    expect(driver.events, isEmpty);

    updateIntro(() => onboardingExitProgress = 0.23);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => onboardingExitProgress = 0.50);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => onboardingExitProgress = 0.70);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start', 'onboarding-stop']);
  });

  testWidgets(
      'intro onboarding transition stops active haptics when progress resets or widget is removed',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var onboardingExitProgress = 0.0;
    var visible = true;
    late StateSetter updateIntro;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateIntro = setState;
              if (!visible) {
                return const SizedBox.shrink();
              }
              return PetFirstLaunchIntro(
                fillParent: false,
                onboardingExitProgress: onboardingExitProgress,
                introHapticsDriver: driver,
                onStartOnboarding: () async {},
                onExploreFirst: () async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _advanceIntroToFinalPage(tester);
    driver.events.clear();

    updateIntro(() => onboardingExitProgress = 0.24);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => onboardingExitProgress = 0.0);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start', 'onboarding-stop']);

    driver.events.clear();
    updateIntro(() => onboardingExitProgress = 0.30);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => visible = false);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start', 'onboarding-stop']);
  });

  testWidgets(
      'intro onboarding transition uses the same haptic window on Android',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var onboardingExitProgress = 0.0;
    var visible = true;
    late StateSetter updateIntro;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateIntro = setState;
              if (!visible) {
                return const SizedBox.shrink();
              }
              return PetFirstLaunchIntro(
                fillParent: false,
                onboardingExitProgress: onboardingExitProgress,
                introHapticsDriver: driver,
                onStartOnboarding: () async {},
                onExploreFirst: () async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _advanceIntroToFinalPage(tester);
    driver.events.clear();

    updateIntro(() => onboardingExitProgress = 0.21);
    await tester.pump();
    expect(driver.events, isEmpty);

    updateIntro(() => onboardingExitProgress = 0.23);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => onboardingExitProgress = 0.70);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start', 'onboarding-stop']);

    driver.events.clear();
    updateIntro(() => onboardingExitProgress = 0.30);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start']);

    updateIntro(() => visible = false);
    await tester.pump();
    expect(driver.events, <String>['onboarding-start', 'onboarding-stop']);
  });

  testWidgets('intro primary buttons trigger a button-tap haptic',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var startedOnboarding = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: PetFirstLaunchIntro(
            fillParent: false,
            introHapticsDriver: driver,
            onStartOnboarding: () async {
              startedOnboarding += 1;
            },
            onExploreFirst: () async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    driver.events.clear();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(driver.events, <String>['button-tap']);

    driver.events.clear();
    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(driver.events, <String>['button-tap']);

    driver.events.clear();
    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_primary_button')),
    );
    await tester.pumpAndSettle();
    expect(driver.events, <String>['button-tap']);
    expect(startedOnboarding, 1);
  });

  testWidgets('onboarding primary buttons trigger button-tap haptics',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    var saved = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: PetOnboardingFlow(
            introHapticsDriver: driver,
            onSubmit: (_) async {
              saved += 1;
            },
            onDefer: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('onboarding_name_field')),
      'Nori',
    );
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();
    expect(driver.events, <String>['button-tap']);

    driver.events.clear();
    await _tapVisibleText(tester, '英短');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '母');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _selectBirthdayDay(
      tester,
      DateTime(DateTime.now().year, DateTime.now().month, 15),
    );
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('onboarding_weight_field')),
      '4.2',
    );
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

    driver.events.clear();
    await tester.tap(find.byKey(const ValueKey('onboarding_save_button')));
    await tester.pumpAndSettle();

    expect(driver.events, <String>['button-tap']);
    expect(saved, 1);
  });

  testWidgets(
      'embedded onboarding primary buttons do not trigger button haptics',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: PetOnboardingFlow(
            embedded: true,
            introHapticsDriver: driver,
            onSubmit: (_) async {},
            onDefer: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('onboarding_name_field')),
      'Nori',
    );
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    expect(driver.events, isEmpty);
  });

  testWidgets(
      'dock embedded onboarding primary buttons trigger button haptics when enabled',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: PetOnboardingFlow(
            embedded: true,
            enableEmbeddedPrimaryButtonHaptics: true,
            introHapticsDriver: driver,
            onSubmit: (_) async {},
            onDefer: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('onboarding_name_field')),
      'Nori',
    );
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    expect(driver.events, <String>['button-tap']);
  });

  testWidgets(
      'checklist card uses readable Chinese action labels and separators',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: ChecklistCard(
            item: ChecklistItemViewModel(
              id: 'reminder-1',
              sourceType: 'reminder',
              petId: 'pet-1',
              petName: 'Luna',
              petAvatarText: 'LU',
              petAvatarPhotoPath: null,
              title: '体内驱虫',
              dueLabel: '03/27 18:00',
              statusLabel: '已逾期',
              kindLabel: '提醒',
              note: '晚饭后服用。',
            ),
            onComplete: () {},
            onPostpone: () {},
            onSkip: () {},
          ),
        ),
      ),
    );

    expect(find.text('完成'), findsOneWidget);
    expect(find.text('延后'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('Luna · 提醒 · 03/27 18:00'), findsOneWidget);
  });

  testWidgets('checklist card prefers pet photo and fallback avatar text',
      (tester) async {
    final photoPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}petnote-checklist-avatar-${DateTime.now().microsecondsSinceEpoch}.bin';
    debugHasPetPhotoOverride = (path) => path == photoPath;
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required BoxFit fit,
      required Widget fallback,
    }) {
      return SizedBox.expand(
        key: ValueKey('debug-pet-photo-$photoPath'),
      );
    };

    final store = PetNoteStore.seeded();
    await store.updatePet(
      petId: 'pet-1',
      name: 'Luna',
      type: PetType.cat,
      photoPath: photoPath,
      breed: 'British Shorthair',
      sex: 'Female',
      birthday: '2023-04-18',
      weightKg: 4.6,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '早晚各一餐，冻干拌主粮',
      allergies: '对鸡肉敏感',
      note: '洗澡后容易紧张，需要安抚。',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              ChecklistCard(
                item: store.checklistSections.first.items
                    .firstWhere((item) => item.petId == 'pet-1'),
                onComplete: () {},
                onPostpone: () {},
                onSkip: () {},
              ),
              ChecklistCard(
                item: ChecklistItemViewModel(
                  id: 'todo-other',
                  sourceType: 'todo',
                  petId: 'pet-other',
                  petName: '龙宝',
                  petAvatarText: '龙',
                  petAvatarPhotoPath: null,
                  title: '补充加湿',
                  dueLabel: '03/27 18:00',
                  statusLabel: '待处理',
                  kindLabel: '待办',
                  note: '',
                ),
                onComplete: () {},
                onPostpone: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(ValueKey('debug-pet-photo-$photoPath')), findsOneWidget);
    expect(find.text('🐱'), findsNothing);
    expect(find.text('龙'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('checklist page shows postponed and skipped segments',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: ChecklistPage(
            store: store,
            activeSectionKey: 'today',
            highlightedChecklistItemKey: null,
            onSectionChanged: (_) {},
            onAddFirstPet: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('已延后'), findsOneWidget);
    expect(find.textContaining('已跳过'), findsOneWidget);
  });

  testWidgets('checklist todo card opens detail page and saves edits',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: ChecklistPage(
            store: store,
            activeSectionKey: 'today',
            highlightedChecklistItemKey: null,
            onSectionChanged: (_) {},
            onAddFirstPet: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('checklist_card_body_todo-todo-1')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo-detail-page-todo-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('todo-detail-edit-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo-detail-title-field')),
      '补货湿粮',
    );
    await tester.tap(find.byKey(const ValueKey('todo-detail-save-button')));
    await tester.pumpAndSettle();

    expect(store.todoById('todo-1')?.title, '补货湿粮');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist_card_todo-todo-1')),
        findsOneWidget);
  });

  testWidgets('checklist reminder card opens detail page and saves edits',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: ChecklistPage(
            store: store,
            activeSectionKey: 'today',
            highlightedChecklistItemKey: null,
            onSectionChanged: (_) {},
            onAddFirstPet: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checklist_card_body_reminder-reminder-2')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('checklist_card_body_reminder-reminder-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reminder-detail-page-reminder-2')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder-detail-edit-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reminder-detail-title-field')),
      '体内驱虫复查',
    );
    await tester.tap(find.byKey(const ValueKey('reminder-detail-save-button')));
    await tester.pumpAndSettle();

    expect(store.reminderById('reminder-2')?.title, '体内驱虫复查');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist_card_reminder-reminder-2')),
        findsOneWidget);
  });

  testWidgets('record detail supports image add remove save and cancel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final existingPhotoPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}petnote-record-edit-${DateTime.now().microsecondsSinceEpoch}.bin';
    final addedPhotoPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}petnote-record-edit-${DateTime.now().microsecondsSinceEpoch + 1}.bin';
    debugHasPetPhotoOverride =
        (path) => path == existingPhotoPath || path == addedPhotoPath;
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required BoxFit fit,
      required Widget fallback,
    }) {
      return SizedBox.expand(
        key: ValueKey('debug-record-edit-photo-$photoPath'),
      );
    };

    final picker = _FakeNativePetPhotoPicker([
      [addedPhotoPath],
    ]);
    final store = PetNoteStore.seeded();
    await store.addRecord(
      petId: 'pet-1',
      type: PetRecordType.image,
      title: '术后恢复',
      recordDate: DateTime.parse('2026-03-26T11:00:00+08:00'),
      summary: '观察恢复情况。',
      note: '保持安静休息。',
      photoPaths: [existingPhotoPath],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RecordDetailPage(
          store: store,
          recordId: 'record-4',
          nativePetPhotoPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-edit-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pet-record-detail-add-photo-button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-add-photo-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('pet-record-detail-photo-tile-$addedPhotoPath')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-save-button')));
    await tester.pumpAndSettle();
    expect(store.recordById('record-4')?.photoPaths,
        [existingPhotoPath, addedPhotoPath]);

    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(ValueKey('pet-record-detail-remove-photo-$addedPhotoPath')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-cancel-button')));
    await tester.pumpAndSettle();
    expect(store.recordById('record-4')?.photoPaths,
        [existingPhotoPath, addedPhotoPath]);

    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(ValueKey('pet-record-detail-remove-photo-$addedPhotoPath')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pet-record-detail-save-button')));
    await tester.pumpAndSettle();
    expect(store.recordById('record-4')?.photoPaths, [existingPhotoPath]);
  });

  testWidgets(
      'first launch onboarding flow does not show the return-to-actions button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetOnboardingFlow(
            onSubmit: (_) async {},
            onDefer: () async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('onboarding_return_to_actions_button')),
        findsNothing);
  });

  testWidgets(
      'intro-entered onboarding shows a back button that returns to intro',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );

    await _enterOnboardingFromIntro(tester);

    expect(find.byKey(const ValueKey('onboarding_return_to_intro_button')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('onboarding_return_to_intro_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('first_launch_intro_overlay')),
    );

    expect(find.byKey(const ValueKey('first_launch_intro_overlay')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
  });

  testWidgets('todo and reminder cards use distinct primary action colors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              ChecklistCard(
                item: ChecklistItemViewModel(
                  id: 'todo-1',
                  sourceType: 'todo',
                  petId: 'pet-1',
                  petName: 'Luna',
                  petAvatarText: 'LU',
                  petAvatarPhotoPath: null,
                  title: '补货主粮',
                  dueLabel: '03/27 18:00',
                  statusLabel: '待处理',
                  kindLabel: '待办',
                  note: '',
                ),
                onComplete: () {},
                onPostpone: () {},
                onSkip: () {},
              ),
              ChecklistCard(
                item: ChecklistItemViewModel(
                  id: 'reminder-1',
                  sourceType: 'reminder',
                  petId: 'pet-1',
                  petName: 'Luna',
                  petAvatarText: 'LU',
                  petAvatarPhotoPath: null,
                  title: '体内驱虫',
                  dueLabel: '03/27 18:00',
                  statusLabel: '待提醒',
                  kindLabel: '提醒',
                  note: '',
                ),
                onComplete: () {},
                onPostpone: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final buttons =
        tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].style?.backgroundColor?.resolve({}),
        isNot(equals(buttons[1].style?.backgroundColor?.resolve({}))));
  });

  testWidgets('intro keeps a single paw during launch without a handoff icon',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );
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

  testWidgets('intro first page hero keeps using svg before and after reveal',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );

    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);

    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_page_0_content')),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('intro_page_0_hero_icon')),
        matching: find.byType(SvgPicture),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows first-launch intro before pet onboarding', (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_page_0_content')),
    );

    expect(find.byKey(const ValueKey('first_launch_intro_overlay')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsNothing);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsOneWidget);
    expect(find.text('欢迎来到宠记'), findsOneWidget);
    expect(find.text('照顾它的每一天，都能更从容一点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '继续'), findsOneWidget);
    expect(find.text('宠记'), findsNothing);
    expect(find.text('1 / 3'), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsNWidgets(3));
    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsNothing);
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsNothing);
  });

  testWidgets(
      'first page footer chrome waits until intro rows finish before appearing',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('intro_launch_paw_icon')),
    );
    await _pumpUntilGone(
      tester,
      find.byKey(const ValueKey('intro_launch_paw_icon')),
      step: const Duration(milliseconds: 100),
    );
    expect(find.byKey(const ValueKey('intro_launch_paw_icon')), findsNothing);

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

    await tester.pump(const Duration(milliseconds: 680));
    await tester.pump();

    expect(
      _revealOpacity(
        tester,
        const ValueKey('first_page_indicator_reveal'),
      ),
      greaterThan(0.5),
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

    expect(buttonElapsedAfterIndicator, greaterThan(0));

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
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
    );
    final controller = pageView.controller!;
    final titleRect = tester.getRect(find.text('欢迎来到宠记'));

    expect(controller.viewportFraction, 1.0);
    expect(titleRect.left, closeTo(20, 0.5));
  });

  testWidgets(
      'second page content reveals when first visited and stays visible',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
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

  testWidgets(
      'hero icons can differ from a shared indicator color across intro pages',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    expect(
      _selectedIndicatorColor(tester),
      const Color(0xFFF2A65A),
    );

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(
      _iconColorByKey(tester, const ValueKey('intro_page_1_hero_icon')),
      const Color(0xFF8D63D2),
    );
    expect(
      _selectedIndicatorColor(tester),
      const Color(0xFFF2A65A),
    );

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(
      _iconColorByKey(tester, const ValueKey('intro_page_2_hero_icon')),
      const Color(0xFF90CE9B),
    );
    expect(
      _selectedIndicatorColor(tester),
      const Color(0xFFF2A65A),
    );
  });

  testWidgets('second page checklist and file icons use the updated colors',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.checklist_rounded)).color,
      const Color(0xFFF2C94C),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.description_rounded)).color,
      const Color(0xFF335FCA),
    );
  });

  testWidgets('intro hero icon stays anchored while switching pages',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_fixed_hero_host')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('intro_page_0_hero_icon')), findsOneWidget);

    final before = tester.getCenter(
      find.byKey(const ValueKey('intro_fixed_hero_host')),
    );

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final during = tester.getCenter(
      find.byKey(const ValueKey('intro_fixed_hero_host')),
    );
    expect(during.dx, closeTo(before.dx, 0.5));
    expect(during.dy, closeTo(before.dy, 0.5));
    expect(_introHeroIconFinder(), findsOneWidget);

    await tester.pumpAndSettle();

    final after = tester.getCenter(
      find.byKey(const ValueKey('intro_fixed_hero_host')),
    );
    expect(after.dx, closeTo(before.dx, 0.5));
    expect(after.dy, closeTo(before.dy, 0.5));
    expect(
        find.byKey(const ValueKey('intro_page_1_hero_icon')), findsOneWidget);
    expect(_introHeroIconFinder(), findsOneWidget);
  });

  testWidgets('intro hero switch shows a visible rebound dip before settling',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    var sawDip = false;
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (_fixedHeroScale(tester) < 0.9) {
        sawDip = true;
        break;
      }
    }

    expect(sawDip, isTrue);

    var settledHigh = false;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (_fixedHeroScale(tester) > 0.96) {
        settledHigh = true;
        break;
      }
    }

    expect(settledHigh, isTrue);
  });

  testWidgets(
      'intro hero stays matched when quickly returning to the previous page',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first_launch_intro_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    expect(find.byKey(const ValueKey('intro_page_1_content')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('intro_page_0_hero_icon')), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('first_launch_intro_page_view')),
      const Offset(500, 0),
      1000,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_page_0_content')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('intro_page_0_hero_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_page_1_hero_icon')), findsNothing);
  });

  testWidgets('intro overlay does not add outer horizontal padding',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
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

  testWidgets('final page privacy lock reaches its enlarged state a bit sooner',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
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

    while (
        find.byKey(const ValueKey('privacy_lock_0_scale')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _scaleByKey(tester, const ValueKey('privacy_lock_0_scale')),
      greaterThan(1.45),
    );
  });

  testWidgets(
      'choosing explore first hides intro, persists dismissal, and still allows manual reopen',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
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

    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);

    await tester.tap(find.text('开始添加宠物').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')),
        findsOneWidget);
  });

  testWidgets(
      'starting onboarding from intro keeps intro briefly visible while onboarding fades in',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('first_launch_onboarding_overlay')),
      findsOneWidget,
    );
  });

  testWidgets(
      'starting onboarding from intro does not reset the intro back to page one during transition',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    expect(find.byKey(const ValueKey('intro_page_2_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.byKey(const ValueKey('intro_page_2_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_page_0_content')), findsNothing);
  });

  testWidgets(
      'starting onboarding keeps intro content fully visible during the hero expansion phase',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('intro_page_2_content')),
      ),
      1,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_primary_button')),
      ),
      1,
    );
    expect(
      _opacityOrOne(
        tester,
        find.byKey(const ValueKey('first_launch_intro_secondary_button')),
      ),
      1,
    );
    expect(
      _opacityByKey(
        tester,
        const ValueKey('onboarding_transition_opacity'),
      ),
      0,
    );
  });

  testWidgets(
      'starting onboarding begins revealing the first onboarding step before intro fully disappears',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 780));

    expect(
      _opacityByKey(
        tester,
        const ValueKey('intro_onboarding_exit_opacity'),
      ),
      allOf(greaterThan(0), lessThan(1)),
    );
    expect(
      _opacityByKey(
        tester,
        const ValueKey('onboarding_transition_opacity'),
      ),
      greaterThan(0),
    );
    expect(
      _opacityByKey(
        tester,
        const ValueKey('onboarding_first_step_content_reveal'),
      ),
      greaterThan(0),
    );
  });

  testWidgets(
      'starting onboarding fades intro content and footer buttons together before the hero becomes tiny',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_primary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 460));

    final contentOpacity = _opacityByKey(
      tester,
      const ValueKey('intro_onboarding_exit_content_opacity'),
    );
    final footerOpacity = _opacityByKey(
      tester,
      const ValueKey('intro_onboarding_exit_footer_opacity'),
    );

    expect(contentOpacity, allOf(greaterThan(0), lessThan(1)));
    expect(footerOpacity, allOf(greaterThan(0), lessThan(1)));
    expect(footerOpacity, closeTo(contentOpacity, 0.0001));
    expect(_fixedHeroScale(tester), greaterThan(0.18));
  });

  testWidgets(
      'explore first keeps intro visible briefly during the shell cross fade',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_secondary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
      findsOneWidget,
    );
    expect(find.text('先添加第一只爱宠'), findsWidgets);
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsOneWidget);
  });

  testWidgets('explore first pulls the whole intro overlay upward',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_secondary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      _translateDyByKey(
        tester,
        const ValueKey('intro_shell_exit_motion'),
      ),
      lessThan(-185),
    );
    expect(
      _opacityByKey(
        tester,
        const ValueKey('intro_shell_exit_opacity'),
      ),
      lessThan(0.2),
    );
    expect(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
      findsOneWidget,
    );
  });

  testWidgets(
      'explore first releases bottom navigation once intro is visually gone',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _advanceIntroToFinalPage(tester);
    await tester
        .tap(find.byKey(const ValueKey('first_launch_intro_secondary_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      _opacityByKey(
        tester,
        const ValueKey('intro_shell_exit_opacity'),
      ),
      lessThan(0.05),
    );

    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('App各项设置'), findsOneWidget);
  });

  testWidgets(
      'deferring onboarding entered from intro closes to shell without reopening intro',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await _enterOnboardingFromIntro(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding_defer_button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 96));
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

    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('first_launch_onboarding_overlay')),
    );
    final progressFrameRect = tester.getRect(
      find.byKey(const ValueKey('onboarding_progress_frame')),
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
      (progressFrameRect.center.dx - overlayRect.center.dx).abs(),
      lessThanOrEqualTo(4),
    );
    expect(progressFrameRect.width, closeTo(middleWidth * 0.8, 2));
    expect(progressFrameRect.height, greaterThan(progressRect.height));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding_progress_bar_paint')),
      findsOneWidget,
    );
    final progressFrame = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('onboarding_progress_frame')),
    );
    final progressDecoration = progressFrame.decoration as BoxDecoration;
    expect(progressDecoration.border, isNotNull);
    expect(progressDecoration.border!.top.width, greaterThanOrEqualTo(2));
    expect(
      (progressFrameRect.center.dy - backRect.center.dy).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (progressFrameRect.center.dy - deferRect.center.dy).abs(),
      lessThanOrEqualTo(2),
    );
  });

  testWidgets('onboarding uses a non-scrollable horizontal page view',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetOnboardingFlow(
            onSubmit: (_) async {},
            onDefer: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final pageView = find.byKey(const ValueKey('onboarding_step_page_view'));
    expect(pageView, findsOneWidget);
    expect(find.text('先认识一下'), findsOneWidget);

    await tester.drag(pageView, const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(find.text('先认识一下'), findsOneWidget);
    expect(find.text('选择品种'), findsNothing);
  });

  testWidgets('onboarding first step content rises in from below on entry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetOnboardingFlow(
            onSubmit: (_) async {},
            onDefer: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      _opacityByKey(
        tester,
        const ValueKey('onboarding_first_step_content_reveal'),
      ),
      lessThan(1),
    );
    expect(
      _translateDyByKey(
        tester,
        const ValueKey('onboarding_first_step_content_reveal'),
      ),
      greaterThan(0),
    );

    await tester.pumpAndSettle();

    expect(
      _opacityByKey(
        tester,
        const ValueKey('onboarding_first_step_content_reveal'),
      ),
      1,
    );
    expect(
      _translateDyByKey(
        tester,
        const ValueKey('onboarding_first_step_content_reveal'),
      ),
      0,
    );
  });

  testWidgets(
      'can create the first pet through onboarding and land on checklist',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Mochi');
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '英短');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '母');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _selectBirthdayDay(
      tester,
      DateTime(DateTime.now().year, DateTime.now().month, 15),
    );
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
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();
    await _tapVisibleText(tester, '其他');

    expect(find.byKey(const ValueKey('onboarding_custom_breed_field')),
        findsOneWidget);
    final continueButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('onboarding_continue_button')),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets(
      'birthday step shows an inline calendar and updates the prompt after selection',
      (tester) async {
    await _enterBirthdayStep(tester);

    expect(find.text('请选择生日'), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsOneWidget);

    final selectedDate =
        DateTime(DateTime.now().year, DateTime.now().month, 15);
    await _selectBirthdayDay(tester, selectedDate);

    expect(find.text(_birthdayPromptText(selectedDate)), findsOneWidget);
  });

  testWidgets('birthday step requires selecting a date before continuing',
      (tester) async {
    await _enterBirthdayStep(tester);

    final continueButtonFinder =
        find.byKey(const ValueKey('onboarding_continue_button'));
    final disabledContinueButton =
        tester.widget<FilledButton>(continueButtonFinder);

    expect(find.text('请选择生日'), findsOneWidget);
    expect(disabledContinueButton.onPressed, isNull);

    final today = DateTime.now();
    await _selectBirthdayDay(tester, today);

    final enabledContinueButton =
        tester.widget<FilledButton>(continueButtonFinder);
    expect(find.text(_birthdayPromptText(today)), findsOneWidget);
    expect(enabledContinueButton.onPressed, isNotNull);
  });

  testWidgets('birthday step allows dates after the current day',
      (tester) async {
    await _enterBirthdayStep(tester);

    final now = DateTime.now();
    final currentMonthDays = DateUtils.getDaysInMonth(now.year, now.month);
    final futureDate = now.day < currentMonthDays
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month + 1, 1);

    if (futureDate.month != now.month || futureDate.year != now.year) {
      final calendarContext = tester.element(find.byType(CalendarDatePicker));
      final localizations = MaterialLocalizations.of(calendarContext);
      await tester.tap(find.byTooltip(localizations.nextMonthTooltip));
      await tester.pumpAndSettle();
    }

    await _selectBirthdayDay(tester, futureDate);

    expect(find.text(_birthdayPromptText(futureDate)), findsOneWidget);
  });

  testWidgets(
      'birthday calendar month navigation buttons switch the displayed month',
      (tester) async {
    await _enterBirthdayStep(tester);

    final calendarContext = tester.element(find.byType(CalendarDatePicker));
    final localizations = MaterialLocalizations.of(calendarContext);
    final now = DateTime.now();
    final currentMonthTitle = localizations.formatMonthYear(
      DateTime(now.year, now.month),
    );
    final nextMonthTitle = localizations.formatMonthYear(
      DateTime(now.year, now.month + 1),
    );

    expect(find.text(currentMonthTitle), findsOneWidget);

    await tester.tap(find.byTooltip(localizations.nextMonthTooltip));
    await tester.pumpAndSettle();

    expect(find.text(nextMonthTitle), findsOneWidget);
  });

  testWidgets(
      'birthday step uses CalendarDatePicker without custom year shortcuts',
      (tester) async {
    await _enterBirthdayStep(tester);

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding_birthday_year_button')),
      findsNothing,
    );
    expect(find.text('快速选择'), findsNothing);
    expect(find.text('快速选择日期/年份'), findsNothing);
  });

  testWidgets('neuter step only shows explicit yes or no options',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '英短');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '母');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _selectBirthdayDay(
      tester,
      DateTime(DateTime.now().year, DateTime.now().month, 15),
    );
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
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();
    await _enterOnboardingFromIntro(tester);

    await tester.enterText(
        find.byKey(const ValueKey('onboarding_name_field')), 'Mochi');
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '英短');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, '母');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    await _selectBirthdayDay(
      tester,
      DateTime(DateTime.now().year, DateTime.now().month, 15),
    );
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
      await tester.pumpWidget(const PetNoteApp());
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

  testWidgets('dock add-pet prerequisite primary button triggers haptics',
      (tester) async {
    final driver = _FakeIntroHapticsDriver();
    SharedPreferences.setMockInitialValues({
      _firstLaunchIntroAutoEnabledKey: false,
    });
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light).copyWith(
          platform: TargetPlatform.android,
        ),
        home: Scaffold(
          body: AddActionSheet(
            store: store,
            introHapticsDriver: driver,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增记录'));
    await tester.pumpAndSettle();
    final addPetButton = find.widgetWithText(FilledButton, '开始添加宠物');
    await _pumpUntilFound(tester, addPetButton);
    await tester.tap(addPetButton);
    await tester.pump();

    expect(driver.events, <String>['button-tap']);
  });

  testWidgets('expanded todo form back returns to action grid', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: _GrantedNotificationPlatformAdapter(),
          appLogController: AppLogController.memory(),
        ),
      ),
    );
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

  testWidgets(
      'root reflects store-managed time-derived refresh on minute boundary',
      (tester) async {
    var now = DateTime.now();
    final dueAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
      nowProvider: () => now,
    );
    await store.dismissFirstLaunchIntro();
    await store.addPet(
      name: 'Luna',
      type: PetType.cat,
      breed: 'British Shorthair',
      sex: 'Female',
      birthday: '2023-04-18',
      weightKg: 4.6,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '早晚各一餐',
      allergies: '无',
      note: '测试宠物',
    );
    await store.addTodo(
      title: '分钟边界刷新测试',
      petId: store.pets.first.id,
      dueAt: dueAt,
      note: '',
    );
    store.setActiveTab(AppTab.checklist);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: _GrantedNotificationPlatformAdapter(),
          appLogController: AppLogController.memory(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('checklist_card_todo-todo-1')),
    );

    expect(find.text('已逾期 0 项'), findsOneWidget);

    now = dueAt.add(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('已逾期 1 项'), findsOneWidget);
  });

  testWidgets(
      'opening add sheet from iOS dock does not throw Flutter layout exceptions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              key: const ValueKey('fake_ios_native_dock'),
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('fake_ios_add_button_for_sheet_test'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('fake_ios_add_button_for_sheet_test')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_sheet_shell')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact add sheet action grid fits within sheet bounds on iPhone-sized iOS screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              key: const ValueKey('fake_ios_native_dock'),
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('fake_ios_add_button_for_layout_test'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('fake_ios_add_button_for_layout_test')));
    await tester.pumpAndSettle();

    final shellRect =
        tester.getRect(find.byKey(const ValueKey('add_sheet_shell')));
    final lastActionCardRect = tester.getRect(find.text('新增爱宠'));

    expect(shellRect.height, greaterThanOrEqualTo(448));
    expect(lastActionCardRect.bottom, lessThanOrEqualTo(shellRect.bottom - 8));
  });

  testWidgets('expanded todo form save closes sheet and persists todo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: _GrantedNotificationPlatformAdapter(),
          appLogController: AppLogController.memory(),
        ),
      ),
    );
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

    expect(store.todos.first.title, '补货主粮');
  });

  testWidgets(
      'record form keeps remaining photos stable during animated removal',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final picker = _FakeNativePetPhotoPicker([
      ['/tmp/petnote-record-1.png', '/tmp/petnote-record-2.png'],
      ['/tmp/petnote-record-3.png'],
    ]);
    debugHasPetPhotoOverride =
        (path) => path != null && path.startsWith('/tmp/petnote-record-');
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required Widget fallback,
      BoxFit fit = BoxFit.cover,
    }) {
      return SizedBox(
        key: ValueKey('debug-record-photo-$photoPath'),
      );
    };

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(PetNoteApp(nativePetPhotoPicker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增记录'));
    await tester.pumpAndSettle();

    expect(find.text('健康'), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('消费'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('图片'), findsNothing);
    expect(find.text('补充说明'), findsNothing);
    expect(find.text('正文'), findsNothing);
    expect(find.byKey(const ValueKey('record_note_field')), findsNothing);
    expect(find.text('可一次选择多张照片'), findsNothing);
    expect(find.text('事实正文'), findsNothing);
    expect(find.byKey(const ValueKey('record_summary_field')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('record_add_photo_button')),
    );
    final addPhotoButtonSize = tester.getSize(
      find.byKey(const ValueKey('record_add_photo_hero_card')),
    );
    expect(addPhotoButtonSize.height, greaterThanOrEqualTo(100));
    expect(addPhotoButtonSize.width, closeTo(addPhotoButtonSize.height, 0.1));
    expect(find.byKey(const ValueKey('record_photo_strip')), findsNothing);
    expect(
        find.byKey(const ValueKey('record_add_photo_tail_card')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('record_add_photo_button')),
    );
    await tester.tap(find.byKey(const ValueKey('record_add_photo_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('record_photo_strip')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('debug-record-photo-/tmp/petnote-record-1.png'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('debug-record-photo-/tmp/petnote-record-2.png'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsNothing,
    );

    final previewSize = tester.getSize(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-1.png')),
    );
    expect(
      addPhotoButtonSize.width,
      closeTo(previewSize.width, 0.1),
    );
    expect(
      addPhotoButtonSize.height,
      closeTo(previewSize.height, 0.1),
    );
    final removeButtonSize = tester.getSize(
      find.byKey(_recordRemovePhotoButtonKey('/tmp/petnote-record-1.png')),
    );
    expect(previewSize.width, greaterThanOrEqualTo(120));
    expect(previewSize.height, greaterThanOrEqualTo(120));
    expect(removeButtonSize.width, lessThanOrEqualTo(32));
    expect(removeButtonSize.height, lessThanOrEqualTo(32));
    expect(find.byKey(const ValueKey('record_add_photo_tail_card')),
        findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('record_add_photo_tail_card')))
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-2.png')),
            )
            .dx,
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('record_add_photo_button')),
    );
    await tester.tap(find.byKey(const ValueKey('record_add_photo_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('debug-record-photo-/tmp/petnote-record-3.png'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-3.png')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('record_add_photo_tail_card')))
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-3.png')),
            )
            .dx,
      ),
    );

    const recordSummary = '吃药后状态稳定，精神恢复正常';
    await tester.enterText(
      find.byKey(const ValueKey('record_summary_field')),
      recordSummary,
    );
    await tester.pump();

    await tester.tap(
      find.byKey(_recordRemovePhotoButtonKey('/tmp/petnote-record-1.png')),
    );
    await tester.pump();
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-1.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-2.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-3.png')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-1.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-2.png')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(picker.deletedPaths, contains('/tmp/petnote-record-1.png'));
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-1.png')),
      findsNothing,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-2.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-3.png')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('record_add_photo_tail_card')))
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-3.png')),
            )
            .dx,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存记录'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getString(_recordsStorageKey);
    expect(recordsJson, isNotNull);
    final decodedRecords = (jsonDecode(recordsJson!) as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList(growable: false);
    expect(decodedRecords.first['purpose'], 'health');
    expect(decodedRecords.first['summary'], recordSummary);
    expect(decodedRecords.first['note'], '');
    expect(decodedRecords.first['photoPaths'], [
      '/tmp/petnote-record-2.png',
      '/tmp/petnote-record-3.png',
    ]);
  });

  testWidgets('record form persists custom purpose labels when selecting other',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          appLogController: AppLogController.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增记录'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('record_custom_purpose_field')),
        findsNothing);

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('record_custom_purpose_field')),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存记录'));
    await tester.pumpAndSettle();
    expect(find.text('请填写 1-12 个字的自定义记录目的'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('record_custom_purpose_field')),
      '术后观察',
    );
    await tester.enterText(
      find.byKey(const ValueKey('record_summary_field')),
      '恢复状态稳定，继续观察。',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存记录'));
    await tester.pumpAndSettle();

    final record = store.records.first;
    expect(record.purpose, RecordPurpose.other);
    expect(record.customPurposeLabel, '术后观察');
  });

  testWidgets(
      'record form reuses a stable empty-state add card after removing all photos',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final picker = _FakeNativePetPhotoPicker([
      ['/tmp/petnote-record-readd-1.png'],
      ['/tmp/petnote-record-readd-2.png'],
    ]);
    debugHasPetPhotoOverride =
        (path) => path != null && path.startsWith('/tmp/petnote-record-readd-');
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required Widget fallback,
      BoxFit fit = BoxFit.cover,
    }) {
      return SizedBox(
        key: ValueKey('debug-record-photo-$photoPath'),
      );
    };

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(PetNoteApp(nativePetPhotoPicker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增记录'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('record_add_photo_hero_card')),
    );
    await tester.tap(find.byKey(const ValueKey('record_add_photo_button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          _recordRemovePhotoButtonKey('/tmp/petnote-record-readd-1.png')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('record_photo_strip')), findsNothing);
    expect(find.byKey(const ValueKey('record_add_photo_hero_card')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsNothing,
    );

    final heroCardLeft = tester
        .getTopLeft(find.byKey(const ValueKey('record_add_photo_hero_card')))
        .dx;

    await tester.ensureVisible(
      find.byKey(const ValueKey('record_add_photo_hero_card')),
    );
    await tester.tap(find.byKey(const ValueKey('record_add_photo_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('record_photo_strip')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsOneWidget,
    );

    final transitionStartLeft = tester
        .getTopLeft(
            find.byKey(const ValueKey('record_add_photo_transition_card')))
        .dx;
    expect((transitionStartLeft - heroCardLeft).abs(), lessThanOrEqualTo(1));

    final midFlightLeftBefore = tester
        .getTopLeft(
            find.byKey(const ValueKey('record_add_photo_transition_card')))
        .dx;
    await tester.pump(const Duration(milliseconds: 160));
    final midFlightLeftAfter = tester
        .getTopLeft(
            find.byKey(const ValueKey('record_add_photo_transition_card')))
        .dx;
    expect(midFlightLeftAfter, greaterThanOrEqualTo(midFlightLeftBefore));

    await tester.pumpAndSettle();

    expect(
      find.byKey(_recordPhotoPreviewKey('/tmp/petnote-record-readd-2.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('record_add_photo_transition_card')),
      findsNothing,
    );
  });

  testWidgets(
      'dock add reminder and record actions expand into full-height form flow',
      (tester) async {
    for (final action in ['新增提醒', '新增记录']) {
      SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
      await tester.pumpWidget(const PetNoteApp());
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

  testWidgets('expanded todo form time field opens a picker flow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: _GrantedNotificationPlatformAdapter(),
          appLogController: AppLogController.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_due_at_field')));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
  });

  testWidgets(
      'expanded todo form shows only simplified core fields on first screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          appLogController: AppLogController.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增待办'));
    await tester.pumpAndSettle();

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('关联爱宠'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('提前通知'), findsOneWidget);
    expect(find.text('补充说明'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存待办'), findsOneWidget);
    expect(find.text('主题'), findsNothing);
    expect(find.text('执行意图'), findsNothing);
    expect(find.text('跟进时间（可选）'), findsNothing);
    expect(find.byKey(const ValueKey('todo_follow_up_field')), findsNothing);
  });

  testWidgets('expanded reminder form uses cupertino picker flow on iOS',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.dark)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey(
                        'fake_ios_add_button_for_cupertino_picker'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const ValueKey('fake_ios_add_button_for_cupertino_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('reminder_scheduled_date_field')),
    );
    await tester
        .tap(find.byKey(const ValueKey('reminder_scheduled_date_field')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets(
      'expanded reminder form save closes sheet and infers reminder kind',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(
        initialValues: _persistedSinglePetPreferences(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetNoteRoot(
          storeLoader: () async => store,
          notificationAdapter: _GrantedNotificationPlatformAdapter(),
          appLogController: AppLogController.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('关联爱宠'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('提前通知'), findsOneWidget);
    expect(find.text('重复规则'), findsNothing);
    expect(find.text('补充说明'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存提醒'), findsOneWidget);
    expect(find.text('主题'), findsNothing);
    expect(find.text('执行意图'), findsNothing);
    expect(find.text('跟进时间（可选）'), findsNothing);
    expect(
        find.byKey(const ValueKey('reminder_follow_up_field')), findsNothing);
    expect(find.text('提前1天'), findsOneWidget);
    expect(find.text('提前3天'), findsOneWidget);
    expect(find.text('提前7天'), findsOneWidget);
    expect(find.text('准时'), findsNothing);
    expect(find.text('提前5分钟'), findsNothing);
    expect(find.text('提前15分钟'), findsNothing);
    expect(find.text('提前1小时'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '年度疫苗补打');
    await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_sheet_shell')), findsNothing);

    final reminder = store.reminders.first;
    expect(reminder.title, '年度疫苗补打');
    expect(reminder.kind, ReminderKind.vaccine);
    expect(reminder.recurrence, '单次');
    expect(reminder.semantic?.topicKey, SemanticTopicKey.vaccine);
    expect(reminder.semantic?.intent, SemanticActionIntent.administer);
  });

  testWidgets('expanded reminder form save button stays above the sheet bottom',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.dark)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey(
                        'fake_ios_add_button_for_expanded_layout'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const ValueKey('fake_ios_add_button_for_expanded_layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();

    final shellRect =
        tester.getRect(find.byKey(const ValueKey('add_sheet_shell')));
    final saveRect = tester.getRect(find.widgetWithText(FilledButton, '保存提醒'));

    expect(saveRect.bottom, lessThanOrEqualTo(shellRect.bottom - 8));
  });

  testWidgets('dock add pet onboarding keeps the original sheet corner radius',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
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
      'dock add pet onboarding shows a top-left back button and returns to actions',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('onboarding_return_to_actions_button')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('onboarding_return_to_actions_button')));
    await tester.pumpAndSettle();

    expect(find.text('新增内容'), findsOneWidget);
    expect(find.text('新增爱宠'), findsOneWidget);
  });

  testWidgets(
      'system back from dock add-pet onboarding returns to actions instead of exiting',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('manual_onboarding_sheet_transition')),
        findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('新增内容'), findsOneWidget);
    expect(find.text('新增爱宠'), findsOneWidget);
    expect(find.byKey(const ValueKey('manual_onboarding_sheet_transition')),
        findsNothing);
    expect(find.byKey(const ValueKey('add_sheet_shell')), findsOneWidget);
  });

  testWidgets(
      'system back from a later add-pet onboarding step returns to the previous step',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('onboarding_name_field')),
      'Mochi',
    );
    await _tapVisibleText(tester, '猫');
    await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
    await tester.pumpAndSettle();

    expect(find.text('选择品种'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('先认识一下'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_name_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('add_sheet_shell')), findsOneWidget);
  });

  testWidgets(
      'dock add pet transition keeps the foreground settling without revealing the action grid',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(
        find.byKey(const ValueKey('add_sheet_push_back_layer')), findsNothing);
    expect(find.text('新增待办'), findsNothing);
    expect(find.byKey(const ValueKey('manual_onboarding_sheet_transition')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('add_sheet_foreground_surface')),
        findsOneWidget);
  });

  testWidgets(
      'expanded reminder transition does not leave a blur layer behind the foreground sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('保存提醒'), findsOneWidget);
    expect(find.byKey(const ValueKey('add_sheet_foreground_surface')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('add_sheet_push_back_layer')), findsNothing);
  });

  testWidgets(
      'manual onboarding from dock defer closes sheet without changing auto-show preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      _firstLaunchIntroAutoEnabledKey: true,
    });
    await tester.pumpWidget(const PetNoteApp());
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

  testWidgets('embedded add-pet onboarding PageView spans the sheet width',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    final shellRect =
        tester.getRect(find.byKey(const ValueKey('add_sheet_shell')));
    final pageViewRect =
        tester.getRect(find.byKey(const ValueKey('onboarding_step_page_view')));

    expect(pageViewRect.left, closeTo(shellRect.left, 0.5));
    expect(pageViewRect.right, closeTo(shellRect.right, 0.5));
  });

  testWidgets('embedded add-pet onboarding content keeps intro-aligned padding',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    final shellRect =
        tester.getRect(find.byKey(const ValueKey('add_sheet_shell')));
    final pageRect =
        tester.getRect(find.byKey(const ValueKey('onboarding_step_page_0')));

    expect(pageRect.left - shellRect.left, closeTo(20, 0.5));
  });

  testWidgets(
      'embedded add-pet onboarding tightens top spacing under drag handle',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增爱宠'));
    await tester.pumpAndSettle();

    final shellRect =
        tester.getRect(find.byKey(const ValueKey('add_sheet_shell')));
    final topBarRect =
        tester.getRect(find.byKey(const ValueKey('onboarding_top_bar_reveal')));
    final pageRect =
        tester.getRect(find.byKey(const ValueKey('onboarding_step_page_0')));

    expect(topBarRect.top - shellRect.top, closeTo(10, 1.0));
    expect(pageRect.top - topBarRect.bottom, closeTo(10, 1.0));
  });

  testWidgets('uses an enlarged dock with unified 17px outer margins',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
    expect(tester.widget(find.byKey(const ValueKey('bottom_nav_blur'))),
        isA<BackdropFilter>());
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock_add_button')), findsOneWidget);

    final addButtonSize =
        tester.getSize(find.byKey(const ValueKey('dock_add_button')));
    expect(addButtonSize.width, greaterThan(48));
    expect(addButtonSize.width, lessThanOrEqualTo(56));
    expect(addButtonSize.height, greaterThan(48));
    expect(addButtonSize.height, lessThanOrEqualTo(56));

    final panelRect =
        tester.getRect(find.byKey(const ValueKey('bottom_nav_panel')));
    final addButtonRect =
        tester.getRect(find.byKey(const ValueKey('dock_add_button')));
    expect(panelRect.height, greaterThan(66));
    expect(panelRect.left, 17);
    expect(
        (tester.view.physicalSize.width / tester.view.devicePixelRatio) -
            panelRect.right,
        17);
    expect((panelRect.center.dx - addButtonRect.center.dx).abs(),
        lessThanOrEqualTo(0.5));
    expect(addButtonRect.top, greaterThanOrEqualTo(panelRect.top));
    expect(addButtonRect.bottom, lessThanOrEqualTo(panelRect.bottom));

    final checklistTab = find.byKey(const ValueKey('tab_checklist'));
    final checklistIcon = tester.widget<Icon>(
      find.descendant(
        of: checklistTab,
        matching: find.byIcon(Icons.checklist_rounded),
      ),
    );
    expect(checklistIcon.size, greaterThan(17));

    final checklistLabel = tester.widget<Text>(
      find.descendant(of: checklistTab, matching: find.text('清单')),
    );
    expect(checklistLabel.style?.fontSize, greaterThan(10.5));
  });

  testWidgets('keeps blur only on the bottom dock and not on content panels',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
  });

  testWidgets('uses iOS native dock host without Flutter dock chrome on iOS',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              key: const ValueKey('fake_ios_native_dock'),
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  Text('selected:${selectedTab.name}'),
                  IconButton(
                    key: const ValueKey('fake_ios_tab_pets'),
                    onPressed: () => onTabSelected(AppTab.pets),
                    icon: const Icon(Icons.pets_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('fake_ios_add'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fake_ios_native_dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsNothing);
    expect(find.byKey(const ValueKey('dock_add_button')), findsNothing);
    expect(find.text('selected:checklist'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fake_ios_tab_pets')));
    await tester.pumpAndSettle();

    expect(find.text('selected:pets'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fake_ios_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_sheet_shell')), findsOneWidget);
  });

  testWidgets('gives the iOS native dock enough height for a floating layout',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IosNativeDockHost(
            selectedTab: AppTab.checklist,
            onTabSelected: _noopTabSelection,
            onAddTap: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    final dockSize =
        tester.getSize(find.byKey(const ValueKey('ios_native_dock_host')));
    expect(dockSize.height, greaterThanOrEqualTo(138));

    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    final creationParams =
        platformView.creationParams! as Map<Object?, Object?>;
    expect(creationParams['brightness'], 'light');
    expect(creationParams['centerSymbolSize'], 42.0);
    expect(creationParams['centerSymbolCanvasOffset'], 8.0);
  });

  testWidgets('uses the warm pet orange theme for primary actions',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
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
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    final metricCardFinder = find.ancestor(
      of: find.text('今日待办'),
      matching: find.byType(Ink),
    );

    expect(metricCardFinder, findsWidgets);

    final coolAccentCard = tester.widget<Ink>(metricCardFinder.first);
    final decoration = coolAccentCard.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFEAF0FF));
  });

  testWidgets('configures transparent immersive status bar wrapper',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    final annotated = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(annotated.value.statusBarColor, const Color(0x00000000));
  });

  testWidgets('shows theme settings on the me page and switches to dark mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var themePreference = AppThemePreference.system;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            theme: buildPetNoteTheme(Brightness.light),
            darkTheme: buildPetNoteTheme(Brightness.dark),
            themeMode: switch (themePreference) {
              AppThemePreference.system => ThemeMode.system,
              AppThemePreference.light => ThemeMode.light,
              AppThemePreference.dark => ThemeMode.dark,
            },
            home: Scaffold(
              body: settings_page.MePage(
                themePreference: themePreference,
                onThemePreferenceChanged: (next) {
                  setState(() {
                    themePreference = next;
                  });
                },
                notificationPermissionState:
                    NotificationPermissionState.unsupported,
                notificationPushToken: null,
                onRequestNotificationPermission: null,
                onOpenNotificationSettings: null,
                onOpenExactAlarmSettings: null,
                settingsController: null,
                aiSettingsCoordinator: null,
                dataStorageCoordinator: null,
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主题外观'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.byKey(const ValueKey('me_theme_slider')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('me_theme_slider_control')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_slider_thumb_icon')), findsNothing);
    expect(find.byKey(const ValueKey('theme_slider_selected_system')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_system')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_light')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_dark')), findsOneWidget);
    expect(find.text(themeModeSectionSubtitle), findsNothing);
    expect(find.byKey(const ValueKey('theme_current_row')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('me_theme_slider_control')),
      const Offset(420, 0),
    );
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(scaffoldContext).brightness, Brightness.dark);
  });

  testWidgets(
      'theme mode options keep standard card spacing and tighter height',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: settings_page.MePage(
            themePreference: AppThemePreference.system,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState:
                NotificationPermissionState.unsupported,
            notificationPushToken: null,
            onRequestNotificationPermission: null,
            onOpenNotificationSettings: null,
            onOpenExactAlarmSettings: null,
            settingsController: null,
            aiSettingsCoordinator: null,
            dataStorageCoordinator: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sliderRect =
        tester.getRect(find.byKey(const ValueKey('me_theme_slider')));
    final systemRect =
        tester.getRect(find.byKey(const ValueKey('theme_option_system')));
    final lightRect =
        tester.getRect(find.byKey(const ValueKey('theme_option_light')));
    final darkRect =
        tester.getRect(find.byKey(const ValueKey('theme_option_dark')));
    final selectedRect = tester.getRect(
      find.byKey(const ValueKey('theme_slider_selected_system')),
    );

    expect(systemRect.height, closeTo(lightRect.height, 0.5));
    expect(lightRect.height, closeTo(darkRect.height, 0.5));
    expect(find.byKey(const ValueKey('theme_current_row')), findsNothing);
    expect(find.byKey(const ValueKey('theme_slider_thumb_icon')), findsNothing);
    expect(selectedRect.height, greaterThan(42));
    expect(selectedRect.height, lessThan(52));
    expect(selectedRect.width, greaterThan(sliderRect.width / 3 - 32));
    expect(selectedRect.width, lessThan(sliderRect.width / 3 + 4));
    final expectedCenterX = sliderRect.left + 6 + selectedRect.width / 2;
    expect(selectedRect.center.dx, closeTo(expectedCenterX, 1.5));
    expect(selectedRect.top, closeTo(sliderRect.top + 6, 1.5));
    expect(selectedRect.bottom, closeTo(sliderRect.bottom - 6, 1.5));
    expect(sliderRect.height, lessThan(66));
  });

  testWidgets('theme slider adapts its surface colors in dark mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        darkTheme: buildPetNoteTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: settings_page.MePage(
            themePreference: AppThemePreference.dark,
            onThemePreferenceChanged: (_) {},
            notificationPermissionState:
                NotificationPermissionState.unsupported,
            notificationPushToken: null,
            onRequestNotificationPermission: null,
            onOpenNotificationSettings: null,
            onOpenExactAlarmSettings: null,
            settingsController: null,
            aiSettingsCoordinator: null,
            dataStorageCoordinator: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sliderContainer = tester.widget<Container>(
      find.byKey(const ValueKey('me_theme_slider')),
    );
    final sliderDecoration = sliderContainer.decoration! as BoxDecoration;
    expect(sliderDecoration.color, isNot(const Color(0xFFFFFFFF)));

    final selectedDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey('theme_slider_selected_dark')),
        )
        .decoration as BoxDecoration;
    expect(selectedDecoration.color, isNot(const Color(0xFF171717)));
  });
  testWidgets('uses amoled-friendly dark theme when persisted in dark mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'dark',
    });
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      PetNoteApp(
        settingsController: settingsController,
        appLogController: AppLogController.memory(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(
      Theme.of(scaffoldContext).scaffoldBackgroundColor,
      const Color(0xFF020304),
    );
  });

  testWidgets(
      'add sheet route chrome follows system brightness changes while open',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);

    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    var bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, lightPetNoteTokens.pageGradientTop);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    final shell = tester.widget<Container>(
      find.byKey(const ValueKey('add_sheet_surface')),
    );
    final shellGradient =
        (shell.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(shellGradient.colors, [
      darkPetNoteTokens.pageGradientTop,
      darkPetNoteTokens.pageGradientBottom,
    ]);

    bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, darkPetNoteTokens.pageGradientTop);
  });

  testWidgets('adapts add sheet surfaces to dark mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'dark',
    });
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      PetNoteApp(
        settingsController: settingsController,
        appLogController: AppLogController.memory(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final shell = tester.widget<Container>(
      find.byKey(const ValueKey('add_sheet_surface')),
    );
    final shellGradient =
        (shell.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(shellGradient.colors, [
      darkPetNoteTokens.pageGradientTop,
      darkPetNoteTokens.pageGradientBottom,
    ]);

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, darkPetNoteTokens.pageGradientTop);

    final title = tester.widget<Text>(find.text('新增内容'));
    expect(title.style?.color, darkPetNoteTokens.primaryText);

    final subtitle = tester.widget<Text>(find.text('今天要给毛孩子加点什么新内容？'));
    expect(subtitle.style?.color, darkPetNoteTokens.secondaryText);

    final cardTitle = tester.widget<Text>(find.text('新增待办'));
    expect(cardTitle.style?.color, darkPetNoteTokens.primaryText);
  });

  testWidgets('notification action buttons share the same pill layout',
      (tester) async {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('me_notification_entry')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('me_request_notification_button')),
      160,
    );
    await tester.pumpAndSettle();

    final requestFinder =
        find.byKey(const ValueKey('me_request_notification_button'));
    final settingsFinder =
        find.byKey(const ValueKey('me_open_notification_settings_button'));

    expect(requestFinder, findsOneWidget);
    expect(settingsFinder, findsOneWidget);

    final requestSize = tester.getSize(requestFinder);
    final settingsSize = tester.getSize(settingsFinder);
    expect(requestSize.height, closeTo(settingsSize.height, 0.1));

    final requestStyle = tester.widget<FilledButton>(requestFinder).style!;
    final settingsStyle = tester.widget<OutlinedButton>(settingsFinder).style!;

    final requestShape =
        requestStyle.shape!.resolve({})! as RoundedRectangleBorder;
    final settingsShape =
        settingsStyle.shape!.resolve({})! as RoundedRectangleBorder;

    expect(requestShape.borderRadius, settingsShape.borderRadius);
    expect(requestShape.borderRadius, BorderRadius.circular(999));
  });

  testWidgets('adapts first-launch intro surfaces to dark mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
    });
    final settingsController = await AppSettingsController.load();

    await tester.pumpWidget(
      PetNoteApp(
        settingsController: settingsController,
        appLogController: AppLogController.memory(),
      ),
    );
    await tester.pumpAndSettle();

    final overlayMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('first_launch_intro_overlay')),
    );
    expect(
      overlayMaterial.color,
      buildPetNoteTheme(Brightness.dark)
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
      darkPetNoteTokens.pageGradientTop,
      darkPetNoteTokens.pageGradientBottom,
    ]);

    final title = tester.widget<Text>(find.text('欢迎来到宠记'));
    expect(title.style?.color, darkPetNoteTokens.primaryText);
  });

  testWidgets(
      'material date picker follows system brightness changes while open',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('爱宠'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_pet_button')));
    await tester.pumpAndSettle();
    final birthdayButton =
        find.byKey(const ValueKey('edit_pet_birthday_button'));
    final editSheetScrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      birthdayButton,
      120,
      scrollable: editSheetScrollable,
    );
    await tester.tap(birthdayButton);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    var dialogContext = tester.element(find.byType(DatePickerDialog));
    expect(Theme.of(dialogContext).brightness, Brightness.light);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    dialogContext = tester.element(find.byType(DatePickerDialog));
    expect(Theme.of(dialogContext).brightness, Brightness.dark);
  });

  testWidgets(
      'material time picker follows system brightness changes while open',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();
    final reminderDateTimeField =
        find.byKey(const ValueKey('reminder_scheduled_at_field'));
    final addSheetScrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      reminderDateTimeField,
      120,
      scrollable: addSheetScrollable,
    );
    await tester.tap(reminderDateTimeField);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dateDialogContext = tester.element(find.byType(DatePickerDialog));
    final okLabel = MaterialLocalizations.of(dateDialogContext).okButtonLabel;
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text(okLabel),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    var timeDialogContext = tester.element(find.byType(TimePickerDialog));
    expect(Theme.of(timeDialogContext).brightness, Brightness.light);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    timeDialogContext = tester.element(find.byType(TimePickerDialog));
    expect(Theme.of(timeDialogContext).brightness, Brightness.dark);
  });

  testWidgets(
      'cupertino picker popup follows system brightness changes while open',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        darkTheme: buildPetNoteTheme(Brightness.dark)
            .copyWith(platform: TargetPlatform.iOS),
        themeMode: ThemeMode.system,
        home: PetNoteRoot(
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return Container(
              height: 84,
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('fake_ios_add_button_for_picker_theme'),
                    onPressed: onAddTap,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('fake_ios_add_button_for_picker_theme')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增提醒'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('reminder_scheduled_date_field')),
    );
    await tester
        .tap(find.byKey(const ValueKey('reminder_scheduled_date_field')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    var pickerShell = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(CupertinoDatePicker),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color != null,
            ),
          )
          .first,
    );
    var pickerDecoration = pickerShell.decoration as BoxDecoration;
    expect(pickerDecoration.color, Colors.white);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    pickerShell = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(CupertinoDatePicker),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color != null,
            ),
          )
          .first,
    );
    pickerDecoration = pickerShell.decoration as BoxDecoration;
    expect(pickerDecoration.color, const Color(0xFF1C1C1E));
  });

  testWidgets(
      'pet edit sheet route chrome follows system brightness changes while open',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);

    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('爱宠'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_pet_button')));
    await tester.pumpAndSettle();

    var bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, lightPetNoteTokens.pageGradientTop);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.backgroundColor, darkPetNoteTokens.pageGradientTop);

    final title = tester.widget<Text>(find.text('编辑爱宠资料'));
    expect(title.style?.color, darkPetNoteTokens.primaryText);
  });

  testWidgets('restores persisted system theme preference', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._persistedSinglePetPreferences(),
      'app_theme_mode_v1': 'system',
    });
    await tester.pumpWidget(const PetNoteApp());
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('uses explicit insets instead of nested SafeArea wrappers',
      (tester) async {
    await tester.pumpWidget(const PetNoteApp());
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

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 6),
  Duration step = const Duration(milliseconds: 40),
}) async {
  var elapsed = Duration.zero;
  while (finder.evaluate().isEmpty && elapsed < timeout) {
    await tester.pump(step);
    elapsed += step;
  }
  expect(finder, findsOneWidget, reason: _visibleValueKeys(tester));
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 6),
  Duration step = const Duration(milliseconds: 40),
}) async {
  var elapsed = Duration.zero;
  while (finder.evaluate().isNotEmpty && elapsed < timeout) {
    await tester.pump(step);
    elapsed += step;
  }
  expect(finder, findsNothing, reason: _visibleValueKeys(tester));
}

String _visibleValueKeys(WidgetTester tester) {
  final keys = tester.allWidgets
      .map((widget) => widget.key)
      .whereType<ValueKey<Object?>>()
      .map((key) => key.value.toString())
      .take(80)
      .join(', ');
  return '当前树上的 ValueKey：$keys';
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

double _scaleByKey(WidgetTester tester, ValueKey<String> key) {
  final transform = tester.widget<Transform>(find.byKey(key));
  return transform.transform.storage[0];
}

Color? _iconColorByKey(WidgetTester tester, ValueKey<String> key) {
  return tester
      .widget<Icon>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(Icon),
        ),
      )
      .color;
}

Color? _selectedIndicatorColor(WidgetTester tester) {
  final indicatorFinder = find.descendant(
    of: find.byKey(const ValueKey('first_launch_intro_indicator')),
    matching: find.byType(AnimatedContainer),
  );
  for (var index = 0; index < indicatorFinder.evaluate().length; index++) {
    final finder = indicatorFinder.at(index);
    if (tester.getSize(finder).width > 16) {
      final selected = tester.widget<AnimatedContainer>(finder);
      final decoration = selected.decoration! as BoxDecoration;
      return decoration.color;
    }
  }
  return null;
}

Finder _introHeroIconFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith('intro_page_') &&
        (widget.key as ValueKey<String>).value.endsWith('_hero_icon'),
  );
}

class _FakeIntroHapticsDriver implements IntroHapticsDriver {
  _FakeIntroHapticsDriver({
    this.prepareFutureFactory,
  });

  final List<String> events = <String>[];
  final Future<void> Function()? prepareFutureFactory;

  @override
  Future<void> prepareIntroLaunchHaptics() async {
    events.add('prepare');
    final prepareFutureFactory = this.prepareFutureFactory;
    if (prepareFutureFactory != null) {
      await prepareFutureFactory();
    }
  }

  @override
  Future<void> playIntroLaunchContinuous() async {
    events.add('start');
  }

  @override
  Future<void> stopIntroLaunchContinuous() async {
    events.add('stop');
  }

  @override
  Future<void> playIntroToOnboardingContinuous() async {
    events.add('onboarding-start');
  }

  @override
  Future<void> stopIntroToOnboardingContinuous() async {
    events.add('onboarding-stop');
  }

  @override
  Future<void> playIntroPrimaryButtonTap() async {
    events.add('button-tap');
  }
}

class _GrantedNotificationPlatformAdapter
    implements NotificationPlatformAdapter {
  final List<NotificationJob> scheduledJobs = <NotificationJob>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> getPermissionState() async =>
      NotificationPermissionState.authorized;

  @override
  Future<bool> hasHandledPermissionPrompt() async => true;

  @override
  Future<PermissionRequestOutcome<NotificationPermissionState>>
      requestPermission() async {
    return const PermissionRequestOutcome(
      state: NotificationPermissionState.authorized,
      promptHandledSystemDialog: true,
    );
  }

  @override
  Future<void> scheduleLocalNotification(NotificationJob job) async {
    scheduledJobs.removeWhere((existing) => existing.key == job.key);
    scheduledJobs.add(job);
  }

  @override
  Future<bool> hasScheduledNotification(String key) async =>
      scheduledJobs.any((job) => job.key == key);

  @override
  Future<void> cancelNotification(String key) async {
    scheduledJobs.removeWhere((job) => job.key == key);
  }

  @override
  Future<void> resetScheduledNotifications() async {
    scheduledJobs.clear();
  }

  @override
  Future<void> showUpdateNotification({
    required String title,
    required String body,
    required Uri releaseUrl,
  }) async {}

  @override
  Future<NotificationLaunchIntent?> getInitialLaunchIntent() async => null;

  @override
  Future<NotificationLaunchIntent?> consumeForegroundTap() async => null;

  @override
  Future<String?> registerPushToken() async => null;

  @override
  Future<NotificationSettingsOpenResult> openNotificationSettings() async =>
      NotificationSettingsOpenResult.opened;

  @override
  Future<NotificationSettingsOpenResult> openExactAlarmSettings() async =>
      NotificationSettingsOpenResult.opened;

  @override
  Future<NotificationPlatformCapabilities> getCapabilities() async =>
      const NotificationPlatformCapabilities();
}

class _FakeNativePetPhotoPicker implements NativePetPhotoPicker {
  _FakeNativePetPhotoPicker(this.batches);

  final List<List<String>> batches;
  final List<String> deletedPaths = <String>[];
  int _nextIndex = 0;

  @override
  Future<NativePetPhotoPickerResult> pickPetPhoto() async {
    if (_nextIndex >= batches.length || batches[_nextIndex].isEmpty) {
      return const NativePetPhotoPickerResult.cancelled();
    }
    final path = batches[_nextIndex].first;
    _nextIndex += 1;
    return NativePetPhotoPickerResult.success(localPath: path);
  }

  @override
  Future<NativePetPhotoPickerBatchResult> pickPetPhotos() async {
    if (_nextIndex >= batches.length) {
      return const NativePetPhotoPickerBatchResult.cancelled();
    }
    final selectedPaths = batches[_nextIndex];
    _nextIndex += 1;
    if (selectedPaths.isEmpty) {
      return const NativePetPhotoPickerBatchResult.cancelled();
    }
    return NativePetPhotoPickerBatchResult.success(localPaths: selectedPaths);
  }

  @override
  Future<void> deletePetPhoto(String path) async {
    deletedPaths.add(path);
  }
}

ValueKey<String> _recordPhotoPreviewKey(String path) {
  return ValueKey<String>('record_photo_preview_$path');
}

ValueKey<String> _recordRemovePhotoButtonKey(String path) {
  return ValueKey<String>('record_remove_photo_${path}_button');
}

double _fixedHeroScale(WidgetTester tester) {
  final exitScale = find.byKey(
    const ValueKey('intro_onboarding_exit_hero_scale'),
    skipOffstage: false,
  );
  if (exitScale.evaluate().isNotEmpty) {
    final transform = tester.widget<Transform>(exitScale);
    final scale = transform.transform.storage[0];
    if ((scale - 1).abs() > 0.001) {
      return scale;
    }
  }
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byKey(const ValueKey('intro_fixed_hero_host')),
          matching: find.byType(Transform),
          matchRoot: true,
        )
        .first,
  );
  return transform.transform.storage[0];
}

double _opacityByKey(WidgetTester tester, ValueKey<String> key) {
  final opacity = tester.widget<Opacity>(find.byKey(key));
  return opacity.opacity;
}

double _translateDyByKey(WidgetTester tester, ValueKey<String> key) {
  final transform = tester.widget<Transform>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(Transform))
        .first,
  );
  return transform.transform.storage[13];
}

IconData _iconDataByKey(WidgetTester tester, ValueKey<String> key) {
  return tester.widget<Icon>(find.byKey(key)).icon!;
}

Future<void> _advanceIntroToFinalPage(WidgetTester tester) async {
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('intro_page_0_content')),
  );
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump();
  for (var i = 0; i < 2; i++) {
    final continueButton =
        find.byKey(const ValueKey('first_launch_intro_continue_button'));
    await _pumpUntilFound(tester, continueButton);
    await tester.tap(continueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
  }
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('first_launch_intro_primary_button')),
  );
  await tester.pump(const Duration(milliseconds: 2200));
  await tester.pump();
}

Future<void> _enterOnboardingFromIntro(WidgetTester tester) async {
  await _advanceIntroToFinalPage(tester);
  final primaryButton =
      find.byKey(const ValueKey('first_launch_intro_primary_button'));
  await tester.tap(primaryButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump();
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('onboarding_return_to_intro_button')),
  );
}

Future<void> _enterBirthdayStep(WidgetTester tester) async {
  await tester.pumpWidget(const PetNoteApp());
  await tester.pumpAndSettle();
  await _enterOnboardingFromIntro(tester);
  await _enterBirthdayStepInCurrentFlow(tester);
}

Future<void> _enterBirthdayStepInCurrentFlow(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const ValueKey('onboarding_name_field')), 'Nori');
  await _tapVisibleText(tester, '猫');
  await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
  await tester.pumpAndSettle();

  await _tapVisibleText(tester, '英短');
  await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
  await tester.pumpAndSettle();

  await _tapVisibleText(tester, '母');
  await tester.tap(find.byKey(const ValueKey('onboarding_continue_button')));
  await tester.pumpAndSettle();

  expect(
    find.byType(CalendarDatePicker),
    findsOneWidget,
  );
}

Future<void> _selectBirthdayDay(WidgetTester tester, DateTime date) async {
  final dayFinder = find.descendant(
    of: find.byType(CalendarDatePicker),
    matching: find.text('${date.day}'),
  );
  await tester.ensureVisible(dayFinder.first);
  await tester.tap(dayFinder.first);
  await tester.pumpAndSettle();
}

Future<void> _tapVisibleText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

String _birthdayPromptText(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '已选择 ${date.year}年$month月$day日';
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

void _noop() {}

void _noopTabSelection(AppTab _) {}
