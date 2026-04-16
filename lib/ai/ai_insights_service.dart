import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:petnote/ai/ai_care_scorecard_builder.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/logging/app_log_controller.dart';

abstract class AiInsightsService {
  Future<bool> hasActiveProvider();

  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  });
}

class NetworkAiInsightsService implements AiInsightsService {
  static const AiCareScorecardBuilder _scorecardBuilder =
      AiCareScorecardBuilder();
  static const Duration _careReportUserFacingTimeout = Duration(seconds: 10);

  NetworkAiInsightsService({
    required this.clientFactory,
    AiHttpTransport? transport,
    this.appLogController,
  }) : _transport = transport ?? HttpClientAiHttpTransport();

  final AiClientFactory clientFactory;
  final AiHttpTransport _transport;
  final AppLogController? appLogController;
  final Map<String, AiCareReport> _careReportCache = <String, AiCareReport>{};
  final Map<String, Future<AiCareReport>> _careReportInFlight =
      <String, Future<AiCareReport>>{};

  @override
  Future<bool> hasActiveProvider() async {
    try {
      final client = await clientFactory.createActiveClient();
      return client != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) async {
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '开始生成 AI 总览',
      message:
          '${context.rangeLabel} · pets=${context.pets.length}, todos=${context.todos.length}, reminders=${context.reminders.length}, records=${context.records.length}',
    );
    final client = await _requireClient();
    final cacheKey = '${client.configId}:care:${context.cacheKey}';
    if (!forceRefresh && _careReportCache.containsKey(cacheKey)) {
      return _careReportCache[cacheKey]!;
    }
    if (!forceRefresh && _careReportInFlight.containsKey(cacheKey)) {
      return _careReportInFlight[cacheKey]!;
    }

    final future = _generateCareReport(client, context);
    _careReportInFlight[cacheKey] = future;
    try {
      final result = await future;
      _careReportCache[cacheKey] = result;
      appLogController?.info(
        category: AppLogCategory.ai,
        title: 'AI 总览生成成功',
        message: result.summary,
      );
      return result;
    } catch (error) {
      appLogController?.error(
        category: AppLogCategory.ai,
        title: 'AI 总览生成失败',
        message: error.toString(),
      );
      rethrow;
    } finally {
      _careReportInFlight.remove(cacheKey);
    }
  }

  Future<AiProviderClient> _requireClient() async {
    try {
      final client = await clientFactory.createActiveClient();
      if (client == null) {
        throw const AiGenerationException('请先在“我的 > AI 功能”里配置可用的 AI 服务。');
      }
      return client;
    } on AiSecretStoreException {
      throw const AiGenerationException('当前 AI 配置不可用，请重新保存 API Key 后再试。');
    } catch (_) {
      throw const AiGenerationException('当前 AI 配置暂时不可读取，请稍后重试。');
    }
  }

