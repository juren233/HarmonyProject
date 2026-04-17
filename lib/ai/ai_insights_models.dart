import 'dart:convert';

import 'package:petnote/state/petnote_store.dart';

class AiGenerationContext {
  const AiGenerationContext({
    required this.title,
    required this.rangeLabel,
    required this.rangeStart,
    required this.rangeEnd,
    required this.languageTag,
    required this.pets,
    required this.todos,
    required this.reminders,
    required this.records,
  });

  final String title;
  final String rangeLabel;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String languageTag;
  final List<Pet> pets;
  final List<TodoItem> todos;
  final List<ReminderItem> reminders;
  final List<PetRecord> records;

  String get cacheKey => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'rangeLabel': rangeLabel,
      'rangeStart': rangeStart.toIso8601String(),
      'rangeEnd': rangeEnd.toIso8601String(),
      'languageTag': languageTag,
      'pets': pets
          .map(
            (pet) => {
              'id': pet.id,
              'name': pet.name,
              'type': petTypeLabel(pet.type),
              'breed': pet.breed,
              'sex': pet.sex,
              'birthday': pet.birthday,
              'ageLabel': pet.ageLabel,
              'weightKg': pet.weightKg,
              'neuterStatus': petNeuterStatusLabel(pet.neuterStatus),
              'feedingPreferences': _compactText(pet.feedingPreferences, 80),
              'allergies': _compactText(pet.allergies, 80),
              'note': _compactText(pet.note, 120),
            },
          )
          .toList(),
      'todos': todos
          .map(
            (todo) => {
              'petId': todo.petId,
              'title': todo.title,
              'dueAt': todo.dueAt.toIso8601String(),
              'status': todo.status.name,
              'notificationLeadTime': todo.notificationLeadTime.name,
              'note': _compactText(todo.note, 120),
            },
          )
          .toList(),
      'reminders': reminders
          .map(
            (reminder) => {
              'petId': reminder.petId,
              'kind': reminder.kind.name,
              'title': reminder.title,
              'scheduledAt': reminder.scheduledAt.toIso8601String(),
              'status': reminder.status.name,
              'recurrence': reminder.recurrence,
              'notificationLeadTime': reminder.notificationLeadTime.name,
              'note': _compactText(reminder.note, 120),
            },
          )
          .toList(),
      'records': records
          .map(
            (record) => {
              'petId': record.petId,
              'type': record.type.name,
              'title': record.title,
              'recordDate': record.recordDate.toIso8601String(),
              'summary': _compactText(record.summary, 120),
              'note': _compactText(record.note, 160),
            },
          )
          .toList(),
    };
  }
}

enum AiScoreConfidence { low, medium, high }

String aiScoreConfidenceLabel(AiScoreConfidence confidence) =>
    switch (confidence) {
      AiScoreConfidence.low => '样本偏少',
      AiScoreConfidence.medium => '可信度中等',
      AiScoreConfidence.high => '可信度较高',
    };

class AiScoreDimension {
  const AiScoreDimension({
    required this.key,
    required this.label,
    required this.score,
    required this.reason,
  });

  final String key;
  final String label;
  final int score;
  final String reason;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'score': score,
      'reason': reason,
    };
  }

  factory AiScoreDimension.fromJson(Map<String, dynamic> json) {
    return AiScoreDimension(
      key: _requiredString(json, 'key'),
      label: _requiredString(json, 'label'),
      score: _optionalInt(json['score']) ?? 0,
      reason: _requiredString(json, 'reason'),
    );
  }
}

class AiPetCareScorecard {
  const AiPetCareScorecard({
    required this.petId,
    required this.petName,
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.riskCandidates,
    required this.dataQualityNotes,
    required this.recentEventTitles,
  });

  final String petId;
  final String petName;
  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final List<String> riskCandidates;
  final List<String> dataQualityNotes;
  final List<String> recentEventTitles;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'petName': petName,
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'riskCandidates': riskCandidates,
      'dataQualityNotes': dataQualityNotes,
      'recentEventTitles': recentEventTitles,
    };
  }
}

class AiCareScorecard {
  const AiCareScorecard({
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.riskCandidates,
    required this.dataQualityNotes,
    required this.petScorecards,
    required this.totalTodos,
    required this.totalReminders,
    required this.totalRecords,
  });

  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final List<String> riskCandidates;
  final List<String> dataQualityNotes;
  final List<AiPetCareScorecard> petScorecards;
  final int totalTodos;
  final int totalReminders;
  final int totalRecords;

