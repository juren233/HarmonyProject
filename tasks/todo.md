# 数据同步与远程视频故障审查

## 2026-06-23 客户端 serverSeq checkpoint 接入

- [x] 持久化客户端 `lastPulledServerSeq` 并在换家庭/清配对时重置 → 验证: settings 与同步测试覆盖
- [x] 默认 merge 拉取携带 `afterServerSeq` / `maxEvents` → 验证: owner/pet 启动和重连请求断言
- [x] 处理 `sync_checkpoint` 并在 `hasMore` 时续拉下一批 → 验证: checkpoint 入站测试覆盖水位推进和续拉
- [x] 入站事件应用失败时不得推进 checkpoint → 验证: 坏 mutation 后 checkpoint 不更新水位
- [x] 增量补发请求不再广播给其他设备 → 验证: server sync flow 测试覆盖
- [x] 跑客户端/服务端聚焦测试、analyze、diff 检查并排除 lock 噪音 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 客户端 settings 新增 `lastPulledServerSeq` 持久水位；切换家庭、重新配对或清除配对时会重置，避免旧家庭 checkpoint 串入新家庭。
- 默认 merge 拉取现在携带 `afterServerSeq` 与 `maxEvents=50`，收到 `sync_checkpoint` 后推进本地水位，若 `hasMore=true` 会继续请求下一批；显式 `remoteWins` 覆盖请求不携带 checkpoint。
- `MultiDeviceSyncController` 入站消息改为串行处理，确保 mutation/action/snapshot 与后续 checkpoint 按 WebSocket 顺序应用；如果入站事件应用失败，同批 checkpoint 不推进水位，避免跳过失败事件。
- 服务端区分增量补发与普通快照请求，带 `afterServerSeq` / `maxEvents` 的请求只返回缺失事件与 checkpoint，不再广播给其他设备触发额外快照。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/sync_service_test.dart test/owner_sync_engine_test.dart test/pet_replica_controller_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/sync_flow_test.dart`；客户端与服务端相关 analyze；`git diff --check`。复查无 lockfile diff 和测试残留进程。

## 2026-06-23 服务端按 serverSeq 增量补发

- [x] 为 `snapshot_request` 增加可选 `afterServerSeq` / `maxEvents` → 验证: 不传字段时旧补发行为不变
- [x] 服务端按 `serverSeq` 过滤与限量补发事件 → 验证: 测试只收到目标序号之后的事件且最多一批
- [x] 新增同步 checkpoint 响应 → 验证: 测试收到 `sync_checkpoint` 且包含 batch 边界和 remaining 标记
- [x] 跑协议/服务端测试、analyze、diff 检查并排除 lock 噪音 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- `snapshot_request` 现在可选携带 `afterServerSeq` 与 `maxEvents`；旧客户端不传字段时仍按原逻辑补发所有未确认事件，且不会额外收到 checkpoint。
- 服务端补发路径按 `serverSeq` 排序，支持只发送 `afterServerSeq` 之后的事件，并把单批数量限制在 `maxEvents`，服务端内部最大按 100 条钳制。
- 新增 `sync_checkpoint` 协议消息，增量请求后返回 `sentEventCount`、`remainingEventCount`、`fromServerSeq`、`toServerSeq` 与 `hasMore`，为后续客户端持久 checkpoint / batch pull 接入留好协议坐标。
- 验证通过：`cd packages/petnote_sync_protocol && ../../.flutter_ohos_sdk_gitcode/bin/dart test`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/sync_flow_test.dart`；协议与服务端相关 `dart analyze`；`git diff --check`。

## 2026-06-23 服务端 serverSeq / checkpoint 基础层

- [x] 为服务端同步事件增加单调 `serverSeq` → 验证: 新 snapshot/mutation/action 事件序号递增并持久化
- [x] 为旧 `syncEvents` 加载路径回填序号并推进 household 当前序号 → 验证: legacy 存储加载后事件有稳定 seq
- [x] 记录设备 `lastAckServerSeq` 水位 → 验证: `sync_received` 后对应设备 ack 水位更新
- [x] 在同步诊断接口暴露 household 当前 seq、最小 ack 和设备 ack → 验证: server app 测试覆盖诊断字段
- [x] 跑 server 测试、analyze、diff 检查并排除 lock 噪音 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 服务端 `Household` 现在维护 `nextServerSeq`，新注册的 snapshot/mutation/action 同步事件会分配单调 `serverSeq`，并把该序号放入服务端事件 payload。
- 旧 `syncEvents` 加载时会为缺少 `serverSeq` 的事件回填稳定序号，并推进 `nextServerSeq`，避免旧数据阻塞后续 checkpoint 设计。
- 设备模型新增 `lastAckServerSeq`，收到 `sync_received` 后记录对应设备已确认的最高服务端序号。
- `/diagnostics/sync` 现在暴露 `nextServerSeq`、事件 seq 范围、active 设备最小 ack 和每设备 ack 水位；这只是 checkpoint/batch pull 的服务端基础层，客户端 `lastPulledSeq` 与按 seq 拉取尚未实现。
- 验证通过：`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/pairing_test.dart test/server_app_test.dart test/sync_flow_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart analyze lib/src/household_store.dart lib/src/session_handler.dart lib/src/server_app.dart test/pairing_test.dart test/server_app_test.dart test/sync_flow_test.dart`；`git diff --check`。

## 2026-06-23 横屏宠物选择页左侧卡片排版再优化

- [x] 对齐“我的”页项目介绍 App 图标盒视觉参数 → 验证: widget 测试覆盖深浅色 logo 背景、边框、阴影和 SVG 过滤
- [x] 在左侧状态卡上部补充紧凑品牌说明并下移标题/连接状态 → 验证: 多尺寸横屏几何测试覆盖品牌区、标题和状态胶囊边界
- [x] 保持宠物选择交互和右侧列表布局不变 → 验证: 点击宠物卡片仍回调选择
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 横屏宠物选择页左侧状态卡上部品牌区补充“宠物日常关怀记录App”，与“我的”页项目介绍语义保持一致，同时保留 `宠记` / `PetNote`。
- App 图标盒继续随深浅色模式切换，阴影参数调整为与“我的”页项目介绍一致的 `blurRadius=16` / `offset=(0, 5)`。
- 状态卡内间距和标题字号轻微收紧，标题“这台设备照顾谁？”与连接状态胶囊继续位于卡片下部，`720x390`、`900x520`、`1180x620` 横屏尺寸均由 widget 几何测试约束不越界。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_device_dashboard_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart`；`git diff --check -- lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart tasks/todo.md`。

## 2026-06-23 服务端同步诊断接口

- [x] 新增默认关闭的只读同步诊断接口 → 验证: 未配置 token 时 `/diagnostics/sync` 返回 404
- [x] 诊断接口必须携带诊断 token → 验证: 缺少 token 返回 401，Bearer token 可访问
- [x] 输出 household/device/syncEvents 统计但不泄露密钥或密文 → 验证: 测试断言响应不包含 auth token 与 ciphertext
- [x] 跑 server app/sync flow 测试、server analyze、diff 检查并排除 lock 噪音 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 新增 `/diagnostics/sync` 只读接口，默认未配置诊断 token 时返回 404，避免生产环境误暴露。
- 配置 `diagnosticsToken` 或 `PETNOTE_SYNC_DIAGNOSTICS_TOKEN` 后，接口要求 `Authorization: Bearer ...` 或 `x-petnote-diagnostics-token`，未授权返回 401。
- 响应只包含 household/device/syncEvents 计数、活跃/在线设备数、事件字节统计和保留策略，不包含 `authToken`、共享密钥、snapshot/action/mutation 密文。
- 验证通过：`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/server_app_test.dart test/sync_flow_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart analyze lib/src/server_app.dart lib/src/session_handler.dart lib/src/household_store.dart test/server_app_test.dart test/sync_flow_test.dart`；`git diff --check`。

## 2026-06-23 服务端 syncEvents 保留策略加固

- [x] 长期离线设备不再阻塞已确认同步事件剪枝 → 验证: stale 设备 45 天未见时已确认 mutation 可清空 `syncEvents`
- [x] 为服务端同步事件账本增加数量上限 → 验证: 测试配置 `maxRetainedSyncEvents=2` 时保留最新事件
- [x] 为服务端同步事件账本增加 UTF-8 字节上限和日志告警 → 验证: 测试配置小字节上限时剪掉旧 snapshot 并保留最新事件
- [x] 跑服务端同步流测试、server analyze、diff 检查并排除 lock 噪音 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 服务端 `syncEvents` 剪枝现在只等待在线设备或最近 30 天内活跃的设备，长期离线/废弃设备不会永久拖住已被活跃设备确认的事件。
- `SyncServerApp` 增加同步事件数量与 UTF-8 字节保留上限，默认最多 1000 条 / 8 MiB；超限时按插入顺序剪掉最旧事件并写入服务端告警日志。
- 剪掉 `syncEvents` 时不删除 `actionSyncEventIds` / `mutationSyncEventIds`，保持旧 action/mutation 去重语义，避免历史事件被容量策略剪掉后重复广播。
- 验证通过：`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/sync_flow_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart analyze lib/src/server_app.dart lib/src/session_handler.dart test/sync_flow_test.dart`。

## 2026-06-23 SyncFailureQueue 容量保护

- [x] 为 durable sync outbox 增加消息数量上限 → 验证: 超过 `maxPendingMessages` 时拒绝新增并保留既有队列
- [x] 为 durable sync outbox 增加持久化字节上限 → 验证: 超过 `maxPendingBytes` 时拒绝新增并暴露容量异常
- [x] 按 UTF-8 实际持久化体积计算字节上限 → 验证: 多字节 payload 回归测试覆盖字符串长度误判场景
- [x] 跑同步相关测试、analyze、服务端同步流和 diff 检查 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- `SyncFailureQueue` 现在默认限制 durable outbox 最多 500 条、持久化 JSON 最多 64 MiB，弱网或服务端异常时不会无限堆积非 mutation 出站消息。
- 超过数量或字节上限时不会写入新消息，会保留既有队列并通过 `SyncOutboxCapacityException` 写入 `lastError`；同 `syncId` 替换消息超限时也不会误删旧消息。
- 字节上限按 UTF-8 编码后的实际持久化体积计算，新增多字节 payload 回归测试避免中文/emoji 被字符串长度低估。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/sync_client_test.dart test/sync_failure_queue_test.dart test/sync_service_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart lib/sync/sync_failure_queue.dart test/sync_failure_queue_test.dart lib/sync/sync_client.dart test/sync_client_test.dart lib/sync/sync_service.dart test/sync_service_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/sync_flow_test.dart`；`git diff --check`。

## 2026-06-23 横屏宠物选择页左侧卡片品牌区微调

- [x] 在横屏左侧状态卡上半区加入紧凑品牌信息 → 验证: widget 测试覆盖 `宠记` / `PetNote` 位于状态卡内
- [x] 保持标题和连接状态向下排列且不越界 → 验证: 多尺寸横屏几何测试覆盖品牌区、标题、状态胶囊边界
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 横屏宠物选择页左侧状态卡上半区现在展示紧凑品牌区，图标盒继续沿用“我的”页项目介绍卡片的深浅色背景、边框、阴影和深色 SVG 白色过滤逻辑。
- 标题“这台设备照顾谁？”与连接状态胶囊保持在卡片底部区域，品牌区、标题和状态胶囊均由多尺寸横屏几何测试约束在状态卡边界内。
- 右侧宠物列表、宠物卡片点击选择、设置按钮和竖屏选择页语义不变。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_device_dashboard_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart`；`git diff --check -- lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart tasks/todo.md`。

## 2026-06-23 SyncClient 出站队列收敛

- [x] 移除 `SyncClient` 底层不可见内存 outbox → 验证: 断线 `send()` 不再静默缓存
- [x] 让断线发送显式抛错交给 `SyncFailureQueue` 持久化 → 验证: sync client / service 回归测试
- [x] 跑同步相关 analyze、服务端同步流和 diff 检查 → 验证: 命令通过且无测试残留
- [x] 审查后提交推送触发 GitHub Actions → 验证: `gh run list` 出现新 run

### Review 2026-06-23

- `SyncClient` 已移除底层内存 `_outbox`，断线时 `send()` 直接抛 `StateError`，避免业务消息进入状态快照不可见、进程重启不可恢复的缓存层。
- 上层 `SyncFailureQueue` 继续作为唯一出站缓存，负责持久化、重试、去重和 household scope 过滤；新增测试锁定断线发送行为。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/sync_client_test.dart test/sync_failure_queue_test.dart test/sync_service_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/sync/sync_client.dart test/sync_client_test.dart lib/sync/sync_failure_queue.dart lib/sync/sync_service.dart test/sync_service_test.dart`；`cd server && ../.flutter_ohos_sdk_gitcode/bin/dart test test/sync_flow_test.dart`。

## 2026-06-23 全面代码质量与同步稳定性评估