  Future<AiCareReport> _generateCareReport(
    AiProviderClient client,
    AiGenerationContext context,
  ) async {
    final scorecard = _scorecardBuilder.build(context);
    final runtimeProfile = _resolveAiGenerationRuntimeProfile(client);
    final totalBudget = _careReportUserFacingTimeout;
    final promptPlans = _buildCareReportPromptPlans(
      context,
      scorecard: scorecard,
      runtimeProfile: runtimeProfile,
    );
    final firstPlan = promptPlans.first;
    final totalStopwatch = Stopwatch()..start();
    appLogController?.info(
      category: AppLogCategory.ai,
      title: 'AI 总览生成画像',
      message:
          'profile=${runtimeProfile.id}, startDetail=${firstPlan.detailLevel.name}, timeout=${totalBudget.inSeconds}s',
      details: [
        'range=${context.rangeLabel}',
        'rangeDays=${_rangeDays(context)}',
        'pets=${context.pets.length}',
        'todos=${context.todos.length}',
        'reminders=${context.reminders.length}',
        'records=${context.records.length}',
        'maxPromptChars=${runtimeProfile.maxPromptChars}',
      ].join('\n'),
    );
    if (firstPlan.isCondensedSummary) {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 总览预降载',
        message: '当前时间范围较长，已自动使用精简事实摘要降低长报告超时概率。',
        details: [
          'profile=${runtimeProfile.id}',
          'detailLevel=${firstPlan.detailLevel.name}',
          'promptChars=${firstPlan.prompt.length}',
          'maxPromptChars=${runtimeProfile.maxPromptChars}',
          'reason=${firstPlan.budgetReason}',
        ].join('\n'),
      );
    }
    final plan = promptPlans.first;
    final elapsedBeforeAttempt = totalStopwatch.elapsed;
    final remainingBudget = totalBudget - elapsedBeforeAttempt;
    if (remainingBudget <= Duration.zero) {
      return _buildLocalFastCareReport(
        context,
        scorecard: scorecard,
        detailLevel: plan.detailLevel,
        profileId: runtimeProfile.id,
        reason: 'budget_exhausted',
        elapsed: elapsedBeforeAttempt,
      );
    }
    final stopwatch = Stopwatch()..start();
    appLogController?.info(
      category: AppLogCategory.ai,
      title: 'AI 总览生成预算',
      message:
          'profile=${runtimeProfile.id}, detailLevel=${plan.detailLevel.name}, promptChars=${plan.prompt.length}',
      details: [
        'attempt=1/1',
        'range=${context.rangeLabel}',
        'pets=${context.pets.length}',
        'todos=${context.todos.length}',
        'reminders=${context.reminders.length}',
        'records=${context.records.length}',
        'remainingBudgetMs=${remainingBudget.inMilliseconds}',
        if (plan.budgetReason != null) 'reason=${plan.budgetReason}',
      ].join('\n'),
    );
    try {
      final jsonObject = await _generateStructuredJson(
        client: client,
        systemPrompt: _careReportSystemPrompt,
        userPrompt: plan.prompt,
        timeout: remainingBudget,
      );
      return _normalizeRemoteFastCareReport(
        AiCareReport.fromJson(
          jsonObject,
          scorecard: scorecard,
        ),
      );
    } on _AiRetryableGenerationException catch (error) {
      stopwatch.stop();
      return _buildLocalFastCareReport(
        context,
        scorecard: scorecard,
        detailLevel: plan.detailLevel,
        profileId: runtimeProfile.id,
        reason: error.phase,
        elapsed: totalStopwatch.elapsed,
      );
    } on AiGenerationException catch (error) {
      stopwatch.stop();
      appLogController?.error(
        category: AppLogCategory.ai,
        title: 'AI 总览结构化输出失败',
        message: error.message,
        details: [
          'profile=${runtimeProfile.id}',
          'failurePhase=structured_output',
          'detailLevel=${plan.detailLevel.name}',
          'promptChars=${plan.prompt.length}',
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        ].join('\n'),
      );
      rethrow;
    }
  }

  AiCareReport _buildLocalFastCareReport(
    AiGenerationContext context, {
    required AiCareScorecard scorecard,
    required _CarePromptDetailLevel detailLevel,
    required String profileId,
    required String reason,
    required Duration elapsed,
  }) {
    final summaryPackage = _buildCareReportSummaryPackage(
      context,
      detailLevel: detailLevel,
    );
    final overdueCount = summaryPackage.activeItems
        .where((item) => item['status'] == 'overdue')
        .length;
    final topicCount = (summaryPackage.globalStats['topicCount'] as int?) ?? 0;
    final eventCount = context.todos.length +
        context.reminders.length +
        context.records.length;
    final leadRisk = _firstString(scorecard.riskCandidates);
    final scoreReason = _firstString(scorecard.scoreReasons);
    final keyFindings = _localKeyFindings(summaryPackage);
    final trendAnalysis = _localTrendAnalysis(summaryPackage);
    final priorityActions = _localPriorityActions(summaryPackage);
    final riskAssessment =
        scorecard.riskCandidates.take(3).toList(growable: false);
    final perPetReports = scorecard.petScorecards
        .map(
          (petScorecard) => _buildLocalFastPetReport(
            petScorecard,
            summaryPackage: summaryPackage,
          ),
        )
        .toList(growable: false);
    appLogController?.warning(
      category: AppLogCategory.ai,
      title: 'AI 总览极速兜底',
      message: '远端总览未在10秒内稳定返回，已切换为本地短版总览。',
      details: [
        'profile=$profileId',
        'reason=$reason',
        'elapsedMs=${elapsed.inMilliseconds}',
        'detailLevel=${detailLevel.name}',
        'eventCount=$eventCount',
        'topicCount=$topicCount',
      ].join('\n'),
    );
    return AiCareReport(
      overallScore: scorecard.overallScore,
      overallScoreLabel: scorecard.overallScoreLabel,
      scoreConfidence: scorecard.scoreConfidence,
      scoreBreakdown: scorecard.scoreBreakdown,
      scoreReasons: scorecard.scoreReasons,
      executiveSummary:
          '已切换为10秒极速总览：${context.rangeLabel}共汇总$eventCount条照护事件，当前整体评分为${scorecard.overallScoreLabel}'
          '（${scorecard.overallScore}分，${aiScoreConfidenceLabel(scorecard.scoreConfidence)}）。'
          '${overdueCount > 0 ? '目前仍有$overdueCount条待处理事项，' : ''}'
          '${leadRisk.isNotEmpty ? '优先关注：$leadRisk' : '当前未见集中风险。'}',
      overallAssessment: <String>[
        if (scoreReason.isNotEmpty) scoreReason,
        '当前覆盖${context.pets.length}只宠物，折叠出$topicCount个照护主题。',
        if (overdueCount > 0) '当前仍有$overdueCount条逾期事项，建议优先闭环。',
      ].take(3).toList(growable: false),
      keyFindings: keyFindings,
      trendAnalysis: trendAnalysis,
      riskAssessment: riskAssessment.isEmpty
          ? const <String>['当前未见集中风险，建议保持规律记录。']
          : riskAssessment,
      priorityActions: priorityActions,
      dataQualityNotes: <String>[
        ...scorecard.dataQualityNotes.take(1),
        '当前结果由本地极速规则生成，以保证10秒内返回。',
      ],
      perPetReports: perPetReports,
    );
  }

  AiPetCareReport _buildLocalFastPetReport(
    AiPetCareScorecard scorecard, {
    required AiPortableSummaryPackage summaryPackage,
  }) {
    final petActiveItems = summaryPackage.activeItems
        .where((item) => item['petName'] == scorecard.petName)
        .toList(growable: false);
    final petEvidence = summaryPackage.keyEvidence
        .where((item) => item['petName'] == scorecard.petName)
        .toList(growable: false);
    final leadRisk = _firstString(scorecard.riskCandidates);
    final recentEvent = _firstString(scorecard.recentEventTitles);
    return AiPetCareReport(
      petId: scorecard.petId,
      petName: scorecard.petName,
      score: scorecard.overallScore,
      scoreLabel: scorecard.overallScoreLabel,
      scoreConfidence: scorecard.scoreConfidence,
      summary:
          '${scorecard.petName} 当前评分为${scorecard.overallScoreLabel}（${scorecard.overallScore}分）。'
          '${leadRisk.isNotEmpty ? '当前主要关注：$leadRisk' : '当前没有集中风险提示。'}',
      careFocus: leadRisk.isNotEmpty
          ? leadRisk
          : (recentEvent.isNotEmpty ? recentEvent : '继续保持规律记录'),
      keyEvents: _localPetKeyEvents(scorecard, petEvidence),
      trendAnalysis: scorecard.scoreReasons.take(2).toList(growable: false),
      riskAssessment: scorecard.riskCandidates.isEmpty
          ? const <String>['当前未见集中风险，建议继续观察。']
          : scorecard.riskCandidates.take(2).toList(growable: false),
      recommendedActions: _localPetActions(
        scorecard: scorecard,
        petActiveItems: petActiveItems,
      ),
      followUpFocus: leadRisk.isNotEmpty ? leadRisk : '继续补充高质量观察记录。',
    );
  }

  AiCareReport _normalizeRemoteFastCareReport(AiCareReport report) {
    return AiCareReport(
      overallScore: report.overallScore,
      overallScoreLabel: report.overallScoreLabel,
      scoreConfidence: report.scoreConfidence,
      scoreBreakdown: report.scoreBreakdown,
      scoreReasons: report.scoreReasons,
      executiveSummary: report.executiveSummary,
      overallAssessment:
          report.overallAssessment.take(3).toList(growable: false),
      keyFindings: report.keyFindings.take(4).toList(growable: false),
      trendAnalysis: report.trendAnalysis.take(3).toList(growable: false),
      riskAssessment: report.riskAssessment.take(3).toList(growable: false),
      priorityActions: report.priorityActions.take(3).toList(growable: false),
      dataQualityNotes: _prependNote(
        report.dataQualityNotes,
        '当前结果为 AI 短版总结，已按极速模式压缩。',
        maxItems: 3,
      ),
      perPetReports: report.perPetReports
          .map(_normalizeRemoteFastPetReport)
          .toList(growable: false),
    );
  }

  AiPetCareReport _normalizeRemoteFastPetReport(AiPetCareReport report) {
    return AiPetCareReport(
      petId: report.petId,
      petName: report.petName,
      score: report.score,
      scoreLabel: report.scoreLabel,
      scoreConfidence: report.scoreConfidence,
      summary: report.summary,
      careFocus: report.careFocus,
      keyEvents: report.keyEvents.take(3).toList(growable: false),
      trendAnalysis: report.trendAnalysis.take(2).toList(growable: false),
      riskAssessment: report.riskAssessment.take(2).toList(growable: false),
      recommendedActions:
          report.recommendedActions.take(3).toList(growable: false),
      followUpFocus: report.followUpFocus,
    );
  }

  List<String> _prependNote(
    List<String> notes,
    String note, {
    required int maxItems,
  }) {
    final normalized = <String>[note];
    for (final item in notes) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || trimmed == note) {
        continue;
      }
      normalized.add(trimmed);
      if (normalized.length >= maxItems) {
        break;
      }
    }
    return normalized.toList(growable: false);
  }

  Future<Map<String, dynamic>> _generateStructuredJson({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required Duration timeout,
  }) async {
    final response = await _sendPrompt(
      client: client,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      timeout: timeout,
    );
    try {
      final content = _extractTextContent(
        providerType: client.providerType,
        response: response,
      );
      appLogController?.info(
        category: AppLogCategory.ai,
        title: 'AI 返回原始内容摘要',
        message: '已收到 ${client.providerType.name} 的文本响应。',
        details: _previewText(content),
      );
      final jsonObject = _extractJsonObject(content);
      if (jsonObject == null) {
        throw AiGenerationException(
          _structuredJsonFailureMessage(client.providerType),
        );
      }
      return jsonObject;
    } on AiGenerationException catch (error) {
      appLogController?.error(
        category: AppLogCategory.ai,
        title: 'AI 总览结构化输出失败',
        message: error.message,
      );
      throw _AiRetryableGenerationException(
        error.message,
        phase: 'structured_output',
      );
    }
  }

  Future<AiHttpResponse> _sendPrompt({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required Duration timeout,
  }) async {
    try {
      return await switch (client.providerType) {
        AiProviderType.openai => _sendOpenAiPrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            useStructuredOutput: true,
            timeout: timeout,
          ),
        AiProviderType.openaiCompatible => _sendOpenAiCompatiblePrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            timeout: timeout,
          ),
        AiProviderType.anthropic => _sendAnthropicPrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            timeout: timeout,
          ),
      };
    } on TimeoutException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 请求超时',
        message: 'AI 请求超时，请稍后重试。',
      );
      throw const _AiRetryableGenerationException(
        'AI 请求超时，请稍后重试。',
        phase: 'provider_timeout',
      );
    } on FormatException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 服务地址格式错误',
        message: 'AI 服务地址格式不正确，请检查 Base URL。',
      );
      throw const AiGenerationException('AI 服务地址格式不正确，请检查 Base URL。');
    } on ArgumentError {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 服务地址参数错误',
        message: 'AI 服务地址格式不正确，请检查 Base URL。',
      );
      throw const AiGenerationException('AI 服务地址格式不正确，请检查 Base URL。');
    } on HandshakeException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 证书校验失败',
        message: 'AI 服务证书校验失败，请检查 HTTPS 证书或系统时间。',
      );
      throw const AiGenerationException('AI 服务证书校验失败，请检查 HTTPS 证书或系统时间。');
    } on SocketException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 服务连接失败',
        message: 'AI 服务连接失败，请检查网络或服务地址。',
      );
      throw const AiGenerationException('AI 服务连接失败，请检查网络或服务地址。');
    } on HttpException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 服务连接异常',
        message: 'AI 服务连接异常，请稍后重试。',
      );
      throw const AiGenerationException('AI 服务连接异常，请稍后重试。');
    }
  }

  Future<AiHttpResponse> _sendOpenAiPrompt({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required bool useStructuredOutput,
    required Duration timeout,
  }) async {
    final request = buildAiConversationRequest(
      providerType: client.providerType,
      baseUrl: client.baseUrl,
      model: client.model,
      apiKey: client.apiKey,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: useStructuredOutput,
      timeout: timeout,
    );
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '发送 AI 请求',
      message: '${request.method} ${request.uri}',
      details: 'timeout=${request.timeout?.inSeconds ?? 10}s',
    );
    final response = await _transport.send(request);
    appLogController?.info(
      category: AppLogCategory.ai,
      title: 'AI 请求返回',
      message: 'OpenAI 接口返回 ${response.statusCode}',
      details: _previewText(response.body),
    );
    _throwIfFailure(response);
    return response;
  }

  Future<AiHttpResponse> _sendOpenAiCompatiblePrompt({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required Duration timeout,
  }) async {
    var request = buildAiConversationRequest(
      providerType: client.providerType,
      baseUrl: client.baseUrl,
      model: client.model,
      apiKey: client.apiKey,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: true,
      timeout: timeout,
    );
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '发送 AI 请求',
      message: '${request.method} ${request.uri}',
      details: 'timeout=${request.timeout?.inSeconds ?? 10}s',
    );
    var response = await _transport.send(request);
    if (looksLikeStructuredOutputUnsupportedResponse(response)) {
      request = buildAiConversationRequest(
        providerType: client.providerType,
        baseUrl: client.baseUrl,
        model: client.model,
        apiKey: client.apiKey,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        useStructuredOutput: false,
        timeout: timeout,
      );
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 请求降级重试',
        message: '当前兼容服务不支持 response_format，改用普通 JSON 提示词重试。',
        details: '${request.method} ${request.uri}',
      );
      response = await _transport.send(request);
    }
    appLogController?.info(
      category: AppLogCategory.ai,
      title: 'AI 请求返回',
      message: '兼容 OpenAI 接口返回 ${response.statusCode}',
      details: _previewText(response.body),
    );
    _throwIfFailure(response);
    return response;
  }

  Future<AiHttpResponse> _sendAnthropicPrompt({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required Duration timeout,
  }) async {
    final request = buildAiConversationRequest(
      providerType: client.providerType,
      baseUrl: client.baseUrl,
      model: client.model,
      apiKey: client.apiKey,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: false,
      timeout: timeout,
    );
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '发送 AI 请求',
      message: '${request.method} ${request.uri}',
      details: 'timeout=${request.timeout?.inSeconds ?? 10}s',
    );
    final response = await _transport.send(request);
    appLogController?.info(
      category: AppLogCategory.ai,
      title: 'AI 请求返回',
      message: 'Anthropic 接口返回 ${response.statusCode}',
      details: _previewText(response.body),
    );
    _throwIfFailure(response);
    return response;
  }

  void _throwIfFailure(AiHttpResponse response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiGenerationException('AI 服务鉴权失败，请检查 API Key。');
    }
    if (response.statusCode == 404) {
      throw const AiGenerationException('AI 服务地址不可用，请检查 Base URL。');
    }
    if (response.statusCode == 429) {
      throw const _AiRetryableGenerationException(
        'AI 服务当前限流，请稍后再试。',
        phase: 'provider_rate_limit',
      );
    }
    if (response.statusCode == 408 ||
        response.statusCode == 425 ||
        response.statusCode == 500 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw _AiRetryableGenerationException(
        'AI 服务暂时不可用，服务返回 ${response.statusCode}。',
        phase: 'provider_overload',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiGenerationException('AI 服务暂时不可用，服务返回 ${response.statusCode}。');
    }
  }

  String _extractTextContent({
    required AiProviderType providerType,
    required AiHttpResponse response,
  }) {
    final decoded = tryDecodeAiJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AiGenerationException('AI 服务响应异常，未返回合法 JSON。');
    }
    final text = tryExtractAiResponseTextContent(
      providerType: providerType,
      decoded: decoded,
    );
    if (text == null || text.isEmpty) {
      throw const AiGenerationException('AI 服务响应异常，未返回文本内容。');
    }
    return text;
  }

  Map<String, dynamic>? _extractJsonObject(String text) {
    return extractAiJsonObject(text);
  }

  String _structuredJsonFailureMessage(AiProviderType providerType) {
    if (providerType == AiProviderType.openaiCompatible) {
      return '当前兼容服务返回的内容不是结构化 JSON，请检查该服务是否支持 JSON 模式或更换模型。';
    }
    return 'AI 返回内容无法解析为结构化 JSON，请稍后重试。';
  }

  String _previewText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'empty';
    }
    if (trimmed.length <= 800) {
      return trimmed;
    }
    return '${trimmed.substring(0, 800)}…';
  }
}

