import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/platform/pet_photo_path_resolver.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncMergeSide { local, remote }

class SyncMergeConflict {
  const SyncMergeConflict({
    required this.collectionLabel,
    required this.id,
    required this.localLabel,
    required this.remoteLabel,
    this.differences = const <SyncMergeDifference>[],
  });

  final String collectionLabel;
  final String id;
  final String localLabel;
  final String remoteLabel;
  final List<SyncMergeDifference> differences;
}

class SyncMergeDifference {
  const SyncMergeDifference({
    required this.fieldPath,
    required this.localValue,
    required this.remoteValue,
  });

  final String fieldPath;
  final Object? localValue;
  final Object? remoteValue;
}

typedef SyncMergeConflictResolver = Future<SyncMergeSide> Function(
  SyncMergeConflict conflict,
);

enum ReminderKind { vaccine, deworming, medication, review, grooming, custom }

enum ReminderStatus { pending, done, skipped, postponed, overdue }

enum TodoStatus { open, done, skipped, postponed, overdue }

enum NotificationLeadTime {
  none,
  fiveMinutes,
  fifteenMinutes,
  oneHour,
  oneDay,
  threeDays,
  sevenDays,
}

enum PetRecordType { medical, receipt, image, testResult, other }

enum RecordPurpose { health, life, expense, other }

enum OverviewRange {
  sevenDays,
  oneMonth,
  threeMonths,
  sixMonths,
  oneYear,
  custom,
}

enum AppTab { checklist, overview, pets, me }

enum PetType { cat, dog, rabbit, bird, other }

enum PetNeuterStatus { neutered, notNeutered, unknown }

enum OverviewAiReportStatus { idle, loading, ready, error }

enum SemanticTopicKey {
  hydration,
  diet,
  deworming,
  litter,
  grooming,
  earCare,
  medication,
  vaccine,
  review,
  weight,
  digestive,
  skin,
  purchase,
  cleaning,
  other,
}

enum SemanticSignal {
  stable,
  improved,
  worsened,
  attention,
  completed,
  missed,
  scheduled,
  info,
}

enum SemanticActionIntent {
  observe,
  administer,
  buy,
  clean,
  record,
  review,
  custom,
}

enum SemanticEvidenceSource { home, vet, lab, receipt, other }

typedef OverviewAiReportGenerator = Future<AiCareReport> Function(
  AiGenerationContext context, {
  bool forceRefresh,
});

class SemanticMeasurement {
  const SemanticMeasurement({
    required this.key,
    required this.value,
    required this.unit,
  });

  final String key;
  final String value;
  final String unit;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
      'unit': unit,
    };
  }

  factory SemanticMeasurement.fromJson(Map<String, dynamic> json) {
    return SemanticMeasurement(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
    );
  }
}

class SemanticEventDetails {
  const SemanticEventDetails({
    required this.topicKey,
    required this.signal,
    required this.tags,
    required this.evidenceSummary,
    required this.actionSummary,
    required this.followUpAt,
    required this.measurements,
    this.intent,
    this.source,
  });

  final SemanticTopicKey topicKey;
  final SemanticSignal signal;
  final List<String> tags;
  final String evidenceSummary;
  final String actionSummary;
  final DateTime? followUpAt;
  final List<SemanticMeasurement> measurements;
  final SemanticActionIntent? intent;
  final SemanticEvidenceSource? source;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'topicKey': topicKey.name,
      'signal': signal.name,
      'tags': tags,
      'evidenceSummary': evidenceSummary,
      'actionSummary': actionSummary,
      'measurements': measurements.map((item) => item.toJson()).toList(),
    };
    if (followUpAt != null) {
      json['followUpAt'] = followUpAt!.toIso8601String();
    }
    if (intent != null) {
      json['intent'] = intent!.name;
    }
    if (source != null) {
      json['source'] = source!.name;
    }
    return json;
  }

  factory SemanticEventDetails.fromJson(Map<String, dynamic> json) {
    final rawMeasurements = json['measurements'];
    return SemanticEventDetails(
      topicKey: _semanticTopicKeyFromName(json['topicKey'] as String?),
      signal: _semanticSignalFromName(json['signal'] as String?),
      tags: (json['tags'] as List?)
              ?.whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(3)
              .toList(growable: false) ??
          const <String>[],
      evidenceSummary: json['evidenceSummary'] as String? ?? '',
      actionSummary: json['actionSummary'] as String? ?? '',
      followUpAt: DateTime.tryParse(json['followUpAt'] as String? ?? ''),
      measurements: rawMeasurements is List
          ? rawMeasurements
              .whereType<Map>()
              .map((item) => SemanticMeasurement.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .where((item) => item.key.isNotEmpty)
              .toList(growable: false)
          : const <SemanticMeasurement>[],
      intent: _semanticActionIntentFromName(json['intent'] as String?),
      source: _semanticEvidenceSourceFromName(json['source'] as String?),
    );
  }
}

class Pet {
  Pet({
    required this.id,
    required this.name,
    required this.avatarText,
    this.photoPath,
    required this.type,
    required this.breed,
    required this.sex,
    required this.birthday,
    required this.ageLabel,
    required this.weightKg,
    required this.neuterStatus,
    required this.feedingPreferences,
    required this.allergies,
    required this.note,
  });

  final String id;
  final String name;
  final String avatarText;
  final String? photoPath;
  final PetType type;
  final String breed;
  final String sex;
  final String birthday;
  final String ageLabel;
  final double weightKg;
  final PetNeuterStatus neuterStatus;
  final String feedingPreferences;
  final String allergies;
  final String note;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarText': avatarText,
      'photoPath': photoPath,
      'type': type.name,
      'breed': breed,
      'sex': sex,
      'birthday': birthday,
      'ageLabel': ageLabel,
      'weightKg': weightKg,
      'neuterStatus': neuterStatus.name,
      'feedingPreferences': feedingPreferences,
      'allergies': allergies,
      'note': note,
    };
  }

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarText: json['avatarText'] as String,
      photoPath: json['photoPath'] as String?,
      type: _petTypeFromName(json['type'] as String?),
      breed: json['breed'] as String,
      sex: json['sex'] as String,
      birthday: json['birthday'] as String,
      ageLabel: json['ageLabel'] as String? ?? '新加入',
      weightKg: (json['weightKg'] as num).toDouble(),
      neuterStatus: _petNeuterStatusFromName(json['neuterStatus'] as String?),
      feedingPreferences: json['feedingPreferences'] as String? ?? '未填写',
      allergies: json['allergies'] as String? ?? '未填写',
      note: json['note'] as String? ?? '未填写',
    );
  }
}

class TodoItem {
  TodoItem({
    required this.id,
    required this.petId,
    required this.title,
    required this.dueAt,
    required this.notificationLeadTime,
    required this.status,
    required this.note,
    this.semantic,
  });

  final String id;
  final String petId;
  final String title;
  DateTime dueAt;
  NotificationLeadTime notificationLeadTime;
  TodoStatus status;
  final String note;
  final SemanticEventDetails? semantic;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'petId': petId,
      'title': title,
      'dueAt': dueAt.toIso8601String(),
      'notificationLeadTime': notificationLeadTime.name,
      'status': status.name,
      'note': note,
      'semantic': semantic?.toJson(),
    };
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      petId: json['petId'] as String,
      title: json['title'] as String,
      dueAt: DateTime.parse(json['dueAt'] as String),
      notificationLeadTime: _notificationLeadTimeFromName(
          json['notificationLeadTime'] as String?),
      status: _todoStatusFromName(json['status'] as String?),
      note: json['note'] as String? ?? '',
      semantic: json['semantic'] is Map
          ? SemanticEventDetails.fromJson(
              Map<String, dynamic>.from(json['semantic'] as Map),
            )
          : null,
    );
  }
}

class ReminderItem {
  ReminderItem({
    required this.id,
    required this.petId,
    required this.kind,
    required this.title,
    required this.scheduledAt,
    required this.notificationLeadTime,
    required this.recurrence,
    required this.status,
    required this.note,
    this.semantic,
  });

  final String id;
  final String petId;
  final ReminderKind kind;
  final String title;
  DateTime scheduledAt;
  NotificationLeadTime notificationLeadTime;
  final String recurrence;
  ReminderStatus status;
  final String note;
  final SemanticEventDetails? semantic;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'petId': petId,
      'kind': kind.name,
      'title': title,
      'scheduledAt': scheduledAt.toIso8601String(),
      'notificationLeadTime': notificationLeadTime.name,
      'recurrence': recurrence,
      'status': status.name,
      'note': note,
      'semantic': semantic?.toJson(),
    };
  }

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      id: json['id'] as String,
      petId: json['petId'] as String,
      kind: _reminderKindFromName(json['kind'] as String?),
      title: json['title'] as String,
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      notificationLeadTime: _notificationLeadTimeFromName(
          json['notificationLeadTime'] as String?),
      recurrence: json['recurrence'] as String? ?? '单次',
      status: _reminderStatusFromName(json['status'] as String?),
      note: json['note'] as String? ?? '',
      semantic: json['semantic'] is Map
          ? SemanticEventDetails.fromJson(
              Map<String, dynamic>.from(json['semantic'] as Map),
            )
          : null,
    );
  }
}

class PetRecord {
  PetRecord({
    required this.id,
    required this.petId,
    required this.type,
    required this.title,
    required this.recordDate,
    required this.summary,
    required this.note,
    this.purpose,
    this.customPurposeLabel,
    this.photoPaths = const <String>[],
    this.semantic,
  });

  final String id;
  final String petId;
  final PetRecordType type;
  final String title;
  final DateTime recordDate;
  final String summary;
  final String note;
  final RecordPurpose? purpose;
  final String? customPurposeLabel;
  final List<String> photoPaths;
  final SemanticEventDetails? semantic;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'petId': petId,
      'type': type.name,
      'title': title,
      'recordDate': recordDate.toIso8601String(),
      'summary': summary,
      'note': note,
      'purpose': purpose?.name,
      'customPurposeLabel': customPurposeLabel,
      'photoPaths': photoPaths,
      'semantic': semantic?.toJson(),
    };
  }

  factory PetRecord.fromJson(Map<String, dynamic> json) {
    return PetRecord(
      id: json['id'] as String,
      petId: json['petId'] as String,
      type: _petRecordTypeFromName(json['type'] as String?),
      title: json['title'] as String,
      recordDate: DateTime.parse(json['recordDate'] as String),
      summary: json['summary'] as String? ?? '',
      note: json['note'] as String? ?? '',
      purpose: _recordPurposeFromName(json['purpose'] as String?),
      customPurposeLabel:
          ((json['customPurposeLabel'] as String?) ?? '').trim().isEmpty
              ? null
              : (json['customPurposeLabel'] as String).trim(),
      photoPaths: (json['photoPaths'] as List?)
              ?.whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      semantic: json['semantic'] is Map
          ? SemanticEventDetails.fromJson(
              Map<String, dynamic>.from(json['semantic'] as Map),
            )
          : null,
    );
  }
}

class ChecklistItemViewModel {
  ChecklistItemViewModel({
    required this.id,
    required this.sourceType,
    required this.petId,
    required this.petName,
    required this.petAvatarText,
    required this.petAvatarPhotoPath,
    required this.title,
    required this.dueLabel,
    required this.statusLabel,
    required this.kindLabel,
    required this.note,
  });

  final String id;
  final String sourceType;
  final String petId;
  final String petName;
  final String petAvatarText;
  final String? petAvatarPhotoPath;
  final String title;
  final String dueLabel;
  final String statusLabel;
  final String kindLabel;
  final String note;
}

String petAvatarFallbackForPet(Pet pet) => switch (pet.type) {
      PetType.cat => '🐱',
      PetType.dog => '🐶',
      PetType.rabbit => '🐰',
      PetType.bird => '🐦',
      PetType.other => pet.avatarText,
    };

class ChecklistSection {
  ChecklistSection({
    required this.key,
    required this.title,
    required this.summary,
    required this.items,
  });

  final String key;
  final String title;
  final String summary;
  final List<ChecklistItemViewModel> items;
}

class OverviewSection {
  OverviewSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;
}

class OverviewSnapshot {
  OverviewSnapshot({
    required this.range,
    required this.sections,
    required this.disclaimer,
  });

  final OverviewRange range;
  final List<OverviewSection> sections;
  final String disclaimer;
}

class OverviewAiReportState {
  const OverviewAiReportState({
    this.status = OverviewAiReportStatus.idle,
    this.requestKey,
    this.rangeLabel,
    this.report,
    this.errorMessage,
    this.hasRequested = false,
    this.activeRequestToken = 0,
  });

  final OverviewAiReportStatus status;
  final String? requestKey;
  final String? rangeLabel;
  final AiCareReport? report;
  final String? errorMessage;
  final bool hasRequested;
  final int activeRequestToken;

  bool get isLoading => status == OverviewAiReportStatus.loading;
  bool get hasReport => report != null;
}

class OverviewAiHistoryEntry {
  const OverviewAiHistoryEntry({
    required this.requestKey,
    required this.rangeLabel,
    required this.report,
  });

  final String requestKey;
  final String rangeLabel;
  final AiCareReport report;
}

class OverviewAnalysisConfig {
  const OverviewAnalysisConfig({
    required this.range,
    required this.selectedPetIds,
    this.customRangeStart,
    this.customRangeEnd,
  });

  final OverviewRange range;
  final List<String> selectedPetIds;
  final DateTime? customRangeStart;
  final DateTime? customRangeEnd;
}

class _OverviewDataSlice {
  const _OverviewDataSlice({
    required this.todos,
    required this.reminders,
    required this.records,
  });

  final List<TodoItem> todos;
  final List<ReminderItem> reminders;
  final List<PetRecord> records;
}

class PetNoteStore extends ChangeNotifier {
  PetNoteStore._({
    List<Pet>? pets,
    List<TodoItem>? todos,
    List<ReminderItem>? reminders,
    List<PetRecord>? records,
    OverviewAnalysisConfig? overviewAnalysisConfig,
    OverviewAiReportState? overviewAiReportState,
    List<PetNoteMutation>? pendingMutations,
    PetNoteLocalStorage? storage,
    DateTime Function()? nowProvider,
    bool shouldAutoShowFirstLaunchIntro = true,
  })  : _storage = storage,
        _nowProvider = nowProvider ?? DateTime.now,
        _shouldAutoShowFirstLaunchIntro = shouldAutoShowFirstLaunchIntro {
    if (pets != null) {
      _pets.addAll(pets);
    }
    _rebuildPetIndex();
    if (todos != null) {
      _todos.addAll(todos);
    }
    _rebuildTodoIndex();
    if (reminders != null) {
      _reminders.addAll(reminders);
    }
    _rebuildReminderIndex();
    if (records != null) {
      _records.addAll(records);
    }
    _rebuildRecordIndex();
    if (overviewAnalysisConfig != null) {
      _overviewRange = overviewAnalysisConfig.range;
      _overviewCustomRangeStart = overviewAnalysisConfig.customRangeStart;
      _overviewCustomRangeEnd = overviewAnalysisConfig.customRangeEnd;
      _overviewSelectedPetIds.addAll(overviewAnalysisConfig.selectedPetIds);
    }
    if (_pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
      if (overviewAnalysisConfig == null && _overviewSelectedPetIds.isEmpty) {
        _overviewSelectedPetIds.addAll(_pets.map((pet) => pet.id));
      }
    }
    if (overviewAiReportState != null) {
      _restoreOverviewAiReportState(overviewAiReportState);
    }
    if (pendingMutations != null) {
      for (final mutation in pendingMutations) {
        _pendingLocalMutations[mutation.id] = mutation;
      }
    }
    _refreshPersistedTableSnapshots();
  }

