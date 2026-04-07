# Performance And Refresh Rate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce redundant Flutter rebuild work in the PetNote app and add a lower-level Android frame-rate request path on top of the existing refresh-rate hint.

**Architecture:** Keep the current page structure intact, but memoize high-cost derived store data and stop reading the same derived getters multiple times per build. On Android, preserve `preferredRefreshRate` and add a guarded `View.setFrameRate()` request so devices that honor the lower-level API can opt into higher refresh behavior.

**Tech Stack:** Flutter, Dart, Kotlin, Android SDK, `flutter_test`, JUnit4

---

### Task 1: Lock Down Store Cache Behavior

**Files:**
- Create: `test/pet_care_store_cache_test.dart`
- Modify: `lib/state/pet_care_store.dart`

**Step 1: Write the failing tests**

- Assert repeated reads of `checklistSections`, `overviewSnapshot`, `remindersForSelectedPet`, and `recordsForSelectedPet` return the same cached object before invalidation.
- Assert relevant mutations invalidate only the expected caches.

**Step 2: Run test to verify it fails**

Run: `flutter test test/pet_care_store_cache_test.dart`

**Step 3: Write minimal implementation**

- Add private cache fields to `PetNoteStore`.
- Centralize cache invalidation into helper methods.
- Recompute cached values lazily only when invalid.

**Step 4: Run test to verify it passes**

Run: `flutter test test/pet_care_store_cache_test.dart`

### Task 2: Reduce Repeated Derived Reads In Widgets

**Files:**
- Modify: `lib/app/pet_care_root.dart`
- Modify: `lib/app/pet_care_pages.dart`

**Step 1: Add coverage indirectly through existing widget tests**

- Reuse existing widget tests as regression coverage for current UI behavior.

**Step 2: Write minimal implementation**

- Split root store-driven sections so the whole scaffold shell is not rebuilt from one builder.
- In each page build, read derived store values once into locals and reuse them.

**Step 3: Run regression tests**

Run: `flutter test test/widget_test.dart`

### Task 3: Add Android View Frame Rate Request Path

**Files:**
- Create: `android/app/src/main/kotlin/com/harmony/pet/pet_care_harmony/FrameRateRequestStrategy.kt`
- Create: `android/app/src/test/kotlin/com/harmony/pet/pet_care_harmony/FrameRateRequestStrategyTest.kt`
- Modify: `android/app/src/main/kotlin/com/harmony/pet/pet_care_harmony/MainActivity.kt`

**Step 1: Write the failing test**

- Assert view-level frame-rate requests only apply on supported SDK levels and only for positive refresh-rate requests.

**Step 2: Run test to verify it fails**

Run: `./gradlew testProfileUnitTest --tests com.harmony.pet.pet_care_harmony.FrameRateRequestStrategyTest`

**Step 3: Write minimal implementation**

- Add a small strategy helper for API gating.
- Keep `preferredRefreshRate`.
- Add guarded `decorView.setFrameRate(...)`.

**Step 4: Run tests to verify they pass**

Run: `./gradlew testDebugUnitTest --tests com.harmony.pet.pet_care_harmony.RefreshRatePreferencesTest --tests com.harmony.pet.pet_care_harmony.FrameRateRequestStrategyTest`

### Task 4: Final Verification

**Files:**
- Verify only

**Step 1: Run Dart tests**

Run: `flutter test test/pet_care_store_cache_test.dart test/widget_test.dart`

**Step 2: Run Android unit tests**

Run: `./gradlew testDebugUnitTest`

**Step 3: Inspect diff**

Run: `git diff -- lib/state/pet_care_store.dart lib/app/pet_care_root.dart lib/app/pet_care_pages.dart android/app/src/main/kotlin/com/harmony/pet/pet_care_harmony/MainActivity.kt android/app/src/main/kotlin/com/harmony/pet/pet_care_harmony/FrameRateRequestStrategy.kt android/app/src/test/kotlin/com/harmony/pet/pet_care_harmony/FrameRateRequestStrategyTest.kt test/pet_care_store_cache_test.dart`
