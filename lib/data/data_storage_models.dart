import 'dart:convert';

import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/state/petnote_store.dart';

enum PetNoteDataPackageType { backup }

class DataExportOptions {
  const DataExportOptions({
    this.includeSensitiveSettings = false,
  });

  final bool includeSensitiveSettings;
}

enum DataOperationKind {
  backupExported,
  importedReplace,
  cleared,
  validationFailed,
}

class DataImportOptions {
  const DataImportOptions({
    this.restoreSettings = false,
    this.restoreSensitiveSettings = false,
  });

  final bool restoreSettings;
  final bool restoreSensitiveSettings;
}

class PetNoteDataState {
  const PetNoteDataState({
    required this.pets,
    required this.todos,
    required this.reminders,
    required this.records,
  });

  final List<Pet> pets;
  final List<TodoItem> todos;
  final List<ReminderItem> reminders;
  final List<PetRecord> records;

  int get totalCount =>
      pets.length + todos.length + reminders.length + records.length;

  Map<String, dynamic> toJson() {
    return {
      'pets': pets.map((pet) => pet.toJson()).toList(),
      'todos': todos.map((item) => item.toJson()).toList(),
      'reminders': reminders.map((item) => item.toJson()).toList(),
      'records': records.map((item) => item.toJson()).toList(),
    };
  }

  factory PetNoteDataState.fromJson(Map<String, dynamic> json) {
    return PetNoteDataState(
      pets: _decodeList(json['pets'], Pet.fromJson),
      todos: _decodeList(json['todos'], TodoItem.fromJson),
      reminders: _decodeList(json['reminders'], ReminderItem.fromJson),
      records: _decodeList(json['records'], PetRecord.fromJson),
    );
  }
}

class PetNoteSettingsState {
  const PetNoteSettingsState({
    required this.themePreferenceName,
    required this.aiProviderConfigs,
    required this.activeAiProviderConfigId,
  });

  final String themePreferenceName;
  final List<AiProviderConfig> aiProviderConfigs;
  final String? activeAiProviderConfigId;

  Map<String, dynamic> toJson() {
    return {
      'themePreferenceName': themePreferenceName,
      'aiProviderConfigs':
          aiProviderConfigs.map((config) => config.toJson()).toList(),
      'activeAiProviderConfigId': activeAiProviderConfigId,
    };
  }

  factory PetNoteSettingsState.fromJson(Map<String, dynamic> json) {
    final rawConfigs = json['aiProviderConfigs'];
    return PetNoteSettingsState(
      themePreferenceName: json['themePreferenceName'] as String? ?? 'system',
      aiProviderConfigs: rawConfigs is List
          ? rawConfigs
              .whereType<Map>()
              .map((item) => AiProviderConfig.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const <AiProviderConfig>[],
      activeAiProviderConfigId: json['activeAiProviderConfigId'] as String?,
    );
  }
}

class PetNoteAiSecretSnapshot {
  const PetNoteAiSecretSnapshot({
    required this.configId,
    required this.apiKey,
  });

  final String configId;
  final String apiKey;

  Map<String, dynamic> toJson() {
    return {
      'configId': configId,
      'apiKey': apiKey,
    };
  }

  factory PetNoteAiSecretSnapshot.fromJson(Map<String, dynamic> json) {
    return PetNoteAiSecretSnapshot(
      configId: json['configId'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
    );
  }
}

class PetNoteSensitiveSettingsState {
  const PetNoteSensitiveSettingsState({
    required this.aiSecrets,
  });

  final List<PetNoteAiSecretSnapshot> aiSecrets;

  bool get hasSecrets => aiSecrets.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'aiSecrets': aiSecrets.map((secret) => secret.toJson()).toList(),
    };
  }

