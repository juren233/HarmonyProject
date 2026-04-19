import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/app/ai_settings_page.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/app/overview_bottom_cta.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
  });

  tearDown(() {
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
  });

  testWidgets(
      'overview page generates restructured AI care report only after tapping button',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 0);
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsNothing);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-select-all-checkbox')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-pet-option-pet-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-pet-option-pet-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);

    final context = tester.element(find.byType(OverviewPage));
    final overviewAccent = tabAccentFor(context, AppTab.overview).label;
    final rangeButtonContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('overview-range-menu-button')),
            matching: find.byType(Container),
          )
          .first,
    );
    final rangeButtonDecoration =
        rangeButtonContainer.decoration! as BoxDecoration;
    final floatingGenerateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    final floatingButtonRect = tester.getRect(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );

    expect(floatingButtonRect.bottom, greaterThan(460));
    expect((rangeButtonDecoration.color!).a, 1);
    expect(rangeButtonDecoration.color, overviewAccent);
    expect(floatingGenerateButton.style?.backgroundColor?.resolve({}),
        overviewAccent);
    expect(floatingGenerateButton.style?.foregroundColor?.resolve({}),
        Colors.white);

    await tester.tap(find.byKey(const ValueKey('overview-range-menu-button')));
    await tester.pumpAndSettle();
    final menuMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('1个月').last,
            matching: find.byType(Material),
          )
          .last,
    );
    expect((menuMaterial.color!).a, 1);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.byTooltip('配置'), findsNothing);
    expect(find.text('关键变化'), findsNothing);
    expect(find.text('照护观察'), findsNothing);
    expect(find.text('风险提醒'), findsNothing);
    expect(find.text('建议行动'), findsNothing);
    expect(find.text('说明'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    expect(find.text('86'), findsOneWidget);
    expect(find.text('基本稳定'), findsWidgets);
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('优先补上 Luna 的耳道复查'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('优先补上 Luna 的耳道复查'), findsOneWidget);
    expect(find.text('安排 Milo 的皮肤复查闭环'), findsOneWidget);
    expect(find.text('本周补一次 Luna 的耳道观察'), findsOneWidget);
    expect(find.text('确认 Milo 下一次复查时间并补上记录'), findsOneWidget);
    expect(find.text('耳道护理线索还没有新的闭环记录。'), findsNothing);
    expect(find.text('皮肤问题已有既往记录，但复查节奏还不够稳定。'), findsNothing);
    expect(find.text('执行总评'), findsNothing);
    expect(find.text('分析对象'), findsNothing);
    expect(service.generateCareReportCalls, 1);
    expect(find.text('AI 总览'), findsNothing);
    expect(find.text('AI 建议'), findsOneWidget);
    expect(find.text('Luna'), findsWidgets);
    expect(find.text('Milo'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Luna 的提醒和记录都在跟进，但耳道问题还缺最后一步复查闭环。'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('为什么是这个分数？'), findsOneWidget);
    expect(find.text('你漏了什么重要信息？'), findsOneWidget);
    expect(find.text('后续怎么跟进？'), findsOneWidget);
    expect(find.text('Luna 的提醒和记录都在跟进，但耳道问题还缺最后一步复查闭环。'), findsOneWidget);
    expect(find.text('详细分析'), findsOneWidget);
    expect(find.text('Milo 的基础提醒基本稳定，但皮肤复查后的持续跟进还不够完整。'), findsNothing);
    expect(find.byKey(const ValueKey('ai-pet-detail-panel-pet-1')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('ai-pet-detail-panel-pet-2')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('ai-pet-tab-pet-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-pet-tab-pet-2')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai-pet-detail-panel-pet-1')), findsNothing);
    expect(find.byKey(const ValueKey('ai-pet-detail-panel-pet-2')),
        findsOneWidget);
    expect(find.text('Luna 的提醒和记录都在跟进，但耳道问题还缺最后一步复查闭环。'), findsNothing);
    expect(find.text('Milo 的基础提醒基本稳定，但皮肤复查后的持续跟进还不够完整。'), findsOneWidget);
    expect(find.text('为什么是这个分数？'), findsOneWidget);
    expect(find.text('你漏了什么重要信息？'), findsOneWidget);
    expect(find.text('后续怎么跟进？'), findsOneWidget);
  });

  testWidgets(
      'overview page prefers pet photo and uses emoji or abbreviation fallback',
      (tester) async {
    final photoPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}petnote-overview-avatar-${DateTime.now().microsecondsSinceEpoch}.bin';
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
    await store.addPet(
      name: '龙宝',
      type: PetType.other,
      photoPath: null,
      breed: '其他',
      sex: 'Unknown',
      birthday: '2024-01-01',
      weightKg: 2.4,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '保持环境湿度稳定',
      allergies: '未填写',
      note: '异宠，需要单独观察。',
    );
    final otherPet = store.pets.firstWhere((pet) => pet.name == '龙宝');
    store.setActiveTab(AppTab.overview);

    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('overview-pet-option-pet-1')),
        matching: find.byKey(ValueKey('debug-pet-photo-$photoPath')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('overview-pet-option-pet-2')),
        matching: find.text('🐶'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('overview-pet-option-${otherPet.id}')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == otherPet.avatarText &&
              widget.textAlign == null,
        ),
      ),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-pet-tab-pet-1')),
        matching: find.byKey(ValueKey('debug-pet-photo-$photoPath')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-pet-tab-pet-2')),
        matching: find.text('🐶'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'overview hero keeps large score size without overly heavy weight',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    final scoreText = tester.widget<Text>(find.text('86').first);
    final statusText = tester.widget<Text>(find.text('基本稳定').first);
    final summaryText = tester.widget<Text>(
      find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'),
    );
    final scoreStack = find.ancestor(
      of: find.text('86').first,
      matching: find.byType(Stack),
    );
    final statusTopRightAlign = find.ancestor(
      of: find.text('基本稳定').first,
      matching: find.byWidgetPredicate(
        (widget) => widget is Align && widget.alignment == Alignment.topRight,
      ),
    );
    final statusStack = find.ancestor(
      of: find.text('基本稳定').first,
      matching: find.byType(Stack),
    );

    expect(scoreText.style?.fontSize, 145);
    expect(scoreText.style?.fontWeight, FontWeight.w400);
    expect(statusText.style?.fontWeight, FontWeight.w600);
    expect(summaryText.style?.fontWeight, FontWeight.w500);
    expect(statusTopRightAlign, findsOneWidget);
    expect(scoreStack, findsWidgets);
    expect(statusStack, findsWidgets);
  });

  testWidgets(
      'overview floating generate button stays above the real iOS dock host with a fixed clearance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    final store = PetNoteStore.seeded()..setActiveTab(AppTab.overview);
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          storeLoader: () async => store,
          aiInsightsService: service,
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return const SizedBox(
              key: ValueKey('fake_ios_native_dock_for_overview_button'),
              height: iosNativeDockHostHeight,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final floatingButtonRect = tester.getRect(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    final dockRect = tester.getRect(
      find.byKey(const ValueKey('fake_ios_native_dock_for_overview_button')),
    );
    final clearance = dockRect.top - floatingButtonRect.bottom;
    const expectedClearance = overviewBottomCtaDockGap;

    expect(clearance, closeTo(expectedClearance, 0.1));
    expect(
      floatingButtonRect.bottom,
      lessThanOrEqualTo(
        dockRect.top - expectedClearance + 0.1,
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('overview-floating-generate-button')),
        matching: find.byType(OverviewPage),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'overview floating generate button keeps the same clearance above the iOS dock host on taller devices',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    final store = PetNoteStore.seeded()..setActiveTab(AppTab.overview);
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.iOS),
        home: PetNoteRoot(
          storeLoader: () async => store,
          aiInsightsService: service,
          iosDockBuilder: (context, selectedTab, onTabSelected, onAddTap) {
            return const SizedBox(
              key: ValueKey('fake_ios_native_dock_for_overview_button_tall'),
              height: iosNativeDockHostHeight,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final floatingButtonRect = tester.getRect(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    final dockRect = tester.getRect(
      find.byKey(
          const ValueKey('fake_ios_native_dock_for_overview_button_tall')),
    );
    final clearance = dockRect.top - floatingButtonRect.bottom;
    const expectedClearance = overviewBottomCtaDockGap;

    expect(clearance, closeTo(expectedClearance, 0.1));
  });

  testWidgets(
      'overview setup keeps the CTA fixed while the page content scrolls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    final store = PetNoteStore.seeded();
    for (var index = 0; index < 24; index += 1) {
      await store.addPet(
        name: '加测宠物$index',
        type: PetType.cat,
        breed: 'Mixed',
        sex: 'Unknown',
        birthday: '2024-01-01',
        weightKg: 3.0 + index,
        neuterStatus: PetNeuterStatus.unknown,
        feedingPreferences: '测试用',
        allergies: '未填写',
        note: '用于拉长总览设置页滚动高度。',
      );
    }
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttonFinder =
        find.byKey(const ValueKey('overview-floating-generate-button'));
    final promptFinder =
        find.byKey(const ValueKey('overview-generation-prompt-row'));
    final beforeButtonRect = tester.getRect(buttonFinder);
    final beforePromptRect = tester.getRect(promptFinder);

    await tester.fling(
        find.byType(ListView).first, const Offset(0, -700), 1400);
    await tester.pumpAndSettle();

    final afterButtonRect = tester.getRect(buttonFinder);
    final afterPromptRect = tester.getRect(promptFinder);

    expect(afterButtonRect.top, closeTo(beforeButtonRect.top, 0.1));
    expect(afterPromptRect.top, lessThan(beforePromptRect.top));
  });

  testWidgets('overview page shows generation setup without AI service',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(OverviewPage));
    final overviewAccent = tabAccentFor(context, AppTab.overview).label;
    final selectAllCheckbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('overview-select-all-checkbox')),
    );
    final floatingGenerateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    final disabledButtonBackground = floatingGenerateButton
        .style?.backgroundColor
        ?.resolve({WidgetState.disabled});

    expect(disabledButtonBackground, isNotNull);
    expect(disabledButtonBackground!.a, 1);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('当前尚未配置AI服务，点我前往设置页进行配置➔'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsNothing);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
    expect(selectAllCheckbox.checkColor, overviewAccent);
    expect(selectAllCheckbox.fillColor?.resolve({WidgetState.selected}),
        overviewAccent.withValues(alpha: 0.14));
    expect(find.text('关键变化'), findsNothing);
    expect(find.text('AI 总览'), findsNothing);
  });

  testWidgets(
      'overview page refreshes provider availability after returning from AI settings',
      (tester) async {
    final store = PetNoteStore.seeded();
    final navigatorKey = GlobalKey<NavigatorState>();
    final service = _MutableAvailabilityAiInsightsService(isConfigured: false);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
          onOpenAiSettings: () => navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('AI 配置')),
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      service.isConfigured = true;
                      Navigator.of(context).pop();
                    },
                    child: const Text('保存 AI 配置'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前尚未配置AI服务，点我前往设置页进行配置➔'), findsOneWidget);
    final disabledGenerateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    expect(disabledGenerateButton.enabled, isFalse);

    await tester
        .tap(find.byKey(const ValueKey('overview-open-ai-settings-link')));
    await tester.pumpAndSettle();
    expect(find.text('AI 配置'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存 AI 配置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    final enabledGenerateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    expect(enabledGenerateButton.enabled, isTrue);
    expect(service.hasActiveProviderCalls, greaterThanOrEqualTo(2));
  });
  testWidgets(
      'overview setup keeps pet grid spacing aligned and opens AI settings',
      (tester) async {
    final store = PetNoteStore.seeded();
    final settingsController = await AppSettingsController.load();
    final navigatorKey = GlobalKey<NavigatorState>();
    final coordinator = AiSettingsCoordinator(
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
      connectionTester: AiConnectionTester(
        transport: _UnexpectedNetworkTransport(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          onOpenAiSettings: () => navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => AiSettingsPage(
                settingsController: settingsController,
                coordinator: coordinator,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-open-ai-settings-link')));
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(find.text('AI 配置'), findsOneWidget);
  });

  testWidgets(
      'overview page does not show an error card before the user asks to generate',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: _FakeAiInsightsService(
            isConfigured: true,
            generateCareReportError: const AiGenerationException('服务暂时不可用'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
    expect(find.text('服务暂时不可用'), findsNothing);
    expect(find.text('AI 总览'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    expect(find.text('服务暂时不可用'), findsOneWidget);
  });

  testWidgets(
      'overview page keeps generation setup when saved AI config is malformed',
      (tester) async {
    final store = PetNoteStore.seeded();
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-11T11:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-broken',
        displayName: 'Broken config',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: '{"broken":true}',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-broken', 'sk-test');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: NetworkAiInsightsService(
            clientFactory: AiClientFactory(
              settingsController: settingsController,
              secretStore: secretStore,
            ),
            transport: _UnexpectedNetworkTransport(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('当前尚未配置AI服务，点我前往设置页进行配置➔'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsNothing);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '生成 AI 总览'), findsNothing);
    expect(find.textContaining('Base URL'), findsNothing);
  });

  testWidgets('pets page shows the selected pet profile by default',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('爱宠'), findsOneWidget);
    expect(find.text('Luna 的照护档案'), findsOneWidget);
    expect(find.text('Milo'), findsWidgets);
  });

  testWidgets(
      'pets page restores metric cards that drill into dedicated detail pages',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('近期提醒').first);
    await tester.pumpAndSettle();

    expect(find.text('近期提醒'), findsWidgets);
    expect(find.text('Luna'), findsWidgets);
    expect(find.text('三联疫苗加强'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料记录').first);
    await tester.pumpAndSettle();

    expect(find.text('资料记录'), findsWidgets);
    expect(find.text('耳道清洁复诊'), findsOneWidget);
  });

  testWidgets(
      'overview setup controls selected pets and range before generation',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(
        oneLineSummary: '配置后的总览已生成。',
      ),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('overview-range-menu-button')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('1个月').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('overview-pet-option-pet-2')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    expect(service.lastCareContext, isNotNull);
    expect(service.lastCareContext!.pets.map((pet) => pet.name).toList(),
        ['Luna']);
    expect(service.lastCareContext!.todos, isEmpty);
    expect(service.lastCareContext!.reminders, isEmpty);
    expect(
      service.lastCareContext!.records.map((record) => record.title).toList(),
      ['耳道清洁复诊'],
    );
    expect(
      service.lastCareContext!.rangeEnd
          .difference(service.lastCareContext!.rangeStart)
          .inDays,
      30,
    );
  });

  testWidgets(
      'overview setup allows clearing all pets and disables generate button',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-pet-selected-overlay-pet-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-pet-selected-check-pet-2')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('overview-pet-option-pet-2')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(store.overviewSelectedPetIds, ['pet-1']);
    expect(find.byKey(const ValueKey('overview-pet-selected-overlay-pet-2')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('overview-pet-option-pet-1')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(store.overviewSelectedPetIds, isEmpty);
    expect(find.byKey(const ValueKey('overview-pet-selected-check-pet-1')),
        findsNothing);

    final generateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-floating-generate-button')),
    );
    expect(generateButton.onPressed, isNull);

    await tester.tap(
        find.byKey(const ValueKey('overview-floating-generate-button')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 0);
  });

  testWidgets(
      'overview header generate button stays disabled when report exists but no pets are selected',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 1);

    final currentConfig = store.overviewAnalysisConfig;
    store.updateOverviewAnalysisConfig(
      range: currentConfig.range,
      selectedPetIds: const [],
      customRangeStart: currentConfig.customRangeStart,
      customRangeEnd: currentConfig.customRangeEnd,
    );
    await tester.pumpAndSettle();

    final headerGenerateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '生成总览'),
    );
    expect(headerGenerateButton.onPressed, isNull);

    await tester.tap(
      find.widgetWithText(FilledButton, '生成总览'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 1);
  });

  testWidgets(
      'overview page keeps loading state and final report after switching tabs',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _DeferredAiInsightsService(
      isConfigured: true,
      careReportFuture: Completer<AiCareReport>(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pump();

    expect(find.text('正在分析'), findsOneWidget);
    expect(find.text('AI 正在生成新的专业分析报告…'), findsNothing);
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-title-shimmer')),
        findsOneWidget);
    final overviewContext = tester.element(find.byType(OverviewPage));
    final generatingTitle = tester.widget<Text>(
      find.byKey(const ValueKey('overview-generating-title-label')),
    );
    expect(generatingTitle.style?.color,
        overviewContext.petNoteTokens.primaryText);
    expect(find.byKey(const ValueKey('overview-generating-experience')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-carousel')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-avatar-pet-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-strip')),
        findsNothing);
    expect(find.byTooltip('配置'), findsOneWidget);
    final analyzingButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-generating-analyzing-button')),
    );
    expect(analyzingButton.onPressed, isNull);
    expect(service.generateCareReportCalls, 1);
    expect(service.forceRefreshValues, <bool>[false]);

    final initialBreathingScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-breath-group-pet-1')),
    );
    expect(initialBreathingScale.transform.storage[0], closeTo(1.0, 0.001));
    expect(initialBreathingScale.transform.storage[5], closeTo(1.0, 0.001));
    expect(
      find.byKey(const ValueKey('overview-generating-pet-breath-group-pet-1')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 700));
    final expandedBreathingScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-breath-group-pet-1')),
    );
    expect(expandedBreathingScale.transform.storage[0], greaterThan(1.1));
    expect(expandedBreathingScale.transform.storage[5], greaterThan(1.1));

    await tester.pump(const Duration(milliseconds: 260));
    final generatingTransitionTop = tester
        .getTopLeft(
            find.byKey(const ValueKey('overview-generating-title-label')))
        .dy;
    await tester.pump(const Duration(milliseconds: 520));
    final generatingSettledTop = tester
        .getTopLeft(
            find.byKey(const ValueKey('overview-generating-title-label')))
        .dy;
    expect(generatingTransitionTop, lessThanOrEqualTo(generatingSettledTop));

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('overview-generating-pet-avatar-pet-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-avatar-pet-2')),
        findsNothing);
    final switchingAvatarScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-avatar-scale-pet-1')),
    );
    expect(switchingAvatarScale.transform.storage[0], greaterThan(1.0));
    expect(switchingAvatarScale.transform.storage[5], greaterThan(1.0));

    await tester.pump(const Duration(milliseconds: 90));
    await tester.pump();
    expect(find.byKey(const ValueKey('overview-generating-pet-avatar-pet-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-avatar-pet-1')),
        findsNothing);

    final switchedAvatarScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-avatar-scale-pet-2')),
    );
    expect(switchedAvatarScale.transform.storage[0], lessThan(1.0));
    expect(switchedAvatarScale.transform.storage[5], lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump();
    final reboundingAvatarScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-avatar-scale-pet-2')),
    );
    expect(reboundingAvatarScale.transform.storage[0], greaterThan(0.8));
    expect(reboundingAvatarScale.transform.storage[0], lessThan(0.98));
    expect(reboundingAvatarScale.transform.storage[5], greaterThan(0.8));
    expect(reboundingAvatarScale.transform.storage[5], lessThan(0.98));

    final contractedBreathingScale = tester.widget<Transform>(
      find.byKey(const ValueKey('overview-generating-pet-breath-group-pet-2')),
    );
    expect(contractedBreathingScale.transform.storage[0], lessThan(0.9));
    expect(contractedBreathingScale.transform.storage[5], lessThan(0.9));

    store.setActiveTab(AppTab.checklist);
    await tester.pumpAndSettle();
    expect(find.text('清单'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pump();
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsOneWidget);

    service.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();

    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);
  });

  testWidgets('overview page keeps generated report after switching tabs',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final initialService = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );
    final refreshService = _DeferredAiInsightsService(
      isConfigured: true,
      careReportFuture: Completer<AiCareReport>(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: initialService),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);

    store.setActiveTab(AppTab.pets);
    await tester.pumpAndSettle();
    expect(find.text('爱宠'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pumpAndSettle();
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);
    expect(initialService.generateCareReportCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: refreshService),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '生成总览'));
    await tester.pump();

    expect(find.text('正在分析'), findsOneWidget);
    expect(find.text('AI 正在生成新的专业分析报告…'), findsNothing);
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('overview-generating-pet-carousel')),
        findsOneWidget);
    final refreshAnalyzingButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('overview-generating-analyzing-button')),
    );
    expect(refreshAnalyzingButton.onPressed, isNull);

    refreshService.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);
    expect(initialService.forceRefreshValues, <bool>[false]);
    expect(refreshService.forceRefreshValues, <bool>[true]);
  });

  testWidgets('overview page restores generation setup after switching back',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.byTooltip('配置'), findsNothing);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);

    store.setActiveTab(AppTab.pets);
    await tester.pumpAndSettle();
    expect(find.text('爱宠'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsNothing);

    store.setActiveTab(AppTab.overview);
    await tester.pump();
    await tester.pump();
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.byTooltip('配置'), findsNothing);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
  });

  testWidgets('overview setup shows CTA on the first rendered frame',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
  });

  testWidgets(
      'overview page uses overview tab accent for header actions after report generation',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewPageHarness(
          store: store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(OverviewPage));
    final overviewAccent = tabAccentFor(context, AppTab.overview).label;
    final configButton =
        tester.widget<IconButton>(find.byType(IconButton).first);
    final generateButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '生成总览'));

    expect(
        find.ancestor(
          of: find.byIcon(Icons.settings_outlined),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing);
    expect(
        find.ancestor(
          of: find.byIcon(Icons.settings_outlined),
          matching: find.byType(IconButton),
        ),
        findsOneWidget);
    expect(configButton.style?.backgroundColor?.resolve({}), isNull);
    expect(configButton.style?.foregroundColor?.resolve({}), overviewAccent);
    expect(generateButton.style?.backgroundColor?.resolve({}), overviewAccent);
  });

  testWidgets(
      'overview page keeps error experience and can return to setup for retry',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _FakeAiInsightsService(
      isConfigured: true,
      generateCareReportError: const AiGenerationException('服务暂时不可用'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('overview-generation-error-experience')),
        findsOneWidget);
    expect(find.text('喵喵喵？！好像出错了...'), findsOneWidget);
    expect(find.text('服务暂时不可用'), findsOneWidget);
    final errorIcon = tester.widget<Icon>(
      find.byIcon(Icons.sentiment_dissatisfied_rounded),
    );
    expect(errorIcon.size, 72);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 560,
      ),
      findsNothing,
    );
    expect(find.text('关键变化'), findsNothing);
    expect(find.widgetWithText(FilledButton, '返回重试'), findsNothing);

    await tester.pump(const Duration(milliseconds: 360));
    expect(find.widgetWithText(FilledButton, '返回重试'), findsNothing);

    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '返回重试'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    store.setActiveTab(AppTab.checklist);
    await tester.pumpAndSettle();
    expect(find.text('清单'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-generation-error-experience')),
        findsOneWidget);
    expect(find.text('喵喵喵？！好像出错了...'), findsOneWidget);
    expect(find.text('服务暂时不可用'), findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
    expect(service.generateCareReportCalls, 1);
    expect(find.widgetWithText(FilledButton, '返回重试'), findsNothing);

    await tester.pump(const Duration(milliseconds: 360));
    expect(find.widgetWithText(FilledButton, '返回重试'), findsNothing);

    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '返回重试'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '返回重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-generation-error-experience')),
        findsNothing);
    expect(find.text('喵喵喵？！好像出错了...'), findsNothing);
    expect(find.text('服务暂时不可用'), findsNothing);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-floating-generate-button')),
        findsOneWidget);
    expect(service.generateCareReportCalls, 1);
  });

  testWidgets(
      'overview page keeps outgoing content moving downward across state transitions',
      (tester) async {
    double transitionOpacity(Finder finder) {
      final opacityWidgets = tester
          .widgetList<Opacity>(
            find.ancestor(of: finder, matching: find.byType(Opacity)),
          )
          .toList(growable: false);
      return opacityWidgets
          .map((widget) => widget.opacity)
          .firstWhere((opacity) => opacity < 1, orElse: () => 1);
    }

    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _DeferredAiInsightsService(
      isConfigured: true,
      careReportFuture: Completer<AiCareReport>(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    final setupPromptFinder =
        find.byKey(const ValueKey('overview-generation-prompt-row'));
    final setupPromptTop = tester.getTopLeft(setupPromptFinder).dy;
    final generatingTitleFinder =
        find.byKey(const ValueKey('overview-generating-title-label'));
    final errorTitleFinder = find.text('喵喵喵？！好像出错了...');

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(setupPromptFinder, findsOneWidget);
    expect(generatingTitleFinder, findsOneWidget);
    expect(transitionOpacity(generatingTitleFinder), 0);
    final setupOutgoingTop = tester.getTopLeft(setupPromptFinder).dy;
    expect(setupOutgoingTop, greaterThan(setupPromptTop));

    await tester.pump(const Duration(milliseconds: 580));
    expect(setupPromptFinder, findsNothing);
    expect(generatingTitleFinder, findsOneWidget);
    final generatingTitleTop = tester.getTopLeft(generatingTitleFinder).dy;

    service.completeCareReportError(const AiGenerationException('服务暂时不可用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(generatingTitleFinder, findsOneWidget);
    expect(errorTitleFinder, findsOneWidget);
    expect(transitionOpacity(errorTitleFinder), 0);
    final generatingOutgoingTop = tester.getTopLeft(generatingTitleFinder).dy;
    expect(generatingOutgoingTop, greaterThan(generatingTitleTop));

    await tester.pump(const Duration(milliseconds: 580));
    expect(generatingTitleFinder, findsNothing);
    expect(errorTitleFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.widgetWithText(FilledButton, '返回重试'), findsOneWidget);
    final errorTitleTop = tester.getTopLeft(errorTitleFinder).dy;

    await tester.tap(find.widgetWithText(FilledButton, '返回重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(errorTitleFinder, findsOneWidget);
    expect(setupPromptFinder, findsOneWidget);
    expect(transitionOpacity(setupPromptFinder), 0);
    final errorOutgoingTop = tester.getTopLeft(errorTitleFinder).dy;
    expect(errorOutgoingTop, greaterThan(errorTitleTop));

    await tester.pump(const Duration(milliseconds: 580));

    expect(errorTitleFinder, findsNothing);
    expect(setupPromptFinder, findsOneWidget);
  });

  testWidgets('overview page clears stale report when overview range changes',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pumpAndSettle();
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsOneWidget);

    store.setOverviewRange(OverviewRange.oneMonth);
    await tester.pumpAndSettle();

    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsNothing);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
  });

  testWidgets(
      'overview page shows generating experience while request is in flight before range changes',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _DeferredAiInsightsService(
      isConfigured: true,
      careReportFuture: Completer<AiCareReport>(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsOneWidget);

    store.setOverviewRange(OverviewRange.oneMonth);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsNothing);

    service.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();

    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsNothing);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
  });

  testWidgets(
      'overview page ignores stale in-flight response after source data changes',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    final service = _DeferredAiInsightsService(
      isConfigured: true,
      careReportFuture: Completer<AiCareReport>(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('overview-floating-generate-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('overview-generating-title-label')),
        findsOneWidget);

    await store.addTodo(
      title: '补充新的观察记录',
      petId: store.pets.first.id,
      dueAt: store.referenceNow.add(const Duration(hours: 2)),
      note: '测试新的总览上下文',
    );
    await tester.pumpAndSettle();
    expect(find.text('清单'), findsOneWidget);

    service.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();

    store.setActiveTab(AppTab.overview);
    await tester.pumpAndSettle();
    expect(find.text('Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。'), findsNothing);
    expect(find.text('你的AI关怀助理'), findsOneWidget);
    expect(find.text('右上角选好时间范围后，在此处选择你的爱宠即可生成总览'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-range-menu-button')),
        findsOneWidget);
    expect(find.text('关键变化'), findsNothing);
  });
}

AiCareReport _buildDetailedCareReport({
  String oneLineSummary = 'Luna 和 Milo 当前整体稳定，但耳道护理和皮肤复查还需要继续盯紧。',
}) {
  return AiCareReport(
    overallScore: 86,
    overallScoreLabel: '稳定',
    scoreConfidence: AiScoreConfidence.high,
    statusLabel: '基本稳定',
    oneLineSummary: oneLineSummary,
    recommendationRankings: const [
      AiRecommendationRanking(
        rank: 1,
        kind: 'action',
        petIds: ['pet-1'],
        petNames: ['Luna'],
        title: '优先补上 Luna 的耳道复查',
        summary: '耳道护理线索还没有新的闭环记录。',
        suggestedAction: '本周补一次 Luna 的耳道观察',
      ),
      AiRecommendationRanking(
        rank: 2,
        kind: 'risk',
        petIds: ['pet-2'],
        petNames: ['Milo'],
        title: '安排 Milo 的皮肤复查闭环',
        summary: '皮肤问题已有既往记录，但复查节奏还不够稳定。',
        suggestedAction: '确认 Milo 下一次复查时间并补上记录',
      ),
      AiRecommendationRanking(
        rank: 3,
        kind: 'gap',
        petIds: ['pet-1'],
        petNames: ['Luna'],
        title: '补齐 Luna 的过敏观察证据',
        summary: '过敏特性已知，但近期缺少连续证据。',
        suggestedAction: '连续补充 3 天饮食和症状记录',
      ),
      AiRecommendationRanking(
        rank: 4,
        kind: 'action',
        petIds: ['pet-2'],
        petNames: ['Milo'],
        title: '继续维持 Milo 的驱虫提醒节奏',
        summary: '当前节奏可控，但仍要避免遗漏关键节点。',
        suggestedAction: '核对下一次驱虫提醒是否已安排',
      ),
      AiRecommendationRanking(
        rank: 5,
        kind: 'gap',
        petIds: ['pet-1', 'pet-2'],
        petNames: ['Luna', 'Milo'],
        title: '补强两只宠物的连续记录密度',
        summary: '当前判断仍然依赖有限样本。',
        suggestedAction: '本周至少各补 1 条高价值观察记录',
      ),
    ],
    scoreBreakdown: const [
      AiScoreDimension(
        key: 'taskExecution',
        label: '执行完成度',
        score: 22,
        reason: '已完成事项占比高，只有少量延后。',
      ),
      AiScoreDimension(
        key: 'reminderFollowThrough',
        label: '提醒跟进度',
        score: 21,
        reason: '关键提醒已持续跟进。',
      ),
      AiScoreDimension(
        key: 'recordCompleteness',
        label: '记录完整度',
        score: 20,
        reason: '当前周期存在稳定记录。',
      ),
      AiScoreDimension(
        key: 'stabilityRisk',
        label: '稳定性与风险',
        score: 23,
        reason: '暂无集中风险信号。',
      ),
    ],
    scoreReasons: const ['本周期记录稳定，风险事项较少。'],
    executiveSummary:
        '最近 7 天内两只宠物整体照护节奏稳定，提醒和记录基本保持连续，但 Luna 的耳道问题和 Milo 的皮肤复查仍然需要继续闭环。当前最有价值的动作不是泛泛增加记录，而是围绕已知问题补上关键证据和明确后续安排。',
    overallAssessment: const [
      '年度体检准备事项已有推进，日常照护节奏保持稳定。',
      '记录与提醒协同较顺，当前主要问题集中在少量延期事项。',
    ],
    keyFindings: const [
      '完成驱虫提醒',
      '新增 2 条资料记录',
      '年度体检准备已有明确进展',
    ],
    trendAnalysis: const [
      '食欲记录更稳定',
      '体重趋势记录开始恢复',
    ],
    riskAssessment: const [
      '耳道护理间隔偏长，建议本周补一次观察。',
    ],
    priorityActions: const [
      '本周补一次耳道观察',
      '继续保持当前提醒节奏',
    ],
    dataQualityNotes: const [
      '最近 7 天记录数量足够，报告可信度较高。',
    ],
    perPetReports: const [
      AiPetCareReport(
        petId: 'pet-1',
        petName: 'Luna',
        score: 86,
        scoreLabel: '稳定',
        scoreConfidence: AiScoreConfidence.high,
        statusLabel: '基本稳定',
        whyThisScore: ['Luna 的提醒和记录都在跟进，但耳道问题还缺最后一步复查闭环。'],
        topPriority: ['先补上耳道复查，确认近期护理是否真正见效。'],
        missedItems: ['过敏相关的饮食和症状连续记录还不够。'],
        recentChanges: ['最近新增了耳道相关记录，说明关注点是明确的。'],
        followUpPlan: ['未来 7 天重点盯耳道状态和饮食反应，并补 1 条总结记录。'],
        summary: 'Luna 当前节奏稳定，但耳道护理还没有形成完整闭环。',
        careFocus: '重点继续观察耳道护理与过敏线索。',
        keyEvents: ['完成耳道护理记录', '补了最近一次观察'],
        trendAnalysis: ['耳道问题已被持续关注，但结论证据还不够扎实'],
        riskAssessment: ['耳道护理间隔偏长'],
        recommendedActions: ['本周补一次耳道观察'],
        followUpFocus: '下一个观察重点是耳道状态和饮食反应。',
      ),
      AiPetCareReport(
        petId: 'pet-2',
        petName: 'Milo',
        score: 82,
        scoreLabel: '基本稳定',
        scoreConfidence: AiScoreConfidence.high,
        statusLabel: '基本稳定',
        whyThisScore: ['Milo 的基础提醒基本稳定，但皮肤复查后的持续跟进还不够完整。'],
        topPriority: ['先把皮肤复查的后续安排补清楚，不要只停在已有记录。'],
        missedItems: ['缺少复查后的连续观察记录。'],
        recentChanges: ['已经有皮肤相关检查结果，说明问题路径是清楚的。'],
        followUpPlan: ['下一步围绕皮肤状态、洗护频率和复查节点继续记录。'],
        summary: 'Milo 当前基础节奏稳定，但皮肤问题还需要继续闭环。',
        careFocus: '重点跟进皮肤复查后的后续变化。',
        keyEvents: ['完成皮肤镜检查', '已有驱虫提醒安排'],
        trendAnalysis: ['皮肤问题已进入观察期，需要连续跟踪'],
        riskAssessment: ['复查闭环仍不够明确'],
        recommendedActions: ['确认下一次皮肤复查时间'],
        followUpFocus: '下一个观察重点是皮肤状态和洗护后的变化。',
      ),
    ],
  );
}

class _FakeAiInsightsService implements AiInsightsService {
  _FakeAiInsightsService({
    this.careReport,
    this.visitSummary,
    this.isConfigured = true,
    this.generateCareReportError,
  });

  final AiCareReport? careReport;
  final AiVisitSummary? visitSummary;
  final bool isConfigured;
  final AiGenerationException? generateCareReportError;
  int generateCareReportCalls = 0;
  final List<bool> forceRefreshValues = <bool>[];
  AiGenerationContext? lastCareContext;

  @override
  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) async {
    generateCareReportCalls += 1;
    forceRefreshValues.add(forceRefresh);
    lastCareContext = context;
    if (generateCareReportError != null) {
      throw generateCareReportError!;
    }
    if (careReport == null) {
      throw const AiGenerationException('missing care report');
    }
    return careReport!;
  }

  @override
  Future<AiVisitSummary> generateVisitSummary(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) async {
    if (visitSummary == null) {
      throw const AiGenerationException('missing visit summary');
    }
    return visitSummary!;
  }

  @override
  Future<bool> hasActiveProvider() async {
    return isConfigured;
  }
}

class _DeferredAiInsightsService implements AiInsightsService {
  _DeferredAiInsightsService({
    required this.careReportFuture,
    this.isConfigured = true,
  });

  Completer<AiCareReport> careReportFuture;
  final bool isConfigured;
  int generateCareReportCalls = 0;
  final List<bool> forceRefreshValues = <bool>[];

  void completeCareReport(AiCareReport report) {
    if (!careReportFuture.isCompleted) {
      careReportFuture.complete(report);
    }
  }

  void completeCareReportError(Object error) {
    if (!careReportFuture.isCompleted) {
      careReportFuture.completeError(error);
    }
  }

  @override
  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) {
    generateCareReportCalls += 1;
    forceRefreshValues.add(forceRefresh);
    return careReportFuture.future;
  }

  @override
  Future<AiVisitSummary> generateVisitSummary(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) async {
    throw const AiGenerationException('missing visit summary');
  }

  @override
  Future<bool> hasActiveProvider() async {
    return isConfigured;
  }
}

