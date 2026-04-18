import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReminderKind { vaccine, deworming, medication, review, grooming, custom }

enum ReminderStatus { pending, done, skipped, postponed, overdue }

enum TodoStatus { open, done, skipped, postponed, overdue }

enum NotificationLeadTime {
  none,
  fiveMinutes,
  fifteenMinutes,
  oneHour,
  oneDay,
}

enum PetRecordType { medical, receipt, image, testResult, other }

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
    this.semantic,
  });

  final String id;
  final String petId;
  final PetRecordType type;
  final String title;
  final DateTime recordDate;
  final String summary;
  final String note;
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
  final String title;
  final String dueLabel;
  final String statusLabel;
  final String kindLabel;
  final String note;
}

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
    this.report,
    this.errorMessage,
    this.hasRequested = false,
    this.activeRequestToken = 0,
  });

  final OverviewAiReportStatus status;
  final String? requestKey;
  final AiCareReport? report;
  final String? errorMessage;
  final bool hasRequested;
  final int activeRequestToken;

  bool get isLoading => status == OverviewAiReportStatus.loading;
  bool get hasReport => report != null;
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

class PetNoteStore extends ChangeNotifier {
  PetNoteStore._({
    List<Pet>? pets,
    List<TodoItem>? todos,
    List<ReminderItem>? reminders,
    List<PetRecord>? records,
    OverviewAnalysisConfig? overviewAnalysisConfig,
    OverviewAiReportState? overviewAiReportState,
    SharedPreferences? preferences,
    DateTime Function()? nowProvider,
    bool shouldAutoShowFirstLaunchIntro = true,
  })  : _preferences = preferences,
        _nowProvider = nowProvider ?? DateTime.now,
        _shouldAutoShowFirstLaunchIntro = shouldAutoShowFirstLaunchIntro {
    if (pets != null) {
      _pets.addAll(pets);
    }
    if (todos != null) {
      _todos.addAll(todos);
    }
    if (reminders != null) {
      _reminders.addAll(reminders);
    }
    if (records != null) {
      _records.addAll(records);
    }
    if (overviewAnalysisConfig != null) {
      _overviewRange = overviewAnalysisConfig.range;
      _overviewCustomRangeStart = overviewAnalysisConfig.customRangeStart;
      _overviewCustomRangeEnd = overviewAnalysisConfig.customRangeEnd;
      _overviewSelectedPetIds.addAll(overviewAnalysisConfig.selectedPetIds);
    }
    if (_pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
      if (_overviewSelectedPetIds.isEmpty) {
        _overviewSelectedPetIds.addAll(_pets.map((pet) => pet.id));
      }
    }
    if (overviewAiReportState != null) {
      _restoreOverviewAiReportState(overviewAiReportState);
    }
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
    DateTime Function()? nowProvider,
  }) async {
    final preferences = await _loadPreferences(preferencesLoader);
    final petsJson = preferences?.getString(_petsStorageKey);
    final todosJson = preferences?.getString(_todosStorageKey);
    final remindersJson = preferences?.getString(_remindersStorageKey);
    final recordsJson = preferences?.getString(_recordsStorageKey);
    final overviewConfigJson =
        preferences?.getString(_overviewConfigStorageKey);
    final overviewAiReportJson =
        preferences?.getString(_overviewAiReportStorageKey);
    final store = PetNoteStore._(
      preferences: preferences,
      nowProvider: nowProvider,
      shouldAutoShowFirstLaunchIntro:
          preferences?.getBool(_firstLaunchIntroAutoEnabledKey) ?? true,
      pets: _decodePets(petsJson),
      todos: _decodeTodos(todosJson),
      reminders: _decodeReminders(remindersJson),
      records: _decodeRecords(recordsJson),
      overviewAnalysisConfig: _decodeOverviewAnalysisConfig(overviewConfigJson),
      overviewAiReportState: _decodeOverviewAiReportState(overviewAiReportJson),
    );
    final migrated = store._migrateLegacySemanticData();
    if (migrated) {
      await store._saveState();
    }
    return store;
  }

  static const String _petsStorageKey = 'pets_v1';
  static const String _todosStorageKey = 'todos_v1';
  static const String _remindersStorageKey = 'reminders_v1';
  static const String _recordsStorageKey = 'records_v1';
  static const String _overviewConfigStorageKey = 'overview_config_v1';
  static const String _overviewAiReportStorageKey = 'overview_ai_report_v1';
  static const String _firstLaunchIntroAutoEnabledKey =
      'first_launch_intro_auto_enabled_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  final List<Pet> _pets = [];
  final List<TodoItem> _todos = [];
  final List<ReminderItem> _reminders = [];
  final List<PetRecord> _records = [];
  final DateTime Function() _nowProvider;
  final SharedPreferences? _preferences;
  List<ChecklistSection>? _checklistSectionsCache;
  int? _checklistSectionsCacheMinuteStamp;
  OverviewSnapshot? _overviewSnapshotCache;
  int? _overviewSnapshotCacheMinuteStamp;
  String? _remindersForSelectedPetCachePetId;
  List<ReminderItem>? _remindersForSelectedPetCache;
  String? _recordsForSelectedPetCachePetId;
  List<PetRecord>? _recordsForSelectedPetCache;
  OverviewAiReportState _overviewAiReportState = const OverviewAiReportState();
  int _overviewAiRequestToken = 0;
  int _notificationSyncVersion = 0;

  AppTab _activeTab = AppTab.checklist;
  OverviewRange _overviewRange = OverviewRange.sevenDays;
  DateTime? _overviewCustomRangeStart;
  DateTime? _overviewCustomRangeEnd;
  final List<String> _overviewSelectedPetIds = <String>[];
  String _selectedPetId = '';
  bool _shouldAutoShowFirstLaunchIntro;

  AppTab get activeTab => _activeTab;
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
  List<Pet> get pets => List<Pet>.unmodifiable(_pets);
  List<TodoItem> get todos => List<TodoItem>.unmodifiable(_todos);
  List<ReminderItem> get reminders =>
      List<ReminderItem>.unmodifiable(_reminders);
  List<PetRecord> get records => List<PetRecord>.unmodifiable(_records);
  bool get shouldAutoShowFirstLaunchIntro => _shouldAutoShowFirstLaunchIntro;
  int get notificationSyncVersion => _notificationSyncVersion;
  DateTime get referenceNow => _referenceNow;

  Pet? get selectedPet {
    for (final pet in _pets) {
      if (pet.id == _selectedPetId) {
        return pet;
      }
    }
    return null;
  }

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
    final cached = _recordsForSelectedPetCache;
    if (cached != null && _recordsForSelectedPetCachePetId == _selectedPetId) {
      return cached;
    }

    final results =
        _records.where((record) => record.petId == _selectedPetId).toList();
    results.sort((a, b) => b.recordDate.compareTo(a.recordDate));
    final cachedResults = List<PetRecord>.unmodifiable(results);
    _recordsForSelectedPetCachePetId = _selectedPetId;
    _recordsForSelectedPetCache = cachedResults;
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

    final todos = _todos
        .where(
          (todo) =>
              selectedPetIds.contains(todo.petId) &&
              !todo.dueAt.isBefore(range.start) &&
              !todo.dueAt.isAfter(range.end),
        )
        .toList();
    final reminders = _reminders
        .where(
          (reminder) =>
              selectedPetIds.contains(reminder.petId) &&
              !reminder.scheduledAt.isBefore(range.start) &&
              !reminder.scheduledAt.isAfter(range.end),
        )
        .toList();
    final records = _records
        .where(
          (record) =>
              selectedPetIds.contains(record.petId) &&
              !record.recordDate.isBefore(range.start) &&
              !record.recordDate.isAfter(range.end),
        )
        .toList()
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));

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
    final selectedPetIds = _effectiveOverviewSelectedPetIds().toSet();
    final selectedPets = _pets
        .where((pet) => selectedPetIds.contains(pet.id))
        .toList(growable: false);
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
        .toList(growable: false);

    return AiGenerationContext(
      title: _overviewTitle(_overviewRange),
      rangeLabel: _overviewRangeLabel(_overviewRange),
      rangeStart: range.start,
      rangeEnd: range.end,
      languageTag: 'zh-CN',
      pets: selectedPets,
      todos: todos,
      reminders: reminders,
      records: records,
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
      await _saveState();
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
      await _saveState();
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
      await _saveState();
    }
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
    unawaited(_saveState());
  }

  void updateOverviewAnalysisConfig({
    required OverviewRange range,
    required List<String> selectedPetIds,
    DateTime? customRangeStart,
    DateTime? customRangeEnd,
  }) {
    final nextSelectedPetIds = selectedPetIds.isEmpty
        ? _pets.map((pet) => pet.id).toList(growable: false)
        : selectedPetIds
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
    unawaited(_saveState());
  }

  void selectPet(String petId) {
    if (_selectedPetId == petId) {
      return;
    }
    _selectedPetId = petId;
    _invalidateSelectedPetDerivedData();
    notifyListeners();
  }

  Future<void> markChecklistDone(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      _todos.firstWhere((item) => item.id == itemId).status = TodoStatus.done;
    } else {
      _reminders.firstWhere((item) => item.id == itemId).status =
          ReminderStatus.done;
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  Future<void> postponeChecklist(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      final todo = _todos.firstWhere((item) => item.id == itemId);
      todo.status = TodoStatus.postponed;
      todo.dueAt = todo.dueAt.add(const Duration(days: 1));
    } else {
      final reminder = _reminders.firstWhere((item) => item.id == itemId);
      reminder.status = ReminderStatus.postponed;
      reminder.scheduledAt = reminder.scheduledAt.add(const Duration(days: 1));
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  Future<void> skipChecklist(String sourceType, String itemId) async {
    if (sourceType == 'todo') {
      _todos.firstWhere((item) => item.id == itemId).status =
          TodoStatus.skipped;
    } else {
      _reminders.firstWhere((item) => item.id == itemId).status =
          ReminderStatus.skipped;
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  Future<void> dismissFirstLaunchIntro() async {
    _shouldAutoShowFirstLaunchIntro = false;
    await _preferences?.setBool(_firstLaunchIntroAutoEnabledKey, false);
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
    _todos.insert(
      0,
      TodoItem(
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
      ),
    );
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
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
    _reminders.insert(
      0,
      ReminderItem(
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
      ),
    );
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    if (_selectedPetId == petId) {
      _invalidateSelectedPetReminders();
    }
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  Future<void> addRecord({
    required String petId,
    required PetRecordType type,
    required String title,
    required DateTime recordDate,
    required String summary,
    required String note,
    SemanticEventDetails? semantic,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedSummary = summary.trim();
    final normalizedNote = note.trim();
    _records.insert(
      0,
      PetRecord(
        id: 'record-${_records.length + 1}',
        petId: petId,
        type: type,
        title: normalizedTitle.isEmpty
            ? _defaultRecordTitle(type, semantic)
            : normalizedTitle,
        recordDate: recordDate,
        summary: normalizedSummary,
        note: normalizedNote,
        semantic: semantic ??
            _inferRecordSemantic(
              type: type,
              title: normalizedTitle,
              summary: normalizedSummary,
              note: normalizedNote,
              recordDate: recordDate,
            ),
      ),
    );
    _selectedPetId = petId;
    _activeTab = AppTab.pets;
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetDerivedData();
    notifyListeners();
    await _saveState();
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
    _overviewSelectedPetIds.add(pet.id);
    _selectedPetId = pet.id;
    _activeTab = AppTab.pets;
    await _saveState();
    _invalidateAllDerivedData();
    notifyListeners();
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
    _pets[index] = Pet(
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
    _selectedPetId = current.id;
    _activeTab = AppTab.pets;
    await _saveState();
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    if (_todos.any((item) => item.petId == current.id) ||
        _reminders.any((item) => item.petId == current.id)) {
      _bumpNotificationSyncVersion();
    }
    notifyListeners();
  }

  PetNoteDataState exportDataState() {
    return PetNoteDataState(
      pets: List<Pet>.from(_pets),
      todos: List<TodoItem>.from(_todos),
      reminders: List<ReminderItem>.from(_reminders),
      records: List<PetRecord>.from(_records),
    );
  }

  Future<void> replaceAllData(PetNoteDataState state) async {
    _validateDataState(state);
    final normalizedState = _normalizedDataState(state);
    _pets
      ..clear()
      ..addAll(normalizedState.pets);
    _todos
      ..clear()
      ..addAll(normalizedState.todos);
    _reminders
      ..clear()
      ..addAll(normalizedState.reminders);
    _records
      ..clear()
      ..addAll(normalizedState.records);
    _overviewSelectedPetIds
      ..clear()
      ..addAll(_pets.map((pet) => pet.id));
    _selectedPetId = _pets.isEmpty ? '' : _pets.first.id;
    _activeTab = _pets.isEmpty ? AppTab.checklist : AppTab.pets;
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
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
    _overviewSelectedPetIds.addAll(normalizedState.pets.map((pet) => pet.id));
    _todos.addAll(normalizedState.todos);
    _reminders.addAll(normalizedState.reminders);
    _records.addAll(normalizedState.records);
    if (_selectedPetId.isEmpty && _pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
    }
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  Future<void> clearAllData() async {
    _pets.clear();
    _todos.clear();
    _reminders.clear();
    _records.clear();
    _overviewSelectedPetIds.clear();
    _selectedPetId = '';
    _activeTab = AppTab.checklist;
    _invalidateAllDerivedData();
    _bumpNotificationSyncVersion();
    notifyListeners();
    await _saveState();
  }

  void _bumpNotificationSyncVersion() {
    _notificationSyncVersion += 1;
  }

  void _invalidateAllDerivedData() {
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetDerivedData();
  }

  void _invalidateChecklistDerivedData() {
    _checklistSectionsCache = null;
    _checklistSectionsCacheMinuteStamp = null;
  }

  void _invalidateOverviewDerivedData() {
    _overviewSnapshotCache = null;
    _overviewSnapshotCacheMinuteStamp = null;
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

  void _invalidateSelectedPetRecords() {
    _recordsForSelectedPetCachePetId = null;
    _recordsForSelectedPetCache = null;
  }

  void _invalidateSelectedPetDerivedData() {
    _invalidateSelectedPetReminders();
    _invalidateSelectedPetRecords();
  }

  ChecklistItemViewModel _todoToChecklistItem(TodoItem item) {
    final effectiveStatus = _effectiveTodoStatus(item, _referenceNow);
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'todo',
      petId: item.petId,
      petName: _petName(item.petId),
      petAvatarText: _petAvatar(item.petId),
      title: item.title,
      dueLabel: _formatDate(item.dueAt),
      statusLabel: _todoStatusLabel(effectiveStatus),
      kindLabel: '待办',
      note: item.note,
    );
  }

  ChecklistItemViewModel _reminderToChecklistItem(ReminderItem item) {
    final effectiveStatus = _effectiveReminderStatus(item, _referenceNow);
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'reminder',
      petId: item.petId,
      petName: _petName(item.petId),
      petAvatarText: _petAvatar(item.petId),
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
    if (_overviewSelectedPetIds.isEmpty) {
      return _pets.map((pet) => pet.id).toList(growable: false);
    }
    final existingPetIds = _pets.map((pet) => pet.id).toSet();
    final selected = _overviewSelectedPetIds
        .where((petId) => existingPetIds.contains(petId))
        .toList(growable: false);
    if (selected.isEmpty) {
      return _pets.map((pet) => pet.id).toList(growable: false);
    }
    return selected;
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

  String _petAvatar(String petId) {
    final pet = _findPet(petId);
    return pet?.avatarText ?? 'PA';
  }

  Pet? _findPet(String petId) {
    for (final pet in _pets) {
      if (pet.id == petId) {
        return pet;
      }
    }
    return null;
  }

  Pet? petById(String petId) => _findPet(petId);

  Future<void> _saveState() async {
    if (_preferences == null) {
      return;
    }
    await _preferences.setString(
      _petsStorageKey,
      jsonEncode(_pets.map((pet) => pet.toJson()).toList()),
    );
    await _preferences.setString(
      _todosStorageKey,
      jsonEncode(_todos.map((item) => item.toJson()).toList()),
    );
    await _preferences.setString(
      _remindersStorageKey,
      jsonEncode(_reminders.map((item) => item.toJson()).toList()),
    );
    await _preferences.setString(
      _recordsStorageKey,
      jsonEncode(_records.map((item) => item.toJson()).toList()),
    );
    await _preferences.setString(
      _overviewConfigStorageKey,
      jsonEncode(_encodeOverviewAnalysisConfig()),
    );
    final encodedOverviewAiReport = _encodeOverviewAiReportState();
    if (encodedOverviewAiReport == null) {
      await _preferences.remove(_overviewAiReportStorageKey);
    } else {
      await _preferences.setString(
        _overviewAiReportStorageKey,
        jsonEncode(encodedOverviewAiReport),
      );
    }
  }

  String _avatarTextForName(String name) {
    final trimmed = name.trim();
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed.substring(0, 1).toUpperCase();
  }

  static List<Pet> _decodePets(String? petsJson) {
    if (petsJson == null || petsJson.isEmpty) {
      return const <Pet>[];
    }
    final decoded = jsonDecode(petsJson);
    if (decoded is! List) {
      return const <Pet>[];
    }
    return decoded.whereType<Map<String, dynamic>>().map(Pet.fromJson).toList();
  }

  static List<TodoItem> _decodeTodos(String? todosJson) {
    return _decodeList(todosJson, TodoItem.fromJson);
  }

  static List<ReminderItem> _decodeReminders(String? remindersJson) {
    return _decodeList(remindersJson, ReminderItem.fromJson);
  }

  static List<PetRecord> _decodeRecords(String? recordsJson) {
    return _decodeList(recordsJson, PetRecord.fromJson);
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

  static Future<SharedPreferences?> _loadPreferences(
    Future<SharedPreferences> Function()? preferencesLoader,
  ) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    try {
      return await loader().timeout(_preferencesLoadTimeout);
    } on TimeoutException catch (error) {
      debugPrint('SharedPreferences timed out during startup: $error');
    } catch (error) {
      debugPrint('SharedPreferences unavailable on this platform: $error');
    }
    return null;
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
      _invalidateAllDerivedData();
    }
    return changed;
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

NotificationLeadTime _notificationLeadTimeFromName(String? value) =>
    switch (value) {
      'fiveMinutes' => NotificationLeadTime.fiveMinutes,
      'fifteenMinutes' => NotificationLeadTime.fifteenMinutes,
      'oneHour' => NotificationLeadTime.oneHour,
      'oneDay' => NotificationLeadTime.oneDay,
      _ => NotificationLeadTime.none,
    };

Duration leadTimeDuration(NotificationLeadTime leadTime) => switch (leadTime) {
      NotificationLeadTime.none => Duration.zero,
      NotificationLeadTime.fiveMinutes => const Duration(minutes: 5),
      NotificationLeadTime.fifteenMinutes => const Duration(minutes: 15),
      NotificationLeadTime.oneHour => const Duration(hours: 1),
      NotificationLeadTime.oneDay => const Duration(days: 1),
    };

String notificationLeadTimeLabel(NotificationLeadTime leadTime) =>
    switch (leadTime) {
      NotificationLeadTime.none => '准时',
      NotificationLeadTime.fiveMinutes => '提前5分钟',
      NotificationLeadTime.fifteenMinutes => '提前15分钟',
      NotificationLeadTime.oneHour => '提前1小时',
      NotificationLeadTime.oneDay => '提前1天',
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
  SemanticEventDetails? semantic,
) {
  if (semantic != null && semantic.evidenceSummary.isNotEmpty) {
    return _truncateSemanticText(semantic.evidenceSummary, 18);
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
  required String title,
  required String summary,
  required String note,
  required DateTime recordDate,
}) {
  final topic = _inferTopicFromText('$title $summary $note');
  return SemanticEventDetails(
    topicKey: topic,
    signal: _semanticSignalForRecordText('$title $summary $note'),
    tags: _tagsForTopic(topic),
    evidenceSummary: _buildEvidenceSummary([summary, note, title]),
    actionSummary: _buildRecordActionSummary(title, summary, note, recordDate),
    followUpAt: _extractFollowUpDate('$title $summary $note'),
    measurements: _extractMeasurementsFromText('$title $summary $note'),
    intent: SemanticActionIntent.record,
    source: _sourceForRecordType(type),
  );
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
