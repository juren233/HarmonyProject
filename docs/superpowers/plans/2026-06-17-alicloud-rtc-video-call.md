# 阿里云视频通话 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 `docs/superpowers/specs/2026-06-17-alicloud-rtc-video-call-design.md` 把远程视频占位入口推进为阿里云 RTC 视频通话能力。

**Architecture:** 服务端提供鉴权 Token API，现有 WebSocket 继续负责设备间呼叫信令；Flutter 提供微信式全屏通话页、状态机和统一 RTC Adapter；Android、iOS、Harmony 通过同一套 Dart 接口挂接各自原生 ARTC SDK。密钥只从服务端环境变量读取，不进入客户端或仓库。

**Tech Stack:** Dart / Flutter、shelf、web_socket_channel、MethodChannel、Android Kotlin、iOS Swift/ObjC、Harmony ArkTS、阿里云 ARTC SDK。

---

### Task 1: 服务端 Token API

**Files:**
- Create: `server/lib/src/rtc_token_service.dart`
- Modify: `server/lib/src/server_app.dart`
- Test: `server/test/rtc_token_service_test.dart`
- Test: `server/test/server_app_test.dart`

- [ ] **Step 1: Write failing service tests**

Add tests that prove:

```dart
test('missing ARTC env disables token issuing', () {
  final service = RtcTokenService.fromEnvironment({});
  expect(service.isConfigured, isFalse);
  expect(
    () => service.issueToken(
      channelId: 'petnote-demo',
      userId: 'owner-device',
      role: RtcUserRole.publisher,
    ),
    throwsA(isA<StateError>()),
  );
});

test('configured service returns token payload without exposing app key', () {
  final service = RtcTokenService.fromEnvironment({
    'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
    'ALICLOUD_RTC_APP_KEY': 'secret-app-key',
  });
  final token = service.issueToken(
    channelId: 'petnote-demo',
    userId: 'owner-device',
    role: RtcUserRole.publisher,
  );

  expect(token.appId, 'nml2ycrp');
  expect(token.channelId, 'petnote-demo');
  expect(token.userId, 'owner-device');
  expect(token.token, isNot(contains('secret-app-key')));
  expect(token.expiresAtMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
});
```

- [ ] **Step 2: Run RED**

Run from `server/`:

```powershell
dart test test/rtc_token_service_test.dart
```

Expected: FAIL because `RtcTokenService` does not exist.

- [ ] **Step 3: Implement `RtcTokenService`**

Create a focused service that:

- reads `ALICLOUD_RTC_APP_ID`
- reads `ALICLOUD_RTC_APP_KEY`
- validates `channelId` and `userId`
- returns a deterministic signed token payload suitable for app/server integration tests
- never exposes `appKey`

- [ ] **Step 4: Add HTTP endpoint tests**

Extend `server/test/server_app_test.dart` to verify:

- `POST /rtc/token` returns `503` when env is missing
- `POST /rtc/token` returns JSON when configured
- request body must include `channelId`, `userId`, and `role`

- [ ] **Step 5: Implement route**

Modify `SyncServerApp` to accept an optional RTC service and handle `POST /rtc/token`.

- [ ] **Step 6: Run GREEN**

Run:

```powershell
dart test test/rtc_token_service_test.dart
dart test test/server_app_test.dart
```

Expected: PASS.

### Task 2: 呼叫信令模型与客户端封装

**Files:**
- Modify: `packages/petnote_sync_protocol/lib/src/sync_messages.dart`
- Create: `lib/rtc/rtc_call_models.dart`
- Create: `lib/rtc/rtc_signaling_controller.dart`
- Test: `test/rtc_call_models_test.dart`
- Test: `test/rtc_signaling_controller_test.dart`

- [ ] **Step 1: Write failing model tests**

Cover call id, channel id, mode, target device id, pet id, and payload round-trip.

- [ ] **Step 2: Run RED**

Run one Flutter test by exact name:

```powershell
flutter test test/rtc_call_models_test.dart --plain-name "RTC call invite payload round trips"
```

Expected: FAIL because models do not exist.

- [ ] **Step 3: Implement models**

Add Dart-only models that can be parsed without platform symbols.

- [ ] **Step 4: Implement signaling controller**

