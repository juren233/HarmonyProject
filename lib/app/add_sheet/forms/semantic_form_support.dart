import 'package:petnote/state/petnote_store.dart';

const List<SemanticTopicKey> todoTopicOptions = <SemanticTopicKey>[
  SemanticTopicKey.diet,
  SemanticTopicKey.purchase,
  SemanticTopicKey.cleaning,
  SemanticTopicKey.grooming,
  SemanticTopicKey.hydration,
  SemanticTopicKey.other,
];

const List<SemanticActionIntent> todoIntentOptions = <SemanticActionIntent>[
  SemanticActionIntent.buy,
  SemanticActionIntent.clean,
  SemanticActionIntent.observe,
  SemanticActionIntent.review,
  SemanticActionIntent.custom,
];

const List<SemanticTopicKey> reminderTopicOptions = <SemanticTopicKey>[
  SemanticTopicKey.deworming,
  SemanticTopicKey.vaccine,
  SemanticTopicKey.medication,
  SemanticTopicKey.review,
  SemanticTopicKey.grooming,
  SemanticTopicKey.other,
];

const List<SemanticActionIntent> reminderIntentOptions = <SemanticActionIntent>[
  SemanticActionIntent.administer,
  SemanticActionIntent.review,
  SemanticActionIntent.clean,
  SemanticActionIntent.observe,
  SemanticActionIntent.custom,
];

const List<SemanticTopicKey> recordTopicOptions = <SemanticTopicKey>[
  SemanticTopicKey.earCare,
  SemanticTopicKey.skin,
  SemanticTopicKey.digestive,
  SemanticTopicKey.hydration,
  SemanticTopicKey.weight,
  SemanticTopicKey.review,
  SemanticTopicKey.other,
];

const List<SemanticSignal> recordSignalOptions = <SemanticSignal>[
  SemanticSignal.attention,
  SemanticSignal.stable,
  SemanticSignal.improved,
  SemanticSignal.worsened,
  SemanticSignal.info,
];

const List<SemanticEvidenceSource> recordSourceOptions =
    <SemanticEvidenceSource>[
  SemanticEvidenceSource.vet,
  SemanticEvidenceSource.lab,
  SemanticEvidenceSource.home,
  SemanticEvidenceSource.receipt,
  SemanticEvidenceSource.other,
];

String semanticTopicLabel(SemanticTopicKey topic) => switch (topic) {
      SemanticTopicKey.hydration => '饮水',
      SemanticTopicKey.diet => '饮食',
      SemanticTopicKey.deworming => '驱虫',
      SemanticTopicKey.litter => '排泄',
      SemanticTopicKey.grooming => '洗护',
      SemanticTopicKey.earCare => '耳道',
      SemanticTopicKey.medication => '用药',
      SemanticTopicKey.vaccine => '疫苗',
      SemanticTopicKey.review => '复查',
      SemanticTopicKey.weight => '体重',
      SemanticTopicKey.digestive => '肠胃',
      SemanticTopicKey.skin => '皮肤',
      SemanticTopicKey.purchase => '补货',
      SemanticTopicKey.cleaning => '清洁',
      SemanticTopicKey.other => '其他',
    };

String semanticIntentLabel(SemanticActionIntent intent) => switch (intent) {
      SemanticActionIntent.observe => '观察',
      SemanticActionIntent.administer => '执行护理',
      SemanticActionIntent.buy => '采购',
      SemanticActionIntent.clean => '清洁',
      SemanticActionIntent.record => '记录',
      SemanticActionIntent.review => '复查',
      SemanticActionIntent.custom => '其他',
    };

String semanticSignalLabel(SemanticSignal signal) => switch (signal) {
      SemanticSignal.stable => '稳定',
      SemanticSignal.improved => '改善',
      SemanticSignal.worsened => '恶化',
      SemanticSignal.attention => '需关注',
      SemanticSignal.completed => '已完成',
      SemanticSignal.missed => '已错过',
      SemanticSignal.scheduled => '已安排',
      SemanticSignal.info => '信息记录',
    };

