import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:petnote/ai/ai_care_scorecard_builder.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_url_utils.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/state/petnote_store.dart';

abstract class AiInsightsService {
  Future<bool> hasActiveProvider();

  Future<AiCareReport> generateCareReport(
    AiGenerationContext context, {
    bool forceRefresh = false,
  });

  Future<AiVisitSummary> generateVisitSummary(
    AiGenerationContext context, {
    bool forceRefresh = false,
  });
}

class NetworkAiInsightsService implements AiInsightsService {
  static const Duration _generationRequestTimeout = Duration(seconds: 45);
  static const AiCareScorecardBuilder _scorecardBuilder =
      AiCareScorecardBuilder();

  NetworkAiInsightsService({
    required this.clientFactory,
    AiHttpTransport? transport,
    this.appLogController,
  }) : _transport = transport ?? HttpClientAiHttpTransport();

  final AiClientFactory clientFactory;
  final AiHttpTransport _transport;
  final AppLogController? appLogController;
  final Map<String, AiCareReport> _careReportCache = <String, AiCareReport>{};
  final Map<String, AiVisitSummary> _visitSummaryCache =
      <String, AiVisitSummary>{};
  final Map<String, Future<AiCareReport>> _careReportInFlight =
      <String, Future<AiCareReport>>{};
  final Map<String, Future<AiVisitSummary>> _visitSummaryInFlight =
      <String, Future<AiVisitSummary>>{};

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