Wrap existing sync client transport so UI can send `call_invite`, `call_answer`, `call_reject`, and `call_end`.

- [ ] **Step 5: Run targeted GREEN**

Run exact-name tests and clean Flutter test processes afterwards.

### Task 3: Flutter RTC Adapter 抽象

**Files:**
- Create: `lib/rtc/rtc_adapter.dart`
- Create: `lib/rtc/method_channel_rtc_adapter.dart`
- Test: `test/rtc_adapter_test.dart`

- [ ] **Step 1: Write failing adapter tests**

Verify the adapter exposes:

- `initialize`
- `join`
- `leave`
- `toggleCamera`
- `toggleMicrophone`
- `toggleSpeaker`
- `switchCamera`
- `dispose`

- [ ] **Step 2: Implement Dart abstraction**

Keep this file platform-neutral.

- [ ] **Step 3: Implement MethodChannel adapter**

Use a single channel name such as `petnote/rtc`.

- [ ] **Step 4: Run exact-name tests**

Run only adapter tests by `--plain-name`.

### Task 4: 微信式全屏通话页

**Files:**
- Modify: `lib/app/remote_video_entry.dart`
- Create: `lib/app/remote_video_call_page.dart`
- Test: `test/remote_video_entry_test.dart`
- Test: `test/remote_video_call_page_test.dart`

- [ ] **Step 1: Update failing widget tests**

Replace assertions that expect `RemoteVideoPlaceholderPage` with assertions that expect `RemoteVideoCallPage`.

- [ ] **Step 2: Run RED**

Run:

```powershell
flutter test test/remote_video_entry_test.dart --plain-name "爱宠页远程视频入口弹出两个选项并进入通话页"
```

Expected: FAIL while placeholder is still used.

- [ ] **Step 3: Implement page**

Use full-screen layout:

- dark video surface
- top contact/status row
- local preview corner
- bottom controls
- no extra instructional UI copy

- [ ] **Step 4: Wire entry to page**

`RemoteVideoPillButton` should push the new page.

- [ ] **Step 5: Run GREEN**

Run the updated exact-name tests.

### Task 5: 三端平台权限与桥接骨架

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt`
- Modify: `ios/Runner/Info.plist`
- Modify: `ohos/entry/src/main/module.json5`
- Modify: `ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets`
- Create: `ohos/entry/src/main/ets/plugins/PetNoteRtcPlugin.ets`
- Test: `test/android_rtc_bridge_structure_test.dart`
- Test: `test/ios_rtc_permission_structure_test.dart`
- Test: `test/harmony_rtc_bridge_structure_test.dart`

- [ ] **Step 1: Write structure tests**

Assert camera/microphone permissions and channel registration exist.

- [ ] **Step 2: Run RED**

Run each structure test by exact name.

- [ ] **Step 3: Add permissions and skeleton bridge**

No AppKey in client files. Method handlers may return explicit unsupported results until SDK libraries are wired.

- [ ] **Step 4: Run GREEN**

Run the structure tests by exact name.

### Task 6: README / deployment note

**Files:**
- Modify: `README.md`
- Modify: `server/README.md`
- Test: `test/sync_server_deploy_structure_test.dart`

- [ ] **Step 1: Write docs structure test**

Assert RTC env names are documented and no actual AppKey literal is present.

- [ ] **Step 2: Update docs**

Document:

- `ALICLOUD_RTC_APP_ID`
- `ALICLOUD_RTC_APP_KEY`
- `POST /rtc/token`
- server restart requirement

- [ ] **Step 3: Run docs test**

Run targeted structure test.

### Task 7: Final verification

**Files:**
- No new files.

- [ ] **Step 1: Run Dart server tests**

Run the two affected server tests.

- [ ] **Step 2: Run Flutter targeted tests**

Run only affected exact-name tests with short timeout discipline.

- [ ] **Step 3: Check processes**

Clean residual `dart.exe`, `dartvm.exe`, and `flutter_tester.exe` that belong to this run.

- [ ] **Step 4: Check diff**

Run:

```powershell
git diff --check
git status --short
```

- [ ] **Step 5: Report completion boundary**

Report which parts are fully implemented, which native SDK wiring still requires downloading/configuring official ARTC libraries, and which commands passed.
