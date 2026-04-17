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
    expect(report.statusLabel, '基本稳定');
    expect(report.oneLineSummary, contains('整体稳定'));
    expect(report.recommendationRankings, hasLength(5));
    expect(report.recommendationRankings.first.petNames, contains('Mochi'));
    expect(report.overallScore, inInclusiveRange(0, 100));
    expect(report.recommendationRankings.first.kind, 'action');
    expect(report.perPetReports.single.petName, 'Mochi');
    expect(report.perPetReports.single.score, 82);
    expect(report.perPetReports.single.statusLabel, '基本稳定');
    expect(report.perPetReports.single.whyThisScore, isNotEmpty);
    expect(report.perPetReports.single.followUpPlan, isNotEmpty);
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
          final userPrompt = (messages[1] as Map<String, dynamic>)['content']
              as String;
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
          final userPrompt = (messages[1] as Map<String, dynamic>)['content']
              as String;
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

  test(
      'care report uses provider supplied scores and status labels from AI output',
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
                    'statusLabel': '急需关注',
                    'perPetReports': [
                      {
                        ...(_careReportResponseJson(
                          petId: 'pet-1',
                          petName: 'Mochi',
                        )['perPetReports'] as List)
                            .single as Map<String, dynamic>,
                        'score': 58,
                        'statusLabel': '存在隐患',
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

  test('care report prompt payload excludes precomputed score and status labels',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
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

    expect(capturedUserPrompt, isNotNull);
    expect(capturedUserPrompt, contains('analysisConfig'));
    expect(capturedUserPrompt, contains('scoringGuidelines'));
    expect(capturedUserPrompt, contains('expectedCare'));
    expect(capturedUserPrompt, contains('missingCare'));
    expect(capturedUserPrompt, isNot(contains('"overallScore"')));
    expect(capturedUserPrompt, isNot(contains('"statusLabel"')));
    expect(capturedUserPrompt, isNot(contains('scorecard')));
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
        isA<AiGenerationException>().having(
          (error) => error.message,
          'message',
          contains('结构化'),
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
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> readKey(String configId) async {
    throw const AiSecretStoreException('secure storage unavailable');
  }

  @override
  Future<void> writeKey(String configId, String value) async {}
}
