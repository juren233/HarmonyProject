# 备份可选导出 API Key 设计

## 背景

当前 PetNote 的完整备份只导出业务数据和普通设置，不包含 API Key。API Key 通过独立的安全存储桥接保存在 iOS Keychain 与 Android `EncryptedSharedPreferences` 中，因此现有备份恢复后，AI 配置会回来，但密钥需要用户重新填写。

用户希望增加一个可选能力：允许在导出备份时一并带上 API Key，但必须经过用户明确确认；导入这类备份时，如果检测到其中包含 API Key，也必须再次确认后才能恢复，避免误覆盖本地现有密钥。

## 目标

- 默认行为保持不变：普通导出不包含 API Key。
- 用户可在导出时选择“同时导出 API Key”，并通过二次确认后将密钥写入备份文件。
- 导入时如果备份中存在 API Key，恢复普通设置之外，再要求一次单独确认才恢复 API Key。
- 保持旧备份文件兼容，不破坏现有恢复流程。

## 非目标

- 本次不做密码加密备份。
- 本次不改变 API Key 的平台存储方式，仍然使用现有安全存储。
- 本次不增加云端托管、同步或跨端自动合并逻辑。

## 方案概述

### 备份数据结构

在现有 `PetNoteDataPackage` 中新增一个可选敏感字段，例如：

- `sensitiveSettings`
  - `aiSecrets`
    - `configId -> apiKey`

当用户未选择导出 API Key 时，`sensitiveSettings` 为 `null` 或不出现在 JSON 中。这样可以保持现有普通备份结构不变，同时兼容旧文件解析。

### 导出流程

点击“导出完整备份”后，先展示一个导出确认对话框，包含：

- 默认选项：仅导出业务数据与普通设置
- 可勾选项：同时导出 API Key（敏感信息）
- 风险提示：包含 API Key 的备份文件应由用户自行妥善保管

如果用户勾选导出 API Key，再进入第二层确认，文案明确说明：

- 该备份文件会包含可直接调用第三方 AI 服务的密钥
- 文件泄露可能导致额度损失或账户风险
- 确认后才会继续导出

只有在第二层确认通过后，导出流程才会从 `AiSecretStore` 读取当前配置对应的 API Key，并写入 `sensitiveSettings.aiSecrets`。

### 导入流程

导入并解析备份后：

- 如果备份不包含 `sensitiveSettings.aiSecrets`，流程与现在一致。
- 如果包含，则在恢复确认页中增加一条高风险提示，说明该文件同时包含 API Key。
- 用户即使选择了“恢复普通设置”，也不会自动恢复 API Key。
- 只有用户在导入流程中再次明确确认“恢复 API Key”后，才会将备份里的密钥写入安全存储。

这样能把“恢复业务数据/普通设置”和“覆盖本地密钥”两个动作拆开，减少误操作。

### 安全存储恢复规则

- 恢复 API Key 时，只处理备份里提供的 `configId -> apiKey` 映射。
- 如果对应 AI 配置也被恢复，则按恢复后的 `configId` 写入密钥。
- 如果备份中存在某个 `configId` 的密钥，但当前导入结果里没有对应配置，则忽略该条密钥并记录日志。
- 如果平台安全存储不可用，则普通恢复仍可继续，但 API Key 恢复入口应禁用，并向用户显示原因。

## UI 与交互

### 导出

在 [lib/app/data_storage_page.dart](/Users/ebato/Documents/Projects/Harmony/PetNote/lib/app/data_storage_page.dart) 的导出按钮流程前增加一个确认弹窗：

- 标题：确认导出备份
- 默认文案：导出业务数据与普通设置
- 可选开关：包含 API Key（敏感信息）
- 若打开开关，展示高风险说明并继续二次确认

### 导入

在现有恢复确认页基础上：

- 若备份不含敏感信息，不改现有界面结构。
- 若备份含敏感信息，新增风险区块，说明文件中存在 API Key。
- 当用户开启“恢复普通设置”后，仍需额外点击“恢复 API Key”确认，避免把它和普通设置恢复混为一体。

## 数据模型与服务边界

### 数据模型

需要新增两个轻量模型：

- `PetNoteSensitiveSettingsState`
- `PetNoteAiSecretSnapshot`

其中 `PetNoteSensitiveSettingsState` 挂在 `PetNoteDataPackage` 上作为可选字段；`PetNoteAiSecretSnapshot` 负责表达单条密钥快照，至少包含：

- `configId`
- `apiKey`

### 协调器

[lib/data/data_storage_coordinator.dart](/Users/ebato/Documents/Projects/Harmony/PetNote/lib/data/data_storage_coordinator.dart) 需要接入 `AiSecretStore`，并新增两个布尔选项：

- 导出选项：`includeSensitiveSettings`
- 导入选项：`restoreSensitiveSettings`

协调器负责：

- 导出时按选项读取并组装敏感字段
- 导入时按选项把敏感字段写回安全存储
- 在日志中明确区分“已恢复普通设置”和“已恢复 API Key”

## 错误处理

- 安全存储不可用：允许普通导出/导入继续，但敏感功能禁用并提示。
- 备份中敏感字段格式错误：忽略 API Key 恢复，普通数据与普通设置按原逻辑继续。
- 仅部分密钥恢复失败：给出明确提示，并记录失败的 `configId`，但不回滚已成功恢复的普通数据。

## 测试策略

需要覆盖三层测试：

### 数据模型与协调器

- 默认导出不包含 `sensitiveSettings`
- 选择包含敏感信息后，导出 JSON 出现 `aiSecrets`
- 导入包含 API Key 的备份时，未开启 `restoreSensitiveSettings` 不应写入密钥
- 导入包含 API Key 的备份时，开启 `restoreSensitiveSettings` 才写入密钥
- 旧备份文件与不含敏感字段的备份应继续可解析

### 页面交互

- 导出时默认不勾选 API Key
- 勾选 API Key 后必须经过二次确认
- 导入含 API Key 的备份时显示额外风险提示
- 用户取消恢复 API Key 时，仅恢复业务数据与普通设置

### 平台可用性降级

- 安全存储不可用时，导出敏感信息入口禁用
- 安全存储不可用时，导入页不能执行 API Key 恢复，但普通恢复照常进行

## 兼容性

- 旧备份文件无需迁移，仍按当前逻辑恢复。
- 新备份文件在没有 `sensitiveSettings` 时与旧格式等价。
- `schemaVersion` 本次可以保持不变，只新增可选字段；如果实现中发现解析约束不足，再考虑升级版本号。

## 风险与权衡

- 该方案让 API Key 可以进入导出的 JSON 文件，安全边界从“仅设备安全存储”扩展到“备份文件本身也可能持有密钥”。
- 为降低风险，本次通过“默认关闭 + 导出确认 + 导入确认”控制误操作，但这不能替代加密。
- 因此 UI 文案必须明确提示风险，且默认路径必须始终是不导出 API Key。

## 实施建议

建议按以下顺序实现：

1. 先扩展数据模型与协调器接口。
2. 再补充协调器与模型测试，确认默认行为不变。
3. 最后接入页面导出/导入确认交互，并补页面测试。

后续如果用户继续要求更高安全性，可以在该结构基础上演进为“备份密码加密敏感字段”方案。
