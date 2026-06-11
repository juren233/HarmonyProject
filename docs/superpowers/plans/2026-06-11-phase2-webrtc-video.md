# 二期：WebRTC 远程视频实体功能 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在一期的配对/信令基础上实现真实跨网音视频——「视频通话」（双向）与「先看看它」（宠物端单向推流），全链路开源自建（flutter_webrtc + 自建信令 + STUN/coturn），无付费 SDK。

**Architecture:** 信令复用一期 SyncClient 的 WebSocket 通道与已定义的 `call_invite/call_answer/call_reject/call_end/ice_candidate` 消息（服务器已实现按 `targetDeviceId` 透传）。媒体面走 WebRTC P2P，NAT 失败兜底自建 coturn（短期凭证由服务器下发）。

**Tech Stack:** flutter_webrtc、coturn（Docker）、一期的 petnote_sync_protocol / petnote_sync_server。

**前置依赖：** 一期全部完成（配对、SyncService、宠物端看板、占位页）。

**项目纪律：** 同一期（定向测试、不碰真机、构建止于成功、pub 镜像 flutter-io.cn）。

---

### Task 1: Spike——flutter_webrtc 鸿蒙适配验证（决策门）

**Files:**
- Modify: `pubspec.yaml`
- Create: `docs/superpowers/specs/2026-XX-XX-webrtc-ohos-spike-result.md`（记录结论，XX 为执行日）

- [ ] **Step 1: 调研 OpenHarmony 适配源**——检索 Gitee `OpenHarmony-SIG` / `openharmony-tpc` 组织下的 flutter_webrtc 适配仓库（关键词 `flutter_webrtc ohos`），确认其支持的 flutter_webrtc 版本与 ohos SDK 版本，记录仓库地址与最近提交时间。

- [ ] **Step 2: 添加依赖并三端拉取**

```yaml
dependencies:
  flutter_webrtc: ^0.12.0   # 实际版本以 spike 调研结论为准
# 若 ohos 需要专用适配源，加 dependency_overrides 指向 git 仓库（写法与
# pubspec 中 url_launcher_harmonyos 的接入方式一致）
```

```bash
PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get
```

- [ ] **Step 3: 最小验证页**——临时页面 `lib/dev/webrtc_spike_page.dart`：`RTCVideoRenderer` + `navigator.mediaDevices.getUserMedia({'video': true, 'audio': true})` 本地回显（不联网）。仅用于构建验证，spike 结束后删除。

- [ ] **Step 4: 三端构建**

```bash
flutter build apk --debug          # 必须通过
# ohos：hvigor 构建（停 codegraph watcher）。通过→鸿蒙进支持矩阵；
# 失败→记录错误，鸿蒙降级（方案A：鸿蒙端不支持视频；方案B：宠物端 MJPEG 帧流兜底），
# 在 spike 结论文档中写明选择并同步用户。
```

- [ ] **Step 5: 写结论文档并提交**——支持矩阵（哪些端可做 owner 侧/pet 侧）、采用的依赖坐标、已知限制。

```bash
git add pubspec.yaml docs/
git commit -m "spike: flutter_webrtc ohos compatibility result"
```

### Task 2: 服务器——通话会话守护与 TURN 凭证下发

**Files:**
- Modify: `server/lib/src/session_handler.dart`
- Modify: `server/lib/src/server_app.dart`
- Test: `server/test/call_signaling_test.dart`

- [ ] **Step 1: 写失败测试**——两个客户端 hello 后：A 发 `call_invite{targetDeviceId:B}` → B 收到；B 发 `call_answer` → A 收到；`ice_candidate` 双向透传；目标设备离线时回 `call_reject{reason:'offline'}`；新增 `turn_credentials_request` → 返回 `{urls, username, credential, ttlSeconds}`。

- [ ] **Step 2: 实现**——
- 信令透传一期已有（`_relayToTarget`）；本任务补充：目标不在线时回 `call_reject{callId, reason:'offline'}`；
- TURN 凭证：coturn `use-auth-secret` 机制——`username = '<过期时间戳>:petnote'`，`credential = base64(hmac_sha1(TURN_SECRET, username))`，TTL 1 小时；`TURN_SECRET`/`TURN_URLS` 从环境变量读取，未配置时返回空列表（客户端仅用 STUN）；协议包 `SyncMessageTypes` 增加 `turnCredentialsRequest`/`turnCredentials`。

- [ ] **Step 3: `dart test` 通过后提交**

```bash
git add server packages/petnote_sync_protocol
git commit -m "feat(server): call signaling guards and TURN credential issuing"
```

### Task 3: 部署——启用 coturn

**Files:**
- Modify: `server/docker-compose.yml`（取消 coturn 注释，补环境变量）
- Modify: `server/README.md`（TURN 部署章节：开放 3478/udp、5349/tcp、relay 端口段；`TURN_SECRET` 生成；公网 IP `--external-ip` 配置）
- Test: 更新 `test/sync_server_deploy_structure_test.dart`（断言 coturn 服务未注释、`use-auth-secret` 存在）

