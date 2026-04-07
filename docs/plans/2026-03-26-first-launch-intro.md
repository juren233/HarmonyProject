# First Launch Intro Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current auto-open pet onboarding with a 3-screen first-launch intro for "宠记" that explains app value first, then routes users into the existing 9-step pet onboarding or into the empty-state shell.

**Architecture:** Keep the existing pet onboarding overlay intact and add a separate intro overlay component rendered by `PetNoteRoot`. Move the persisted first-launch flag from "auto show onboarding" semantics to "auto show intro" semantics so startup, defer, and manual entry remain easy to reason about.

**Tech Stack:** Flutter, Material 3 widgets, `shared_preferences`, Flutter widget tests, file-structure tests

---

### Task 0: Add intro motion design constraints

**Files:**
- Modify: `F:/HarmonyProject/Pet/docs/plans/2026-03-26-first-launch-intro-design.md`
- Modify: `F:/HarmonyProject/Pet/docs/plans/2026-03-26-first-launch-intro.md`

**Step 1: Record the approved motion behavior**

Document these constraints before implementation:

- opening paw animation replays every time the intro is opened
- paw color animates from gray to the first-page accent color
- paw shrinks and moves into the first-page hero icon position
- each page reveals content only the first time that page is visited in the current intro session

**Step 2: Commit**

```bash
git add F:/HarmonyProject/Pet/docs/plans/2026-03-26-first-launch-intro-design.md F:/HarmonyProject/Pet/docs/plans/2026-03-26-first-launch-intro.md
git commit -m "docs: add intro motion design"
```

### Task 1: Rename and reshape first-launch persistence semantics

**Files:**
- Modify: `F:/HarmonyProject/Pet/lib/state/pet_care_store.dart`
- Test: `F:/HarmonyProject/Pet/test/pet_care_store_test.dart`

**Step 1: Write the failing test**

Add a store test that loads empty preferences, expects the new intro flag getter to be `true`, dismisses the intro, reloads the store, and expects it to be `false`.

```dart
test('dismissing first-launch intro persists auto-show disabled', () async {
  final store = await PetNoteStore.load();

  await store.dismissFirstLaunchIntro();

  final reloaded = await PetNoteStore.load();
  expect(reloaded.shouldAutoShowFirstLaunchIntro, isFalse);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/pet_care_store_test.dart`
Expected: FAIL because `dismissFirstLaunchIntro` and `shouldAutoShowFirstLaunchIntro` do not exist yet.

**Step 3: Write minimal implementation**

In `lib/state/pet_care_store.dart`:

- rename the persisted key to a new intro-specific key
- rename the backing field/getter from onboarding auto-show semantics to intro auto-show semantics
- rename `dismissFirstLaunchOnboarding()` to `dismissFirstLaunchIntro()`
- keep the rest of store behavior unchanged for now

**Step 4: Run test to verify it passes**

