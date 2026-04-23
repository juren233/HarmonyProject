# PetNote 项目级 AI 协作约束

本文件是仓库级约束，面向所有在本项目内工作的 AI agent、自动化助手和代码生成工具。

目标只有一个：在不破坏现有工程约定的前提下，稳定交付改动，避免把本地环境噪音、错误平台状态或未对齐的文档理解带进仓库。

## 1. 先读 README，再动手

- 首次进入本仓库，或开始任何一个新任务时，必须先打开并阅读 [README.md](./README.md) 原文，再决定实现方案。
- 如果任务涉及平台运行、签名、SDK、脚本、目录结构、提交边界、协作流程，必须重新阅读 README 对应章节，不能只依赖记忆。
- 如果还没有读到 README 相关章节，不得开始修改代码、配置、脚本或文档。
- 开始任何任务前，先阅读 [README.md](./README.md) 中与本次任务直接相关的部分。
- 涉及平台运行、签名、SDK 切换、目录归属、提交边界、脚本入口、构建命令时，README 是项目内第一参考源。
- 不要凭经验套用其他 Flutter / HarmonyOS 项目的习惯到本仓库。

## 2. 作用范围与优先级

- 本文件只定义项目级约束，不替代系统级或用户级安全规则。
- 如果系统指令、用户明确要求、仓库 README 与本文件之间出现冲突，按以下顺序处理：
  1. 系统 / 平台硬约束
  2. 用户当前明确要求
  3. README
  4. 本文件
- 如果 README 和实际代码、脚本行为、当前任务需求之间出现分歧，禁止擅自选择其中一边并继续开发，必须先整理证据，再向人工确认。

## 3. 变更前的基础判断

- 先判断本次任务涉及的是共享层、Android / iOS 官方 Flutter 平台层，还是 Harmony 平台层。
- 先判断修改范围是否最小且必要，不要顺手重构无关文件，不要顺手清理无关 warning，不要顺手统一格式化整个仓库。
- 如果用户只点名一个文件，默认只改这个文件；如果必须联动修改其他文件，先确认这些文件是完成任务所绝对必要的直接相关文件。

## 4. 文档与实现的协同规则

- 任何改动只要影响以下内容之一，就必须检查 README 是否也需要同步：
  - 运行方式
  - 构建命令
  - 签名流程
  - SDK / 工具链约定
  - 目录结构
  - 可提交 / 不可提交文件边界
  - 团队协作方式
- 如果发现 README 缺失、模糊、过期，不能假装没看到继续写代码。
- 在汇报方案、排查结论或改动结果时，应明确说明这次主要依据了 README 的哪些约定；如果没有对应约定，也要明确指出 README 当前缺口。
- 此时必须向人工明确说明：
  - 当前分歧点是什么
  - 代码或脚本实际行为是什么
  - README 目前写的是什么
  - 是否需要顺手补全 README
- 询问时必须带证据，不要空口问“要不要改文档”。

## 5. 出现分歧时的强制动作

- 遇到以下任一情况，必须暂停并询问人工是否继续，以及是否要把结论补进 README：
  - README 与代码行为不一致
  - README 与用户要求不一致
  - 涉及签名、密钥、证书、profile、密码密文的共享规则不清楚
  - 需要修改受版本控制的基线配置，但无法确认这是共享改动还是本机噪音
  - 需要在多个合理方案中二选一，且后果不明显
- 询问时必须默认附带一句：`如果这次结论会影响后续协作，是否同时补充到 README？`

## 6. Flutter / Harmony 项目特殊约束

### 6.1 三端共存规则

- 本仓库同时维护 Android、iOS、HarmonyOS / OpenHarmony 三端。
- 共享业务层主要位于 [lib](./lib) 和 [test](./test)。
- Android 和 iOS 走官方 Flutter。
- Harmony 走项目内 OHOS Flutter 与 [ohos](./ohos) 工程。
- 不要把一个平台的经验直接套到另一个平台，尤其不要把 Android Studio / VS Code 下的 Flutter 运行方式直接套到 DevEco。

### 6.2 SDK 状态切换规则

- 根目录默认应保持 README 约定的官方 Flutter 状态。
- Harmony 相关构建、测试、运行优先走 [scripts/flutter-ohos.ps1](./scripts/flutter-ohos.ps1) 或 README 中约定的 DevEco / hvigor 流程。
- 不要手动混用两套 SDK 状态，不要在不确认当前状态的情况下裸跑 `flutter pub get`。

### 6.3 Harmony 签名规则

