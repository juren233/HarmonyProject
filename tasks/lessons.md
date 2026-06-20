# 项目经验

- 删除确认弹窗这类遮罩 UI，要区分“背景 barrier 允许半透明”和“弹窗卡片 surface 必须不透明”。用户要求“不要黑色背景，只让卡片不透明”时，不能用加深整个背景替代修正卡片 surface。
- 长按删除这类危险操作不能用裸 pointer down 定时器自证成功；应绑定 Flutter 长按手势生命周期，让滚动、取消和手势竞争自然取消进度，避免误触。
- Harmony Flutter 插件注册失败时，不能只清缓存；如果 `.flutter-plugins-dependencies` 缺 `plugins.ohos`，自管 hvigor 插件必须能从 `dependencyGraph` 和 `.dart_tool/package_config.json` 回退识别 `ohos/oh-package.json5`，并且用标准 `fileURLToPath` 还原 `file://` package URI，避免丢失 `/Users/...` 的前导斜杠。
- 双机真机问题不能把单端页面、单端日志或服务端健康检查包装成“测试成功”。必须同时确认两台设备都实际进入目标 App 状态，并用双端日志或 UI 状态互相印证后再下结论。
- 用户明确“两台已打开视频通话页”或“不要再切页面”后，后续验证只能做只读抓取：截图、logcat、服务端日志、包信息。不得再用 `monkey`、`am start`、`input tap` 或安装动作改变设备页面；如确需安装新包，先说明安装会打断页面，安装后等待用户重新打开目标页。

- 双端 RTC 排障时，必须先向用户区分 UI 连接状态和原生 SDK 媒体面入会状态；如果修复异步入会判断会让“已连接”变成“连接失败”，要提前说明这是暴露真实失败而不是媒体链路倒退，并给用户一个是否保留旧展示的选择。
- 审查 GitHub Actions 构建数量时，不能只看 job 显示名里的 matrix 字段组合下结论；必须同时核对 matrix include 数量、artifact 名称和构建命令。`(arm64-v8a, arm64)` 这类显示通常是“产物 ABI + Flutter target 映射”，不等于构建了两个 APK。