  factory PetNoteStore.seeded({
    DateTime Function()? nowProvider,
  }) {
    return PetNoteStore._(
      nowProvider:
          nowProvider ?? () => DateTime.parse('2026-03-24T12:00:00+08:00'),
      shouldAutoShowFirstLaunchIntro: false,
      pets: [
        Pet(
          id: 'pet-1',
          name: 'Luna',
          avatarText: 'LU',
          type: PetType.cat,
          breed: 'British Shorthair',
          sex: 'Female',
          birthday: '2023-04-18',
          ageLabel: '2岁',
          weightKg: 4.6,
          neuterStatus: PetNeuterStatus.neutered,
          feedingPreferences: '早晚各一餐，冻干拌主粮',
          allergies: '对鸡肉敏感',
          note: '洗澡后容易紧张，需要安抚。',
        ),
        Pet(
          id: 'pet-2',
          name: 'Milo',
          avatarText: 'MI',
          type: PetType.dog,
          breed: 'Corgi',
          sex: 'Male',
          birthday: '2022-09-05',
          ageLabel: '3岁',
          weightKg: 11.2,
          neuterStatus: PetNeuterStatus.notNeutered,
          feedingPreferences: '散步后补水，晚饭分两次喂',
          allergies: '无已知过敏',
          note: '喜欢追球，驱虫后食欲会下降半天。',
        ),
      ],
      todos: [
        TodoItem(
          id: 'todo-1',
          petId: 'pet-1',
          title: '补充冻干库存',
          dueAt: DateTime.parse('2026-03-24T18:00:00+08:00'),
          notificationLeadTime: NotificationLeadTime.none,
          status: TodoStatus.open,
          note: '检查低敏口味。',
        ),
        TodoItem(
          id: 'todo-2',
          petId: 'pet-2',
          title: '周末修剪指甲',
          dueAt: DateTime.parse('2026-03-27T10:00:00+08:00'),
          notificationLeadTime: NotificationLeadTime.none,
          status: TodoStatus.postponed,
          note: '准备零食安抚。',
        ),
        TodoItem(
          id: 'todo-3',
          petId: 'pet-2',
          title: '清洗牵引绳',
          dueAt: DateTime.parse('2026-03-22T20:00:00+08:00'),
          notificationLeadTime: NotificationLeadTime.none,
          status: TodoStatus.overdue,
          note: '下雨后有泥点。',
        ),
      ],
      reminders: [
        ReminderItem(
          id: 'reminder-1',
          petId: 'pet-1',
          kind: ReminderKind.vaccine,
          title: '三联疫苗加强',
          scheduledAt: DateTime.parse('2026-03-30T09:30:00+08:00'),
          notificationLeadTime: NotificationLeadTime.oneDay,
          recurrence: '每年',
          status: ReminderStatus.pending,
          note: '提前准备免疫本。',
        ),
        ReminderItem(
          id: 'reminder-2',
          petId: 'pet-2',
          kind: ReminderKind.deworming,
          title: '体内驱虫',
          scheduledAt: DateTime.parse('2026-03-24T21:00:00+08:00'),
          notificationLeadTime: NotificationLeadTime.oneHour,
          recurrence: '每月',
          status: ReminderStatus.pending,
          note: '晚饭后服用。',
        ),
        ReminderItem(
          id: 'reminder-3',
          petId: 'pet-2',
          kind: ReminderKind.review,
          title: '皮肤复查',
          scheduledAt: DateTime.parse('2026-03-20T14:00:00+08:00'),
          notificationLeadTime: NotificationLeadTime.none,
          recurrence: '单次',
          status: ReminderStatus.done,
          note: '带上上次化验单。',
        ),
      ],
      records: [
        PetRecord(
          id: 'record-1',
          petId: 'pet-1',
          type: PetRecordType.medical,
          title: '耳道清洁复诊',
          recordDate: DateTime.parse('2026-03-21T10:30:00+08:00'),
          summary: '医生建议一周后继续观察，没有感染迹象。',
          note: '继续减少洗澡频率。',
        ),
        PetRecord(
          id: 'record-2',
          petId: 'pet-2',
          type: PetRecordType.testResult,
          title: '皮肤镜检查',
          recordDate: DateTime.parse('2026-03-20T15:20:00+08:00'),
          summary: '真菌风险低，建议继续控油洗护。',
          note: '下次复查前减少零食。',
        ),
        PetRecord(
          id: 'record-3',
          petId: 'pet-2',
          type: PetRecordType.receipt,
          title: '洗护消费小票',
          recordDate: DateTime.parse('2026-02-28T18:00:00+08:00'),
          summary: '包含洗护和耳部护理。',
          note: '对比上次价格上涨 10 元。',
        ),
      ],
    );
  }

  static Future<PetNoteStore> load({
    Future<SharedPreferences> Function()? preferencesLoader,
    PetNoteLocalStorage? storage,
    DateTime Function()? nowProvider,
    Future<String?> Function()? appSupportDirectoryLoader,
  }) async {
    final localStorage = storage ??
        await PetNoteLocalStorage.load(
          preferencesLoader: preferencesLoader,
          timeout: _preferencesLoadTimeout,
        );
    final store = PetNoteStore._(
      storage: localStorage,
      nowProvider: nowProvider,
      shouldAutoShowFirstLaunchIntro:
          localStorage?.readBool(_firstLaunchIntroAutoEnabledKey) ?? true,
      pets: _decodePetsFromStorage(localStorage),
      todos: _decodeTodosFromStorage(localStorage),
      reminders: _decodeRemindersFromStorage(localStorage),
      records: _decodeRecordsFromStorage(localStorage),
      overviewAnalysisConfig: _decodeOverviewAnalysisConfig(
        localStorage?.readTable(PetNoteLocalTable.overviewConfig),
      ),
      overviewAiReportState: _decodeOverviewAiReportState(
        localStorage?.readTable(PetNoteLocalTable.overviewAiReport),
      ),
      pendingMutations: _decodePendingMutationsFromStorage(localStorage),
    );
    final migratedSemanticData = store._migrateLegacySemanticData();
    String? petPhotoDirectoryPath;
    if (store._needsLegacyPetPhotoPathMigration()) {
      petPhotoDirectoryPath =
          await PetPhotoPathResolver.loadAndCachePetPhotoDirectoryPath(
        appSupportDirectoryLoader: appSupportDirectoryLoader,
      );
    }
    final migratedPetPhotoPaths =
        store._migrateLegacyPetPhotoPaths(petPhotoDirectoryPath);
    if (migratedSemanticData || migratedPetPhotoPaths) {
      await store._saveState(
        pets: migratedPetPhotoPaths,
        todos: migratedSemanticData,
        reminders: migratedSemanticData,
        records: migratedSemanticData,
        overviewAiReport: true,
      );
    }
    return store;
  }

  static const String _firstLaunchIntroAutoEnabledKey =
      'first_launch_intro_auto_enabled_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  final List<Pet> _pets = [];
  final Map<String, Pet> _petsById = <String, Pet>{};
  final List<TodoItem> _todos = [];
  final Map<String, TodoItem> _todosById = <String, TodoItem>{};
  final List<ReminderItem> _reminders = [];
  final Map<String, ReminderItem> _remindersById = <String, ReminderItem>{};
  final List<PetRecord> _records = [];
  final Map<String, PetRecord> _recordsById = <String, PetRecord>{};
  final DateTime Function() _nowProvider;
  final PetNoteLocalStorage? _storage;
  final StreamController<PetNoteMutation> _localMutations =
      StreamController<PetNoteMutation>.broadcast();
  final Map<String, PetNoteMutation> _pendingLocalMutations =
      <String, PetNoteMutation>{};
  final Map<PetNoteLocalTable, String?> _persistedTableSnapshots =
      <PetNoteLocalTable, String?>{};
  Future<void> Function()? _notificationSyncHandler;
  Timer? _timeDerivedDataTimer;
  int? _timeDerivedDataMinuteStamp;
  List<ChecklistSection>? _checklistSectionsCache;
  int? _checklistSectionsCacheMinuteStamp;
  OverviewSnapshot? _overviewSnapshotCache;
  int? _overviewSnapshotCacheMinuteStamp;
  _OverviewDataSlice? _overviewDataSliceCache;
  String? _overviewDataSliceCacheKey;
  bool _overviewEntityStorageFresh = true;
  String? _remindersForSelectedPetCachePetId;
  List<ReminderItem>? _remindersForSelectedPetCache;
  final Map<String, List<PetRecord>> _recordsByPetIdCache =
      <String, List<PetRecord>>{};
  OverviewAiReportState _overviewAiReportState = const OverviewAiReportState();
  int _overviewAiRequestToken = 0;
  int _notificationSyncVersion = 0;
  int _dataResetVersion = 0;
  var _applyingRemoteMutationDepth = 0;
  ({AppTab activeTab, String selectedPetId})? _remoteNavigationState;

  AppTab _activeTab = AppTab.checklist;
  OverviewRange _overviewRange = OverviewRange.sevenDays;
  DateTime? _overviewCustomRangeStart;
  DateTime? _overviewCustomRangeEnd;
  final List<String> _overviewSelectedPetIds = <String>[];
  String _selectedPetId = '';
  bool _shouldAutoShowFirstLaunchIntro;

  AppTab get activeTab => _activeTab;
  String get selectedPetId => _selectedPetId;
  OverviewRange get overviewRange => _overviewRange;
  List<String> get overviewSelectedPetIds =>
      List<String>.unmodifiable(_effectiveOverviewSelectedPetIds());
  DateTime? get overviewCustomRangeStart => _overviewCustomRangeStart;
  DateTime? get overviewCustomRangeEnd => _overviewCustomRangeEnd;
  OverviewAnalysisConfig get overviewAnalysisConfig => OverviewAnalysisConfig(
        range: _overviewRange,
        selectedPetIds: overviewSelectedPetIds,
        customRangeStart: _overviewCustomRangeStart,
        customRangeEnd: _overviewCustomRangeEnd,
      );
  OverviewAiReportState get overviewAiReportState => _overviewAiReportState;
  List<OverviewAiHistoryEntry> get overviewAiHistory {
    final requestKey = _overviewAiReportState.requestKey;
    final report = _overviewAiReportState.report;
    if (requestKey == null || requestKey.isEmpty || report == null) {
      return const <OverviewAiHistoryEntry>[];
    }
    return <OverviewAiHistoryEntry>[
      OverviewAiHistoryEntry(
        requestKey: requestKey,
        rangeLabel: _overviewAiHistoryLabelFromRequestKey(requestKey),
        report: report,
      ),
    ];
  }

  List<Pet> get pets => List<Pet>.unmodifiable(_pets);
  List<TodoItem> get todos => List<TodoItem>.unmodifiable(_todos);
  List<ReminderItem> get reminders =>
      List<ReminderItem>.unmodifiable(_reminders);
  List<PetRecord> get records => List<PetRecord>.unmodifiable(_records);
  bool get shouldAutoShowFirstLaunchIntro => _shouldAutoShowFirstLaunchIntro;
  int get notificationSyncVersion => _notificationSyncVersion;
  int get dataResetVersion => _dataResetVersion;
  DateTime get referenceNow => _referenceNow;
  Stream<PetNoteMutation> get localMutations => _localMutations.stream;
  List<PetNoteMutation> get pendingLocalMutations =>
      List<PetNoteMutation>.unmodifiable(_pendingLocalMutations.values);

  void setNotificationSyncHandler(Future<void> Function()? handler) {
    _notificationSyncHandler = handler;
  }

  void startTimeDerivedDataRefresh() {
    _timeDerivedDataMinuteStamp = _minuteStamp(_referenceNow);
    _scheduleNextTimeDerivedDataRefresh();
  }

  void stopTimeDerivedDataRefresh() {
    _timeDerivedDataTimer?.cancel();
    _timeDerivedDataTimer = null;
    _timeDerivedDataMinuteStamp = null;
  }

  @override
  void dispose() {
    stopTimeDerivedDataRefresh();
    _localMutations.close();
    super.dispose();
  }

  @override
  void notifyListeners() {
    final navigationState = _remoteNavigationState;
    if (navigationState != null) {
      _restoreNavigationState(navigationState);
    }
    super.notifyListeners();
  }

  Pet? get selectedPet {
    return _findPet(_selectedPetId);
  }

  TodoItem? todoById(String todoId) => _todosById[todoId];

  ReminderItem? reminderById(String reminderId) => _remindersById[reminderId];

  PetRecord? recordById(String recordId) => _recordsById[recordId];

  List<ReminderItem> get remindersForSelectedPet {
    final cached = _remindersForSelectedPetCache;
    if (cached != null &&
        _remindersForSelectedPetCachePetId == _selectedPetId) {
      return cached;
    }

    final results = _reminders
        .where((reminder) => reminder.petId == _selectedPetId)
        .toList();
    results.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final cachedResults = List<ReminderItem>.unmodifiable(results);
    _remindersForSelectedPetCachePetId = _selectedPetId;
    _remindersForSelectedPetCache = cachedResults;
    return cachedResults;
  }

  List<PetRecord> get recordsForSelectedPet {
    return recordsForPet(_selectedPetId);
  }

  List<PetRecord> recordsForPet(String petId) {
    final cached = _recordsByPetIdCache[petId];
    if (cached != null) {
      return cached;
    }

    final results = _records.where((record) => record.petId == petId).toList();
    results.sort((a, b) => b.recordDate.compareTo(a.recordDate));
    final cachedResults = List<PetRecord>.unmodifiable(results);
    _recordsByPetIdCache[petId] = cachedResults;
    return cachedResults;
  }

  List<ChecklistSection> get checklistSections {
    final referenceNow = _referenceNow;
    final minuteStamp = _minuteStamp(referenceNow);
    final cached = _checklistSectionsCache;
    if (cached != null && _checklistSectionsCacheMinuteStamp == minuteStamp) {
      return cached;
    }

    final todayEnd = DateTime(
        referenceNow.year, referenceNow.month, referenceNow.day, 23, 59, 59);
    final today = <ChecklistItemViewModel>[];
    final upcoming = <ChecklistItemViewModel>[];
    final overdue = <ChecklistItemViewModel>[];
    final postponed = <ChecklistItemViewModel>[];
    final skipped = <ChecklistItemViewModel>[];

    for (final todo in _todos) {
      if (todo.status == TodoStatus.done) {
        continue;
      }
      final item = _todoToChecklistItem(todo);
      if (todo.status == TodoStatus.skipped) {
        skipped.add(item);
      } else if (todo.status == TodoStatus.postponed) {
        postponed.add(item);
      } else if (_effectiveTodoStatus(todo, referenceNow) ==
          TodoStatus.overdue) {
        overdue.add(item);
      } else if (!todo.dueAt.isAfter(todayEnd)) {
        today.add(item);
      } else {
        upcoming.add(item);
      }
    }

    for (final reminder in _reminders) {
      if (reminder.status == ReminderStatus.done) {
        continue;
      }
      final item = _reminderToChecklistItem(reminder);
      if (reminder.status == ReminderStatus.skipped) {
        skipped.add(item);
      } else if (reminder.status == ReminderStatus.postponed) {
        postponed.add(item);
      } else if (_effectiveReminderStatus(reminder, referenceNow) ==
          ReminderStatus.overdue) {
        overdue.add(item);
      } else if (!reminder.scheduledAt.isAfter(todayEnd)) {
        today.add(item);
      } else {
        upcoming.add(item);
      }
    }

    final sections = List<ChecklistSection>.unmodifiable([
      ChecklistSection(
          key: 'today',
          title: '今日待办',
          summary: '${today.length} 项',
          items: today),
      ChecklistSection(
          key: 'upcoming',
          title: '即将到期',
          summary: '${upcoming.length} 项',
          items: upcoming),
      ChecklistSection(
          key: 'overdue',
          title: '已逾期',
          summary: '${overdue.length} 项',
          items: overdue),
      ChecklistSection(
          key: 'postponed',
          title: '已延后',
          summary: '${postponed.length} 项',
          items: postponed),
      ChecklistSection(
          key: 'skipped',
          title: '已跳过',
          summary: '${skipped.length} 项',
          items: skipped),
    ]);
    _checklistSectionsCache = sections;
    _checklistSectionsCacheMinuteStamp = minuteStamp;
    return sections;
  }

  OverviewSnapshot get overviewSnapshot {
    final referenceNow = _referenceNow;
    final minuteStamp = _minuteStamp(referenceNow);
    final cached = _overviewSnapshotCache;
    if (cached != null && _overviewSnapshotCacheMinuteStamp == minuteStamp) {
      return cached;
    }

    final range = _resolveOverviewDateRange(referenceNow);
    final selectedPetIds = _effectiveOverviewSelectedPetIds().toSet();
    final slice = _overviewDataSlice(
      range: range,
      selectedPetIds: selectedPetIds,
      minuteStamp: minuteStamp,
    );
    final todos = slice.todos;
    final reminders = slice.reminders;
    final records = slice.records;

    final riskItems = <String>[];
    final overdueCount = todos
        .where((item) =>
            _effectiveTodoStatus(item, referenceNow) == TodoStatus.overdue)
        .length;
    final completedReminderCount =
        reminders.where((item) => item.status == ReminderStatus.done).length;
    final hasPendingReminder = reminders.any(
      (item) => item.status == ReminderStatus.pending,
    );
    if (overdueCount > 0) {
      riskItems.add('有 $overdueCount 条待办已逾期，建议尽快回到清单页处理。');
    }
    for (final pet in _pets.where((item) => selectedPetIds.contains(item.id))) {
      final hasRecord = records.any((record) => record.petId == pet.id);
      if (!hasRecord) {
        riskItems.add('${pet.name} 在当前区间没有新增记录，建议补充近况。');
      }
    }
    if (riskItems.isEmpty) {
      riskItems.add('当前没有明显风险信号，继续保持规律记录即可。');
    }

    final snapshot = OverviewSnapshot(
      range: _overviewRange,
      sections: [
        OverviewSection(
          title: '关键变化',
          items: [
            '最近新增 ${records.length} 条资料记录，覆盖 ${records.map((record) => record.petId).toSet().length} 只爱宠。',
            '待办 ${todos.length} 条，提醒 ${reminders.length} 条，日常照护节奏已经形成。',
            if (records.isNotEmpty)
              '${_petName(records.first.petId)} 最近新增了一条资料记录。',
          ],
        ),
        OverviewSection(
          title: '照护观察',
          items: [
            '已完成提醒 $completedReminderCount 次，关键健康节点有被跟进。',
            '当前逾期待办 $overdueCount 条，需要优先处理。',
            if (records.isNotEmpty)
              '最近一条记录是“${records.first.title}”，建议结合详情持续跟进。',
          ],
        ),
        OverviewSection(title: '风险提醒', items: riskItems),
        OverviewSection(
          title: '建议行动',
          items: [
            if (overdueCount > 0) '先处理已逾期待办，避免照护任务继续堆积。',
            if (records.isNotEmpty)
              '为 ${_petName(records.first.petId)} 整理最近一次资料记录的后续行动。',
            if (hasPendingReminder) '检查未来 7 天提醒分布，避免多个关键事项集中在同一天。',
            if (records.isEmpty) '保持每周至少补充 1 次记录，让总览建议更准确。',
          ],
        ),
      ],
      disclaimer: '仅供日常照护参考，不构成诊断或医疗建议，如有异常请及时咨询专业兽医。',
    );
    _overviewSnapshotCache = snapshot;
    _overviewSnapshotCacheMinuteStamp = minuteStamp;
    return snapshot;
  }

  AiGenerationContext buildOverviewAiGenerationContext() {
    final now = _referenceNow;
    final range = _resolveOverviewDateRange(now);
    final minuteStamp = _minuteStamp(now);
    final selectedPetIds = _effectiveOverviewSelectedPetIds().toSet();
    final selectedPets = _pets
        .where((pet) => selectedPetIds.contains(pet.id))
        .toList(growable: false);
    final slice = _overviewDataSlice(
      range: range,
      selectedPetIds: selectedPetIds,
      minuteStamp: minuteStamp,
    );

    return AiGenerationContext(
      title: _overviewTitle(_overviewRange),
      rangeLabel: _overviewRangeLabel(_overviewRange),
      rangeStart: range.start,
      rangeEnd: range.end,
      languageTag: 'zh-CN',
      pets: selectedPets,
      todos: slice.todos,
      reminders: slice.reminders,
      records: slice.records,
    );
  }

