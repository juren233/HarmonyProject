# PetNote 同步功能安全与质量审查报告

**审查日期：** 2026-06-15
**审查范围：** v1.4.0-beta.2 → v1.4.0-beta.3 最近 5 个提交，涵盖同步协议、配对流程、客户端状态管理、服务端逻辑、平台原生代码、CI/CD 配置。
**审查方法：** 全量代码阅读 + 测试覆盖缺口分析

---

## 目录

- [CRITICAL — 必须在正式版前修复](#critical--必须在正式版前修复)
- [HIGH — 强烈建议尽快修复](#high--强烈建议尽快修复)
- [MEDIUM — 建议在 beta 期间修复](#medium--建议在-beta-期间修复)
- [LOW — 可在后续迭代中处理](#low--可在后续迭代中处理)
- [测试覆盖缺口](#测试覆盖缺口)
- [修复优先级建议](#修复优先级建议)

---

## CRITICAL — 必须在正式版前修复

### C1. 配对码 + HKDF 有效密钥熵仅 ~13 bit

**位置：** `packages/petnote_sync_protocol/lib/src/sync_crypto.dart:23-29`

配对码（4 位数字）直接作为 HKDF 的输入密钥材料。HKDF-SHA256 本身没问题，但输入熵只有 ~13 bit。salt 在 `pairJoined` 响应中明文传输（`server/lib/src/session_handler.dart:174`），对暴力破解无防护。攻击者拿到 salt 后离线穷举 10000 个配对码即可派生出共享密钥，解密所有同步流量。

**建议：** 至少用 PAKE（如 SPAKE2），或使用高熵共享密钥替代纯数字配对码。

---

### C2. ID 生成依赖列表长度，删除后碰撞

**位置：** `lib/state/petnote_store.dart:1510, 1549, 1607, 1843`

```dart
id: 'todo-${_todos.length + 1}'
```

`addTodo`、`addReminder`、`addRecord`、`addPet` 都用 `_list.length + 1` 生成 ID。删除元素后长度回退，新 ID 与已删除 ID 碰撞。

**复现场景：** 设备 A 有 `record-1`、`record-2`、`record-3`，删除 `record-3` 后 `_records.length` 变为 2，新建记录 ID 为 `record-3` — 与已删除记录同 ID。设备 B 上 `mergeData` 会产生冲突或 `appendData` 抛出 `StateError`。

**建议：** 使用 UUID 或独立单调递增计数器（不依赖列表长度）。

---

### C3. 消息信封明文，元数据泄露 + 可篡改

**位置：** `packages/petnote_sync_protocol/lib/src/sync_messages.dart:10`

```dart
String encode() => jsonEncode({'type': type, 'payload': payload});
```

`SyncMessage.encode()` 是纯 JSON，无 HMAC/签名。`actionPush` 的 `kind`、`sourceType`、`itemId` 明文传输（`lib/sync/pet_replica_controller.dart:162-169`）。

**影响：**
- 被动监听者可知道用户对哪个宠物做了什么操作
- 中间人可篡改 `type` 字段让服务器误路由消息
- 中间人可篡改 `kind` 字段改变服务器去重逻辑（`server/lib/src/session_handler.dart:315-342`）

---

### C4. 无重放保护

**位置：** `packages/petnote_sync_protocol/lib/src/sync_crypto.dart:40-52`

AES-GCM 保证单条消息的机密性和完整性，但无序列号/时间戳绑定。攻击者截获合法的 `actionPush` 密文后可重放。服务器不校验版本顺序（`snapshotPush` 的 `version` 仅客户端单调递增，服务器直接转发），可被利用回滚客户端状态。

---

### C5. 客户端 Store 加载失败 → 永久卡在 loading

**位置：** `lib/app/pet_device_home.dart:64-72`，`lib/app/petnote_root.dart:131-177`

`_loadStore()` 无 try/catch。存储损坏或超时时 `_store` 永远为 `null`，UI 永久显示 `CircularProgressIndicator`，用户无法操作，只能卸载重装。

**建议：** 包裹 try/catch，设置错误状态，显示重试按钮。

---

## HIGH — 强烈建议尽快修复

### H1. action 元数据明文泄露操作内容

**位置：** `lib/sync/pet_replica_controller.dart:162-169`

加密的只是 `PetAction` 对象本身，但信封里的 `kind`（操作类型）、`sourceType`（数据来源）、`itemId`（条目 ID）全是明文。服务器也用这些明文字段做去重和路由（`server/lib/src/session_handler.dart:296-342`），确认服务器可见这些数据。

---

### H2. authToken 明文传输

**位置：** `lib/sync/sync_service.dart:239`，`server/lib/src/session_handler.dart:137,176`

`hello` 消息中 authToken 明文发送，`pairCreated`/`pairJoined` 响应中也明文返回。完全依赖 TLS 保护，但无 TLS 强制校验（见 H7）。

---

### H3. SyncClient 只有 2 个测试，关键路径未覆盖

**位置：** `test/sync_client_test.dart`

**缺少的测试场景：**
- 指数退避验证（`_scheduleReconnect` 使用 `pow(2, exponent)` capped at 6）
- outbox 缓冲与重连后刷新
- 连接失败处理（`connect()` catch 路径）
- `dispose()` 生命周期
- 二进制帧处理（`_handleRawMessage` 对 non-String 的 FormatException）
- 重复 `connect()` 调用的 early return
- `connect()` 在 `dispose()` 后抛 StateError

---

### H4. SyncFailureQueue 零测试

**位置：** `lib/sync/sync_failure_queue.dart`

断连时排队、重连时重试、错误计数 — 全部无直接测试。仅通过其他模块间接覆盖。

---

### H5. SyncService.stop() 和角色切换无测试

**位置：** `test/sync_service_test.dart`

`stop()` 负责清理引擎、断开连接、通知监听器，无测试。从 owner 切到 pet（或反向）的 stop-then-restart 路径也无测试。`ensureStarted` 对 `DeviceRole.undecided` 的 early return、配置缺失时的 no-op、官方服务器解析失败的回退 — 全部未覆盖。

---

### H6. Android 5 个 Bridge 在引擎销毁时未清理

**位置：** `android/app/src/main/kotlin/com/krustykrab/petnote/MainActivity.kt:110-118`

`cleanUpFlutterEngine` 只清理了 3 个 bridge（`dataPackageFileAccessBridge`、`appDirectoryBridge`、`keepAliveBridge`），以下 bridge 的 MethodChannel handler 泄漏：

- `notificationBridge`（也无 `close()` 方法）
- `aiSecretStoreBridge`
- `introHapticsBridge`
- `nativeOptionPickerBridge`
- `nativePetPhotoPickerBridge`

`notificationBridge` 还持有 Activity 引用，阻止 GC。

---

### H7. 无 TLS 强制校验

**位置：** `server/lib/src/server_app.dart:27`，`lib/sync/sync_client.dart:55`

服务端 `shelf_io.serve` 绑定纯 HTTP。客户端 `WebSocket.connect(url)` 连 `ws://` 还是 `wss://` 取决于配置，无校验。若配置为 `ws://`，所有流量（含 authToken、配对码、密文）明文传输。

---

### H8. Android NotificationRestoreReceiver exported=true

**位置：** `android/app/src/main/AndroidManifest.xml:48-59`

系统广播接收器（`BOOT_COMPLETED`、`TIME_SET` 等）设了 `android:exported="true"`。系统广播会绕过 export 标志，设为 true 只让其他 app 也能向它发 intent，扩大攻击面。应改为 `exported="false"`。

---

### H9. CI release.yml 对所有 push 触发，无分支过滤

**位置：** `.github/workflows/release.yml:3-4`

```yaml
on: push
```

无 `branches:` 过滤。每次推送到任何分支（feature、hotfix 等）都触发完整构建流水线（`build-android`、`build-ios-unsigned`），浪费 CI 分钟数。publish 步骤虽有 main/beta 门控，但构建作业无条件执行。

---

### H10. SyncService 全局单例，角色切换时旧实例泄漏

**位置：** `lib/app/pet_device_home.dart:79-83`，`lib/app/petnote_root.dart:165`

`SyncService` 是静态单例（`static SyncService? instance`）。从 owner 切到 pet 时，`PetDeviceHome` 创建新实例覆盖它，`PetNoteRoot` 持有的旧实例及其 `resolveMergeConflict` 闭包变为孤儿，永远不会被调用。

---

## MEDIUM — 建议在 beta 期间修复

### M1. WebSocket 无消息大小限制

**位置：** `server/lib/src/server_app.dart:35`

`webSocketHandler` 对收到的消息无大小限制。恶意客户端可发超大消息耗尽服务端内存。应设置 `maxFrameSize` 或在 `SessionHandler._onData` 中检查长度。

---

### M2. syncEvents / completedActions 无限增长

**位置：** `server/lib/src/household_store.dart:47-50`

```dart
final Map<String, Map<String, dynamic>> completedActions = ...;
final Set<String> completedItemKeys = ...;
final Map<String, SyncEventReceipt> syncEvents = ...;
```

`_pruneReceivedSyncEvents` 仅清理所有设备都已确认的事件。某台设备长期离线时事件永不 prune。`completedActions` 完全没有清理机制，只会持续增长。长期运行后内存膨胀。

---

### M3. HouseholdStore.flush() 非原子写入

**位置：** `server/lib/src/household_store.dart:244`

```dart
await _file.writeAsString(jsonEncode({...}));
```

直接写目标文件。写入过程中崩溃（OOM、被 kill、断电）会截断 `households.json`，所有家庭组数据丢失。

**建议：** 先写临时文件再 rename：
```dart
final tmp = File('${_file.path}.tmp');
await tmp.writeAsString(jsonEncode({...}));
await tmp.rename(_file.path);
```

---

### M4. 服务端存储明文 JSON（含 authToken、密文）

**位置：** `server/lib/src/household_store.dart:52-64`

`HouseholdStore.flush()` 将完整家庭组状态（含 `authToken`、`saltBase64`、所有已完成操作的密文、所有同步事件的密文）写入明文 JSON 文件。文件系统被入侵后所有历史数据暴露。

---

### M5. PetNoteDataState.fromJson 无大小限制

**位置：** `lib/data/data_storage_models.dart:58-65`

```dart
factory PetNoteDataState.fromJson(Map<String, dynamic> json) {
  return PetNoteDataState(
    pets: _decodeList(json['pets'], Pet.fromJson),
    todos: _decodeList(json['todos'], TodoItem.fromJson),
    reminders: _decodeList(json['reminders'], ReminderItem.fromJson),
    records: _decodeList(json['records'], PetRecord.fromJson),
  );
}
```

解密后接受任意大小的列表。恶意 peer（持有共享密钥）可发送包含百万条记录的 snapshot 导致 OOM。`_decodeList` 还会静默跳过畸形条目而非失败，允许构造大量部分可解析的条目。

---

### M6. Pet.fromJson 等模型无字段值校验

**位置：** `lib/state/petnote_store.dart:268-471`

所有数据模型（`Pet`、`TodoItem`、`ReminderItem`、`PetRecord`）的 `fromJson` 只做类型转换，无内容校验：

- `id`：无格式检查，可为空、超长、含控制字符
- `name`：无长度限制，可达 MB 级
- `weightKg`：无范围检查，可为负数、Infinity、NaN
- `birthday`：无日期格式校验
- `photoPath`：接受任意文件系统路径，恶意 peer 可设为敏感路径

---

### M7. DevicesPage onPeerJoined 使用已失效的 ScaffoldMessenger

**位置：** `lib/app/devices_page.dart:174,197`

```dart
final messenger = ScaffoldMessenger.of(context);  // await 前捕获
// ... await ...
messenger.showSnackBar(...);  // peer 加入可能在页面已 pop 之后
```

`messenger` 在 await 前捕获。peer 加入是异步回调，可能发生在页面已 pop 之后，此时 messenger 已失效，可抛异常或静默失败。

**建议：** 在 `onPeerJoined` 回调内加 `if (!mounted) return;` 守卫。

---

### M8. _restartSync 无并发互斥

**位置：** `lib/app/pet_device_home.dart:74-99`

`_restartSync` 是 async 方法，从三个调用点以 `unawaited` 方式调用：

1. `_loadStore`（line 71）store 加载完成后
2. `_handleSettingsChanged`（line 103）每次设置变更
3. `didUpdateWidget`（line 53）settingsController 变更时

快速操作可导致多个 `_restartSync` 实例交错执行，`SyncService.instance` 被覆盖，旧 transport 泄漏。

**建议：** 加代数计数器（generation counter），每次调用递增，await 后检查计数器是否变化。

---

### M9. removedByOwner 在 build() 中直接调用 clearSyncPairing

**位置：** `lib/app/pet_device_home.dart:134-135`

```dart
if (controller?.removedByOwner.value == true) {
  unawaited(widget.settingsController.clearSyncPairing());
}
```

在 `AnimatedBuilder` 的 builder 里直接执行副作用。每次 listenable 变化触发 rebuild 时都会执行，可能在一次 build 周期内多次触发 `clearSyncPairing`。

**建议：** 移到 listener 回调中，并加 once 守卫确保只触发一次。

---

### M10. iOS 后台保活是静默空操作

**位置：** `ios/Runner/AppDelegate.swift:117-118`

`startBackgroundKeepAlive` 和 `stopBackgroundKeepAlive` 都直接返回 nil（成功），但 iOS 无 `UIBackgroundModes` 配置。Flutter 侧以为保活已启动，实际无效，无法区分"iOS 静默忽略"和"保活运行中"。

---

### M11. iOS Keychain 未设 kSecAttrAccessible

**位置：** `ios/Runner/AppDelegate.swift:193-209`

`writeKey` 方法未设置 `kSecAttrAccessible`。默认 `kSecAttrAccessibleWhenUnlocked`，设备锁定时后台读取密钥会失败。

**建议：** 如需后台访问，显式设置 `kSecAttrAccessibleAfterFirstUnlock`。

---

### M12. 通知 payload 中的 URL 未校验直接打开

**位置：** `ios/Runner/AppDelegate.swift:1773-1778`，Android `PetNoteNotificationBridge.kt:219`

`releaseUrl` 从通知 `userInfo` 中提取后直接传给 `UIApplication.shared.open`。若通知 payload 被篡改，可打开 `javascript:`、`data:` 或钓鱼 URL。

**建议：** 校验 scheme 只允许 `https`。

---

### M13. _connectionFailureMessage 对非网络错误泄露内部信息

**位置：** `lib/sync/owner_pairing_flow.dart:161-166`

```dart
String _connectionFailureMessage(Object error) {
  if (error is HandshakeException || error is SocketException) {
    return '无法连接同步服务器，请检查网络或服务器地址';
  }
  return '生成配对码失败：$error';  // 暴露 error.toString()
}
```

对 `HandshakeException`/`SocketException` 有友好提示，但其他异常直接暴露 `toString()`，可能含内部路径、类型名。

---

### M14. Predictable syncId (timestamp-based)

**位置：** `server/lib/src/session_handler.dart:487`

```dart
final syncId = '${DateTime.now().toUtc().microsecondsSinceEpoch}-${deviceId ?? 'unknown'}';
```

微秒时间戳 + deviceId，可预测。攻击者可伪造 `syncReceived` 确认导致事件被提前 prune。

---

### M15. Harmony avoidAreaChange 监听器未注销

**位置：** `ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets:287-296`

`refreshMeasuredBottomInset` 中注册 `win.on('avoidAreaChange', ...)` 监听器，但 `dispose()` 未调用 `win.off('avoidAreaChange')`。内存泄漏 + 回调在已销毁视图上触发。

---

### M16. SyncClient outbox 无大小限制

**位置：** `lib/sync/sync_client.dart:27,89`

```dart
final List<String> _outbox = <String>[];
// ...
_outbox.add(encoded);
```

断连期间所有发送请求无限缓冲。连接长时间不可用 + store 持续变更（触发 `snapshotPush`）可导致 outbox 无限增长。

---

### M17. PetNoteNotificationPlugin 静态强引用

**位置：** `ios/Runner/AppDelegate.swift:1529`

```swift
static var shared: PetNoteNotificationPlugin?
```

持有 `FlutterMethodChannel` 引用，引擎重建后旧 channel 无法 GC。

---

### M18. PairingFlow.joinAsPet 的 connect() 无超时

**位置：** `lib/sync/pairing_flow.dart:36-91`

`timeout` 只应用于 `completer.future`（line 62），不应用于 `transport.connect()`（line 52）。若 WebSocket 连接挂起（DNS 卡死、服务端不响应），`connect()` 可无限阻塞。

---

## LOW — 可在后续迭代中处理

| # | 问题 | 位置 |
|---|------|------|
| L1 | 服务端 Dockerfile 以 root 运行 | `server/Dockerfile` |
| L2 | Data model 缺少 `==`/`hashCode`，影响 merge 去重 | `lib/state/petnote_store.dart` 全局 |
| L3 | iOS 已废弃 API（`contentEdgeInsets`、`imageEdgeInsets`） | `ios/Runner/AppDelegate.swift:1026,1075` |
| L4 | Android KeepAliveService 缺 `onDestroy` 生命周期清理 | `android/.../KeepAliveService.kt` |
| L5 | Android `startForegroundService` 无 try/catch（Android 12+ 可抛异常） | `android/.../PetNoteKeepAliveBridge.kt:38-45` |
| L6 | Harmony `extractNativeLibs: true` 增大安装体积 | `ohos/entry/src/main/module.json5:14` |
| L7 | Harmony 缺少通知权限声明 | `ohos/entry/src/main/module.json5:41-65` |
| L8 | CI artifact action 版本不匹配（v6 upload / v8 download） | `.github/workflows/release.yml:379,477` |
| L9 | CI macOS runner 固定 `macos-26`，弃用后会断 | `.github/workflows/release.yml:390` |
| L10 | 配对码释放不撤销已签发的 authToken | `server/lib/src/session_handler.dart:630-639` |
| L11 | 同步状态标签误显示"重连中"（实际服务未启动） | `lib/app/pet_device_home.dart:164-171` |
| L12 | PetDeviceDashboard 云图标始终显示已连接 | `lib/app/pet_device_dashboard.dart:186-193` |
| L13 | merge 冲突闭包捕获的 context 可能在 dispose 过程中失效 | `lib/app/pet_device_home.dart:84-89` |
| L14 | SyncService `_attachHelloOnConnect` 重连时重复请求 snapshot 未做去重 | `lib/sync/sync_service.dart:204-226` |
| L15 | _invalidateOverviewAiReportState 数据变更时静默丢弃 AI 报告 | `lib/state/petnote_store.dart:2174-2179` |
| L16 | SyncClient `pingInterval` 30s 可能过于频繁 | `lib/sync/sync_client.dart:56` |

---

## 测试覆盖缺口

### SyncClient (`test/sync_client_test.dart`) — 仅 2 个测试

**已覆盖：** connect → send/receive hello+helloAck → 自动重连；畸形 JSON 通过 errors stream 暴露

**未覆盖：**
- 指数退避验证（`_scheduleReconnect` 使用 `pow(2, exponent)` capped at 6）
- outbox 缓冲与重连后刷新
- 连接失败处理（`connect()` catch 路径）
- `dispose()` 生命周期
- 二进制帧处理（`_handleRawMessage` 对 non-String 的 FormatException）
- 重复 `connect()` 调用的 early return
- `connect()` 在 `dispose()` 后抛 StateError

### SyncFailureQueue (`lib/sync/sync_failure_queue.dart`) — 0 个测试

断连时排队、重连时重试、错误计数 — 全部无直接测试。

### SyncService (`test/sync_service_test.dart`) — 10 个测试

**未覆盖：**
- `stop()` 生命周期
- 角色切换（owner ↔ pet 的 stop-then-restart）
- `DeviceRole.undecided` 的 early return
- 配置缺失时的 no-op
- 官方服务器解析失败的回退
- `merge` 初始同步策略（只测了 remoteWins 和 localWins）
- `failedSyncCount` 通过 `petController` 的路径

### OwnerSyncEngine (`test/owner_sync_engine_test.dart`) — 10+ 个测试

**未覆盖：**
- 节流行为（`throttle` Duration 默认 2s）
- `_lastPushedSnapshotKey` 去重
- `dispose()` 生命周期
- 畸形 `devices` 消息
- snapshot 缺少 ciphertext
- action 缺少/空 actionId
- `retryFailedSync()` 直接调用
- 并发快速 snapshot

### PetReplicaController (`test/pet_replica_controller_test.dart`) — 9 个测试

**未覆盖：**
- `start()` 双调用守卫
- snapshot 缺少 ciphertext
- action 缺少/空 actionId
- action 解密失败
- `dispose()` 生命周期
- `retryFailedSync()` 直接调用
- `pushSnapshotNow` 的 remoteWins 策略
- `removedByOwner` UI 响应
- `lastSyncedAt` 值通知

### 服务端集成测试 (`server/test/sync_flow_test.dart`) — 15 个测试

**未覆盖：**
- 两台设备同时 push snapshot 的并发场景
- WebRTC 信令（callAnswer、callReject、callEnd）
- `_relayToTarget` 目标设备不存在
- pairCreate 码耗尽时的 StateError
- 已注册会话重复 hello
- `actionAck` 处理

### 其他无专属测试的模块

| 模块 | 文件 | 缺失 |
|------|------|------|
| WsHub | `server/lib/src/ws_hub.dart` | 多连接、并发注册、closeAll |
| SessionHandler | `server/lib/src/session_handler.dart` | 边界条件仅靠集成测试覆盖 |
| PairingService | `server/lib/src/pairing_service.dart` | releaseCode、双次 redeem、码耗尽 |
| PairingFlow (客户端) | `lib/sync/pairing_flow.dart` | 错误 UI、超时、无效码输入 |
| DevicesPage | `test/devices_page_test.dart` | rename/unbind 执行、空列表、错误状态 |
| PetPairingPage | `test/pet_pairing_page_test.dart` | 配对错误 UI、超时状态、loading 状态 |

### 安全场景未覆盖

1. **重放攻击** — 无测试验证重放旧 action 消息的行为
2. **配对码暴力破解** — 无限速/锁定测试
3. **共享密钥泄露** — 无测试验证重新配对后旧密钥失效
4. **消息篡改** — 无测试验证信封字段被篡改后的行为
5. **跨家庭组消息注入** — 无测试验证 household A 的客户端不能向 household B 发消息

### 网络故障场景未覆盖

1. 同步中途 WebSocket 断开
2. 服务端主动关闭连接
3. DNS 解析失败
4. 快速 connect/disconnect 循环

---

## 修复优先级建议

### Beta 必修（上线前必须修复）

| 优先级 | 编号 | 问题 | 影响 |
|--------|------|------|------|
| 1 | C2 | ID 碰撞 | 数据损坏 |
| 2 | C5 | Store 加载失败卡死 | 用户体验灾难 |
| 3 | H6 | Android bridge 泄漏 | 内存泄漏 |
| 4 | M3 | flush 非原子写入 | 数据丢失 |
| 5 | M7 | stale messenger | 潜在崩溃 |
| 6 | M8 | _restartSync 竞态 | 状态混乱 |

### Beta 期间应修

| 优先级 | 编号 | 问题 | 影响 |
|--------|------|------|------|
| 7 | C1 | 配对码熵不足 | 安全：可离线暴力破解 |
| 8 | C3+C4 | 消息信封无保护 | 安全：泄露+篡改 |
| 9 | H5 | 角色切换无测试 | 回归风险 |
| 10 | M1 | WebSocket 无大小限制 | 稳定性：DoS |
| 11 | M2 | syncEvents 无限增长 | 稳定性：内存膨胀 |
| 12 | M5+M6 | 数据模型无校验 | 稳定性：OOM/异常数据 |

### GA 前完成

| 优先级 | 编号 | 问题 | 影响 |
|--------|------|------|------|
| 13 | H7 | TLS 强制 | 安全 |
| 14 | H9 | CI 触发优化 | 资源浪费 |
| 15 | H10 | 单例泄漏 | 状态不一致 |
| 16 | 其余 M/L | 见上表 | 各类 |
