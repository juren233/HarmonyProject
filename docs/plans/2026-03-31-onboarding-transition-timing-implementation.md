# Onboarding Transition Timing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Speed up the intro shrink-and-fade portion of the intro-to-onboarding handoff and reveal onboarding earlier without changing the hero expansion phase.

**Architecture:** Reuse the existing overlay transition controller in `pet_care_root.dart`, keep the intro expansion segment in `pet_first_launch_intro.dart` intact, and remap the post-expansion exit timing plus onboarding reveal timing in `pet_onboarding_overlay.dart`.

**Tech Stack:** Flutter, Dart, widget tests

---

### Task 1: Lock the expected timing in tests

**Files:**
- Modify: `test/widget_test.dart`

**Step 1: Write the failing test**

- Add a widget test that enters onboarding from the intro, pumps into the shrink phase, and expects onboarding opacity to already be greater than zero while the intro overlay opacity is still between zero and one.
- Keep the existing expansion-phase assertion that intro content remains fully visible early in the transition.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding begins revealing the first onboarding step before intro fully disappears"`

Expected: FAIL because onboarding still appears too late.

**Step 3: Write minimal implementation**

- Adjust the intro exit curves and onboarding reveal progress mapping only after the expansion phase.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding begins revealing the first onboarding step before intro fully disappears"`

Expected: PASS

### Task 2: Tighten the intro exit timing

**Files:**
- Modify: `lib/app/pet_first_launch_intro.dart`

**Step 1: Write the failing test**

- Reuse the timing assertions from Task 1 plus the existing expansion-phase coverage.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding keeps intro content fully visible during the hero expansion phase"`

Expected: PASS before code changes and remain PASS after the timing update.

**Step 3: Write minimal implementation**

- Keep the expansion branch unchanged.
- Compress the later shrink and fade windows.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding keeps intro content fully visible during the hero expansion phase"`

Expected: PASS

### Task 3: Reveal onboarding earlier during intro-driven transitions

**Files:**
- Modify: `lib/app/pet_onboarding_overlay.dart`

**Step 1: Write the failing test**

- Use the Task 1 onboarding-visibility test.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding begins revealing the first onboarding step before intro fully disappears"`

Expected: FAIL until reveal thresholds are moved earlier.

**Step 3: Write minimal implementation**

- Map `externalRevealProgress` into progressive reveal stages instead of returning `1.0`.
- Move onboarding opacity earlier so the shell appears during the intro shrink phase.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget_test.dart --plain-name "starting onboarding begins revealing the first onboarding step before intro fully disappears"`

Expected: PASS

### Task 4: Run focused regression coverage

**Files:**
- Modify: `test/widget_test.dart` if the assertions need final cleanup

**Step 1: Run focused tests**

Run:
- `flutter test test/widget_test.dart --plain-name "starting onboarding keeps intro content fully visible during the hero expansion phase"`
- `flutter test test/widget_test.dart --plain-name "starting onboarding begins revealing the first onboarding step before intro fully disappears"`
- `flutter test test/widget_test.dart --plain-name "explore first keeps intro visible briefly during the shell cross fade"`

**Step 2: Confirm output**

Expected: all selected tests PASS with no new failures in the adjusted transition flow.