  _OverviewDataSlice _overviewDataSlice({
    required ({DateTime start, DateTime end}) range,
    required Set<String> selectedPetIds,
    required int minuteStamp,
  }) {
    final sortedPetIds = selectedPetIds.toList(growable: false)..sort();
    final cacheKey = [
      minuteStamp,
      _overviewRange.name,
      range.start.millisecondsSinceEpoch,
      range.end.millisecondsSinceEpoch,
      ...sortedPetIds,
    ].join('|');
    final cached = _overviewDataSliceCache;
    if (cached != null && _overviewDataSliceCacheKey == cacheKey) {
      return cached;
    }

    final storageSlice = _overviewDataSliceFromStorage(
      range: range,
      selectedPetIds: selectedPetIds,
    );
    if (storageSlice != null) {
      _overviewDataSliceCache = storageSlice;
      _overviewDataSliceCacheKey = cacheKey;
      return storageSlice;
    }

    final todos = _todos
        .where(
          (todo) =>
              selectedPetIds.contains(todo.petId) &&
              !todo.dueAt.isBefore(range.start) &&
              !todo.dueAt.isAfter(range.end),
        )
        .toList(growable: false);
    final reminders = _reminders
        .where(
          (reminder) =>
              selectedPetIds.contains(reminder.petId) &&
              !reminder.scheduledAt.isBefore(range.start) &&
              !reminder.scheduledAt.isAfter(range.end),
        )
        .toList(growable: false);
    final records = _records
        .where(
          (record) =>
              selectedPetIds.contains(record.petId) &&
              !record.recordDate.isBefore(range.start) &&
              !record.recordDate.isAfter(range.end),
        )
        .toList(growable: false)
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));
    final slice = _OverviewDataSlice(
      todos: todos,
      reminders: reminders,
      records: records,
    );
    _overviewDataSliceCache = slice;
    _overviewDataSliceCacheKey = cacheKey;
    return slice;
  }

  _OverviewDataSlice? _overviewDataSliceFromStorage({
    required ({DateTime start, DateTime end}) range,
    required Set<String> selectedPetIds,
  }) {
    if (!_overviewEntityStorageFresh || selectedPetIds.isEmpty) {
      return null;
    }
    final storage = _storage;
    if (storage == null ||
        !storage.usesEntityRows(PetNoteLocalTable.todos) ||
        !storage.usesEntityRows(PetNoteLocalTable.reminders) ||
        !storage.usesEntityRows(PetNoteLocalTable.records)) {
      return null;
    }
    final todoRows = storage.readEntityTableSlice(
      PetNoteLocalTable.todos,
      petIds: selectedPetIds,
      start: range.start,
      end: range.end,
    );
    final reminderRows = storage.readEntityTableSlice(
      PetNoteLocalTable.reminders,
      petIds: selectedPetIds,
      start: range.start,
      end: range.end,
    );
    final recordRows = storage.readEntityTableSlice(
      PetNoteLocalTable.records,
      petIds: selectedPetIds,
      start: range.start,
      end: range.end,
    );
    if (todoRows == null || reminderRows == null || recordRows == null) {
      return null;
    }
    final records =
        _decodeRows(recordRows, PetRecord.fromJson) ?? <PetRecord>[];
    return _OverviewDataSlice(
      todos: _decodeRows(todoRows, TodoItem.fromJson) ?? <TodoItem>[],
      reminders:
          _decodeRows(reminderRows, ReminderItem.fromJson) ?? <ReminderItem>[],
      records: records..sort((a, b) => b.recordDate.compareTo(a.recordDate)),
    );
  }

  AiPortableSummaryPackage buildAiPortableSummary({
    String? title,
    DateTime? generatedAt,
  }) {
    final context = buildOverviewAiGenerationContext();
    return AiPortableSummaryBuilder().build(
      title: title ?? context.title,
      context: context,
      generatedAt: generatedAt ?? _referenceNow,
    );
  }

  Future<void> generateOverviewAiReport(
    OverviewAiReportGenerator generate, {
    bool forceRefresh = false,
  }) async {
    if (_overviewAiReportState.isLoading) {
      return;
    }

    final context = buildOverviewAiGenerationContext();
    final requestKey = context.cacheKey;
    final requestToken = ++_overviewAiRequestToken;
    final previousReport = _overviewAiReportState.report;
    _overviewAiReportState = OverviewAiReportState(
      status: OverviewAiReportStatus.loading,
      requestKey: requestKey,
      report: previousReport,
      hasRequested: true,
      activeRequestToken: requestToken,
    );
    notifyListeners();

    try {
      final report = await generate(context, forceRefresh: forceRefresh);
      if (_overviewAiRequestToken != requestToken ||
          _overviewAiReportState.requestKey != requestKey) {
        return;
      }
      _overviewAiReportState = OverviewAiReportState(
        status: OverviewAiReportStatus.ready,
        requestKey: requestKey,
        report: report,
        hasRequested: true,
        activeRequestToken: requestToken,
      );
      notifyListeners();
      await _saveState(overviewAiReport: true);
    } on AiGenerationException catch (error) {
      if (_overviewAiRequestToken != requestToken ||
          _overviewAiReportState.requestKey != requestKey) {
        return;
      }
      _overviewAiReportState = OverviewAiReportState(
        status: OverviewAiReportStatus.error,
        requestKey: requestKey,
        errorMessage: error.message,
        hasRequested: true,
        activeRequestToken: requestToken,
      );
      notifyListeners();
      await _saveState(overviewAiReport: true);
    } catch (_) {
      if (_overviewAiRequestToken != requestToken ||
          _overviewAiReportState.requestKey != requestKey) {
        return;
      }
      _overviewAiReportState = OverviewAiReportState(
        status: OverviewAiReportStatus.error,
        requestKey: requestKey,
        errorMessage: 'AI 总览暂时无法生成，请稍后重试。',
        hasRequested: true,
        activeRequestToken: requestToken,
      );
      notifyListeners();
      await _saveState(overviewAiReport: true);
    }
  }

  Future<void> clearOverviewAiHistory() async {
    _overviewAiRequestToken += 1;
    _overviewAiReportState = OverviewAiReportState(
      activeRequestToken: _overviewAiRequestToken,
    );
    notifyListeners();
    await _saveState(overviewAiReport: true);
  }

  void setActiveTab(AppTab tab) {
    if (_activeTab == tab) {
      return;
    }
    _activeTab = tab;
    notifyListeners();
  }

  void setOverviewRange(OverviewRange range) {
    if (_overviewRange == range) {
      return;
    }
    _overviewRange = range;
    if (range != OverviewRange.custom) {
      _overviewCustomRangeStart = null;
      _overviewCustomRangeEnd = null;
    }
    _invalidateOverviewDerivedData();
    notifyListeners();
    unawaited(_saveState(overviewConfig: true, overviewAiReport: true));
  }

  void updateOverviewAnalysisConfig({
    required OverviewRange range,
    required List<String> selectedPetIds,
    DateTime? customRangeStart,
    DateTime? customRangeEnd,
  }) {
    final nextSelectedPetIds = selectedPetIds
        .where((petId) => _findPet(petId) != null)
        .toList(growable: false);
    _overviewRange = range;
    _overviewSelectedPetIds
      ..clear()
      ..addAll(nextSelectedPetIds);
    if (range == OverviewRange.custom) {
      _overviewCustomRangeStart = customRangeStart;
      _overviewCustomRangeEnd = customRangeEnd;
    } else {
      _overviewCustomRangeStart = null;
      _overviewCustomRangeEnd = null;
    }
    _invalidateOverviewDerivedData();
    notifyListeners();
    unawaited(_saveState(overviewConfig: true, overviewAiReport: true));
  }

  void selectPet(String petId) {
    if (_selectedPetId == petId) {
      return;
    }
    _selectedPetId = petId;
    _invalidateSelectedPetViewData();
    notifyListeners();
  }

  Future<void> markChecklistDone(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      _requireTodo(itemId).status = TodoStatus.done;
    } else {
      _requireReminder(itemId).status = ReminderStatus.done;
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      todos: sourceType == 'todo',
      reminders: sourceType != 'todo',
    );
    await _emitChecklistMutation(sourceType, itemId, PetActionKind.markDone);
  }

  Future<void> postponeChecklist(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      final todo = _requireTodo(itemId);
      todo.status = TodoStatus.postponed;
      todo.dueAt = todo.dueAt.add(const Duration(days: 1));
    } else {
      final reminder = _requireReminder(itemId);
      reminder.status = ReminderStatus.postponed;
      reminder.scheduledAt = reminder.scheduledAt.add(const Duration(days: 1));
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      todos: sourceType == 'todo',
      reminders: sourceType != 'todo',
    );
    await _emitChecklistMutation(sourceType, itemId, PetActionKind.postpone);
  }

  Future<void> skipChecklist(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      _requireTodo(itemId).status = TodoStatus.skipped;
    } else {
      _requireReminder(itemId).status = ReminderStatus.skipped;
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      todos: sourceType == 'todo',
      reminders: sourceType != 'todo',
    );
    await _emitChecklistMutation(sourceType, itemId, PetActionKind.skip);
  }

  bool isPetActionApplied(PetAction action) {
    if (action.sourceType == 'todo') {
      final item = _todosById[action.itemId];
      return item != null && item.status == _todoStatusForAction(action.kind);
    }
    final item = _remindersById[action.itemId];
    return item != null && item.status == _reminderStatusForAction(action.kind);
  }

  Future<void> applyPetAction(PetAction action) async {
    if (isPetActionApplied(action)) {
      return;
    }
    switch (action.kind) {
      case PetActionKind.markDone:
        await markChecklistDone(action.sourceType, action.itemId);
      case PetActionKind.postpone:
        await postponeChecklist(action.sourceType, action.itemId);
      case PetActionKind.skip:
        await skipChecklist(action.sourceType, action.itemId);
    }
  }

  Future<PetAction> applyRemotePetAction(
    PetAction action, {
    String? sourceNamespace,
    String? localNamespace,
  }) async {
    _applyingRemoteMutationDepth += 1;
    final navigationState = _captureNavigationState();
    _remoteNavigationState = navigationState;
    final mappedAction = _mappedRemoteAction(
      action,
      sourceNamespace: sourceNamespace,
      localNamespace: localNamespace,
    );
    try {
      await applyPetAction(mappedAction);
      return mappedAction;
    } finally {
      _restoreNavigationState(navigationState);
      _remoteNavigationState = null;
      _applyingRemoteMutationDepth -= 1;
    }
  }

  Future<void> applyLocalSyncedPetAction(PetAction action) async {
    final wasApplied = isPetActionApplied(action);
    _applyingRemoteMutationDepth += 1;
    try {
      await applyPetAction(action);
    } finally {
      _applyingRemoteMutationDepth -= 1;
    }
    if (wasApplied) {
      return;
    }
    await _emitChecklistMutation(
      action.sourceType,
      action.itemId,
      action.kind,
    );
  }

  Future<void> applyMutation(
    PetNoteMutation mutation, {
    String? sourceNamespace,
    String? localNamespace,
  }) async {
    _applyingRemoteMutationDepth += 1;
    final navigationState = _captureNavigationState();
    _remoteNavigationState = navigationState;
    try {
      final mappedMutation = _mappedRemoteMutation(
        mutation,
        sourceNamespace: sourceNamespace,
        localNamespace: localNamespace,
      );
      switch (mutation.kind) {
        case PetNoteMutationKind.upsert:
          await _applyUpsertMutation(mappedMutation);
        case PetNoteMutationKind.delete:
          await _applyDeleteMutation(mappedMutation);
        case PetNoteMutationKind.checklistAction:
          final actionKind = mappedMutation.actionKind;
          if (actionKind == null) {
            throw const FormatException('missing checklist action kind');
          }
          await applyPetAction(PetAction(
            kind: actionKind,
            sourceType: _sourceTypeForEntityType(mappedMutation.entityType),
            itemId: mappedMutation.entityId,
            occurredAtMs: mappedMutation.occurredAtMs,
          ));
      }
    } finally {
      _restoreNavigationState(navigationState);
      _remoteNavigationState = null;
      _applyingRemoteMutationDepth -= 1;
    }
  }

  Future<void> dismissFirstLaunchIntro() async {
    _shouldAutoShowFirstLaunchIntro = false;
    await _storage?.writeBool(_firstLaunchIntroAutoEnabledKey, false);
    notifyListeners();
  }

  Future<void> addTodo({
    required String title,
    required String petId,
    required DateTime dueAt,
    required String note,
    NotificationLeadTime notificationLeadTime = NotificationLeadTime.none,
    SemanticEventDetails? semantic,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedNote = note.trim();
    final todo = TodoItem(
      id: 'todo-${_todos.length + 1}',
      petId: petId,
      title: normalizedTitle.isEmpty
          ? _defaultTodoTitle(semantic, normalizedNote)
          : normalizedTitle,
      dueAt: dueAt,
      notificationLeadTime: notificationLeadTime,
      status: TodoStatus.open,
      note: normalizedNote,
      semantic: semantic ??
          _inferTodoSemantic(
            title: normalizedTitle,
            note: normalizedNote,
            dueAt: dueAt,
            status: TodoStatus.open,
          ),
    );
    _todos.insert(0, todo);
    _todosById[todo.id] = todo;
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(todos: true);
    await _emitUpsertMutation(PetNoteEntityType.todo, todo.id, todo.toJson());
  }

  Future<void> addReminder({
    required String title,
    required String petId,
    required DateTime scheduledAt,
    required ReminderKind kind,
    required String recurrence,
    required String note,
    NotificationLeadTime notificationLeadTime = NotificationLeadTime.none,
    SemanticEventDetails? semantic,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedNote = note.trim();
    final reminder = ReminderItem(
      id: 'reminder-${_reminders.length + 1}',
      petId: petId,
      kind: kind,
      title: normalizedTitle.isEmpty
          ? _defaultReminderTitle(kind, semantic)
          : normalizedTitle,
      scheduledAt: scheduledAt,
      notificationLeadTime: notificationLeadTime,
      recurrence: recurrence,
      status: ReminderStatus.pending,
      note: normalizedNote,
      semantic: semantic ??
          _inferReminderSemantic(
            kind: kind,
            title: normalizedTitle,
            note: normalizedNote,
            scheduledAt: scheduledAt,
            status: ReminderStatus.pending,
          ),
    );
    _reminders.insert(0, reminder);
    _remindersById[reminder.id] = reminder;
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    if (_selectedPetId == petId) {
      _invalidateSelectedPetReminders();
    }
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(reminders: true);
    await _emitUpsertMutation(
      PetNoteEntityType.reminder,
      reminder.id,
      reminder.toJson(),
    );
  }

  Future<void> addRecord({
    required String petId,
    PetRecordType? type,
    RecordPurpose? purpose,
    String? customPurposeLabel,
    required String title,
    required DateTime recordDate,
    required String summary,
    required String note,
    List<String> photoPaths = const <String>[],
    SemanticEventDetails? semantic,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedSummary = summary.trim();
    final normalizedNote = note.trim();
    final normalizedCustomPurpose = customPurposeLabel?.trim().isEmpty ?? true
        ? null
        : customPurposeLabel!.trim();
    final normalizedPhotoPaths = photoPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final resolvedType =
        type ?? _recordTypeForPurpose(purpose ?? RecordPurpose.health);
    final resolvedPurpose = purpose ?? _recordPurposeForType(resolvedType);
    final record = PetRecord(
      id: 'record-${_records.length + 1}',
      petId: petId,
      type: resolvedType,
      purpose: resolvedPurpose,
      customPurposeLabel: resolvedPurpose == RecordPurpose.other
          ? normalizedCustomPurpose
          : null,
      title: normalizedTitle.isEmpty
          ? _defaultRecordTitle(
              resolvedType,
              semantic,
              purpose: resolvedPurpose,
              customPurposeLabel: normalizedCustomPurpose,
            )
          : normalizedTitle,
      recordDate: recordDate,
      summary: normalizedSummary,
      note: normalizedNote,
      photoPaths: normalizedPhotoPaths,
      semantic: semantic ??
          _inferRecordSemantic(
            type: resolvedType,
            purpose: resolvedPurpose,
            title: normalizedTitle,
            summary: normalizedSummary,
            note: normalizedNote,
            recordDate: recordDate,
          ),
    );
    _records.insert(0, record);
    _recordsById[record.id] = record;
    _selectedPetId = petId;
    _activeTab = AppTab.pets;
    _invalidateOverviewDerivedData();
    _invalidateRecordDerivedData();
    notifyListeners();
    await _saveState(records: true, overviewAiReport: true);
    await _emitUpsertMutation(
      PetNoteEntityType.record,
      record.id,
      record.toJson(),
    );
  }

  Future<void> updateTodo({
    required String todoId,
    required String petId,
    required String title,
    required DateTime dueAt,
    required NotificationLeadTime notificationLeadTime,
    required String note,
  }) async {
    final index = _todos.indexWhere((item) => item.id == todoId);
    if (index == -1 || _findPet(petId) == null) {
      return;
    }

    final current = _todos[index];
    final normalizedTitle = title.trim();
    final normalizedNote = note.trim();
    final updatedTodo = TodoItem(
      id: current.id,
      petId: petId,
      title: normalizedTitle.isEmpty
          ? _defaultTodoTitle(current.semantic, normalizedNote)
          : normalizedTitle,
      dueAt: dueAt,
      notificationLeadTime: notificationLeadTime,
      status: current.status,
      note: normalizedNote,
      semantic: _inferTodoSemantic(
        title: normalizedTitle,
        note: normalizedNote,
        dueAt: dueAt,
        status: current.status,
      ),
    );
    _todos[index] = updatedTodo;
    _todosById[updatedTodo.id] = updatedTodo;
    _selectedPetId = petId;
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(todos: true);
    await _emitUpsertMutation(
      PetNoteEntityType.todo,
      updatedTodo.id,
      updatedTodo.toJson(),
    );
  }

  Future<void> updateReminder({
    required String reminderId,
    required String petId,
    required ReminderKind kind,
    required String title,
    required DateTime scheduledAt,
    required NotificationLeadTime notificationLeadTime,
    required String note,
  }) async {
    final index = _reminders.indexWhere((item) => item.id == reminderId);
    if (index == -1 || _findPet(petId) == null) {
      return;
    }

    final current = _reminders[index];
    final normalizedTitle = title.trim();
    final normalizedNote = note.trim();
    final updatedReminder = ReminderItem(
      id: current.id,
      petId: petId,
      kind: kind,
      title: normalizedTitle.isEmpty
          ? _defaultReminderTitle(kind, current.semantic)
          : normalizedTitle,
      scheduledAt: scheduledAt,
      notificationLeadTime: notificationLeadTime,
      recurrence: current.recurrence,
      status: current.status,
      note: normalizedNote,
      semantic: _inferReminderSemantic(
        kind: kind,
        title: normalizedTitle,
        note: normalizedNote,
        scheduledAt: scheduledAt,
        status: current.status,
      ),
    );
    _reminders[index] = updatedReminder;
    _remindersById[updatedReminder.id] = updatedReminder;
    _selectedPetId = petId;
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetReminders();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(reminders: true);
    await _emitUpsertMutation(
      PetNoteEntityType.reminder,
      updatedReminder.id,
      updatedReminder.toJson(),
    );
  }

  Future<void> updateRecord({
    required String recordId,
    required String petId,
    required DateTime recordDate,
    required RecordPurpose? purpose,
    String? customPurposeLabel,
    required String title,
    required String summary,
    required String note,
    List<String> photoPaths = const <String>[],
  }) async {
    final index = _records.indexWhere((item) => item.id == recordId);
    if (index == -1 || _findPet(petId) == null) {
      return;
    }

    final current = _records[index];
    final normalizedTitle = title.trim();
    final normalizedSummary = summary.trim();
    final normalizedNote = note.trim();
    final normalizedCustomPurpose = customPurposeLabel?.trim().isEmpty ?? true
        ? null
        : customPurposeLabel!.trim();
    final normalizedPhotoPaths = photoPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final resolvedPurpose = purpose ?? current.purpose ?? RecordPurpose.health;
    final resolvedType = _recordTypeForPurpose(resolvedPurpose);
    final updatedRecord = PetRecord(
      id: current.id,
      petId: petId,
      type: resolvedType,
      title: normalizedTitle.isEmpty
          ? _defaultRecordTitle(
              resolvedType,
              current.semantic,
              purpose: resolvedPurpose,
              customPurposeLabel: normalizedCustomPurpose,
            )
          : normalizedTitle,
      recordDate: recordDate,
      summary: normalizedSummary,
      note: normalizedNote,
      purpose: resolvedPurpose,
      customPurposeLabel: resolvedPurpose == RecordPurpose.other
          ? normalizedCustomPurpose
          : null,
      photoPaths: normalizedPhotoPaths,
      semantic: _inferRecordSemantic(
        type: resolvedType,
        purpose: resolvedPurpose,
        title: normalizedTitle,
        summary: normalizedSummary,
        note: normalizedNote,
        recordDate: recordDate,
      ),
    );
    _records[index] = updatedRecord;
    _recordsById[updatedRecord.id] = updatedRecord;
    _selectedPetId = petId;
    _activeTab = AppTab.pets;
    _invalidateOverviewDerivedData();
    _invalidateRecordDerivedData();
    notifyListeners();
    await _saveState(records: true, overviewAiReport: true);
    await _emitUpsertMutation(
      PetNoteEntityType.record,
      updatedRecord.id,
      updatedRecord.toJson(),
    );
  }

  Future<void> deleteRecords(Iterable<String> recordIds) async {
    final ids =
        recordIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) {
      return;
    }

    final originalLength = _records.length;
    _records.removeWhere((item) => ids.contains(item.id));
    if (_records.length == originalLength) {
      return;
    }
    for (final id in ids) {
      _recordsById.remove(id);
    }

    _activeTab = AppTab.pets;
    _invalidateOverviewDerivedData();
    _invalidateRecordDerivedData();
    notifyListeners();
    await _saveState(records: true, overviewAiReport: true);
    for (final id in ids) {
      await _emitDeleteMutation(PetNoteEntityType.record, id);
    }
  }

  Future<void> deletePet(String petId) {
    return _deletePet(petId, emitMutation: true);
  }

  Future<void> _deletePet(
    String petId, {
    required bool emitMutation,
  }) async {
    final normalizedPetId = petId.trim();
    if (normalizedPetId.isEmpty || !_petsById.containsKey(normalizedPetId)) {
      return;
    }

    final relatedTodoIds = _todos
        .where((item) => item.petId == normalizedPetId)
        .map((item) => item.id)
        .toSet();
    final relatedReminderIds = _reminders
        .where((item) => item.petId == normalizedPetId)
        .map((item) => item.id)
        .toSet();
    final relatedRecordIds = _records
        .where((item) => item.petId == normalizedPetId)
        .map((item) => item.id)
        .toSet();

    _pets.removeWhere((item) => item.id == normalizedPetId);
    _petsById.remove(normalizedPetId);
    _todos.removeWhere((item) => item.petId == normalizedPetId);
    _rebuildTodoIndex();
    _reminders.removeWhere((item) => item.petId == normalizedPetId);
    _rebuildReminderIndex();
    _records.removeWhere((item) => item.petId == normalizedPetId);
    _rebuildRecordIndex();
    _overviewSelectedPetIds.remove(normalizedPetId);
    if (_selectedPetId == normalizedPetId) {
      _selectedPetId = _pets.isEmpty ? '' : _pets.first.id;
    }
    _activeTab = _pets.isEmpty ? AppTab.checklist : AppTab.pets;
    await _removePendingMutationsForDeletedPet(
      petId: normalizedPetId,
      todoIds: relatedTodoIds,
      reminderIds: relatedReminderIds,
      recordIds: relatedRecordIds,
    );
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
      overviewConfig: true,
    );
    if (emitMutation) {
      await _emitDeleteMutation(PetNoteEntityType.pet, normalizedPetId);
    }
  }

  Future<void> _removePendingMutationsForDeletedPet({
    required String petId,
    required Set<String> todoIds,
    required Set<String> reminderIds,
    required Set<String> recordIds,
  }) async {
    _pendingLocalMutations.removeWhere((_, mutation) {
      if (mutation.entityType == PetNoteEntityType.pet) {
        return mutation.entityId == petId;
      }
      if (mutation.entityType == PetNoteEntityType.todo) {
        return todoIds.contains(mutation.entityId);
      }
      if (mutation.entityType == PetNoteEntityType.reminder) {
        return reminderIds.contains(mutation.entityId);
      }
      if (mutation.entityType == PetNoteEntityType.record) {
        return recordIds.contains(mutation.entityId);
      }
      return false;
    });
    await _savePendingLocalMutations(force: true);
  }

  Future<void> addPet({
    required String name,
    required PetType type,
    String? photoPath,
    required String breed,
    required String sex,
    required String birthday,
    required double weightKg,
    required PetNeuterStatus neuterStatus,
    required String feedingPreferences,
    required String allergies,
    required String note,
  }) async {
    final pet = Pet(
      id: 'pet-${_pets.length + 1}',
      name: name,
      avatarText: _avatarTextForName(name),
      photoPath: photoPath,
      type: type,
      breed: breed,
      sex: sex,
      birthday: birthday,
      ageLabel: '新加入',
      weightKg: weightKg,
      neuterStatus: neuterStatus,
      feedingPreferences: feedingPreferences,
      allergies: allergies,
      note: note,
    );
    _pets.insert(0, pet);
    _petsById[pet.id] = pet;
    _overviewSelectedPetIds.add(pet.id);
    _selectedPetId = pet.id;
    _activeTab = AppTab.pets;
    _invalidateAllDerivedData();
    await _saveState(
      pets: true,
      overviewConfig: true,
      overviewAiReport: true,
    );
    notifyListeners();
    await _emitUpsertMutation(PetNoteEntityType.pet, pet.id, pet.toJson());
  }

  Future<void> updatePet({
    required String petId,
    required String name,
    required PetType type,
    String? photoPath,
    required String breed,
    required String sex,
    required String birthday,
    required double weightKg,
    required PetNeuterStatus neuterStatus,
    required String feedingPreferences,
    required String allergies,
    required String note,
  }) async {
    final index = _pets.indexWhere((pet) => pet.id == petId);
    if (index == -1) {
      return;
    }

    final current = _pets[index];
    final updatedPet = Pet(
      id: current.id,
      name: name,
      avatarText: _avatarTextForName(name),
      photoPath: photoPath,
      type: type,
      breed: breed,
      sex: sex,
      birthday: birthday,
      ageLabel: current.ageLabel,
      weightKg: weightKg,
      neuterStatus: neuterStatus,
      feedingPreferences: feedingPreferences,
      allergies: allergies,
      note: note,
    );
    _pets[index] = updatedPet;
    _petsById[updatedPet.id] = updatedPet;
    _selectedPetId = current.id;
    _activeTab = AppTab.pets;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    if (_todos.any((item) => item.petId == current.id) ||
        _reminders.any((item) => item.petId == current.id)) {
      _bumpNotificationSyncVersion();
      await _finalizeNotificationMutation(pets: true);
      await _emitUpsertMutation(
        PetNoteEntityType.pet,
        updatedPet.id,
        updatedPet.toJson(),
      );
      return;
    }
    notifyListeners();
    await _saveState(pets: true, overviewAiReport: true);
    await _emitUpsertMutation(
      PetNoteEntityType.pet,
      updatedPet.id,
      updatedPet.toJson(),
    );
  }

  PetNoteDataState exportDataState() {
    return PetNoteDataState(
      pets: List<Pet>.from(_pets),
      todos: List<TodoItem>.from(_todos),
      reminders: List<ReminderItem>.from(_reminders),
      records: List<PetRecord>.from(_records),
    );
  }

  List<String> completedItemKeys() {
    final keys = <String>[
      for (final todo in _todos)
        if (todo.status == TodoStatus.done ||
            todo.status == TodoStatus.postponed ||
            todo.status == TodoStatus.skipped)
          'todo:${todo.id}',
      for (final reminder in _reminders)
        if (reminder.status == ReminderStatus.done ||
            reminder.status == ReminderStatus.postponed ||
            reminder.status == ReminderStatus.skipped)
          'reminder:${reminder.id}',
    ]..sort();
    return keys;
  }

  Future<void> replaceAllData(PetNoteDataState state) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    _replaceDataCollections(normalizedState);
    await _resetPendingLocalMutations();
    _bumpDataResetVersion();
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
      overviewConfig: true,
    );
  }

  Future<void> replaceAllDataFromRemote(PetNoteDataState state) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    final pendingMutations = pendingLocalMutations;
    _replaceDataCollections(normalizedState);
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
      overviewConfig: true,
    );
    for (final mutation in pendingMutations) {
      await applyMutation(mutation);
    }
    await _savePendingLocalMutations(force: true);
  }

  void _replaceDataCollections(PetNoteDataState normalizedState) {
    _pets
      ..clear()
      ..addAll(normalizedState.pets);
    _rebuildPetIndex();
    _todos
      ..clear()
      ..addAll(normalizedState.todos);
    _rebuildTodoIndex();
    _reminders
      ..clear()
      ..addAll(normalizedState.reminders);
    _rebuildReminderIndex();
    _records
      ..clear()
      ..addAll(normalizedState.records);
    _rebuildRecordIndex();
    _overviewSelectedPetIds
      ..clear()
      ..addAll(_pets.map((pet) => pet.id));
    _selectedPetId = _pets.isEmpty ? '' : _pets.first.id;
    _activeTab = _pets.isEmpty ? AppTab.checklist : AppTab.pets;
  }

  Future<void> appendData(PetNoteDataState state) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    _ensureNoConflicts(
      currentIds: _pets.map((pet) => pet.id),
      incomingIds: normalizedState.pets.map((pet) => pet.id),
      label: '宠物',
    );
    _ensureNoConflicts(
      currentIds: _todos.map((item) => item.id),
      incomingIds: normalizedState.todos.map((item) => item.id),
      label: '待办',
    );
    _ensureNoConflicts(
      currentIds: _reminders.map((item) => item.id),
      incomingIds: normalizedState.reminders.map((item) => item.id),
      label: '提醒',
    );
    _ensureNoConflicts(
      currentIds: _records.map((item) => item.id),
      incomingIds: normalizedState.records.map((item) => item.id),
      label: '记录',
    );

    _pets.addAll(normalizedState.pets);
    for (final pet in normalizedState.pets) {
      _petsById[pet.id] = pet;
    }
    _overviewSelectedPetIds.addAll(normalizedState.pets.map((pet) => pet.id));
    _todos.addAll(normalizedState.todos);
    for (final item in normalizedState.todos) {
      _todosById[item.id] = item;
    }
    _reminders.addAll(normalizedState.reminders);
    for (final item in normalizedState.reminders) {
      _remindersById[item.id] = item;
    }
    _records.addAll(normalizedState.records);
    for (final item in normalizedState.records) {
      _recordsById[item.id] = item;
    }
    if (_selectedPetId.isEmpty && _pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
    }
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
      overviewConfig: true,
    );
  }

  Future<void> mergeData(
    PetNoteDataState state, {
    SyncMergeConflictResolver? resolveConflict,
  }) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    await _mergeById<Pet>(
      current: _pets,
      incoming: normalizedState.pets,
      idOf: (item) => item.id,
      index: _petsById,
      collectionLabel: '宠物',
      labelOf: (item) => item.name,
      jsonOf: (item) => item.toJson(),
      resolveConflict: resolveConflict,
    );
    await _mergeById<TodoItem>(
      current: _todos,
      incoming: normalizedState.todos,
      idOf: (item) => item.id,
      index: _todosById,
      collectionLabel: '待办',
      labelOf: (item) => item.title,
      jsonOf: (item) => item.toJson(),
      resolveConflict: resolveConflict,
    );
    await _mergeById<ReminderItem>(
      current: _reminders,
      incoming: normalizedState.reminders,
      idOf: (item) => item.id,
      index: _remindersById,
      collectionLabel: '提醒',
      labelOf: (item) => item.title,
      jsonOf: (item) => item.toJson(),
      resolveConflict: resolveConflict,
    );
    await _mergeById<PetRecord>(
      current: _records,
      incoming: normalizedState.records,
      idOf: (item) => item.id,
      index: _recordsById,
      collectionLabel: '记录',
      labelOf: (item) => item.title,
      jsonOf: (item) => item.toJson(),
      resolveConflict: resolveConflict,
    );
    if (_selectedPetId.isEmpty && _pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
    }
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
    );
  }

  Future<void> mergeDataPreservingConflictingIds(
    PetNoteDataState state, {
    String? sourceNamespace,
    String? localNamespace,
  }) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    final remappedPetIds = <String, String>{};
    final importedPetKeys = <String>{};
    final importedTodoKeys = <String>{};
    final importedReminderKeys = <String>{};
    final importedRecordKeys = <String>{};
    for (final pet in normalizedState.pets) {
      final petKey = _mergeEntityKey('pet', pet.id, pet.toJson());
      if (!importedPetKeys.add(petKey)) {
        remappedPetIds[pet.id] =
            _matchImportedEntityId(_pets, pet, (item) => item.id);
        continue;
      }
      final mergedId = _mergedIdFor(
        prefix: 'pet',
        sourceId: pet.id,
        json: pet.toJson(),
        sourceNamespace: sourceNamespace,
        localNamespace: localNamespace,
        index: _petsById,
      );
      final existingPet = _petsById[pet.id];
      if (existingPet == null && mergedId == pet.id) {
        _pets.add(pet);
        _petsById[pet.id] = pet;
        remappedPetIds[pet.id] = pet.id;
        continue;
      }
      if (existingPet != null &&
          mergedId == pet.id &&
          _jsonEquals(existingPet.toJson(), pet.toJson())) {
        remappedPetIds[pet.id] = existingPet.id;
        continue;
      }
      final importedPet = _petsById[mergedId];
      if (importedPet != null) {
        final cloned = _petWithId(pet, mergedId);
        final index = _pets.indexWhere((item) => item.id == mergedId);
        if (index == -1) {
          _pets.add(cloned);
        } else {
          _pets[index] = cloned;
        }
        _petsById[mergedId] = cloned;
        remappedPetIds[pet.id] = mergedId;
        continue;
      }
      final cloned = _petWithId(pet, mergedId);
      _pets.add(cloned);
      _petsById[cloned.id] = cloned;
      remappedPetIds[pet.id] = cloned.id;
    }

    _mergeIncomingEntitiesPreservingConflictingIds<TodoItem>(
      current: _todos,
      incoming: normalizedState.todos,
      idOf: (item) => item.id,
      index: _todosById,
      jsonOf: (item) => item.toJson(),
      cloneWithIds: (item, id) => _todoWithIds(
        item,
        id: id,
        petId: remappedPetIds[item.petId] ?? item.petId,
      ),
      idPrefix: 'todo',
      sourceNamespace: sourceNamespace,
      localNamespace: localNamespace,
      importedKeys: importedTodoKeys,
    );
    _mergeIncomingEntitiesPreservingConflictingIds<ReminderItem>(
      current: _reminders,
      incoming: normalizedState.reminders,
      idOf: (item) => item.id,
      index: _remindersById,
      jsonOf: (item) => item.toJson(),
      cloneWithIds: (item, id) => _reminderWithIds(
        item,
        id: id,
        petId: remappedPetIds[item.petId] ?? item.petId,
      ),
      idPrefix: 'reminder',
      sourceNamespace: sourceNamespace,
      localNamespace: localNamespace,
      importedKeys: importedReminderKeys,
    );
    _mergeIncomingEntitiesPreservingConflictingIds<PetRecord>(
      current: _records,
      incoming: normalizedState.records,
      idOf: (item) => item.id,
      index: _recordsById,
      jsonOf: (item) => item.toJson(),
      cloneWithIds: (item, id) => _recordWithIds(
        item,
        id: id,
        petId: remappedPetIds[item.petId] ?? item.petId,
      ),
      idPrefix: 'record',
      sourceNamespace: sourceNamespace,
      localNamespace: localNamespace,
      importedKeys: importedRecordKeys,
    );

    if (_selectedPetId.isEmpty && _pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
    }
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
    );
  }

  bool hasStableMergedEntitiesForSource(String? sourceNamespace) {
    final normalizedNamespace = _normalizedSourceNamespace(sourceNamespace);
    if (normalizedNamespace == null) {
      return false;
    }
    return _hasStableMergedEntityForSource(
          ids: _petsById.keys,
          prefix: 'pet',
          namespace: normalizedNamespace,
        ) ||
        _hasStableMergedEntityForSource(
          ids: _todosById.keys,
          prefix: 'todo',
          namespace: normalizedNamespace,
        ) ||
        _hasStableMergedEntityForSource(
          ids: _remindersById.keys,
          prefix: 'reminder',
          namespace: normalizedNamespace,
        ) ||
        _hasStableMergedEntityForSource(
          ids: _recordsById.keys,
          prefix: 'record',
          namespace: normalizedNamespace,
        );
  }

  Future<void> clearAllData() async {
    _pets.clear();
    _petsById.clear();
    _todos.clear();
    _todosById.clear();
    _reminders.clear();
    _remindersById.clear();
    _records.clear();
    _recordsById.clear();
    _overviewSelectedPetIds.clear();
    _selectedPetId = '';
    _activeTab = AppTab.checklist;
    await _resetPendingLocalMutations();
    _bumpDataResetVersion();
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    await _finalizeNotificationMutation(
      pets: true,
      todos: true,
      reminders: true,
      records: true,
      overviewConfig: true,
    );
  }

  Future<void> _finalizeNotificationMutation({
    bool pets = false,
    bool todos = false,
    bool reminders = false,
    bool records = false,
    bool overviewConfig = false,
  }) async {
    notifyListeners();
    await _saveState(
      pets: pets,
      todos: todos,
      reminders: reminders,
      records: records,
      overviewConfig: overviewConfig,
      overviewAiReport: true,
    );
    final handler = _notificationSyncHandler;
    if (handler != null) {
      unawaited(
        Future<void>.sync(handler)
            .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'petnote_store',
              context: ErrorDescription('在后台同步通知任务时发生异常'),
            ),
          );
        }),
      );
    }
  }

  Future<void> _applyUpsertMutation(PetNoteMutation mutation) async {
    final data = mutation.data;
    if (data == null) {
      throw const FormatException('missing mutation data');
    }
    switch (mutation.entityType) {
      case PetNoteEntityType.pet:
        final pet = Pet.fromJson(data);
        final index = _pets.indexWhere((item) => item.id == pet.id);
        if (index == -1) {
          _pets.insert(0, pet);
        } else {
          _pets[index] = pet;
        }
        _petsById[pet.id] = pet;
        _overviewSelectedPetIds.add(pet.id);
        _selectedPetId = pet.id;
        _activeTab = AppTab.pets;
        _invalidateAllDerivedData();
        await _finalizeNotificationMutation(
          pets: true,
          overviewConfig: true,
        );
      case PetNoteEntityType.todo:
        final todo = TodoItem.fromJson(data);
        final index = _todos.indexWhere((item) => item.id == todo.id);
        if (index == -1) {
          _todos.insert(0, todo);
        } else {
          _todos[index] = todo;
        }
        _todosById[todo.id] = todo;
        _selectedPetId = todo.petId;
        _activeTab = AppTab.checklist;
        _invalidateChecklistDerivedData();
        _invalidateOverviewDerivedData();
        _bumpNotificationSyncVersion();
        await _finalizeNotificationMutation(todos: true);
      case PetNoteEntityType.reminder:
        final reminder = ReminderItem.fromJson(data);
        final index = _reminders.indexWhere((item) => item.id == reminder.id);
        if (index == -1) {
          _reminders.insert(0, reminder);
        } else {
          _reminders[index] = reminder;
        }
        _remindersById[reminder.id] = reminder;
        _selectedPetId = reminder.petId;
        _activeTab = AppTab.checklist;
        _invalidateChecklistDerivedData();
        _invalidateOverviewDerivedData();
        _invalidateSelectedPetReminders();
        _bumpNotificationSyncVersion();
        await _finalizeNotificationMutation(reminders: true);
      case PetNoteEntityType.record:
        final record = PetRecord.fromJson(data);
        final index = _records.indexWhere((item) => item.id == record.id);
        if (index == -1) {
          _records.insert(0, record);
        } else {
          _records[index] = record;
        }
        _recordsById[record.id] = record;
        _selectedPetId = record.petId;
        _activeTab = AppTab.pets;
        _invalidateOverviewDerivedData();
        _invalidateRecordDerivedData();
        notifyListeners();
        await _saveState(records: true, overviewAiReport: true);
    }
  }

  Future<void> _applyDeleteMutation(PetNoteMutation mutation) async {
    switch (mutation.entityType) {
      case PetNoteEntityType.pet:
        await _deletePet(mutation.entityId, emitMutation: false);
        break;
      case PetNoteEntityType.record:
        await deleteRecords([mutation.entityId]);
        break;
      case PetNoteEntityType.todo:
      case PetNoteEntityType.reminder:
        return;
    }
  }

  Future<void> _emitUpsertMutation(
    PetNoteEntityType entityType,
    String entityId,
    Map<String, dynamic> data,
  ) {
    return _emitLocalMutation(PetNoteMutation(
      id: _newMutationId(entityType, entityId),
      entityType: entityType,
      entityId: entityId,
      kind: PetNoteMutationKind.upsert,
      data: data,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    ));
  }

  Future<void> _emitDeleteMutation(
    PetNoteEntityType entityType,
    String entityId,
  ) {
    return _emitLocalMutation(PetNoteMutation(
      id: _newMutationId(entityType, entityId),
      entityType: entityType,
      entityId: entityId,
      kind: PetNoteMutationKind.delete,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    ));
  }

  Future<void> _emitChecklistMutation(
    String sourceType,
    String itemId,
    PetActionKind actionKind,
  ) {
    final entityType = switch (sourceType) {
      'todo' => PetNoteEntityType.todo,
      'reminder' => PetNoteEntityType.reminder,
      _ => throw FormatException('unsupported source type: $sourceType'),
    };
    return _emitLocalMutation(PetNoteMutation(
      id: _newMutationId(entityType, itemId),
      entityType: entityType,
      entityId: itemId,
      kind: PetNoteMutationKind.checklistAction,
      actionKind: actionKind,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    ));
  }

  Future<void> _emitLocalMutation(PetNoteMutation mutation) async {
    if (_applyingRemoteMutationDepth > 0 || _localMutations.isClosed) {
      return;
    }
    _pendingLocalMutations[mutation.id] = mutation;
    await _savePendingLocalMutations();
    _localMutations.add(mutation);
  }

  Future<void> markMutationSynced(String mutationId) async {
    if (!_pendingLocalMutations.containsKey(mutationId)) {
      return;
    }
    _pendingLocalMutations.remove(mutationId);
    await _savePendingLocalMutations();
  }

  Future<void> markChecklistActionSynced({
    required String sourceType,
    required String itemId,
    String? kind,
  }) async {
    final entityType = switch (sourceType) {
      'todo' => PetNoteEntityType.todo,
      'reminder' => PetNoteEntityType.reminder,
      _ => null,
    };
    if (entityType == null) {
      return;
    }
    PetActionKind? actionKind;
    if (kind != null) {
      for (final value in PetActionKind.values) {
        if (value.name == kind) {
          actionKind = value;
          break;
        }
      }
    }
    final removedMutationIds = <String>[];
    for (final entry in _pendingLocalMutations.entries) {
      final mutation = entry.value;
      if (mutation.kind != PetNoteMutationKind.checklistAction ||
          mutation.entityType != entityType ||
          mutation.entityId != itemId) {
        continue;
      }
      if (actionKind != null &&
          actionKind != PetActionKind.markDone &&
          mutation.actionKind != actionKind) {
        continue;
      }
      removedMutationIds.add(entry.key);
    }
    if (removedMutationIds.isEmpty) {
      return;
    }
    for (final mutationId in removedMutationIds) {
      _pendingLocalMutations.remove(mutationId);
    }
    await _savePendingLocalMutations();
  }

  String _newMutationId(PetNoteEntityType entityType, String entityId) {
    return '${DateTime.now().toUtc().microsecondsSinceEpoch}-${entityType.name}-$entityId';
  }

  String _sourceTypeForEntityType(PetNoteEntityType entityType) {
    return switch (entityType) {
      PetNoteEntityType.todo => 'todo',
      PetNoteEntityType.reminder => 'reminder',
      PetNoteEntityType.pet ||
      PetNoteEntityType.record =>
        throw FormatException('unsupported checklist entity: $entityType'),
    };
  }

  ({AppTab activeTab, String selectedPetId}) _captureNavigationState() {
    return (activeTab: _activeTab, selectedPetId: _selectedPetId);
  }

  void _restoreNavigationState(
    ({AppTab activeTab, String selectedPetId}) state,
  ) {
    _activeTab = state.activeTab;
    if (state.selectedPetId.isEmpty ||
        _petsById.containsKey(state.selectedPetId)) {
      _selectedPetId = state.selectedPetId;
    } else {
      _selectedPetId = _pets.isEmpty ? '' : _pets.first.id;
    }
    _invalidateSelectedPetViewData();
  }

  void _bumpNotificationSyncVersion() {
    _notificationSyncVersion += 1;
  }

  void _bumpDataResetVersion() {
    _dataResetVersion += 1;
  }

  void _invalidateAllDerivedData() {
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetViewData();
    _invalidateRecordDerivedData();
  }

  void _invalidateChecklistDerivedData() {
    _checklistSectionsCache = null;
    _checklistSectionsCacheMinuteStamp = null;
  }

  void _invalidateOverviewDerivedData() {
    _overviewSnapshotCache = null;
    _overviewSnapshotCacheMinuteStamp = null;
    _overviewDataSliceCache = null;
    _overviewDataSliceCacheKey = null;
    _overviewEntityStorageFresh = false;
    _invalidateOverviewAiReportState();
  }

  void _invalidateOverviewAiReportState() {
    _overviewAiRequestToken += 1;
    _overviewAiReportState = OverviewAiReportState(
      activeRequestToken: _overviewAiRequestToken,
    );
  }

  void _invalidateSelectedPetReminders() {
    _remindersForSelectedPetCachePetId = null;
    _remindersForSelectedPetCache = null;
  }

  void _invalidateRecordDerivedData() {
    _recordsByPetIdCache.clear();
  }

  void _invalidateSelectedPetViewData() {
    _invalidateSelectedPetReminders();
  }

  void _invalidateTimeDerivedData() {
    _invalidateChecklistDerivedData();
    _overviewSnapshotCache = null;
    _overviewSnapshotCacheMinuteStamp = null;
    _overviewDataSliceCache = null;
    _overviewDataSliceCacheKey = null;
  }

  void _rebuildPetIndex() {
    _petsById
      ..clear()
      ..addEntries(_pets.map((pet) => MapEntry(pet.id, pet)));
  }

  void _rebuildTodoIndex() {
    _todosById
      ..clear()
      ..addEntries(_todos.map((item) => MapEntry(item.id, item)));
  }

  void _rebuildReminderIndex() {
    _remindersById
      ..clear()
      ..addEntries(_reminders.map((item) => MapEntry(item.id, item)));
  }

  void _rebuildRecordIndex() {
    _recordsById
      ..clear()
      ..addEntries(_records.map((item) => MapEntry(item.id, item)));
  }

  void _scheduleNextTimeDerivedDataRefresh() {
    _timeDerivedDataTimer?.cancel();
    final now = _referenceNow;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timeDerivedDataTimer =
        Timer(nextMinute.difference(now), _handleTimeDerivedDataRefresh);
  }

  void _handleTimeDerivedDataRefresh() {
    final minuteStamp = _minuteStamp(_referenceNow);
    if (_timeDerivedDataMinuteStamp != minuteStamp) {
      _timeDerivedDataMinuteStamp = minuteStamp;
      _invalidateTimeDerivedData();
      notifyListeners();
    }
    if (_timeDerivedDataTimer != null) {
      _scheduleNextTimeDerivedDataRefresh();
    }
  }

  ChecklistItemViewModel _todoToChecklistItem(TodoItem item) {
    final effectiveStatus = _effectiveTodoStatus(item, _referenceNow);
    final pet = _findPet(item.petId);
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'todo',
      petId: item.petId,
      petName: pet?.name ?? '未命名爱宠',
      petAvatarText: pet == null ? 'PA' : petAvatarFallbackForPet(pet),
      petAvatarPhotoPath: pet?.photoPath,
      title: item.title,
      dueLabel: _formatDate(item.dueAt),
      statusLabel: _todoStatusLabel(effectiveStatus),
      kindLabel: '待办',
      note: item.note,
    );
  }

  ChecklistItemViewModel _reminderToChecklistItem(ReminderItem item) {
    final effectiveStatus = _effectiveReminderStatus(item, _referenceNow);
    final pet = _findPet(item.petId);
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'reminder',
      petId: item.petId,
      petName: pet?.name ?? '未命名爱宠',
      petAvatarText: pet == null ? 'PA' : petAvatarFallbackForPet(pet),
      petAvatarPhotoPath: pet?.photoPath,
      title: item.title,
      dueLabel: _formatDate(item.scheduledAt),
      statusLabel: _reminderStatusLabel(effectiveStatus),
      kindLabel: '提醒',
      note: item.note,
    );
  }

  DateTime get _referenceNow => _nowProvider();

  ({DateTime start, DateTime end}) _resolveOverviewDateRange(
    DateTime referenceNow,
  ) {
    if (_overviewRange == OverviewRange.custom &&
        _overviewCustomRangeStart != null &&
        _overviewCustomRangeEnd != null) {
      final start = _atStartOfDay(_overviewCustomRangeStart!);
      final end = _atEndOfDay(_overviewCustomRangeEnd!);
      return (
        start: start,
        end: end,
      );
    }
    final days = switch (_overviewRange) {
      OverviewRange.sevenDays => 7,
      OverviewRange.oneMonth => 30,
      OverviewRange.threeMonths => 90,
      OverviewRange.sixMonths => 180,
      OverviewRange.oneYear => 365,
      OverviewRange.custom => 7,
    };
    return (
      start: referenceNow.subtract(Duration(days: days)),
      end: referenceNow,
    );
  }

  DateTime _atStartOfDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  DateTime _atEndOfDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999, 999);
  }

  List<String> _effectiveOverviewSelectedPetIds() {
    final existingPetIds = _pets.map((pet) => pet.id).toSet();
    return _overviewSelectedPetIds
        .where((petId) => existingPetIds.contains(petId))
        .toList(growable: false);
  }

  int _minuteStamp(DateTime value) => DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      ).millisecondsSinceEpoch;

  TodoStatus _effectiveTodoStatus(TodoItem item, DateTime referenceNow) {
    if (item.status == TodoStatus.done ||
        item.status == TodoStatus.skipped ||
        item.status == TodoStatus.overdue) {
      return item.status;
    }
    if (item.dueAt.isBefore(referenceNow)) {
      return TodoStatus.overdue;
    }
    return item.status;
  }

  ReminderStatus _effectiveReminderStatus(
    ReminderItem item,
    DateTime referenceNow,
  ) {
    if (item.status == ReminderStatus.done ||
        item.status == ReminderStatus.skipped ||
        item.status == ReminderStatus.overdue) {
      return item.status;
    }
    if (item.scheduledAt.isBefore(referenceNow)) {
      return ReminderStatus.overdue;
    }
    return item.status;
  }

  String _petName(String petId) {
    final pet = _findPet(petId);
    return pet?.name ?? '未命名爱宠';
  }

  Pet? _findPet(String petId) {
    return _petsById[petId];
  }

  Pet? petById(String petId) => _findPet(petId);

  TodoItem _requireTodo(String todoId) {
    final item = _todosById[todoId];
    if (item == null) {
      throw StateError('No element');
    }
    return item;
  }

  ReminderItem _requireReminder(String reminderId) {
    final item = _remindersById[reminderId];
    if (item == null) {
      throw StateError('No element');
    }
    return item;
  }

  Future<void> _saveState({
    bool pets = false,
    bool todos = false,
    bool reminders = false,
    bool records = false,
    bool overviewConfig = false,
    bool overviewAiReport = false,
  }) async {
    final storage = _storage;
    if (storage == null) {
      return;
    }
    if (pets) {
      await _writeEntityTableIfChanged(
        storage,
        PetNoteLocalTable.pets,
        _pets.map((pet) => pet.toJson()).toList(growable: false),
        _encodePetsTable,
      );
    }
    if (todos) {
      await _writeEntityTableIfChanged(
        storage,
        PetNoteLocalTable.todos,
        _todos.map((item) => item.toJson()).toList(growable: false),
        _encodeTodosTable,
      );
    }
    if (reminders) {
      await _writeEntityTableIfChanged(
        storage,
        PetNoteLocalTable.reminders,
        _reminders.map((item) => item.toJson()).toList(growable: false),
        _encodeRemindersTable,
      );
    }
    if (records) {
      await _writeEntityTableIfChanged(
        storage,
        PetNoteLocalTable.records,
        _records.map((item) => item.toJson()).toList(growable: false),
        _encodeRecordsTable,
      );
    }
    if (overviewConfig) {
      await _writeTableIfChanged(
        storage,
        PetNoteLocalTable.overviewConfig,
        _encodeOverviewConfigTable(),
      );
    }
    if (overviewAiReport) {
      final encodedOverviewAiReport = _encodeOverviewAiReportTable();
      if (encodedOverviewAiReport == null) {
        await _removeTableIfPresent(
            storage, PetNoteLocalTable.overviewAiReport);
      } else {
        await _writeTableIfChanged(
          storage,
          PetNoteLocalTable.overviewAiReport,
          encodedOverviewAiReport,
        );
      }
    }
    if (pets || todos || reminders || records) {
      _overviewEntityStorageFresh = true;
    }
  }

  void _refreshPersistedTableSnapshots() {
    _refreshPersistedTableSnapshot(PetNoteLocalTable.pets, _encodePetsTable);
    _refreshPersistedTableSnapshot(PetNoteLocalTable.todos, _encodeTodosTable);
    _refreshPersistedTableSnapshot(
      PetNoteLocalTable.reminders,
      _encodeRemindersTable,
    );
    _refreshPersistedTableSnapshot(
      PetNoteLocalTable.records,
      _encodeRecordsTable,
    );
    _persistedTableSnapshots[PetNoteLocalTable.overviewConfig] =
        _encodeOverviewConfigTable();
    _persistedTableSnapshots[PetNoteLocalTable.overviewAiReport] =
        _encodeOverviewAiReportTable();
    _persistedTableSnapshots[PetNoteLocalTable.pendingMutations] =
        _encodePendingMutationsTable();
  }

  void _refreshPersistedTableSnapshot(
    PetNoteLocalTable table,
    String Function() encode,
  ) {
    if (_storage?.usesEntityRows(table) ?? false) {
      _persistedTableSnapshots.remove(table);
      return;
    }
    _persistedTableSnapshots[table] = encode();
  }

  Future<void> _writeEntityTableIfChanged(
    PetNoteLocalStorage storage,
    PetNoteLocalTable table,
    List<Map<String, Object?>> values,
    String Function() encode,
  ) async {
    if (storage.usesEntityRows(table)) {
      await storage.writeEntityTable(table, values);
      return;
    }
    await _writeTableIfChanged(storage, table, encode());
  }

  Future<void> _writeTableIfChanged(
    PetNoteLocalStorage storage,
    PetNoteLocalTable table,
    String value,
  ) async {
    if (_persistedTableSnapshots[table] == value) {
      return;
    }
    await storage.writeTable(table, value);
    _persistedTableSnapshots[table] = value;
  }

  Future<void> _removeTableIfPresent(
    PetNoteLocalStorage storage,
    PetNoteLocalTable table,
  ) async {
    if (_persistedTableSnapshots[table] == null) {
      return;
    }
    await storage.removeTable(table);
    _persistedTableSnapshots[table] = null;
  }

  String _encodePetsTable() {
    return jsonEncode(_pets.map((pet) => pet.toJson()).toList());
  }

  String _encodeTodosTable() {
    return jsonEncode(_todos.map((item) => item.toJson()).toList());
  }

  String _encodeRemindersTable() {
    return jsonEncode(_reminders.map((item) => item.toJson()).toList());
  }

  String _encodeRecordsTable() {
    return jsonEncode(_records.map((item) => item.toJson()).toList());
  }

  String _encodeOverviewConfigTable() {
    return jsonEncode(_encodeOverviewAnalysisConfig());
  }

  String? _encodeOverviewAiReportTable() {
    final encodedOverviewAiReport = _encodeOverviewAiReportState();
    return encodedOverviewAiReport == null
        ? null
        : jsonEncode(encodedOverviewAiReport);
  }

  String _encodePendingMutationsTable() {
    return jsonEncode(
      _pendingLocalMutations.values
          .map((mutation) => mutation.toJson())
          .toList(growable: false),
    );
  }

  Future<void> _savePendingLocalMutations({bool force = false}) async {
    final storage = _storage;
    if (storage == null) {
      return;
    }
    final encodedPendingMutations = _encodePendingMutationsTable();
    if (force) {
      await storage.writeTable(
        PetNoteLocalTable.pendingMutations,
        encodedPendingMutations,
      );
      _persistedTableSnapshots[PetNoteLocalTable.pendingMutations] =
          encodedPendingMutations;
      return;
    }
    await _writeTableIfChanged(
      storage,
      PetNoteLocalTable.pendingMutations,
      encodedPendingMutations,
    );
  }

  Future<void> _resetPendingLocalMutations() async {
    _pendingLocalMutations.clear();
    await _savePendingLocalMutations(force: true);
  }

  String _avatarTextForName(String name) {
    final trimmed = name.trim();
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed.substring(0, 1).toUpperCase();
  }

  static List<Pet> _decodePetsFromStorage(PetNoteLocalStorage? storage) {
    return _decodeRows(
            storage?.readEntityTable(PetNoteLocalTable.pets), Pet.fromJson) ??
        _decodeList(storage?.readTable(PetNoteLocalTable.pets), Pet.fromJson);
  }

  static List<TodoItem> _decodeTodosFromStorage(PetNoteLocalStorage? storage) {
    return _decodeRows(storage?.readEntityTable(PetNoteLocalTable.todos),
            TodoItem.fromJson) ??
        _decodeList(
          storage?.readTable(PetNoteLocalTable.todos),
          TodoItem.fromJson,
        );
  }

  static List<ReminderItem> _decodeRemindersFromStorage(
    PetNoteLocalStorage? storage,
  ) {
    return _decodeRows(
          storage?.readEntityTable(PetNoteLocalTable.reminders),
          ReminderItem.fromJson,
        ) ??
        _decodeList(
          storage?.readTable(PetNoteLocalTable.reminders),
          ReminderItem.fromJson,
        );
  }

  static List<PetRecord> _decodeRecordsFromStorage(
    PetNoteLocalStorage? storage,
  ) {
    return _decodeRows(
          storage?.readEntityTable(PetNoteLocalTable.records),
          PetRecord.fromJson,
        ) ??
        _decodeList(
          storage?.readTable(PetNoteLocalTable.records),
          PetRecord.fromJson,
        );
  }

  static List<PetNoteMutation> _decodePendingMutationsFromStorage(
    PetNoteLocalStorage? storage,
  ) {
    return _decodeList(
      storage?.readTable(PetNoteLocalTable.pendingMutations),
      PetNoteMutation.fromJson,
    );
  }

  static OverviewAnalysisConfig? _decodeOverviewAnalysisConfig(
    String? encoded,
  ) {
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      return OverviewAnalysisConfig(
        range: _overviewRangeFromName(json['range'] as String?),
        selectedPetIds: _stringList(json['selectedPetIds']),
        customRangeStart: _optionalDateTime(json['customRangeStart']),
        customRangeEnd: _optionalDateTime(json['customRangeEnd']),
      );
    } catch (_) {
      return null;
    }
  }

  static OverviewAiReportState? _decodeOverviewAiReportState(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      final requestKey = json['requestKey'] as String?;
      final rawReport = json['report'];
      if (requestKey == null || requestKey.isEmpty || rawReport is! Map) {
        return null;
      }
      return OverviewAiReportState(
        status: OverviewAiReportStatus.ready,
        requestKey: requestKey,
        report:
            AiCareReport.fromStoredJson(Map<String, dynamic>.from(rawReport)),
        hasRequested: true,
      );
    } catch (_) {
      return null;
    }
  }

  static List<T> _decodeList<T>(
    String? encoded,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (encoded == null || encoded.isEmpty) {
      return <T>[];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return <T>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static List<T>? _decodeRows<T>(
    List<Map<String, Object?>>? rows,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    return rows
        ?.map((item) => fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Map<String, dynamic> _encodeOverviewAnalysisConfig() {
    return {
      'range': _overviewRange.name,
      'selectedPetIds': _effectiveOverviewSelectedPetIds(),
      'customRangeStart': _overviewCustomRangeStart?.toIso8601String(),
      'customRangeEnd': _overviewCustomRangeEnd?.toIso8601String(),
    };
  }

  Map<String, dynamic>? _encodeOverviewAiReportState() {
    final requestKey = _overviewAiReportState.requestKey;
    final report = _overviewAiReportState.report;
    if (requestKey == null || requestKey.isEmpty || report == null) {
      return null;
    }
    return {
      'requestKey': requestKey,
      'report': report.toJson(),
    };
  }

  void _restoreOverviewAiReportState(OverviewAiReportState state) {
    final requestKey = state.requestKey;
    final report = state.report;
    if (requestKey == null || requestKey.isEmpty || report == null) {
      return;
    }
    _overviewAiReportState = OverviewAiReportState(
      status: OverviewAiReportStatus.ready,
      requestKey: requestKey,
      report: report,
      hasRequested: true,
      activeRequestToken: _overviewAiRequestToken,
    );
  }

  static String _overviewAiHistoryLabelFromRequestKey(String requestKey) {
    try {
      final decoded = jsonDecode(requestKey);
      if (decoded is! Map) {
        return 'AI 照护总结';
      }
      final json = Map<String, dynamic>.from(decoded);
      final title = json['title'] as String?;
      if (title != null && title.trim().isNotEmpty) {
        return title.trim();
      }
      final rangeLabel = json['rangeLabel'] as String?;
      if (rangeLabel != null && rangeLabel.trim().isNotEmpty) {
        return rangeLabel.trim();
      }
    } catch (_) {
      // 历史 requestKey 不是有效 JSON 时，退回统一文案。
    }
    return 'AI 照护总结';
  }

  static OverviewRange _overviewRangeFromName(String? value) => switch (value) {
        'oneMonth' => OverviewRange.oneMonth,
        'threeMonths' => OverviewRange.threeMonths,
        'sixMonths' => OverviewRange.sixMonths,
        'oneYear' => OverviewRange.oneYear,
        'custom' => OverviewRange.custom,
        _ => OverviewRange.sevenDays,
      };

  static DateTime? _optionalDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String _todoStatusLabel(TodoStatus status) => switch (status) {
        TodoStatus.done => '已完成',
        TodoStatus.postponed => '已延后',
        TodoStatus.skipped => '已跳过',
        TodoStatus.overdue => '已逾期',
        TodoStatus.open => '待处理',
      };

  String _reminderStatusLabel(ReminderStatus status) => switch (status) {
        ReminderStatus.done => '已完成',
        ReminderStatus.postponed => '已延后',
        ReminderStatus.skipped => '已跳过',
        ReminderStatus.overdue => '已逾期',
        ReminderStatus.pending => '待提醒',
      };

  void _validateDataState(PetNoteDataState state) {
    _ensureUniqueIds(state.pets.map((pet) => pet.id), '宠物');
    _ensureUniqueIds(state.todos.map((item) => item.id), '待办');
    _ensureUniqueIds(state.reminders.map((item) => item.id), '提醒');
    _ensureUniqueIds(state.records.map((item) => item.id), '记录');

    final petIds = state.pets.map((pet) => pet.id).toSet();
    final invalidTodo = state.todos
        .where((item) => !petIds.contains(item.petId))
        .map((item) => item.title)
        .toList();
    if (invalidTodo.isNotEmpty) {
      throw StateError('待办引用了不存在的宠物。');
    }
    final invalidReminder = state.reminders
        .where((item) => !petIds.contains(item.petId))
        .map((item) => item.title)
        .toList();
    if (invalidReminder.isNotEmpty) {
      throw StateError('提醒引用了不存在的宠物。');
    }
    final invalidRecord = state.records
        .where((item) => !petIds.contains(item.petId))
        .map((item) => item.title)
        .toList();
    if (invalidRecord.isNotEmpty) {
      throw StateError('记录引用了不存在的宠物。');
    }
  }

  void _ensureUniqueIds(Iterable<String> ids, String label) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw StateError('$label 数据包内存在重复 ID。');
      }
    }
  }

  void _ensureNoConflicts({
    required Iterable<String> currentIds,
    required Iterable<String> incomingIds,
    required String label,
  }) {
    final current = currentIds.toSet();
    for (final id in incomingIds) {
      if (current.contains(id)) {
        throw StateError('$label 存在重复 ID，无法追加导入。');
      }
    }
  }

  Future<void> _mergeById<T>({
    required List<T> current,
    required List<T> incoming,
    required String Function(T item) idOf,
    required Map<String, T> index,
    required String collectionLabel,
    required String Function(T item) labelOf,
    required Map<String, dynamic> Function(T item) jsonOf,
    required SyncMergeConflictResolver? resolveConflict,
  }) async {
    for (final item in incoming) {
      final id = idOf(item);
      final existingIndex = current.indexWhere((currentItem) {
        return idOf(currentItem) == id;
      });
      if (existingIndex == -1) {
        current.add(item);
        index[id] = item;
        continue;
      }
      final existingItem = current[existingIndex];
      if (resolveConflict == null) {
        _promoteCompletionState(existingItem, item);
      }
      final existingJson = jsonOf(existingItem);
      final incomingJson = jsonOf(item);
      if (_jsonEquals(existingJson, incomingJson)) {
        index[id] = existingItem;
        continue;
      }
      final side = await resolveConflict?.call(
            SyncMergeConflict(
              collectionLabel: collectionLabel,
              id: id,
              localLabel: labelOf(existingItem),
              remoteLabel: labelOf(item),
              differences: _mergeDifferences(existingJson, incomingJson),
            ),
          ) ??
          SyncMergeSide.local;
      if (side == SyncMergeSide.remote) {
        current[existingIndex] = item;
        index[id] = item;
      } else {
        index[id] = existingItem;
      }
    }
  }

  void _mergeIncomingEntitiesPreservingConflictingIds<T>({
    required List<T> current,
    required List<T> incoming,
    required String Function(T item) idOf,
    required Map<String, T> index,
    required Map<String, dynamic> Function(T item) jsonOf,
    required T Function(T item, String id) cloneWithIds,
    required String idPrefix,
    required String? sourceNamespace,
    required String? localNamespace,
    required Set<String> importedKeys,
  }) {
    for (final item in incoming) {
      final id = idOf(item);
      final preparedItem = cloneWithIds(item, id);
      final mergeKey = _mergeEntityKey(idPrefix, id, jsonOf(preparedItem));
      if (!importedKeys.add(mergeKey)) {
        continue;
      }
      final mergedId = _mergedIdFor(
        prefix: idPrefix,
        sourceId: id,
        json: jsonOf(preparedItem),
        sourceNamespace: sourceNamespace,
        localNamespace: localNamespace,
        index: index,
      );
      final existingItem = index[id];
      if (existingItem == null && mergedId == id) {
        current.add(preparedItem);
        index[id] = preparedItem;
        continue;
      }
      if (existingItem != null &&
          mergedId == id &&
          _jsonEquals(jsonOf(existingItem), jsonOf(preparedItem))) {
        continue;
      }
      final importedItem = index[mergedId];
      if (importedItem != null) {
        final cloned = cloneWithIds(item, mergedId);
        final existingIndex =
            current.indexWhere((currentItem) => idOf(currentItem) == mergedId);
        if (existingIndex == -1) {
          current.add(cloned);
        } else {
          current[existingIndex] = cloned;
        }
        index[mergedId] = cloned;
        continue;
      }
      final cloned = cloneWithIds(item, mergedId);
      current.add(cloned);
      index[idOf(cloned)] = cloned;
    }
  }

  bool _jsonEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
    return jsonEncode(_conflictComparableJson(left)) ==
        jsonEncode(_conflictComparableJson(right));
  }

  Map<String, dynamic> _conflictComparableJson(Map<String, dynamic> source) {
    return {
      for (final entry in source.entries)
        if (entry.key != 'semantic') entry.key: entry.value,
    };
  }

  String _mergeEntityKey(
    String prefix,
    String sourceId,
    Map<String, dynamic> json,
  ) {
    return '$prefix:${_sanitizeIdSegment(sourceId)}:${_entityFingerprint(json)}';
  }

  String _matchImportedEntityId<T>(
    Iterable<T> items,
    T source,
    String Function(T item) idOf,
  ) {
    for (final item in items) {
      if (idOf(item) == idOf(source)) {
        return idOf(item);
      }
    }
    return idOf(source);
  }

  String _mergedIdFor<T>({
    required String prefix,
    required String sourceId,
    required Map<String, dynamic> json,
    required String? sourceNamespace,
    required String? localNamespace,
    required Map<String, T> index,
  }) {
    final stableId = _decodeStableMergedId(prefix, sourceId);
    final normalizedLocalNamespace = _normalizedSourceNamespace(localNamespace);
    if (stableId != null) {
      if (stableId.namespace == normalizedLocalNamespace) {
        return stableId.sourceId;
      }
      return sourceId;
    }
    final normalizedNamespace = _normalizedSourceNamespace(sourceNamespace);
    if (normalizedNamespace != null) {
      return '$prefix-merge-$normalizedNamespace-${_sanitizeIdSegment(sourceId)}';
    }
    return '$prefix-merge-${_sanitizeIdSegment(sourceId)}-${_entityFingerprint(json)}';
  }

  String? _normalizedSourceNamespace(String? sourceNamespace) {
    if (sourceNamespace == null || sourceNamespace.isEmpty) {
      return null;
    }
    return _sanitizeIdSegment(sourceNamespace);
  }

  String _remoteStableId({
    required String prefix,
    required String sourceId,
    required String? sourceNamespace,
  }) {
    final normalizedNamespace = _normalizedSourceNamespace(sourceNamespace);
    if (normalizedNamespace == null) {
      return sourceId;
    }
    return '$prefix-merge-$normalizedNamespace-${_sanitizeIdSegment(sourceId)}';
  }

  bool _hasStableMergedEntityForSource({
    required Iterable<String> ids,
    required String prefix,
    required String namespace,
  }) {
    for (final id in ids) {
      final stableId = _decodeStableMergedId(prefix, id);
      if (stableId != null && stableId.namespace == namespace) {
        return true;
      }
    }
    return false;
  }

  String _mappedRemoteEntityId({
    required PetNoteEntityType entityType,
    required String sourceId,
    required String? sourceNamespace,
    required String? localNamespace,
  }) {
    final prefix = _idPrefixForEntityType(entityType);
    final stableId = _decodeStableMergedId(prefix, sourceId);
    final normalizedLocalNamespace = _normalizedSourceNamespace(localNamespace);
    if (stableId != null) {
      if (stableId.namespace == normalizedLocalNamespace &&
          _hasEntityId(entityType, stableId.sourceId)) {
        return stableId.sourceId;
      }
      return sourceId;
    }
    final remoteStableId = _remoteStableId(
      prefix: prefix,
      sourceId: sourceId,
      sourceNamespace: sourceNamespace,
    );
    if (_hasEntityId(entityType, remoteStableId)) {
      return remoteStableId;
    }
    return sourceId;
  }

  PetNoteMutation _mappedRemoteMutation(
    PetNoteMutation mutation, {
    required String? sourceNamespace,
    required String? localNamespace,
  }) {
    if (_normalizedSourceNamespace(sourceNamespace) == null) {
      return mutation;
    }
    final mappedEntityId = _mappedRemoteEntityId(
      entityType: mutation.entityType,
      sourceId: mutation.entityId,
      sourceNamespace: sourceNamespace,
      localNamespace: localNamespace,
    );
    final data = mutation.data == null
        ? null
        : _mappedRemoteEntityData(
            entityType: mutation.entityType,
            data: mutation.data!,
            sourceNamespace: sourceNamespace,
            localNamespace: localNamespace,
          );
    return PetNoteMutation(
      id: mutation.id,
      entityType: mutation.entityType,
      entityId: mappedEntityId,
      kind: mutation.kind,
      data: data,
      actionKind: mutation.actionKind,
      occurredAtMs: mutation.occurredAtMs,
    );
  }

  Map<String, dynamic> _mappedRemoteEntityData({
    required PetNoteEntityType entityType,
    required Map<String, dynamic> data,
    required String? sourceNamespace,
    required String? localNamespace,
  }) {
    final mapped = Map<String, dynamic>.from(data);
    final rawId = mapped['id'];
    if (rawId is String && rawId.isNotEmpty) {
      mapped['id'] = _mappedRemoteEntityId(
        entityType: entityType,
        sourceId: rawId,
        sourceNamespace: sourceNamespace,
        localNamespace: localNamespace,
      );
    }
    if (entityType != PetNoteEntityType.pet) {
      final rawPetId = mapped['petId'];
      if (rawPetId is String && rawPetId.isNotEmpty) {
        mapped['petId'] = _mappedRemoteEntityId(
          entityType: PetNoteEntityType.pet,
          sourceId: rawPetId,
          sourceNamespace: sourceNamespace,
          localNamespace: localNamespace,
        );
      }
    }
    return mapped;
  }

  PetAction _mappedRemoteAction(
    PetAction action, {
    required String? sourceNamespace,
    required String? localNamespace,
  }) {
    if (_normalizedSourceNamespace(sourceNamespace) == null) {
      return action;
    }
    final entityType = switch (action.sourceType) {
      'todo' => PetNoteEntityType.todo,
      'reminder' => PetNoteEntityType.reminder,
      _ =>
        throw FormatException('unsupported source type: ${action.sourceType}'),
    };
    return PetAction(
      kind: action.kind,
      sourceType: action.sourceType,
      itemId: _mappedRemoteEntityId(
        entityType: entityType,
        sourceId: action.itemId,
        sourceNamespace: sourceNamespace,
        localNamespace: localNamespace,
      ),
      occurredAtMs: action.occurredAtMs,
    );
  }

  bool _hasEntityId(PetNoteEntityType entityType, String id) {
    return switch (entityType) {
      PetNoteEntityType.pet => _petsById.containsKey(id),
      PetNoteEntityType.todo => _todosById.containsKey(id),
      PetNoteEntityType.reminder => _remindersById.containsKey(id),
      PetNoteEntityType.record => _recordsById.containsKey(id),
    };
  }

  String _idPrefixForEntityType(PetNoteEntityType entityType) {
    return switch (entityType) {
      PetNoteEntityType.pet => 'pet',
      PetNoteEntityType.todo => 'todo',
      PetNoteEntityType.reminder => 'reminder',
      PetNoteEntityType.record => 'record',
    };
  }

  ({String namespace, String sourceId})? _decodeStableMergedId(
    String prefix,
    String value,
  ) {
    final marker = '$prefix-merge-';
    if (!value.startsWith(marker)) {
      return null;
    }
    final rest = value.substring(marker.length);
    final separatorIndex = rest.lastIndexOf('-$prefix-');
    if (separatorIndex <= 0) {
      return null;
    }
    return (
      namespace: rest.substring(0, separatorIndex),
      sourceId: rest.substring(separatorIndex + 1),
    );
  }

  String _sanitizeIdSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'remote' : sanitized;
  }

  String _entityFingerprint(Map<String, dynamic> json) {
    final comparable = Map<String, dynamic>.from(_conflictComparableJson(json))
      ..remove('id');
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode(comparable)))
        .replaceAll('=', '');
    final limit = encoded.length < 48 ? encoded.length : 48;
    return encoded.substring(0, limit);
  }

  Pet _petWithId(Pet item, String id) {
    return Pet(
      id: id,
      name: item.name,
      avatarText: item.avatarText,
      photoPath: item.photoPath,
      type: item.type,
      breed: item.breed,
      sex: item.sex,
      birthday: item.birthday,
      ageLabel: item.ageLabel,
      weightKg: item.weightKg,
      neuterStatus: item.neuterStatus,
      feedingPreferences: item.feedingPreferences,
      allergies: item.allergies,
      note: item.note,
    );
  }

  TodoItem _todoWithIds(TodoItem item,
      {required String id, required String petId}) {
    return TodoItem(
      id: id,
      petId: petId,
      title: item.title,
      dueAt: item.dueAt,
      notificationLeadTime: item.notificationLeadTime,
      status: item.status,
      note: item.note,
      semantic: item.semantic,
    );
  }

  ReminderItem _reminderWithIds(
    ReminderItem item, {
    required String id,
    required String petId,
  }) {
    return ReminderItem(
      id: id,
      petId: petId,
      kind: item.kind,
      title: item.title,
      scheduledAt: item.scheduledAt,
      notificationLeadTime: item.notificationLeadTime,
      recurrence: item.recurrence,
      status: item.status,
      note: item.note,
      semantic: item.semantic,
    );
  }

  PetRecord _recordWithIds(
    PetRecord item, {
    required String id,
    required String petId,
  }) {
    return PetRecord(
      id: id,
      petId: petId,
      type: item.type,
      title: item.title,
      recordDate: item.recordDate,
      summary: item.summary,
      note: item.note,
      purpose: item.purpose,
      customPurposeLabel: item.customPurposeLabel,
      photoPaths: item.photoPaths,
      semantic: item.semantic,
    );
  }

  void _promoteCompletionState<T>(T existingItem, T incomingItem) {
    if (existingItem is TodoItem && incomingItem is TodoItem) {
      if (existingItem.status != TodoStatus.done &&
          incomingItem.status == TodoStatus.done) {
        existingItem.status = TodoStatus.done;
      }
      return;
    }
    if (existingItem is ReminderItem && incomingItem is ReminderItem) {
      if (existingItem.status != ReminderStatus.done &&
          incomingItem.status == ReminderStatus.done) {
        existingItem.status = ReminderStatus.done;
      }
    }
  }

  List<SyncMergeDifference> _mergeDifferences(
    Map<String, dynamic> localJson,
    Map<String, dynamic> remoteJson,
  ) {
    final differences = <SyncMergeDifference>[];
    void collect(String path, Object? localValue, Object? remoteValue) {
      if (path == 'semantic' || path.startsWith('semantic.')) {
        return;
      }
      if (localValue is Map && remoteValue is Map) {
        final keys = <String>{
          ...localValue.keys.map((key) => key.toString()),
          ...remoteValue.keys.map((key) => key.toString()),
        };
        for (final key in keys) {
          collect(
            path.isEmpty ? key : '$path.$key',
            localValue[key],
            remoteValue[key],
          );
        }
        return;
      }
      if (jsonEncode(localValue) == jsonEncode(remoteValue)) {
        return;
      }
      differences.add(SyncMergeDifference(
        fieldPath: path,
        localValue: localValue,
        remoteValue: remoteValue,
      ));
    }

    collect('', localJson, remoteJson);
    return differences;
  }

  bool _migrateLegacySemanticData() {
    var changed = false;
    for (var index = 0; index < _todos.length; index += 1) {
      final item = _todos[index];
      if (item.semantic != null) {
        continue;
      }
      _todos[index] = TodoItem(
        id: item.id,
        petId: item.petId,
        title: item.title,
        dueAt: item.dueAt,
        notificationLeadTime: item.notificationLeadTime,
        status: item.status,
        note: item.note,
        semantic: _inferTodoSemantic(
          title: item.title,
          note: item.note,
          dueAt: item.dueAt,
          status: item.status,
        ),
      );
      changed = true;
    }
    for (var index = 0; index < _reminders.length; index += 1) {
      final item = _reminders[index];
      if (item.semantic != null) {
        continue;
      }
      _reminders[index] = ReminderItem(
        id: item.id,
        petId: item.petId,
        kind: item.kind,
        title: item.title,
        scheduledAt: item.scheduledAt,
        notificationLeadTime: item.notificationLeadTime,
        recurrence: item.recurrence,
        status: item.status,
        note: item.note,
        semantic: _inferReminderSemantic(
          kind: item.kind,
          title: item.title,
          note: item.note,
          scheduledAt: item.scheduledAt,
          status: item.status,
        ),
      );
      changed = true;
    }
    for (var index = 0; index < _records.length; index += 1) {
      final item = _records[index];
      if (item.semantic != null) {
        continue;
      }
      _records[index] = PetRecord(
        id: item.id,
        petId: item.petId,
        type: item.type,
        title: item.title,
        recordDate: item.recordDate,
        summary: item.summary,
        note: item.note,
        semantic: _inferRecordSemantic(
          type: item.type,
          title: item.title,
          summary: item.summary,
          note: item.note,
          recordDate: item.recordDate,
        ),
      );
      changed = true;
    }
    if (changed) {
      _rebuildTodoIndex();
      _rebuildReminderIndex();
      _rebuildRecordIndex();
      _invalidateAllDerivedData();
    }
    return changed;
  }

  bool _migrateLegacyPetPhotoPaths(String? petPhotoDirectoryPath) {
    var changed = false;
    for (var index = 0; index < _pets.length; index += 1) {
      final pet = _pets[index];
      final relocatedPath = PetPhotoPathResolver.relocateLegacyPath(
        pet.photoPath,
        petPhotoDirectoryPath: petPhotoDirectoryPath,
      );
      if (relocatedPath == null || relocatedPath == pet.photoPath) {
        continue;
      }
      final migratedPet = Pet(
        id: pet.id,
        name: pet.name,
        avatarText: pet.avatarText,
        photoPath: relocatedPath,
        type: pet.type,
        breed: pet.breed,
        sex: pet.sex,
        birthday: pet.birthday,
        ageLabel: pet.ageLabel,
        weightKg: pet.weightKg,
        neuterStatus: pet.neuterStatus,
        feedingPreferences: pet.feedingPreferences,
        allergies: pet.allergies,
        note: pet.note,
      );
      _pets[index] = migratedPet;
      _petsById[migratedPet.id] = migratedPet;
      changed = true;
    }
    if (changed) {
      _invalidateAllDerivedData();
    }
    return changed;
  }

  bool _needsLegacyPetPhotoPathMigration() {
    return _pets.any(
      (pet) => PetPhotoPathResolver.shouldAttemptLegacyRelocation(
        pet.photoPath,
      ),
    );
  }

  PetNoteDataState _normalizedDataState(PetNoteDataState state) {
    return PetNoteDataState(
      pets: List<Pet>.from(state.pets),
      todos: state.todos
          .map(
            (item) => item.semantic != null
                ? item
                : TodoItem(
                    id: item.id,
                    petId: item.petId,
                    title: item.title,
                    dueAt: item.dueAt,
                    notificationLeadTime: item.notificationLeadTime,
                    status: item.status,
                    note: item.note,
                    semantic: _inferTodoSemantic(
                      title: item.title,
                      note: item.note,
                      dueAt: item.dueAt,
                      status: item.status,
                    ),
                  ),
          )
          .toList(growable: false),
      reminders: state.reminders
          .map(
            (item) => item.semantic != null
                ? item
                : ReminderItem(
                    id: item.id,
                    petId: item.petId,
                    kind: item.kind,
                    title: item.title,
                    scheduledAt: item.scheduledAt,
                    notificationLeadTime: item.notificationLeadTime,
                    recurrence: item.recurrence,
                    status: item.status,
                    note: item.note,
                    semantic: _inferReminderSemantic(
                      kind: item.kind,
                      title: item.title,
                      note: item.note,
                      scheduledAt: item.scheduledAt,
                      status: item.status,
                    ),
                  ),
          )
          .toList(growable: false),
      records: state.records
          .map(
            (item) => item.semantic != null
                ? item
                : PetRecord(
                    id: item.id,
                    petId: item.petId,
                    type: item.type,
                    title: item.title,
                    recordDate: item.recordDate,
                    summary: item.summary,
                    note: item.note,
                    semantic: _inferRecordSemantic(
                      type: item.type,
                      title: item.title,
                      summary: item.summary,
                      note: item.note,
                      recordDate: item.recordDate,
                    ),
                  ),
          )
          .toList(growable: false),
    );
  }
}