const String _careReportSystemPrompt = '''
你是宠物日常照护分析助手。你只能基于给定数据做总结、风险关注和下一步建议，不能编造事实，不能输出诊断结论，也不能假装自己是兽医。

始终使用简体中文，输出必须是一个 JSON object，不能出现 Markdown、解释文字或代码块之外的额外内容。

JSON schema:
{
  "executiveSummary": "80-140字的短版自然段，概括当前周期执行质量、变化趋势和主要关注点",
  "overallAssessment": ["1-3条总体判断"],
  "keyFindings": ["2-4条关键事实或发现"],
  "trendAnalysis": ["1-3条趋势分析"],
  "riskAssessment": ["0-3条风险说明，必须写清依据与建议"],
  "priorityActions": ["1-3条优先行动"],
  "dataQualityNotes": ["1-3条关于样本量、记录完整度、可信度的说明"],
  "perPetReports": [
    {
      "petId": "必须与输入里的 petId 一致",
      "petName": "必须与输入里的 petName 一致",
      "summary": "60-100字的短版自然段摘要",
      "careFocus": "一句本周期照护重点",
      "keyEvents": ["1-3条关键事件"],
      "trendAnalysis": ["1-2条趋势分析"],
      "riskAssessment": ["0-2条风险说明"],
      "recommendedActions": ["1-3条建议行动"],
      "followUpFocus": "一句后续观察重点"
    }
  ]
}

约束:
- 这是短版 AI 总览，不要写成长报告，不要铺陈背景
- 每一段结论都要引用输入中的事实、统计或时间范围，不准空泛
- perPetReports 必须覆盖输入中的每一只宠物，且 petId/petName 不得串位
- 分数、等级和可信度已由本地规则计算，你只能解释它们，不能重新生成数值分数
- 没有足够证据时，明确写“样本不足，仅供参考”或“建议继续观察”
- 不要给用药剂量、诊断名称或确定性医疗结论
- 所有字段都必须返回；没有内容时返回空数组或保守表述
- 默认短句和短数组；除 executiveSummary / summary 外，单字段优先控制在 1-3 条
''';

