import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_url_utils.dart';

class AiConnectionTestResult {
  const AiConnectionTestResult({
    required this.status,
    required this.message,
  });

  final AiConnectionStatus status;
  final String message;
}

class AiHttpRequest {
  const AiHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
    this.timeout,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final Duration? timeout;
}

class AiHttpResponse {
  const AiHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract class AiHttpTransport {
  Future<AiHttpResponse> send(AiHttpRequest request);
}

class HttpClientAiHttpTransport implements AiHttpTransport {
  HttpClientAiHttpTransport({
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const Duration _defaultTimeout = Duration(seconds: 10);

  final HttpClient Function() _httpClientFactory;

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) async {
    final client = _httpClientFactory();
    final timeout = request.timeout ?? _defaultTimeout;
    try {
      final httpRequest =
          await client.openUrl(request.method, request.uri).timeout(timeout);
      request.headers.forEach(httpRequest.headers.set);
      final requestBody = request.body;
      if (requestBody != null) {
        httpRequest.add(utf8.encode(requestBody));
      }
      final httpResponse = await httpRequest.close().timeout(timeout);
      final responseBody = await _readResponseBody(httpResponse, timeout);
      return AiHttpResponse(
        statusCode: httpResponse.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readResponseBody(
    HttpClientResponse httpResponse,
    Duration timeout,
  ) {
    final contentType = httpResponse.headers.contentType;
    final mediaType = contentType?.mimeType.toLowerCase();
    if (mediaType == 'text/event-stream') {
      return _readEventStreamBody(httpResponse, timeout);
    }
    return utf8.decoder.bind(httpResponse).join().timeout(timeout);
  }

  Future<String> _readEventStreamBody(
    HttpClientResponse httpResponse,
    Duration timeout,
  ) async {
    final rawBody =
        await utf8.decoder.bind(httpResponse).join().timeout(timeout);
    return decodeSseToOpenAiChatCompletionBody(rawBody) ?? rawBody;
  }
}

enum AiStrictProbeKind {
  openAiChatCompletions,
  anthropicMessages,
}

enum AiModelDiscoveryPolicy {
  required,
  optional,
  fallbackOnMethodNotAllowed,
  skip,
}

class AiProviderRuntimeProfile {
  const AiProviderRuntimeProfile({
    required this.id,
    required this.providerType,
    required this.strictProbeKind,
    required this.modelDiscoveryPolicy,
    required this.strictProbeTimeout,
  });

  final String id;
  final AiProviderType providerType;
  final AiStrictProbeKind strictProbeKind;
  final AiModelDiscoveryPolicy modelDiscoveryPolicy;
  final Duration strictProbeTimeout;
}

AiProviderRuntimeProfile resolveAiProviderRuntimeProfile({
  required AiProviderType providerType,
  required String baseUrl,
}) {
  switch (providerType) {
    case AiProviderType.openai:
      return const AiProviderRuntimeProfile(
        id: 'openai',
        providerType: AiProviderType.openai,
        strictProbeKind: AiStrictProbeKind.openAiChatCompletions,
        modelDiscoveryPolicy: AiModelDiscoveryPolicy.required,
        strictProbeTimeout: Duration(seconds: 20),
      );
    case AiProviderType.anthropic:
      return const AiProviderRuntimeProfile(
        id: 'anthropic',
        providerType: AiProviderType.anthropic,
        strictProbeKind: AiStrictProbeKind.anthropicMessages,
        modelDiscoveryPolicy: AiModelDiscoveryPolicy.required,
        strictProbeTimeout: Duration(seconds: 20),
      );
    case AiProviderType.openaiCompatible:
      if (looksLikeCloudflareWorkersAiUrl(baseUrl)) {
        return const AiProviderRuntimeProfile(
          id: 'openai-compatible-cloudflare-workers-ai',
          providerType: AiProviderType.openaiCompatible,
          strictProbeKind: AiStrictProbeKind.openAiChatCompletions,
          modelDiscoveryPolicy: AiModelDiscoveryPolicy.skip,
          strictProbeTimeout: Duration(seconds: 60),
        );
      }
      final uri = Uri.tryParse(baseUrl);
      if (uri != null && uri.host == 'open.bigmodel.cn') {
        return const AiProviderRuntimeProfile(
          id: 'openai-compatible-bigmodel',
          providerType: AiProviderType.openaiCompatible,
          strictProbeKind: AiStrictProbeKind.openAiChatCompletions,
          modelDiscoveryPolicy: AiModelDiscoveryPolicy.required,
          strictProbeTimeout: Duration(seconds: 28),
        );
      }
      return const AiProviderRuntimeProfile(
        id: 'openai-compatible-generic',
        providerType: AiProviderType.openaiCompatible,
        strictProbeKind: AiStrictProbeKind.openAiChatCompletions,
        modelDiscoveryPolicy: AiModelDiscoveryPolicy.optional,
        strictProbeTimeout: Duration(seconds: 20),
      );
    case AiProviderType.cloudflareWorkersAi:
      return const AiProviderRuntimeProfile(
        id: 'cloudflare-workers-ai',
        providerType: AiProviderType.cloudflareWorkersAi,
        strictProbeKind: AiStrictProbeKind.openAiChatCompletions,
        modelDiscoveryPolicy: AiModelDiscoveryPolicy.skip,
        strictProbeTimeout: Duration(seconds: 60),
      );
  }
}

bool aiProviderSupportsResponseFormat(AiProviderType providerType) {
  return providerType != AiProviderType.anthropic;
}

AiProviderType resolveEffectiveAiProviderType(
  AiProviderType providerType, {
  String? baseUrl,
}) {
  return providerType == AiProviderType.openaiCompatible &&
          baseUrl != null &&
          looksLikeCloudflareWorkersAiUrl(baseUrl)
      ? AiProviderType.cloudflareWorkersAi
      : providerType;
}

int? aiProviderDefaultMaxTokens(
  AiProviderType providerType, {
  String? baseUrl,
  String? model,
}) {
  final effectiveProviderType = resolveEffectiveAiProviderType(
    providerType,
    baseUrl: baseUrl,
  );
  return switch (effectiveProviderType) {
    AiProviderType.cloudflareWorkersAi => 4096,
    _ => null,
  };
}

int? aiProviderStrictProbeMaxTokens(AiProviderType providerType) {
  return switch (providerType) {
    AiProviderType.cloudflareWorkersAi => 1024,
    _ => null,
  };
}

int? aiProviderStrictProbeMaxTokensForConfig(
  AiProviderType providerType, {
  String? baseUrl,
  String? model,
}) {
  final effectiveProviderType = resolveEffectiveAiProviderType(
    providerType,
    baseUrl: baseUrl,
  );
  return aiProviderStrictProbeMaxTokens(effectiveProviderType);
}

AiHttpRequest buildAiConversationRequest({
  required AiProviderType providerType,
  required String baseUrl,
  required String model,
  required String apiKey,
  required String systemPrompt,
  required String userPrompt,
  required bool useStructuredOutput,
  int? maxTokens,
  bool stream = false,
  Duration? timeout,
}) {
  final normalizedBaseUrl = normalizeAiBaseUrl(baseUrl);
  switch (providerType) {
    case AiProviderType.openai:
    case AiProviderType.openaiCompatible:
    case AiProviderType.cloudflareWorkersAi:
      final body = <String, dynamic>{
        'model': model,
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
      if (maxTokens != null) {
        body['max_tokens'] = maxTokens;
      }
      if (useStructuredOutput &&
          aiProviderSupportsResponseFormat(providerType)) {
        body['response_format'] = const {
          'type': 'json_object',
        };
      }
      if (stream) {
        body['stream'] = true;
      }
      return AiHttpRequest(
        method: 'POST',
        uri: Uri.parse('$normalizedBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': stream ? 'text/event-stream' : 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
        timeout: timeout,
      );
    case AiProviderType.anthropic:
      return AiHttpRequest(
        method: 'POST',
        uri: Uri.parse('$normalizedBaseUrl/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'max_tokens': 1200,
          'system': systemPrompt,
          'messages': [
            {
              'role': 'user',
              'content': userPrompt,
            },
          ],
        }),
        timeout: timeout,
      );
  }
}

bool looksLikeStructuredOutputUnsupportedResponse(AiHttpResponse response) {
  if (response.statusCode < 400 || response.statusCode >= 500) {
    return false;
  }
  final message = extractAiErrorMessage(response.body)?.toLowerCase() ??
      response.body.toLowerCase();
  return message.contains('response_format') ||
      message.contains('json_schema') ||
      message.contains('json_object') ||
      message.contains('structured output');
}

bool shouldRetryOpenAiCompatibleWithStreamResponse({
  required AiProviderType providerType,
  required AiHttpResponse response,
}) {
  if (providerType != AiProviderType.openaiCompatible &&
      providerType != AiProviderType.cloudflareWorkersAi) {
    return false;
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return false;
  }
  final decoded = tryDecodeAiJson(response.body);
  if (decoded is! Map<String, dynamic>) {
    return false;
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    return false;
  }
  final firstChoice = choices.first;
  if (firstChoice is! Map) {
    return false;
  }
  final message = firstChoice['message'];
  if (message is! Map) {
    return false;
  }
  final finishReason = firstChoice['finish_reason'];
  final normalizedFinishReason =
      finishReason is String ? finishReason.trim().toLowerCase() : null;
  if (normalizedFinishReason == 'length' ||
      normalizedFinishReason == 'max_tokens') {
    return false;
  }
  final content = tryExtractAiResponseTextContent(
    providerType: providerType,
    decoded: decoded,
  );
  return content == null;
}

String? extractAiErrorMessage(String rawBody) {
  final decoded = tryDecodeAiJson(rawBody);
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

String? tryExtractAiResponseTextContent({
  required AiProviderType providerType,
  required Map<String, dynamic> decoded,
}) {
  switch (providerType) {
    case AiProviderType.openai:
    case AiProviderType.openaiCompatible:
    case AiProviderType.cloudflareWorkersAi:
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        return null;
      }
      final firstChoice = choices.first;
      if (firstChoice is! Map) {
        return null;
      }
      final message = firstChoice['message'];
      if (message is! Map) {
        return null;
      }
      final buffer = StringBuffer();
      _appendTextContent(message['content'], buffer);
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    case AiProviderType.anthropic:
      final content = decoded['content'];
      if (content is! List || content.isEmpty) {
        return null;
      }
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['type'] == 'text' && item['text'] is String) {
          buffer.writeln(item['text'] as String);
        }
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
  }
}

String? decodeSseToOpenAiChatCompletionBody(String rawBody) {
  final lines = LineSplitter.split(rawBody);
  final contentBuffer = StringBuffer();
  String? role;
  String? finishReason;
  String? model;
  int? created;
  String? id;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (!line.startsWith('data:')) {
      continue;
    }
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') {
      continue;
    }
    final decoded = tryDecodeAiJson(payload);
    if (decoded is! Map<String, dynamic>) {
      continue;
    }
    id ??= decoded['id'] as String?;
    model ??= decoded['model'] as String?;
    created ??= decoded['created'] as int?;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      continue;
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      continue;
    }
    final delta = firstChoice['delta'];
    if (delta is Map) {
      role ??= delta['role'] as String?;
      final deltaContent = delta['content'];
      if (deltaContent is String) {
        contentBuffer.write(deltaContent);
      } else {
        _appendTextContent(deltaContent, contentBuffer);
      }
    }
    final chunkFinishReason = firstChoice['finish_reason'];
    if (chunkFinishReason is String && chunkFinishReason.trim().isNotEmpty) {
      finishReason = chunkFinishReason;
    }
  }

  if (contentBuffer.isEmpty && role == null && finishReason == null) {
    return null;
  }

  return jsonEncode({
    'id': id ?? 'sse-decoded-response',
    'object': 'chat.completion',
    'created': created ?? 0,
    'model': model ?? 'unknown',
    'choices': [
      {
        'index': 0,
        'message': {
          'role': role ?? 'assistant',
          'content': contentBuffer.toString(),
        },
        'finish_reason': finishReason ?? 'stop',
      },
    ],
  });
}

Map<String, dynamic>? extractAiJsonObject(String text) {
  final direct = tryDecodeAiJson(text);
  if (direct is Map<String, dynamic>) {
    return direct;
  }

  final fencedMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fencedMatch != null) {
    final fenced = tryDecodeAiJson(fencedMatch.group(1)!.trim());
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
        final decoded = tryDecodeAiJson(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return null;
      }
    }
  }
  return null;
}

