import 'dart:convert';
import 'dart:io';

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

const _accountIdEnvName = 'CLOUDFLARE_ACCOUNT_ID';
const _apiTokenEnvName = 'CLOUDFLARE_API_TOKEN';
const _modelsEnvName = 'CLOUDFLARE_AI_MODELS';

void main() {
  final accountId = Platform.environment[_accountIdEnvName]?.trim() ?? '';
  final apiToken = Platform.environment[_apiTokenEnvName]?.trim() ?? '';
  final models = _cloudflareModels();
  final skipReason = accountId.isEmpty || apiToken.isEmpty
      ? '需要在当前终端设置 $_accountIdEnvName 和 $_apiTokenEnvName 后才会真实调用 Cloudflare Workers AI。'
      : false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'cloudflare workers ai live care report generation matches app parser',
    () async {
      final baseUrl =
          'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/v1';
      final results = <String>[];

      for (final model in models) {
        final settingsController = await AppSettingsController.load();
        final secretStore = InMemoryAiSecretStore();
        final transport = _RecordingAiHttpTransport();
        final configId = 'cloudflare-live-${model.hashCode}';
        final now = DateTime.parse('2026-04-19T10:00:00+08:00');

        await settingsController.upsertAiProviderConfig(
          AiProviderConfig(
            id: configId,
            displayName: 'Cloudflare Workers AI Live',
            providerType: AiProviderType.cloudflareWorkersAi,
            baseUrl: baseUrl,
            model: model,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await secretStore.writeKey(configId, apiToken);

        final service = NetworkAiInsightsService(
          clientFactory: AiClientFactory(
            settingsController: settingsController,
            secretStore: secretStore,
          ),
          transport: transport,
        );

        final startedAt = DateTime.now();
        final report = await service.generateCareReport(
          _sampleCareContext(),
          forceRefresh: true,
        );
        final elapsed = DateTime.now().difference(startedAt);
        final response = transport.responses.last;
        final responseSummary = _summarizeChatCompletion(response.body);
        final result = {
          'model': model,
          'statusCode': response.statusCode,
          'elapsedMs': elapsed.inMilliseconds,
          'requestCount': transport.requests.length,
          'maxTokens': transport.lastRequestMaxTokens,
          'finishReason': responseSummary.finishReason,
          'contentLength': responseSummary.contentLength,
          'oneLineSummary': report.oneLineSummary,
          'recommendationCount': report.recommendationRankings.length,
          'perPetReportCount': report.perPetReports.length,
        };
        results.add(jsonEncode(result));
        // ignore: avoid_print
        print('[Cloudflare Workers AI live] ${jsonEncode(result)}');

        expect(response.statusCode, 200);
        expect(report.oneLineSummary.trim(), isNotEmpty);
        expect(report.recommendationRankings, isNotEmpty);
        expect(report.perPetReports, isNotEmpty);
      }

      expect(results, hasLength(models.length));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test('live sample care context uses dual pets and high-volume quarterly data',
      () {
    final context = _sampleCareContext();

    expect(context.pets, hasLength(2));
    expect(
        context.todos.length +
            context.reminders.length +
            context.records.length,
        greaterThanOrEqualTo(300));
    expect(
      context.rangeEnd.difference(context.rangeStart).inDays,
      greaterThanOrEqualTo(89),
    );
  });
}

List<String> _cloudflareModels() {
  final rawModels = Platform.environment[_modelsEnvName];
  if (rawModels == null || rawModels.trim().isEmpty) {
    return const [
      '@cf/google/gemma-4-26b-a4b-it',
      '@cf/meta/llama-3.1-8b-instruct-fast',
    ];
  }
  final parsedModels = rawModels
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return parsedModels.isEmpty
      ? const ['@cf/google/gemma-4-26b-a4b-it']
      : parsedModels;
}

AiGenerationContext _sampleCareContext() {
  final pets = [
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
      note: '偶尔紧张，需要持续观察耳道和肠胃状态。',
    ),
    Pet(
      id: 'pet-2',
      name: 'Cocoa',
      avatarText: 'CO',
      type: PetType.dog,
      breed: '柯基',
      sex: '公',
      birthday: '2023-06-03',
      ageLabel: '3岁',
      weightKg: 12.1,
      neuterStatus: PetNeuterStatus.notNeutered,
      feedingPreferences: '鲜食拌粮，运动后补水',
      allergies: '高盐零食会抓耳',
      note: '雨天运动不足时晚上容易烦躁。',
    ),
  ];
  final rangeStart = DateTime.parse('2026-01-20T00:00:00+08:00');
  final rangeEnd = DateTime.parse('2026-04-19T23:59:59+08:00');
  final todos = <TodoItem>[];
  final reminders = <ReminderItem>[];
  final records = <PetRecord>[];
  final todoTitles = ['补充耳道观察', '梳毛排毛计划', '饮水观察复盘', '便便状态补记'];
  final reminderTitles = ['驱虫提醒', '疫苗复查提醒', '洗护提醒', '体重复盘提醒'];
  final recordTitles = ['耳道复查', '进食观察', '便便记录', '散步状态记录', '皮肤观察'];

  for (var index = 0; index < 100; index += 1) {
    final pet = pets[index % pets.length];
    final at = rangeStart.add(Duration(hours: 18 * index));
    final todoTitle = todoTitles[index % todoTitles.length];
    final reminderTitle = reminderTitles[index % reminderTitles.length];
    final recordTitle = recordTitles[index % recordTitles.length];
    todos.add(
      TodoItem(
        id: 'todo-$index',
        petId: pet.id,
        title: '$todoTitle #${index + 1}',
        dueAt: at,
        notificationLeadTime: NotificationLeadTime
            .values[index % NotificationLeadTime.values.length],
        status: TodoStatus.values[index % TodoStatus.values.length],
        note: '${pet.name} 这次任务用于补齐连续观察和护理闭环。',
      ),
    );
    reminders.add(
      ReminderItem(
        id: 'reminder-$index',
        petId: pet.id,
        kind: ReminderKind.values[index % ReminderKind.values.length],
        title: '$reminderTitle #${index + 1}',
        scheduledAt: at.add(const Duration(hours: 6)),
        notificationLeadTime: NotificationLeadTime
            .values[index % NotificationLeadTime.values.length],
        recurrence: index.isEven ? '每月' : '单次',
        status: ReminderStatus.values[index % ReminderStatus.values.length],
        note: '${pet.name} 需要继续看护理节奏、观察连续性和提醒闭环。',
      ),
    );
    records.add(
      PetRecord(
        id: 'record-$index',
        petId: pet.id,
        type: PetRecordType.values[index % PetRecordType.values.length],
        title: '$recordTitle #${index + 1}',
        recordDate: at.add(const Duration(hours: 12)),
        summary: '${pet.name} 最近状态有波动，但整体仍在可观察范围内。',
        note: '记录 ${pet.name} 的饮食、耳道、运动、排便和情绪变化，给 AI 做季度总结。',
      ),
    );
  }

  return AiGenerationContext(
    title: '最近 3 个月的总结',
    rangeLabel: '最近 3 个月',
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    languageTag: 'zh-CN',
    pets: pets,
    todos: todos,
    reminders: reminders,
    records: records,
  );
}

class _RecordingAiHttpTransport implements AiHttpTransport {
  _RecordingAiHttpTransport({AiHttpTransport? delegate})
      : _delegate = delegate ?? HttpClientAiHttpTransport();

  final AiHttpTransport _delegate;
  final requests = <AiHttpRequest>[];
  final responses = <AiHttpResponse>[];

  int? get lastRequestMaxTokens {
    if (requests.isEmpty) {
      return null;
    }
    final body = jsonDecode(requests.last.body ?? '{}');
    if (body is! Map<String, dynamic>) {
      return null;
    }
    return body['max_tokens'] as int?;
  }

  @override
  Future<AiHttpResponse> send(AiHttpRequest request) async {
    requests.add(request);
    final startedAt = DateTime.now();
    final response = await _delegate.send(request);
    responses.add(response);
    final elapsed = DateTime.now().difference(startedAt);
    final summary = _summarizeChatCompletion(response.body);
    // ignore: avoid_print
    print(
      '[Cloudflare Workers AI live response] '
      '${jsonEncode({
            'uri': _redactCloudflareAccount(request.uri),
            'statusCode': response.statusCode,
            'elapsedMs': elapsed.inMilliseconds,
            'finishReason': summary.finishReason,
            'contentLength': summary.contentLength,
            'bodyPreview': _preview(response.body),
          })}',
    );
    return response;
  }
}