String _buildCareReportPrompt(
  AiGenerationContext context, {
  required AiCareScorecard scorecard,
  required _CarePromptDetailLevel detailLevel,
}) {
  final payload = _buildCareReportPayload(
    context,
    scorecard: scorecard,
    detailLevel: detailLevel,
  );
  return '''
请基于以下宠物照护上下文生成一份“短版 AI 总览”。

分析目标:
- 给出整体执行结论与趋势判断
- 解释本地评分为什么是这个结果
- 提炼关键事实、风险依据和优先行动
- 按宠物分别输出独立专项报告

已知规则:
- overallScore、scoreBreakdown、scoreConfidence 都是本地已算好的基线，不允许改写数值
- 你要做的是解释这些评分背后的原因，而不是重新打分
- 输入数据已经过本地压缩与筛选，优先依据统计、评分理由、风险候选和保留的关键事件下结论
- detailLevel 越低，说明这是为了提高生成稳定性而进行的降载版本，不要因为缺少细枝末节而编造内容
- 当前目标是 10 秒内返回结果，请使用简洁表达，避免长段铺陈
- 保持现有 JSON 结构，但所有数组都优先短版输出；在 compact/minimal/distilled 模式下，每个数组优先控制在 1-3 条
- 不要使用“正式分析报告”“综合研判如下”这类长报告措辞

压缩上下文:
${jsonEncode(payload)}
''';
}