  @override
  Future<AiVisitSummary> generateVisitSummary(
    AiGenerationContext context, {
    bool forceRefresh = false,
  }) async {
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '开始生成看诊摘要',
      message:
          '${context.rangeLabel} · pets=${context.pets.length}, todos=${context.todos.length}, reminders=${context.reminders.length}, records=${context.records.length}',
    );
    if (_hasNoVisitSummarySourceData(context)) {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: '看诊摘要跳过远端请求',
        message: '当前区间没有足够数据，直接返回保守摘要。',
      );
      return _buildEmptyVisitSummary(context);
    }

    final client = await _requireClient();
    final cacheKey = '${client.configId}:visit:${context.cacheKey}';
    if (!forceRefresh && _visitSummaryCache.containsKey(cacheKey)) {
      return _visitSummaryCache[cacheKey]!;
    }
    if (!forceRefresh && _visitSummaryInFlight.containsKey(cacheKey)) {
      return _visitSummaryInFlight[cacheKey]!;
    }

    final future = _generateVisitSummary(client, context);
    _visitSummaryInFlight[cacheKey] = future;
    try {
      final result = await future;
      _visitSummaryCache[cacheKey] = result;
      appLogController?.info(
        category: AppLogCategory.ai,
        title: '看诊摘要生成成功',
        message: result.visitReason,
      );
      return result;
    } catch (error) {
      appLogController?.error(
        category: AppLogCategory.ai,
        title: '看诊摘要生成失败',
        message: error.toString(),
      );
      rethrow;
    } finally {
      _visitSummaryInFlight.remove(cacheKey);
    }
  }

  bool _hasNoVisitSummarySourceData(AiGenerationContext context) {
    return context.todos.isEmpty &&
        context.reminders.isEmpty &&
        context.records.isEmpty;
  }

  AiVisitSummary _buildEmptyVisitSummary(AiGenerationContext context) {
    return AiVisitSummary(
      visitReason: '${context.rangeLabel}内暂无足够记录可整理为看诊摘要，建议先补充症状、提醒或就诊经过后再生成。',
      timeline: const ['当前区间暂无可用时间线记录。'],
      medicationsAndTreatments: const ['暂无可归纳的用药或护理处置。'],
      testsAndResults: const ['暂无检查项目或结果记录。'],
      questionsToAskVet: const ['如需就诊，建议带上最新观察和近期变化描述与兽医确认。'],
    );
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
    final promptPlans = _buildCareReportPromptPlans(
      context,
      scorecard: scorecard,
    );
    for (var index = 0; index < promptPlans.length; index += 1) {
      final plan = promptPlans[index];
      try {
        final jsonObject = await _generateStructuredJson(
          client: client,
          systemPrompt: _careReportSystemPrompt,
          userPrompt: plan.prompt,
        );
        return AiCareReport.fromJson(
          jsonObject,
          scorecard: scorecard,
        );
      } on _AiRetryableGenerationException catch (error) {
        if (index == promptPlans.length - 1) {
          throw const AiGenerationException(
            '当前 AI 服务基础连接可用，但在生成较长专业报告时仍然超时或过载。请先切换到较短时间范围，或更换更稳定的模型/供应商后再试。',
          );
        }
        final nextPlan = promptPlans[index + 1];
        appLogController?.warning(
          category: AppLogCategory.ai,
          title: 'AI 总览降载重试',
          message:
              '当前服务在${plan.label}上下文下未稳定返回，改用${nextPlan.label}上下文重试。',
          details: error.message,
        );
      }
    }
    throw const AiGenerationException('AI 总览生成失败，请稍后重试。');
  }

  Future<AiVisitSummary> _generateVisitSummary(
    AiProviderClient client,
    AiGenerationContext context,
  ) async {
    final jsonObject = await _generateStructuredJson(
      client: client,
      systemPrompt: _visitSummarySystemPrompt,
      userPrompt: _buildVisitSummaryPrompt(context),
    );
    return AiVisitSummary.fromJson(jsonObject);
  }

  Future<Map<String, dynamic>> _generateStructuredJson({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final response = await _sendPrompt(
      client: client,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );
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
  }

  Future<AiHttpResponse> _sendPrompt({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    try {
      return await switch (client.providerType) {
        AiProviderType.openai => _sendOpenAiPrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            useStructuredOutput: true,
          ),
        AiProviderType.openaiCompatible => _sendOpenAiCompatiblePrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
          ),
        AiProviderType.anthropic => _sendAnthropicPrompt(
            client: client,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
          ),
      };
    } on TimeoutException {
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 请求超时',
        message: 'AI 请求超时，请稍后重试。',
      );
      throw const _AiRetryableGenerationException('AI 请求超时，请稍后重试。');
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
  }) async {
    final request = _buildOpenAiRequest(
      client: client,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: useStructuredOutput,
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
  }) async {
    var request = _buildOpenAiRequest(
      client: client,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: true,
    );
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '发送 AI 请求',
      message: '${request.method} ${request.uri}',
      details: 'timeout=${request.timeout?.inSeconds ?? 10}s',
    );
    var response = await _transport.send(request);
    if (_looksLikeStructuredOutputUnsupportedResponse(response)) {
      request = _buildOpenAiRequest(
        client: client,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        useStructuredOutput: false,
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
  }) async {
    final baseUrl = normalizeAiBaseUrl(client.baseUrl);
    final request = AiHttpRequest(
      method: 'POST',
      uri: Uri.parse('$baseUrl/messages'),
      headers: {
        'x-api-key': client.apiKey,
        'anthropic-version': '2023-06-01',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': client.model,
        'max_tokens': 1200,
        'system': systemPrompt,
        'messages': [
          {
            'role': 'user',
            'content': userPrompt,
          },
        ],
      }),
      timeout: _generationRequestTimeout,
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

  AiHttpRequest _buildOpenAiRequest({
    required AiProviderClient client,
    required String systemPrompt,
    required String userPrompt,
    required bool useStructuredOutput,
  }) {
    final baseUrl = normalizeAiBaseUrl(client.baseUrl);
    final body = <String, dynamic>{
      'model': client.model,
      'messages': [
        {
          'role': 'system',
          'content': systemPrompt,
        },
        {
          'role': 'user',
          'content': userPrompt,
        },
      ],
      'temperature': 0.2,
    };
    if (useStructuredOutput) {
      body['response_format'] = const {
        'type': 'json_object',
      };
    }
    return AiHttpRequest(
      method: 'POST',
      uri: Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${client.apiKey}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
      timeout: _generationRequestTimeout,
    );
  }

  void _throwIfFailure(AiHttpResponse response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiGenerationException('AI 服务鉴权失败，请检查 API Key。');
    }
    if (response.statusCode == 404) {
      throw const AiGenerationException('AI 服务地址不可用，请检查 Base URL。');
    }
    if (response.statusCode == 429) {
      throw const _AiRetryableGenerationException('AI 服务当前限流，请稍后再试。');
    }
    if (response.statusCode == 408 ||
        response.statusCode == 425 ||
        response.statusCode == 500 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw _AiRetryableGenerationException(
        'AI 服务暂时不可用，服务返回 ${response.statusCode}。',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiGenerationException('AI 服务暂时不可用，服务返回 ${response.statusCode}。');
    }
  }

  bool _looksLikeStructuredOutputUnsupportedResponse(AiHttpResponse response) {
    if (response.statusCode < 400 || response.statusCode >= 500) {
      return false;
    }
    final message = _extractErrorMessage(response.body)?.toLowerCase() ??
        response.body.toLowerCase();
    return message.contains('response_format') ||
        message.contains('json_schema') ||
        message.contains('json_object') ||
        message.contains('structured output');
  }

  String? _extractErrorMessage(String rawBody) {
    final decoded = _tryDecodeJson(rawBody);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    final errors = decoded['errors'];
    if (errors is List) {
      for (final item in errors) {
        if (item is Map<String, dynamic>) {
          final message = item['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }
    }
    return null;
  }

  String _extractTextContent({
    required AiProviderType providerType,
    required AiHttpResponse response,
  }) {
    final decoded = _tryDecodeJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AiGenerationException('AI 服务响应异常，未返回合法 JSON。');
    }

    return switch (providerType) {
      AiProviderType.openai ||
      AiProviderType.openaiCompatible =>
        _extractOpenAiContent(decoded),
      AiProviderType.anthropic => _extractAnthropicContent(decoded),
    };
  }

  String _extractOpenAiContent(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiGenerationException('AI 服务响应异常，未返回聊天结果。');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw const AiGenerationException('AI 服务响应异常，未返回聊天结果。');
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw const AiGenerationException('AI 服务响应异常，未返回聊天结果。');
    }
    final buffer = StringBuffer();
    _appendTextContent(message['content'], buffer);
    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
    throw const AiGenerationException('AI 服务响应异常，未返回文本内容。');
  }

  String _extractAnthropicContent(Map<String, dynamic> decoded) {
    final content = decoded['content'];
    if (content is! List || content.isEmpty) {
      throw const AiGenerationException('AI 服务响应异常，未返回消息内容。');
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map && item['type'] == 'text' && item['text'] is String) {
        buffer.writeln(item['text'] as String);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw const AiGenerationException('AI 服务响应异常，未返回文本内容。');
    }
    return text;
  }

  Map<String, dynamic>? _extractJsonObject(String text) {
    final direct = _tryDecodeJson(text);
    if (direct is Map<String, dynamic>) {
      return direct;
    }

    final fencedMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fencedMatch != null) {
      final fenced = _tryDecodeJson(fencedMatch.group(1)!.trim());
      if (fenced is Map<String, dynamic>) {
        return fenced;
      }
    }

    final startIndex = text.indexOf('{');
    if (startIndex == -1) {
      return null;
    }

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = startIndex; index < text.length; index += 1) {
      final char = text[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          final candidate = text.substring(startIndex, index + 1);
          final decoded = _tryDecodeJson(candidate);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          return null;
        }
      }
    }
    return null;
  }

  Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  void _appendTextContent(Object? value, StringBuffer buffer) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln(trimmed);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _appendTextContent(item, buffer);
      }
      return;
    }
    if (value is Map) {
      if (value['text'] is String) {
        _appendTextContent(value['text'], buffer);
      }
      if (value['value'] is String) {
        _appendTextContent(value['value'], buffer);
      }
      if (value['content'] != null) {
        _appendTextContent(value['content'], buffer);
      }
      if (value['text'] == null &&
          value['value'] == null &&
          value['content'] == null) {
        for (final nested in value.values) {
          _appendTextContent(nested, buffer);
        }
      }
    }
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
  "overallScore": 0,
  "statusLabel": "必须严格遵守分数档位映射",
  "oneLineSummary": "一句话总结，直接告诉用户当前最值得关注的结论",
  "executiveSummary": "120-220字的完整自然段，概括当前周期执行质量、变化趋势和主要关注点",
  "overallAssessment": ["2-4条总体判断"],
  "keyFindings": ["3-6条关键事实或发现"],
  "trendAnalysis": ["2-5条趋势分析"],
  "riskAssessment": ["0-4条风险说明，必须写清依据与建议"],
  "priorityActions": ["3-5条优先行动"],
  "dataQualityNotes": ["1-3条关于样本量、记录完整度、可信度的说明"],
  "recommendationRankings": [
    {
      "rank": 1,
      "kind": "action|risk|gap",
      "petIds": ["涉及的宠物 id"],
      "petNames": ["涉及的宠物名称"],
      "title": "建议标题",
      "summary": "为什么这条建议重要且紧急",
      "suggestedAction": "用户下一步应该怎么做"
    }
  ],
  "perPetReports": [
    {
      "petId": "必须与输入里的 petId 一致",
      "petName": "必须与输入里的 petName 一致",
      "score": 0,
      "statusLabel": "必须严格遵守分数档位映射",
      "whyThisScore": ["为什么是这个分数"],
      "topPriority": ["当前最该处理什么"],
      "missedItems": ["你漏了什么"],
      "recentChanges": ["最近有哪些变化"],
      "followUpPlan": ["后续怎么跟"],
      "summary": "该宠物的完整自然段摘要，可与 whyThisScore 互相印证",
      "careFocus": "一句本周期照护重点",
      "keyEvents": ["2-4条关键事件"],
      "trendAnalysis": ["1-3条趋势分析"],
      "riskAssessment": ["0-3条风险说明"],
      "recommendedActions": ["2-4条建议行动"],
      "followUpFocus": "一句后续观察重点"
    }
  ]
}

