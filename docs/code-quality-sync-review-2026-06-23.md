# PetNote 代码质量与数据同步稳定性评估

日期：2026-06-23  
审查定位：L3 Team（未单独校准，按团队项目默认标准）  
范围：当前 `main` 的 Flutter 共享层、同步协议包、同步服务端、相关测试与分支状态。重点关注弱网、断线重连、进程重启、高频操作和多设备同步一致性。

## 结论摘要

当前 `main` 相比 2026-06-22 的旧同步审查已有明显进步：客户端已经有握手状态机、认证后发送门禁、持久化 outbox、pending mutation、首次配对默认双向 merge；服务端已经有按连接串行处理、事件回执账本、设备 role 持久化和 `households.json` 原子写入。这些改动已经覆盖了此前最危险的“启动时单向同步”“回执/出站消息进程重启丢失”“服务端写文件中断损坏”几类问题。

但如果目标是“极端网络和高频操作后仍稳定高效”，当前自研同步仍未到最终形态。主要剩余风险集中在四处：

1. 客户端还有双层 outbox：`SyncFailureQueue` 持久化队列之外，`SyncClient` 内部还有无上限内存 `_outbox`，发送路径复杂且缺少 backpressure。
2. 服务端事件账本仍按“所有登记设备回执才剪枝”，永久离线或废弃设备会拖住 `syncEvents` 增长。
3. 日常同步仍混用 snapshot、mutation、checklist action 三条链路，缺少统一 server sequence / checkpoint，冲突收敛依赖多处分支规则。
4. 诊断能力仍偏本地 UI 状态，缺少服务端 per-household 队列长度、事件滞后、payload 大小和 last seq 的可观测指标。

本轮建议：不要在当前轮贸然替换同步底座；先做“上限、压缩、可观测、checkpoint”四类增量加固。`codex/powersync-spike` 分支仍有保留价值，作为中长期迁移验证分支；已合并的 `feature/unified-ohos-flutter` 已在本轮删除。

## 当前已具备的可靠性基础

- `SyncService` 暴露 `SyncSessionState`、`SyncStatusSnapshot` 和 `SyncIssueKind`，能够区分断开、握手、认证、失败队列和待确认覆盖快照。证据：`lib/sync/sync_service.dart:92`、`lib/sync/sync_service.dart:96`、`lib/sync/sync_service.dart:113`。
- 业务消息通过 `canSend` 门禁限制在 authenticated 状态之后再从上层队列发送。证据：`lib/sync/sync_service.dart:228`、`lib/sync/sync_service.dart:464`、`lib/sync/sync_failure_queue.dart:144`。
- 默认首次配对在无显式策略时执行双向 merge：先推本地 merge 快照，再请求远端 merge 快照。证据：`lib/sync/sync_service.dart:249`、`lib/sync/sync_service.dart:260`、`lib/sync/sync_service.dart:264`、`lib/sync/sync_service.dart:360`、`lib/sync/sync_service.dart:364`、`lib/sync/sync_service.dart:368`。
- 非 mutation 出站消息已接入持久化 outbox，并按 household scope 过滤旧家庭残留。证据：`lib/sync/multi_device_sync_controller.dart:54`、`lib/sync/sync_failure_queue.dart:52`、`lib/sync/sync_failure_queue.dart:161`、`lib/state/petnote_store.dart:2770`。
- 本地业务 mutation 先进入 `PetNoteStore` pending mutation，再由 `SyncMutationOutbox` 发送，收到 `sync_received` 后清除。证据：`lib/state/petnote_store.dart:2757`、`lib/state/petnote_store.dart:2762`、`lib/sync/sync_mutation_outbox.dart:35`、`lib/sync/sync_mutation_outbox.dart:105`。
- 服务端每条 WebSocket 连接串行处理消息，避免同一连接内 snapshot/action/mutation 处理乱序。证据：`server/lib/src/session_handler.dart:21`、`server/lib/src/session_handler.dart:41`。
- 服务端持久化已使用 tmp + bak + rename 的原子写入形态，并串行 flush。证据：`server/lib/src/household_store.dart:389`、`server/lib/src/household_store.dart:435`、`server/lib/src/household_store.dart:450`。

## 重要问题与风险

### P1: 双层 outbox 与无上限内存队列

`SyncFailureQueue` 已经能把消息持久化到本地存储，但底层 `SyncClient.send()` 在 WebSocket 不在线时仍把帧追加到内存 `_outbox`，且没有数量、字节数或过期上限。证据：`lib/sync/sync_client.dart:27`、`lib/sync/sync_client.dart:60`、`lib/sync/sync_client.dart:82`。