PetType _petTypeFromName(String? value) => switch (value) {
      'cat' => PetType.cat,
      'dog' => PetType.dog,
      'rabbit' => PetType.rabbit,
      'bird' => PetType.bird,
      _ => PetType.other,
    };

PetNeuterStatus _petNeuterStatusFromName(String? value) => switch (value) {
      'neutered' => PetNeuterStatus.neutered,
      'notNeutered' => PetNeuterStatus.notNeutered,
      _ => PetNeuterStatus.unknown,
    };

String petTypeLabel(PetType type) => switch (type) {
      PetType.cat => '猫',
      PetType.dog => '狗',
      PetType.rabbit => '兔',
      PetType.bird => '鸟',
      PetType.other => '其他',
    };

String petNeuterStatusLabel(PetNeuterStatus status) => switch (status) {
      PetNeuterStatus.neutered => '已绝育',
      PetNeuterStatus.notNeutered => '未绝育',
      PetNeuterStatus.unknown => '暂不确定',
    };

TodoStatus _todoStatusFromName(String? value) => switch (value) {
      'done' => TodoStatus.done,
      'skipped' => TodoStatus.skipped,
      'postponed' => TodoStatus.postponed,
      'overdue' => TodoStatus.overdue,
      _ => TodoStatus.open,
    };