- [x] 复核当前 CI、工作区和 README 约束 → 验证: `gh run list` / `git status` 证据明确
- [x] 审查 Flutter 客户端同步核心、服务端 relay 和协议包 → 验证: 关键文件与测试覆盖路径可追溯
- [x] 联网调研弱网/高频操作下的可靠同步实践 → 验证: 报告引用官方或成熟项目资料
- [x] 输出代码质量与同步稳定性评估报告 → 验证: `docs/` 落盘 Markdown
- [x] 审查本地和远端分支留存必要性 → 验证: merged/stale 分支清单与处理建议明确
- [x] 根据评估结果决定是否需要代码修复/提交推送 → 验证: 如有变更则测试、提交并触发 Actions

### Review 2026-06-23

- UI 提交 `852528b` 的 GitHub Actions 已完成：`PetNote Notify` 和 `PetNote Release` 均 success，并生成 `v1.4.0-beta.39`。
- 新评估报告已落盘到 `docs/code-quality-sync-review-2026-06-23.md`，覆盖当前 main 的同步可靠性基线、剩余风险、外部官方资料依据、优先行动清单和分支留存结论。
- 审查结论：当前 main 已具备握手门禁、持久 outbox、首次配对双向 merge、服务端原子写入等基础；剩余重点是收敛 `SyncClient._outbox`、增加队列/事件上限、引入 server sequence/checkpoint 和服务端诊断。
- 分支处理：已删除已合并远端 `origin/feature/unified-ohos-flutter`；已删除干净且已合并的本地 `claude/frosty-greider-5d3ed7` worktree/分支；保留未合并且有同步迁移价值的 `codex/powersync-spike`。
- 本轮没有直接修改同步核心代码，原因是未发现当前 main 会直接导致数据错位或同步完全失败的高危 bug；报告建议下一轮从 `SyncClient._outbox` 收敛开始做低风险增量修复。

## 2026-06-23 横屏宠物选择页左侧卡片图标排版优化

- [x] 在横屏选择页左侧状态卡加入深浅色自适应 App 图标 → 验证: widget 测试覆盖 light/dark logo 样式
- [x] 下移标题和连接状态并收紧卡片内部边界 → 验证: 多尺寸横屏几何测试无溢出
- [x] 保持右侧列表和宠物选择交互不变 → 验证: 点击宠物卡片仍回调选择
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: 命令通过且无测试残留

### Review 2026-06-23

- 横屏宠物选择页左侧状态卡新增 App 图标，复用“我的”页项目介绍卡片的白/黑图标盒、边框、阴影和深色模式白色 SVG 过滤逻辑。
- 状态卡改为上方图标、下方标题和连接状态胶囊的结构，标题与状态整体下移，`LayoutBuilder` 按卡片高度调整图标尺寸与间距，避免横屏小尺寸越界。
- 右侧宠物列表和点击选择回调保持不变；新增测试覆盖 `720x390`、`900x520`、`1180x620` 横屏几何边界和深浅色图标样式。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_device_dashboard_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart`。

## 2026-06-23 主人端头像 emoji fallback 与宠物类型预设扩展

- [x] 主人端无图片宠物头像改用类型 emoji fallback，其他类型保持原缩写 → 验证: 主人端宠物列表 widget 测试
- [x] 扩展宠物类型枚举、标签和头像映射 → 验证: store 序列化/反序列化与 fallback 测试
- [x] 按联网取证结果更新建档预设类型与品种/常见饲养类型 → 验证: taxonomy 测试覆盖新增类型和每类数量
- [x] 落盘预设来源审阅文档 → 验证: docs 中包含来源、边界和不纳入猴类说明
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: Flutter tests、`flutter analyze`、`git diff --check`

### Review 2026-06-23

- 主人端宠物列表无图片头像现在复用 `petAvatarFallbackForPet`，猫狗兔鸟及新增类型显示对应 emoji；`other` 继续显示原 `avatarText` 缩写。
- `PetType` 新增仓鼠、鱼、龟、蛇、马、猪、鸡、牛、羊、山羊、啮齿类；旧未知 `type` 仍降级为 `other`，不做数据迁移。
- 添加宠物引导页预设已按联网取证结果扩展：猫狗提供更多大众品种；鸟、鱼、龟、蛇、仓鼠、啮齿类按常见饲养类型处理；猴类未纳入预设。
- 来源审阅已落盘到 `docs/pet-breed-preset-source-review-2026-06-23.md`，记录来源、预设口径和维护边界。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_care_store_test.dart test/pet_onboarding_taxonomy_test.dart test/pets_page_subtitle_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter test test/widget_test.dart test/pet_replica_controller_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter test test/ai_insights_widget_test.dart --plain-name "overview page prefers pet photo and uses emoji or abbreviation fallback"`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/state/petnote_store.dart lib/app/petnote_pages_pets.dart lib/app/pet_onboarding_taxonomy.dart test/pet_care_store_test.dart test/pet_onboarding_taxonomy_test.dart test/pets_page_subtitle_test.dart test/widget_test.dart`；`git diff --check`。完整 `test/ai_insights_widget_test.dart` 曾卡在既有浮动按钮布局用例，已终止并改跑本轮相关聚焦用例；复查无 Flutter 测试残留进程。

## 2026-06-23 宠物端头像返回选择页

- [x] 为宠物待办页头像添加返回选择列表交互 → 验证: 点击头像回调清空服务宠物
- [x] 保持界面无新增提示文案 → 验证: 仅增加语义按钮与 widget 测试
- [x] 运行聚焦测试和静态检查 → 验证: dashboard 测试、analyze、diff check 通过

### Review 2026-06-23

- 宠物待办页头像现在是可点击语义按钮，点击后复用现有 `servedPetId = null` 路径返回宠物选择列表，不新增任何可见指引文案。
- 新增 widget 测试覆盖点击头像后回调清空服务宠物并重新展示 `pet_selector_list_panel`。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_device_dashboard_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart lib/app/pet_device_home.dart test/pet_device_dashboard_test.dart`；`git diff --check`。

## 2026-06-22 宠物端 UI 与首次配对同步修复

- [x] 修复首启角色页深色模式图标背景 → 验证: 浅色/深色 widget 测试覆盖 hero 颜色
- [x] 修复宠物端选择页卡片阴影和横屏重复标题 → 验证: dashboard widget 测试覆盖无阴影、无右侧重复标题、点击选择仍可用
- [x] 修复宠物端同步异常展示和时间栏换行 → 验证: 不再出现额外 `sync_failure_chip`，状态胶囊可打开同步问题弹窗
- [x] 修复首次配对默认 merge 只拉不推的问题 → 验证: sync service 测试覆盖默认双向快照交换和 `pushStartupSnapshot=false`
- [x] 输出首次配对同步根因报告 → 验证: `docs/pet-initial-pairing-sync-root-cause-2026-06-22.md`
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: 计划内命令通过并清理本次测试残留

### Review 2026-06-22

- 首启角色页保留浅色软蓝图标背景，深色模式切换为深蓝灰圆形背景与高对比蓝色设备图标，避免深色主题下大浅色圆块突兀。
- 宠物端选择页小卡片已移除阴影，仅保留背景、圆角和边框；横屏右侧列表面板不再重复显示“这台设备照顾谁？”，该语义只保留在左侧状态卡。
- 宠物端看板/选择页顶部不再使用额外 `SyncFailureChip`；同步失败、握手失败和等待确认统一由原状态胶囊展示并打开同一同步问题弹窗，时间/日期约束为单行缩放或省略。
- 默认首次配对启动改为双向 merge 快照交换：认证后先推本地 merge 快照，再请求远端 merge 快照，修复“先添加宠物再配对”时已有宠物不稳定下发的问题；显式同步策略和 `pushStartupSnapshot=false` 保护路径保持不变。
- 根因报告已落盘到 `docs/pet-initial-pairing-sync-root-cause-2026-06-22.md`，记录现象、方向性缺口、修复策略、保护边界和验证场景。
- 验证通过：`.flutter_ohos_sdk_gitcode/bin/flutter test test/pet_device_dashboard_test.dart test/widget_test.dart test/sync_service_test.dart test/owner_sync_engine_test.dart test/pet_replica_controller_test.dart`；`.flutter_ohos_sdk_gitcode/bin/flutter analyze lib/app/pet_device_dashboard.dart lib/app/pet_first_launch_intro.dart lib/app/petnote_pages.dart lib/app/pet_device_home.dart lib/sync/sync_service.dart test/pet_device_dashboard_test.dart test/widget_test.dart test/sync_service_test.dart`；`git diff --check`。复查无本次 Flutter/Gradle 测试残留，仅有常驻 `xcodebuildmcp`。

## 2026-06-22 main 同步稳定性加固

- [x] 启用 PUA always-on 模式 → 验证: `~/.pua/config.json` 保留未知字段且 `always_on=true`
- [x] 新增同步会话状态机和握手门禁 → 验证: 业务消息在 `hello_ack` 后才 flush
- [x] 新增 durable sync outbox 覆盖非 mutation 出站消息 → 验证: 重启后 `syncReceived/deviceUpdate/snapshotRequest` 仍可重发
- [x] 优化启动、后台恢复和重连拉取 → 验证: 恢复时 flush pending 并主动 request snapshot，且带冷却
- [x] 增强同步状态监控 → 验证: 状态快照包含连接/握手/outbox/mutation/error/next retry
- [x] 加固服务端文件写入和设备在线时间 → 验证: atomic flush 与 `hello` 更新 `lastSeenMs`
- [x] 跑聚焦测试、analyze 和 Android/iOS 构建 → 验证: README 认可命令通过并清理构建残留

### Review 2026-06-22

- 客户端同步链路新增 `SyncSessionState` 与 `SyncStatusSnapshot`，业务消息通过 `canSend` 门禁限制在 `hello_ack` 后 flush；`pair_error` / 握手超时进入可解释的 blocked/handshakeFailed 状态，不再直接 stop。
- 非 mutation 出站消息接入 `sync_outbox_v1` durable outbox；`dispose()` 不再清持久队列，真正的数据重置/解绑仍会清理，pending reset snapshot 通过同一 `syncId` 去重重推。
- 启动、前台恢复、重连恢复改为认证后重试 outbox / pending mutation 并主动拉取快照；既有配对冷启动不再无条件推 full merge snapshot，降低重复宠物风险。
- 服务端 `households.json` 写入改为串行 flush + tmp/bak rename 恢复；`hello` 更新 `lastSeenMs` 由 sync flow 覆盖。
- 验证通过：`flutter test test/sync_client_test.dart test/sync_service_test.dart test/owner_sync_engine_test.dart test/pet_replica_controller_test.dart`；`cd server && dart test test/household_store_test.dart test/sync_flow_test.dart`；客户端与服务端改动文件 analyze。
- 构建通过：Android arm64 APK `build/app/outputs/flutter-apk/app-release.apk` SHA256 `dc9078c9e220ef335313259563e6bf364d6ea9cfb2266e8e1ca1e530ea6f23f0`；iOS unsigned IPA `build/ios/Runner-unsigned.ipa` SHA256 `d8df04cc5c3e7f7d66624013a47bb1926b78caadfb8c78639e0241775798d9d6`。
- 构建后清理：已删除 unsigned IPA 临时 staging 目录，`./gradlew --stop` 停止 Gradle daemon；复查无 Gradle/Kotlin/Flutter test/build 残留，仅剩常驻 `xcodebuildmcp` 工具服务。

### Confidence Review 2026-06-22

- 继续审查后修复两个真实漏洞：`SyncFailureQueue` 持久化写入改为串行队列，避免连续 enqueue/clear 时旧写入覆盖新状态；durable outbox 增加 `scopeKey=householdId` 并在 restore 时过滤/剪除其他家庭的旧消息，避免杀进程后新配对复活旧家庭消息。
- 补强状态与弱网覆盖：状态快照的 `pendingOutboxCount` 读取真实 durable outbox 数；握手失败/超时写入 `lastError`；新增测试覆盖握手超时后底层重连会重新 hello 并恢复 authenticated。
- 新增/更新回归测试：`test/sync_failure_queue_test.dart` 覆盖串行持久化与 household scope 过滤；`test/sync_service_test.dart` 覆盖真实 outbox 数、清配对清 outbox、新配对进程重启过滤旧 outbox、握手错误可诊断、握手超时后重连恢复。
- 最新验证通过：`flutter test test/sync_client_test.dart test/sync_failure_queue_test.dart test/sync_service_test.dart test/owner_sync_engine_test.dart test/pet_replica_controller_test.dart`；`cd server && dart test test/household_store_test.dart test/sync_flow_test.dart`；客户端同步相关 `flutter analyze`；服务端同步相关 `dart analyze`。
- 最新构建通过：Android arm64 APK `build/app/outputs/flutter-apk/app-release.apk` SHA256 `1ee95004c319f16ee0252aa01d7e4a8916a95cc9bc5c4647fca82012c320e2e2`；iOS unsigned IPA `build/ios/Runner-unsigned.ipa` SHA256 `f4f1499120eff8db5790ecb229819545ab84ac1ea26b4b447729529fe4dfd8d7`。
- 构建后清理：已删除 IPA 临时 staging 目录，`./gradlew --stop` 后复查无 Gradle/Kotlin/Flutter test/build 残留；仅剩常驻 `xcodebuildmcp` 工具服务。
- 剩余边界：本地自动化已覆盖弱网断线、握手门禁、后台/恢复触发、进程重启 outbox 恢复与去旧家庭消息；“事实上的 100%”仍不能替代双 Android 真机弱网/退后台/杀进程验收，因为真实系统调度、网络切换和 release 设备日志不完全可由单元测试模拟。