影响：

- 弱网抖动时，同一条业务消息可能先被上层判断“可发送”，再被底层内存 outbox 缓存；可观测状态只统计上层 pending outbox，无法看到底层积压。
- 高频点击、频繁断网或代理半连接状态下，内存 `_outbox` 可以无界增长，App 进程被杀后这部分也没有恢复能力。
- 双层队列让故障定位变难：用户看到 `failedSyncCount=0` 不等于底层没有缓存帧。

建议：让 `SyncClient.send()` 在断线时直接抛出可分类错误，由 `SyncFailureQueue` 统一负责持久化、重试、去重和上限；或者给 `SyncClient` 内存队列设极小上限并把长度暴露进 `SyncStatusSnapshot`。优先方案是删除底层 `_outbox`。

### P1: 服务端事件账本缺少 active device cursor/TTL

服务端 `_pruneReceivedSyncEvents` 只有在除 origin 外所有登记设备都回执后才删除事件。证据：`server/lib/src/session_handler.dart:638`、`server/lib/src/session_handler.dart:804`、`server/lib/src/session_handler.dart:825`。

影响：

- 已配对但长期不用的设备会让 `syncEvents` 永久保留，后续每次 snapshotRequest 都可能重放更多事件。
- 头像附件、全量快照和高频 mutation 会放大 `households.json` 体积，最终拖慢服务端 load/flush。
- 依赖用户主动移除设备才能清理事件，对真实家庭设备换机/丢失/卸载不够稳。

建议：引入 active device 概念和 cursor：设备超过 N 天未见且非当前 active 设备时不再阻塞剪枝；服务端按 `serverSeq` 保存事件，每个设备维护 `lastAckSeq`，事件只保留到最小 active cursor；再加事件数量/字节上限和压缩任务。

### P2: 缺少 server sequence / checkpoint，重连恢复仍靠事件全扫

当前事件注册使用 `syncId` 和 payload，服务端向新连接补发时遍历 `household.syncEvents.values` 判断当前设备是否缺失。证据：`server/lib/src/household_store.dart:56`、`server/lib/src/session_handler.dart:804`、`server/lib/src/session_handler.dart:825`。

影响：

- 事件数量增长后，补发复杂度与 household 历史事件数相关。
- 客户端不能明确表达“我已处理到哪个 serverSeq”，只能通过逐条 `sync_received` 间接确认。
- 高频多端写入下，冲突调试缺少统一顺序坐标。

建议：服务端为所有 snapshot/mutation/action 分配单调 `serverSeq`；客户端本地保存 `lastPulledSeq` / `lastAckedSeq`；重连时请求 `eventsAfter(seq)`，服务端按 batch 下发并返回新 checkpoint。

### P2: snapshot、mutation、checklist action 三条链路冲突语义分散

日常同步既会使用 `snapshotPush`，也会使用 entity mutation，还会为宠物端待办 action 维护独立完成键和回执逻辑。证据：`lib/sync/multi_device_sync_controller.dart:132`、`lib/sync/multi_device_sync_controller.dart:262`、`lib/sync/multi_device_sync_controller.dart:288`、`server/lib/src/session_handler.dart:331`、`server/lib/src/session_handler.dart:397`。

影响：

- 同一个实体可能被快照 merge 和 mutation 同时触达，行为依赖 `dataPolicy`、`mergeMode`、source namespace、completedItemKeys 等多个维度。
- 复杂度已经从业务状态扩散到服务端特殊分支，继续增加“撤销、编辑冲突、附件删除、批量操作”时风险会继续上升。

建议：把快照降级为初始化/灾难恢复工具，日常同步统一走 operation log；每条 op 带 `opId`、`entityType`、`entityId`、`baseRevision`、`newRevision`、`serverSeq`，checklist action 也收敛为实体 op。

### P2: 队列和 payload 缺少背压策略

`SyncFailureQueue` 持久队列没有最大消息数/字节数，snapshot 会把完整 `PetNoteDataState` 和头像附件一起 JSON + 加密发送。证据：`lib/sync/sync_failure_queue.dart:32`、`lib/sync/sync_failure_queue.dart:76`、`lib/sync/multi_device_sync_controller.dart:143`、`lib/sync/multi_device_sync_controller.dart:145`。

影响：

- 长期离线或网络抖动下可能写入大量出站消息，存储和内存都没有明确保护线。
- 大图 base64 进入 WebSocket JSON 帧，弱网下容易造成代理切断、重复重传和 UI 感知“同步卡住”。