约束:
- 你要基于输入事实自行给出全局总分和单宠物分数，不要引用不存在的数值
- statusLabel 必须遵守固定档位：90-100=状态不错，80-89=状态还行，70-79=需要关注，60-69=急需关注，0-59=存在隐患
- recommendationRankings 必须按“重要且紧急”排序，数量至少为 max(5, 已选宠物数)
- recommendationRankings 必须覆盖每只已选宠物；多宠物场景下每条建议都要在 petNames 中显式点名对应宠物
- executiveSummary 不能是一句话简报，必须写成正式报告式摘要
- 每一段结论都要引用输入中的事实、统计或时间范围，不准空泛
- perPetReports 必须覆盖输入中的每一只宠物，且 petId/petName 不得串位
- 单宠物详细分析必须围绕五个固定段落展开：为什么是这个分数、当前最该处理什么、你漏了什么、最近有哪些变化、后续怎么跟
- 没有足够证据时，明确写“样本不足，仅供参考”或“建议继续观察”
- 不要给用药剂量、诊断名称或确定性医疗结论
- 所有字段都必须返回；没有内容时返回空数组或保守表述
''';

const String _visitSummarySystemPrompt = '''
你是宠物就诊准备助手。你只能整理用户提供的宠物历史数据，不得编造不存在的就诊结论，不得输出诊断结论。