## 2026-06-22 同步异常状态拆分与诊断日志

- [x] 复核双端 Android 当前安装状态和线上同步服务健康状态 → 验证: 两端均为 `versionCode=44`，公网 `/healthz` 返回 `ok`
- [x] 区分真正同步失败、握手失败和等待覆盖快照确认三类状态 → 验证: `SyncService.currentIssueKind` 聚焦测试
- [x] 将等待对端回执的 UI 从“同步失败”改为“同步确认中” → 验证: 宠物端看板 widget 测试
- [x] 让“重新同步”能重推待确认覆盖快照，而不是只重试失败队列 → 验证: `retrySyncIssues()` 聚焦测试
- [x] 补充低噪声 `PetNoteSync` 诊断日志 → 验证: 测试日志出现 hello 和 pending reset snapshot 关键点
- [x] 验证服务端 legacy relay 回执账本未被破坏 → 验证: `cd server && dart test test/sync_flow_test.dart`
- [x] 构建 Android release APK → 验证: `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`
- [x] 安装到两台 Android 设备复测 → 验证: 用户接受清数据后双端卸载重装成功，重新配对并添加宠物后宠物端显示“已连接主人端”和 1 只可服务宠物

### Review 2026-06-22

- 本轮没有发现设备历史 logcat 中残留有效 PetNote 同步异常栈；两台设备 App 均在前台，线上同步服务健康，现有包签名一致但与本机新构建 APK 签名不一致。
- 根因候选收敛到状态展示口径：此前 `pendingResetSnapshotSyncId != null` 会把“等待覆盖快照回执”伪装成“同步失败 / 1 条数据同步失败”。现在 UI 显示为“同步确认中”，弹窗说明“数据已发出，正在等待另一台设备确认收到”。
- “重新同步”按钮现在通过 `SyncService.retrySyncIssues()` 同时覆盖失败队列重试和待确认覆盖快照重推，避免 pending reset 状态只能被动等待。
- 本机验证通过：`flutter analyze lib/sync/sync_service.dart lib/app/petnote_pages.dart test/sync_service_test.dart test/pet_device_dashboard_test.dart`；聚焦同步状态/重试/widget 测试；`cd server && dart test test/sync_flow_test.dart`；Android release APK 构建成功，SHA256 `95e03bfb66dcc6fbcbd6aa1933b04fbc3817b85d7b35423f111f4e16e33f1fc7`。
- 真机复测更新：用户接受清数据后，两台 Android 均已卸载旧包并安装新 APK；重新配对和添加宠物后，`127.0.0.1:5575` 宠物端 UI 显示“已连接主人端”“1 只可服务”以及同步过来的宠物“对对对 / 安哥拉兔”。当前 logcat 未发现 PetNote 崩溃、WebSocket 失败或同步异常栈；release 包的 Dart `debugPrint` 未落到应用进程 logcat，因此本轮只能用 UI 状态证明数据已同步，不能从 logcat 取得细粒度 `PetNoteSync` 握手行。

## 2026-06-22 宠物时间刷新与同步稳定性审查

- [x] 定位列表页和详情页时间派生数据不自动刷新的根因 → 验证: 找到页面生命周期和 store 刷新链路证据
- [x] 修复页面常驻时的时间刷新租约，不改动同步业务代码 → 验证: 清单列表页和详情页 widget 测试
- [x] 审阅当前同步协议、客户端、服务端、outbox 和测试覆盖 → 验证: 源码路径与风险点可追溯
- [x] 调研成熟同步方案和最佳实践 → 验证: 使用官方文档/仓库资料形成对比
- [x] 输出同步稳定性报告 → 验证: 报告包含问题分析、优化建议、第三方方案评估

### Review 2026-06-22

- 宠物端中枢页此前只在 build 时读取 `DateTime.now()`，页面常驻时没有自身定时刷新；主人端 `PetNoteStore` 已有分钟级派生数据刷新，因此本轮只给 `PetDeviceDashboard` 增加页面级分钟时钟租约，并覆盖“未选择宠物列表页”和“已进入服务宠物详情页”两种状态。
- 同步稳定性本轮只做审阅与调研，未修改同步业务代码；报告已落盘到 `docs/sync-stability-review-2026-06-22.md`，核心风险集中在内存失败队列、三套同步链路并存、服务端单 JSON 文件持久化、离线设备拖住回执剪枝、附件/队列缺少背压和握手门禁不足。
- 第三方方案调研使用官方文档为依据，建议短期加固现有协议，中期引入 durable operation log/server sequence，长期优先 spike PowerSync，其次评估 Couchbase Lite + Sync Gateway。

- [x] 复核 README 中同步服务、RTC Token、三端 SDK 和验证边界
- [x] 梳理 App 更新后数据同步链路：启动、服务器发现、配对身份、outbox、WebSocket、服务端持久化和回执清理
- [x] 梳理远程视频链路：入口、呼叫信令、RTC Token、平台桥接、权限、频道加入、远端音视频订阅和渲染
- [x] 对照测试与实现，找出能解释“更新后无法同步”和“看不到/听不到对方”的根因候选
- [x] 运行最小相关测试，区分已验证事实、未复现边界和需要真机/服务器验证的项
- [x] 输出修复方案：最小代码改动、服务端部署动作、验证命令和风险边界
- [x] 本地修复服务端旧设备 token 兼容测试口径 → 验证: `cd server && dart test test/server_app_test.dart test/sync_flow_test.dart`
- [x] 本地修复远程视频测试隔离与 Token 期望 → 验证: `flutter test test/remote_video_entry_test.dart test/rtc_token_client_test.dart`
- [x] 检查并清理测试产生的 lockfile 噪音 → 验证: `git status --short`
- [x] 针对“两端本地画面正常但无远端音视频”补充 RTC 原生桥接诊断点 → 验证: 三端结构测试覆盖 join 回调、错误回调、远端首包/首帧与订阅返回码
- [x] 构建 Android Actions-like arm64 APK 供真机复测 → 验证: `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`
- [x] 清理构建副作用并记录真机日志采集口径 → 验证: `git status --short`
- [x] 真机复现“通话不可用/无远端音视频”状态并采集两台 Android 设备日志/UI 状态 → 验证: `adb logcat` + `dumpsys package`
- [x] 定位“通话不可用/无远端音视频”的客户端判定分支，区分角色未激活、同步未连接、Token 失败或 RTC bridge 失败 → 验证: 源码路径 + 设备日志互证
- [x] 输出当前根因与下一步修复/操作方案 → 验证: 可复核命令与边界说明
- [x] 按官方 ARTC 单 Token 鉴权路径修正服务端签名串与三端入会参数 → 验证: server/unit + 三端结构测试
- [x] 构建修复后的 Android arm64 APK 供真机复测 → 验证: `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`
- [x] 为“通话不可用/连接失败”补充 Dart 侧真机诊断日志 → 验证: 相关 Flutter 测试 + 两台 Android logcat
- [x] 修复服务端设备 role 持久化链路，避免宠物端离线/重连后目录退化为 `unknown` → 验证: server pairing/sync flow 测试
- [x] 用两台 Android 真机重新验证当前线上失败点 → 验证: 双端 UI 状态 + `adb logcat`
- [x] 修复 Android RTC 入会状态机，避免异步入会失败时 UI 误显示“已连接” → 验证: Android 结构测试 + 双端真机复测
- [x] 定位主人端视频页 5 秒后闪退根因 → 验证: 主人端完整 logcat/tombstone 与服务端 `/rtc/token` 日志互证
- [x] 修复 Android RTC 入会失败后的释放竞态 → 验证: 结构测试覆盖失败清理且避免立即 `destroy()`
- [x] 修复并部署服务端 ARTC 单 Token 签名格式 → 验证: server token 测试通过，服务器容器重建后 `/healthz` 200
- [x] 修复默认 RTC channelId 超过阿里云 64 字符限制 → 验证: 默认 callId 短于 64 且双方信令/Token 使用同一值
- [x] 构建并安装 Android arm64 APK 到两台真机复测 → 验证: 双端 APK hash 一致，主人端不再 native crash
- [x] 验证 Android 四参数显式入会形态 → 验证: `joinChannel(singleToken, channelId, userId, "")` 后仍返回 `33620485 / 401 auth invalid`
- [ ] 验证 Android 官方 AuthInfo 入会形态 → 验证: `joinChannel(authInfo, "")` 构建安装后双端日志出现 `onJoinChannelResult result=0` 或保留 401 证据继续核查签名算法/SDK 版本

## Review

