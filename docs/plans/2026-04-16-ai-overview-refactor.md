# AI 总览重构 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 重构“总览”模块的 AI 总览，优化喂给 AI 的上下文与提示词以降低生成时间，并将 UI 重构为“全局总分首屏 + 建议排行榜 + 分宠物详细分析”的结构。

**Architecture:** 保留现有 Overview 页面和 AI 服务入口，重构 AI 输入/输出契约与总览展示结构。服务层改为向 AI 提供“事实证据 + 规则模板 + 宠物分桶摘要”，由 AI 输出全局总分、状态语、建议排行榜和按宠物分类的详细分析；页面层改为“配置弹窗 + 生成按钮 + 首屏结果 + 宠物标签页详细分析”。

**Tech Stack:** Flutter、Dart、现有 `AiInsightsService` / `AiCareReport` 模型、`flutter_test`

---

### Task 1: 固定服务层新输出契约测试

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_service_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_models.dart`

**Step 1: Write the failing test**

在 `test\ai_insights_service_test.dart` 新增一个用例，验证新的 AI 总览结构至少包含：
- 全局总分 `overallScore`
- 全局状态语 `statusLabel`
- 首屏一句话总结 `oneLineSummary`
- 至少 5 条 `recommendationRankings`
- 单宠物分数与状态语
- 单宠物五段式详细分析

测试断言要覆盖：
- 多宠物时排行榜每条建议带宠物名
- 单宠物分析里有 `score` 和 `statusLabel`

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: FAIL，提示缺少新字段或解析失败

**Step 3: Write minimal implementation**

在 `lib\ai\ai_insights_models.dart` 中新增/调整 AI 总览模型，支持：
- 全局首屏字段
- 建议排行榜项模型
- 单宠物分析模型
- 解析新 JSON 结构

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 2: 固定服务层输入 JSON 压缩和提示词模板测试

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_service_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_service.dart`

**Step 1: Write the failing test**

新增一个测试，验证喂给 AI 的 payload：
- 不包含 `overallScore`
- 不包含 `statusLabel`
- 包含 `analysisConfig`
- 包含 `scoringGuidelines`
- 按宠物分桶后的 `pets`
- 每只宠物包含 `profile`、`expectedCare`、`evidence`

再新增一个测试，验证新的提示词要求：
- 先输出首屏结果
- 建议榜按重要且紧急排序
- 每只宠物至少一条建议
- 详细分析只按宠物输出

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: FAIL，提示旧 payload 或旧 prompt 不满足新断言

**Step 3: Write minimal implementation**

在 `lib\ai\ai_insights_service.dart` 中：
- 重写 AI 总览 system prompt
- 重写 user prompt 模板
- 重构 `_buildCareReportPayload`
- 引入规则模板与证据压缩结构
- 去掉把分数、状态语预先喂给 AI 的行为

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 3: 固定建议排行榜规则

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_service_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_service.dart`
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_models.dart`

**Step 1: Write the failing test**

新增服务层测试，验证：
- 建议排行榜条数下限是 `max(5, 已选宠物数)`
- 每只已选宠物至少 1 条建议
- 排行榜第 1 条建议可映射到默认宠物标签

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: FAIL，旧结构无法保证该规则

**Step 3: Write minimal implementation**

在服务层和模型层增加：
- 建议排行榜最少条数约束说明
- 宠物覆盖约束
- 建议项中的 `petIds` / `petNames`

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 4: 固定总览页面新首屏结构测试

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_widget_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\app\petnote_pages.dart`

**Step 1: Write the failing test**

在 `test\ai_insights_widget_test.dart` 新增 Widget 测试，验证总览页在生成 AI 总览后出现：
- 顶部 `配置` 按钮
- 顶部 `生成总览` 按钮
- 全局总分
- 全局状态语
- 一句话总结
- 至少 5 条建议排行榜项

同时验证旧的“执行总评/评分拆解/关键发现”平铺结构不再作为首屏主结构出现。

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: FAIL，旧页面结构不满足新断言

**Step 3: Write minimal implementation**

在 `lib\app\petnote_pages.dart` 中重构 AI 总览首屏卡片布局。

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 5: 固定配置弹窗和宠物选择交互测试

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_widget_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\app\petnote_pages.dart`

**Step 1: Write the failing test**

新增 Widget 测试，验证：
- 点击 `配置` 按钮会弹出配置弹窗
- 弹窗中有时间段选择
- 弹窗中有宠物多选
- 确认后生成只使用当前配置

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: FAIL，旧页面无该弹窗或交互不匹配

**Step 3: Write minimal implementation**

在 `lib\app\petnote_pages.dart` 中实现配置弹窗及状态同步。

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 6: 固定分宠物详细分析标签页测试

**Files:**
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_widget_test.dart`
- Modify: `F:\HarmonyProject\Pet\lib\app\petnote_pages.dart`

**Step 1: Write the failing test**

新增 Widget 测试，验证：
- 详细分析区只有宠物标签，没有 `全部`
- 默认选中“建议排行榜第 1 条所涉宠物中，配置顺序最靠前的宠物”
- 单宠物标签页展示该宠物分数、状态语和五段式分段

**Step 2: Run test to verify it fails**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: FAIL，旧页面不满足新标签规则

**Step 3: Write minimal implementation**

在 `lib\app\petnote_pages.dart` 中实现：
- 宠物标签切换
- 默认宠物标签选择逻辑
- 单宠物详细分析展示

**Step 4: Run test to verify it passes**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: PASS

**Step 5: Commit**

暂不提交，等待后续任务完成后统一确认。

### Task 7: 运行回归验证

**Files:**
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_models.dart`
- Modify: `F:\HarmonyProject\Pet\lib\ai\ai_insights_service.dart`
- Modify: `F:\HarmonyProject\Pet\lib\app\petnote_pages.dart`
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_service_test.dart`
- Modify: `F:\HarmonyProject\Pet\test\ai_insights_widget_test.dart`

**Step 1: Run focused tests**

Run: `flutter test test/ai_insights_service_test.dart`
Expected: PASS

**Step 2: Run widget tests**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: PASS

**Step 3: Run combined verification**

Run: `flutter test test/ai_insights_service_test.dart test/ai_insights_widget_test.dart`
Expected: PASS

**Step 4: Inspect for scope drift**

Run: `git status --short`
Expected: 只出现本计划允许的直接相关文件

**Step 5: Commit**

按你的默认操作边界，本轮不自动提交，等你确认后再决定。