  factory PetNoteSensitiveSettingsState.fromJson(Map<String, dynamic> json) {
    final rawSecrets = json['aiSecrets'];
    return PetNoteSensitiveSettingsState(
      aiSecrets: rawSecrets is List
          ? rawSecrets
              .whereType<Map>()
              .map((item) => PetNoteAiSecretSnapshot.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const <PetNoteAiSecretSnapshot>[],
    );
  }
}

class PetNoteDataPackage {
  const PetNoteDataPackage({
    required this.schemaVersion,
    required this.packageType,
    required this.packageName,
    required this.description,
    required this.createdAt,
    required this.appVersion,
    required this.data,
    required this.settings,
    this.sensitiveSettings,
    required this.meta,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final PetNoteDataPackageType packageType;
  final String packageName;
  final String description;
  final DateTime createdAt;
  final String appVersion;
  final PetNoteDataState data;
  final PetNoteSettingsState? settings;
  final PetNoteSensitiveSettingsState? sensitiveSettings;
  final Map<String, Object?> meta;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'packageType': packageType.name,
      'packageName': packageName,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'appVersion': appVersion,
      'data': data.toJson(),
      'settings': settings?.toJson(),
      'sensitiveSettings': sensitiveSettings?.toJson(),
      'meta': meta,
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  factory PetNoteDataPackage.fromJson(Map<String, dynamic> json) {
    return PetNoteDataPackage(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      packageType: _packageTypeFromName(json['packageType'] as String?),
      packageName: json['packageName'] as String? ?? '未命名数据包',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: json['appVersion'] as String? ?? 'unknown',
      data: PetNoteDataState.fromJson(
        Map<String, dynamic>.from(
          (json['data'] as Map?) ?? const <String, Object?>{},
        ),
      ),
      settings: json['settings'] is Map
          ? PetNoteSettingsState.fromJson(
              Map<String, dynamic>.from(json['settings'] as Map),
            )
          : null,
      sensitiveSettings: json['sensitiveSettings'] is Map
          ? PetNoteSensitiveSettingsState.fromJson(
              Map<String, dynamic>.from(json['sensitiveSettings'] as Map),
            )
          : null,
      meta: json['meta'] is Map
          ? Map<String, Object?>.from(json['meta'] as Map)
          : const <String, Object?>{},
    );
  }
}

class DataOperationResult {
  const DataOperationResult({
    required this.kind,
    required this.isSuccess,
    required this.message,
    required this.snapshotCreated,
    required this.restoredSettings,
    required this.packageType,
    required this.petsCount,
    required this.todosCount,
    required this.remindersCount,
    required this.recordsCount,
  });

  final DataOperationKind kind;
  final bool isSuccess;
  final String message;
  final bool snapshotCreated;
  final bool restoredSettings;
  final PetNoteDataPackageType? packageType;
  final int petsCount;
  final int todosCount;
  final int remindersCount;
  final int recordsCount;

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'isSuccess': isSuccess,
      'message': message,
      'snapshotCreated': snapshotCreated,
      'restoredSettings': restoredSettings,
      'packageType': packageType?.name,
      'petsCount': petsCount,
      'todosCount': todosCount,
      'remindersCount': remindersCount,
      'recordsCount': recordsCount,
    };
  }

  factory DataOperationResult.fromJson(Map<String, dynamic> json) {
    return DataOperationResult(
      kind: _dataOperationKindFromName(json['kind'] as String?),
      isSuccess: json['isSuccess'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      snapshotCreated: json['snapshotCreated'] as bool? ?? false,
      restoredSettings: json['restoredSettings'] as bool? ?? false,
      packageType: json['packageType'] == null
          ? null
          : _packageTypeFromName(json['packageType'] as String?),
      petsCount: (json['petsCount'] as num?)?.toInt() ?? 0,
      todosCount: (json['todosCount'] as num?)?.toInt() ?? 0,
      remindersCount: (json['remindersCount'] as num?)?.toInt() ?? 0,
      recordsCount: (json['recordsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

List<T> _decodeList<T>(
  Object? rawValue,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (rawValue is! List) {
    return <T>[];
  }
  return rawValue
      .whereType<Map>()
      .map((item) => fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

PetNoteDataPackageType _packageTypeFromName(String? value) {
  return PetNoteDataPackageType.backup;
}

DataOperationKind _dataOperationKindFromName(String? value) {
  return switch (value) {
    'importedReplace' => DataOperationKind.importedReplace,
    'importedAppend' => DataOperationKind.importedReplace,
    'cleared' => DataOperationKind.cleared,
    'restoredSnapshot' => DataOperationKind.importedReplace,
    'validationFailed' => DataOperationKind.validationFailed,
    _ => DataOperationKind.backupExported,
  };
}
