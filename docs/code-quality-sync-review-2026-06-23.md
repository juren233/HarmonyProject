# PetNote 代码质量与数据同步稳定性评估

日期：2026-06-23  
审查定位：L3 Team（未单独校准，按团队项目默认标准）  
范围：当前 `main` 的 Flutter 共享层、同步协议包、同步服务端、相关测试与分支状态。重点关注弱网、断线重连、进程重启、高频操作和多设备同步一致性。

## 结论摘要

当前 `main` 相比 2026-06-22 的旧同步审查已有明显进步：客户端已经有握手状态机、认证后发送门禁、单一持久化 outbox、pending mutation、首次配对默认双向 merge；服务端已经有按连接串行处理、事件回执账本、设备 role 持久化、`households.json` 原子写入、同步事件 TTL/数量/字节保留策略、只读诊断接口，以及 `serverSeq` / 设备 ack 水位基础。这些改动已经覆盖了此前最危险的“启动时单向同步”“回执/出站消息进程重启丢失”“服务端写文件中断损坏”“长期离线设备拖住剪枝”“服务端无诊断入口”几类问题。

但如果目标是“极端网络和高频操作后仍稳定高效”，当前自研同步仍未到最终形态。主要剩余风险集中在四处：

1. 客户端持久 outbox 已有数量/字节上限，但头像附件和全量 snapshot 仍可能形成大 payload，后续需要更细的 blob/分片同步策略。
2. 服务端事件账本已有 active device TTL 和容量上限，但补发路径仍按 `syncEvents.values` 全扫，事件多时效率和诊断定位仍不理想。
3. 日常同步仍混用 snapshot、mutation、checklist action 三条链路；服务端已具备 `serverSeq` / 设备 ack 水位基础，但客户端 checkpoint、按 seq batch pull 和统一 operation log 尚未完成。
4. 诊断能力已有服务端只读入口和 per-household 同步统计，后续还需要把 last pulled seq、事件滞后和客户端错误分类串起来。

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

### 已完成: 双层 outbox 与无上限内存队列收敛

`SyncClient` 底层不可见内存 outbox 已移除，断线发送显式抛错，由 `SyncFailureQueue` 统一负责持久化、去重、重试和容量控制。

剩余边界：大 snapshot / 附件 payload 仍需要更细粒度的 blob 与分片策略，避免单帧过大。

### 已完成: 服务端事件账本 active device TTL 与容量上限

服务端 `_pruneReceivedSyncEvents` 已只等待在线或近期活跃设备；`syncEvents` 同时有数量与 UTF-8 字节上限，超限时剪掉最旧事件并写日志告警。

剩余边界：服务端已记录 `serverSeq` 和 `lastAckServerSeq`，但还没有用 active cursor 直接驱动 batch pull / cursor prune。

### P2: 缺少 server sequence / checkpoint，重连恢复仍靠事件全扫

当前事件注册已分配 `serverSeq`，设备确认后服务端也会记录 `lastAckServerSeq`，但服务端向新连接补发仍遍历 `household.syncEvents.values` 判断当前设备是否缺失。证据：`server/lib/src/household_store.dart`、`server/lib/src/session_handler.dart`。

影响：

- 事件数量增长后，补发复杂度与 household 历史事件数相关。
- 客户端还不能明确持久表达“我已处理到哪个 serverSeq”，只能通过逐条 `sync_received` 间接确认，且当前 ack 水位只保存在服务端设备状态里。
- 高频多端写入下，冲突调试缺少统一顺序坐标。

建议：在现有服务端 `serverSeq` / `lastAckServerSeq` 基础上，继续让客户端本地保存 `lastPulledSeq` / `lastAckedSeq`；重连时请求 `eventsAfter(seq)`，服务端按 batch 下发并返回新 checkpoint。

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

### P3: 可观测性仍需串联端侧状态

客户端已有 `SyncStatusSnapshot`，服务端也已新增默认关闭的 household 级只读诊断入口，能够看到 household/device/syncEvents、事件字节数和 ack 水位；但用户反馈同步失败时，仍难以把服务端指标、客户端队列、认证错误、附件体积和具体冲突归因串成一条可读链路。

建议继续扩展只读诊断或本地导出：补充每设备 last pulled/last ack 差值、最近错误分类、最近大 payload 来源和客户端 outbox 状态。生产接口仍必须走诊断 token、内网或管理员访问边界。

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

1. 已完成：移除 `SyncClient._outbox`，让持久 `SyncFailureQueue` 成为唯一出站队列，并补测试覆盖断线发送不进入不可见内存层。
2. 已完成：给 `SyncFailureQueue` 加消息数/字节数上限，超限进入明确容量异常并保留既有队列。
3. 已完成：服务端为 `syncEvents` 增加数量/字节统计、最大保留上限和日志告警；设备超过 TTL 未见时不再阻塞剪枝。
4. 进行中：服务端已落地 `serverSeq` / per-device ack 水位基础；下一步引入客户端 checkpoint 和 batch pull，替代按 `syncEvents.values` 全扫补发。
5. 中期：把 checklist action 收敛进统一 operation log，快照只保留初始化/恢复/手动覆盖用途。
6. 中长期：保留并继续推进 PowerSync spike，重点验证 Android/iOS 官方 Flutter、OHOS Flutter、服务端部署和数据迁移脚本。

## 本轮是否需要立即代码修复

本轮没有发现会直接导致当前 main 数据错位或同步完全失败的高危 bug；更多是“极端弱网/长期运行/高频写入”下的架构风险。考虑到同步链路刚经历多轮修复，当前最安全的交付是先落盘评估报告和分支清理，不在同一轮贸然改核心队列语义。下一轮若继续实现，建议从 `SyncClient._outbox` 收敛开始，影响面可控且测试边界清晰。