TodoStatus _todoStatusForAction(PetActionKind kind) => switch (kind) {
      PetActionKind.markDone => TodoStatus.done,
      PetActionKind.postpone => TodoStatus.postponed,
      PetActionKind.skip => TodoStatus.skipped,
    };

ReminderKind _reminderKindFromName(String? value) => switch (value) {
      'vaccine' => ReminderKind.vaccine,
      'deworming' => ReminderKind.deworming,
      'medication' => ReminderKind.medication,
      'review' => ReminderKind.review,
      'grooming' => ReminderKind.grooming,
      _ => ReminderKind.custom,
    };

ReminderStatus _reminderStatusFromName(String? value) => switch (value) {
      'done' => ReminderStatus.done,
      'skipped' => ReminderStatus.skipped,
      'postponed' => ReminderStatus.postponed,
      'overdue' => ReminderStatus.overdue,
      _ => ReminderStatus.pending,
    };

ReminderStatus _reminderStatusForAction(PetActionKind kind) => switch (kind) {
      PetActionKind.markDone => ReminderStatus.done,
      PetActionKind.postpone => ReminderStatus.postponed,
      PetActionKind.skip => ReminderStatus.skipped,
    };

NotificationLeadTime _notificationLeadTimeFromName(String? value) =>
    switch (value) {
      'fiveMinutes' => NotificationLeadTime.fiveMinutes,
      'fifteenMinutes' => NotificationLeadTime.fifteenMinutes,
      'oneHour' => NotificationLeadTime.oneHour,
      'oneDay' => NotificationLeadTime.oneDay,
      'threeDays' => NotificationLeadTime.threeDays,
      'sevenDays' => NotificationLeadTime.sevenDays,
      _ => NotificationLeadTime.none,
    };