List<_CareReportPromptPlan> _buildCareReportPromptPlans(
  AiGenerationContext context, {
  required AiCareScorecard scorecard,
  required _AiGenerationRuntimeProfile runtimeProfile,
}) {
  final candidateLevels = runtimeProfile.promptLevelsFor(context);
  final promptPlans = candidateLevels
      .map(
        (detailLevel) => _CareReportPromptPlan(
          label: detailLevel.label,
          detailLevel: detailLevel,
          prompt: _buildCareReportPrompt(
            context,
            scorecard: scorecard,
            detailLevel: detailLevel,
          ),
        ),
      )
      .toList(growable: true);

  if (promptPlans.isEmpty) {
    return const [];
  }

  while (promptPlans.length > 1 &&
      promptPlans.first.prompt.length > runtimeProfile.maxPromptChars) {
    promptPlans.removeAt(0);
  }

  if (promptPlans.first.detailLevel != candidateLevels.first) {
    final firstPlan = promptPlans.first;
    promptPlans[0] = firstPlan.copyWith(
      budgetReason: 'prompt_chars_exceeded:${runtimeProfile.maxPromptChars}',
    );
  } else if (promptPlans.first.isCondensedSummary) {
    final firstPlan = promptPlans.first;
    promptPlans[0] = firstPlan.copyWith(
      budgetReason: 'range_policy',
    );
  }

  return promptPlans.toList(growable: false);
}

