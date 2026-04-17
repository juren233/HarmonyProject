# Petnote Pages Reuse Design

## 背景

`lib/app/petnote_pages.dart` 已拆分为多个 `part` 文件，文件体量问题已缓解，但重复展示块仍然散落在：

- `lib/app/petnote_pages.dart`
- `lib/app/petnote_pages_overview.dart`
- `lib/app/petnote_pages_pets.dart`
- `lib/app/petnote_pages_ai.dart`

当前重复主要集中在空态展示、加载提示、标题+要点列表、以及 pets 页面里的状态行展示壳。

本次目标不是重构页面状态流，而是在不改变交互和结果的前提下，把稳定的展示+状态块抽到共享文件，降低维护成本。

## 设计目标

- 只抽取稳定、重复、低风险的展示组件。
- 不改变页面状态机、数据流、事件回调和业务判断。
- 共享组件统一放入 `lib/app/common_widgets.dart`，避免继续增加新的零散文件。
- 继续兼容现有测试，必要时只调整直接受源码结构变化影响的测试。

## 不做的事

- 不改 `PetNoteStore`、AI service、状态计算逻辑。
- 不把页面私有业务逻辑下沉到共享组件。
- 不顺手清理 analyzer 存量 warning/info。
- 不修改 README、脚本、平台工程。

## 拟新增共享组件

### 1. `PageEmptyStateBlock`

用途：统一页面空态中的 HeroPanel + EmptyCard 组合展示。

输入：

- hero 标题
- hero 副标题
- empty title
- empty subtitle
- action label
- onAction

使用位置：

- checklist 空态
- overview 空态
- pets 空态

注意：页头 `PageHeader` 仍保留在各页面内，不抽进共享组件，避免页面语义被抹平。

### 2. `InlineLoadingMessage`

用途：统一“圆形进度 + 提示文案”的内联加载状态。

输入：

- message
- 可选 `Key`

使用位置：

- pets 页 AI 看诊摘要加载
- 后续可覆盖 overview/其他局部加载提示

### 3. `TitledBulletGroup`

用途：统一“标题 + BulletText 列表”的展示块。

输入：

- title
- items
- 可选 titleStyle
- 可选 spacing

使用位置：

- `_InlineBulletGroup`
- `_AiDetailGroup`

注意：仅抽壳，不改变空列表时返回 `SizedBox.shrink()` 的行为。

### 4. `StatusListRow`

用途：统一 pets 页面内 `ListRow` 的展示骨架。

输入：

- title
- subtitle
- leadingIcon
- leadingBackgroundColor
- leadingIconColor
- trailing

使用位置：

- 近期提醒列表
- 资料记录列表
- 后续可选迁移自定义区间行，但不强制

注意：

- 只负责视觉壳层。
- subtitle 拼接、badge 文案、按钮点击仍由页面层完成。
- 不要做成过度泛化的大组件。

## 风险与控制

### 风险 1：抽象过度

如果把不同语义的状态块统一得过头，会导致共享组件承担业务判断。

控制：

- 共享组件只接收最终展示数据。
- 页面层继续负责条件判断、文案拼装和事件处理。

### 风险 2：结构测试失效

源码结构测试可能仍读取旧文件内容或假定旧组件名称。

控制：

- 仅调整直接依赖源码布局的测试。
- 不改与行为无关的断言语义。

### 风险 3：视觉细节回归

共享组件抽取时可能漏掉 padding、字号、边框等细节。

控制：

- 抽取前后跑 widget tests。
- 对关键组件保留原样式参数，不做视觉“优化”。

## 推荐实施顺序

1. 先在 `common_widgets.dart` 新增 4 个共享组件。
2. 先替换风险最低的 `InlineLoadingMessage` 和 `TitledBulletGroup`。
3. 再替换 `PageEmptyStateBlock`。
4. 最后替换 `StatusListRow`，并限定在 pets 页面。
5. 跑结构测试、AI 页面测试、通用 widget tests 回归。
