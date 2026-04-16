import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'overview page generates AI care report only after tapping button',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
            aiInsightsService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.generateCareReportCalls, 0);
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    expect(find.text('综合评分'), findsOneWidget);
    expect(find.text('86 分 · 稳定'), findsOneWidget);
    expect(find.text('可信度较高'), findsNothing);
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);
    expect(find.text('当前正在展示 AI 短版总结与综合评分，仅供照护参考，不替代兽医建议。'), findsOneWidget);
    expect(find.text('执行总评'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);
    await tester.scrollUntilVisible(
      find.text('执行完成度 · 22/25'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('执行完成度 · 22/25'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mochi 专项报告'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mochi 专项报告'), findsOneWidget);
    expect(find.text('86 分 · 稳定'), findsWidgets);
    expect(find.text('86 分 · 稳定 · 可信度较高'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('下一个观察重点是耳道状态和体重变化。'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('下一个观察重点是耳道状态和体重变化。'), findsOneWidget);
  });

  testWidgets('overview page falls back to local summary without AI service',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关键变化'), findsOneWidget);
    expect(find.text('AI 总览'), findsNothing);
  });

  testWidgets(
      'overview page shows local-rule short summary status text for fallback reports',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(
        executiveSummary: '已切换为10秒极速总览。',
        dataQualityNotes: const [
          '当前结果由本地极速规则生成，以保证10秒内返回。',
        ],
      ),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
            aiInsightsService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    expect(find.text('当前正在展示本地规则短版总结与综合评分，仅供照护参考，不替代兽医建议。'), findsOneWidget);
  });

  testWidgets(
      'overview page does not show an error card before the user asks to generate',
      (tester) async {
    final store = PetNoteStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
            aiInsightsService: _FakeAiInsightsService(
              isConfigured: true,
              generateCareReportError: const AiGenerationException('服务暂时不可用'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关键变化'), findsOneWidget);
    expect(find.text('服务暂时不可用'), findsNothing);
    expect(find.text('AI 总览'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    expect(find.text('服务暂时不可用'), findsOneWidget);
  });

  testWidgets(
      'overview page keeps local summary when saved AI config is malformed',
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
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
            aiInsightsService: NetworkAiInsightsService(
              clientFactory: AiClientFactory(
                settingsController: settingsController,
                secretStore: secretStore,
              ),
              transport: _UnexpectedNetworkTransport(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关键变化'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '生成 AI 总览'), findsNothing);
    expect(find.textContaining('Base URL'), findsNothing);
  });

  testWidgets('pets page generates and displays visit summary', (tester) async {
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
            aiInsightsService: _FakeAiInsightsService(
              visitSummary: AiVisitSummary(
                visitReason: '近两周耳道护理后仍偶尔抓耳，建议复查。',
                timeline: const ['04-01 抓耳增加', '04-03 做耳道清洁'],
                medicationsAndTreatments: const ['耳道清洁 1 次'],
                testsAndResults: const ['暂无新增检查结果'],
                questionsToAskVet: const ['是否需要继续滴耳液'],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final generateButton = find.widgetWithText(FilledButton, '生成看诊摘要');
    await tester.tap(generateButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('AI 看诊摘要'), findsOneWidget);
    expect(find.text('近两周耳道护理后仍偶尔抓耳，建议复查。'), findsOneWidget);
    expect(find.text('是否需要继续滴耳液'), findsOneWidget);
  });

  testWidgets(
      'overview AI generation uses the store reference time window instead of wall clock now',
      (tester) async {
    final store = PetNoteStore.seeded();
    final service = _FakeAiInsightsService(
      careReport: _buildDetailedCareReport(
        executiveSummary: '稳定。',
      ),
      isConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: OverviewPage(
            store: store,
            onAddFirstPet: () {},
            aiInsightsService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    expect(service.lastCareContext, isNotNull);
    expect(service.lastCareContext!.todos, isNotEmpty);
    expect(service.lastCareContext!.reminders, isNotEmpty);
    expect(service.lastCareContext!.records, isNotEmpty);
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pump();

    expect(find.text('正在根据当前时间范围生成结构化照护总结…'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);
    expect(service.forceRefreshValues, <bool>[false]);

    store.setActiveTab(AppTab.checklist);
    await tester.pumpAndSettle();
    expect(find.text('清单'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pump();
    expect(find.text('正在根据当前时间范围生成结构化照护总结…'), findsOneWidget);

    service.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();

    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);
  });

  testWidgets('overview page keeps generated report after switching tabs',
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);

    store.setActiveTab(AppTab.pets);
    await tester.pumpAndSettle();
    expect(find.text('爱宠'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, '重新生成 AI 总览'));
    await tester.pumpAndSettle();
    expect(service.forceRefreshValues, <bool>[false, true]);
  });

  testWidgets('overview page can open ai history after report generation',
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('overview_ai_history_button')));
    await tester.pumpAndSettle();

    expect(find.text('AI 总览历史'), findsOneWidget);
    expect(find.text('最近 7 天 AI 照护总结'), findsOneWidget);
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);
  });

  testWidgets(
      'overview page keeps error state and local summary after switching tabs',
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();
    expect(find.text('服务暂时不可用'), findsOneWidget);
    expect(find.text('关键变化'), findsOneWidget);

    store.setActiveTab(AppTab.checklist);
    await tester.pumpAndSettle();
    expect(find.text('清单'), findsOneWidget);

    store.setActiveTab(AppTab.overview);
    await tester.pumpAndSettle();
    expect(find.text('服务暂时不可用'), findsOneWidget);
    expect(find.text('关键变化'), findsOneWidget);
    expect(service.generateCareReportCalls, 1);
  });

  testWidgets(
      'overview page uses condensed-summary loading copy for long ranges',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    store.setOverviewRange(OverviewRange.sixMonths);
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pump();

    expect(
      find.text('当前时间范围较长，正在基于精简事实摘要生成结构化照护总结…'),
      findsOneWidget,
    );
  });

  testWidgets(
      'overview page distinguishes generation stability issues from config errors',
      (tester) async {
    final store = PetNoteStore.seeded();
    store.setActiveTab(AppTab.overview);
    store.setOverviewRange(OverviewRange.sixMonths);
    final service = _FakeAiInsightsService(
      isConfigured: true,
      generateCareReportError: const AiGenerationException(
        '当前 AI 服务基础连接可用，但在生成最近 6 个月 AI 总览时，即使已自动改用精简事实摘要仍然超时或过载。建议先切换到较短时间范围，或更换更稳定的模型/供应商后再试。',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: _OverviewTabHarness(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();

    expect(
      find.text('AI 基础连接可用，但当前时间范围的长报告生成不稳定，已回退到本地规则总结。'),
      findsOneWidget,
    );
    expect(
      find.textContaining('即使已自动改用精简事实摘要仍然超时或过载'),
      findsOneWidget,
    );
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsOneWidget);

    store.setOverviewRange(OverviewRange.oneMonth);
    await tester.pumpAndSettle();

    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsNothing);
    expect(find.text('关键变化'), findsOneWidget);
  });

  testWidgets(
      'overview page ignores stale in-flight response after overview range changes',
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pump();
    expect(find.text('正在根据当前时间范围生成结构化照护总结…'), findsOneWidget);

    store.setOverviewRange(OverviewRange.oneMonth);
    await tester.pumpAndSettle();
    expect(find.text('正在根据当前时间范围生成结构化照护总结…'), findsNothing);

    service.completeCareReport(_buildDetailedCareReport());
    await tester.pumpAndSettle();

    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsNothing);
    expect(find.text('关键变化'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(OutlinedButton, '生成 AI 总览'));
    await tester.pump();
    expect(find.text('正在根据当前时间范围生成结构化照护总结…'), findsOneWidget);

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
    expect(find.text('最近 7 天整体稳定，记录节奏比上周更完整。'), findsNothing);
    expect(find.text('关键变化'), findsOneWidget);
  });
}

AiCareReport _buildDetailedCareReport({
  String executiveSummary = '最近 7 天整体稳定，记录节奏比上周更完整。',
  List<String> dataQualityNotes = const [
    '当前结果为 AI 短版总结，已按极速模式压缩。',
  ],
}) {
  return AiCareReport(
    overallScore: 86,
    overallScoreLabel: '稳定',
    scoreConfidence: AiScoreConfidence.high,
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
    executiveSummary: executiveSummary,
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
    dataQualityNotes: dataQualityNotes,
    perPetReports: const [
      AiPetCareReport(
        petId: 'pet-1',
        petName: 'Mochi',
        score: 86,
        scoreLabel: '稳定',
        scoreConfidence: AiScoreConfidence.high,
        summary: 'Mochi 当前节奏稳定，记录和提醒都在可控范围内。',
        careFocus: '重点继续观察耳道护理与体重趋势。',
        keyEvents: ['完成驱虫提醒', '新增体重记录'],
        trendAnalysis: ['食欲记录更规律'],
        riskAssessment: ['耳道护理间隔偏长'],
        recommendedActions: ['本周补一次耳道观察'],
        followUpFocus: '下一个观察重点是耳道状态和体重变化。',
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

class _OverviewTabHarness extends StatelessWidget {
  const _OverviewTabHarness({
    required this.store,
    required this.service,
  });

  final PetNoteStore store;
  final AiInsightsService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return switch (store.activeTab) {
            AppTab.checklist => ChecklistPage(
                store: store,
                activeSectionKey: 'today',
                highlightedChecklistItemKey: null,
                onSectionChanged: (_) {},
                onAddFirstPet: () {},
              ),
            AppTab.overview => OverviewPage(
                store: store,
                onAddFirstPet: () {},
                aiInsightsService: service,
              ),
            AppTab.pets => PetsPage(
                store: store,
                onAddFirstPet: () {},
                onEditPet: (_) {},
                aiInsightsService: service,
              ),
            AppTab.me => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _UnexpectedNetworkTransport implements AiHttpTransport {
  @override
  Future<AiHttpResponse> send(AiHttpRequest request) {
    fail(
        'overview should not hit the remote AI provider before user requests it');
  }
}