class _OverviewPageHarness extends StatefulWidget {
  const _OverviewPageHarness({
    required this.store,
    this.service,
    this.onOpenAiSettings,
  });

  final PetNoteStore store;
  final AiInsightsService? service;
  final FutureOr<void> Function()? onOpenAiSettings;

  @override
  State<_OverviewPageHarness> createState() => _OverviewPageHarnessState();
}

class _OverviewPageHarnessState extends State<_OverviewPageHarness> {
  late final OverviewBottomCtaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OverviewBottomCtaController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OverviewPage(
        store: widget.store,
        onAddFirstPet: () {},
        aiInsightsService: widget.service,
        onOpenAiSettings: widget.onOpenAiSettings,
        bottomCtaController: _controller,
      ),
      bottomNavigationBar: _OverviewTestBottomChrome(
        store: widget.store,
        controller: _controller,
        activeTabOverride: AppTab.overview,
      ),
    );
  }
}

class _OverviewTabHarness extends StatefulWidget {
  const _OverviewTabHarness({
    required this.store,
    required this.service,
  });

  final PetNoteStore store;
  final AiInsightsService service;

  @override
  State<_OverviewTabHarness> createState() => _OverviewTabHarnessState();
}

class _OverviewTabHarnessState extends State<_OverviewTabHarness> {
  late final OverviewBottomCtaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OverviewBottomCtaController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _OverviewTestBottomChrome(
        store: widget.store,
        controller: _controller,
      ),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          return switch (widget.store.activeTab) {
            AppTab.checklist => ChecklistPage(
                store: widget.store,
                activeSectionKey: 'today',
                highlightedChecklistItemKey: null,
                onSectionChanged: (_) {},
                onAddFirstPet: () {},
              ),
            AppTab.overview => OverviewPage(
                store: widget.store,
                onAddFirstPet: () {},
                aiInsightsService: widget.service,
                bottomCtaController: _controller,
              ),
            AppTab.pets => PetsPage(
                store: widget.store,
                onAddFirstPet: () {},
                onEditPet: (_) {},
              ),
            AppTab.me => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _OverviewTestBottomChrome extends StatelessWidget {
  const _OverviewTestBottomChrome({
    required this.store,
    required this.controller,
    this.activeTabOverride,
  });

  final PetNoteStore store;
  final OverviewBottomCtaController controller;
  final AppTab? activeTabOverride;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, controller]),
      builder: (context, _) {
        final state = controller.value;
        final visibleState = overviewBottomCtaFallbackState(
          store: store,
          activeTab: activeTabOverride ?? store.activeTab,
          syncedState: state,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (visibleState != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: overviewBottomCtaHorizontalMargin,
                ),
                child: OverviewBottomCtaBar(state: visibleState),
              ),
            if (visibleState != null)
              const SizedBox(height: overviewBottomCtaDockGap),
            const SizedBox(
              key: ValueKey('overview-test-dock'),
              height: 96,
            ),
          ],
        );
      },
    );
  }
}

class _MutableAvailabilityAiInsightsService implements AiInsightsService {
  _MutableAvailabilityAiInsightsService({required this.isConfigured});

  bool isConfigured;
  int hasActiveProviderCalls = 0;

  @override
  Future<bool> hasActiveProvider() async {
    hasActiveProviderCalls += 1;
    return isConfigured;
  }

  @override
  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AiVisitSummary> generateVisitSummary(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) {
    throw UnimplementedError();
  }
}

class _UnexpectedNetworkTransport implements AiHttpTransport {
  @override
  Future<AiHttpResponse> send(AiHttpRequest request) {
    fail(
        'overview should not hit the remote AI provider before user requests it');
  }
}
