# 阿里云视频通话接入设计

## 背景

PetNote 早期曾有一个远程视频占位页；当前入口已切换到 `lib/app/remote_video_entry.dart` 的 `RemoteVideoPillButton`，直达 `RemoteVideoCallPage`。

同步服务已经有 WebSocket 设备会话与定向转发能力。`packages/petnote_sync_protocol/lib/src/sync_messages.dart` 已预留 `call_invite`、`call_answer`、`call_end`、`ice_candidate` 等视频信令，`server/lib/src/session_handler.dart` 也已把这些消息按 `targetDeviceId` 透传。

## 目标

1. 把远程视频入口升级为真正可用的视频通话入口。
2. 通话页采用微信风格，全屏直入，不再保留占位页作为主流程。
3. 采用阿里云 ARTC 作为媒体通话能力。
4. Flutter 侧负责通话页 UI、状态机和业务入口，原生侧负责接入各平台 ARTC SDK。
5. 服务端负责生成和下发通话所需的鉴权 Token，不把 AppKey 暴露到客户端。

## 非目标

1. 不在本次范围内实现群呼、多方会议、录制、直播转推。
2. 不做 Web 版通话。
3. 不把阿里云密钥写进客户端或仓库。
4. 不把现有同步服务改成媒体转发服务，媒体流仍由阿里云承载。

## 方案

### 推荐方案：Flutter UI + 原生 ARTC SDK 桥接

Flutter 负责微信风格通话页、呼叫中/接通中/通话中/挂断/失败态，以及本地控制按钮。

Android、iOS、Harmony 分别接各自平台上的阿里云 ARTC 原生 SDK。

Flutter 与原生通过平台通道交换：

- 初始化与销毁
- 加入/离开通话
- 本地预览开关
- 麦克风、摄像头、扬声器切换
- 远端画面状态
- 错误与断线事件

### 备选方案：Web SDK 容器

只适合作为验证，不作为最终移动端方案。移动端权限、前后台切换、Harmony 兼容性和体验稳定性都不如原生桥接。

## 交互设计

### 入口

保留当前宠物页上的视频入口，但入口点击后不再进入占位页，而是进入全屏通话页。

### 通话页

通话页采用微信风格，核心结构如下：

- 顶部：联系人头像、名称、通话状态、计时
- 中部：远端主画面
- 右下或角落：本地小窗预览
- 底部：静音、免提、摄像头开关、挂断

页面状态至少包括：

- 发起中
- 宠物端自动接通
- 呼叫中
- 接通中
- 通话中
- 已挂断
- 设备/网络错误

## 数据流

### 发起呼叫

1. Flutter 通话页根据当前宠物和目标设备，创建 `call_invite`。
2. 呼叫消息通过现有 WebSocket 定向转发到 `targetDeviceId`。
3. 目标设备收到后自动进入通话页。
4. 客户端向服务端请求本次房间所需 Token。
5. 进入频道后，由原生 ARTC SDK 建立媒体连接。

### 宠物端自动接通

1. 被叫端收到 `call_invite`。
2. 默认直接接通，不显示接听确认。
3. 立即通过 `call_answer` 回传已接通状态。
4. 获取 Token 并加入 ARTC 房间。
5. 被叫端入房后不再反向发送 `call_invite`。

### 挂断与清理

1. 任一端挂断时发送 `call_end`。
2. 原生 SDK 离会并释放资源。
3. Flutter 恢复到宠物详情页或呼叫前状态。

## 服务端设计

新增一个最小的 Token 生成接口，职责如下：

- 读取服务端环境变量中的阿里云应用标识与密钥
- 生成一次通话所需的 Token
- 返回给客户端当前房间、用户、角色和过期信息

要求：

- AppKey 不下发到客户端
- Token 只在服务端生成
- 接口返回必须可被 Flutter 侧缓存短时间复用

## 客户端设计

### Flutter 层

新增一个通话页和一个 RTC Adapter 抽象。

Adapter 负责：

- `initialize`
- `join`
- `leave`
- `toggleCamera`
- `toggleMicrophone`
- `toggleSpeaker`
- `switchCamera`
- `dispose`

### 平台层

每个平台各自实现 ARTC 原生桥接。

要求：

- Android、iOS、Harmony 都走同一组 Dart 接口
- 共享 Dart 代码里不直接引用某个平台专属类型
- 平台差异只留在原生适配层
- 视频画质只固定 720P，不设置或下发 FPS / frameRate / videoFrameRate，帧率由阿里云 SDK 与设备能力自行协商

## 现有代码的落点

本次实施优先改这些点：

1. `lib/app/remote_video_entry.dart`
2. `packages/petnote_sync_protocol/lib/src/sync_messages.dart`
3. `server/lib/src/session_handler.dart`
4. 新增一个 RTC 服务封装和通话页组件
5. Android / iOS / Harmony 各自新增或扩展原生桥接
6. 必要时补充权限和文档说明

## 验证

最小验证口径：

- Flutter 侧通话页能打开
- 呼叫消息能从发起端到达目标端
- Token 接口能返回有效数据
- Android 至少完成一次构建验证
- Harmony 至少完成一次构建验证
- iOS 至少完成一次编译或等价静态验证

## 风险

1. 这是跨端能力，不是单页改造。
2. Flutter 公开生态里没有一个可以直接替代原生 ARTC 的稳定单包方案。
3. 服务端 Token 和客户端房间参数必须严格对齐，否则会出现入会失败。
4. 需要补齐麦克风、摄像头、网络、前后台切换和挂断边界。

## 结论

最终路线采用“Flutter 微信样式通话页 + 原生 ARTC SDK 桥接 + 服务端 Token”。
