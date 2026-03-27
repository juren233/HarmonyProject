# OHOS Flutter 3.35.8 Upgrade Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the in-repo OHOS Flutter SDK to `3.35.8-ohos-0.0.3` while keeping Android on official Flutter and preserving successful dual-platform builds.

**Architecture:** Upgrade the embedded OHOS Flutter git checkout in place, reapply any required local compatibility patches after the version switch, then verify the existing split build scripts still work end-to-end. Keep Android and Harmony SDK selection logic unchanged except for whatever the new OHOS SDK requires.

**Tech Stack:** PowerShell scripts, embedded Flutter SDK checkout, Hvigor/DevEco toolchain, Android Gradle build, Git

---

### Task 1: Snapshot current OHOS SDK state

**Files:**
- Create: `docs/plans/2026-03-26-ohos-flutter-3.35.8-upgrade.md`
- Create: `.upgrade-temp/ohos-flutter-hvigor.patch`
- Inspect: `.flutter_ohos_sdk_gitcode/packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts`

**Step 1: Save local SDK patch**

Run: `git -C F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode diff -- packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts > F:\HarmonyProject\Pet\.upgrade-temp\ohos-flutter-hvigor.patch`

**Step 2: Confirm current SDK version**

Run: `F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode\bin\flutter.bat --version`
Expected: `3.27.4-ohos-1.0.4`

### Task 2: Upgrade the embedded OHOS Flutter checkout

**Files:**
- Modify: `.flutter_ohos_sdk_gitcode`

**Step 1: Fetch remote tags**

Run: `git -C F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode fetch --tags origin`

**Step 2: Switch to target version**

Run: `git -C F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode checkout 3.35.8-ohos-0.0.3`

**Step 3: Verify target version**

Run: `F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode\bin\flutter.bat --version`
Expected: `3.35.8-ohos-0.0.3`

### Task 3: Reapply required compatibility fixes

**Files:**
- Modify: `.flutter_ohos_sdk_gitcode/packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts`
- Modify: `ohos/node_modules/flutter-hvigor-plugin/src/plugin/flutter-hvigor-plugin.ts`

**Step 1: Check whether the new SDK already includes the null-safe OHOS plugin handling**

Run: `git -C F:\HarmonyProject\Pet\.flutter_ohos_sdk_gitcode diff 3.35.8-ohos-0.0.3 -- packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts`

**Step 2: Reapply only if still needed**

Expected: `plugins.ohos` access must safely handle missing entries.

### Task 4: Verify split builds still work

**Files:**
- Verify: `scripts/flutter-ohos.ps1`
- Verify: `scripts/flutter-android.ps1`

**Step 1: Run Harmony build**

Run: `powershell -ExecutionPolicy Bypass -File F:\HarmonyProject\Pet\scripts\flutter-ohos.ps1 -Mode build -TargetPlatform x64`
Expected: signed HAP is produced

**Step 2: Run Android build**

Run: `powershell -ExecutionPolicy Bypass -File F:\HarmonyProject\Pet\scripts\flutter-android.ps1 -Mode build -BuildMode release -TargetPlatform arm64`
Expected: release APK is produced with official Flutter