Map<String, dynamic> _buildCareReportPayload(
  AiGenerationContext context, {
  required AiCareScorecard scorecard,
  required _CarePromptDetailLevel detailLevel,
}) {
  final config = detailLevel.config;
  final summaryPackage = _buildCareReportSummaryPackage(
    context,
    detailLevel: detailLevel,
  );
  return {
    'detailLevel': detailLevel.name,
    'scorecard': scorecard.toJson(),
    'summaryPackage': summaryPackage.toJson(),
    'globalHighlights': {
      'riskCandidates':
          scorecard.riskCandidates.take(config.maxRiskCandidates).toList(),
      'dataQualityNotes':
          scorecard.dataQualityNotes.take(config.maxDataQualityNotes).toList(),
    },
  };
}

AiPortableSummaryPackage _buildCareReportSummaryPackage(
  AiGenerationContext context, {
  required _CarePromptDetailLevel detailLevel,
}) {
  final config = detailLevel.config;
  return AiPortableSummaryBuilder(
    maxEvidencePerTopic: config.maxPerPetRecordSamples.clamp(1, 3),
    maxActiveItems:
        (config.maxGlobalTodoSamples + config.maxGlobalReminderSamples)
            .clamp(3, 12),
    maxRiskCandidates: config.maxRiskCandidates,
  ).build(
    title: context.title,
    context: context,
    generatedAt: context.rangeEnd,
  );
}

List<String> _localKeyFindings(AiPortableSummaryPackage summaryPackage) {
  final findings = <String>[];
  for (final item in summaryPackage.keyEvidence.take(3)) {
    final petName = item['petName'] as String? ?? '爱宠';
    final topicKey = item['topicKey'] as String? ?? 'other';
    final summary = item['summary'] as String? ?? '';
    findings.add('$petName 在${_summaryTopicLabel(topicKey)}方面：$summary');
  }
  if (findings.isEmpty) {
    findings.add('当前没有足够关键证据，建议继续补充结构化记录。');
  }
  return findings;
}

