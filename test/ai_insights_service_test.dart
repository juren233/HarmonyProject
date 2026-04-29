import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('generates care report from openai-compatible chat completions',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare',
        displayName: 'Cloudflare',
        providerType: AiProviderType.openaiCompatible,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path.endsWith('/chat/completions'), isTrue);
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          expect(body['model'], '@cf/google/gemma-4-26b-a4b-it');
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(
      AiGenerationContext(
        title: '最近 7 天的总结',
        rangeLabel: '最近 7 天',
        rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: [
          Pet(
            id: 'pet-1',
            name: 'Mochi',
            avatarText: 'MO',
            type: PetType.cat,
            breed: '英短',
            sex: '母',
            birthday: '2024-02-12',
            ageLabel: '2岁',
            weightKg: 4.2,
            neuterStatus: PetNeuterStatus.neutered,
            feedingPreferences: '主粮+冻干',
            allergies: '鸡肉敏感',
            note: '偶尔紧张',
          ),
        ],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(report.overallScore, 84);
    expect(report.statusLabel, '状态还行');
    expect(report.oneLineSummary, contains('整体稳定'));
    expect(report.recommendationRankings, hasLength(5));
    expect(report.recommendationRankings.first.petNames, contains('Mochi'));
    expect(report.overallScore, inInclusiveRange(0, 100));
    expect(report.recommendationRankings.first.kind, 'action');
    expect(report.perPetReports.single.petName, 'Mochi');
    expect(report.perPetReports.single.score, 82);
    expect(report.perPetReports.single.statusLabel, '状态还行');
    expect(report.perPetReports.single.whyThisScore, isNotEmpty);
    expect(report.perPetReports.single.topPriority, isNotEmpty);
    expect(report.perPetReports.single.missedItems, isNotEmpty);
    expect(report.perPetReports.single.followUpPlan, isNotEmpty);
    expect(report.perPetReports.single.recentChanges, isEmpty);
  });

  test('fails when per-pet ai summary misses required four sections', () {
    expect(
      () => AiCareReport.fromJson(
        {
          'overallScore': 84,
          'oneLineSummary': '整体稳定。',
          'executiveSummary': '本周期整体稳定，仍需继续跟进。',
          'overallAssessment': ['整体执行稳定。'],
          'keyFindings': ['近期变化不大。'],
          'trendAnalysis': ['趋势平稳。'],
          'riskAssessment': ['当前风险可控。'],
          'priorityActions': ['继续跟进。'],
          'recommendationRankings': [
            {
              'rank': 1,
              'kind': 'action',
              'petIds': ['pet-1'],
              'petNames': ['Mochi'],
              'title': '继续观察',
              'summary': '需要持续跟进。',
              'suggestedAction': '继续记录。',
            },
          ],
          'perPetReports': [
            {
              'petId': 'pet-1',
              'petName': 'Mochi',
              'score': 82,
              'whyThisScore': ['近期有护理动作，但闭环还不够完整。'],
              'topPriority': ['先补上耳道复查闭环。'],
              'missedItems': ['缺少连续观察记录。'],
            },
          ],
        },
        scorecard: const AiCareScorecard(
          overallScore: 84,
          overallScoreLabel: '稳定',
          scoreConfidence: AiScoreConfidence.medium,
          scoreBreakdown: [],
          scoreReasons: [],
          riskCandidates: [],
          dataQualityNotes: [],
          petScorecards: [
            AiPetCareScorecard(
              petId: 'pet-1',
              petName: 'Mochi',
              overallScore: 82,
              overallScoreLabel: '状态还行',
              scoreConfidence: AiScoreConfidence.medium,
              scoreBreakdown: [],
              scoreReasons: [],
              riskCandidates: [],
              dataQualityNotes: [],
              recentEventTitles: [],
            ),
          ],
          totalTodos: 0,
          totalReminders: 0,
          totalRecords: 0,
        ),
      ),
      throwsA(
        isA<AiGenerationException>().having(
          (error) => error.message,
          'message',
          contains('缺少 followUpPlan'),
        ),
      ),
    );
  });

  test(
      'falls back to prompt-only mode when compatible provider rejects structured output parameter',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-compatible-fallback',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-compatible-fallback', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          if (requestBodies.length == 1) {
            expect(body['response_format'], isNotNull);
            return const AiHttpResponse(
              statusCode: 400,
              body: '{"error":{"message":"response_format unsupported"}}',
            );
          }
          expect(body.containsKey('response_format'), isFalse);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '好的，以下是结果：```json ${jsonEncode(_careReportResponseJson(petId: "pet-1", petName: "Mochi", executiveSummary: "本周期稳定。"))} ```',
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(
      AiGenerationContext(
        title: '最近 7 天的总结',
        rangeLabel: '最近 7 天',
        rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: const [],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(requestBodies, hasLength(2));
    expect(report.oneLineSummary, '本周期稳定。');
    expect(report.recommendationRankings, hasLength(5));
  });

  test(
      'keeps prompt-only mode when stream fallback runs after response_format rejection',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-compatible-prompt-only-stream-fallback',
        displayName: 'Compatible Stream Fallback',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
      'cfg-compatible-prompt-only-stream-fallback',
      'sk-test-123',
    );

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          if (requestBodies.length == 1) {
            expect(body['response_format'], isNotNull);
            return const AiHttpResponse(
              statusCode: 400,
              body: '{"error":{"message":"response_format unsupported"}}',
            );
          }
          if (requestBodies.length == 2) {
            expect(body.containsKey('response_format'), isFalse);
            expect(body['stream'], isNot(true));
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
          expect(body['stream'], isTrue);
          expect(body.containsKey('response_format'), isFalse);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '降级后流式兜底仍保持普通提示词模式。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '降级后流式兜底仍保持普通提示词模式。');
    expect(requestBodies, hasLength(3));
    expect(requestBodies.first['response_format'], isNotNull);
    expect(requestBodies[1].containsKey('response_format'), isFalse);
    expect(requestBodies.last.containsKey('response_format'), isFalse);
    expect(requestBodies.last['stream'], isTrue);
  });

  test('extracts openai-compatible content when message content is an object',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-content-object',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-content-object', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': {
                    'text': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Compatible',
                        executiveSummary: '整体稳定。',
                      ),
                    ),
                  },
                },
              },
            ],
          }),
        ),
      ),
    );

    final report = await service.generateCareReport(
      AiGenerationContext(
        title: '最近 7 天的总结',
        rangeLabel: '最近 7 天',
        rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: const [],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(report.oneLineSummary, '整体稳定。');
    expect(
      report.recommendationRankings.map((item) => item.suggestedAction),
      contains('本周补一次耳道观察'),
    );
  });

  test('extracts openai-compatible content from sse chat completion chunks',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-content-sse',
        displayName: 'Compatible SSE',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-content-sse', 'sk-test-123');

    final responseJson = jsonEncode(
      _careReportResponseJson(
        petId: 'pet-1',
        petName: 'Mochi',
        executiveSummary: 'SSE 兼容层正文已成功聚合。',
      ),
    );
    final escapedResponseJson =
        responseJson.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final sseBody =
        'data: {"id":"resp_test","object":"chat.completion.chunk","created":1776568688,"model":"petnote-ai","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_test","object":"chat.completion.chunk","created":1776568688,"model":"petnote-ai","choices":[{"index":0,"delta":{"content":"$escapedResponseJson"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_test","object":"chat.completion.chunk","created":1776568688,"model":"petnote-ai","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n';

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: decodeSseToOpenAiChatCompletionBody(sseBody) ?? sseBody,
        ),
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, 'SSE 兼容层正文已成功聚合。');
    expect(report.perPetReports.single.petName, 'Mochi');
  });

  test(
      'falls back to stream when openai-compatible non-stream response has no content',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-compatible-stream-fallback',
        displayName: 'Compatible Stream Fallback',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://hk.yybb.codes/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-compatible-stream-fallback', 'sk-test-123');

    final responseJson = jsonEncode(
      _careReportResponseJson(
        petId: 'pet-1',
        petName: 'Mochi',
        executiveSummary: '非流式空正文后已自动切换流式生成。',
      ),
    );
    final escapedResponseJson =
        responseJson.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final sseBody =
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"gpt-5.4","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"gpt-5.4","choices":[{"index":0,"delta":{"content":"$escapedResponseJson"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"gpt-5.4","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n';

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          if (requestBodies.length == 1) {
            expect(body['stream'], isNot(true));
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'message': {
                      'role': 'assistant',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
            );
          }
          expect(body['stream'], isTrue);
          expect(body['response_format'], isNotNull);
          return AiHttpResponse(
            statusCode: 200,
            body: decodeSseToOpenAiChatCompletionBody(sseBody) ?? sseBody,
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '非流式空正文后已自动切换流式生成。');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['response_format'], isNotNull);
    expect(requestBodies.last['stream'], isTrue);
  });

  test(
      'falls back to stream when cloudflare workers ai non-stream response has no content',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-stream-fallback',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/meta/llama-3.1-8b-instruct-fast',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
        'cfg-cloudflare-stream-fallback', 'cf-test-token');

    final responseJson = jsonEncode(
      _careReportResponseJson(
        petId: 'pet-1',
        petName: 'Mochi',
        executiveSummary: 'Cloudflare 非流式空正文后已自动切换流式生成。',
      ),
    );
    final escapedResponseJson =
        responseJson.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final sseBody =
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"@cf/meta/llama-3.1-8b-instruct-fast","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"@cf/meta/llama-3.1-8b-instruct-fast","choices":[{"index":0,"delta":{"content":"$escapedResponseJson"},"finish_reason":null}]}\n\n'
        'data: {"id":"resp_stream","object":"chat.completion.chunk","created":1776568688,"model":"@cf/meta/llama-3.1-8b-instruct-fast","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n';

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          if (requestBodies.length == 1) {
            expect(body['stream'], isNot(true));
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'message': {
                      'role': 'assistant',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
            );
          }
          expect(body['stream'], isTrue);
          expect(body['response_format'], isNotNull);
          return AiHttpResponse(
            statusCode: 200,
            body: decodeSseToOpenAiChatCompletionBody(sseBody) ?? sseBody,
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, 'Cloudflare 非流式空正文后已自动切换流式生成。');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['response_format'], isNotNull);
    expect(requestBodies.last['stream'], isTrue);
  });

  test('uses a longer timeout for remote generation requests', () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final recordedTimeouts = <Duration?>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-timeout-check',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-timeout-check', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          recordedTimeouts.add(request.timeout);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Compatible',
                        executiveSummary: '整体稳定。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    await service.generateCareReport(
      AiGenerationContext(
        title: '最近 7 天的总结',
        rangeLabel: '最近 7 天',
        rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: const [],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(recordedTimeouts, isNotEmpty);
    expect(recordedTimeouts.first, const Duration(seconds: 45));
  });

  test('cloudflare workers ai uses an extended generation timeout', () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final recordedTimeouts = <Duration?>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-timeout-check',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare-timeout-check', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          recordedTimeouts.add(request.timeout);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: 'Cloudflare 使用加长超时预算。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, 'Cloudflare 使用加长超时预算。');
    expect(recordedTimeouts, isNotEmpty);
    expect(recordedTimeouts.first, const Duration(seconds: 90));
  });

  test(
      'legacy cloudflare-compatible config also uses an extended generation timeout',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final recordedTimeouts = <Duration?>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-compatible-timeout-check',
        displayName: 'Cloudflare Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
      'cfg-cloudflare-compatible-timeout-check',
      'cf-test-token',
    );

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          recordedTimeouts.add(request.timeout);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '旧兼容 Cloudflare 也使用加长超时预算。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '旧兼容 Cloudflare 也使用加长超时预算。');
    expect(recordedTimeouts, isNotEmpty);
    expect(recordedTimeouts.first, const Duration(seconds: 90));
  });

  test('cloudflare workers ai generation request includes explicit max_tokens',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-workers-ai',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/meta/llama-3.1-8b-instruct-fast',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare-workers-ai', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: 'Cloudflare 适配已生效。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(
      AiGenerationContext(
        title: '最近 7 天的总结',
        rangeLabel: '最近 7 天',
        rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: const [],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(report.oneLineSummary, 'Cloudflare 适配已生效。');
    expect(requestBodies, isNotEmpty);
    expect(requestBodies.single['max_tokens'], greaterThanOrEqualTo(4000));
    expect(requestBodies.single['response_format'], isNotNull);
  });

  test('cloudflare gemma4 generation request uses full max_tokens budget',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-gemma4-tokens',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare-gemma4-tokens', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: 'Gemma4 使用完整输出预算。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, 'Gemma4 使用完整输出预算。');
    expect(requestBodies, isNotEmpty);
    expect(requestBodies.single['max_tokens'], 4096);
    expect(requestBodies.single['response_format'], isNotNull);
  });

  test(
      'legacy cloudflare openai-compatible gemma4 config uses full max_tokens budget',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final requestBodies = <Map<String, dynamic>>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-compatible-gemma4-tokens',
        displayName: 'Cloudflare Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
      'cfg-cloudflare-compatible-gemma4-tokens',
      'cf-test-token',
    );

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          requestBodies.add(body);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '旧兼容配置也使用完整输出预算。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '旧兼容配置也使用完整输出预算。');
    expect(requestBodies, isNotEmpty);
    expect(requestBodies.single['max_tokens'], 4096);
    expect(requestBodies.single['response_format'], isNotNull);
  });

  test(
      'cloudflare llama valid json still fails when care report schema is incomplete',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-llama-incomplete-schema',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/meta/llama-3.1-8b-instruct-fast',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
      'cfg-cloudflare-llama-incomplete-schema',
      'cf-test-token',
    );

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode({
                    'overallScore': 81,
                    'oneLineSummary': '整体稳定。',
                    'executiveSummary': '本周期整体稳定，提醒和记录都有持续跟进。',
                    'overallAssessment': ['整体执行稳定。'],
                    'keyFindings': ['主线节奏正常。'],
                    'trendAnalysis': ['暂无明显波动。'],
                    'riskAssessment': ['当前风险可控。'],
                    'priorityActions': ['继续保持本周观察。'],
                    'recommendationRankings': [
                      {
                        'rank': 1,
                        'kind': 'action',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '继续观察',
                        'summary': '当前整体稳定。',
                        'suggestedAction': '继续保持记录。',
                      },
                    ],
                  }),
                },
              },
            ],
          }),
        ),
      ),
    );

    await expectLater(
      () => service.generateCareReport(_heavyCareContext()),
      throwsA(
        isA<AiGenerationException>()
            .having(
              (error) => error.message,
              'message',
              contains('缺少 perPetReports'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('模型未按 schema 输出'),
            ),
      ),
    );
  });

  test(
      'retries missing required care report fields on the same payload level before degrading',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final userPromptLengths = <int>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-missing-field-retry-same-level',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey(
        'cfg-missing-field-retry-same-level', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          final userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          userPromptLengths.add(userPrompt.length);
          if (userPromptLengths.length == 1) {
            return AiHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'overallScore': 81,
                        'oneLineSummary': '第一轮缺字段。',
                        'executiveSummary': '第一轮结构不完整。',
                        'overallAssessment': ['结构不完整。'],
                        'keyFindings': ['缺少 perPetReports。'],
                        'trendAnalysis': ['暂无趋势。'],
                        'riskAssessment': ['结构不完整。'],
                        'priorityActions': ['继续重试。'],
                        'recommendationRankings': [
                          {
                            'rank': 1,
                            'kind': 'action',
                            'petIds': ['pet-1'],
                            'petNames': ['Mochi'],
                            'title': '补全结构',
                            'summary': '先补齐结构化字段。',
                            'suggestedAction': '继续保持记录。',
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
            );
          }
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '同档位重试后补齐字段并生成成功。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_heavyCareContext());

    expect(report.oneLineSummary, '同档位重试后补齐字段并生成成功。');
    expect(report.promptPayloadVersion, 'full');
    expect(report.promptPayloadVersionLabel, '所有数据');
    expect(userPromptLengths, hasLength(2));
    expect(userPromptLengths.last, userPromptLengths.first);
  });

  test(
      'cloudflare workers ai retries care report after length-truncated reasoning response',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final userPromptLengths = <int>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-length-retry',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare-length-retry', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          final userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          userPromptLengths.add(userPrompt.length);
          if (userPromptLengths.length == 1) {
            return const AiHttpResponse(
              statusCode: 200,
              body:
                  '{"id":"resp_1","object":"chat.completion","created":1776536530,"model":"@cf/google/gemma-4-26b-a4b-it","choices":[{"finish_reason":"length","index":0,"message":{"role":"assistant","reasoning":"Pet Daily Care Analysis Assistant. Summarize only according to provided data.","content":null}}]}',
            );
          }
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '长度截断后已通过降载重试成功生成。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_heavyCareContext());

    expect(report.oneLineSummary, '长度截断后已通过降载重试成功生成。');
    expect(userPromptLengths, hasLength(2));
    expect(userPromptLengths.last, lessThan(userPromptLengths.first));
  });

  test('parses care report when raw json is preceded by long natural language',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-long-preface-json',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-long-preface-json', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '我先说明一下 {这些花括号只是解释字段，不是最终输出}。\n'
                      '下面才是最后结果，请直接读取最后那个 JSON object。\n\n'
                      '${jsonEncode(_careReportResponseJson(petId: "pet-1", petName: "Mochi", executiveSummary: "长说明后仍然成功解析。"))}\n'
                      '补充说明结束。',
                },
              },
            ],
          }),
        ),
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '长说明后仍然成功解析。');
    expect(report.perPetReports.single.petName, 'Mochi');
  });

  test(
      'retries care report when content contains incomplete json without finish_reason',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final userPromptLengths = <int>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-incomplete-json-retry',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/google/gemma-4-26b-a4b-it',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-incomplete-json-retry', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          final userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          userPromptLengths.add(userPrompt.length);
          if (userPromptLengths.length == 1) {
            return const AiHttpResponse(
              statusCode: 200,
              body:
                  r'''{"choices":[{"index":0,"message":{"role":"assistant","content":"先给结论：整体照护节奏基本稳定，但我这次输出被截住了。
{
  "overallScore": 84,
  "statusLabel": "基本稳定",
  "oneLineSummary": "这是一段被截断的 JSON"}}]}''',
            );
          }
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '未标 finish_reason 的半截 JSON 已走重试。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_heavyCareContext());

    expect(report.oneLineSummary, '未标 finish_reason 的半截 JSON 已走重试。');
    expect(userPromptLengths, hasLength(2));
    expect(userPromptLengths.last, lessThan(userPromptLengths.first));
  });

  test('retries care report with a smaller prompt after provider overload',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final userPromptLengths = <int>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-overload-retry',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-overload-retry', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          final userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          userPromptLengths.add(userPrompt.length);
          if (userPromptLengths.length == 1) {
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
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '经过降载后成功生成报告。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_heavyCareContext());

    expect(report.oneLineSummary, '经过降载后成功生成报告。');
    expect(userPromptLengths, hasLength(2));
    expect(userPromptLengths.last, lessThan(userPromptLengths.first));
  });

  test('retries care report after a timeout with a smaller prompt', () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    final userPromptLengths = <int>[];

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-timeout-retry',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-timeout-retry', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          final userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          userPromptLengths.add(userPrompt.length);
          if (userPromptLengths.length == 1) {
            throw TimeoutException('future not completed');
          }
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                        executiveSummary: '超时后使用轻量上下文生成成功。',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    final report = await service.generateCareReport(_heavyCareContext());

    expect(report.oneLineSummary, '超时后使用轻量上下文生成成功。');
    expect(userPromptLengths, hasLength(2));
    expect(userPromptLengths.last, lessThan(userPromptLengths.first));
  });

  test('care report maps status labels locally from provider supplied scores',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-local-score',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-local-score', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    ..._careReportResponseJson(
                      petId: 'pet-1',
                      petName: 'Mochi',
                    ),
                    'overallScore': 61,
                    'statusLabel': '状态不错',
                    'perPetReports': [
                      {
                        ...(_careReportResponseJson(
                          petId: 'pet-1',
                          petName: 'Mochi',
                        )['perPetReports'] as List)
                            .single as Map<String, dynamic>,
                        'score': 58,
                        'statusLabel': '状态还行',
                      },
                    ],
                  }),
                },
              },
            ],
          }),
        ),
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.overallScore, 61);
    expect(report.statusLabel, '急需关注');
    expect(report.perPetReports.single.score, 58);
    expect(report.perPetReports.single.statusLabel, '存在隐患');
  });

  test(
      'care report prompt keeps only per-pet payload and excludes duplicated rules',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    String? capturedSystemPrompt;
    String? capturedUserPrompt;

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-payload-check',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-payload-check', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          capturedSystemPrompt =
              (messages[0] as Map<String, dynamic>)['content'] as String;
          capturedUserPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      _careReportResponseJson(
                        petId: 'pet-1',
                        petName: 'Mochi',
                      ),
                    ),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    await service.generateCareReport(_sampleCareContext());

    expect(capturedSystemPrompt, isNotNull);
    expect(capturedSystemPrompt, contains('顶层必填字段固定为'));
    expect(capturedSystemPrompt, contains('recommendationRankings 中每一项都必须包含'));
    expect(capturedSystemPrompt, contains('perPetReports 中每一项都必须包含'));
    expect(capturedSystemPrompt, contains('输出前先逐项自检所有必填字段是否齐全'));
    expect(capturedSystemPrompt, contains('先完整输出 perPetReports'));
    expect(capturedSystemPrompt, contains('从宠物当前状态、变化趋势、照护缺口和后续照护重点出发'));
    expect(capturedSystemPrompt, contains('一句话总结，直接概括宠物当前最值得关注的状态结论'));
    expect(capturedSystemPrompt, contains('围绕宠物当前状态与照护重点的下一步建议'));
    expect(capturedSystemPrompt, contains('不要站在人类任务管理视角输出'));
    expect(capturedSystemPrompt, isNot(contains('statusLabel')));
    expect(capturedSystemPrompt, isNot(contains('状态语')));
    expect(capturedSystemPrompt, isNot(contains('dataQualityNotes')));
    expect(capturedSystemPrompt, isNot(contains('summary、careFocus')));
    expect(capturedSystemPrompt, isNot(contains('用户下一步应该怎么做')));
    expect(capturedSystemPrompt, isNot(contains('直接告诉用户当前最值得关注的结论')));
    expect(capturedUserPrompt, isNotNull);
    expect(capturedUserPrompt, contains('context'));
    expect(capturedUserPrompt, contains('pets'));
    expect(capturedUserPrompt, contains('"todos"'));
    expect(capturedUserPrompt, contains('"reminders"'));
    expect(capturedUserPrompt, contains('"records"'));
    expect(capturedUserPrompt, contains('"title":"补充耳道观察"'));
    expect(capturedUserPrompt, contains('"title":"驱虫提醒"'));
    expect(capturedUserPrompt, contains('"title":"耳道复查"'));
    expect(capturedUserPrompt, isNot(contains('expectedCare')));
    expect(capturedUserPrompt, isNot(contains('missingCare')));
    expect(capturedUserPrompt, isNot(contains('recentSignals')));
    expect(capturedUserPrompt, isNot(contains('riskSignals')));
    expect(capturedUserPrompt, isNot(contains('当前没有明确缺口，但仍建议保持连续记录')));
    expect(capturedUserPrompt, isNot(contains('summaryPackage')));
    expect(capturedUserPrompt, isNot(contains('scoringGuidelines')));
    expect(capturedUserPrompt, isNot(contains('globalEvidence')));
    expect(capturedUserPrompt, isNot(contains('recommendationRules')));
    expect(capturedUserPrompt, isNot(contains('statusBands')));
    expect(capturedUserPrompt, isNot(contains('全局状态语')));
    expect(capturedUserPrompt, isNot(contains('dataQualityNotes')));
    expect(capturedUserPrompt, isNot(contains('"overallScore"')));
    expect(capturedUserPrompt, isNot(contains('"statusLabel"')));
    expect(capturedUserPrompt, isNot(contains('scorecard')));
  });

  test(
      'care report accepts minimal per-pet schema and derives display fields locally',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-minimal-per-pet-schema',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-minimal-per-pet-schema', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => AiHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'overallScore': 84,
                    'oneLineSummary': '整体稳定。',
                    'executiveSummary': '本周期整体稳定，重点是继续保持耳道观察和记录闭环。',
                    'overallAssessment': ['整体执行稳定。'],
                    'keyFindings': ['耳道护理已有动作，但还要持续跟进。'],
                    'trendAnalysis': ['近期照护节奏平稳。'],
                    'riskAssessment': ['当前风险可控，但仍需保持观察。'],
                    'priorityActions': ['继续补齐耳道观察记录。'],
                    'recommendationRankings': [
                      {
                        'rank': 1,
                        'kind': 'action',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '补上耳道观察闭环',
                        'summary': '最近已有相关护理动作，但缺少后续观察。',
                        'suggestedAction': '本周补一次耳道观察。',
                      },
                      {
                        'rank': 2,
                        'kind': 'gap',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '补齐过敏跟进记录',
                        'summary': '当前过敏相关资料仍偏少。',
                        'suggestedAction': '补充饮食与症状变化记录。',
                      },
                      {
                        'rank': 3,
                        'kind': 'risk',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '继续盯住提醒闭环',
                        'summary': '提醒已建立，但仍要防止遗漏。',
                        'suggestedAction': '核对本周提醒完成情况。',
                      },
                      {
                        'rank': 4,
                        'kind': 'action',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '保持当前照护节奏',
                        'summary': '基础照护节奏整体稳定。',
                        'suggestedAction': '保持当前提醒节奏。',
                      },
                      {
                        'rank': 5,
                        'kind': 'gap',
                        'petIds': ['pet-1'],
                        'petNames': ['Mochi'],
                        'title': '补强重点问题证据',
                        'summary': '重点问题记录仍然偏少。',
                        'suggestedAction': '补充一条重点问题观察记录。',
                      },
                    ],
                    'perPetReports': [
                      {
                        'petId': 'pet-1',
                        'petName': 'Mochi',
                        'score': 82,
                        'whyThisScore': ['耳道护理已有动作，但后续观察还不够连续。'],
                        'topPriority': ['优先补上耳道观察闭环。'],
                        'missedItems': ['近期缺少过敏相关跟进记录。'],
                        'followUpPlan': ['下一个观察重点是耳道状态和进食表现。'],
                      },
                    ],
                  }),
                },
              },
            ],
          }),
        ),
      ),
    );

    final report = await service.generateCareReport(_sampleCareContext());

    expect(report.oneLineSummary, '整体稳定。');
    expect(report.statusLabel, '状态还行');
    expect(report.perPetReports.single.summary, '耳道护理已有动作，但后续观察还不够连续。');
    expect(report.perPetReports.single.careFocus, '优先补上耳道观察闭环。');
    expect(report.perPetReports.single.keyEvents, isEmpty);
    expect(
        report.perPetReports.single.recommendedActions, ['下一个观察重点是耳道状态和进食表现。']);
    expect(report.perPetReports.single.followUpFocus, '下一个观察重点是耳道状态和进食表现。');
    expect(report.perPetReports.single.recentChanges, isEmpty);
    expect(report.promptPayloadVersion, 'full');
    expect(report.promptPayloadVersionLabel, '所有数据');
  });

  test('generates visit summary from anthropic messages', () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-anthropic',
        displayName: 'Anthropic',
        providerType: AiProviderType.anthropic,
        baseUrl: 'https://api.anthropic.com/v1',
        model: 'claude-sonnet-4-20250514',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-anthropic', 'anthropic-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path.endsWith('/messages'), isTrue);
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'visitReason': '近两周耳道护理后仍有抓耳行为，准备复查。',
                    'timeline': ['04-01 出现抓耳', '04-03 做了耳道清洁'],
                    'medicationsAndTreatments': ['耳道清洁 1 次'],
                    'testsAndResults': ['暂无新检查结果'],
                    'questionsToAskVet': ['是否需要继续滴耳液'],
                  }),
                },
              ],
            }),
          );
        },
      ),
    );

    final summary = await service.generateVisitSummary(
      AiGenerationContext(
        title: '最近 30 天看诊摘要',
        rangeLabel: '最近 30 天',
        rangeStart: DateTime.parse('2026-03-10T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: [
          Pet(
            id: 'pet-1',
            name: 'Mochi',
            avatarText: 'MO',
            type: PetType.cat,
            breed: '英短',
            sex: '母',
            birthday: '2024-02-12',
            ageLabel: '2岁',
            weightKg: 4.2,
            neuterStatus: PetNeuterStatus.neutered,
            feedingPreferences: '主粮+冻干',
            allergies: '鸡肉敏感',
            note: '偶尔紧张',
          ),
        ],
        todos: const [],
        reminders: const [],
        records: [
          PetRecord(
            id: 'record-1',
            petId: 'pet-1',
            type: PetRecordType.medical,
            title: '耳道复查',
            recordDate: DateTime.parse('2026-04-03T18:00:00+08:00'),
            summary: '抓耳次数略有增加，准备复查。',
            note: '近两周有耳道护理。',
          ),
        ],
      ),
    );

    expect(summary.visitReason, contains('复查'));
    expect(summary.timeline, hasLength(2));
    expect(summary.questionsToAskVet.single, contains('滴耳液'));
  });

  test('throws a readable exception when provider response is malformed',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai',
        displayName: 'OpenAI',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-openai', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          return const AiHttpResponse(
            statusCode: 200,
            body: '{"choices":[{"message":{"content":"not-json"}}]}',
          );
        },
      ),
    );

    await expectLater(
      () => service.generateCareReport(
        AiGenerationContext(
          title: '最近 7 天的总结',
          rangeLabel: '最近 7 天',
          rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
          rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
          languageTag: 'zh-CN',
          pets: const [],
          todos: const [],
          reminders: const [],
          records: const [],
        ),
      ),
      throwsA(
        isA<AiGenerationException>()
            .having(
              (error) => error.message,
              'message',
              contains('结构化'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('not-json'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('响应异常')),
            ),
      ),
    );
  });

  test('surfaces response body when generation response has no chat result',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai-malformed-body',
        displayName: 'OpenAI',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-openai-malformed-body', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          return const AiHttpResponse(
            statusCode: 200,
            body: '{"error":{"message":"model returned empty choices"}}',
          );
        },
      ),
    );

    await expectLater(
      () => service.generateCareReport(
        AiGenerationContext(
          title: '最近 7 天的总结',
          rangeLabel: '最近 7 天',
          rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
          rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
          languageTag: 'zh-CN',
          pets: const [],
          todos: const [],
          reminders: const [],
          records: const [],
        ),
      ),
      throwsA(
        isA<AiGenerationException>().having(
          (error) => error.message,
          'message',
          contains('model returned empty choices'),
        ),
      ),
    );
  });

  test(
      'surfaces cloudflare empty-content responses as compatibility-layer failures',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-cloudflare-empty-content',
        displayName: 'Cloudflare Workers AI',
        providerType: AiProviderType.cloudflareWorkersAi,
        baseUrl:
            'https://api.cloudflare.com/client/v4/accounts/demo-account/ai/v1',
        model: '@cf/meta/llama-3.1-8b-instruct-fast',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-cloudflare-empty-content', 'cf-test-token');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async => const AiHttpResponse(
          statusCode: 200,
          body:
              '{"choices":[{"index":0,"message":{"role":"assistant"},"finish_reason":"stop"}]}',
        ),
      ),
    );

    await expectLater(
      () => service.generateCareReport(_sampleCareContext()),
      throwsA(
        isA<AiGenerationException>().having(
          (error) => error.message,
          'message',
          contains('兼容层非流式聚合异常'),
        ),
      ),
    );
  });

  test(
      'surfaces provider error message when generation response includes api error',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai-error',
        displayName: 'OpenAI',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-openai-error', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          return const AiHttpResponse(
            statusCode: 400,
            body:
                '{"error":{"message":"response_format json_object is not supported by this model"}}',
          );
        },
      ),
    );

    await expectLater(
      () => service.generateCareReport(
        AiGenerationContext(
          title: '最近 7 天的总结',
          rangeLabel: '最近 7 天',
          rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
          rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
          languageTag: 'zh-CN',
          pets: const [],
          todos: const [],
          reminders: const [],
          records: const [],
        ),
      ),
      throwsA(
        isA<AiGenerationException>().having(
          (error) => error.message,
          'message',
          contains(
              'response_format json_object is not supported by this model'),
        ),
      ),
    );
  });

  test(
      'returns a conservative visit summary when the selected range has no data',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-openai',
        displayName: 'OpenAI',
        providerType: AiProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-openai', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          fail(
              'empty-range visit summaries should not call the remote AI provider');
        },
      ),
    );

    final summary = await service.generateVisitSummary(
      AiGenerationContext(
        title: '最近 30 天看诊摘要',
        rangeLabel: '最近 30 天',
        rangeStart: DateTime.parse('2026-03-10T00:00:00+08:00'),
        rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
        languageTag: 'zh-CN',
        pets: [
          Pet(
            id: 'pet-1',
            name: 'Mochi',
            avatarText: 'MO',
            type: PetType.cat,
            breed: '英短',
            sex: '母',
            birthday: '2024-02-12',
            ageLabel: '2岁',
            weightKg: 4.2,
            neuterStatus: PetNeuterStatus.neutered,
            feedingPreferences: '主粮+冻干',
            allergies: '鸡肉敏感',
            note: '偶尔紧张',
          ),
        ],
        todos: const [],
        reminders: const [],
        records: const [],
      ),
    );

    expect(summary.visitReason, contains('暂无足够记录'));
    expect(summary.timeline.single, contains('暂无'));
    expect(summary.questionsToAskVet.single, contains('带上最新观察'));
  });

  test('hasActiveProvider returns false when secure storage read fails',
      () async {
    final settingsController = await AppSettingsController.load();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-secret-failure',
        displayName: 'Compatible',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        model: 'petnote-ai',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: _ThrowingSecretStore(),
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          fail('hasActiveProvider should not call the remote AI provider');
        },
      ),
    );

    expect(await service.hasActiveProvider(), isFalse);
  });
}

