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
  static const Duration _cloudflareGenerationRequestTimeout =
      Duration(seconds: 90);
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
      final maxAttempts = plan.detailLevel == _CarePromptDetailLevel.full ? 2 : 1;
      for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
        try {
          final jsonObject = await _generateStructuredJson(
            client: client,
            systemPrompt: _careReportSystemPrompt,
            userPrompt: plan.prompt,
          );
          jsonObject['promptPayloadVersion'] = plan.detailLevel.name;
          jsonObject['promptPayloadVersionLabel'] = plan.detailLevel.displayLabel;
          return AiCareReport.fromJson(
            jsonObject,
            scorecard: scorecard,
          );
        } on _AiRetryableGenerationException catch (error) {
          if (index == promptPlans.length - 1) {
            throw AiGenerationException(
              ' 已经尝试使用更轻量的上下文重试，但当前模型仍无法稳定完成总览生成。请先切换到较短时间范围，或更换更稳定的模型/供应商后再试。',
            );
          }
          final nextPlan = promptPlans[index + 1];
          appLogController?.warning(
            category: AppLogCategory.ai,
            title: 'AI 总览降载重试',
            message: '当前服务在上下文下未稳定返回，改用上下文重试。',
            details: error.message,
          );
          break;
        } on AiGenerationException catch (error) {
          if (_looksLikeRetryableSchemaGap(error) &&
              _shouldRetrySamePayloadLevel(
                plan: plan,
                attempt: attempt,
                maxAttempts: maxAttempts,
              )) {
            appLogController?.warning(
              category: AppLogCategory.ai,
              title: 'AI 总览缺字段同档重试',
              message: '当前服务在上下文下漏了必填字段，先保持当前数据版重试。',
              details: error.message,
            );
            continue;
          }
          rethrow;
        }
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
      if (_looksLikeLengthTruncatedResponse(
        providerType: client.providerType,
        rawBody: response.body,
      )) {
        throw const _AiRetryableGenerationException(
          'AI 输出因长度限制被截断，已切换更轻量的上下文重试。',
        );
      }
      throw AiGenerationException(
        _buildInvalidAiContentMessage(
          baseMessage: _structuredJsonFailureMessage(client.providerType),
          rawContent: content,
        ),
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
        AiProviderType.cloudflareWorkersAi => _sendOpenAiCompatiblePrompt(
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
    var useStructuredOutput = true;
    var request = _buildOpenAiRequest(
      client: client,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      useStructuredOutput: useStructuredOutput,
      stream: false,
    );
    appLogController?.info(
      category: AppLogCategory.ai,
      title: '发送 AI 请求',
      message: '${request.method} ${request.uri}',
      details: 'timeout=${request.timeout?.inSeconds ?? 10}s',
    );
    var response = await _transport.send(request);
    if (_looksLikeStructuredOutputUnsupportedResponse(response)) {
      useStructuredOutput = false;
      request = _buildOpenAiRequest(
        client: client,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        useStructuredOutput: useStructuredOutput,
        stream: false,
      );
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 请求降级重试',
        message: '当前兼容服务不支持 response_format，改用普通 JSON 提示词重试。',
        details: '${request.method} ${request.uri}',
      );
      response = await _transport.send(request);
    }
    if (shouldRetryOpenAiCompatibleWithStreamResponse(
      providerType: client.providerType,
      response: response,
    )) {
      request = _buildOpenAiRequest(
        client: client,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        useStructuredOutput: useStructuredOutput,
        stream: true,
      );
      appLogController?.warning(
        category: AppLogCategory.ai,
        title: 'AI 请求流式重试',
        message: '兼容服务非流式返回缺少正文，改用 stream=true 重试。',
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
      timeout: _generationRequestTimeoutFor(client),
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
    bool stream = false,
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
    final maxTokens = aiProviderDefaultMaxTokens(
      client.providerType,
      baseUrl: client.baseUrl,
      model: client.model,
    );
    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }
    if (useStructuredOutput) {
      body['response_format'] = const {
        'type': 'json_object',
      };
    }
    if (stream) {
      body['stream'] = true;
    }
    return AiHttpRequest(
      method: 'POST',
      uri: Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${client.apiKey}',
        'Accept': stream ? 'text/event-stream' : 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
      timeout: _generationRequestTimeoutFor(client),
    );
  }

  Duration _generationRequestTimeoutFor(AiProviderClient client) {
    if (client.providerType == AiProviderType.cloudflareWorkersAi ||
        client.providerType == AiProviderType.openaiCompatible &&
            looksLikeCloudflareWorkersAiUrl(client.baseUrl)) {
      return _cloudflareGenerationRequestTimeout;
    }
    return _generationRequestTimeout;
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
    final providerMessage = _extractErrorMessage(response.body);
    if (response.statusCode == 408 ||
        response.statusCode == 425 ||
        response.statusCode == 500 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw _AiRetryableGenerationException(
        providerMessage == null || providerMessage.isEmpty
            ? 'AI 服务暂时不可用，服务返回 ${response.statusCode}。'
            : 'AI 服务暂时不可用：$providerMessage',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiGenerationException(
        providerMessage == null || providerMessage.isEmpty
            ? 'AI 服务暂时不可用，服务返回 ${response.statusCode}。'
            : 'AI 服务返回错误：$providerMessage',
      );
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
      if (providerType != AiProviderType.anthropic) {
        final fallbackText =
            _extractTextFromMalformedOpenAiResponse(response.body);
        if (fallbackText != null && fallbackText.trim().isNotEmpty) {
          return fallbackText.trim();
        }
        if (_looksLikeLengthTruncatedResponse(
          providerType: providerType,
          rawBody: response.body,
        )) {
          throw const _AiRetryableGenerationException(
            'AI 输出因长度限制被截断，已切换更轻量的上下文重试。',
          );
        }
      }
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回不是合法 JSON。',
          responseBody: response.body,
        ),
      );
    }

    return switch (providerType) {
      AiProviderType.openai ||
      AiProviderType.openaiCompatible ||
      AiProviderType.cloudflareWorkersAi =>
        _extractOpenAiContent(providerType, decoded, response.body),
      AiProviderType.anthropic =>
        _extractAnthropicContent(decoded, response.body),
    };
  }

  String _extractOpenAiContent(
    AiProviderType providerType,
    Map<String, dynamic> decoded,
    String rawBody,
  ) {
    final providerMessage = _extractErrorMessage(rawBody);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回未包含聊天结果。',
          responseBody: rawBody,
          providerMessage: providerMessage,
        ),
      );
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回未包含聊天结果。',
          responseBody: rawBody,
          providerMessage: providerMessage,
        ),
      );
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回未包含聊天结果。',
          responseBody: rawBody,
          providerMessage: providerMessage,
        ),
      );
    }
    final buffer = StringBuffer();
    _appendTextContent(message['content'], buffer);
    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
    if (_looksLikeLengthTruncatedChoice(firstChoice)) {
      throw const _AiRetryableGenerationException(
        'AI 输出因长度限制被截断，已切换更轻量的上下文重试。',
      );
    }
    throw AiGenerationException(
      _buildInvalidAiResponseMessage(
        baseMessage: providerType == AiProviderType.cloudflareWorkersAi
            ? 'Cloudflare Workers AI 返回 stop，但没有正文内容，根因更像兼容层非流式聚合异常。'
            : 'AI 端返回未包含文本内容，根因更像兼容层未返回正文。',
        responseBody: rawBody,
        providerMessage: providerMessage,
      ),
    );
  }

  String _extractAnthropicContent(
      Map<String, dynamic> decoded, String rawBody) {
    final providerMessage = _extractErrorMessage(rawBody);
    final content = decoded['content'];
    if (content is! List || content.isEmpty) {
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回未包含消息内容。',
          responseBody: rawBody,
          providerMessage: providerMessage,
        ),
      );
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map && item['type'] == 'text' && item['text'] is String) {
        buffer.writeln(item['text'] as String);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw AiGenerationException(
        _buildInvalidAiResponseMessage(
          baseMessage: 'AI 端返回未包含文本内容。',
          responseBody: rawBody,
          providerMessage: providerMessage,
        ),
      );
    }
    return text;
  }

  Map<String, dynamic>? _extractJsonObject(String text) {
    final direct = _tryDecodeJson(text);
    if (direct is Map<String, dynamic>) {
      return direct;
    }

    for (final fencedMatch
        in RegExp(r'```(?:json)?\s*([\s\S]*?)```').allMatches(text)) {
      final fencedText = fencedMatch.group(1)!.trim();
      final fenced = _tryDecodeJson(fencedText);
      if (fenced is Map<String, dynamic>) {
        return fenced;
      }
      final nested = _extractJsonObjectFromText(fencedText);
      if (nested != null) {
        return nested;
      }
    }

    return _extractJsonObjectFromText(text);
  }

  Map<String, dynamic>? _extractJsonObjectFromText(String text) {
    for (var startIndex = text.indexOf('{');
        startIndex != -1;
        startIndex = text.indexOf('{', startIndex + 1)) {
      if (!_looksLikeJsonObjectStart(text, startIndex)) {
        continue;
      }
      final candidate = _readBalancedJsonObject(text, startIndex);
      if (candidate == null) {
        continue;
      }
      final decoded = _tryDecodeJson(candidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return null;
  }

  String? _readBalancedJsonObject(String text, int startIndex) {
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
          return text.substring(startIndex, index + 1);
        }
      }
    }
    return null;
  }

  bool _looksLikeJsonObjectStart(String text, int startIndex) {
    if (startIndex < 0 ||
        startIndex >= text.length ||
        text[startIndex] != '{') {
      return false;
    }
    for (var index = startIndex + 1; index < text.length; index += 1) {
      final char = text[index];
      if (_isJsonWhitespace(char)) {
        continue;
      }
      return char == '"' || char == '}';
    }
    return true;
  }

  bool _isJsonWhitespace(String char) {
    return char == ' ' || char == '\n' || char == '\r' || char == '\t';
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

  String? _extractTextFromMalformedOpenAiResponse(String rawBody) {
    final content = _extractMalformedJsonStringField(
      rawBody,
      fieldName: 'content',
    );
    if (content != null && content.trim().isNotEmpty) {
      return content;
    }
    final text = _extractMalformedJsonStringField(
      rawBody,
      fieldName: 'text',
    );
    if (text != null && text.trim().isNotEmpty) {
      return text;
    }
    return null;
  }

  String? _extractMalformedJsonStringField(
    String rawBody, {
    required String fieldName,
  }) {
    final marker = '"$fieldName"';
    var searchStart = 0;
    while (searchStart < rawBody.length) {
      final fieldIndex = rawBody.indexOf(marker, searchStart);
      if (fieldIndex == -1) {
        return null;
      }
      var cursor = fieldIndex + marker.length;
      while (cursor < rawBody.length && _isJsonWhitespace(rawBody[cursor])) {
        cursor += 1;
      }
      if (cursor >= rawBody.length || rawBody[cursor] != ':') {
        searchStart = fieldIndex + marker.length;
        continue;
      }
      cursor += 1;
      while (cursor < rawBody.length && _isJsonWhitespace(rawBody[cursor])) {
        cursor += 1;
      }
      if (cursor >= rawBody.length) {
        return null;
      }
      if (rawBody.startsWith('null', cursor)) {
        return null;
      }
      if (rawBody[cursor] != '"') {
        searchStart = fieldIndex + marker.length;
        continue;
      }
      return _readLenientJsonString(rawBody, cursor);
    }
    return null;
  }

  String? _readLenientJsonString(String rawBody, int openingQuoteIndex) {
    final buffer = StringBuffer();
    var index = openingQuoteIndex + 1;
    var escaped = false;
    while (index < rawBody.length) {
      final char = rawBody[index];
      if (escaped) {
        if (char == 'u' && index + 4 < rawBody.length) {
          final hex = rawBody.substring(index + 1, index + 5);
          final codePoint = int.tryParse(hex, radix: 16);
          if (codePoint != null) {
            buffer.writeCharCode(codePoint);
            index += 5;
            escaped = false;
            continue;
          }
        }
        buffer.write(switch (char) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          'b' => '\b',
          'f' => '\f',
          '"' => '"',
          '\\' => '\\',
          '/' => '/',
          _ => char,
        });
        escaped = false;
        index += 1;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        index += 1;
        continue;
      }
      if (char == '"') {
        return buffer.toString();
      }
      buffer.write(char);
      index += 1;
    }
    return buffer.toString();
  }

  String _structuredJsonFailureMessage(AiProviderType providerType) {
    if (providerType == AiProviderType.cloudflareWorkersAi) {
      return 'Cloudflare Workers AI 返回的内容不是结构化 JSON，请检查该模型是否支持 JSON Mode，或适当增大输出长度。';
    }
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

  String _buildInvalidAiResponseMessage({
    required String baseMessage,
    required String responseBody,
    String? providerMessage,
  }) {
    final normalizedProviderMessage = providerMessage?.trim();
    if (normalizedProviderMessage != null &&
        normalizedProviderMessage.isNotEmpty) {
      return normalizedProviderMessage;
    }
    final preview = _previewText(responseBody);
    if (preview == 'empty') {
      return baseMessage;
    }
    return '$baseMessage AI 端返回：$preview';
  }

  String _buildInvalidAiContentMessage({
    required String baseMessage,
    required String rawContent,
  }) {
    final preview = _previewText(rawContent);
    if (preview == 'empty') {
      return baseMessage;
    }
    return '$baseMessage AI 端返回：$preview';
  }

  bool _looksLikeLengthTruncatedResponse({
    required AiProviderType providerType,
    required String rawBody,
  }) {
    if (providerType == AiProviderType.anthropic) {
      return false;
    }
    final normalizedBody = rawBody.toLowerCase();
    if (normalizedBody.contains('"finish_reason":"length"') ||
        normalizedBody.contains('"finish_reason": "length"') ||
        normalizedBody.contains('"stop_reason":"max_tokens"') ||
        normalizedBody.contains('"stop_reason": "max_tokens"')) {
      return true;
    }
    final decoded = _tryDecodeJson(rawBody);
    if (decoded is! Map<String, dynamic>) {
      final fallbackText = _extractTextFromMalformedOpenAiResponse(rawBody);
      return fallbackText != null &&
          _looksLikeIncompleteJsonObject(fallbackText);
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return false;
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return false;
    }
    return _looksLikeLengthTruncatedChoice(firstChoice);
  }

  bool _looksLikeLengthTruncatedChoice(Map choice) {
    final finishReason = choice['finish_reason'];
    if (finishReason is String) {
      final normalized = finishReason.trim().toLowerCase();
      if (normalized == 'length' || normalized == 'max_tokens') {
        return true;
      }
    }
    final stopReason = choice['stop_reason'];
    if (stopReason is String &&
        stopReason.trim().toLowerCase() == 'max_tokens') {
      return true;
    }
    final message = choice['message'];
    if (message is Map) {
      final buffer = StringBuffer();
      _appendTextContent(message['content'], buffer);
      if (_looksLikeIncompleteJsonObject(buffer.toString())) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeIncompleteJsonObject(String text) {
    for (var startIndex = text.indexOf('{');
        startIndex != -1;
        startIndex = text.indexOf('{', startIndex + 1)) {
      if (!_looksLikeJsonObjectStart(text, startIndex)) {
        continue;
      }
      if (_readBalancedJsonObject(text, startIndex) == null) {
        return true;
      }
    }
    return false;
  }
}

const String _careReportSystemPrompt = '''
你是宠物日常照护分析助手。你只能基于给定数据，从宠物当前状态、变化趋势、照护缺口和后续照护重点出发做总结、风险关注和下一步建议，不能编造事实，不能输出诊断结论，也不能假装自己是兽医。

始终使用简体中文，输出必须是一个 JSON object，不能出现 Markdown、解释文字或代码块之外的额外内容。

JSON schema:
{
  "overallScore": 0,
  "perPetReports": [
    {
      "petId": "必须与输入里的 petId 一致",
      "petName": "必须与输入里的 petName 一致",
      "score": 0,
      "whyThisScore": ["为什么是这个分数"],
      "topPriority": ["现在应该怎么做"],
      "missedItems": ["你漏了什么重要信息"],
      "followUpPlan": ["后续要怎么跟进"]
    }
  ],
  "oneLineSummary": "一句话总结，直接概括宠物当前最值得关注的状态结论",
  "executiveSummary": "60-100字的完整自然段，概括当前周期执行质量、变化趋势和主要关注点",
  "overallAssessment": ["1-3条总体判断"],
  "keyFindings": ["2-4条关键事实或发现"],
  "trendAnalysis": ["1-3条趋势分析"],
  "riskAssessment": ["0-4条风险说明，必须写清依据与建议"],
  "priorityActions": ["3-5条优先行动"],
  "recommendationRankings": [
    {
      "rank": 1,
      "kind": "action|risk|gap",
      "petIds": ["涉及的宠物 id"],
      "petNames": ["涉及的宠物名称"],
      "title": "建议标题",
      "summary": "为什么这条建议重要且紧急",
      "suggestedAction": "围绕宠物当前状态与照护重点的下一步建议"
    }
  ]
}

约束:
- 顶层必填字段固定为：overallScore、perPetReports、oneLineSummary、executiveSummary、overallAssessment、keyFindings、trendAnalysis、riskAssessment、priorityActions、recommendationRankings；缺少任何一个都视为输出不合格
- recommendationRankings 中每一项都必须包含：rank、kind、petIds、petNames、title、summary、suggestedAction；没有内容也要返回空数组或保守表述，不能省略键名
- perPetReports 中每一项都必须包含：petId、petName、score、whyThisScore、topPriority、missedItems、followUpPlan；没有内容也要返回空数组，不能省略键名
- 输出前先逐项自检所有必填字段是否齐全、类型是否正确；如果发现缺字段，先补齐再结束输出
- 你要基于输入事实自行给出全局总分和单宠物分数，不要引用不存在的数值
- 先完整输出 perPetReports，再输出全局总结和 recommendationRankings，避免遗漏单宠物专项报告
- recommendationRankings 必须按“重要且紧急”排序，数量至少为 max(5, 已选宠物数)
- recommendationRankings 必须覆盖每只已选宠物；多宠物场景下每条建议都要在 petNames 中显式点名对应宠物
- executiveSummary 不能是一句话简报，必须是紧凑但完整的短版摘要
- 每一段结论都要引用输入中的事实、统计或时间范围，不准空泛
- perPetReports 必须覆盖输入中的每一只宠物，且 petId/petName 不得串位
- 单宠物详细分析只围绕四个固定段落展开：为什么是这个分数、现在应该怎么做、你漏了什么重要信息、后续要怎么跟进；不要重复输出额外的小结字段，也不要把本地统计说明改写成额外段落
- 所有结论与建议都要优先围绕宠物本身展开，例如宠物最近状态如何、当前更需要补什么照护、接下来该关注哪些变化；不要站在人类任务管理视角输出“主人应该如何监控、记得观察、记得打卡”这类空泛表述
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
请基于以下逐宠物照护数据生成 AI 总览，并从 pets 数组自行归纳全局结论。

上下文:
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
          detailLevel: detailLevel,
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
    'context': {
      'detailLevel': detailLevel.name,
      'title': context.title,
      'rangeLabel': context.rangeLabel,
      'rangeStart': context.rangeStart.toIso8601String(),
      'rangeEnd': context.rangeEnd.toIso8601String(),
      'rangeDays': context.rangeEnd.difference(context.rangeStart).inDays,
      'selectedPetCount': context.pets.length,
      'languageTag': context.languageTag,
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
  final records =
      context.records.where((item) => item.petId == pet.id).toList();
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
    'evidence': {
      'todoStats': _countByName(todos.map((item) => item.status.name)),
      'reminderStats': _countByName(reminders.map((item) => item.status.name)),
      'recordStats': _countByName(records.map((item) => item.type.name)),
      'todos': _sampleTodos(todos, keepRatio: config.itemKeepRatio),
      'reminders': _sampleReminders(
        reminders,
        keepRatio: config.itemKeepRatio,
      ),
      'records': _sampleRecords(records, keepRatio: config.itemKeepRatio),
    },
  };
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
  required double keepRatio,
}) {
  final sampled = List<TodoItem>.from(todos)
    ..sort((a, b) {
      final priorityCompare = _todoPriority(a).compareTo(_todoPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.dueAt.compareTo(a.dueAt);
    });
  return _selectEvenly(sampled, keepRatio: keepRatio).map((todo) {
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
  required double keepRatio,
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
  return _selectEvenly(sampled, keepRatio: keepRatio).map((reminder) {
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
  required double keepRatio,
}) {
  final sampled = List<PetRecord>.from(records)
    ..sort((a, b) {
      final priorityCompare = _recordPriority(a).compareTo(_recordPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.recordDate.compareTo(a.recordDate);
    });
  return _selectEvenly(sampled, keepRatio: keepRatio).map((record) {
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

List<T> _selectEvenly<T>(
  List<T> items, {
  required double keepRatio,
}) {
  if (items.isEmpty || keepRatio >= 1) {
    return List<T>.from(items, growable: false);
  }
  final targetCount = (items.length * keepRatio).ceil().clamp(1, items.length);
  if (targetCount >= items.length) {
    return List<T>.from(items, growable: false);
  }
  final selected = <T>[];
  final usedIndexes = <int>{};
  final priorityCount = targetCount <= 2 ? 1 : 2;
  for (var index = 0; index < priorityCount && index < items.length; index += 1) {
    selected.add(items[index]);
    usedIndexes.add(index);
  }
  if (selected.length >= targetCount) {
    return selected.take(targetCount).toList(growable: false);
  }
  final remainingSlots = targetCount - selected.length;
  final candidateIndexes = [
    for (var index = priorityCount; index < items.length; index += 1) index,
  ];
  if (remainingSlots >= candidateIndexes.length) {
    selected.addAll(candidateIndexes.map((index) => items[index]));
    return selected.toList(growable: false);
  }
  if (remainingSlots == 1) {
    final midIndex = candidateIndexes[(candidateIndexes.length - 1) ~/ 2];
    selected.add(items[midIndex]);
    return selected.toList(growable: false);
  }
  final lastPosition = candidateIndexes.length - 1;
  for (var slot = 0; slot < remainingSlots; slot += 1) {
    final rawIndex = (slot * lastPosition / (remainingSlots - 1)).round();
    final candidateIndex = candidateIndexes[rawIndex];
    if (usedIndexes.add(candidateIndex)) {
      selected.add(items[candidateIndex]);
    }
  }
  if (selected.length < targetCount) {
    for (final candidateIndex in candidateIndexes) {
      if (usedIndexes.add(candidateIndex)) {
        selected.add(items[candidateIndex]);
        if (selected.length >= targetCount) {
          break;
        }
      }
    }
  }
  return selected.toList(growable: false);
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

bool _looksLikeRetryableSchemaGap(AiGenerationException error) {
  final message = error.message;
  return message.contains('结构化输出不完整') ||
      message.contains('模型未按 schema 输出') ||
      message.contains('AI 返回的结构化结果缺少');
}

bool _shouldRetrySamePayloadLevel({
  required _CareReportPromptPlan plan,
  required int attempt,
  required int maxAttempts,
}) {
  return plan.detailLevel == _CarePromptDetailLevel.full &&
      attempt < maxAttempts - 1;
}

class _CareReportPromptPlan {
  const _CareReportPromptPlan({
    required this.label,
    required this.prompt,
    required this.detailLevel,
  });

  final String label;
  final String prompt;
  final _CarePromptDetailLevel detailLevel;
}

class _CarePromptPayloadConfig {
  const _CarePromptPayloadConfig({
    required this.itemKeepRatio,
  });

  final double itemKeepRatio;
}

enum _CarePromptDetailLevel {
  full(
    '所有数据',
    _CarePromptPayloadConfig(
      itemKeepRatio: 1,
    ),
  ),
  balanced(
    '一半数据',
    _CarePromptPayloadConfig(
      itemKeepRatio: 0.5,
    ),
  ),
  minimal(
    '轻量数据',
    _CarePromptPayloadConfig(
      itemKeepRatio: 0.25,
    ),
  );

  const _CarePromptDetailLevel(this.label, this.config);

  final String label;
  final _CarePromptPayloadConfig config;

  String get displayLabel => switch (this) {
        _CarePromptDetailLevel.full => '所有数据',
        _CarePromptDetailLevel.balanced => '一半数据',
        _CarePromptDetailLevel.minimal => '轻量数据',
      };
}

class _AiRetryableGenerationException extends AiGenerationException {
  const _AiRetryableGenerationException(super.message);
}