List<String> _localTrendAnalysis(AiPortableSummaryPackage summaryPackage) {
  final trends = <String>[];
  for (final item in summaryPackage.topicRollups.take(3)) {
    final topicKey = item['topicKey'] as String? ?? 'other';
    final count = item['count'] as int? ?? 0;
    trends.add('${_summaryTopicLabel(topicKey)}相关事件共$count条，近期仍在持续出现。');
  }
  if (trends.isEmpty) {
    trends.add('当前样本较少，趋势判断以保守结论为主。');
  }
  return trends;
}

List<String> _localPriorityActions(AiPortableSummaryPackage summaryPackage) {
  final actions = <String>[];
  for (final item in summaryPackage.activeItems.take(3)) {
    final title = item['title'] as String? ?? '待处理事项';
    actions.add('优先处理$title。');
  }
  if (actions.isEmpty) {
    actions.add('继续保持当前提醒和记录节奏。');
  }
  return actions;
}

List<String> _localPetKeyEvents(
  AiPetCareScorecard scorecard,
  List<Map<String, Object?>> petEvidence,
) {
  final events = <String>[];
  for (final item in petEvidence.take(2)) {
    final summary = item['summary'] as String? ?? '';
    if (summary.isNotEmpty) {
      events.add(summary);
    }
  }
  if (events.isEmpty) {
    events.addAll(scorecard.recentEventTitles.take(2));
  }
  if (events.isEmpty) {
    events.add('当前周期暂无可提炼的关键事件。');
  }
  return events;
}

List<String> _localPetActions({
  required AiPetCareScorecard scorecard,
  required List<Map<String, Object?>> petActiveItems,
}) {
  final actions = <String>[];
  for (final item in petActiveItems.take(2)) {
    final title = item['title'] as String? ?? '待处理事项';
    actions.add('优先处理$title。');
  }
  if (actions.isEmpty && scorecard.riskCandidates.isNotEmpty) {
    actions.add('优先跟进${scorecard.riskCandidates.first}');
  }
  if (actions.isEmpty) {
    actions.add('继续补充稳定、连续的照护记录。');
  }
  return actions;
}