Map<String, dynamic> _careReportResponseJson({
  required String petId,
  required String petName,
  String executiveSummary = '本周期整体稳定，提醒和记录都有持续跟进。',
}) {
  return {
    'overallScore': 84,
    'statusLabel': '基本稳定',
    'oneLineSummary': executiveSummary,
    'recommendationRankings': [
      {
        'rank': 1,
        'kind': 'action',
        'petIds': [petId],
        'petNames': [petName],
        'title': '优先补上$petName 的耳道复查',
        'summary': '$petName 最近仍有耳道护理线索，但后续观察没有闭环。',
        'suggestedAction': '本周补一次耳道观察',
      },
      {
        'rank': 2,
        'kind': 'gap',
        'petIds': [petId],
        'petNames': [petName],
        'title': '补齐$petName 的过敏跟进记录',
        'summary': '现有资料无法稳定判断过敏波动。',
        'suggestedAction': '补充饮食与症状变化记录',
      },
      {
        'rank': 3,
        'kind': 'risk',
        'petIds': [petId],
        'petNames': [petName],
        'title': '$petName 的提醒闭环仍需加强',
        'summary': '关键提醒虽然已建立，但仍有延迟风险。',
        'suggestedAction': '核对本周提醒完成情况',
      },
      {
        'rank': 4,
        'kind': 'action',
        'petIds': [petId],
        'petNames': [petName],
        'title': '继续保持$petName 的当前照护节奏',
        'summary': '当前基础照护节奏整体稳定。',
        'suggestedAction': '保持当前提醒节奏',
      },
      {
        'rank': 5,
        'kind': 'gap',
        'petIds': [petId],
        'petNames': [petName],
        'title': '补强$petName 的重点问题证据',
        'summary': '重点问题记录仍然偏少，影响判断可信度。',
        'suggestedAction': '补充一条针对重点问题的观察记录',
      },
    ],
    'perPetReports': [
      {
        'petId': petId,
        'petName': petName,
        'score': 82,
        'statusLabel': '基本稳定',
        'whyThisScore': ['耳道护理已有动作，但后续观察还不够连续。'],
        'topPriority': ['优先补上耳道观察闭环。'],
        'missedItems': ['近期缺少过敏相关跟进记录。'],
        'recentChanges': ['最近有新增耳道护理记录。'],
        'followUpPlan': ['下一个观察重点是耳道状态和进食表现。'],
      },
    ],
  };
}

