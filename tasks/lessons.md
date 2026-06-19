# 项目经验

- 删除确认弹窗这类遮罩 UI，要区分“背景 barrier 允许半透明”和“弹窗卡片 surface 必须不透明”。用户要求“不要黑色背景，只让卡片不透明”时，不能用加深整个背景替代修正卡片 surface。
- 长按删除这类危险操作不能用裸 pointer down 定时器自证成功；应绑定 Flutter 长按手势生命周期，让滚动、取消和手势竞争自然取消进度，避免误触。
- Harmony Flutter 插件注册失败时，不能只清缓存；如果 `.flutter-plugins-dependencies` 缺 `plugins.ohos`，自管 hvigor 插件必须能从 `dependencyGraph` 和 `.dart_tool/package_config.json` 回退识别 `ohos/oh-package.json5`，并且用标准 `fileURLToPath` 还原 `file://` package URI，避免丢失 `/Users/...` 的前导斜杠。
