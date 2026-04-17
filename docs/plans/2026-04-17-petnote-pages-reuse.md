# Petnote Pages Reuse Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不改变页面行为的前提下，把 petnote pages 中重复的展示+状态块抽到共享文件复用。

**Architecture:** 保持 `petnote_pages` 现有 `part` 结构不变，仅在 `lib/app/common_widgets.dart` 中新增共享展示组件。页面文件继续保留状态判断、事件处理和数据拼装逻辑，只把稳定的展示壳替换为共享组件。

**Tech Stack:** Flutter、Dart、现有 `common_widgets.dart`、widget tests、dart analyze。

---

### Task 1: 新增共享组件骨架

**Files:**
- Modify: `lib/app/common_widgets.dart`

**Step 1: 添加 `PageEmptyStateBlock`**

把 HeroPanel + EmptyCard 的重复组合抽成共享组件，参数只保留展示文案和 action。

**Step 2: 添加 `InlineLoadingMessage`**

把当前 `_AiLoadingState` 的展示壳复制为共享组件，保留原布局和字号。

**Step 3: 添加 `TitledBulletGroup`**

把标题 + BulletText 列表抽成共享组件，空列表时仍返回 `SizedBox.shrink()`。

**Step 4: 添加 `StatusListRow`**

做一个薄封装，内部仍基于 `ListRow` + 图标盒 + trailing Widget，不接管业务逻辑。

**Step 5: 格式化共享文件**

Run: `dart format lib/app/common_widgets.dart`

---

### Task 2: 替换低风险重复块

**Files:**
- Modify: `lib/app/petnote_pages.dart`
- Modify: `lib/app/petnote_pages_overview.dart`
- Modify: `lib/app/petnote_pages_pets.dart`
- Modify: `lib/app/petnote_pages_ai.dart`

**Step 1: 替换空态组合块**

把 checklist / overview / pets 中的 HeroPanel + EmptyCard 组合替换为 `PageEmptyStateBlock`。

**Step 2: 替换加载提示块**

把 pets 中的 `_AiLoadingState` 替换为 `InlineLoadingMessage`。

**Step 3: 替换标题+要点组**

把 `_InlineBulletGroup` 和 `_AiDetailGroup` 的调用迁移到 `TitledBulletGroup`。

**Step 4: 删除已无引用的私有展示组件**

仅删除已完全被共享组件替代的私有展示类；如果仍有引用则保留。

**Step 5: 格式化相关页面文件**

Run: `dart format lib/app/petnote_pages.dart lib/app/petnote_pages_overview.dart lib/app/petnote_pages_pets.dart lib/app/petnote_pages_ai.dart`

---

### Task 3: 替换 pets 页面状态行展示壳

**Files:**
- Modify: `lib/app/petnote_pages_pets.dart`

**Step 1: 替换提醒列表行**

用 `StatusListRow` 承接提醒列表展示壳，保留 subtitle 拼接和 badge 内容。

**Step 2: 替换资料记录列表行**

用 `StatusListRow` 承接资料记录展示壳，保留现有颜色、图标和文案。

**Step 3: 评估自定义区间行是否适合迁移**

如果只是视觉壳一致且不增加条件分支，就迁移；否则保持现状。

**Step 4: 格式化 pets 页面文件**

Run: `dart format lib/app/petnote_pages_pets.dart`

---

### Task 4: 验证与回归

**Files:**
- Modify if needed: `test/performance_structure_test.dart`

**Step 1: 运行结构测试**

Run: `flutter test test/performance_structure_test.dart`
Expected: PASS

**Step 2: 运行 AI 页面相关测试**

Run: `flutter test test/ai_insights_widget_test.dart`
Expected: PASS

**Step 3: 运行通用页面回归测试**

Run: `flutter test test/widget_test.dart`
Expected: PASS

**Step 4: 运行设置与数据页测试**

Run: `flutter test test/ai_settings_widget_test.dart test/data_storage_widget_test.dart`
Expected: PASS

**Step 5: 运行静态分析**

Run: `dart analyze lib/app/common_widgets.dart lib/app/petnote_pages.dart lib/app/petnote_pages_overview.dart lib/app/petnote_pages_pets.dart lib/app/petnote_pages_ai.dart`
Expected: 不新增 error；如仍有存量 warning/info，需在结果说明中明确标注。
