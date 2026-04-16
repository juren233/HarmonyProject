# 数据导出短样本替换设计

## 背景

当前数据导出链路使用的联调样本位于 [docs/examples/petnote-ai-history-backup.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup.json)。这份样本是“单宠 1 年高密度备份”，覆盖 12 个月历史并带有未来计划，条目量较大。

这与当前 app 的主要使用诉求不一致：现阶段更需要贴近“最近 1 个月”和“最近 3 个月”的伪真实数据，而不是年度级高密度历史。继续保留年度样本会带来两个问题：

- 导出/导入联调样本过重，阅读和维护成本高
- 测试对 12 个月覆盖和大条目数形成了不必要绑定

## 目标

- 用“1 个月样本 + 3 个月样本”替换现有年度大样本
- 保持现有导出/导入 JSON 协议不变
- 保持样本仍可被 `DataStorageCoordinator.parsePackageJson()` 和 `validatePackage()` 正常解析与校验
- 让测试从“年度高密度覆盖”改为“短窗口、伪真实、可导入”

## 非目标

- 不修改 `PetNoteDataPackage`、`PetNoteDataState` 或导入导出协议
- 不修改真实用户数据的导出逻辑
- 不改页面结构，只调整样本文件与相关测试
- 不新增“6 个月”或“1 年”新样本

## 方案

### 样本文件

移除年度样本的默认使用，改为提供两份短样本：

- [docs/examples/petnote-ai-history-backup-1m.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup-1m.json)
- [docs/examples/petnote-ai-history-backup-3m.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup-3m.json)

两份样本都继续使用完整备份格式：

- `packageType` 仍为 `backup`
- `schemaVersion` 保持当前版本
- `data/settings/meta` 结构保持兼容

### 数据语义

两份样本都保持“单宠、伪真实、可联调”的特征，但时间窗口不同：

- `1m` 样本：仅覆盖最近 30 天内的历史数据，并保留少量未来 todo/reminder
- `3m` 样本：仅覆盖最近 90 天内的历史数据，并保留少量未来 todo/reminder

共同约束：

- `records` 仅保留历史记录，不生成未来记录
- `todos` 与 `reminders` 可以保留少量未来计划，模拟真实待办和提醒分布
- 条目密度保持“足够真实但不过载”，不再追求每月 30+ 条、全年覆盖

### 测试调整

更新 [test/data_storage_sample_fixture_test.dart](/Users/ebato/Documents/Projects/Harmony/PetNote/test/data_storage_sample_fixture_test.dart)，从单个年度样本断言改为双样本断言：

- `1m` 样本可解析、可校验
- `3m` 样本可解析、可校验
- `1m` 样本的业务数据时间分布不超过最近 30 天窗口
- `3m` 样本的业务数据时间分布不超过最近 90 天窗口
- 两份样本都保留未来 todo/reminder，且不包含未来 records

不再断言以下年度特征：

- `packageName` 必须包含“1 年”或“年度高密度”
- 12 个月 bucket 全覆盖
- 每月至少 30 条
- 年度级固定总条目数

## 影响范围

直接影响文件：

- [docs/examples/petnote-ai-history-backup.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup.json)
- [test/data_storage_sample_fixture_test.dart](/Users/ebato/Documents/Projects/Harmony/PetNote/test/data_storage_sample_fixture_test.dart)

新增文件：

- [docs/examples/petnote-ai-history-backup-1m.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup-1m.json)
- [docs/examples/petnote-ai-history-backup-3m.json](/Users/ebato/Documents/Projects/Harmony/PetNote/docs/examples/petnote-ai-history-backup-3m.json)

预期不会影响：

- `DataStorageCoordinator.createBackupPackage()`
- 真实用户导出/恢复流程
- `PetNoteStore.seeded()` 的页面演示数据

## 验证

最低验证包含：

- `flutter test test/data_storage_sample_fixture_test.dart`
- 如测试涉及解析或模型兼容，再补跑
  - `flutter test test/data_storage_coordinator_test.dart`
  - `flutter test test/data_storage_widget_test.dart`

## 风险与收口

主要风险不是协议兼容，而是测试仍然残留对年度样本名称或条目规模的隐式假设。实现时需要同步清理这些硬编码，避免“样本已瘦身，但测试仍按年度样本写死”。

这次设计的收口标准是：

- 仓库里不再默认依赖年度高密度导出样本
- 1 个月和 3 个月两份样本都能独立通过解析与校验测试
- 导出联调样本体量明显下降，但仍保留真实业务节奏感