  Map<String, dynamic> toJson() {
    return {
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'riskCandidates': riskCandidates,
      'dataQualityNotes': dataQualityNotes,
      'totals': {
        'todos': totalTodos,
        'reminders': totalReminders,
        'records': totalRecords,
      },
      'petScorecards': petScorecards.map((item) => item.toJson()).toList(),
    };
  }
}

class AiPetCareReport {
  const AiPetCareReport({
    required this.petId,
    required this.petName,
    required this.score,
    required this.scoreLabel,
    required this.scoreConfidence,
    required this.summary,
    required this.careFocus,
    required this.keyEvents,
    required this.trendAnalysis,
    required this.riskAssessment,
    required this.recommendedActions,
    required this.followUpFocus,
    this.statusLabel = '',
    this.whyThisScore = const [],
    this.topPriority = const [],
    this.missedItems = const [],
    this.recentChanges = const [],
    this.followUpPlan = const [],
  });

  final String petId;
  final String petName;
  final int score;
  final String scoreLabel;
  final AiScoreConfidence scoreConfidence;
  final String summary;
  final String careFocus;
  final List<String> keyEvents;
  final List<String> trendAnalysis;
  final List<String> riskAssessment;
  final List<String> recommendedActions;
  final String followUpFocus;
  final String statusLabel;
  final List<String> whyThisScore;
  final List<String> topPriority;
  final List<String> missedItems;
  final List<String> recentChanges;
  final List<String> followUpPlan;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'petName': petName,
      'score': score,
      'scoreLabel': scoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'summary': summary,
      'careFocus': careFocus,
      'keyEvents': keyEvents,
      'trendAnalysis': trendAnalysis,
      'riskAssessment': riskAssessment,
      'recommendedActions': recommendedActions,
      'followUpFocus': followUpFocus,
      'statusLabel': statusLabel,
      'whyThisScore': whyThisScore,
      'topPriority': topPriority,
      'missedItems': missedItems,
      'recentChanges': recentChanges,
      'followUpPlan': followUpPlan,
    };
  }

  factory AiPetCareReport.fromJson(
    Map<String, dynamic> json, {
    AiPetCareScorecard? scorecard,
  }) {
    final petId = _optionalString(json['petId']) ?? scorecard?.petId;
    final petName = _optionalString(json['petName']) ?? scorecard?.petName;
    if (petId == null || petName == null) {
      throw const AiGenerationException('AI 返回的结构化结果缺少宠物标识。');
    }
    final score = _optionalInt(json['score']) ?? scorecard?.overallScore ?? 0;
    final statusLabel = _optionalString(json['statusLabel']) ??
        _optionalString(json['scoreLabel']) ??
        scorecard?.overallScoreLabel ??
        aiStatusLabelForScore(score);
    final whyThisScore = _firstStringList(
      json,
      const ['whyThisScore', 'scoreReasons'],
      fallback: scorecard?.scoreReasons,
    );
    final topPriority = _firstStringList(
      json,
      const ['topPriority', 'recommendedActions'],
    );
    final missedItems = _firstStringList(
      json,
      const ['missedItems', 'dataQualityNotes'],
      fallback: scorecard?.dataQualityNotes,
    );
    final recentChanges = _firstStringList(
      json,
      const ['recentChanges', 'keyEvents'],
      fallback: scorecard?.recentEventTitles,
    );
    final followUpPlan = _firstStringList(
      json,
      const ['followUpPlan', 'recommendedActions'],
    );
    final summary = _firstString(
      json,
      const ['summary', 'careFocus'],
      fallback: whyThisScore.isNotEmpty ? whyThisScore.first : statusLabel,
    );
    final careFocus = _firstString(
      json,
      const ['careFocus'],
      fallback: topPriority.isNotEmpty ? topPriority.first : summary,
    );
    final trendAnalysis = _firstStringList(
      json,
      const ['trendAnalysis', 'recentChanges'],
    );
    final riskAssessment = _firstStringList(
      json,
      const ['riskAssessment', 'missedItems'],
    );
    return AiPetCareReport(
      petId: petId,
      petName: petName,
      score: score,
      scoreLabel: _optionalString(json['scoreLabel']) ?? statusLabel,
      scoreConfidence: scorecard?.scoreConfidence ?? AiScoreConfidence.medium,
      summary: summary,
      careFocus: careFocus,
      keyEvents: _firstStringList(
        json,
        const ['keyEvents', 'recentChanges'],
        fallback: recentChanges,
      ),
      trendAnalysis: trendAnalysis,
      riskAssessment: riskAssessment,
      recommendedActions: _firstStringList(
        json,
        const ['recommendedActions', 'followUpPlan', 'topPriority'],
        fallback: followUpPlan,
      ),
      followUpFocus: _firstString(
        json,
        const ['followUpFocus'],
        fallback: followUpPlan.isNotEmpty ? followUpPlan.first : careFocus,
      ),
      statusLabel: statusLabel,
      whyThisScore: whyThisScore,
      topPriority: topPriority,
      missedItems: missedItems,
      recentChanges: recentChanges,
      followUpPlan: followUpPlan,
    );
  }

  factory AiPetCareReport.fromStoredJson(Map<String, dynamic> json) {
    return AiPetCareReport(
      petId: _requiredString(json, 'petId'),
      petName: _requiredString(json, 'petName'),
      score: _optionalInt(json['score']) ?? 0,
      scoreLabel: _requiredString(json, 'scoreLabel'),
      scoreConfidence:
          _aiScoreConfidenceFromName(json['scoreConfidence'] as String?),
      summary: _requiredString(json, 'summary'),
      careFocus: _requiredString(json, 'careFocus'),
      keyEvents: _stringList(json['keyEvents']),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      recommendedActions: _stringList(json['recommendedActions']),
      followUpFocus: _requiredString(json, 'followUpFocus'),
      statusLabel: _optionalString(json['statusLabel']) ?? '',
      whyThisScore: _stringList(json['whyThisScore']),
      topPriority: _stringList(json['topPriority']),
      missedItems: _stringList(json['missedItems']),
      recentChanges: _stringList(json['recentChanges']),
      followUpPlan: _stringList(json['followUpPlan']),
    );
  }
}