Duration leadTimeDuration(NotificationLeadTime leadTime) => switch (leadTime) {
      NotificationLeadTime.none => Duration.zero,
      NotificationLeadTime.fiveMinutes => const Duration(minutes: 5),
      NotificationLeadTime.fifteenMinutes => const Duration(minutes: 15),
      NotificationLeadTime.oneHour => const Duration(hours: 1),
      NotificationLeadTime.oneDay => const Duration(days: 1),
      NotificationLeadTime.threeDays => const Duration(days: 3),
      NotificationLeadTime.sevenDays => const Duration(days: 7),
    };

String notificationLeadTimeLabel(NotificationLeadTime leadTime) =>
    switch (leadTime) {
      NotificationLeadTime.none => '准时',
      NotificationLeadTime.fiveMinutes => '提前5分钟',
      NotificationLeadTime.fifteenMinutes => '提前15分钟',
      NotificationLeadTime.oneHour => '提前1小时',
      NotificationLeadTime.oneDay => '提前1天',
      NotificationLeadTime.threeDays => '提前3天',
      NotificationLeadTime.sevenDays => '提前7天',
    };

String _overviewTitle(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '最近 7 天 AI 照护总结',
      OverviewRange.oneMonth => '最近 1 个月 AI 照护总结',
      OverviewRange.threeMonths => '最近 3 个月 AI 照护总结',
      OverviewRange.sixMonths => '最近 6 个月 AI 照护总结',
      OverviewRange.oneYear => '最近 1 年 AI 照护总结',
      OverviewRange.custom => '自定义区间 AI 照护总结',
    };