- [ ] 完成后 `flutter test test/sync_server_deploy_structure_test.dart` 通过并提交：

```bash
git add server test/sync_server_deploy_structure_test.dart
git commit -m "feat(deploy): enable coturn with shared-secret auth"
```

### Task 4: 客户端 CallEngine（WebRTC 封装）

**Files:**
- Create: `lib/video/call_engine.dart`
- Create: `lib/video/call_signaling.dart`
- Test: `test/call_signaling_test.dart`（信令层可全测；RTC 层接口测试用抽象注入）

- [ ] **Step 1: `call_signaling.dart`**——复用一期 `SyncTransport`：

```dart
import 'dart:async';

import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum CallMode { call, watch }

/// 通话信令：在已建立的同步 WebSocket 上收发 call_* 消息。
class CallSignaling {
  CallSignaling({required this.transport, required this.selfDeviceId});

  final SyncTransport transport;
  final String selfDeviceId;

  Stream<SyncMessage> get callMessages => transport.messages.where((m) =>
      m.type == SyncMessageTypes.callInvite ||
      m.type == SyncMessageTypes.callAnswer ||
      m.type == SyncMessageTypes.callReject ||
      m.type == SyncMessageTypes.callEnd ||
      m.type == SyncMessageTypes.iceCandidate);

  void sendInvite({required String callId, required String targetDeviceId,
      required CallMode mode, required String sdp}) {
    transport.send(SyncMessage(SyncMessageTypes.callInvite, {
      'callId': callId, 'targetDeviceId': targetDeviceId,
      'mode': mode.name, 'sdp': sdp, 'fromDeviceId': selfDeviceId,
    }));
  }

  void sendAnswer({required String callId, required String targetDeviceId, required String sdp}) {
    transport.send(SyncMessage(SyncMessageTypes.callAnswer,
        {'callId': callId, 'targetDeviceId': targetDeviceId, 'sdp': sdp}));
  }

  void sendCandidate({required String callId, required String targetDeviceId,
      required Map<String, dynamic> candidate}) {
    transport.send(SyncMessage(SyncMessageTypes.iceCandidate,
        {'callId': callId, 'targetDeviceId': targetDeviceId, 'candidate': candidate}));
  }

  void sendEnd({required String callId, required String targetDeviceId}) {
    transport.send(SyncMessage(SyncMessageTypes.callEnd,
        {'callId': callId, 'targetDeviceId': targetDeviceId}));
  }

  void sendReject({required String callId, required String targetDeviceId, required String reason}) {
    transport.send(SyncMessage(SyncMessageTypes.callReject,
        {'callId': callId, 'targetDeviceId': targetDeviceId, 'reason': reason}));
  }
}
```

- [ ] **Step 2: `call_engine.dart`**——封装 `RTCPeerConnection` 生命周期：

- `startOutgoingCall({targetDeviceId, mode})`：获取本地媒体（`call`：音视频双开；`watch`：**不采集本地媒体**，`offerToReceiveAudio/Video: true` 仅收流）→ createOffer → sendInvite → 等 answer → setRemoteDescription；
- `acceptIncomingCall(invite)`（宠物端）：`call` 模式采集音视频；`watch` 模式同样采集（它是被看方）但**不渲染/不播放远端**（远端无流）→ createAnswer → sendAnswer；
- ICE：`onIceCandidate` → sendCandidate；收 `ice_candidate` → addCandidate；
- ICE servers：`[{urls: stun:stun.l.google.com:19302}]` + 服务器下发的 TURN 凭证（连接前发 `turn_credentials_request`）；
- 状态机 `ValueNotifier<CallState>`：idle/calling/ringing/connected/ended/failed；`onConnectionState` 为 failed/disconnected 时触发 `restartIce()`，10 秒未恢复挂断；
- 挂断：双向 sendEnd + 关闭 PeerConnection + 释放 MediaStream。

测试策略：RTC 对象不可在 flutter_test 中创建——`CallEngine` 构造注入 `PeerConnectionFactory`（`typedef`，生产为 `createPeerConnection`），信令交互与状态机用 fake factory 单测覆盖。

- [ ] **Step 3: 定向测试通过后提交**

```bash
git add lib/video test/call_signaling_test.dart
git commit -m "feat(video): call engine and signaling over sync channel"
```

### Task 5: 主人端通话 UI

**Files:**
- Create: `lib/video/owner_call_page.dart`
- Modify: `lib/app/remote_video_entry.dart`
- Test: `test/owner_call_page_test.dart`