class AiRecommendationRanking {
  const AiRecommendationRanking({
    required this.rank,
    required this.kind,
    required this.petIds,
    required this.petNames,
    required this.title,
    required this.summary,
    required this.suggestedAction,
  });

  final int rank;
  final String kind;
  final List<String> petIds;
  final List<String> petNames;
  final String title;
  final String summary;
  final String suggestedAction;

  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'kind': kind,
      'petIds': petIds,
      'petNames': petNames,
      'title': title,
      'summary': summary,
      'suggestedAction': suggestedAction,
    };
  }

  factory AiRecommendationRanking.fromJson(Map<String, dynamic> json) {
    return AiRecommendationRanking(
      rank: _optionalInt(json['rank']) ?? 0,
      kind: _requiredString(json, 'kind'),
      petIds: _requiredStringList(json, 'petIds'),
      petNames: _requiredStringList(json, 'petNames'),
      title: _requiredString(json, 'title'),
      summary: _requiredString(json, 'summary'),
      suggestedAction: _requiredString(json, 'suggestedAction'),
    );
  }
}

class AiCareReport {
  const AiCareReport({
    required this.overallScore,
    required this.overallScoreLabel,
    required this.scoreConfidence,
    required this.scoreBreakdown,
    required this.scoreReasons,
    required this.executiveSummary,
    required this.overallAssessment,
    required this.keyFindings,
    required this.trendAnalysis,
    required this.riskAssessment,
    required this.priorityActions,
    required this.dataQualityNotes,
    required this.perPetReports,
    this.statusLabel = '',
    this.oneLineSummary = '',
    this.recommendationRankings = const [],
  });

  final int overallScore;
  final String overallScoreLabel;
  final AiScoreConfidence scoreConfidence;
  final List<AiScoreDimension> scoreBreakdown;
  final List<String> scoreReasons;
  final String executiveSummary;
  final List<String> overallAssessment;
  final List<String> keyFindings;
  final List<String> trendAnalysis;
  final List<String> riskAssessment;
  final List<String> priorityActions;
  final List<String> dataQualityNotes;
  final List<AiPetCareReport> perPetReports;
  final String statusLabel;
  final String oneLineSummary;
  final List<AiRecommendationRanking> recommendationRankings;