- README 约定同步服务更新必须在仓库根目录执行 `docker compose -f server/docker-compose.yml up -d --build`，只 `git pull` 或只重启旧容器不能保证 `server/` 与 `packages/petnote_sync_protocol/` 新协议进入镜像。
- 公网探测结果：`https://petnote-server.juren233.top/server` 返回 `wss://petnote.juren233.top/ws`；`https://petnote.juren233.top/healthz` 返回 `ok`；`POST https://petnote.juren233.top/rtc/token` 使用伪造 household/auth 返回 `401 unauthorized`，说明线上服务和 RTC Token 路由已存在，且已走到家庭认证校验，不是 503 未配置状态。
- 同步链路根因候选：App 更新引入 `householdAuthToken`、安全密钥兜底、旧家庭组导入和未回执事件账本；若线上服务镜像未重建或旧设备缺 token 的兼容策略与服务端版本不一致，会在 hello 阶段得到 `auth failed` / `unknown household`，客户端 `SyncService` 随即 stop 并只暴露失败计数。
- 服务端测试存在口径冲突：`server_app_test.dart` 期望“已有 household 的 hello 缺少 token 会拒绝”，但 `sync_flow_test.dart` 与客户端测试期望旧版已登记设备缺 token 时 `hello_ack` 补发 token。这不是单纯测试红，而是升级兼容策略需要定稿。
- RTC 链路根因候选：通话必须双方使用同一个 `callId` 作为 ARTC `channelId`；被叫端当前从 `RtcCallInvite.callId` 传入 `RemoteVideoCallPage`，代码路径正确。若线上/设备运行的不是这版代码，或宠物端未收到 invite 而手动另开通话页，会进入不同频道，表现为双方无画无声。
- Android、iOS、Harmony 原生桥均存在真实 ARTC SDK 接入、权限、平台视图、publish/subscribe 代码；模拟器/iOS simulator 不支持真实 RTC。真机仍需用两台已配对设备验证。
- 相关最小测试运行结果：`flutter test test/sync_service_test.dart test/remote_video_entry_test.dart test/rtc_signaling_controller_test.dart test/rtc_token_client_test.dart test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart` 失败 3 项，失败集中在 `remote_video_entry_test.dart` 全局 `SyncService.instance` 污染和测试期望未更新；`dart test test/server_app_test.dart test/sync_flow_test.dart` 失败 1 项，失败为旧客户端缺 token 兼容策略冲突。
- 2026-06-19 复核：`curl https://petnote-server.juren233.top/server` 返回 `updated_at=2026-06-19T08:18:51.776Z` 与 `wss://petnote.juren233.top/ws`；`curl -i https://petnote.juren233.top/healthz` 返回 HTTP 200 `ok`；伪造身份请求 `/rtc/token` 返回 HTTP 401，说明 token 服务走到 household/auth 校验，线上不是“RTC 未配置”。
- 2026-06-19 复核：`flutter test test/remote_video_entry_test.dart test/rtc_token_client_test.dart` 失败 3 项，均为远程视频测试基线问题：缺依赖时页面显示不可用导致找不到远端视图、未成功入会时挂断不发 `call_end`、Token 请求现在应携带 `householdId/authToken`。这些失败会掩盖真实 RTC 回归，需要先修测试隔离和期望。
- 2026-06-19 复核：`cd server && dart test test/server_app_test.dart test/sync_flow_test.dart` 失败 1 项，`server_app_test.dart` 的“缺 token 拒绝”与 `sync_flow_test.dart` 的旧版已登记设备恢复策略直接冲突。建议定稿为：已登记旧设备缺 token 允许 `hello_ack` 补发 token；未知设备/错误 token/空新服务器无 token 继续拒绝。
- 修复方案建议：先按 README 在服务器根目录执行 `docker compose -f server/docker-compose.yml up -d --build` 并备份 `petnote-data` volume；再修正服务端兼容测试口径；再修正远程视频测试隔离和 Token 期望；最后用两台真机验证同一 household、同一 `callId/channelId`、双方 `userId` 均已登记且远端音视频轨道实际出现。
- 2026-06-19 本地修复：`server_app_test.dart` 已改为验证旧版已登记设备缺 token 时由 `hello_ack` 补发 token，安全边界仍由 `sync_flow_test.dart` 覆盖错误 token、陌生设备和空新服务器无 token 拒绝。
- 2026-06-19 本地修复：`remote_video_entry_test.dart` 增加全局清理 `SyncService.instance`，并给“只连当前宠物设备”和“挂断发送 call_end”测试显式注入 fake token/signaling/adapter，避免测试依赖残留单例或缺依赖状态。
- 2026-06-19 验证：`flutter test test/remote_video_entry_test.dart test/rtc_token_client_test.dart` 通过，24/24 pass；`cd server && dart test test/server_app_test.dart test/sync_flow_test.dart` 通过，42/42 pass。测试解析产生的 `pubspec.lock` 与 `server/pubspec.lock` 噪音已还原。
- 2026-06-19 新现象：两台真机可以建立通话并显示自己的本地画面，但看不到/听不到对方。该现象说明登录、信令、页面入口、本地权限和本地预览大概率已通，故障重点收敛到 ARTC 异步入会结果、远端用户/track 回调、远端订阅、远端渲染或 Token/channel/userId 不匹配。
- 2026-06-19 SDK 证据：iOS 和 Harmony 头文件均说明 `joinChannel` 是异步接口，真正成功/失败要看 `onJoinChannelResult` / `onJoinChannel`；当前 iOS join callback 为空，Android/Harmony 也缺少足够日志，导致真机 UI 的“已连接”不能证明 RTC 媒体面真正入会成功。
- 2026-06-19 本地改动：Android/iOS/Harmony 原生 RTC 桥均补充 `PetNoteRtc` / `PetNoteRtcPlugin` 诊断日志，覆盖 join 同步返回、异步入会结果、SDK error、远端用户上线、远端 track 可用、远端音视频首包/首帧、publish/subscribe/setRemoteViewConfig 返回码。未修改服务端接口、RTC Token 接口或 Dart 业务协议。
- 2026-06-19 Android 复测包：`build/app/outputs/flutter-apk/app-release.apk`，README/Actions-like 命令产出，大小 `55.0MB`（`ls -lh` 显示 52M），SHA256 `66630131d49d037ec8e4f956e1ddcaa1890e9ae88d8e69e4ad270c6a9e040c1b`。
- 2026-06-19 验证：`flutter test test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart` 通过，3/3 pass；`flutter test test/remote_video_entry_test.dart test/rtc_token_client_test.dart test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart` 通过，27/27 pass；`cd server && dart test test/server_app_test.dart test/sync_flow_test.dart` 通过，42/42 pass；Android release APK 构建通过。
- 2026-06-19 真机日志采集口径：安装新 APK 后，两台 Android 设备同时发起/接听一次通话，用 `adb logcat -s PetNoteRtc` 抓双方日志。若无 `onJoinChannelResult result=0` 或出现 `onOccurError` / `onAuthInfoExpired`，优先查 Token/AppId/channelId/userId/阿里云控制台；若 join=0 但没有 `onRemoteUserOnLineNotify` / `onRemoteTrackAvailableNotify`，优先查双方是否同一 `callId/channelId` 和同一 ARTC AppId；若有 remote track 但无 `onFirstVideoPacketReceived` / `onFirstAudioPacketReceived`，优先查订阅/发布状态；若有首包但无 `onFirstRemoteVideoFrameDrawn`，优先查远端渲染 view 绑定。
- 2026-06-19 真机 RCA：两台 Android 设备均安装 `com.krustykrab.petnote` `1.4.0-beta.17+39`，相机/麦克风权限已授权。有效通话日志显示信令和页面自动进入正常，双方 `joinChannel` 同步返回 `0`，但异步 `onJoinChannelResult result=33620485`，随后 `onOccurError error=33620485 message=gslb_code=0,roomserver_code=401,room_server_desc=auth invalid,`。因此当前无远端画面/声音的直接根因不是 UI、权限、配对或本地预览，而是 ARTC 媒体面鉴权失败。
- 2026-06-19 本地修复：`server/lib/src/rtc_token_service.dart` 的签名串从 `appId + appKey + channelId + userId + nonce + timestamp` 收敛为官方 ARTC Token 字段 `appId + appKey + channelId + userId + timestamp`；保留响应里的 `nonce` 字段作为兼容/可观测信息，但不再参与 ARTC 鉴权签名。
- 2026-06-19 本地修复：Android `joinChannel`、iOS `joinChannel`、Harmony `joinChannelWithToken` 均改为单 Token 入会路径，让 SDK 从 `singleToken` 解出 `channelId/userId`，避免 `singleToken` 与额外 channel/user 参数不一致时被服务端判 `auth invalid`。未改变 `/rtc/token` 路由、请求体或响应字段名。
- 2026-06-19 验证：`cd server && dart test test/rtc_token_service_test.dart test/server_app_test.dart` 通过，13/13 pass；`flutter test test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart test/rtc_token_client_test.dart` 通过，9/9 pass。`flutter test` 产生的 `pubspec.lock` / `server/pubspec.lock` 依赖解析噪音已恢复。
- 2026-06-19 Android 修复包：`build/app/outputs/flutter-apk/app-release.apk`，README/Actions-like 命令产出，大小 `55.0MB`（`ls -lh` 显示 52M），SHA256 `8d40f2ef83cee7f5c1d5db82d4807385821c53614f8d51f11d3fa67fe95caf3e`。构建产生的 `android/gradle.properties` 和根 `pubspec.lock` 工具链噪音已恢复。
- 2026-06-19 复测现象：服务端更新后，发起端页面直接显示“通话不可用”，且 logcat 未出现新的 `PetNoteRtc` native 入会日志。源码确认该状态发生在 `RemoteVideoCallPage._startRtc()` 的前置条件分支，说明当前还没进入阿里云 RTC 入会阶段，需要先定位 `tokenClient/userId/targetDeviceId/signalingController` 哪一项为空。
- 2026-06-19 纠偏：不能把单端日志或手机端页面状态包装成“双机测试成功”。重新验证时，两台 Android 均安装 `1.4.0-beta.17+39`，手机在爱宠页发起，平板实际在 PetNote 宠物端首页并显示“已连接”。
- 2026-06-19 真机证据：手机发起远程视频后页面显示“连接失败”，平板未进入被叫页；手机 logcat 输出 `[PetNoteRemoteVideo] start failed: Bad state: rtc token request failed: 503 rtc not configured`，栈落在 `RtcTokenClient.issueToken`，且无 `PetNoteRtc` 原生入会日志。公网 curl 复核 `https://petnote.juren233.top/healthz` 返回 200 `ok`，但 `POST https://petnote.juren233.top/rtc/token` 返回 503 `rtc not configured`。
- 2026-06-19 根因更新：当前线上通话失败的直接原因是同步服务容器没有拿到 `ALICLOUD_RTC_APP_ID` / `ALICLOUD_RTC_APP_KEY`，或更新时未带这些环境变量重建/重启；健康检查只能证明端口可用，不能证明 RTC Token 服务已配置。
- 2026-06-19 本地修复：服务端设备 `role` 已补全持久化，覆盖 `pairCreate`、`pairJoin`、`hello` 恢复和设备列表输出。关键 bug 是 `pairJoin` 里曾在 `_sessionRole` 赋值前写入设备 role，导致新配对宠物端 role 持久化为空，离线/重连目录可能退化为 `unknown`。
- 2026-06-19 验证：`flutter test test/remote_video_entry_test.dart test/rtc_token_client_test.dart` 通过，25/25 pass；`cd server && dart test test/server_app_test.dart test/sync_flow_test.dart test/pairing_test.dart` 通过，48/48 pass；`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons` 通过并安装到两台 Android。当前 APK SHA256 `bde7d454fd5762434631a4fd5b509c614fc29716ea62052c165494bec5bf6925`。
- 2026-06-19 19:32 真机复测：公网 `https://petnote.juren233.top/healthz` 返回 HTTP 200 `ok`，伪造 `/rtc/token` 请求已不再返回 `503 rtc not configured`，说明朋友修复了 RTC 环境变量缺失这一层；两台 Android 均安装 `1.4.0-beta.17+39`，手机从爱宠页发起，平板宠物端自动进入通话页，双方 UI 均显示“阿里云视频通话已连接”。但两端 `PetNoteRtc` 日志仍显示同一频道 `rtc-pet-1-call-1781868749215656-767146564` 下 `joinChannel result=0` 后异步 `onJoinChannelResult result=33620485`，并报 `onOccurError error=33620485 message=gslb_code=0,roomserver_code=401,room_server_desc=auth invalid,`。因此当前不是 UI、权限、配对、信令或本地预览问题，而是 ARTC 媒体面 Token 鉴权仍失败；页面“已连接”文案不能作为成功标准。
- 2026-06-20 00:49 真机复测：两台 Android 在同一频道 `rtc-pet-1-call-1781887744486252-940020936` 入会，服务端对应时间两次 `POST /rtc/token` 均为 200；双端原生同步 `joinChannel/publish/subscribe` 返回 0，但异步 `onJoinChannelResult result=33620485` 与 `roomserver_code=401, auth invalid` 仍复现，继续排除页面、信令、端口、权限和同频道问题。
- 2026-06-20 00:59 Android `AliRtcAuthInfo` 结构体入会实验：第一版修复包双端安装成功后不再走到 401，而是在原生桥接前置校验失败，手机日志显示 `[PetNoteRemoteVideo] start failed: PlatformException(rtc_native_error, missing rtc nonce, null, null)`；原因是服务端当前按官方建议返回空 `nonce`，Android `requireString` 不允许空字符串。已修正为 `requireNullableString(arguments, "nonce")`，并按 SDK 示例使用 `joinChannel(authInfo, "")`。
- 2026-06-20 01:04 Android 修正版实验包已构建并安装到两台设备，APK SHA256 `11c62e338d17fa4c481fc7ca75d461091c0176fc8d8bc9ab83f62a316427b4b2`；等待用户重新打开双端视频通话页后，只做只读日志/截图采集，不再切页面。
- 2026-06-20 01:42 真机复测：双端截图均确认在视频通话页且只显示本地小窗；服务端同时间两次 `/rtc/token` 返回 200；系统窗口显示双端均创建 Flutter/RTC Surface，但 01:42 之后没有新的 `PetNoteRtc join requested` 或 `onJoinChannelResult` 日志。结合此前 401 证据，当前 UI 的“阿里云视频通话已连接”仍不能证明媒体面入会成功，需要先修 Android 原生桥接，等待 `onJoinChannelResult result=0` 后才向 Flutter 返回 join 成功，失败时把 SDK 错误回传给页面。
- 2026-06-20 02:01 Android 入会状态机修复后真机复测：两台设备均安装 APK SHA256 `433ec657435997af3d9a8a3b8eb34ab10300b4797e7dcd22bfe57002af582d6e`。手机端日志显示 `joinChannel result=0` 后异步 `onJoinChannelResult result=33620485`，Flutter 收到 `PlatformException(rtc_join_failed, join rtc channel failed asynchronously: 33620485 ...)` 并显示连接失败，随后 SDK 明确报 `roomserver_code=401, room_server_desc=auth invalid`。这证明 UI 假连接已修复；当前剩余根因仍是阿里云 RTC Token/AppID/AppKey 鉴权不被 roomserver 接受。
- 2026-06-20 02:42 真机日志更新：服务端 `/rtc/token` 返回 200，客户端已进入 `PetNoteRtc.joinChannel`，但新频道 `rtc-pet-merge-device-hjmmyxpp95-lauugj-pet-1-call-1781894567218074-814969914` 长度为 76，超过阿里云 RTC 常见 ChannelID 上限 64。该线索能解释服务端签发成功但 roomserver 仍返回 `33620485 / 401 auth invalid`，需把默认 `callId/channelId` 改短，不能再拼接可能被数据合并扩长的 `pet.id`。
- 2026-06-20 03:01 真机只读复核：两台 Android 均仍运行 `1.4.0-beta.17+39`，进程存活且当前窗口为 `com.krustykrab.petnote/.MainActivity`；服务端最近 `/rtc/token` 返回 HTTP 200。该轮 logcat 未筛到新的 `PetNoteRtc` 入会日志，无法证明本次页面失败已进入原生 RTC，下一步用 Android 四参数显式入会做单变量实验。
- 2026-06-20 03:12 四参数显式入会实验：两台 Android 安装同一 APK SHA256 `53de478b8ad5c095e73ab02135a196d084b57970593b516a6cab98047b887432`；主人端短频道 `rtc-c-hjmnvem67o-l07t` 下 `joinChannel(singleToken, channelId, userId, "")` 同步返回 0，但异步仍 `onJoinChannelResult result=33620485`，并报 `roomserver_code=401, room_server_desc=auth invalid`。因此问题不是 Android V2 入会参数未显式传递 channel/user。

