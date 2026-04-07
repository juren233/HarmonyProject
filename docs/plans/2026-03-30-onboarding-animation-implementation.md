# Onboarding Animation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为首次引导和填写流程补齐连续的过渡动画与受控横向分页。

**Architecture:** 在根页面新增一次性转场控制器，统一驱动引导页退出、主页交叉淡出和填写页首屏进入。填写流程内部改为顶部固定、内容分页的 `PageView` 结构，并通过按钮控制页码切换与进度条更新。

**Tech Stack:** Flutter, Material, AnimationController, PageController, flutter_test

---

### Task 1: 固定动画预期

**Files:**
- Modify: `test/widget_test.dart`
- Test: `test/widget_test.dart`

**Step 1: Write the failing test**

- 为“开始填写”和“先看看宠记”补充转场测试，要求转场开始后短时间内旧层仍存在。
- 为填写流程补充 `PageView` 与禁用手动滑动测试。
- 为填写流程第一页补充入场动画测试。

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`

Expected: FAIL，因为当前实现仍是瞬时切换，且填写流程不是 `PageView`。

**Step 3: Write minimal implementation**

- 在根页面与填写流程中补足动画状态和关键 key。

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`

Expected: PASS

### Task 2: 接入引导页与主页/填写页过渡

**Files:**
- Modify: `lib/app/pet_care_root.dart`
- Modify: `lib/app/pet_first_launch_intro.dart`
- Test: `test/widget_test.dart`

**Step 1: Write the failing test**

- 固定“开始填写”和“先看看宠记”的双层过渡行为。

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`

Expected: FAIL

**Step 3: Write minimal implementation**

- 在根页面维护引导退出和交叉渐隐控制器。
- 给引导页暴露退出进度参数，驱动 hero 放大到 `1.5x` 后缩小，并让正文原地渐隐。

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`

Expected: PASS

### Task 3: 改造填写流程首屏与分页切换

**Files:**
- Modify: `lib/app/pet_onboarding_overlay.dart`
- Test: `test/widget_test.dart`

**Step 1: Write the failing test**

- 固定首屏渐显与后续横向滚动的行为。

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`

Expected: FAIL

**Step 3: Write minimal implementation**

- 抽出步骤页组件。
- 使用禁用手势的 `PageView` 承载步骤页。
- 首屏用独立动画控制顶栏与页面内容显隐，底部按钮采用从下往上的延后渐显。

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`

Expected: PASS

### Task 4: 补结构断言

**Files:**
- Modify: `test/first_launch_intro_structure_test.dart`

**Step 1: Write the failing test**

- 固定新的引导退出峰值和填写分页结构关键字符串。

**Step 2: Run test to verify it fails**

Run: `flutter test test/first_launch_intro_structure_test.dart`

Expected: FAIL

**Step 3: Write minimal implementation**

- 补齐必要常量、key 和受控分页代码。

**Step 4: Run test to verify it passes**

Run: `flutter test test/first_launch_intro_structure_test.dart`

Expected: PASS