String _overviewRangeLabel(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '最近 7 天',
      OverviewRange.oneMonth => '最近 1 个月',
      OverviewRange.threeMonths => '最近 3 个月',
      OverviewRange.sixMonths => '最近 6 个月',
      OverviewRange.oneYear => '最近 1 年',
      OverviewRange.custom => '自定义',
    };

PetRecordType _petRecordTypeFromName(String? value) => switch (value) {
      'medical' => PetRecordType.medical,
      'receipt' => PetRecordType.receipt,
      'image' => PetRecordType.image,
      'testResult' => PetRecordType.testResult,
      _ => PetRecordType.other,
    };

RecordPurpose? _recordPurposeFromName(String? value) => switch (value) {
      'health' => RecordPurpose.health,
      'life' => RecordPurpose.life,
      'expense' => RecordPurpose.expense,
      'other' => RecordPurpose.other,
      _ => null,
    };

SemanticTopicKey _semanticTopicKeyFromName(String? value) => switch (value) {
      'hydration' => SemanticTopicKey.hydration,
      'diet' => SemanticTopicKey.diet,
      'deworming' => SemanticTopicKey.deworming,
      'litter' => SemanticTopicKey.litter,
      'grooming' => SemanticTopicKey.grooming,
      'earCare' => SemanticTopicKey.earCare,
      'medication' => SemanticTopicKey.medication,
      'vaccine' => SemanticTopicKey.vaccine,
      'review' => SemanticTopicKey.review,
      'weight' => SemanticTopicKey.weight,
      'digestive' => SemanticTopicKey.digestive,
      'skin' => SemanticTopicKey.skin,
      'purchase' => SemanticTopicKey.purchase,
      'cleaning' => SemanticTopicKey.cleaning,
      _ => SemanticTopicKey.other,
    };