建议：设置上限，例如每 household pending outbox 最大消息数、最大总字节、最大单帧字节；超限时进入 blocked 状态并提示用户。头像改为 content-addressed blob：业务 op 只同步 `photoBlobId/hash/size`，文件内容单独分片上传下载。

### P3: 可观测性仍不足

客户端已有 `SyncStatusSnapshot`，但服务端没有公开 household 级诊断数据，用户反馈同步失败时仍难以判断是认证、网络、队列、冲突、附件还是服务端积压。

建议新增只读诊断接口或本地导出：`householdId`、设备数、active 设备数、`syncEvents` 数、最大 payload 字节、每设备 lastSeen/lastAckSeq、最近错误分类。注意生产接口必须走本地调试密钥或仅内网/管理员可访问。

## 外部资料取证与可借鉴设计

- Flutter 官方 Offline-first 指南强调 repository 应统一协调本地与远端数据，并允许离线时先读写本地、之后同步。来源：[Flutter Offline-first support](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)。PetNote 当前本地优先方向正确，但还需把上传队列和同步状态进一步产品化。
- PowerSync 官方说明其核心是让后端数据库与 App 内 SQLite 保持同步。来源：[PowerSync Docs](https://docs.powersync.com/)。这与 PetNote 的中长期方向吻合，尤其适合减少自研同步协议复杂度；当前 `codex/powersync-spike` 分支应保留。
- Couchbase Lite 文档说明通过 Sync Gateway 做本地数据库与远端的安全同步。来源：[Couchbase Lite replication](https://docs.couchbase.com/couchbase-lite/current/swift/replication.html)。它适合作为“成熟移动复制协议”的对照，但引入服务端和 SDK 迁移成本较高。
- RxDB Sync Engine 文档强调 local-first、离线继续写入、恢复连接后同步，并使用 pull handler / push handler / pull stream、checkpoint、冲突返回等模型。来源：[RxDB replication](https://rxdb.info/replication.html)。PetNote 自研协议最应该借鉴的是 checkpoint + assumedMasterState + conflict result 的清晰模型。
- Electric Shapes 文档强调只同步 Postgres 数据的子集，避免把所有数据都同步到本地。来源：[Electric Shapes](https://electric-sql.com/docs/guides/shapes)。PetNote 未来若支持多家庭/多宠大量记录，应考虑按设备角色和服务宠物裁剪同步范围。

## 分支留存评估

当前分支状态：

- `main`：当前工作分支，已推送到 `origin/main`。
- `codex/powersync-spike` / `origin/codex/powersync-spike`：未合并，包含 PowerSync spike 的 12 个提交。保留，原因是它正好对应本次同步中长期迁移评估，不能删除。
- `origin/feature/unified-ohos-flutter`：已合并到 `origin/main`，本轮已删除远端分支，后续可通过 tag/main 找回历史。
- `claude/frosty-greider-5d3ed7`：本地分支已合并到 `main`，对应 worktree 状态干净，本轮已删除 worktree 和本地分支。
- `/private/tmp/PetNote-v1.2.2-build`：worktree 元数据已经 prunable，本轮已执行 `git worktree prune` 清理无效引用。

## 优先行动清单

1. 短期：移除或限制 `SyncClient._outbox`，让持久 `SyncFailureQueue` 成为唯一出站队列，并补测试覆盖断线发送不进入不可见内存层。
2. 短期：给 `SyncFailureQueue` 加消息数/字节数上限，超限进入 `SyncSessionState.blocked` 或明确 issue kind。
3. 短期：服务端为 `syncEvents` 增加数量/字节统计、最大保留上限和日志告警；设备超过 TTL 未见时不再阻塞剪枝。
4. 中期：引入 `serverSeq`、per-device checkpoint 和 batch pull，替代按 `syncEvents.values` 全扫补发。
5. 中期：把 checklist action 收敛进统一 operation log，快照只保留初始化/恢复/手动覆盖用途。
6. 中长期：保留并继续推进 PowerSync spike，重点验证 Android/iOS 官方 Flutter、OHOS Flutter、服务端部署和数据迁移脚本。

## 本轮是否需要立即代码修复

本轮没有发现会直接导致当前 main 数据错位或同步完全失败的高危 bug；更多是“极端弱网/长期运行/高频写入”下的架构风险。考虑到同步链路刚经历多轮修复，当前最安全的交付是先落盘评估报告和分支清理，不在同一轮贸然改核心队列语义。下一轮若继续实现，建议从 `SyncClient._outbox` 收敛开始，影响面可控且测试边界清晰。