String semanticSourceLabel(SemanticEvidenceSource source) => switch (source) {
      SemanticEvidenceSource.home => '在家',
      SemanticEvidenceSource.vet => '医院',
      SemanticEvidenceSource.lab => '检验',
      SemanticEvidenceSource.receipt => '票据',
      SemanticEvidenceSource.other => '其他',
    };

SemanticActionIntent defaultIntentForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.diet ||
    SemanticTopicKey.purchase =>
      SemanticActionIntent.buy,
    SemanticTopicKey.cleaning ||
    SemanticTopicKey.grooming =>
      SemanticActionIntent.clean,
    SemanticTopicKey.review => SemanticActionIntent.review,
    _ => SemanticActionIntent.observe,
  };
}

SemanticActionIntent defaultReminderIntentForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.deworming ||
    SemanticTopicKey.vaccine ||
    SemanticTopicKey.medication =>
      SemanticActionIntent.administer,
    SemanticTopicKey.grooming => SemanticActionIntent.clean,
    SemanticTopicKey.review => SemanticActionIntent.review,
    _ => SemanticActionIntent.observe,
  };
}

ReminderKind reminderKindForTopic(SemanticTopicKey topic) {
  return switch (topic) {
    SemanticTopicKey.deworming => ReminderKind.deworming,
    SemanticTopicKey.vaccine => ReminderKind.vaccine,
    SemanticTopicKey.medication => ReminderKind.medication,
    SemanticTopicKey.review => ReminderKind.review,
    SemanticTopicKey.grooming => ReminderKind.grooming,
    _ => ReminderKind.custom,
  };
}

SemanticEvidenceSource defaultSourceForRecordType(PetRecordType type) {
  return switch (type) {
    PetRecordType.medical => SemanticEvidenceSource.vet,
    PetRecordType.testResult => SemanticEvidenceSource.lab,
    PetRecordType.receipt => SemanticEvidenceSource.receipt,
    _ => SemanticEvidenceSource.home,
  };
}

List<String> semanticTagsForTopic(SemanticTopicKey topic) {
  return <String>[semanticTopicLabel(topic)];
}

String todoEvidenceSummary({
  required String title,
  required String note,
}) {
  final summary = note.trim().isNotEmpty ? note.trim() : title.trim();
  return summary.isEmpty ? '暂无补充说明。' : summary;
}

String recordEvidenceSummary({
  required String summary,
  required String note,
  required String title,
}) {
  return [
    summary.trim(),
    note.trim(),
    title.trim(),
  ].firstWhere((item) => item.isNotEmpty, orElse: () => '暂无补充说明。');
}

String intentActionSummary(
  SemanticActionIntent intent,
  DateTime dateTime,
) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return switch (intent) {
    SemanticActionIntent.buy => '计划在 $month/$day 前完成采购。',
    SemanticActionIntent.clean => '计划在 $month/$day 前完成清洁护理。',
    SemanticActionIntent.review => '计划在 $month/$day 前完成复查安排。',
    SemanticActionIntent.administer => '计划在 $month/$day 执行护理事项。',
    SemanticActionIntent.observe => '计划在 $month/$day 前继续观察。',
    SemanticActionIntent.record => '计划在 $month/$day 前补充记录。',
    SemanticActionIntent.custom => '计划在 $month/$day 前处理该事项。',
  };
}

String recordActionSummary(
  SemanticSignal signal,
  DateTime recordDate,
) {
  final month = recordDate.month.toString().padLeft(2, '0');
  final day = recordDate.day.toString().padLeft(2, '0');
  return switch (signal) {
    SemanticSignal.attention => '建议在 $month/$day 后持续跟进相关变化。',
    SemanticSignal.improved => '记录显示状态改善，可继续维持观察。',
    SemanticSignal.worsened => '记录提示风险上升，建议尽快复查。',
    SemanticSignal.stable => '当前记录显示状态稳定，可作为基线继续观察。',
    _ => '记录时间为 $month/$day，可作为后续分析依据。',
  };
}
