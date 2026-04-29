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

  test('care report uses short-form schema and short-form prompt wording',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    String? systemPrompt;
    String? userPrompt;

    await settingsController.upsertAiProviderConfig(
      AiProviderConfig(
        id: 'cfg-bigmodel-short-form',
        displayName: 'BigModel',
        providerType: AiProviderType.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.7',
        isActive: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await secretStore.writeKey('cfg-bigmodel-short-form', 'sk-test-123');

    final service = NetworkAiInsightsService(
      clientFactory: AiClientFactory(
        settingsController: settingsController,
        secretStore: secretStore,
      ),
      transport: _FakeAiHttpTransport(
        handler: (request) async {
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          systemPrompt =
              (messages[0] as Map<String, dynamic>)['content'] as String;
          userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(_careReportResponseJson()),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    await service.generateCareReport(_sampleCareContext());

    expect(systemPrompt, isNotNull);
    expect(systemPrompt, contains('"executiveSummary": "60-100字'));
    expect(systemPrompt, contains('"overallAssessment": ["1-3条总体判断"]'));
    expect(systemPrompt, isNot(contains('120-220字')));
    expect(userPrompt, contains('生成 AI 总览'));
    expect(userPrompt, isNot(contains('正式分析报告”风格的 AI 总览')));
  });

  test('care report sends ai summary package instead of raw event arrays',
      () async {
    final settingsController = await AppSettingsController.load();
    final secretStore = InMemoryAiSecretStore();
    final createdAt = DateTime.parse('2026-04-09T10:00:00+08:00');
    String? userPrompt;

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
          final body = jsonDecode(request.body!) as Map<String, dynamic>;
          final messages = body['messages'] as List<dynamic>;
          userPrompt =
              (messages[1] as Map<String, dynamic>)['content'] as String;
          return AiHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(_careReportResponseJson()),
                  },
                },
              ],
            }),
          );
        },
      ),
    );

    await service.generateCareReport(_sampleCareContext());

    expect(userPrompt, isNotNull);
    expect(userPrompt, contains('"context":{'));
    expect(userPrompt, contains('"pets":['));
    expect(userPrompt, contains('"todos":['));
    expect(userPrompt, contains('"reminders":['));
    expect(userPrompt, contains('"records":['));
  });
}

Map<String, Object?> _careReportResponseJson() {
  return {
    'executiveSummary': '整体稳定。',
    'overallAssessment': ['提醒、记录与待办协同顺畅。'],
    'keyFindings': ['已完成关键提醒。'],
    'trendAnalysis': ['照护节奏保持稳定。'],
    'riskAssessment': ['暂未发现新的集中风险。'],
    'priorityActions': ['继续保持当前节奏。'],
    'dataQualityNotes': ['本周期样本量充足。'],
    'perPetReports': [
      {
        'petId': 'pet-1',
        'petName': 'Mochi',
        'score': 86,
        'summary': 'Mochi 当前照护节奏稳定。',
        'careFocus': '继续观察耳道状态。',
        'keyEvents': ['完成驱虫提醒'],
        'trendAnalysis': ['食欲记录更规律'],
        'riskAssessment': ['暂无新增风险'],
        'recommendedActions': ['继续保持记录'],
        'followUpFocus': '观察耳道与精神状态。',
        'whyThisScore': ['近期照护节奏稳定，但耳道观察还需要持续闭环。'],
        'topPriority': ['继续补充耳道观察记录并确认复查节点。'],
        'missedItems': ['耳道复查后的连续观察记录还不够完整。'],
        'followUpPlan': ['未来 7 天继续记录耳道与精神状态，并视情况安排复查。'],
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
        title: '补货主粮',
        dueAt: DateTime.parse('2026-04-08T18:00:00+08:00'),
        notificationLeadTime: NotificationLeadTime.none,
        status: TodoStatus.done,
        note: '准备换粮',
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

class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport({required this.handler});

  final Future<AiHttpResponse> Function(AiHttpRequest request) handler;

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) => handler(request);
}