始终使用简体中文，输出必须是一个 JSON object，不能出现 Markdown、解释文字或额外前后缀。

JSON schema:
{
  "visitReason": "本次就诊/复盘背景",
  "timeline": ["按时间排序的关键事件"],
  "medicationsAndTreatments": ["用药/护理/处置"],
  "testsAndResults": ["检查与结果"],
  "questionsToAskVet": ["建议问医生的问题"]
}

约束:
- 时间线尽量精炼，保留日期和事件
- 没有数据时要明确说明“暂无相关信息”
- 问题列表聚焦复查、观察点和下一步确认事项
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
请基于以下宠物照护上下文生成一份“高密度、能直接帮助用户决策”的 AI 总览。

分析目标:
- 输出全局总分、全局状态语和一句话总结
- 输出按重要且紧急排序的建议排行榜
- 给出关键事实、风险依据和优先行动
- 按宠物分别输出独立专项报告，并完成五段式详细分析

已知规则:
- 只能基于输入中的事实、缺口和规则模板判断，不要编造未提供的观察
- 优先依据宠物档案、expectedCare、missingCare、recentSignals 和关键统计下结论
- detailLevel 越低，说明这是为了提高生成稳定性而进行的降载版本，不要因为缺少细枝末节而编造内容
- 建议排行榜必须先保证宠物覆盖，再按重要且紧急排序
- detailLevel 越低，说明这是为了提高生成稳定性而进行的降载版本，不要因为缺少细枝末节而编造内容

压缩上下文:
${jsonEncode(payload)}
''';
}

String _buildVisitSummaryPrompt(AiGenerationContext context) {
  return '''
请基于以下宠物照护上下文生成就诊准备摘要。

分析目标:
- 归纳本次复查/就诊背景
- 提炼关键时间线
- 整理护理、用药、检查和结果
- 给出值得向兽医确认的问题