- [ohos/build-profile.json5](./ohos/build-profile.json5) 是共享签名基线文件，不是随手承载本机 IDE 自动修复结果的地方。
- 不要提交以下类型的改动，除非用户明确要求并且已经完成共享验证：
  - 把 `storeFile`、`profile`、`certpath` 改成本机绝对路径
  - 只改单独的 `storePassword` / `keyPassword` 密文
  - 把本机生成的证书、`p7b`、`cer`、设备绑定 profile 当成共享文件提交
- [ohos/sign/debug-profile.json](./ohos/sign/debug-profile.json) 是共享基线；`ohos/sign/` 下其他签名产物默认视为本地文件。
- `ohos/sign/` 下除 [ohos/sign/debug-profile.json](./ohos/sign/debug-profile.json) 之外的任何文件都不得提交，包括证书、签名链、`p7b`、`cer`、`p12`、设备绑定 profile、本机签名材料和临时辅助脚本；如果确实要共享签名辅助脚本，应放到 [scripts](./scripts) 或其他受控源码目录，并同步 README 说明。
- 如果签名链路出问题，优先核对 README、脚本和受控基线，不要先入为主地把责任归因到“用户没配环境”。

### 6.4 OHOS 工具链归属规则

- DevEco 直跑相关逻辑优先查看 [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)、[ohos/hvigorfile.ts](./ohos/hvigorfile.ts)、[ohos/hvigorconfig.ts](./ohos/hvigorconfig.ts)。
- 不要直接依赖 OHOS Flutter 子模块中的本地脏改动。
- 如果要改 Harmony 构建链路，先确认是否应该改仓库内自管插件副本，而不是子模块源码。

## 7. 提交边界与本地噪音控制

- 不要提交 README 已明确标记为本地生成物、缓存、构建产物、IDE 状态、签名临时文件的内容。
- 不要提交 Android keystore 或证书原件，包括根目录 `pet-release.jks`、`*.jks`、`*.keystore`、`*.p12`、`*.pfx`、`android/key.properties` 和 `android/signing/`。
- 不要提交 IDE 本地工程状态，包括 `*.iml`、`.idea/`、`.vscode/`、`.fleet/` 等文件或目录。
- 不要因为本机能跑，就把本机路径、本机凭据、本机状态快照提交进仓库。
- 看到以下 diff 时要高度警惕，它们默认更像环境噪音而不是共享价值：
  - `local.properties`
  - `.dart_tool/`
  - `*.iml`
  - `pet-release.jks` 或其他 keystore / 证书原件
  - `ohos/node_modules/`
  - `ohos/oh_modules/`
  - `ohos/sign/` 下本地签名产物
  - 只改 [ohos/build-profile.json5](./ohos/build-profile.json5) 密文或路径

## 8. 验证原则

- 任何声称“已修复”“已完成”“可以提交”的结论，都要有对应验证。
- 验证方式优先复用 README 中已有的官方命令或脚本，不要自创一套没人维护的命令链。
- 平台相关改动至少做对应平台的最低验证：
  - 共享层改动：至少验证 Android 和 Harmony
  - Android 改动：至少跑一次 README 中的 Android 脚本或等价命令
  - iOS 改动：至少按 README 的原生命令链或脚本完成对应验证
  - Harmony 改动：至少跑一次 [scripts/flutter-ohos.ps1](./scripts/flutter-ohos.ps1) 对应模式
- 如果因环境限制无法完成验证，必须明确说明卡在哪里，不能把“未验证”包装成“已完成”。

## 9. 沟通要求

- 与人工协作者沟通时默认使用简体中文。
- 汇报结果时优先说明：
  - 改了哪些文件
  - 为什么这些文件是必要的
  - 跑了哪些验证
  - 还有哪些风险或边界未覆盖
- 如果本次任务暴露的是项目规则缺口，而不是单点 bug，必须主动提醒人工：`这次结论是否需要补充进 README，避免后续重复踩坑？`

## 9.1 错误避免再犯警醒

