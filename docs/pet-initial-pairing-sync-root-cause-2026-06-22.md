# 首次配对已有宠物不同步根因报告（2026-06-22）

## 问题现象

用户先在主人端添加宠物，再进入宠物端配对时，宠物端有较高概率只显示已连接或等待状态，但已有宠物资料没有稳定出现。相反，先配对再新增宠物时，新 mutation 可以通过实时同步链路推送，问题不明显。

## 根因分析

当前首次连接存在两类同步入口：

1. 显式配对策略：`localWins`、`remoteWins`、`merge`，由 `pendingInitialSyncPolicy` 控制。
2. 默认启动/首次配对：`pendingInitialSyncPolicy == null` 且 `pushStartupSnapshot == true`。

修复前，默认启动分支在握手完成后只执行 `requestSnapshot()`，也就是向对端请求快照；它不会主动把本机已有数据作为 merge 快照推给对端。这个行为在“双方都有最近数据”时看似安全，但在“主人端已有宠物、宠物端为空”的首次配对场景下会产生方向性缺口：空端参与请求/响应后，已有宠物不一定被推送到空端，直到后续新增或修改触发 mutation，才可能重新收敛。

这解释了“先添加宠物再配对大概率不同步”：已有宠物属于配对前静态快照，不是配对后的新 mutation；默认首次启动又缺少本地快照推送，因此依赖对端请求方向和重连时机，表现为不稳定。

## 修复方案

默认首次配对/启动在无显式策略时改为双向 merge 快照交换：

1. 先推本地 `snapshotPush`，`dataPolicy=merge`，`preserveConflictingIds=true`。
2. 再请求远端 `snapshotRequest`，`dataPolicy=merge`，`resolveConflicts=true`。

这样两端无论谁先有数据，都会在首次认证后主动提供本地快照，同时仍请求对端快照，最终以 merge 方式收敛。显式策略语义保持不变：`localWins` 仍推覆盖快照，`remoteWins` 仍请求覆盖快照，显式 `merge` 仍双向交换。

## 保护边界

- `pushStartupSnapshot=false` 的导入备份/手动覆盖流程保持不夹带启动 merge 快照，避免导入或重置被默认同步扰动。
- `pendingResetSnapshotSyncId` 存在时保留既有 pending reset 推送路径，不额外叠加默认 merge 快照，避免覆盖确认流程语义变化。
- 同步协议字段没有新增或删除，仍使用现有 `snapshotPush`、`snapshotRequest`、`dataPolicy` 和 `mergeMode`。

## 验证场景

本轮测试覆盖以下场景：

- owner 默认启动：握手前不发业务快照；握手后发送 merge `snapshotPush` 和 merge `snapshotRequest`。
- pet 默认启动：握手后同样发送 merge `snapshotPush` 和 merge `snapshotRequest`。
- 显式 `localWins`、`remoteWins`、`merge` 策略继续保持原语义。
- `pushStartupSnapshot=false` 时仍只执行指定覆盖快照，不发送默认 merge 快照。

## 剩余风险

本修复解决的是首次配对默认 merge 的方向性缺口。真实设备仍可能受到网络断线、服务端中继延迟、旧包未升级或历史坏数据影响；这些属于同步传输和数据质量问题，应通过现有 outbox、握手状态和同步问题弹窗继续诊断。