Run: `flutter test test/pet_care_store_test.dart`
Expected: PASS for the new intro persistence test and existing store tests.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/lib/state/pet_care_store.dart F:/HarmonyProject/Pet/test/pet_care_store_test.dart
git commit -m "refactor: rename first-launch intro state"
```

### Task 2: Add a dedicated first-launch intro overlay widget

**Files:**
- Create: `F:/HarmonyProject/Pet/lib/app/pet_first_launch_intro.dart`
- Test: `F:/HarmonyProject/Pet/test/widget_test.dart`

**Step 1: Write the failing test**

Add a widget test that pumps `PetNoteApp`, waits for startup, and expects a first-launch intro overlay with page-one copy and a continue button.

```dart
testWidgets('shows first-launch intro before pet onboarding', (tester) async {
  await tester.pumpWidget(const PetNoteApp());
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('first_launch_intro_overlay')), findsOneWidget);
  expect(find.text('欢迎来到宠记'), findsOneWidget);
  expect(find.widgetWithText(FilledButton, '继续'), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL because the intro overlay widget and its copy do not exist.

**Step 3: Write minimal implementation**

Create `lib/app/pet_first_launch_intro.dart` with:

- a stateful `PageView`
- 3 intro pages matching the approved copy
- icon blocks using existing rounded Material icons
- page indicator
- primary CTA for page 1 and 2: `继续`
- final-page primary CTA: `添加第一只宠物`
- final-page secondary CTA: `先看看宠记`
- keys for stable widget testing

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`
Expected: PASS for the new intro visibility assertion once root wiring exists.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/lib/app/pet_first_launch_intro.dart F:/HarmonyProject/Pet/test/widget_test.dart
git commit -m "feat: add first-launch intro overlay"
```

### Task 3: Route startup through intro first, then onboarding

**Files:**
- Modify: `F:/HarmonyProject/Pet/lib/app/pet_care_root.dart`
- Modify: `F:/HarmonyProject/Pet/lib/app/pet_care_app.dart`
- Test: `F:/HarmonyProject/Pet/test/widget_test.dart`
- Test: `F:/HarmonyProject/Pet/test/root_startup_structure_test.dart`

**Step 1: Write the failing test**

Add widget coverage for:

- startup shows intro instead of onboarding
- tapping through to final page then `添加第一只宠物` opens the existing onboarding overlay
- intro hides bottom nav while visible

```dart
testWidgets('intro primary CTA opens pet onboarding on final page', (tester) async {
  await tester.pumpWidget(const PetNoteApp());
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '添加第一只宠物'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart test/root_startup_structure_test.dart`
Expected: FAIL because startup still opens the onboarding overlay directly.

**Step 3: Write minimal implementation**

In `lib/app/pet_care_root.dart`:

- add separate booleans for intro visibility and onboarding visibility
- on startup with no pets, show intro when the persisted flag is enabled
- show onboarding only after explicit user action
- keep bottom navigation hidden while either full-screen overlay is active
- wire intro actions:
  - continue between pages
  - open onboarding from final-page primary CTA
  - dismiss intro into shell from final-page secondary CTA

Only touch `lib/app/pet_care_app.dart` if startup bootstrapping needs small API changes.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart test/root_startup_structure_test.dart`
Expected: PASS for startup flow and shell structure checks.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/lib/app/pet_care_root.dart F:/HarmonyProject/Pet/lib/app/pet_care_app.dart F:/HarmonyProject/Pet/test/widget_test.dart F:/HarmonyProject/Pet/test/root_startup_structure_test.dart
git commit -m "feat: show first-launch intro before onboarding"
```

### Task 4: Persist "先看看宠记" dismissal and preserve manual onboarding entry

**Files:**
- Modify: `F:/HarmonyProject/Pet/lib/app/pet_care_root.dart`
- Modify: `F:/HarmonyProject/Pet/test/widget_test.dart`
- Modify: `F:/HarmonyProject/Pet/test/pet_care_store_test.dart`

**Step 1: Write the failing test**

Add widget coverage for:

- choosing `先看看宠记` hides intro
- the intro does not auto-reappear on a fresh app pump
- empty-state CTA still opens the onboarding overlay manually

```dart
testWidgets('choosing explore first hides intro and preserves manual add flow', (tester) async {
  await tester.pumpWidget(const PetNoteApp());
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, '先看看宠记'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);
  expect(find.text('先添加第一只爱宠'), findsWidgets);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL because the intro dismissal path is not persisted yet.

**Step 3: Write minimal implementation**

Update root/store wiring so that:

- final-page secondary CTA calls `dismissFirstLaunchIntro()`
- manual onboarding entry from empty states still works
- entering onboarding from intro also marks intro as dismissed

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart test/pet_care_store_test.dart`
Expected: PASS for the explore-first path and store persistence coverage.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/lib/app/pet_care_root.dart F:/HarmonyProject/Pet/test/widget_test.dart F:/HarmonyProject/Pet/test/pet_care_store_test.dart
git commit -m "feat: persist first-launch intro dismissal"
```

### Task 5: Adjust onboarding defer behavior after intro launch

**Files:**
- Modify: `F:/HarmonyProject/Pet/lib/app/pet_care_root.dart`
- Modify: `F:/HarmonyProject/Pet/test/widget_test.dart`

**Step 1: Write the failing test**

Add widget coverage for:

- user enters onboarding from intro
- taps onboarding `稍后`
- onboarding closes back to shell empty state
- intro does not re-open

```dart
testWidgets('deferring onboarding after intro returns to shell without reopening intro', (tester) async {
  await tester.pumpWidget(const PetNoteApp());
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '添加第一只宠物'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('onboarding_defer_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '稍后处理'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('first_launch_intro_overlay')), findsNothing);
  expect(find.byKey(const ValueKey('first_launch_onboarding_overlay')), findsNothing);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL because the previous onboarding dismissal behavior assumes intro/onboarding are the same auto-start flow.

**Step 3: Write minimal implementation**

Refine `onDefer` handling so manual or intro-initiated onboarding dismisses back to the shell cleanly without reopening intro. Keep the existing confirmation dialog only for flows that still need confirmation.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`
Expected: PASS for onboarding defer behavior and prior widget tests.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/lib/app/pet_care_root.dart F:/HarmonyProject/Pet/test/widget_test.dart
git commit -m "fix: keep onboarding defer consistent after intro"
```

### Task 6: Add lightweight structure guards for copy and overlay separation

**Files:**
- Create: `F:/HarmonyProject/Pet/test/first_launch_intro_structure_test.dart`
- Modify: `F:/HarmonyProject/Pet/test/widget_test.dart`

**Step 1: Write the failing test**

Create a file-structure test that reads `lib/app/pet_first_launch_intro.dart` and checks for:

- approved brand copy `欢迎来到宠记`
- final CTA `添加第一只宠物`
- secondary CTA `先看看宠记`
- approved icon references

```dart
test('first-launch intro keeps approved brand copy and icon set', () {
  final source = File('lib/app/pet_first_launch_intro.dart').readAsStringSync();

  expect(source.contains('欢迎来到宠记'), isTrue);
  expect(source.contains('添加第一只宠物'), isTrue);
  expect(source.contains('先看看宠记'), isTrue);
  expect(source.contains('Icons.pets_rounded'), isTrue);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/first_launch_intro_structure_test.dart`
Expected: FAIL until the file and copy are present.

**Step 3: Write minimal implementation**

Create the structure test and adjust source keys/copy if needed so the intro remains easy to verify in future refactors.

**Step 4: Run test to verify it passes**

Run: `flutter test test/first_launch_intro_structure_test.dart test/widget_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add F:/HarmonyProject/Pet/test/first_launch_intro_structure_test.dart F:/HarmonyProject/Pet/test/widget_test.dart F:/HarmonyProject/Pet/lib/app/pet_first_launch_intro.dart
git commit -m "test: guard first-launch intro copy and icons"
```

### Task 7: Run the focused verification suite and update docs if needed

**Files:**
- Modify: `F:/HarmonyProject/Pet/README.md` (only if startup flow description needs documenting)
- Test: `F:/HarmonyProject/Pet/test/pet_care_store_test.dart`
- Test: `F:/HarmonyProject/Pet/test/widget_test.dart`
- Test: `F:/HarmonyProject/Pet/test/root_startup_structure_test.dart`
- Test: `F:/HarmonyProject/Pet/test/first_launch_intro_structure_test.dart`

**Step 1: Run the focused test suite**

Run:

```bash
flutter test test/pet_care_store_test.dart
flutter test test/widget_test.dart
flutter test test/root_startup_structure_test.dart
flutter test test/first_launch_intro_structure_test.dart
```

Expected: All PASS.

**Step 2: Run broader smoke coverage if the focused suite passes**

Run:

```bash
flutter test
```

Expected: PASS, or a clearly identified unrelated failure.

**Step 3: Update docs only if behavior changed in user-facing startup guidance**

If needed, add a short note to `README.md` or another user-facing document. Skip if it would be noise.

**Step 4: Commit**

```bash
git add F:/HarmonyProject/Pet/README.md
git commit -m "docs: note first-launch intro flow"
```

Skip this commit if no docs changed beyond tests and code commits above.