## 2026-06-20 RTC 3.0 Token 收敛计划

- [ ] 按阿里云 3.0 单参数 Token 文档修正服务端签名串：nonce 不参与签名且响应 nonce 为空 → 验证: server token/app 测试
- [ ] Android 回到官方推荐单参数 Base64 Token 入会，避免 AuthInfo 多参兼容歧义 → 验证: Android 结构测试 + release 构建
- [ ] 安装两台 Android 真机复测并抓双端 logcat/服务端日志 → 验证: `onJoinChannelResult result=0` 或保留新的失败证据

## 2026-06-20 官方 DingRTC Demo 对照验证

- [x] 检查官方 Demo 依赖与 SDK 来源，不把 AppKey 写入 PetNote 仓库 → 验证: 临时 Demo 使用阿里云 Maven `com.ding.rtc:dingrtc-basic:3.9.0` 构建成功
- [x] 构建并安装官方 Android Demo 到两台真机 → 验证: `:app:assembleDebug` 成功，APK SHA256 `4b8830f12fb77e5d7bc8701d738c0fe686462d6043ae92fc693ade4b9592482e`
- [x] 双端加入同一官方 Demo 频道并抓取日志 → 验证: 手机端出现 `onJoinChannelResult, result=0`，随后收到平板远端上线、音视频轨道、订阅返回 0 和远端首帧渲染
- [x] 补齐官方 iOS DingRTC Demo SDK 与临时 token，不把 AppKey/token 写入 PetNote 仓库 → 验证: `DingRTC.xcframework` 放在外部 Demo `iOS/SDK`，`xcodebuild ... DEVELOPMENT_TEAM=G9CUU32QMD PRODUCT_BUNDLE_IDENTIFIER=com.krustykrab.dingrtcdemo IPHONEOS_DEPLOYMENT_TARGET=15.0 build` 成功
- [x] 安装并启动官方 iOS DingRTC Demo 抓 console 日志 → 验证: iPhone 端先因新 App 网络权限被系统拦截报 `Denied over Wi-Fi interface`，允许网络后重启出现 `Join channel successfully.`
- [x] 官方 iOS Demo 与官方 Android Demo 跨端互通验证 → 验证: iOS 端频道 `ios-demo-0620` 用户 `ios-demo-1`，Android 平板用户 `android-demo-1`；iOS 日志出现 `User android-demo-1 join channel`、`start audio`、`start video`、`unmute audio/video`，Android UI 层同时显示 `ios-demo-1` 和 `android-demo-1`

## 2026-06-20 Android DingRTC 3.x 迁移计划

- [ ] 替换 Android RTC SDK 依赖：移除 `com.aliyun.aio:AliVCSDK_ARTC:7.11.0`，改用官方 Demo 已验证的 `com.ding.rtc:dingrtc-basic:3.9.0` → 验证: Gradle 能解析阿里云 Maven 依赖且 Android 结构测试更新通过
- [ ] 按官方 Demo 重写 Android `PetNoteRtcBridge` 的 SDK 层：`DingRtcEngine.create`、`DingRtcAuthInfo(appId/channelId/userId/token)`、`joinChannel(authInfo, userName)`、异步 `onJoinChannelResult` 后再向 Flutter 返回成功 → 验证: 结构测试覆盖 `com.ding.rtc.*`、`DingRtcAuthInfo`、`joinChannel(authInfo, userName)`，且不再出现 `com.alivc.rtc.*`
- [ ] 迁移本地预览、远端渲染和订阅发布：使用 DingRTC 的 `createRenderSurfaceView`、`setLocalViewConfig`、`setRemoteViewConfig`、`publishLocalAudioStream/VideoStream`、`subscribeRemoteVideoStream`，保持 Flutter `petnote/rtc` 和 `petnote/rtc_video_view` 接口不变 → 验证: Dart 层无需改页面调用，Android 桥接结构测试覆盖远端上线、远端 track、订阅返回码和首帧日志
- [ ] 保留并校准服务端 AppToken：以官方 Demo 成功的 TokenGenerator 为对照，确认 `server/lib/src/rtc_token_service.dart` 生成的 `singleToken` 与 DingRTC 3.x 结构一致 → 验证: server token 测试通过，必要时新增“DingRTC 3 token starts with 000 and decodes/zlib body shape”测试
- [ ] 构建 Android arm64 release APK 并安装到两台真机 → 验证: `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons` 成功，双端安装同一 APK SHA256
- [ ] 双端 PetNote 真实通话验收 → 验证: `adb logcat -s PetNoteRtc` 同时出现 `onJoinChannelResult result=0`、远端用户上线、远端音频/视频 track、订阅返回 0、远端首帧；UI 不再显示“连接失败”，且能看到/听到对方
- [ ] 收尾清理与提交边界检查 → 验证: 不提交临时官方 Demo、AppKey、APK、Gradle/lockfile 噪音；`git status --short` 中只保留本次必要源码/测试/文档变更

## 2026-06-20 iOS 真机 RTC 入会修复

- [x] 抓取 Ebato 的 iPhone 真机 console 日志 → 验证: `joinChannel result=-1`，随后 `onJoinChannelResult result=16974081 channel= userId=`，说明 iOS 原生层已进入 RTC 但入会参数未被 SDK 接受
- [x] 对照 `AliRtcEngine.h` 修正 iOS 入会参数 → 验证: `joinChannel(singleToken, channelId: channelId, userId: userId, ...)` 显式传入与 token 生成一致的频道和用户
- [x] 更新 iOS RTC 结构测试 → 验证: `flutter test test/ios_rtc_permission_structure_test.dart` 通过
- [x] 构建未签名 iOS release IPA → 验证: `flutter build ios --release --no-codesign` 通过，`build/ios/Runner-unsigned.ipa` SHA256 `2c11adc0e06bfd804e850c8b1b545474a57cbba495d66525a64b13beeb008ffe`
- [x] 拉取 iOS 真机 crash report 并定位闪退根因 → 验证: `Runner-2026-06-20-131044.ips` 主线程卡在 `PetNoteRtcPlugin.releaseEngine()` → `AliRTCSdk::AliEngine::Destroy(...)`，并伴随 `A-Eng-3` 线程 `EXC_BAD_ACCESS`
- [x] 修复 iOS RTC 释放路径 → 验证: dispose 只执行 `stopPreview`、解绑本地/远端 view、`leaveChannel`，不再同步调用 `AliRtcEngine.destroy()`
- [x] 重新构建未签名 iOS release IPA → 验证: `flutter test test/ios_rtc_permission_structure_test.dart` 通过，`flutter build ios --release --no-codesign` 通过，`build/ios/Runner-unsigned.ipa` SHA256 `c410b44ef3709ea01eb0ae3c07c723163905a6ec0ddc09cb6859f79e557334f2`

## 2026-06-20 Android CI Linux Runner 迁移

- [x] 将 Release workflow 的 Android job 从 `windows-latest` 切到 `ubuntu-latest`，并用 bash 写入 `android/local.properties` → 验证: workflow 静态检查通过
- [x] Android signing 改用现有 `scripts/prepare-android-signing.sh`，保持 GitHub Secrets 和 Gradle 签名协议不变 → 验证: Actions 中 `Prepare Android Signing` 成功
- [x] Android APK 构建改为 Linux 上直接执行 `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons` → 验证: Actions 生成 `apk-arm64-v8a`
- [x] 推送后对比 Linux runner 实际耗时与上一轮 Windows runner `11m1s` → 验证: Linux runner Android job `7m50s`
- [x] 修复 GitHub Actions 外显 beta 版本号自动递增 → 验证: workflow 嵌入解析脚本在 `GITHUB_RUN_NUMBER=130` 时输出 `version_core=1.4.0-beta.19` / `tag=v1.4.0-beta.19`
- [x] 同步新的 Release 版本/构建号规范到 workflow 教程并补正并发控制位置 → 验证: workflow YAML 解析通过，教程不再引用 run number offset / git commit count 旧规则

## 2026-06-20 iOS / Harmony RTC 复用与构建验收

- [x] 删除 Android CI 临时测试分支 → 验证: 本地和远端均无 `codex/android-ci-linux-runner`
- [x] 对比 Android 已验证 DingRTC 3.x 桥接与 iOS/Harmony 当前 RTC 实现，明确哪些可复用、哪些必须平台专用 → 验证: iOS/Harmony 复用异步入会状态机，不直接复用 Android DingRTC SDK；结构测试覆盖 pending join、timeout、错误回传
- [x] 使用 macOS DevEco CLI 链路构建 Harmony x64 HAP → 验证: `ohpm install --all` 成功；DevEco `hvigor.js assembleHap -p product=default -p buildMode=debug --no-daemon` 通过 ArkTS/PackageHap 并产出 unsigned HAP，签名阶段因共享基线缺本地证书失败
- [x] 安装 Harmony HAP 到已启动虚拟机 → 验证: 本地 `hap-sign-tool.jar` 签出 `entry-default-signed.hap`，`hdc -t 127.0.0.1:5555 install -r ...` 成功，`aa start -a EntryAbility -b com.krustykrab.petnote` 成功
- [x] 构建 iOS 未签名 IPA → 验证: `flutter build ios --release --no-codesign` 成功并产出 `build/ios/Runner-unsigned.ipa`，SHA256 `f9fe423646bccdf6af9718a395eedd8789d1b8741f47515f555cf2e5fad23cf3`
- [x] 清理构建残留和进程 → 验证: 无 Gradle/Kotlin/Flutter 测试构建残留；仅有常驻 `xcodebuildmcp` 工具服务；git 噪音限于本次 RTC 源码/测试/任务记录

### Review

- Android 已验证 DingRTC 3.x 的 SDK 层不能直接复制到 iOS/Harmony：iOS 仍是 `AliVCSDK_ARTC 7.11.0`，Harmony 仍是 `@aliyun_video_cloud/alivcsdk_artc 6.11.0-beta`。本轮复用的是“异步入会回调成功后才向 Flutter 返回成功、失败/超时回传错误、成功后再发布/订阅”的状态机。
- Harmony 构建实测发现 README 的 macOS `hvigorw` 命令与当前仓库实际入口不完全一致：`ohos/` 没有 Unix `hvigorw`，本机可用 DevEco 自带 node 执行 `tools/hvigor/hvigor/bin/hvigor.js`。如果这次结论会影响后续协作，是否同时补充到 README？
- Harmony unsigned HAP SHA256: `26ac5b5ef3395e0f6413df53b35bb599e5ffe89eb4bfdc38f5d2093b83e5d439`；本地签出的 signed HAP SHA256: `ff07971321742defeff3f0129eb2c11328c54dde90ff6f1fd7788487dc05ce7d`。

## 2026-06-20 iOS 主人端 RTC 连接失败复测

- [x] 抓取 iPhone 主人端控制台日志 → 验证: `devicectl --console` 下复现连接失败，日志显示 `joinChannel result=-1`，随后 `onJoinChannelResult result=16974081 channel= userId=`
- [x] 对照 iOS `AliRtcEngine.h` 改为 `AliRtcAuthInfo` 入会 → 验证: `AliRtcAuthInfo` 需要 `appId/channelId/userId/nonce/token/timestamp`；iOS 桥接改用 `joinChannel(authInfo, name:onResultWithUserId:)`
- [x] 更新 iOS 结构测试 → 验证: 防止退回 `joinChannel(singleToken...)`
- [x] 构建新版 iOS 未签名 IPA → 验证: `flutter build ios --release --no-codesign` 通过，`build/ios/Runner-unsigned.ipa` SHA256 `d2c6479f8bf924e605d30a49edefa58060d8cdbcfb7642235f24fc504ab23f49`
- [ ] 安装新版 IPA 到 Ebato 的 iPhone 后复测 → 验证: `joinChannel result=0` 且异步 `onJoinChannelResult result=0`，或保留新的错误码继续核查

### Review

- 这次 iOS 主人端失败不是同步、信令、权限或 Token 请求前置失败；日志已经进入原生 RTC，并打印出非空 `channelId/userId/remoteUserId`。
- 直接根因是 iOS 端使用 token 字符串重载时 SDK 同步拒绝入会，表现为 `joinChannel result=-1` 和空 channel/user 回调；当前修复切换到 SDK 头文件明确要求字段完整的 `AliRtcAuthInfo` 入会形态。
- 本机无法直接用 `flutter run` 安装调试包到 iPhone，原因是 Apple 账号 `souitou@outlook.com` 登录被拒且缺少 `com.krustykrab.petnote` 开发 provisioning profile；这不是本次 Swift 编译失败。

## 2026-06-20 iOS / Harmony DingRTC 迁移

