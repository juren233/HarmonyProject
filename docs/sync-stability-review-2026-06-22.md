# PetNote 数据同步稳定性审查报告

日期：2026-06-22  
范围：只审阅同步相关实现与测试，不修改同步业务代码。本轮代码修改仅限宠物端时间刷新 UI。

## 结论摘要

PetNote 当前同步是自研的离线优先同步层：本地以 `PetNoteStore`/`sembast` 保存业务数据和未确认 mutation，客户端通过 WebSocket 连接同步服务器，协议中同时存在全量加密快照、实体 mutation、宠物端 checklist action、设备目录和 RTC 信令透传。这个方案已经具备本地优先写入、重启后重发未确认 mutation、事件回执和头像附件同步等基础能力，但稳定性仍主要受三类问题制约：

1. 同步状态拆散在多个内存队列、SharedPreferences、sembast 表和服务端 JSON 文件中，缺少统一的 durable checkpoint/outbox。
2. 快照、mutation、action 三条链路并存，且以自定义规则解决顺序、幂等和冲突，复杂度已经接近自研同步引擎的上限。
3. 服务端以单个 `households.json` 文件保存家庭组、事件日志和设备状态，缺少事务写入、压缩、上限和可观测性，数据量或弱网场景会放大不稳定。

建议短期先加固现有协议的持久化、限流、握手门禁和诊断；中期将同步模型收敛到“持久操作日志 + server sequence/checkpoint + 幂等写入 + 按实体冲突策略”；长期若继续加大跨端同步能力，优先评估 PowerSync 或 Couchbase Lite/Sync Gateway 这类成熟方案。

## 当前实现方式

### 客户端入口

- `SyncService` 根据 `DeviceRole` 创建 `OwnerSyncEngine` 或 `PetReplicaController`，两者都继承 `MultiDeviceSyncController`。参见 `lib/sync/sync_service.dart:89-107`、`lib/sync/sync_service.dart:109-200`、`lib/sync/sync_service.dart:202-294`。
- 配置读取依赖 `AppSettingsController`，包括 `householdId`、`householdAuthToken`、`sharedKeyBase64`、`servedPetId` 和待处理同步策略。参见 `lib/state/app_settings_controller.dart:56-70`、`lib/state/app_settings_controller.dart:128-168`。
- WebSocket 客户端 `SyncClient` 使用指数退避重连，连接后发送缓存帧，断线时把 `send()` 的帧放入内存 `_outbox`。参见 `lib/sync/sync_client.dart:43-90`、`lib/sync/sync_client.dart:105-132`。

### 数据与协议

- `MultiDeviceSyncController` 订阅 `transport.messages`，处理 `hello_ack`、`snapshot`、`mutation`、`action`、`devices`、`sync_received` 等消息。参见 `lib/sync/multi_device_sync_controller.dart:75-98`、`lib/sync/multi_device_sync_controller.dart:160-185`。
- 全量快照通过 `snapshot_push` 发送，内容为 `PetNoteDataState` JSON 加密后放在 `ciphertext`，宠物头像作为 base64 附件进入同一消息。参见 `lib/sync/multi_device_sync_controller.dart:119-158`、`lib/sync/sync_photo_attachment.dart:50-90`。
- 增量 mutation 由 `SyncMutationOutbox` 从 `store.localMutations` 监听并加密发送；未确认 mutation 持久化在本地 `pendingMutations` 表，收到 `sync_received` 后清除。参见 `lib/sync/sync_mutation_outbox.dart:35-54`、`lib/sync/sync_mutation_outbox.dart:60-106`、`lib/state/petnote_store.dart:2725-2740`、`lib/state/petnote_store.dart:3232-3265`。
- 宠物端 checklist action 有额外 dedupe/pending UI 状态，收到回执或远端 action 后再清理。参见 `lib/sync/sync_mutation_outbox.dart:125-166`、`lib/sync/sync_mutation_outbox.dart:187-223`。

### 服务端

- `SessionHandler` 每条 WebSocket 连接维护会话，先 `pair_*` 或 `hello` 注册，再允许 snapshot/action/mutation/device/RTC 信令处理。参见 `server/lib/src/session_handler.dart:23-83`、`server/lib/src/session_handler.dart:226-327`。
- 服务端把收到的 snapshot/mutation/action 注册为 `SyncEventReceipt`，广播给同 household 的其他设备，并等待 `sync_received` 后剪枝。参见 `server/lib/src/session_handler.dart:331-382`、`server/lib/src/session_handler.dart:533-638`、`server/lib/src/session_handler.dart:803-977`。
- `HouseholdStore` 以一个 JSON 文件保存所有 household、device、completed action 和 `syncEvents`。参见 `server/lib/src/household_store.dart:40-75`、`server/lib/src/household_store.dart:384-445`。

## 主要风险与缺陷

### 1. 失败队列不是 durable，重启/stop 会丢掉部分待发送消息

