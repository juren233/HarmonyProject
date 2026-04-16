import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_provider_config.dart';

void main() {
  test('http transport writes request body as utf8', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    late String receivedBody;
    final responseFuture = server.first.then((request) async {
      receivedBody = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = 200
        ..write('{}');
      await request.response.close();
    });

    final transport = HttpClientAiHttpTransport();
    await transport.send(
      AiHttpRequest(
        method: 'POST',
        uri: Uri.parse('http://${server.address.host}:${server.port}/chat'),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': '你是宠物日常照护助手。',
        }),
      ),
    );

    await responseFuture;
    expect(receivedBody, contains('你是宠物日常照护助手'));
  });

  test('openai probe succeeds when configured model is listed', () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://api.openai.com/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'gpt-5.4'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://api.openai.com/v1/chat/completions' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(
      requestedUrls,
      containsAll([
        'https://api.openai.com/v1/models',
        'https://api.openai.com/v1/chat/completions',
      ]),
    );
  });

  test('returns invalid key when provider rejects credentials', () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async => const AiHttpResponse(
          statusCode: 401,
          body: '{"error":"unauthorized"}',
        ),
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.anthropic,
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-sonnet-4-20250514',
      apiKey: 'bad-key',
    );

    expect(result.status, AiConnectionStatus.invalidKey);
  });

  test(
      'returns model unavailable when openai model list does not include target',
      () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'data': [
              {'id': 'gpt-4.1'},
            ],
          }),
        ),
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openai,
      baseUrl: 'https://llm.example.com/v1',
      model: 'petnote-ai',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.modelUnavailable);
  });

  test('returns invalid response when provider responds with malformed body',
      () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async => const AiHttpResponse(
          statusCode: 200,
          body: '{"unexpected":true}',
        ),
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5.4',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.invalidResponse);
  });

  test(
      'returns invalid response instead of unreachable when endpoint serves HTML',
      () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async => const AiHttpResponse(
          statusCode: 200,
          body: '<!doctype html><html><body>gateway page</body></html>',
        ),
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://yybb.codes',
      model: 'gpt-5.4',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.invalidResponse);
  });

  test('retries with /v1 when root base url serves a non-api HTML page',
      () async {
    final requestedUrls = <String>[];
    final requestedBodies = <Map<String, dynamic>>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://yybb.codes/models') {
            return const AiHttpResponse(
              statusCode: 200,
              body: '<!doctype html><html><body>gateway page</body></html>',
            );
          }
          if (request.uri.toString() == 'https://yybb.codes/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'gpt-5.4'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
              'https://yybb.codes/v1/chat/completions') {
            final body = jsonDecode(request.body!) as Map<String, dynamic>;
            requestedBodies.add(body);
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://yybb.codes',
      model: 'gpt-5.4',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(
      requestedUrls,
      containsAll([
        'https://yybb.codes/models',
        'https://yybb.codes/v1/models',
        'https://yybb.codes/v1/chat/completions',
      ]),
    );
    expect(requestedBodies.single['response_format'], isNotNull);
  });

  test(
      'cloudflare openai-compatible probe falls back to chat completions when models endpoint is unsupported',
      () async {
    final requestedUrls = <String>[];
    final requestedMethods = <String>[];
    final requestedBodies = <Map<String, dynamic>>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          requestedMethods.add(request.method);
          if (request.uri.toString() ==
                  'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/models' &&
              request.method == 'GET') {
            return const AiHttpResponse(
              statusCode: 405,
              body:
                  '{"result":null,"success":false,"errors":[{"code":7001,"message":"GET not supported for requested URI."}],"messages":[]}',
            );
          }
          if (request.uri.toString() ==
                  'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/chat/completions' &&
              request.method == 'POST') {
            requestedBodies
                .add(jsonDecode(request.body!) as Map<String, dynamic>);
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'id': 'id-1',
                'object': 'chat.completion',
                'created': 1775726387,
                'model': '@cf/google/gemma-4-26b-a4b-it',
                'choices': [
                  {
                    'index': 0,
                    'finish_reason': 'stop',
                    'message': {
                      'role': 'assistant',
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl:
          'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1',
      model: '@cf/google/gemma-4-26b-a4b-it',
      apiKey: 'cf-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(result.message, contains('基础连接成功'));
    expect(result.message, contains('正式生成较长报告'));
    expect(
      requestedUrls,
      containsAll([
        'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/models',
        'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/chat/completions',
      ]),
    );
    expect(requestedMethods, containsAll(['GET', 'POST']));
    expect(requestedBodies.single['response_format'], isNotNull);
  });

  test(
      'cloudflare openai-compatible probe retries after a transient chat completion overload',
      () async {
    final requestedUrls = <String>[];
    var chatAttempts = 0;
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() ==
                  'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/models' &&
              request.method == 'GET') {
            return const AiHttpResponse(
              statusCode: 405,
              body:
                  '{"result":null,"success":false,"errors":[{"code":7001,"message":"GET not supported for requested URI."}],"messages":[]}',
            );
          }
          if (request.uri.toString() ==
                  'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1/chat/completions' &&
              request.method == 'POST') {
            chatAttempts += 1;
            if (chatAttempts == 1) {
              return const AiHttpResponse(
                statusCode: 503,
                body:
                    '{"errors":[{"message":"AiError: Max retries exhausted","code":3050}],"success":false}',
              );
            }
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl:
          'https://api.cloudflare.com/client/v4/accounts/test-account/ai/v1',
      model: '@cf/google/gemma-4-26b-a4b-it',
      apiKey: 'cf-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(chatAttempts, 2);
    expect(
      requestedUrls.where(
        (url) => url.endsWith('/chat/completions'),
      ),
      hasLength(2),
    );
  });

  test(
      'openai-compatible probe rejects providers that cannot return structured json for overview generation',
      () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://llm.example.com/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'petnote-ai'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://llm.example.com/v1/chat/completions' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '这是普通文本，不是 JSON。',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://llm.example.com/v1',
      model: 'petnote-ai',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.invalidResponse);
    expect(result.message, contains('结构化 JSON'));
    expect(
      requestedUrls,
      containsAll([
        'https://llm.example.com/v1/models',
        'https://llm.example.com/v1/chat/completions',
      ]),
    );
  });

  test('bigmodel profile stops at model discovery when target model is missing',
      () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() ==
              'https://open.bigmodel.cn/api/paas/v4/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'glm-4.7'},
                  {'id': 'glm-5.1'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
              'https://open.bigmodel.cn/api/paas/v4/chat/completions') {
            fail('chat probe should not run when target model is missing');
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-4.7-flashx',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.modelUnavailable);
    expect(result.message, contains('模型名称'));
    expect(
      requestedUrls,
      ['https://open.bigmodel.cn/api/paas/v4/models'],
    );
  });

  test('bigmodel profile preserves timeout when strict chat probe times out',
      () async {
    final requestedUrls = <String>[];
    var chatAttempts = 0;
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() ==
              'https://open.bigmodel.cn/api/paas/v4/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'glm-5.1'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://open.bigmodel.cn/api/paas/v4/chat/completions' &&
              request.method == 'POST') {
            chatAttempts += 1;
            throw TimeoutException('probe timeout');
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-5.1',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.timeout);
    expect(result.message, contains('结构化'));
    expect(result.message, contains('超时'));
    expect(chatAttempts, 2);
    expect(
      requestedUrls,
      containsAll([
        'https://open.bigmodel.cn/api/paas/v4/models',
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      ]),
    );
  });

  test(
      'openai-compatible probe can still succeed when models endpoint is unavailable but chat completions works',
      () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://relay.example.com/v1/models') {
            return const AiHttpResponse(
              statusCode: 404,
              body: '{"error":{"message":"not found"}}',
            );
          }
          if (request.uri.toString() ==
                  'https://relay.example.com/v1/chat/completions' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://relay.example.com/v1',
      model: 'petnote-ai',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(
      requestedUrls,
      containsAll([
        'https://relay.example.com/v1/models',
        'https://relay.example.com/v1/chat/completions',
      ]),
    );
  });

  test('returns a clear message when base url is malformed', () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async =>
            throw StateError('transport should not be called'),
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: '{"broken":true}',
      model: 'petnote-ai',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.unreachable);
    expect(result.message, contains('Base URL'));
  });

  test(
      'openai-compatible probe retries without response_format when provider does not support it',
      () async {
    final requestedBodies = <Map<String, dynamic>>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          if (request.uri.toString() == 'https://llm.example.com/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'petnote-ai'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://llm.example.com/v1/chat/completions' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body!) as Map<String, dynamic>;
            requestedBodies.add(body);
            if (requestedBodies.length == 1) {
              return const AiHttpResponse(
                statusCode: 400,
                body:
                    '{"error":{"message":"response_format json_object is not supported"}}',
              );
            }
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '{"ok":true}',
                    },
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openaiCompatible,
      baseUrl: 'https://llm.example.com/v1',
      model: 'petnote-ai',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(requestedBodies, hasLength(2));
    expect(requestedBodies.first['response_format'], isNotNull);
    expect(requestedBodies.last.containsKey('response_format'), isFalse);
  });

  test(
      'anthropic strict probe succeeds only when messages endpoint returns parseable json',
      () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://api.anthropic.com/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'claude-sonnet-4-20250514'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://api.anthropic.com/v1/messages' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'content': [
                  {
                    'type': 'text',
                    'text': '{"ok":true}',
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.anthropic,
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-sonnet-4-20250514',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.success);
    expect(
      requestedUrls,
      containsAll([
        'https://api.anthropic.com/v1/models',
        'https://api.anthropic.com/v1/messages',
      ]),
    );
  });

  test(
      'anthropic strict probe returns invalid response when messages endpoint does not return json content',
      () async {
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          if (request.uri.toString() == 'https://api.anthropic.com/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'claude-sonnet-4-20250514'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://api.anthropic.com/v1/messages' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'content': [
                  {
                    'type': 'text',
                    'text': '这不是 JSON',
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.anthropic,
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-sonnet-4-20250514',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.invalidResponse);
    expect(result.message, contains('结构化 JSON'));
  });

  test(
      'openai probe rejects providers that list the model but return no message content',
      () async {
    final requestedUrls = <String>[];
    final tester = AiConnectionTester(
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          requestedUrls.add(request.uri.toString());
          if (request.uri.toString() == 'https://yybb.codes/v1/models') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'data': [
                  {'id': 'gpt-5.4'},
                ],
              }),
            );
          }
          if (request.uri.toString() ==
                  'https://yybb.codes/v1/chat/completions' &&
              request.method == 'POST') {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
            );
          }
          return const AiHttpResponse(statusCode: 404, body: '{}');
        },
      ),
    );

    final result = await tester.testConnection(
      providerType: AiProviderType.openai,
      baseUrl: 'https://yybb.codes/v1',
      model: 'gpt-5.4',
      apiKey: 'sk-test',
    );

    expect(result.status, AiConnectionStatus.invalidResponse);
    expect(result.message, contains('未返回文本内容'));
    expect(
      requestedUrls,
      containsAll([
        'https://yybb.codes/v1/models',
        'https://yybb.codes/v1/chat/completions',
      ]),
    );
  });
}

class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport({required this.handler});

  final Future<AiHttpResponse> Function(AiHttpRequest request) handler;

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) => handler(request);
}