Object? tryDecodeAiJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

class AiConnectionTester {
  AiConnectionTester({
    AiHttpTransport? transport,
  }) : _transport = transport ?? HttpClientAiHttpTransport();

  static const String _probeSystemPrompt = '只返回一个 JSON object，不要输出任何额外文字。';
  static const String _probeUserPrompt = '请返回 {"ok":true}。';

  final AiHttpTransport _transport;

  Future<AiConnectionTestResult> testConnection({
    required AiProviderType providerType,
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    final normalizedBaseUrl = normalizeAiBaseUrl(baseUrl);
    if (!isValidAiBaseUrl(normalizedBaseUrl)) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.unreachable,
        message: 'Base URL 格式不正确，请检查完整的 http(s) 地址。',
      );
    }

    final candidateBaseUrls = _candidateBaseUrls(normalizedBaseUrl);
    AiConnectionTestResult? fallbackInvalidResponse;
    for (final candidateBaseUrl in candidateBaseUrls) {
      final attempt = await _attemptConnection(
        providerType: providerType,
        baseUrl: candidateBaseUrl,
        model: model,
        apiKey: apiKey,
      );
      if (attempt.status == AiConnectionStatus.invalidResponse) {
        fallbackInvalidResponse ??= attempt;
        continue;
      }
      return attempt;
    }

