import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists overview ai history after a successful generation', () async {
    final store = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-04-15T19:05:00+08:00'),
    );

    await store.generateOverviewAiReport(
      (context, {forceRefresh = false}) async => _buildHistoryReport(),
    );

    expect(store.overviewAiHistory, hasLength(1));
    expect(store.overviewAiHistory.single.rangeLabel, '最近 7 天 AI 照护总结');
    expect(
        store.overviewAiHistory.single.report.executiveSummary, '最近 7 天整体稳定。');

    final reloaded = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-04-15T19:06:00+08:00'),
    );
    expect(reloaded.overviewAiHistory, hasLength(1));
    expect(reloaded.overviewAiHistory.single.report.executiveSummary,
        '最近 7 天整体稳定。');
  });

  test('can clear persisted overview ai history', () async {
    final store = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-04-15T19:05:00+08:00'),
    );

    await store.generateOverviewAiReport(
      (context, {forceRefresh = false}) async => _buildHistoryReport(),
    );
    expect(store.overviewAiHistory, hasLength(1));

    await store.clearOverviewAiHistory();
    expect(store.overviewAiHistory, isEmpty);

    final reloaded = await PetNoteStore.load(
      nowProvider: () => DateTime.parse('2026-04-15T19:06:00+08:00'),
    );
    expect(reloaded.overviewAiHistory, isEmpty);
  });
}

AiCareReport _buildHistoryReport() {
  return const AiCareReport(
    overallScore: 88,
    overallScoreLabel: '稳定',
    scoreConfidence: AiScoreConfidence.high,
    scoreBreakdown: [
      AiScoreDimension(
        key: 'taskExecution',
        label: '执行完成度',
        score: 22,
        reason: '执行节奏稳定。',
      ),
      AiScoreDimension(
        key: 'reminderFollowThrough',
        label: '提醒跟进度',
        score: 22,
        reason: '提醒处理及时。',
      ),
      AiScoreDimension(
        key: 'recordCompleteness',
        label: '记录完整度',
        score: 21,
        reason: '记录保持连续。',
      ),
      AiScoreDimension(
        key: 'stabilityRisk',
        label: '稳定性与风险',
        score: 23,
        reason: '暂无集中风险。',
      ),
    ],
    scoreReasons: ['最近 7 天完成度较高。'],
    executiveSummary: '最近 7 天整体稳定。',
    overallAssessment: ['提醒、记录与待办协同顺畅。'],
    keyFindings: ['已完成关键提醒。'],
    trendAnalysis: ['照护节奏保持稳定。'],
    riskAssessment: ['暂未发现新的集中风险。'],
    priorityActions: ['继续保持当前节奏。'],
    dataQualityNotes: ['本周期样本量充足。'],
    perPetReports: [
      AiPetCareReport(
        petId: 'pet-1',
        petName: 'Luna',
        score: 88,
        scoreLabel: '稳定',
        scoreConfidence: AiScoreConfidence.high,
        summary: 'Luna 当前节奏稳定。',
        careFocus: '继续观察耳道状态。',
        keyEvents: ['完成驱虫提醒'],
        trendAnalysis: ['食欲记录更规律'],
        riskAssessment: ['暂无新增风险'],
        recommendedActions: ['继续保持记录'],
        followUpFocus: '观察耳道与精神状态。',
      ),
    ],
  );
}
