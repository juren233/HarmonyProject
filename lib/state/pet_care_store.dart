import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReminderKind { vaccine, deworming, medication, review, grooming, custom }

enum ReminderStatus { pending, done, skipped, postponed, overdue }

enum TodoStatus { open, done, skipped, postponed, overdue }

enum PetRecordType { medical, receipt, image, testResult, other }

enum OverviewRange { sevenDays, oneMonth, threeMonths, sixMonths, oneYear }

enum AppTab { checklist, overview, pets, me }

enum PetType { cat, dog, rabbit, bird, other }

enum PetNeuterStatus { neutered, notNeutered, unknown }

class Pet {
  Pet({
    required this.id,
    required this.name,
    required this.avatarText,
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
    required this.status,
    required this.note,
  });

  final String id;
  final String petId;
  final String title;
  DateTime dueAt;
  TodoStatus status;
  final String note;
}

class ReminderItem {
  ReminderItem({
    required this.id,
    required this.petId,
    required this.kind,
    required this.title,
    required this.scheduledAt,
    required this.recurrence,
    required this.status,
    required this.note,
  });

  final String id;
  final String petId;
  final ReminderKind kind;
  final String title;
  DateTime scheduledAt;
  final String recurrence;
  ReminderStatus status;
  final String note;
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
  });

  final String id;
  final String petId;
  final PetRecordType type;
  final String title;
  final DateTime recordDate;
  final String summary;
  final String note;
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