_ChatCompletionSummary _summarizeChatCompletion(String body) {
  final decoded = _tryDecodeJson(body);
  if (decoded is! Map<String, dynamic>) {
    return const _ChatCompletionSummary();
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    return const _ChatCompletionSummary();
  }
  final firstChoice = Map<String, dynamic>.from(choices.first as Map);
  final message = firstChoice['message'];
  final content = message is Map ? message['content'] : null;
  final normalizedContent = content is String ? content : jsonEncode(content);
  return _ChatCompletionSummary(
    finishReason: firstChoice['finish_reason'] as String?,
    contentLength: normalizedContent.length,
  );
}

Object? _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

String _redactCloudflareAccount(Uri uri) {
  final segments = uri.pathSegments.toList(growable: false);
  final accountIndex = segments.indexOf('accounts');
  if (accountIndex == -1 || accountIndex + 1 >= segments.length) {
    return uri.toString();
  }
  final redactedSegments = [...segments];
  redactedSegments[accountIndex + 1] = '<account>';
  return uri.replace(pathSegments: redactedSegments).toString();
}

String _preview(String value, {int maxLength = 360}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}

class _ChatCompletionSummary {
  const _ChatCompletionSummary({
    this.finishReason,
    this.contentLength = 0,
  });

  final String? finishReason;
  final int contentLength;
}