- [x] 对照官方 DingRTC iOS / Ohos Demo，确认两端最小迁移 API → 验证: iOS 使用 `DingRtcEngine/DingRtcAuthInfo/DingRtcVideoCanvas`，Ohos 使用 `DingRtcSDK.create/AuthInfo/DingRtcVideoView`
- [x] 迁移 iOS 原生桥与 CocoaPods 依赖到 DingRTC → 验证: 结构测试检查 `DingRTC_iOS`、`import DingRTC`、`joinChannel(authInfo)`，并禁止旧 `AliRtc*`
- [x] 迁移 Harmony 原生桥与 OHPM 依赖到 DingRTC → 验证: 结构测试检查 `@dingrtc/dingrtc`、`DingRtcEventListener`、`DingRtcVideoView`，并禁止旧 `@aliyun_video_cloud/alivcsdk_artc`
- [x] 将服务端默认 GSLB 收敛为官方 DingRTC 地址 → 验证: server token 测试期望 `https://gslb.dingrtc.com`
- [x] 运行 Flutter 结构/RTC token 相关测试 → 验证: `flutter test test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart test/rtc_token_client_test.dart test/rtc_adapter_test.dart`，10/10 pass
- [x] 运行 server token 相关测试 → 验证: `cd server && dart test test/rtc_token_service_test.dart test/server_app_test.dart`，14/14 pass
- [x] 执行 iOS 依赖安装与未签名 IPA 构建 → 验证: `cd ios && pod install` 成功安装 `DingRTC_iOS 3.9.38`；`flutter build ios --release --no-codesign` 通过；`build/ios/Runner-unsigned.ipa` SHA256 `38ff86d07062fd9eae5d79ad4deb80521bcd8675e4e5fb8647e92b5b41d26610`
- [x] 执行 Harmony OHPM / DevEco CLI 构建 → 验证: `ohpm install --all` 成功拉取 `@dingrtc/dingrtc 3.5.0`；DevEco `hvigor.js assembleHap ...` 通过 `CompileArkTS` 与 `PackageHap`，签名阶段因本机缺 `./sign/OpenHarmony.p12` 失败；unsigned HAP SHA256 `59547c836583d02d61b42ed041e81f459965a58c68a6d67ad33f5104f0eccd50`
- [x] 清理构建残留与 lockfile 噪音 → 验证: `git status --short --untracked-files=all` 只保留必要源码、测试和任务记录；无 Flutter/Gradle/Java/hvigor 构建残留进程，只有常驻 `xcodebuildmcp` 工具服务

### Review

- iOS 已从 `AliVCSDK_ARTC` 迁移到 `DingRTC_iOS 3.9.38`，原生桥改用 `DingRtcEngine`、`DingRtcAuthInfo`、`DingRtcVideoCanvas`、`joinChannel(authInfo, name:)`，并继续保留“异步入会成功后才向 Flutter 返回成功”的状态机。
- Harmony 已从 `@aliyun_video_cloud/alivcsdk_artc` 迁移到 `@dingrtc/dingrtc 3.5.0`，平台视图内部改用官方 `DingRtcVideoView(canvasId)` 与 `RtcEngineVideoCanvas.xComponentId`，不再使用旧 `AliRtcXComponentController`。
- DingRTC OHOS bytecode HAR 要求 project-level `useNormalizedOHMUrl=true`，已按官方 Ohos Demo 的 product-level `buildOption.strictMode` 方式补入 [ohos/build-profile.json5](../ohos/build-profile.json5)。这次结论是否需要补充进 README，避免后续重复踩坑？
- Harmony 当前构建失败只剩签名材料缺失：`Invalid storeFile value ... ./sign/OpenHarmony.p12`。这属于 README 已记录的本机/共享签名边界，不是 DingRTC ArkTS 编译失败。

## 2026-06-20 设备配对成功提示样式替换

- [x] 复用现有 `PageFeedbackBanner` 成功态替换设备配对成功默认 `SnackBar` → 验证: 配对成功时出现浅绿横幅且无 `SnackBar`
- [x] 更新设备页配对成功 widget 测试 → 验证: `test/devices_page_test.dart` 覆盖主人端回调与输入配对码加入路径
- [x] 运行聚焦 Flutter 测试并检查本地噪音 → 验证: `flutter test test/devices_page_test.dart` + `git status --short`

### Review

- 设备页两处配对成功路径已从默认 `SnackBar` 改为复用 `PageFeedbackBanner` 成功态：主人端生成配对码后对端加入显示 `客厅平板 已配对 ✓`，输入配对码加入显示 `配对成功`；错误提示和保存服务器地址提示仍沿用原有 `SnackBar`。
- 验证通过：`flutter test test/devices_page_test.dart --plain-name '配对成功回调只关闭配对码弹窗而不退出设备页'`；`flutter test test/devices_page_test.dart --plain-name '主人端可通过已配对列表入口输入配对码'`。两条路径均断言无 `SnackBar` 且有 `devices_feedback_banner`。
- 全量 `flutter test test/devices_page_test.dart` 仍被既有同步重绑用例挡住：`主人端重绑收到宠物端加入后重启同步服务使用新配对配置` 期望 `pendingInitialSyncPolicy == null`，实际为 `SyncDataPolicy.localWins`。该失败不来自本次 UI 样式替换；测试产生的 `pubspec.lock` 版本翻转噪音已恢复。

## 2026-06-20 长按删除卡片三端触觉反馈

- [x] 新增共享 Interaction Haptics 门面并提供 Flutter 降级 → 验证: MethodChannel 单元测试覆盖 ramp/stop/confirm
- [x] 接入爱宠卡片长按生命周期 → 验证: widget 测试覆盖开始、取消、完成触觉调用顺序
- [x] 实现 Android/iOS/Harmony 原生触觉桥 → 验证: 三端结构测试覆盖注册、渐强播放、停止和确认反馈
- [x] 跑聚焦测试与三端最低构建验证 → 验证: Flutter 测试、Android build、iOS release no-codesign、Harmony CompileArkTS/PackageHap

### Review

- 新增 `petnote/interaction_haptics` 统一通道，Dart 侧通过 `InteractionHapticsDriver` 调用 `playDeleteHoldRamp`、`stopDeleteHoldRamp`、`playDeleteConfirmImpact`；原生插件缺失或异常时降级到 Flutter `HapticFeedback`，不阻塞删除 UI。
- Android 使用 `VibrationEffect` primitive composition，降级到 amplitude waveform / one-shot；iOS 使用 Core Haptics continuous intensity curve + transient confirm，并保留 `UIImpactFeedbackGenerator` fallback；Harmony 使用 `@ohos.vibrator` 的递增短振动序列模拟渐强，并声明 `ohos.permission.VIBRATE`。
- 验证通过：`flutter test test/interaction_haptics_test.dart test/interaction_haptics_structure_test.dart test/pets_page_subtitle_test.dart`；`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`；`flutter build ios --release --no-codesign`。
- `flutter build ios --simulator --debug` 未通过，失败点是既有 `DingRTC_iOS` pod 缺 simulator xcframework slice 路径，未进入本次 Swift 触觉插件编译；改用 README 认可的 no-codesign 真机 release 构建验证 Swift 语法。
- Harmony 使用 DevEco hvigor 链路通过 `CompileArkTS` 与 `PackageHap`，最终 `SignHap` 因本机缺 `./sign/OpenHarmony.p12` 失败；这是 README 已记录的签名材料边界，不是本次插件编译失败。

- 二次蓝军审查修正：完成长按时 Dart 侧改为顺序执行 `stopDeleteHoldRamp()` 后再 `playDeleteConfirmImpact()`，避免 stop/confirm fire-and-forget 竞态吞掉确认震动；新增 widget 测试锁定该顺序。
- 二次蓝军审查修正：Android 优先使用覆盖完整长按时长的 amplitude waveform，primitive composition 只作为无 amplitude control 的降级；Harmony 确认震动前只清理待执行 ramp 定时器，不再先调用异步 stopVibration 造成确认震动竞态。
- 二次验证通过：`flutter test test/interaction_haptics_test.dart test/interaction_haptics_structure_test.dart test/pets_page_subtitle_test.dart`；`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`；`flutter build ios --release --no-codesign`；Harmony 仍通过 `CompileArkTS` / `PackageHap` 后停在缺 `./sign/OpenHarmony.p12`。

## 2026-06-21 宠物端家庭中枢 HTML 原型

- [x] 新增独立原型文件 `docs/prototypes/pet-device-hub-preview.html` → 验证: `test -s` 与 `wc -l` 确认文件存在
- [x] 同屏呈现竖屏与横屏两个 mock frame → 验证: `rg` 确认包含 `portrait-frame` / `landscape-frame`
- [x] 延续 PetNote 柔和浅底、白色面板、橙色强调，同时替换黄色便签感 → 验证: 原型使用 `#f8f4ef`、`#f3f4f8`、白色面板与 `#f2a65a` 强调
- [x] 检查小屏响应式不会明显溢出或重叠 → 验证: 原型包含 1120px / 720px 断点，横屏 frame 由 `device-scroll` 承载

### Review

- 已新增纯 HTML/CSS 静态原型，不引入脚本、外链样式或 App 运行依赖；原型同屏展示竖屏与横屏两套宠物端家庭中枢布局。
- 竖屏突出大时间、宠物状态、下一件事和今日待办；横屏使用左侧中枢栏与右侧主观察区，适合平板或家中常驻设备横放。
- 验证通过：`git diff --check -- docs/prototypes/pet-device-hub-preview.html tasks/todo.md`；Node 静态检查确认 doctype、双方向 frame、media query、无外链脚本/样式；标签数量检查确认主要容器闭合匹配。

## 2026-06-21 宠物端监控屏 HTML 原型简化

- [x] 将原型从信息中枢收敛为监控常亮屏 → 验证: 静态检查确认不再展示完整今日待办列表和多项指标
- [x] 保留竖屏/横屏两种方向 → 验证: 原型仍包含 `portrait-device` / `landscape-device` 两个 mock frame
- [x] 只保留必要信息：宠物身份、连接状态、当前观察状态、下一条关键提醒、设置入口 → 验证: 静态检查确认包含 `正在观察中` 与 `下一次喂食`
- [x] 补充项目经验，避免后续宠物端复用主人端信息密度 → 验证: `tasks/lessons.md` 已增加对应规则

### Review

- 已将原型重做为宠物端监控常亮屏：取消今日待办列表、指标卡、横屏中枢栏和多面板信息堆叠。
- 竖屏保留顶部时间/设置、中间宠物监控状态、底部下一次喂食提醒；横屏保留大面积宠物状态占位、少量同步状态和同一条关键提醒。
- 验证通过：`git diff --check -- docs/prototypes/pet-device-hub-preview.html tasks/todo.md tasks/lessons.md`；Node 静态检查确认双方向、关键监控文案、无待办列表残留、无外链脚本/样式；标签数量检查确认主要容器闭合匹配。

## 2026-06-21 宠物端监控屏比例调整

- [x] 竖屏改为头像状态区约 3、提醒区域约 7 的主体比例 → 验证: CSS 使用 `3fr 7fr` 主体分配
- [x] 横屏头像缩小，并将连接状态放到头像下方 → 验证: 横屏状态 pill 位于头像容器内
- [x] 记录宠物端头像不应占主体空间的经验 → 验证: `tasks/lessons.md` 增加对应规则

### Review

- 竖屏主体增加 `portrait-body`，使用 `3fr / 7fr` 将头像状态区压缩为识别区，把下一次喂食提醒作为主要区域。
- 横屏头像从原先的大占位缩小，并把 `正在观察中` 连接状态移动到头像下方，右侧只保留宠物名称、说明和同步小标签。
- 验证通过：`git diff --check -- docs/prototypes/pet-device-hub-preview.html tasks/todo.md tasks/lessons.md`；Node 静态检查确认 3:7 主体比例、横屏状态位于头像容器、无待办列表残留、无外链脚本/样式；标签数量检查确认主要容器闭合匹配。

## 2026-06-21 横屏待办区域比例修正

- [x] 横屏改为头像+状态区约 3、待办区约 7 → 验证: `wide-monitor` 使用 `3fr 7fr`
- [x] 连接状态保持在头像区域下方，不占用底部 → 验证: 横屏 footer 不再承载状态/待办主体
- [x] 右侧大区域用于待办/下一件事 → 验证: HTML 包含 `wide-todos` 待办主体
- [x] 记录横屏比例经验 → 验证: `tasks/lessons.md` 增加对应规则

### Review

- 横屏已改成左侧头像+连接状态、右侧待办主体的 `3fr / 7fr` 分栏；连接状态保留在头像区域下方，不再占用底部。
- 右侧 `wide-todos` 现在承载下一件事卡片，底部 footer 已移除，设置入口移到横屏顶栏右侧。
- 验证通过：`git diff --check -- docs/prototypes/pet-device-hub-preview.html tasks/todo.md tasks/lessons.md`；Node 静态检查确认横屏 3:7、状态位于头像区域、存在 `wide-todos`、无 `landscape-bottom` / footer 残留、无旧待办列表残留。