class PetCareStore extends ChangeNotifier {
  PetCareStore._({
    List<Pet>? pets,
    List<TodoItem>? todos,
    List<ReminderItem>? reminders,
    List<PetRecord>? records,
    SharedPreferences? preferences,
    bool shouldAutoShowFirstLaunchIntro = true,
  })  : _preferences = preferences,
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
    if (_pets.isNotEmpty) {
      _selectedPetId = _pets.first.id;
    }
  }

  factory PetCareStore.seeded() {
    return PetCareStore._(
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
          status: TodoStatus.open,
          note: '检查低敏口味。',
        ),
        TodoItem(
          id: 'todo-2',
          petId: 'pet-2',
          title: '周末修剪指甲',
          dueAt: DateTime.parse('2026-03-27T10:00:00+08:00'),
          status: TodoStatus.postponed,
          note: '准备零食安抚。',
        ),
        TodoItem(
          id: 'todo-3',
          petId: 'pet-2',
          title: '清洗牵引绳',
          dueAt: DateTime.parse('2026-03-22T20:00:00+08:00'),
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

  static Future<PetCareStore> load({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) async {
    final preferences = await _loadPreferences(preferencesLoader);
    final petsJson = preferences?.getString(_petsStorageKey);
    return PetCareStore._(
      preferences: preferences,
      shouldAutoShowFirstLaunchIntro:
          preferences?.getBool(_firstLaunchIntroAutoEnabledKey) ?? true,
      pets: _decodePets(petsJson),
    );
  }

  static const String _petsStorageKey = 'pets_v1';
  static const String _firstLaunchIntroAutoEnabledKey =
      'first_launch_intro_auto_enabled_v1';
  static const Duration _preferencesLoadTimeout = Duration(seconds: 2);

  final List<Pet> _pets = [];
  final List<TodoItem> _todos = [];
  final List<ReminderItem> _reminders = [];
  final List<PetRecord> _records = [];
  final DateTime _referenceNow = DateTime.parse('2026-03-24T12:00:00+08:00');
  final SharedPreferences? _preferences;
  List<ChecklistSection>? _checklistSectionsCache;
  OverviewSnapshot? _overviewSnapshotCache;
  String? _remindersForSelectedPetCachePetId;
  List<ReminderItem>? _remindersForSelectedPetCache;
  String? _recordsForSelectedPetCachePetId;
  List<PetRecord>? _recordsForSelectedPetCache;

  AppTab _activeTab = AppTab.checklist;
  OverviewRange _overviewRange = OverviewRange.sevenDays;
  String _selectedPetId = '';
  bool _shouldAutoShowFirstLaunchIntro;

  AppTab get activeTab => _activeTab;
  OverviewRange get overviewRange => _overviewRange;
  List<Pet> get pets => List<Pet>.unmodifiable(_pets);
  bool get shouldAutoShowFirstLaunchIntro => _shouldAutoShowFirstLaunchIntro;

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
    final cached = _checklistSectionsCache;
    if (cached != null) {
      return cached;
    }

    final todayEnd = DateTime(
        _referenceNow.year, _referenceNow.month, _referenceNow.day, 23, 59, 59);
    final today = <ChecklistItemViewModel>[];
    final upcoming = <ChecklistItemViewModel>[];
    final overdue = <ChecklistItemViewModel>[];

    for (final todo in _todos) {
      if (todo.status == TodoStatus.done || todo.status == TodoStatus.skipped) {
        continue;
      }
      final item = _todoToChecklistItem(todo);
      if (todo.status == TodoStatus.overdue ||
          todo.dueAt.isBefore(_referenceNow)) {
        overdue.add(item);
      } else if (!todo.dueAt.isAfter(todayEnd)) {
        today.add(item);
      } else {
        upcoming.add(item);
      }
    }

    for (final reminder in _reminders) {
      if (reminder.status == ReminderStatus.done ||
          reminder.status == ReminderStatus.skipped) {
        continue;
      }
      final item = _reminderToChecklistItem(reminder);
      if (reminder.status == ReminderStatus.overdue ||
          reminder.scheduledAt.isBefore(_referenceNow)) {
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
    ]);
    _checklistSectionsCache = sections;
    return sections;
  }

  OverviewSnapshot get overviewSnapshot {
    final cached = _overviewSnapshotCache;
    if (cached != null) {
      return cached;
    }

    final rangeStart = _referenceNow.subtract(Duration(
        days: switch (_overviewRange) {
      OverviewRange.sevenDays => 7,
      OverviewRange.oneMonth => 30,
      OverviewRange.threeMonths => 90,
      OverviewRange.sixMonths => 180,
      OverviewRange.oneYear => 365,
    }));

    final todos =
        _todos.where((todo) => !todo.dueAt.isBefore(rangeStart)).toList();
    final reminders = _reminders
        .where((reminder) => !reminder.scheduledAt.isBefore(rangeStart))
        .toList();
    final records = _records
        .where((record) => !record.recordDate.isBefore(rangeStart))
        .toList()
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));

    final riskItems = <String>[];
    final overdueCount =
        _todos.where((item) => item.status == TodoStatus.overdue).length;
    if (overdueCount > 0) {
      riskItems.add('有 $overdueCount 条待办已逾期，建议尽快回到清单页处理。');
    }
    for (final pet in _pets) {
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
            '已完成提醒 ${_reminders.where((item) => item.status == ReminderStatus.done).length} 次，关键健康节点有被跟进。',
            '当前逾期待办 ${_todos.where((item) => item.status == TodoStatus.overdue).length} 条，需要优先处理。',
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
            if (_reminders.any((item) => item.status == ReminderStatus.pending))
              '检查未来 7 天提醒分布，避免多个关键事项集中在同一天。',
            if (records.isEmpty) '保持每周至少补充 1 次记录，让总览建议更准确。',
          ],
        ),
      ],
      disclaimer: '仅供日常照护参考，不构成诊断或医疗建议，如有异常请及时咨询专业兽医。',
    );
    _overviewSnapshotCache = snapshot;
    return snapshot;
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
    _invalidateOverviewDerivedData();
    notifyListeners();
  }

  void selectPet(String petId) {
    if (_selectedPetId == petId) {
      return;
    }
    _selectedPetId = petId;
    _invalidateSelectedPetDerivedData();
    notifyListeners();
  }

  void markChecklistDone(String sourceType, String itemId) {
    if (sourceType == 'todo') {
      _todos.firstWhere((item) => item.id == itemId).status = TodoStatus.done;
    } else {
      _reminders.firstWhere((item) => item.id == itemId).status =
          ReminderStatus.done;
      _invalidateSelectedPetReminders();
    }
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    notifyListeners();
  }

  void postponeChecklist(String sourceType, String itemId) {
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
    notifyListeners();
  }

  void skipChecklist(String sourceType, String itemId) {
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
    notifyListeners();
  }

  Future<void> dismissFirstLaunchIntro() async {
    _shouldAutoShowFirstLaunchIntro = false;
    await _preferences?.setBool(_firstLaunchIntroAutoEnabledKey, false);
    notifyListeners();
  }

  void addTodo({
    required String title,
    required String petId,
    required DateTime dueAt,
    required String note,
  }) {
    _todos.insert(
      0,
      TodoItem(
        id: 'todo-${_todos.length + 1}',
        petId: petId,
        title: title,
        dueAt: dueAt,
        status: TodoStatus.open,
        note: note,
      ),
    );
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    notifyListeners();
  }

  void addReminder({
    required String title,
    required String petId,
    required DateTime scheduledAt,
    required ReminderKind kind,
    required String recurrence,
    required String note,
  }) {
    _reminders.insert(
      0,
      ReminderItem(
        id: 'reminder-${_reminders.length + 1}',
        petId: petId,
        kind: kind,
        title: title,
        scheduledAt: scheduledAt,
        recurrence: recurrence,
        status: ReminderStatus.pending,
        note: note,
      ),
    );
    _activeTab = AppTab.checklist;
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    if (_selectedPetId == petId) {
      _invalidateSelectedPetReminders();
    }
    notifyListeners();
  }

  void addRecord({
    required String petId,
    required PetRecordType type,
    required String title,
    required DateTime recordDate,
    required String summary,
    required String note,
  }) {
    _records.insert(
      0,
      PetRecord(
        id: 'record-${_records.length + 1}',
        petId: petId,
        type: type,
        title: title,
        recordDate: recordDate,
        summary: summary,
        note: note,
      ),
    );
    _selectedPetId = petId;
    _activeTab = AppTab.pets;
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetDerivedData();
    notifyListeners();
  }

  Future<void> addPet({
    required String name,
    required PetType type,
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
    _selectedPetId = pet.id;
    _activeTab = AppTab.pets;
    await _savePets();
    _invalidateAllDerivedData();
    notifyListeners();
  }

  Future<void> updatePet({
    required String petId,
    required String name,
    required PetType type,
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
    await _savePets();
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    notifyListeners();
  }

  void _invalidateAllDerivedData() {
    _invalidateChecklistDerivedData();
    _invalidateOverviewDerivedData();
    _invalidateSelectedPetDerivedData();
  }

  void _invalidateChecklistDerivedData() {
    _checklistSectionsCache = null;
  }

  void _invalidateOverviewDerivedData() {
    _overviewSnapshotCache = null;
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
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'todo',
      petId: item.petId,
      petName: _petName(item.petId),
      petAvatarText: _petAvatar(item.petId),
      title: item.title,
      dueLabel: _formatDate(item.dueAt),
      statusLabel: _todoStatusLabel(item.status),
      kindLabel: '待办',
      note: item.note,
    );
  }

  ChecklistItemViewModel _reminderToChecklistItem(ReminderItem item) {
    return ChecklistItemViewModel(
      id: item.id,
      sourceType: 'reminder',
      petId: item.petId,
      petName: _petName(item.petId),
      petAvatarText: _petAvatar(item.petId),
      title: item.title,
      dueLabel: _formatDate(item.scheduledAt),
      statusLabel: _reminderStatusLabel(item.status),
      kindLabel: '提醒',
      note: item.note,
    );
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

  Future<void> _savePets() async {
    if (_preferences == null) {
      return;
    }
    final encoded = jsonEncode(_pets.map((pet) => pet.toJson()).toList());
    await _preferences.setString(_petsStorageKey, encoded);
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