String _firstString(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _summaryTopicLabel(String key) => switch (key) {
      'hydration' => '饮水',
      'diet' => '饮食',
      'deworming' => '驱虫',
      'litter' => '排泄',
      'grooming' => '洗护',
      'earCare' => '耳道',
      'medication' => '用药',
      'vaccine' => '疫苗',
      'review' => '复查',
      'weight' => '体重',
      'digestive' => '消化',
      'skin' => '皮肤',
      'purchase' => '采购',
      'cleaning' => '清洁',
      _ => '日常',
    };

class _CareReportPromptPlan {
  const _CareReportPromptPlan({
    required this.label,
    required this.detailLevel,
    required this.prompt,
    this.budgetReason,
  });

  final String label;
  final _CarePromptDetailLevel detailLevel;
  final String prompt;
  final String? budgetReason;

  bool get isCondensedSummary =>
      detailLevel == _CarePromptDetailLevel.distilled || budgetReason != null;

  _CareReportPromptPlan copyWith({
    String? budgetReason,
  }) {
    return _CareReportPromptPlan(
      label: label,
      detailLevel: detailLevel,
      prompt: prompt,
      budgetReason: budgetReason ?? this.budgetReason,
    );
  }
}

class _CarePromptPayloadConfig {
  const _CarePromptPayloadConfig({
    required this.maxRiskCandidates,
    required this.maxDataQualityNotes,
    required this.maxGlobalTodoSamples,
    required this.maxGlobalReminderSamples,
    required this.maxGlobalRecordSamples,
    required this.maxPerPetTodoSamples,
    required this.maxPerPetReminderSamples,
    required this.maxPerPetRecordSamples,
  });

  final int maxRiskCandidates;
  final int maxDataQualityNotes;
  final int maxGlobalTodoSamples;
  final int maxGlobalReminderSamples;
  final int maxGlobalRecordSamples;
  final int maxPerPetTodoSamples;
  final int maxPerPetReminderSamples;
  final int maxPerPetRecordSamples;
}

enum _CarePromptDetailLevel {
  standard(
    '标准',
    _CarePromptPayloadConfig(
      maxRiskCandidates: 8,
      maxDataQualityNotes: 4,
      maxGlobalTodoSamples: 12,
      maxGlobalReminderSamples: 12,
      maxGlobalRecordSamples: 16,
      maxPerPetTodoSamples: 8,
      maxPerPetReminderSamples: 8,
      maxPerPetRecordSamples: 10,
    ),
  ),
  compact(
    '压缩',
    _CarePromptPayloadConfig(
      maxRiskCandidates: 6,
      maxDataQualityNotes: 3,
      maxGlobalTodoSamples: 7,
      maxGlobalReminderSamples: 7,
      maxGlobalRecordSamples: 10,
      maxPerPetTodoSamples: 5,
      maxPerPetReminderSamples: 5,
      maxPerPetRecordSamples: 6,
    ),
  ),
  minimal(
    '极简',
    _CarePromptPayloadConfig(
      maxRiskCandidates: 4,
      maxDataQualityNotes: 2,
      maxGlobalTodoSamples: 4,
      maxGlobalReminderSamples: 4,
      maxGlobalRecordSamples: 6,
      maxPerPetTodoSamples: 3,
      maxPerPetReminderSamples: 3,
      maxPerPetRecordSamples: 4,
    ),
  ),
  distilled(
    '精简事实摘要',
    _CarePromptPayloadConfig(
      maxRiskCandidates: 3,
      maxDataQualityNotes: 1,
      maxGlobalTodoSamples: 2,
      maxGlobalReminderSamples: 2,
      maxGlobalRecordSamples: 3,
      maxPerPetTodoSamples: 2,
      maxPerPetReminderSamples: 2,
      maxPerPetRecordSamples: 2,
    ),
  );

  const _CarePromptDetailLevel(this.label, this.config);

  final String label;
  final _CarePromptPayloadConfig config;
}

class _AiRetryableGenerationException extends AiGenerationException {
  const _AiRetryableGenerationException(
    super.message, {
    required this.phase,
  });

  final String phase;
}

class _AiGenerationRuntimeProfile {
  const _AiGenerationRuntimeProfile({
    required this.id,
    required this.requestTimeout,
    required this.maxPromptChars,
  });

  final String id;
  final Duration requestTimeout;
  final int maxPromptChars;

  List<_CarePromptDetailLevel> promptLevelsFor(AiGenerationContext context) {
    final startLevel = _startDetailLevel(context);
    final startIndex = _CarePromptDetailLevel.values.indexOf(startLevel);
    return _CarePromptDetailLevel.values
        .skip(startIndex)
        .toList(growable: false);
  }

  _CarePromptDetailLevel _startDetailLevel(AiGenerationContext context) {
    final rangeDays = _rangeDays(context);
    switch (id) {
      case 'openai-compatible-bigmodel':
        if (rangeDays <= 30) {
          return _CarePromptDetailLevel.standard;
        }
        return _CarePromptDetailLevel.distilled;
      case 'openai-compatible-generic':
      case 'openai-compatible-cloudflare-workers-ai':
        if (rangeDays <= 30) {
          return _CarePromptDetailLevel.standard;
        }
        if (rangeDays <= 90) {
          return _CarePromptDetailLevel.compact;
        }
        return _CarePromptDetailLevel.minimal;
      case 'anthropic':
      case 'openai':
        if (rangeDays <= 30) {
          return _CarePromptDetailLevel.standard;
        }
        if (rangeDays <= 180) {
          return _CarePromptDetailLevel.compact;
        }
        return _CarePromptDetailLevel.minimal;
    }
    return _CarePromptDetailLevel.compact;
  }
}

_AiGenerationRuntimeProfile _resolveAiGenerationRuntimeProfile(
  AiProviderClient client,
) {
  final connectionProfile = resolveAiProviderRuntimeProfile(
    providerType: client.providerType,
    baseUrl: client.baseUrl,
  );
  return switch (connectionProfile.id) {
    'openai-compatible-bigmodel' => const _AiGenerationRuntimeProfile(
        id: 'openai-compatible-bigmodel',
        requestTimeout: Duration(seconds: 38),
        maxPromptChars: 7200,
      ),
    'openai-compatible-generic' => const _AiGenerationRuntimeProfile(
        id: 'openai-compatible-generic',
        requestTimeout: Duration(seconds: 45),
        maxPromptChars: 10000,
      ),
    'openai-compatible-cloudflare-workers-ai' =>
      const _AiGenerationRuntimeProfile(
        id: 'openai-compatible-cloudflare-workers-ai',
        requestTimeout: Duration(seconds: 45),
        maxPromptChars: 9600,
      ),
    'anthropic' => const _AiGenerationRuntimeProfile(
        id: 'anthropic',
        requestTimeout: Duration(seconds: 45),
        maxPromptChars: 13000,
      ),
    _ => const _AiGenerationRuntimeProfile(
        id: 'openai',
        requestTimeout: Duration(seconds: 45),
        maxPromptChars: 12500,
      ),
  };
}

int _rangeDays(AiGenerationContext context) {
  final inclusiveRange = context.rangeEnd.difference(context.rangeStart).inDays;
  return inclusiveRange <= 0 ? 1 : inclusiveRange;
}