AiGenerationContext _sampleCareContext() {
  return AiGenerationContext(
    title: '最近 7 天的总结',
    rangeLabel: '最近 7 天',
    rangeStart: DateTime.parse('2026-04-02T00:00:00+08:00'),
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [
      Pet(
        id: 'pet-1',
        name: 'Mochi',
        avatarText: 'MO',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        ageLabel: '2岁',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '主粮+冻干',
        allergies: '鸡肉敏感',
        note: '偶尔紧张',
      ),
    ],
    todos: [
      TodoItem(
        id: 'todo-1',
        petId: 'pet-1',
        title: '补充耳道观察',
        dueAt: DateTime.parse('2026-04-08T18:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.done,
        note: '',
      ),
    ],
    reminders: [
      ReminderItem(
        id: 'reminder-1',
        petId: 'pet-1',
        kind: ReminderKind.deworming,
        title: '驱虫提醒',
        scheduledAt: DateTime.parse('2026-04-06T09:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '每月',
        status: ReminderStatus.done,
        note: '',
      ),
    ],
    records: [
      PetRecord(
        id: 'record-1',
        petId: 'pet-1',
        type: PetRecordType.medical,
        title: '耳道复查',
        recordDate: DateTime.parse('2026-04-07T20:00:00+08:00'),
        summary: '状态稳定。',
        note: '继续观察。',
      ),
    ],
  );
}

AiGenerationContext _heavyCareContext() {
  final baseStart = DateTime.parse('2025-10-12T00:00:00+08:00');
  return AiGenerationContext(
    title: '最近 6 个月的总结',
    rangeLabel: '最近 6 个月',
    rangeStart: baseStart,
    rangeEnd: DateTime.parse('2026-04-09T23:59:59+08:00'),
    languageTag: 'zh-CN',
    pets: [
      Pet(
        id: 'pet-1',
        name: 'Mochi',
        avatarText: 'MO',
        type: PetType.cat,
        breed: '英短',
        sex: '母',
        birthday: '2024-02-12',
        ageLabel: '2岁',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '主粮+冻干',
        allergies: '鸡肉敏感',
        note: '偶尔紧张，需要持续观察肠胃和耳道状态。',
      ),
    ],
    todos: List.generate(90, (index) {
      return TodoItem(
        id: 'todo-$index',
        petId: 'pet-1',
        title: '待办任务 $index',
        dueAt: baseStart.add(Duration(days: index * 2)),
        notificationLeadTime: NotificationLeadTime.none,
        status: index % 7 == 0 ? TodoStatus.overdue : TodoStatus.done,
        note: '这是第 $index 条待办，用于模拟长周期照护数据。',
      );
    }),
    reminders: List.generate(85, (index) {
      return ReminderItem(
        id: 'reminder-$index',
        petId: 'pet-1',
        kind: index.isEven ? ReminderKind.deworming : ReminderKind.vaccine,
        title: '提醒事项 $index',
        scheduledAt: baseStart.add(Duration(days: index * 2 + 1)),
        notificationLeadTime: NotificationLeadTime.none,
        recurrence: '每月',
        status: index % 6 == 0 ? ReminderStatus.overdue : ReminderStatus.done,
        note: '这是第 $index 条提醒，用于模拟长周期照护数据。',
      );
    }),
    records: List.generate(107, (index) {
      return PetRecord(
        id: 'record-$index',
        petId: 'pet-1',
        type: index % 5 == 0 ? PetRecordType.medical : PetRecordType.other,
        title: '记录 $index',
        recordDate: baseStart.add(Duration(days: index)),
        summary: '这是第 $index 条记录摘要。',
        note: '用于模拟最近 6 个月的连续观察和护理记录。',
      );
    }),
  );
}

class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport({required this.handler});

  final Future<AiHttpResponse> Function(AiHttpRequest request) handler;

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) {
    return handler(request);
  }
}

class _ThrowingSecretStore implements AiSecretStore {
  @override
  Future<void> deleteKey(String configId) async {}

  @override
  Future<Map<String, bool>> hasKeys(Iterable<String> configIds) async {
    throw const AiSecretStoreException('secure storage unavailable');
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> readKey(String configId) async {
    throw const AiSecretStoreException('secure storage unavailable');
  }

  @override
  Future<void> writeKey(String configId, String value) async {}
}