    final result = fallbackInvalidResponse ??
        const AiConnectionTestResult(
          status: AiConnectionStatus.unreachable,
          message: '连接失败，请检查网络和服务地址。',
        );
    return result;
  }

  Future<AiConnectionTestResult> _attemptConnection({
    required AiProviderType providerType,
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    final profile = resolveAiProviderRuntimeProfile(
      providerType: providerType,
      baseUrl: baseUrl,
    );

    if (profile.modelDiscoveryPolicy == AiModelDiscoveryPolicy.skip) {
      return _probeStrictStructuredOutput(
        profile: profile,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
    }

    try {
      final request = _buildModelDiscoveryRequest(
        providerType: providerType,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      final response = await _transport.send(request);

      final discoveryOutcome = _evaluateModelDiscovery(
        profile: profile,
        response: response,
        model: model,
      );
      if (discoveryOutcome.result != null) {
        return discoveryOutcome.result!;
      }

      return _probeStrictStructuredOutput(
        profile: profile,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
    } on TimeoutException {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.timeout,
        message: '连接超时，请稍后重试。',
      );
    } on SocketException {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.unreachable,
        message: '服务地址不可达，请检查 Base URL。',
      );
    } catch (_) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.unreachable,
        message: '连接失败，请检查网络和服务地址。',
      );
    }
  }

  AiHttpRequest _buildModelDiscoveryRequest({
    required AiProviderType providerType,
    required String baseUrl,
    required String apiKey,
  }) {
    return switch (providerType) {
      AiProviderType.openai ||
      AiProviderType.openaiCompatible ||
      AiProviderType.cloudflareWorkersAi =>
        AiHttpRequest(
          method: 'GET',
          uri: Uri.parse('$baseUrl/models'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
        ),
      AiProviderType.anthropic => AiHttpRequest(
          method: 'GET',
          uri: Uri.parse('$baseUrl/models'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Accept': 'application/json',
          },
        ),
    };
  }

  _ModelDiscoveryOutcome _evaluateModelDiscovery({
    required AiProviderRuntimeProfile profile,
    required AiHttpResponse response,
    required String model,
  }) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.invalidKey,
          message: 'API Key 无效或没有访问权限。',
        ),
      );
    }
    if (response.statusCode == 404 &&
        profile.modelDiscoveryPolicy == AiModelDiscoveryPolicy.optional) {
      return const _ModelDiscoveryOutcome(shouldProbe: true);
    }
    if (response.statusCode == 405 &&
        profile.modelDiscoveryPolicy ==
            AiModelDiscoveryPolicy.fallbackOnMethodNotAllowed) {
      return const _ModelDiscoveryOutcome(shouldProbe: true);
    }
    if (response.statusCode == 404) {
      return const _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.unreachable,
          message: '服务地址不可达，请确认接口地址。',
        ),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.unreachable,
          message: '连接失败，服务返回 ${response.statusCode}。',
        ),
      );
    }

    final decoded = tryDecodeAiJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      return _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.invalidResponse,
          message: _buildInvalidResponseMessage(
            baseMessage: 'AI 端返回不是合法 JSON。',
            responseBody: response.body,
          ),
        ),
      );
    }
    final items = decoded['data'];
    if (items is! List) {
      return _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.invalidResponse,
          message: _buildInvalidResponseMessage(
            baseMessage: 'AI 端返回未包含模型列表。',
            responseBody: response.body,
          ),
        ),
      );
    }

    final modelIds = items
        .whereType<Map>()
        .map((item) => item['id'])
        .whereType<String>()
        .toSet();
    if (!modelIds.contains(model)) {
      return const _ModelDiscoveryOutcome(
        result: AiConnectionTestResult(
          status: AiConnectionStatus.modelUnavailable,
          message: '当前模型不可用，请检查模型名称。',
        ),
      );
    }
    return const _ModelDiscoveryOutcome(shouldProbe: true);
  }

  Future<AiConnectionTestResult> _probeStrictStructuredOutput({
    required AiProviderRuntimeProfile profile,
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    var useStructuredOutput = aiProviderSupportsResponseFormat(
      profile.providerType,
    );
    var hasRetriedTransientFailure = false;
    var useStream = false;

    while (true) {
      AiHttpResponse response;
      final request = buildAiConversationRequest(
        providerType: profile.providerType,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        systemPrompt: _probeSystemPrompt,
        userPrompt: _probeUserPrompt,
        useStructuredOutput: useStructuredOutput,
        maxTokens: aiProviderStrictProbeMaxTokensForConfig(
          profile.providerType,
          baseUrl: baseUrl,
          model: model,
        ),
        stream: useStream,
        timeout: profile.strictProbeTimeout,
      );
      try {
        response = await _transport.send(request);
      } on TimeoutException {
        if (!hasRetriedTransientFailure) {
          hasRetriedTransientFailure = true;
          continue;
        }
        return const AiConnectionTestResult(
          status: AiConnectionStatus.timeout,
          message: '基础连接已通过，但结构化生成探活超时，请稍后重试或更换模型。',
        );
      }

      if (useStructuredOutput &&
          aiProviderSupportsResponseFormat(profile.providerType) &&
          looksLikeStructuredOutputUnsupportedResponse(response)) {
        useStructuredOutput = false;
        continue;
      }

      if (_isRetryableProbeResponse(response) && !hasRetriedTransientFailure) {
        hasRetriedTransientFailure = true;
        continue;
      }

      if (!useStream &&
          shouldRetryOpenAiCompatibleWithStreamResponse(
            providerType: profile.providerType,
            response: response,
          )) {
        useStream = true;
        continue;
      }

      return _parseStrictProbeResponse(
        providerType: profile.providerType,
        response: response,
      );
    }
  }

  AiConnectionTestResult _parseStrictProbeResponse({
    required AiProviderType providerType,
    required AiHttpResponse response,
  }) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.invalidKey,
        message: 'API Key 无效或没有访问权限。',
      );
    }
    if (response.statusCode == 404) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.unreachable,
        message: '服务地址不可达，请确认接口地址。',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AiConnectionTestResult(
        status: AiConnectionStatus.unreachable,
        message: '连接失败，服务返回 ${response.statusCode}。',
      );
    }

    final decoded = tryDecodeAiJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      return AiConnectionTestResult(
        status: AiConnectionStatus.invalidResponse,
        message: _buildInvalidResponseMessage(
          baseMessage: 'AI 端返回不是合法 JSON。',
          responseBody: response.body,
        ),
      );
    }

    final content = tryExtractAiResponseTextContent(
      providerType: providerType,
      decoded: decoded,
    );
    if (content == null) {
      return AiConnectionTestResult(
        status: AiConnectionStatus.invalidResponse,
        message: _buildInvalidResponseMessage(
          baseMessage: 'AI 端返回未包含文本内容。',
          responseBody: response.body,
        ),
      );
    }
    if (extractAiJsonObject(content) == null) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.invalidResponse,
        message: '连接成功但当前服务无法稳定返回结构化 JSON，暂不可用于 AI 总览生成。',
      );
    }

    return const AiConnectionTestResult(
      status: AiConnectionStatus.success,
      message: '基础连接成功，当前服务可返回结构化 JSON。正式生成较长报告仍可能受模型负载、上下文长度和超时影响。',
    );
  }

  List<String> _candidateBaseUrls(String normalizedBaseUrl) {
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null) {
      return [normalizedBaseUrl];
    }
    final hasNoPath = uri.path.isEmpty || uri.path == '/';
    if (!hasNoPath) {
      return [normalizedBaseUrl];
    }
    return [
      normalizedBaseUrl,
      '$normalizedBaseUrl/v1',
    ];
  }

  bool _isRetryableProbeResponse(AiHttpResponse response) {
    return response.statusCode == 408 ||
        response.statusCode == 425 ||
        response.statusCode == 429 ||
        response.statusCode == 500 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504;
  }

  String _previewResponseBody(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'response body is empty';
    }
    if (trimmed.length <= 600) {
      return trimmed;
    }
    return '${trimmed.substring(0, 600)}…';
  }

  String _buildInvalidResponseMessage({
    required String baseMessage,
    required String responseBody,
  }) {
    final preview = _previewResponseBody(responseBody);
    if (preview == 'response body is empty') {
      return baseMessage;
    }
    return '$baseMessage AI 端返回：$preview';
  }
}

class _ModelDiscoveryOutcome {
  const _ModelDiscoveryOutcome({
    this.result,
    this.shouldProbe = false,
  });

  final AiConnectionTestResult? result;
  final bool shouldProbe;
}

bool looksLikeCloudflareWorkersAiUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) {
    return false;
  }
  return uri.host == 'api.cloudflare.com' &&
      uri.path.contains('/client/v4/accounts/') &&
      uri.path.endsWith('/ai/v1');
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