本地 mutation 本身会持久化，但 `SyncFailureQueue` 只用内存列表保存发送失败的 `SyncMessage`，`dispose()` 会直接清空。参见 `lib/sync/sync_failure_queue.dart:16-65`。这意味着 snapshot、devicesRequest、deviceUpdate、syncReceived 等非 mutation 消息在 App 被杀、角色切换或 controller 重建时可能丢失。

影响：容易出现“本地已改但对端迟迟不一致”“回执丢失导致服务端事件不剪枝”“设备分配状态没有可靠重放”。

建议：把所有出站消息统一落到持久 outbox，至少包含 `messageId`、`type`、`payloadHash`、`createdAt`、`attemptCount`、`lastError`、`nextRetryAt`，收到服务端 ack 后删除。

### 2. snapshot、mutation、action 三套链路并存，冲突语义分散

同一个数据域可能通过快照、普通 mutation 和 checklist action 三种方式同步。快照按 `dataPolicy` 决定 merge/remoteWins；mutation 走 `applyMutation`；checklist action 又有 `completedItemKeys`、`completedActions` 和服务端 special case。参见 `lib/sync/multi_device_sync_controller.dart:341-418`、`server/lib/src/session_handler.dart:331-382`、`server/lib/src/session_handler.dart:824-977`。

影响：在弱网、重连、设备长时间离线后，很容易出现顺序依赖或回放差异。代码里已有大量针对 checklist action 的补丁式规则，说明复杂度正在上升。

建议：收敛为一个标准操作日志模型：每个实体 mutation 都有稳定 `opId`、`entityId`、`baseRevision`、`newRevision`、`serverSeq`。快照只用于初始化/修复，不参与日常同步。

### 3. 服务端持久化是单文件 JSON，缺少事务与容量控制

`HouseholdStore.flush()` 直接 `writeAsString` 到 `households.json`，没有临时文件 + rename 的原子写策略，也没有按 household 分片或事件上限。参见 `server/lib/src/household_store.dart:434-445`。

影响：服务进程异常退出、磁盘写失败或并发 flush 可能导致文件损坏；头像 base64 和未剪枝事件增加后，读写整文件会越来越慢。

建议：短期改为 atomic write；中期把 server store 换成 SQLite/PostgreSQL，至少按 household/events/devices 分表，并对事件日志设置 TTL、大小上限和 compaction。

### 4. 回执剪枝依赖所有设备，离线/废弃设备会拖住事件日志

服务端 `_pruneReceivedSyncEvents` 需要除 origin 外所有 household devices 都收到事件才删除。参见 `server/lib/src/session_handler.dart:969-977`。如果设备永久离线但没有被移除，事件会一直留在 `syncEvents`。

影响：历史同步事件越来越多，新设备或重连设备会收到更大批量的补发；配合 base64 头像附件会放大带宽和服务端文件体积。

建议：为设备维护 `lastSeenMs`、软删除/过期策略；对事件建立 per-device cursor，事件只保留到最小 active cursor，废弃设备不阻塞 compaction。

### 5. 队列和附件缺少尺寸/数量背压

`SyncClient._outbox`、`SyncFailureQueue._messages` 都没有上限；快照会把宠物头像 base64 内联到消息中，单张最多 3MB，多个宠物会叠加。参见 `lib/sync/sync_client.dart:24-90`、`lib/sync/sync_failure_queue.dart:16-33`、`lib/sync/sync_photo_attachment.dart:40-90`。

影响：长时间离线或网络抖动时内存增长不可控；大快照经 WebSocket/JSON/base64 传输性能差，也更容易触发代理或移动网络限制。

建议：出站队列设硬上限和 backpressure；图片改成 content-addressed blob/附件通道，业务 mutation 只同步 `photoBlobId`，文件内容单独上传下载并校验 hash。

### 6. 认证/握手与业务消息没有严格门禁

客户端在启动 controller 后再连接并发送 `hello`，失败队列、重连和 hello ack 的时序由多个 listener 协作完成。当前 `hello_ack` 用于恢复 token/状态，但 controller 没有明确的“已认证后才 flush 所有业务 outbox”的状态机。参见 `lib/sync/sync_service.dart:153-164`、`lib/sync/sync_service.dart:243-256`、`lib/sync/sync_service.dart:426-480`。

影响：重连、旧 token、服务端重启恢复时，业务消息可能在认证状态不清晰时被排队或被拒绝，用户只能看到较粗粒度失败数。

建议：引入 `syncSessionState = disconnected/connecting/handshaking/authenticated/backingOff/blocked`；只有 authenticated 才允许 flush durable outbox，handshake error 进入可解释的阻塞状态。

### 7. 可观测性不足，难以快速判断“卡在哪一层”

客户端暴露 `failedSyncCount` 和 `lastError`，但错误不持久、不分类；服务端没有 per-household 队列长度、last seq、回执滞后、payload 大小等指标。

影响：用户反馈“同步不稳定”时，需要反复抓日志才能判断是认证、连接、附件、冲突、回执还是服务端事件堆积。

建议：新增同步诊断页/导出包，至少包含 connection state、handshake state、pending durable outbox 数、last ack time、last server seq、last error code、server `/debug/households/:id/sync-status`。