- [ ] **Step 1: 实现 `OwnerCallPage`**——替换一期占位页跳转：
- 全屏 `RTCVideoView`（远端）+ `call` 模式右上角本地小窗（`watch` 模式无本地窗）；
- 底部控制条：静音（`watch` 模式隐藏）、挂断（红色大按钮）、切换前后摄像头请求（`watch` 模式下发送给宠物端的自定义消息，挂到 `device_update` 之外新增协议字段——若超出本期范围则仅 `call` 模式本地切换）；
- 呼出阶段显示「正在呼叫 <设备名>…」+ 取消；`call_reject{reason:'offline'}` → 提示设备离线；30 秒无应答自动取消。

- [ ] **Step 2: `remote_video_entry.dart`**——`_openPlaceholder` 改为：有在线宠物端 → push `OwnerCallPage(mode: ...)`；无 → 保留占位提示。

- [ ] **Step 3: widget 测试**（fake CallEngine 注入，断言控制条按 mode 显隐、挂断回调）通过后提交。

```bash
git add lib/video lib/app/remote_video_entry.dart test/owner_call_page_test.dart
git commit -m "feat(video): owner call/watch UI"
```

### Task 6: 宠物端来电处理

**Files:**
- Create: `lib/video/pet_call_overlay.dart`
- Modify: `lib/app/pet_device/pet_device_home.dart`
- Modify: `lib/app/pet_device/pet_device_settings_page.dart`
- Test: `test/pet_call_overlay_test.dart`

- [ ] **Step 1: 实现**——
- `PetDeviceHome` 监听 `CallSignaling.callMessages` 的 `call_invite`；
- `call` 模式：设置项「自动接听视频通话」（默认开，存 `pet_auto_answer_v1`）开启时直接 `acceptIncomingCall` 并全屏显示主人端画面 + 本地小窗；关闭时显示来电卡片（接听/拒接，30 秒超时自动 `sendReject{reason:'timeout'}`）；
- `watch` 模式：**始终自动接受**（产品语义：主人随时可以看）——采集并推流，看板界面仅在顶栏显示小红点「直播中 ●」（不打断看板展示，不渲染远端）；
- 通话期间调 `SyncService` 暂停快照接收处理（接收消息但延迟应用，挂断后应用最后一版），避免解密/落库与编解码抢资源；
- 挂断/结束后释放媒体并回看板。

- [ ] **Step 2: 测试**（fake 信令注入：watch invite 自动 answer；call invite 弹卡片）通过后提交。

```bash
git add lib/video lib/app/pet_device test/pet_call_overlay_test.dart
git commit -m "feat(video): pet-side auto-answer and silent watch streaming"
```

### Task 7: 摄像头/麦克风权限

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`（CAMERA / RECORD_AUDIO）
- Modify: `ios/Runner/Info.plist`（NSCameraUsageDescription / NSMicrophoneUsageDescription，中文文案）
- Modify: `ohos/entry/src/main/module.json5`（ohos.permission.CAMERA / MICROPHONE，含 reason 资源）
- Modify: `lib/video/call_engine.dart`（getUserMedia 失败 → `CallState.failed` + 用户可读错误「请在系统设置中允许摄像头/麦克风」）
- Test: `test/video_permission_structure_test.dart`（结构测试断言三端清单包含权限声明）

- [ ] 完成后定向测试通过并提交：

```bash
git add android ios ohos lib/video test/video_permission_structure_test.dart
git commit -m "feat(video): camera/microphone permission declarations"
```

### Task 8: 收尾——构建验证与验收清单

- [ ] **Step 1: 定向测试清单**

```bash
cd server && dart test && cd ..
flutter test test/call_signaling_test.dart
flutter test test/owner_call_page_test.dart
flutter test test/pet_call_overlay_test.dart
flutter test test/video_permission_structure_test.dart
flutter test test/remote_video_entry_test.dart
```

- [ ] **Step 2: 构建验证**——`flutter build apk --debug` + ohos hvigor 构建（按 spike 结论的平台矩阵）。

- [ ] **Step 3: 用户验收支持文档**——README 增补：验收三场景操作步骤（① call 双向音视频；② watch 单向监看（主人端不开摄麦）；③ 挂断/拒接/超时回到原页面），TURN 兜底验证方法（关 WiFi 走蜂窝测穿透）。

```bash
git add -A
git commit -m "chore: phase2 wrap-up - build verification and acceptance guide"
```

---

## 自查记录

- **Spec 覆盖**：spike→设计文档 §8.2-1；信令/coturn→§8.1、§8.2-2；主人端 UI→§8.2-3；宠物端→§8.2-4；权限→§8.2-5；弱网→Task 4 状态机 restartIce + Task 6 同步暂停（§8.2-6）；验收→Task 8（§8.3）。
- **决策门**：Task 1 spike 失败时鸿蒙降级路径已写明，后续任务以 Android/iOS 为基线不受阻塞。
- **类型一致性**：`CallMode`/`CallSignaling` 定义于 Task 4 并被 Task 5/6 引用；信令消息类型全部来自一期协议包。
