import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/state/app_settings_controller.dart';

class AiSettingsCoordinator {
  const AiSettingsCoordinator({
    required this.settingsController,
    required this.secretStore,
    required this.connectionTester,
  });

  final AppSettingsController settingsController;
  final AiSecretStore secretStore;
  final AiConnectionTester connectionTester;

  Future<bool> isSecretStoreAvailable() {
    return secretStore.isAvailable();
  }

  Future<bool> hasSavedKey(String configId) async {
    final states = await savedKeyStates([configId]);
    return states[configId] ?? false;
  }

  Future<Map<String, bool>> savedKeyStates(Iterable<String> configIds) {
    return secretStore.hasKeys(configIds);
  }

  Future<void> saveConfig({
    required AiProviderConfig config,
    String? apiKey,
  }) async {
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await secretStore.writeKey(config.id, apiKey.trim());
    }
    await settingsController.upsertAiProviderConfig(config);
  }

  Future<void> deleteConfig(String configId) async {
    await secretStore.deleteKey(configId);
    await settingsController.deleteAiProviderConfig(configId);
  }

  Future<AiConnectionTestResult> testConnection({
    required AiProviderType providerType,
    required String baseUrl,
    required String model,
    required String? apiKey,
    String? existingConfigId,
  }) async {
    final resolvedKey = apiKey?.trim().isNotEmpty == true
        ? apiKey!.trim()
        : (existingConfigId == null
            ? null
            : await secretStore.readKey(existingConfigId));
    if (resolvedKey == null || resolvedKey.isEmpty) {
      return const AiConnectionTestResult(
        status: AiConnectionStatus.invalidKey,
        message: '请先填写 API Key。',
      );
    }
    return connectionTester.testConnection(
      providerType: providerType,
      baseUrl: baseUrl,
      model: model,
      apiKey: resolvedKey,
    );
  }
}