上下文数据:
${jsonEncode(context.toJson())}
''';
}

List<_CareReportPromptPlan> _buildCareReportPromptPlans(
  AiGenerationContext context, {
  required AiCareScorecard scorecard,
}) {
  return _CarePromptDetailLevel.values
      .map(
        (detailLevel) => _CareReportPromptPlan(
          label: detailLevel.label,
          prompt: _buildCareReportPrompt(
            context,
            scorecard: scorecard,
            detailLevel: detailLevel,
          ),
        ),
      )
      .toList(growable: false);
}

Map<String, dynamic> _buildCareReportPayload(
  AiGenerationContext context, {
  required AiCareScorecard scorecard,
  required _CarePromptDetailLevel detailLevel,
}) {
  final config = detailLevel.config;
  return {
    'analysisConfig': {
      'detailLevel': detailLevel.name,
      'title': context.title,
      'rangeLabel': context.rangeLabel,
      'rangeStart': context.rangeStart.toIso8601String(),
      'rangeEnd': context.rangeEnd.toIso8601String(),
      'rangeDays': context.rangeEnd.difference(context.rangeStart).inDays,
      'selectedPetIds': context.pets.map((pet) => pet.id).toList(growable: false),
      'selectedPetCount': context.pets.length,
      'languageTag': context.languageTag,
    },
    'scoringGuidelines': {
      'statusBands': const [
        {'min': 90, 'max': 100, 'label': '状态不错'},
        {'min': 80, 'max': 89, 'label': '状态还行'},
        {'min': 70, 'max': 79, 'label': '需要关注'},
        {'min': 60, 'max': 69, 'label': '急需关注'},
        {'min': 0, 'max': 59, 'label': '存在隐患'},
      ],
      'scoringFocus': const [
        '宠物特性决定的应做事项是否被安排和跟进',
        '提醒和待办是否及时完成，逾期与跳过需要扣分',
        '重点问题是否有连续记录和复查闭环',
        '样本不足时要明确提示信息缺口，不要强行下结论',
      ],
      'recommendationRules': {
        'sortBy': '重要且紧急',
        'minimumCount': context.pets.length < 5 ? 5 : context.pets.length,
        'mustCoverEverySelectedPet': true,
        'mentionPetNamesWhenMultiplePets': context.pets.length > 1,
      },
      'globalEvidence': {
        'todoStats': _countByName(
          context.todos.map((item) => item.status.name),
        ),
        'reminderStats': _countByName(
          context.reminders.map((item) => item.status.name),
        ),
        'recordStats': _countByName(
          context.records.map((item) => item.type.name),
        ),
        'recentSignals': _buildGlobalRecentSignals(
          context,
          config: config,
        ),
        'riskSignals': scorecard.riskCandidates
            .take(config.maxRiskCandidates)
            .toList(growable: false),
        'dataQualityNotes': scorecard.dataQualityNotes
            .take(config.maxDataQualityNotes)
            .toList(growable: false),
      },
    },
    'pets': context.pets
        .map(
          (pet) => _buildPetPromptSnapshot(
            context,
            pet: pet,
            scorecard: scorecard.petScorecards.firstWhere(
              (item) => item.petId == pet.id,
            ),
            config: config,
          ),
        )
        .toList(growable: false),
  };
}

Map<String, dynamic> _buildPetPromptSnapshot(
  AiGenerationContext context, {
  required Pet pet,
  required AiPetCareScorecard scorecard,
  required _CarePromptPayloadConfig config,
}) {
  final todos = context.todos.where((item) => item.petId == pet.id).toList();
  final reminders =
      context.reminders.where((item) => item.petId == pet.id).toList();
  final records = context.records.where((item) => item.petId == pet.id).toList();
  return {
    'profile': {
      'petId': pet.id,
      'petName': pet.name,
      'type': petTypeLabel(pet.type),
      'breed': pet.breed,
      'sex': pet.sex,
      'birthday': pet.birthday,
      'ageLabel': pet.ageLabel,
      'weightKg': pet.weightKg,
      'neuterStatus': petNeuterStatusLabel(pet.neuterStatus),
      'feedingPreferences': _trimPromptText(pet.feedingPreferences, 50),
      'allergies': _trimPromptText(pet.allergies, 50),
      'note': _trimPromptText(pet.note, 80),
    },
    'expectedCare': _buildExpectedCare(
      context,
      pet: pet,
      records: records,
    ),
    'missingCare': _buildMissingCare(
      pet: pet,
      todos: todos,
      reminders: reminders,
      records: records,
      scorecard: scorecard,
    ),
    'evidence': {
      'todoStats': _countByName(todos.map((item) => item.status.name)),
      'reminderStats': _countByName(reminders.map((item) => item.status.name)),
      'recordStats': _countByName(records.map((item) => item.type.name)),
      'recentSignals': _buildPetRecentSignals(
        pet: pet,
        todos: todos,
        reminders: reminders,
        records: records,
        config: config,
      ),
      'riskSignals': scorecard.riskCandidates
          .take(config.maxRiskCandidates)
          .toList(growable: false),
      'dataQualityNotes': scorecard.dataQualityNotes
          .take(config.maxDataQualityNotes)
          .toList(growable: false),
    },
  };
}

List<String> _buildExpectedCare(
  AiGenerationContext context, {
  required Pet pet,
  required List<PetRecord> records,
}) {
  final items = <String>{
    '保持饮食、排便、精神状态等基础观察的连续记录',
  };
  final ageYears = _estimatePetAgeYears(context.rangeEnd, pet.birthday);
  if (ageYears != null && ageYears < 1.5) {
    items.add('按成长阶段持续关注疫苗、驱虫和体重变化');
  }
  if (ageYears != null && ageYears >= 7) {
    items.add('关注老年期体重、活动量和定期检查安排');
  }
  if (pet.allergies.trim().isNotEmpty) {
    items.add('围绕过敏相关饮食和症状变化补充观察记录');
  }
  if (pet.note.trim().isNotEmpty) {
    items.add('围绕已知特性或既往备注问题做持续跟进');
  }
  final hasClinicalHistory = records.any(
    (item) =>
        item.type == PetRecordType.medical ||
        item.type == PetRecordType.testResult,
  );
  if (hasClinicalHistory) {
    items.add('针对既往医疗问题安排复查或后续观察闭环');
  }
  return items.toList(growable: false);
}

List<String> _buildMissingCare({
  required Pet pet,
  required List<TodoItem> todos,
  required List<ReminderItem> reminders,
  required List<PetRecord> records,
  required AiPetCareScorecard scorecard,
}) {
  final items = <String>[];
  final overdueTodos = todos.where((item) => item.status == TodoStatus.overdue).length;
  final skippedTodos = todos.where((item) => item.status == TodoStatus.skipped).length;
  final overdueReminders =
      reminders.where((item) => item.status == ReminderStatus.overdue).length;
  final skippedReminders =
      reminders.where((item) => item.status == ReminderStatus.skipped).length;
  if (overdueTodos > 0) {
    items.add('${pet.name} 还有$overdueTodos条待办没有及时闭环');
  }
  if (skippedTodos > 0) {
    items.add('${pet.name} 有$skippedTodos条待办被跳过，说明关键跟进可能缺口');
  }
  if (overdueReminders > 0) {
    items.add('${pet.name} 有$overdueReminders条定期提醒未按时完成');
  }
  if (skippedReminders > 0) {
    items.add('${pet.name} 有$skippedReminders条提醒被跳过，需要确认是否仍然必要');
  }
  if (records.isEmpty) {
    items.add('${pet.name} 当前时间段缺少观察记录，难以判断真实状态');
  }
  if (pet.allergies.trim().isNotEmpty && records.isEmpty) {
    items.add('${pet.name} 已知有过敏特性，但当前缺少相关跟进证据');
  }
  for (final candidate in scorecard.riskCandidates.take(2)) {
    if (!items.contains(candidate)) {
      items.add(candidate);
    }
  }
  if (items.isEmpty) {
    items.add('${pet.name} 当前没有明确缺口，但仍建议保持连续记录');
  }
  return items;
}

List<String> _buildGlobalRecentSignals(
  AiGenerationContext context, {
  required _CarePromptPayloadConfig config,
}) {
  final items = <String>[];
  for (final todo in _sampleTodos(
    context.todos,
    maxItems: config.maxGlobalTodoSamples,
  )) {
    items.add('待办：${todo['title']}（${todo['status']}）');
  }
  for (final reminder in _sampleReminders(
    context.reminders,
    maxItems: config.maxGlobalReminderSamples,
  )) {
    items.add('提醒：${reminder['title']}（${reminder['status']}）');
  }
  for (final record in _sampleRecords(
    context.records,
    maxItems: config.maxGlobalRecordSamples,
  )) {
    items.add('记录：${record['title']}（${record['type']}）');
  }
  return items;
}

List<String> _buildPetRecentSignals({
  required Pet pet,
  required List<TodoItem> todos,
  required List<ReminderItem> reminders,
  required List<PetRecord> records,
  required _CarePromptPayloadConfig config,
}) {
  final items = <String>[];
  for (final todo in _sampleTodos(todos, maxItems: config.maxPerPetTodoSamples)) {
    items.add('${pet.name} 待办：${todo['title']}（${todo['status']}）');
  }
  for (final reminder in _sampleReminders(
    reminders,
    maxItems: config.maxPerPetReminderSamples,
  )) {
    items.add('${pet.name} 提醒：${reminder['title']}（${reminder['status']}）');
  }
  for (final record in _sampleRecords(
    records,
    maxItems: config.maxPerPetRecordSamples,
  )) {
    items.add('${pet.name} 记录：${record['title']}（${record['type']}）');
  }
  return items;
}

double? _estimatePetAgeYears(DateTime reference, String birthday) {
  final raw = birthday.trim();
  if (raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return null;
  }
  return reference.difference(parsed).inDays / 365;
}

Map<String, int> _countByName(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (current) => current + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<Map<String, dynamic>> _sampleTodos(
  List<TodoItem> todos, {
  required int maxItems,
}) {
  final sampled = List<TodoItem>.from(todos)
    ..sort((a, b) {
      final priorityCompare = _todoPriority(a).compareTo(_todoPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.dueAt.compareTo(a.dueAt);
    });
  return sampled.take(maxItems).map((todo) {
    return {
      'petId': todo.petId,
      'title': todo.title,
      'dueAt': todo.dueAt.toIso8601String(),
      'status': todo.status.name,
      'note': _trimPromptText(todo.note, 70),
    };
  }).toList(growable: false);
}

List<Map<String, dynamic>> _sampleReminders(
  List<ReminderItem> reminders, {
  required int maxItems,
}) {
  final sampled = List<ReminderItem>.from(reminders)
    ..sort((a, b) {
      final priorityCompare =
          _reminderPriority(a).compareTo(_reminderPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.scheduledAt.compareTo(a.scheduledAt);
    });
  return sampled.take(maxItems).map((reminder) {
    return {
      'petId': reminder.petId,
      'kind': reminder.kind.name,
      'title': reminder.title,
      'scheduledAt': reminder.scheduledAt.toIso8601String(),
      'status': reminder.status.name,
      'recurrence': reminder.recurrence,
      'note': _trimPromptText(reminder.note, 70),
    };
  }).toList(growable: false);
}

List<Map<String, dynamic>> _sampleRecords(
  List<PetRecord> records, {
  required int maxItems,
}) {
  final sampled = List<PetRecord>.from(records)
    ..sort((a, b) {
      final priorityCompare = _recordPriority(a).compareTo(_recordPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.recordDate.compareTo(a.recordDate);
    });
  return sampled.take(maxItems).map((record) {
    return {
      'petId': record.petId,
      'type': record.type.name,
      'title': record.title,
      'recordDate': record.recordDate.toIso8601String(),
      'summary': _trimPromptText(record.summary, 80),
      'note': _trimPromptText(record.note, 100),
    };
  }).toList(growable: false);
}

int _todoPriority(TodoItem item) => switch (item.status) {
      TodoStatus.overdue => 0,
      TodoStatus.open => 1,
      TodoStatus.postponed => 2,
      TodoStatus.skipped => 3,
      TodoStatus.done => 4,
    };

int _reminderPriority(ReminderItem item) => switch (item.status) {
      ReminderStatus.overdue => 0,
      ReminderStatus.pending => 1,
      ReminderStatus.postponed => 2,
      ReminderStatus.skipped => 3,
      ReminderStatus.done => 4,
    };

int _recordPriority(PetRecord item) => switch (item.type) {
      PetRecordType.medical => 0,
      PetRecordType.testResult => 1,
      PetRecordType.image => 2,
      PetRecordType.receipt => 3,
      PetRecordType.other => 4,
    };

String _trimPromptText(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength)}…';
}

class _CareReportPromptPlan {
  const _CareReportPromptPlan({
    required this.label,
    required this.prompt,
  });

  final String label;
  final String prompt;
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
  );

  const _CarePromptDetailLevel(this.label, this.config);

  final String label;
  final _CarePromptPayloadConfig config;
}

class _AiRetryableGenerationException extends AiGenerationException {
  const _AiRetryableGenerationException(super.message);
}
