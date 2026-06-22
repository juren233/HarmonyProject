# Pet Type / Avatar Sync Risk Review - 2026-06-22

## Scope

本次审阅覆盖宠物类型、品种与 emoji 头像在本地模型和同步链路中的流转：

- `Pet.toJson` / `Pet.fromJson`
- `petAvatarFallbackForPet`
- `PetNoteStore.exportDataState` / `replaceAllData` / `replaceAllDataFromRemote`
- mutation upsert 与 `sync_mutation_outbox`
- snapshot 应用与 `multi_device_sync_controller`
- `sync_photo_attachment` 的照片附件回填

## Current Mapping

当前 fallback emoji 只由 `Pet.type` 决定：

- `PetType.cat` -> `🐱`
- `PetType.dog` -> `🐶`
- `PetType.rabbit` -> `🐰`
- `PetType.bird` -> `🐦`
- `PetType.other` -> `pet.avatarText`

`Pet.breed` 不参与 emoji 映射。也就是说，只要同步后的 `type` 仍为 `dog`，即使 `breed` 文案包含“兔”等字样，fallback emoji 仍应显示为 `🐶`。

## Sync Flow Findings

- `Pet.toJson` 会同时写出 `type.name`、`breed`、`avatarText`、`photoPath`，字段没有复用或位置交换。
- `Pet.fromJson` 通过 `type` 字符串还原 `PetType`；未知值会降级为 `PetType.other`，不会根据 `breed` 猜测类型。
- snapshot 同步使用 `PetNoteDataState.fromJson` 后整体 `replaceAllDataFromRemote`，宠物对象仍走 `Pet.fromJson`。
- mutation 同步中，宠物 upsert 的 `data` 使用 `Pet.toJson`，接收端再用 `Pet.fromJson`。
- 照片附件应用只回写 `photoPath`，并显式保留 `type`、`breed`、`avatarText` 等宠物字段。

## Risk Assessment

“狗的品种显示兔子 emoji 头像”的直接发生概率较低。当前代码不会从品种推导 emoji，也没有发现把 `breed` 写入 `type` 的本地路径。

真实风险点主要在以下几类：

- 远端或旧数据中的 `type` 字段本身已经错误，例如狗被写成 `rabbit`。
- 旧版本、测试种子或外部导入数据缺失/污染 `type`，导致 `Pet.fromJson` 降级为 `other`，从而显示 `avatarText`。
- 多端合并冲突中，较新的错误宠物 payload 覆盖了正确 payload。
- 调试或测试数据人为组合出“dog breed + rabbit type”，界面会按 `type` 显示兔 emoji，这符合当前映射规则但会造成认知错位。

## Recommendations

- 保持 emoji 映射继续只依赖 `type`，不要引入基于 `breed` 文案的猜测逻辑。
- 增加回归测试：`PetType.dog` 搭配兔相关 `breed` 时 fallback 仍为 `🐶`。
- 增加未知 `type` 降级测试，确认旧/坏数据只进入 `other` 并使用 `avatarText`。
- 若后续要修复历史坏数据，应做显式数据校验或迁移报告，不建议在展示层隐式猜测并改写类型。