- 任何涉及展示层的改动，必须先区分“内部实现需要调整”与“用户可见展示需要变化”是否为同一件事。凡是用户未明确要求变更的展示语义、展示文案和展示口径，一律默认保持不变；如确需变更，必须先向人工确认。
- 任何同时包含“本地立即可得信息”和“远端异步检查”的场景，必须优先保证本地信息首帧直接显示；远端检查只能作为异步补充，不得阻塞、覆盖或串联本地信息的即时展示。
- 任何版本信息相关改动，必须先分别确认 `version`、`buildNumber`、内部比较口径与用户可见展示口径的职责边界，禁止把内部判断字段直接当成用户展示字段使用。
- 任何一次改动只要同时触及数据来源、比较逻辑、展示文案三层，就必须先逐项写清楚“哪一层允许变、哪一层禁止变、哪一层需要确认后才能变”，确认边界后再动手修改代码。
- 任何共享 Dart 层代码只要会被 Android / iOS 官方 Flutter 编译解析，就不能直接静态引用 OHOS Flutter 独有符号，例如 `TargetPlatform.ohos`、`OhosView`、`PlatformViewsService.initOhosView`、`OhosViewController`、`OhosViewSurface` 等。运行时平台判断不能隔离编译期符号解析；如果必须承载 Harmony 专属原生视图，应使用两套 SDK 都存在的公共抽象，或拆到明确只由 OHOS Flutter 状态解析的隔离入口。
- 任何 Harmony 原生底栏、平台视图、Flutter / ArkTS 桥接相关改动，都必须同时验证官方 Flutter 和 OHOS Flutter 两条链路。Harmony 显示正常但 Android / iOS 编译失败，或者 Android 构建通过但 Harmony 原生视图不显示，都是未闭环；最低验证为 README 约定的 Android 构建脚本和 Harmony 构建脚本各跑一次。
- 不要在共享 Dart 代码中用 `TargetPlatform.ohos` 判断 Harmony，因为官方 Flutter 没有该枚举值；不要用自造 Dart 条件导入如 `if (petnote.hasOhosView)` 试图隔离 OHOS API，因为 `--dart-define` 不会创建条件导入键。需要平台判断时，必须先确认写法能被官方 Flutter 与 OHOS Flutter 同时解析。
- 任何跨 SDK 构建验证后，都要检查并清理 [pubspec.lock](./pubspec.lock) 的依赖源噪音。官方 Flutter 或 OHOS Flutter 构建可能把 `https://pub.flutter-io.cn` 改成 `https://pub.dev`，这不属于业务修复，不得混进提交。
- 任何 Harmony / ArkTS 原生插件改动，必须先按 ArkTS 而不是 TypeScript 判断语法和类型可行性。禁止使用 `in`、`for..in`、动态对象布局、运行时追加字段、隐式 `any` 思路或未验证的对象探测写法；跨 MethodChannel 返回复杂结构时，必须使用明确字段结构，并用 Harmony 构建验证。
- 任何安装后启动闪退且栈落在 `@ohos/flutter_ohos`、`FlutterView.ets`、`MethodChannel`、`StandardMessageCodec` 等桥接层的位置时，禁止直接归因到新业务插件或用户环境。必须先读取生成物中的实际栈行号上下文，再回查 [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)、[ohos/hvigorfile.ts](./ohos/hvigorfile.ts)、[ohos/hvigorconfig.ts](./ohos/hvigorconfig.ts) 等仓库自管补丁链路。
- 任何涉及 Harmony / ArkUI 系统对象的改动，都必须区分“普通 ArkTS 对象”和“系统原生对象”。对 `window.AvoidArea`、`window.Rect` 等对象，不得随意把嵌套字段整体替换成对象字面量；需要清零或调整时优先逐字段更新标量值，或先克隆成稳定普通结构后再使用，避免触发 `Obj is not a Valid object` 一类运行时崩溃。
- 任何新增 Harmony 原生插件实现文件时，不能只看本地构建是否通过。必须同时确认注册文件和实现文件都能进入版本控制，尤其要检查 [ohos/entry/src/main/ets/plugins](./ohos/entry/src/main/ets/plugins) 下新增文件是否被 `.gitignore` 命中，避免出现“注册引用已提交、插件实现未提交”的断链。
- 任何修复 `ohos/oh_modules`、`ohos/entry/build` 等生成物里暴露的问题时，不得直接修改生成物后汇报完成。必须把修复落到仓库受控源码、脚本或自管补丁中，重新跑 README 约定的 Harmony 构建，并反查生成物确认危险写法已经消失。

## 10. 推荐工作流

1. 先读 README 相关章节。
2. 再读当前任务涉及文件与脚本。
3. 判断是共享问题、平台问题、还是本地环境噪音。
4. 只做最小必要修改。
5. 用 README 认可的命令验证。
6. 检查 README 是否需要同步。
7. 如果存在分歧或新的团队约束，询问人工是否补充到 README。

## 11. 一句话原则

本仓库里，AI 的职责不是“尽快改完”，而是“在尊重 README 和项目边界的前提下，把问题闭环，并在发现规则缺口时及时拉人工确认与补文档”。