## 2026-06-21 宠物端监控屏 Flutter 实现

- [x] 将 `PetDeviceDashboard` 从便签样式改为监控常亮屏样式 → 验证: widget 测试覆盖宠物身份、连接状态、下一件事和完成动作
- [x] 实现竖屏/横屏自适应 3:7 布局 → 验证: widget 测试分别用 portrait / landscape surface 检查关键 key
- [x] 宠物端允许横竖屏、主人端继续锁竖屏 → 验证: 更新系统方向策略和平台结构测试
- [x] 保持同步失败入口与设置入口可用 → 验证: 既有同步失败 widget 测试通过
- [x] 跑聚焦测试和静态检查，确认无 lockfile/平台噪音 → 验证: `flutter test` 相关用例、`flutter analyze`、Android/iOS 构建与 `git status --short`

### Review

- `PetDeviceDashboard` 已按确认后的原型改为宠物端监控常亮屏：竖屏压缩头像身份区、突出下一件事；横屏采用左侧头像+状态、右侧待办主体的约 3:7 分栏。
- 方向策略改为角色驱动：主人端继续调用 `lockAppToPortrait()` 锁竖屏，宠物端调用 `allowPetDeviceOrientations()` 允许竖屏和左右横屏；Android/iOS/Harmony 原生入口改为允许旋转，由 Flutter 按角色收口。
- 验证通过：`flutter test test/pet_device_dashboard_test.dart`；`flutter test test/system_ui_policy_test.dart test/platform_orientation_structure_test.dart test/main_startup_test.dart`；`flutter analyze lib/app/pet_device_dashboard.dart lib/app/petnote_app.dart lib/app/system_ui_policy.dart test/pet_device_dashboard_test.dart test/platform_orientation_structure_test.dart test/system_ui_policy_test.dart test/main_startup_test.dart`。
- 平台构建通过：`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`；`flutter build ios --release --no-codesign`。
- Harmony 本机验证通过 DevEco hvigor 进入 FlutterTask，但 `ohpm` 不在 PATH，导致 `@ohos/flutter_ohos`、`@dingrtc/dingrtc` 等依赖未安装，最终停在 `:entry:default@CompileArkTS`；`pubspec.lock` 的 OHOS SDK 版本翻转噪音已确认没有留下 diff。

## 2026-06-21 宠物端头像同步与横屏修正

- [x] 确认主人端头像图片是否进入同步数据包 → 验证: 检查 `Pet` 模型、图片存储、同步导入导出链路和对应测试
- [x] 宠物端优先显示同步过来的真实头像 → 验证: widget 测试覆盖有头像路径时不再回落到默认图标
- [x] 将“已连接”状态移动到设置按钮左侧 → 验证: 横竖屏 widget 测试确认头像区域不再包含连接 pill
- [x] 修复 Android 横屏左侧黑边，并判断 Harmony 是否同类风险 → 验证: Android native 结构测试覆盖 cutout short edges；Harmony 不套用 Android cutout API
- [x] 跑聚焦测试和构建检查 → 验证: Flutter 测试、analyze、Android release 构建与 `git status --short`

### Review

- 根因确认：同步快照原本只同步 `Pet.photoPath` 字符串，该值是主人端本机绝对路径；宠物端拿到后本机没有对应图片文件，因此 `PetPhotoAvatar` 会回落到默认宠物图标。
- 新增加密头像附件链路：快照密文内携带 `petPhotoAttachments`，宠物 upsert mutation 密文内携带 `petPhotoAttachment`；接收端写入本机 `petnote_synced_pet_photos` 目录，并把 `photoPath` 替换为本机可读路径。旧纯数据快照仍兼容。
- `已连接` 已从头像卡片移到顶部设置按钮左侧，头像/身份卡不再占用空间显示连接 pill；同步失败胶囊仍保留在设置入口旁。
- Android 横屏左侧黑边按 cutout 根因修复：`MainActivity` 在 immersive 系统栏策略里设置 `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`。Harmony 没有 Android display cutout manifest/window 同构机制，本轮不做盲改；它仍依赖现有 `auto_rotation` 与 Flutter edge-to-edge 策略。
- 验证通过：`flutter test test/pet_replica_controller_test.dart`；`flutter test test/pet_device_dashboard_test.dart test/android_native_dock_structure_test.dart`；`flutter analyze lib/sync/sync_photo_attachment.dart lib/sync/multi_device_sync_controller.dart lib/sync/sync_mutation_outbox.dart lib/sync/pet_replica_controller.dart lib/state/petnote_store.dart lib/app/pet_device_dashboard.dart test/pet_replica_controller_test.dart test/pet_device_dashboard_test.dart test/android_native_dock_structure_test.dart`；`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`。

## 2026-06-21 三端视频通话全屏与关摄像头遮罩

- [x] 定位 iOS 视频通话顶部/底部黑区来源 → 验证: 截图现象与 Flutter/iOS RTC 容器代码互证
- [x] 让视频画面铺满整屏，控件仍按安全区避让 → 验证: widget 测试覆盖沉浸系统 UI 与全屏视频容器
- [x] 本地关闭摄像头时显示半透明遮罩和“摄像头已关闭”提示 → 验证: widget 测试覆盖关闭/开启状态
- [x] 主副画面切换时遮罩跟随本地画面，不显示在远端画面 → 验证: widget 测试覆盖点击小窗切换后的遮罩位置
- [x] 补齐 Android 原生 RTC 裁剪填满模式，评估 Harmony 是否需要同类字段 → 验证: Android SDK 枚举反查、Android/Harmony 结构测试
- [x] 跑聚焦测试、Android 构建与 iOS 无签名构建 → 验证: Flutter 测试、结构测试、`flutter build apk`、`flutter build ios --release --no-codesign`

### Review

- 截图里的顶部/底部黑区对应 iOS 系统 overlay 区域和视频渲染没有真正全屏覆盖的问题；通话页进入时改用 `SystemUiMode.immersiveSticky`，控件定位改用 `MediaQuery.viewPaddingOf` 保留刘海/手势区避让。
- iOS DingRTC 本地/远端画布从 `DingRtcRenderMode.fill` 调整为 `DingRtcRenderMode.crop`，并让平台视图容器裁剪且跟随父尺寸，避免视频内容按比例留黑边；Android DingRTC 本地/远端画布也从 `DingRtcRenderModeAuto` 调整为 `DingRtcRenderModeCrop`。
- Harmony 端本轮没有盲写未知 canvas 字段：本地 `@dingrtc/dingrtc` 包未暴露可读类型源码，现有 `DingRtcVideoView` 已设置 `.width('100%').height('100%')`；共享 Flutter 页面层的全屏模式和关摄像头遮罩已覆盖 Harmony。
- 本地视频统一包了一层 `_RtcVideoTile`，只有 `feed == local && cameraEnabled == false` 时显示 50% 黑色遮罩与“摄像头已关闭”；主副画面切换时遮罩自然跟随本地画面，不会显示在远端小窗，Android/iOS/Harmony 共用该逻辑。
- 验证通过：`flutter test test/remote_video_entry_test.dart test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart`；`flutter analyze lib/app/remote_video_call_page.dart test/remote_video_entry_test.dart test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart`；`flutter build ios --release --no-codesign`；`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`。
- 构建产物：`build/ios/iphoneos/Runner.app`，Runner SHA256 `5889a4c42fb2dde574a95a442085eb2d5136f7025103e7765bd7e11836a8938e`；`build/app/outputs/flutter-apk/app-release.apk` SHA256 `0fe404c59a2931370e838ed5a357e3ad95132d18deb10d16d321c6dea8cfa0ee`。
- 构建后检查：`pubspec.lock`、`ios/Podfile.lock`、`android/gradle.properties` 和 `android/app/build.gradle` 无本次构建噪音；无 Flutter/Xcode/Gradle 构建任务残留，只有 Gradle/Kotlin daemon 与常驻 `xcodebuildmcp` 工具服务。

## 2026-06-21 对端关闭摄像头黑屏修复

- [x] 补充 RTC 媒体状态信令，传递摄像头开关状态 → 验证: call model / signaling controller 单元测试
- [x] 本地点击摄像头按钮时发送媒体状态给对端 → 验证: widget 测试检查 `call_media_state` payload
- [x] 远端关闭摄像头时在对应远端画面显示遮罩，不露出黑屏 → 验证: widget 测试覆盖主画面和小窗切换
- [x] 服务端透传新媒体状态信令 → 验证: server sync flow 测试覆盖 `call_media_state`
- [x] 跑聚焦测试、analyze 和平台构建 → 验证: Flutter tests、server tests、Android APK、iOS unsigned IPA

### Review

- 根因是“关闭摄像头”之前只存在本地 UI 状态：本地按钮关闭时能叠遮罩，但对端关闭摄像头后，本机只收到 RTC 黑帧，没有业务状态可判断应该显示“摄像头已关闭”。
- 新增 `call_media_state` 信令，双方入会后和本地摄像头开关变化时发送当前 `cameraEnabled`；服务端按 `targetDeviceId` 透传，客户端收到后更新远端摄像头状态。
- `_RtcVideoTile` 现在按画面来源决定遮罩：本地画面看 `_cameraEnabled`，远端画面看 `_remoteCameraEnabled`。点击小窗切换主副画面时，遮罩跟随对应画面移动，不再把对端关摄像头暴露成黑屏。
- 验证通过：`flutter test test/rtc_call_models_test.dart test/rtc_signaling_controller_test.dart test/remote_video_entry_test.dart test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart`；`cd server && dart test test/sync_flow_test.dart`；`flutter analyze lib/app/remote_video_call_page.dart lib/rtc/rtc_call_models.dart lib/rtc/rtc_signaling_controller.dart test/remote_video_entry_test.dart test/rtc_call_models_test.dart test/rtc_signaling_controller_test.dart`。

## 2026-06-21 远端关摄像头遮罩稳定与 iOS 头像路径迁移

- [x] 重构视频 tile：摄像头关闭时不挂载 RTC 原生 PlatformView，直接渲染统一关闭占位层 → 验证: widget 测试确认主画面/小窗都不存在对应 RTC view 且遮罩仍在
- [x] 强化远端摄像头状态管理：入会后、切换摄像头、应用恢复时同步本端媒体状态，远端状态不因窗口切换丢失 → 验证: widget 测试覆盖切换和恢复
- [x] 补充三端结构测试，防止回退为只依赖平台黑帧或只做本地遮罩 → 验证: Android/iOS/Harmony 结构测试
- [x] 修复 iOS 更新后头像绝对路径失效：引入沙盒照片路径解析和迁移逻辑 → 验证: store/photo widget 单元测试模拟旧绝对路径迁移
- [x] 跑聚焦测试、analyze 和必要构建，记录产物/限制 → 验证: Flutter tests、Android APK、iOS no-codesign

### Review

- 视频黑屏根因不是单纯缺一层 Flutter 遮罩，而是 RTC 画面是三端原生 PlatformView：在 iOS/Android 主副窗口切换后，原生视图层级可能把 Flutter 遮罩压掉。现在 `_RtcVideoTile` 在摄像头关闭时直接不构建 `RtcVideoView`，改为纯 Flutter 的 `摄像头已关闭` 占位层，黑帧没有机会露出。
- 状态管理继续以 `call_media_state` 为准：入会后、本端摄像头开关变化、应用恢复前台时都会同步当前 `cameraEnabled`。远端状态保存在页面 state 中，主画面/小窗切换只移动 feed，不会重置远端关闭状态。
- iOS 头像消失根因是历史 `Pet.photoPath` 存的是沙盒绝对路径；App 更新后如果容器基路径变化，数据库里旧绝对路径不可读，但文件仍在当前 Application Support 的 `pet_photos` 目录。新增 `PetPhotoPathResolver`，加载 store 时仅对不可读且属于 `pet_photos` 的旧路径按当前沙盒目录重定位，并写回本地存储。
- 验证通过：`flutter test test/remote_video_entry_test.dart test/rtc_call_models_test.dart test/rtc_signaling_controller_test.dart test/pet_care_store_test.dart test/native_pet_photo_picker_test.dart`；`flutter test test/android_rtc_bridge_structure_test.dart test/ios_rtc_permission_structure_test.dart test/harmony_rtc_bridge_structure_test.dart test/pet_device_dashboard_test.dart`；`flutter analyze lib/app/remote_video_call_page.dart lib/rtc/rtc_call_models.dart lib/rtc/rtc_signaling_controller.dart lib/platform/pet_photo_path_resolver.dart lib/app/pet_photo_widgets.dart lib/state/petnote_store.dart test/remote_video_entry_test.dart test/pet_care_store_test.dart test/native_pet_photo_picker_test.dart`。
- 构建通过：`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons`；`flutter build ios --release --no-codesign`；未签名 IPA 已重新打包。