SemanticSignal _semanticSignalFromName(String? value) => switch (value) {
      'stable' => SemanticSignal.stable,
      'improved' => SemanticSignal.improved,
      'worsened' => SemanticSignal.worsened,
      'attention' => SemanticSignal.attention,
      'completed' => SemanticSignal.completed,
      'missed' => SemanticSignal.missed,
      'scheduled' => SemanticSignal.scheduled,
      _ => SemanticSignal.info,
    };

SemanticActionIntent? _semanticActionIntentFromName(String? value) =>
    switch (value) {
      'observe' => SemanticActionIntent.observe,
      'administer' => SemanticActionIntent.administer,
      'buy' => SemanticActionIntent.buy,
      'clean' => SemanticActionIntent.clean,
      'record' => SemanticActionIntent.record,
      'review' => SemanticActionIntent.review,
      'custom' => SemanticActionIntent.custom,
      _ => null,
    };

SemanticEvidenceSource? _semanticEvidenceSourceFromName(String? value) =>
    switch (value) {
      'home' => SemanticEvidenceSource.home,
      'vet' => SemanticEvidenceSource.vet,
      'lab' => SemanticEvidenceSource.lab,
      'receipt' => SemanticEvidenceSource.receipt,
      'other' => SemanticEvidenceSource.other,
      _ => null,
    };

String _defaultTodoTitle(SemanticEventDetails? semantic, String note) {
  if (semantic == null) {
    return note.isEmpty ? '新增待办' : _truncateSemanticText(note, 18);
  }
  return switch (semantic.intent ?? SemanticActionIntent.custom) {
    SemanticActionIntent.buy => '补货采购',
    SemanticActionIntent.clean => '安排清洁',
    SemanticActionIntent.administer => '执行护理',
    SemanticActionIntent.observe => '继续观察',
    SemanticActionIntent.record => '补充记录',
    SemanticActionIntent.review => '安排复查',
    SemanticActionIntent.custom => '新增待办',
  };
}

String _defaultReminderTitle(
  ReminderKind kind,
  SemanticEventDetails? semantic,
) {
  if (semantic != null && semantic.evidenceSummary.isNotEmpty) {
    return _truncateSemanticText(semantic.evidenceSummary, 18);
  }
  return switch (kind) {
    ReminderKind.vaccine => '疫苗提醒',
    ReminderKind.deworming => '驱虫提醒',
    ReminderKind.medication => '用药提醒',
    ReminderKind.review => '复查提醒',
    ReminderKind.grooming => '洗护提醒',
    ReminderKind.custom => '事项提醒',
  };
}

String _defaultRecordTitle(
  PetRecordType type,
  SemanticEventDetails? semantic, {
  RecordPurpose? purpose,
  String? customPurposeLabel,
}) {
  if (semantic != null && semantic.evidenceSummary.isNotEmpty) {
    return _truncateSemanticText(semantic.evidenceSummary, 18);
  }
  if (purpose != null) {
    return switch (purpose) {
      RecordPurpose.health => '健康记录',
      RecordPurpose.life => '生活记录',
      RecordPurpose.expense => '消费记录',
      RecordPurpose.other => (customPurposeLabel?.trim().isNotEmpty ?? false)
          ? '${customPurposeLabel!.trim()}记录'
          : '其他记录',
    };
  }
  return switch (type) {
    PetRecordType.medical => '就诊记录',
    PetRecordType.receipt => '消费记录',
    PetRecordType.image => '影像记录',
    PetRecordType.testResult => '检查结果',
    PetRecordType.other => '日常记录',
  };
}

SemanticEventDetails _inferTodoSemantic({
  required String title,
  required String note,
  required DateTime dueAt,
  required TodoStatus status,
}) {
  final topic = _inferTopicFromText('$title $note');
  return SemanticEventDetails(
    topicKey: topic,
    signal: _semanticSignalForTodoStatus(status),
    tags: _tagsForTopic(topic),
    evidenceSummary: _buildEvidenceSummary([title, note]),
    actionSummary: '计划在${_formatSemanticDate(dueAt)}前处理。',
    followUpAt: dueAt,
    measurements: _extractMeasurementsFromText('$title $note'),
    intent: _intentForTodoTopic(topic),
    source: null,
  );
}

SemanticEventDetails _inferReminderSemantic({
  required ReminderKind kind,
  required String title,
  required String note,
  required DateTime scheduledAt,
  required ReminderStatus status,
}) {
  final topic = _topicForReminderKind(kind, title, note);
  return SemanticEventDetails(
    topicKey: topic,
    signal: _semanticSignalForReminderStatus(status),
    tags: _tagsForTopic(topic),
    evidenceSummary: _buildEvidenceSummary([title, note]),
    actionSummary: '计划在${_formatSemanticDate(scheduledAt)}执行提醒事项。',
    followUpAt: scheduledAt,
    measurements: _extractMeasurementsFromText('$title $note'),
    intent: _intentForReminderKind(kind, topic),
    source: null,
  );
}

SemanticEventDetails _inferRecordSemantic({
  required PetRecordType type,
  RecordPurpose? purpose,
  required String title,
  required String summary,
  required String note,
  required DateTime recordDate,
}) {
  final topic = _topicForRecordPurpose(purpose, '$title $summary $note');
  return SemanticEventDetails(
    topicKey: topic,
    signal: _semanticSignalForRecordText('$title $summary $note'),
    tags: _tagsForTopic(topic),
    evidenceSummary: _buildEvidenceSummary([summary, note, title]),
    actionSummary: _buildRecordActionSummary(title, summary, note, recordDate),
    followUpAt: _extractFollowUpDate('$title $summary $note'),
    measurements: _extractMeasurementsFromText('$title $summary $note'),
    intent: SemanticActionIntent.record,
    source: _sourceForRecordPurpose(purpose) ?? _sourceForRecordType(type),
  );
}

PetRecordType _recordTypeForPurpose(RecordPurpose purpose) {
  return switch (purpose) {
    RecordPurpose.health => PetRecordType.medical,
    RecordPurpose.life => PetRecordType.other,
    RecordPurpose.expense => PetRecordType.receipt,
    RecordPurpose.other => PetRecordType.other,
  };
}

RecordPurpose _recordPurposeForType(PetRecordType type) {
  return switch (type) {
    PetRecordType.medical || PetRecordType.testResult => RecordPurpose.health,
    PetRecordType.receipt => RecordPurpose.expense,
    PetRecordType.image || PetRecordType.other => RecordPurpose.life,
  };
}

SemanticTopicKey _topicForRecordPurpose(RecordPurpose? purpose, String text) {
  return switch (purpose) {
    RecordPurpose.health => _inferTopicFromText(text),
    RecordPurpose.life => SemanticTopicKey.other,
    RecordPurpose.expense => SemanticTopicKey.purchase,
    RecordPurpose.other => SemanticTopicKey.other,
    null => _inferTopicFromText(text),
  };
}

SemanticEvidenceSource? _sourceForRecordPurpose(RecordPurpose? purpose) {
  return switch (purpose) {
    RecordPurpose.health => SemanticEvidenceSource.home,
    RecordPurpose.life => SemanticEvidenceSource.home,
    RecordPurpose.expense => SemanticEvidenceSource.receipt,
    RecordPurpose.other => SemanticEvidenceSource.other,
    null => null,
  };
}

SemanticTopicKey _topicForReminderKind(
  ReminderKind kind,
  String title,
  String note,
) {
  return switch (kind) {
    ReminderKind.vaccine => SemanticTopicKey.vaccine,
    ReminderKind.deworming => SemanticTopicKey.deworming,
    ReminderKind.medication => SemanticTopicKey.medication,
    ReminderKind.review => SemanticTopicKey.review,
    ReminderKind.grooming => SemanticTopicKey.grooming,
    ReminderKind.custom => _inferTopicFromText('$title $note'),
  };
}

SemanticTopicKey _inferTopicFromText(String rawText) {
  final text = rawText.toLowerCase();
  if (_containsAny(text, ['驱虫'])) {
    return SemanticTopicKey.deworming;
  }
  if (_containsAny(text, ['疫苗', '免疫'])) {
    return SemanticTopicKey.vaccine;
  }
  if (_containsAny(text, ['耳', '耳道'])) {
    return SemanticTopicKey.earCare;
  }
  if (_containsAny(text, ['皮肤', '真菌', '红疹', '控油'])) {
    return SemanticTopicKey.skin;
  }
  if (_containsAny(text, ['饮水', '喝水', '补水'])) {
    return SemanticTopicKey.hydration;
  }
  if (_containsAny(text, ['体重', '称重', 'kg', '公斤'])) {
    return SemanticTopicKey.weight;
  }
  if (_containsAny(text, ['排便', '腹泻', '呕吐', '肠胃', '食欲'])) {
    return SemanticTopicKey.digestive;
  }
  if (_containsAny(text, ['猫砂', '便便', '厕所', 'litter'])) {
    return SemanticTopicKey.litter;
  }
  if (_containsAny(text, ['洗澡', '洗护', '美容', '梳毛', '指甲', '修剪'])) {
    return SemanticTopicKey.grooming;
  }
  if (_containsAny(text, ['清洗', '清洁', '消毒'])) {
    return SemanticTopicKey.cleaning;
  }
  if (_containsAny(text, ['药', '服用', '滴耳', '喷剂'])) {
    return SemanticTopicKey.medication;
  }
  if (_containsAny(text, ['复查', '复诊', '复盘'])) {
    return SemanticTopicKey.review;
  }
  if (_containsAny(text, ['补货', '购买', '采购', '库存', '小票', '消费'])) {
    return SemanticTopicKey.purchase;
  }
  if (_containsAny(text, ['主粮', '冻干', '猫粮', '狗粮', '饮食'])) {
    return SemanticTopicKey.diet;
  }
  return SemanticTopicKey.other;
}

SemanticSignal _semanticSignalForTodoStatus(TodoStatus status) {
  return switch (status) {
    TodoStatus.done => SemanticSignal.completed,
    TodoStatus.skipped => SemanticSignal.missed,
    TodoStatus.postponed => SemanticSignal.attention,
    TodoStatus.overdue => SemanticSignal.attention,
    TodoStatus.open => SemanticSignal.attention,
  };
}

SemanticSignal _semanticSignalForReminderStatus(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.done => SemanticSignal.completed,
    ReminderStatus.skipped => SemanticSignal.missed,
    ReminderStatus.postponed => SemanticSignal.scheduled,
    ReminderStatus.overdue => SemanticSignal.attention,
    ReminderStatus.pending => SemanticSignal.scheduled,
  };
}

SemanticSignal _semanticSignalForRecordText(String rawText) {
  final text = rawText.toLowerCase();
  if (_containsAny(text, ['复查', '复诊', '观察', '注意', '继续'])) {
    return SemanticSignal.attention;
  }
  if (_containsAny(text, ['改善', '恢复', '好转', '下降'])) {
    return SemanticSignal.improved;
  }
  if (_containsAny(text, ['恶化', '异常', '加重'])) {
    return SemanticSignal.worsened;
  }
  if (_containsAny(text, ['稳定', '平稳', '正常', '无异常'])) {
    return SemanticSignal.stable;
  }
  return SemanticSignal.info;
}

SemanticActionIntent _intentForTodoTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.purchase ||
    SemanticTopicKey.diet =>
      SemanticActionIntent.buy,
    SemanticTopicKey.cleaning ||
    SemanticTopicKey.grooming =>
      SemanticActionIntent.clean,
    SemanticTopicKey.review => SemanticActionIntent.review,
    SemanticTopicKey.medication ||
    SemanticTopicKey.deworming ||
    SemanticTopicKey.vaccine =>
      SemanticActionIntent.administer,
    SemanticTopicKey.hydration ||
    SemanticTopicKey.digestive ||
    SemanticTopicKey.skin ||
    SemanticTopicKey.earCare ||
    SemanticTopicKey.weight ||
    SemanticTopicKey.litter =>
      SemanticActionIntent.observe,
    _ => SemanticActionIntent.custom,
  };
}

SemanticActionIntent _intentForReminderKind(
  ReminderKind kind,
  SemanticTopicKey topic,
) {
  return switch (kind) {
    ReminderKind.vaccine ||
    ReminderKind.deworming ||
    ReminderKind.medication =>
      SemanticActionIntent.administer,
    ReminderKind.review => SemanticActionIntent.review,
    ReminderKind.grooming => SemanticActionIntent.clean,
    ReminderKind.custom => _intentForTodoTopic(topic),
  };
}

SemanticEvidenceSource _sourceForRecordType(PetRecordType type) {
  return switch (type) {
    PetRecordType.medical => SemanticEvidenceSource.vet,
    PetRecordType.testResult => SemanticEvidenceSource.lab,
    PetRecordType.receipt => SemanticEvidenceSource.receipt,
    PetRecordType.image || PetRecordType.other => SemanticEvidenceSource.home,
  };
}

List<String> _tagsForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.purchase => const ['补货', '库存'],
    SemanticTopicKey.deworming => const ['驱虫', '周期'],
    SemanticTopicKey.vaccine => const ['免疫', '计划'],
    SemanticTopicKey.earCare => const ['耳道', '观察'],
    SemanticTopicKey.skin => const ['皮肤', '护理'],
    SemanticTopicKey.hydration => const ['饮水', '观察'],
    SemanticTopicKey.grooming => const ['洗护', '日常'],
    SemanticTopicKey.review => const ['复查', '跟进'],
    SemanticTopicKey.weight => const ['体重', '趋势'],
    SemanticTopicKey.digestive => const ['肠胃', '观察'],
    SemanticTopicKey.litter => const ['排便', '猫砂'],
    SemanticTopicKey.medication => const ['用药', '执行'],
    SemanticTopicKey.cleaning => const ['清洁', '维护'],
    SemanticTopicKey.diet => const ['饮食', '主粮'],
    _ => const ['日常'],
  };
}

List<SemanticMeasurement> _extractMeasurementsFromText(String rawText) {
  final text = rawText.trim();
  final results = <SemanticMeasurement>[];
  final weightMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|公斤)').firstMatch(text);
  if (weightMatch != null) {
    results.add(
      SemanticMeasurement(
        key: 'weight',
        value: weightMatch.group(1) ?? '',
        unit: weightMatch.group(2) ?? 'kg',
      ),
    );
  }
  final waterMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|毫升)').firstMatch(text);
  if (waterMatch != null) {
    results.add(
      SemanticMeasurement(
        key: 'hydration',
        value: waterMatch.group(1) ?? '',
        unit: waterMatch.group(2) ?? 'ml',
      ),
    );
  }
  return results;
}

String _buildEvidenceSummary(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return _truncateSemanticText(trimmed, 72);
    }
  }
  return '暂无补充说明。';
}

String _buildRecordActionSummary(
  String title,
  String summary,
  String note,
  DateTime recordDate,
) {
  final merged = [summary, note, title]
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .join(' ');
  if (_containsAny(merged.toLowerCase(), ['复查', '继续观察', '观察'])) {
    return '建议在${_formatSemanticDate(recordDate)}之后继续跟进相关变化。';
  }
  return '记录时间为${_formatSemanticDate(recordDate)}，可作为后续分析依据。';
}

DateTime? _extractFollowUpDate(String rawText) {
  if (_containsAny(rawText.toLowerCase(), ['复查', '继续观察', '跟进'])) {
    return null;
  }
  return null;
}

String _formatSemanticDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day';
}

String _truncateSemanticText(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength)}…';
}

bool _containsAny(String source, List<String> keywords) {
  for (final keyword in keywords) {
    if (source.contains(keyword.toLowerCase())) {
      return true;
    }
  }
  return false;
}