## 优化路线

### 短期加固（不重构架构）

1. 服务端 `households.json` 改 atomic write：写 `households.json.tmp` 后 rename，flush 串行化并记录失败日志。
2. 为 `SyncFailureQueue` 和 `SyncClient._outbox` 加最大数量/最大字节数，超过后进入 blocked 状态并提示用户。
3. 所有业务消息都等 `hello_ack` 后再发送；把握手失败原因映射成 UI 可读状态。
4. `sync_received` 也进入 durable outbox，避免回执丢失导致服务端事件无法剪枝。
5. 对服务端 `syncEvents` 做 active device TTL 和最大 retained events 保护。
6. 图片附件先做 hash 去重和压缩，再考虑拆成独立 blob 通道。

### 中期改造（保留自研协议）

1. 引入 server sequence：服务端给每条 event 分配单调递增 `serverSeq`，客户端保存 `lastPulledSeq`。
2. 引入 durable operation log：本地所有写入都先落 `pending_ops`，UI 从本地状态即时更新，网络层只负责上传/确认。
3. 以 entity revision 替代全量快照参与日常同步：`baseRevision` 不匹配时返回 conflict，由客户端按实体/字段策略解决。
4. 快照只用于初始化、灾难恢复和手动“以本机/对方为准”。
5. 增加协议兼容版本和迁移测试矩阵，避免旧 App/新服务器组合靠散落的 legacy 分支兜底。

## 第三方方案评估

| 方案 | 适配度 | 优点 | 风险/代价 | 建议 |
| --- | --- | --- | --- | --- |
| PowerSync | 高，官方有 Dart/Flutter SDK | 本地 SQLite、实时流式同步、watch query、后台上传队列、SDK 处理大量同步细节；官方文档明确本地写入会进入 upload queue 并在线后自动上传 | 需要把 PetNote 数据映射到 SQLite/后端源数据库，服务端要接入 PowerSync Service 或自托管形态；Harmony 需验证官方 Flutter 插件在 OHOS Flutter 下是否可编译 | 首选中长期候选，适合替换自研 sync engine |
| Couchbase Lite + Sync Gateway | 中 | 成熟移动/边缘同步体系，支持 WebSocket 复制、continuous push/pull、冲突 resolver、重试和心跳配置 | 引入 Couchbase Server/Sync Gateway 运维；Dart/Flutter 生态需要依赖 `cbl-dart`，Harmony 支持需单独验证；数据模型要文档化迁移 | 适合重视成熟移动同步和边缘场景，但工程迁移重 |
| RxDB Sync Engine | 中低 | 文档清楚，push/pull/pullStream、checkpoint、客户端冲突处理和批量传输是很好的架构参考 | 主要面向 JS/TS，不是 Flutter 原生首选；要落地需嵌 Web/JS 或重写协议思想 | 不建议直接接入，可借鉴其 checkpoint + assumedMasterState 模型 |
| ElectricSQL / Electric Next | 中低 | Postgres shape/subscription 思路适合服务端数据下发和局部复制 | 当前官方主线偏 shape/HTTP read subscription；离线写入和 Flutter/Harmony 落地不如 PowerSync 明确 | 不作为近期主选，可继续观察 Dart/SQLite 支持成熟度 |

## 网络调研依据

- Flutter 官方 Offline-first 指南：强调 repository 作为本地/远端数据统一入口，离线写入先写本地再同步，同时需要处理失败后的同步状态。[Flutter Offline-first support](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- PowerSync Dart/Flutter SDK：官方说明支持实时数据库变更流、本地 SQLite、后台执行、query subscriptions、`uploadData` 上传队列和 `watch` 查询。[PowerSync Flutter SDK](https://docs.powersync.com/client-sdks/reference/flutter)
- Couchbase Lite / Sync Gateway：官方说明通过 replicator 与 Sync Gateway 做安全双向同步，复制协议基于 WebSocket，并支持 continuous push/pull、冲突 resolver、heartbeat/retry。[Couchbase Lite replication](https://docs.couchbase.com/couchbase-lite/current/c/replication.html)、[Sync Gateway](https://docs.couchbase.com/sync-gateway/current/index.html)
- RxDB Sync Engine：官方文档描述 checkpoint、pushHandler、pullHandler、pullStream、客户端冲突处理和批量传输模型。[RxDB Replication](https://rxdb.info/replication.html)
- ElectricSQL Shapes：官方文档说明 shape subscription 和 live long-polling，同步服务把 shape log 推给客户端。[Electric Shapes](https://electric.ax/docs/sync/guides/shapes)

## 推荐下一步

1. 先做现有协议的“诊断与防丢”加固：durable outbox、认证后 flush、atomic server write、事件日志上限。
2. 同时开一个技术 spike：用 PowerSync 建一个 Pet/Todo/Reminder 最小表模型，验证 Android/iOS 官方 Flutter 与 Harmony OHOS Flutter 的依赖兼容性。
3. spike 通过后，再决定是继续自研中期改造，还是把同步底座迁移到 PowerSync/Couchbase Lite。