## 2026-06-21 宠物端服务对象选择页同化

- [x] 新增宠物选择列表 HTML 预览，先确认横竖屏视觉方向 → 验证: `docs/prototypes/pet-device-selector-preview.html` 可直接打开
- [x] 将配对成功后的宠物选择列表改为 PetNote 家庭中枢风格 → 验证: widget 测试覆盖标题、连接状态、设置入口和宠物卡片
- [x] 选择页支持横竖屏自适应，并保持宠物卡片可点击 → 验证: portrait / landscape surface 测试覆盖对应布局 key
- [x] 选择页显示同步后的真实头像，不回落到文字头像 → 验证: 使用 `debugPetPhotoImageBuilder` 的 widget 测试
- [x] 宠物端设置页加入“返回选择列表”选项 → 验证: 设置页测试确认点击后清空 `servedPetId`
- [x] 跑聚焦测试、format/analyze，确认无无关构建噪音 → 验证: Flutter tests、`dart format`、`flutter analyze`、`git diff --check`

### Review

- 宠物端未选择服务对象时不再使用普通列表页，改为横竖屏自适应的家庭中枢选择界面：竖屏保留顶部状态、柔和提示和宠物卡片列表；横屏使用左侧状态栏与右侧选择区，适合家中常驻设备横放。
- 选择卡片复用 `PetPhotoAvatar(photoPath: pet.photoPath, ...)`，会走现有同步附件和 iOS 头像路径迁移/解析链路；测试用 `debugPetPhotoImageBuilder` 验证同步后的真实头像会被使用。
- 宠物端设置页新增“服务宠物”区块和“返回选择列表”按钮；点击后清空 `servedPetId`，同时清理运行期 `servedPetIdOverride`，避免返回列表后又被旧 override 顶回宠物看板。
- 验证通过：`flutter test test/pet_device_dashboard_test.dart test/pet_device_settings_page_test.dart`；`flutter analyze lib/app/pet_device_dashboard.dart lib/app/pet_device_home.dart lib/app/pet_device_settings_page.dart test/pet_device_dashboard_test.dart test/pet_device_settings_page_test.dart`；`git diff --check`。

## 2026-06-21 宠物端选择页文案清理与横屏修正

- [x] 清理竖屏和横屏选择页说明性/引导性文案 → 验证: widget 测试和 `rg` 确认目标文案无残留
- [x] 将横屏左右比例调整为 3.5:6.5，并修复左侧时间/标题/状态胶囊排版 → 验证: 多尺寸横屏 widget 测试覆盖比例与胶囊边界
- [x] 移除宠物卡片内的箭头符号，释放文案显示空间 → 验证: widget 测试确认无 `chevron_right_rounded` 且卡片仍可点击
- [x] 同步更新 HTML 原型并记录经验 → 验证: 原型静态搜索和 `tasks/lessons.md` 更新
- [x] 跑聚焦测试、format/analyze 和 diff 检查 → 验证: Flutter tests、`dart format --output=none`、`flutter analyze`、`git diff --check`

### Review

- 已删除截图中指定的五处说明性文案：竖屏顶部说明、竖屏底部提示、横屏左侧说明、横屏左侧底部提示、横屏右侧卡片引导。
- 横屏选择页左右区域改为 `35:65`，左侧卡片统一 12px 内边距；时间和“选择服务宠物”使用单行缩放，状态胶囊支持收缩和省略，避免在窄横屏中越界。
- 宠物选择卡片不再显示 `>` / chevron，整张卡片仍作为点击区域；删除箭头后的空间用于宠物名称和品种/年龄文案。
- HTML 原型已同步删除旧文案和箭头，并更新横屏比例与排版参数。

## 2026-06-22 时间实时刷新与 legacy 同步回放修正

- [x] 核实 PowerSync 试验分支是否影响当前 main → 验证: 确认 PowerSync 仍在独立 worktree/分支，main 使用 legacy 同步链路
- [x] 修复宠物列表页与详情页年龄/时间相关文案不实时刷新 → 验证: 页面保持打开时跨分钟 widget 测试
- [x] 修复服务端旧 action 重放可能返回旧状态的问题 → 验证: `server/test/sync_flow_test.dart` 覆盖同一事项新旧操作收敛
- [x] 跑聚焦测试和静态检查 → 验证: Flutter 同步/时间测试、服务端同步流测试、受影响文件 analyze

### Review

- 这次同步变严重的可复现问题在 legacy 服务端 action 去重顺序：旧动作重放时先命中同 kind 已应用动作，绕过了同一事项最新动作判断，可能把 receipt 指回旧 action。
- 服务端现在先构造本次 action payload；只有本次带 `occurredAtMs` 时，才按同一事项最新动作判断是否过期，避免误伤历史无时间戳兼容动作。
- 宠物列表页和宠物详情页新增页面级分钟刷新，并用生日动态计算展示年龄；旧数据生日无法解析或未来日期时仍回退 `pet.ageLabel`。
- 验证通过：`cd server && dart test test/sync_flow_test.dart`；`flutter test test/pets_page_subtitle_test.dart test/owner_sync_engine_test.dart test/pet_replica_controller_test.dart`；`dart analyze lib/src/session_handler.dart`；`flutter analyze lib/app/petnote_pages.dart lib/app/petnote_pages_pets.dart lib/app/petnote_pages_pets_details.dart lib/sync/multi_device_sync_controller.dart test/pets_page_subtitle_test.dart test/owner_sync_engine_test.dart`。

## 2026-06-22 横屏宠物看板空间修正

- [x] 重排已选择服务宠物后的横屏看板：左侧承载时间/设置和头像状态，右侧待办卡片从顶部填充 → 验证: 横屏几何测试覆盖左右区域与设置按钮对齐
- [x] 将连接状态迁入左侧宠物头像卡片底部，并适度增大头像 → 验证: widget 测试确认连接胶囊位于宠物卡片内且无溢出
- [x] 收紧横屏待办卡片内部排版，防止完成按钮越界 → 验证: 多尺寸横屏测试确认完成按钮完全位于待办卡片内
- [x] 保持设置和完成交互功能不变 → 验证: 点击设置和完成按钮仍触发原回调
- [x] 跑聚焦测试和静态检查 → 验证: `flutter test test/pet_device_dashboard_test.dart` 与相关 `flutter analyze`

### Review

- 已选择服务宠物后的横屏看板改为真正的左右两栏：左侧 3 份宽度包含时间、同步异常入口、设置按钮和宠物头像状态卡，右侧 7 份宽度由待办大卡片从顶部到底部完整填充，避免顶部右侧状态区继续压缩待办空间。
- 连接状态胶囊只在横屏看板中迁入宠物头像卡片底部；竖屏看板和未选择宠物的选择页保持原展示。头像紧凑态半径从 38 增至 45，并通过卡片内 `spaceBetween` 为底部状态胶囊留出稳定间距。
- 新增横屏多尺寸 widget 几何测试，覆盖 `720x390`、`900x520` 和接近截图比例的 `2048x945`，验证设置按钮右边缘与宠物卡片右边缘对齐、连接胶囊在宠物卡片内、待办卡片和完成按钮都不越界。
- 验证通过：`flutter test test/pet_device_dashboard_test.dart`；`flutter analyze lib/app/pet_device_dashboard.dart test/pet_device_dashboard_test.dart`。

## 2026-06-22 横屏看板修复后双端安装包构建

- [x] 同步官方 Flutter 依赖并刷新 iOS Pods → 验证: `flutter pub get` 与 `cd ios && pod install`
- [x] 构建 iOS 未签名 release App 并打包 unsigned IPA → 验证: `build/ios/Runner-unsigned.ipa` 存在且可计算 SHA256
- [x] 构建 Android arm64 release APK → 验证: `build/app/outputs/flutter-apk/app-release.apk` 存在且可计算 SHA256
- [x] 检查构建副作用和残留进程 → 验证: `git status --short`、测试/构建进程检查

### Review

- iOS 未签名 IPA 已构建：`build/ios/Runner-unsigned.ipa`，大小 31MB，SHA256 `af95ba06b324fb748ecdf0ffe3c750d6579730b88e5e8d96ee016ff7d76809fe`。
- Android arm64 release APK 已构建：`build/app/outputs/flutter-apk/app-release.apk`，大小 40MB，SHA256 `7d3f808e38074bfafdca4da70710acfc1f5d28473a24661f4a3f4b967d5ca2a0`。
- 构建过程提示 Gradle/AGP/Kotlin Gradle Plugin 未来 Flutter 兼容性警告，但本次 Android release 构建成功。
- `flutter pub get` 曾产生 `pubspec.lock` 的 `meta/test_api` 版本翻转，已作为构建副作用恢复；`./gradlew --stop` 后复查无 Flutter/Xcode/Gradle 测试或构建残留进程。

## 2026-06-22 宠物端与建档体验修复

- [x] 优化宠物端横屏选择页布局、文案和小卡片阴影 → 验证: 多尺寸 widget 几何测试无越界/暗角文案残留
- [x] 修复添加宠物流程生日卡片阴影，并重构体重滚轮/直接输入 → 验证: 建档流程 widget 测试覆盖日期、滚轮、弹窗和校验
- [x] 修复首次启动角色页回滑和深色模式图标 → 验证: intro widget 测试覆盖不能前进、可后退、深色颜色
- [x] 清理用户可见“新加入”展示 → 验证: UI 测试和 `rg` 聚焦检查
- [x] 审阅宠物类型/品种/emoji 同步链路并落盘报告 → 验证: `docs/pet-type-avatar-sync-risk-review-2026-06-22.md`
- [x] 跑聚焦测试、analyze 和 diff 检查 → 验证: Flutter tests、`flutter analyze`、`git diff --check`

### Review

- 宠物端横屏选择页已统一为左侧时间/设置加状态卡、右侧宠物列表；右侧计数胶囊和左侧“选择服务宠物/已连接主人端”类冗余文案已移除，小卡片阴影降噪并留出安全 padding。
- 添加宠物流程中，生日 `CalendarDatePicker` 现在包在独立内嵌面板内；体重步骤改为滚轮选择，点击数值可直接输入，非法输入保留弹窗错误，超范围值会 clamp 到 `0.1-80.0kg`。
- 首次启动角色页保留不能继续滑到下一页的逻辑，并允许从角色页回滑到上一页；角色页英雄图标继续使用浅蓝圆形背景和蓝色设备图标。
- 用户可见展示层不再直接展示“新加入”；`Pet.ageLabel` 字段保留作旧数据兼容，相关过滤在展示 helper 中完成。
- 同步风险报告已落盘到 `docs/pet-type-avatar-sync-risk-review-2026-06-22.md`；新增数据测试确认 dog 类型不会因兔相关品种文案变成兔 emoji，未知 type 会降级为 other 并使用 `avatarText`。
- 验证通过：`flutter analyze lib/app/pet_device_dashboard.dart lib/app/pet_onboarding_overlay.dart lib/app/pet_first_launch_intro.dart lib/app/petnote_pages.dart lib/app/petnote_pages_pets.dart lib/app/petnote_pages_pets_details.dart test/pet_device_dashboard_test.dart test/widget_test.dart test/pet_care_store_test.dart test/pet_replica_controller_test.dart`；`flutter test test/pet_device_dashboard_test.dart test/widget_test.dart test/pet_care_store_test.dart test/pet_replica_controller_test.dart`；`git diff --check`。复查无测试残留进程。

## 2026-06-22 宠物端与建档体验修复后双端构建

- [x] 检查 README 构建约定和 macOS 串行脚本可用性 → 验证: 脚本存在性、booted simulator 状态
- [x] 构建 iOS release App 并打包 unsigned IPA → 验证: `build/ios/Runner-unsigned.ipa` 存在且可计算 SHA256
- [x] 构建 Android arm64-v8a release APK → 验证: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 存在且可计算 SHA256
- [x] 检查构建副作用和残留进程 → 验证: `git status --short`、构建/测试进程检查

### Review

- 当前没有已启动 iOS 模拟器，`scripts/post-build-macos.sh` 的模拟器安装步骤会被设备状态阻塞；本次按 README release 链路构建产物。
- iOS 未签名 IPA 已构建：`build/ios/Runner-unsigned.ipa`，大小 31MB，SHA256 `7d40724e667d6a994c7d4f035daa144e27950b6c3c5711511673b46600212cca`。
- Android arm64-v8a release APK 已构建：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，大小 27MB，SHA256 `08a276b7dccc3a9aa5dd1d92f1365a66ef601839a9bf39523f254ad9dfae8074`。
- Android 构建首次在 Gradle 启动阶段出现 `exit code -9`，随后确认 Gradle wrapper 可启动并重跑成功；构建过程仍提示 Gradle/AGP/Kotlin Gradle Plugin 未来 Flutter 兼容性警告。
- `./gradlew --stop` 后复查无 Flutter/Xcode/Gradle 测试或构建残留进程；`git status --short` 未出现 lockfile、Pods 或签名配置噪音。