  String get summary =>
      oneLineSummary.isNotEmpty ? oneLineSummary : executiveSummary;

  Map<String, dynamic> toJson() {
    return {
      'overallScore': overallScore,
      'overallScoreLabel': overallScoreLabel,
      'scoreConfidence': scoreConfidence.name,
      'scoreBreakdown': scoreBreakdown.map((item) => item.toJson()).toList(),
      'scoreReasons': scoreReasons,
      'executiveSummary': executiveSummary,
      'overallAssessment': overallAssessment,
      'keyFindings': keyFindings,
      'trendAnalysis': trendAnalysis,
      'riskAssessment': riskAssessment,
      'priorityActions': priorityActions,
      'dataQualityNotes': dataQualityNotes,
      'perPetReports': perPetReports.map((item) => item.toJson()).toList(),
      'statusLabel': statusLabel,
      'oneLineSummary': oneLineSummary,
      'recommendationRankings':
          recommendationRankings.map((item) => item.toJson()).toList(),
    };
  }

  factory AiCareReport.fromJson(
    Map<String, dynamic> json, {
    required AiCareScorecard scorecard,
  }) {
    final rawPetReports = json['perPetReports'];
    if (rawPetReports is! List) {
      throw const AiGenerationException('AI 返回的结构化结果缺少 perPetReports。');
    }
    final reportsByPetId = <String, Map<String, dynamic>>{};
    for (final item in rawPetReports) {
      if (item is! Map) {
        continue;
      }
      final mapped = item.map((key, value) => MapEntry('$key', value));
      final petId = _requiredString(mapped, 'petId');
      reportsByPetId[petId] = mapped;
    }
    final perPetReports = scorecard.petScorecards.isEmpty
        ? reportsByPetId.values
            .map(AiPetCareReport.fromJson)
            .toList(growable: false)
        : scorecard.petScorecards.map((petScorecard) {
            final rawReport = reportsByPetId[petScorecard.petId];
            if (rawReport == null) {
              throw AiGenerationException(
                'AI 返回的结构化结果缺少 ${petScorecard.petName} 的专项报告。',
              );
            }
            return AiPetCareReport.fromJson(
              rawReport,
              scorecard: petScorecard,
            );
          }).toList(growable: false);
    final recommendationRankings = _recommendationRankings(json);
    final oneLineSummary = _firstString(
      json,
      const ['oneLineSummary', 'executiveSummary'],
    );
    final overallScore =
        _optionalInt(json['overallScore']) ?? scorecard.overallScore;
    final statusLabel = _optionalString(json['statusLabel']) ??
        _optionalString(json['overallScoreLabel']) ??
        scorecard.overallScoreLabel;
    final priorityActions = _firstStringList(
      json,
      const ['priorityActions'],
      fallback: recommendationRankings
          .map((item) => item.suggestedAction)
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    return AiCareReport(
      overallScore: overallScore,
      overallScoreLabel:
          _optionalString(json['overallScoreLabel']) ?? statusLabel,
      scoreConfidence: scorecard.scoreConfidence,
      scoreBreakdown: scorecard.scoreBreakdown,
      scoreReasons: scorecard.scoreReasons,
      executiveSummary: _firstString(
        json,
        const ['executiveSummary', 'oneLineSummary'],
      ),
      overallAssessment: _firstStringList(
        json,
        const ['overallAssessment'],
        fallback: oneLineSummary.isEmpty ? const [] : [oneLineSummary],
      ),
      keyFindings: _firstStringList(
        json,
        const ['keyFindings'],
        fallback: recommendationRankings
            .map((item) => item.summary)
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      ),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      priorityActions: priorityActions,
      dataQualityNotes: _firstStringList(
        json,
        const ['dataQualityNotes'],
        fallback: scorecard.dataQualityNotes,
      ),
      perPetReports: perPetReports,
      statusLabel: statusLabel,
      oneLineSummary: oneLineSummary,
      recommendationRankings: recommendationRankings,
    );
  }

  factory AiCareReport.fromStoredJson(Map<String, dynamic> json) {
    final rawScoreBreakdown = json['scoreBreakdown'];
    final rawPetReports = json['perPetReports'];
    final rawRecommendationRankings = json['recommendationRankings'];
    return AiCareReport(
      overallScore: _optionalInt(json['overallScore']) ?? 0,
      overallScoreLabel: _requiredString(json, 'overallScoreLabel'),
      scoreConfidence:
          _aiScoreConfidenceFromName(json['scoreConfidence'] as String?),
      scoreBreakdown: rawScoreBreakdown is List
          ? rawScoreBreakdown
              .whereType<Map>()
              .map((item) =>
                  AiScoreDimension.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiScoreDimension>[],
      scoreReasons: _stringList(json['scoreReasons']),
      executiveSummary: _requiredString(json, 'executiveSummary'),
      overallAssessment: _stringList(json['overallAssessment']),
      keyFindings: _stringList(json['keyFindings']),
      trendAnalysis: _stringList(json['trendAnalysis']),
      riskAssessment: _stringList(json['riskAssessment']),
      priorityActions: _stringList(json['priorityActions']),
      dataQualityNotes: _stringList(json['dataQualityNotes']),
      perPetReports: rawPetReports is List
          ? rawPetReports
              .whereType<Map>()
              .map((item) => AiPetCareReport.fromStoredJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiPetCareReport>[],
      statusLabel: _optionalString(json['statusLabel']) ?? '',
      oneLineSummary: _optionalString(json['oneLineSummary']) ?? '',
      recommendationRankings: rawRecommendationRankings is List
          ? rawRecommendationRankings
              .whereType<Map>()
              .map((item) => AiRecommendationRanking.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <AiRecommendationRanking>[],
    );
  }
}

class AiVisitSummary {
  const AiVisitSummary({
    required this.visitReason,
    required this.timeline,
    required this.medicationsAndTreatments,
    required this.testsAndResults,
    required this.questionsToAskVet,
  });

  final String visitReason;
  final List<String> timeline;
  final List<String> medicationsAndTreatments;
  final List<String> testsAndResults;
  final List<String> questionsToAskVet;

  factory AiVisitSummary.fromJson(Map<String, dynamic> json) {
    return AiVisitSummary(
      visitReason: _requiredString(json, 'visitReason'),
      timeline: _stringList(json['timeline']),
      medicationsAndTreatments: _stringList(json['medicationsAndTreatments']),
      testsAndResults: _stringList(json['testsAndResults']),
      questionsToAskVet: _stringList(json['questionsToAskVet']),
    );
  }
}

class AiGenerationException implements Exception {
  const AiGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _compactText(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength)}…';
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null || value.isEmpty) {
    throw AiGenerationException('AI 返回的结构化结果缺少 $key。');
  }
  return value;
}

String aiStatusLabelForScore(int score) {
  if (score >= 90) {
    return '状态不错';
  }
  if (score >= 80) {
    return '状态还行';
  }
  if (score >= 70) {
    return '需要关注';
  }
  if (score >= 60) {
    return '急需关注';
  }
  return '存在隐患';
}

AiScoreConfidence _aiScoreConfidenceFromName(String? value) {
  return switch (value) {
    'low' => AiScoreConfidence.low,
    'high' => AiScoreConfidence.high,
    _ => AiScoreConfidence.medium,
  };
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value.clamp(0, 100);
  }
  if (value is num) {
    return value.round().clamp(0, 100);
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    return parsed?.clamp(0, 100);
  }
  return null;
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = _optionalString(json[key]);
    if (value != null) {
      return value;
    }
  }
  if (fallback.isNotEmpty) {
    return fallback;
  }
  throw AiGenerationException('AI 返回的结构化结果缺少 ${keys.first}。');
}

List<String> _firstStringList(
  Map<String, dynamic> json,
  List<String> keys, {
  List<String>? fallback,
}) {
  for (final key in keys) {
    final value = _stringList(json[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback ?? const <String>[];
}

List<AiRecommendationRanking> _recommendationRankings(
  Map<String, dynamic> json,
) {
  final rawItems = json['recommendationRankings'];
  if (rawItems is! List) {
    return const <AiRecommendationRanking>[];
  }
  return rawItems
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .map(AiRecommendationRanking.fromJson)
      .toList(growable: false);
}

List<String> _requiredStringList(Map<String, dynamic> json, String key) {
  final value = _stringList(json[key]);
  if (value.isEmpty) {
    throw AiGenerationException('AI 返回的结构化结果缺少 $key。');
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value is String ? value.trim() : null;
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
