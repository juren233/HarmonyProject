# PowerSync 试验分支

- [x] 创建隔离 worktree，不带入 main 工作区未提交改动 → 验证: `git status --short --branch` 显示 `codex/powersync-spike...origin/main`，main 工作区状态保持原样
- [x] 接入 Flutter / server 依赖探针 → 验证: `flutter pub add powersync path_provider`、`cd server && dart pub add postgres`
- [x] 建立 PowerSync spike 文档和任务边界 → 验证: `docs/powersync-spike-plan.md` 记录架构、Docker、本地/远端边界、三端风险
- [x] 新增本地 Docker 试验栈和 Postgres schema → 验证: 新增 `server/docker-compose.powersync.yml`、`server/powersync/*`、`server/sql/powersync_spike_001.sql`，未修改现有 `server/docker-compose.yml`
- [x] 扩展 server `/powersync/credentials` 和 `/powersync/upload` → 验证: `cd server && dart test test/powersync_server_test.dart` 通过，7/7 pass
- [x] 新增 Flutter PowerSync schema / connector / mapper / feature flag → 验证: `flutter test test/sync/powersync/powersync_spike_test.dart` 通过，8/8 pass
- [x] 运行 spike 聚焦验证与隔离检查 → 验证: targeted analyze 通过，`git diff --check` 通过，main 工作区状态对比未变化
- [x] 尝试 Android / iOS / Harmony 构建硬门槛 → 验证: iOS no-codesign 通过；Android debug 通过；Android release 被本机缺正式签名材料阻断；Harmony 被本机缺 `powershell`/`pwsh` 阻断，未形成 PowerSync OHOS 兼容结论

## Review

- 试验从 `origin/main` 新建 worktree `/Volumes/Data/Projects/PetNote-powersync-spike`，不在当前 main 工作区切分支、stash、提交或格式化。
- 第一轮只做本地 Docker 可行性，不部署 `8.138.24.105`，也不改现有生产 `server/docker-compose.yml` 默认入口。
- PowerSync 侧必须保留 legacy sync 为默认路径；只有显式选择 `SyncEngineMode.powersyncSpike` 才进入试验路径。
- 三端兼容是硬门槛。若 PowerSync Flutter SDK 的 native sqlite/jni/objective_c 依赖无法被 OHOS Flutter 编译，这是 spike 的有效阻断结论。
- 本轮新增 server HMAC JWT credentials、Postgres upload repository、PowerSync schema、Flutter BackendConnector、数据映射 adapter 和独立 Docker/SQL 配置。`/ws`、配对、RTC Token 与生产 compose 默认入口保持不变。
- 验证通过：`cd server && dart test test/powersync_server_test.dart` 7/7 pass；`flutter test test/sync/powersync/powersync_spike_test.dart` 8/8 pass；`flutter analyze lib/sync/sync_engine_mode.dart lib/sync/powersync test/sync/powersync` 无问题；`cd server && dart analyze lib/src/powersync_jwt.dart lib/src/powersync_upload_repository.dart lib/src/server_app.dart test/powersync_server_test.dart` 无问题；`git diff --check` 无问题。
- 平台探针：`flutter build ios --release --no-codesign` 通过，产出 `build/ios/iphoneos/Runner.app` 约 66M；`flutter build apk --debug --target-platform android-arm64 --no-tree-shake-icons` 通过，debug APK SHA256 `71827d5c25cf0e236f6af5ebcb6b879b539fbac864818a3f9f96615994359587`。
- 未完成的硬门槛：`flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons` 停在缺 `android/key.properties`，未进入 PowerSync 编译阶段；`powershell` 与 `pwsh` 均不存在，无法执行 README 约定的 Harmony 脚本；本机也没有 `docker`，无法运行 `docker compose -f server/docker-compose.powersync.yml config/up`。

# 数据同步与远程视频故障审查

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


## 2026-06-22 PowerSync spike 服务端闭环

- [x] 隔离 main 工作区，继续在 `/Volumes/Data/Projects/PetNote-powersync-spike` 分支执行 → 验证: `git status --short --branch` 显示 `codex/powersync-spike...origin/codex/powersync-spike`
- [x] 修复 PowerSync service 启动失败 → 验证: `server/powersync/service.yaml` 显式设置 source/storage `sslmode: disable`，服务器容器 `petnote-powersync-spike-powersync-service-1` 稳定 `Up`
- [x] 固定 PowerSync spike 服务镜像版本 → 验证: `server/docker-compose.powersync.yml` 默认使用 `journeyapps/powersync-service:1.20.0`
- [x] 修复头像 metadata 上传写入 `pet_photo_assets.pet_id` → 验证: 服务器闭环写入 `pet_photos/photo-1.jpg`，并新增 server 单元测试覆盖 operation 透传
- [x] 验证生产服务不受 spike 影响 → 验证: 生产 `server-petnote-sync-1` 仍监听 `0.0.0.0:8787`，`curl http://127.0.0.1:8787/healthz` 返回 `ok`
- [x] 完成服务器端幂等和冲突策略闭环 → 验证: owner 上传 `applied:3`、重复上传 `skipped:3`、pet 同时间冲突后最终 `pets` 行保持 `Luna owner|20|owner-device`

### Review

- PowerSync service 重启根因不是服务器资源，也不是 Postgres 不可写，而是 PowerSync 的 Postgres 配置不会从 URI query 读取 `sslmode`；只写 `?sslmode=disable` 会被忽略，默认 `verify-full` 触发 TLS 探测，并在 metrics 初始化前报 `PSYNC_S0001`。已在 YAML source/storage 连接上显式写入 `sslmode: disable`。
- 服务器隔离栈已跑通：Postgres `127.0.0.1:15432`、PetNote spike server `127.0.0.1:18787`、PowerSync service `127.0.0.1:18080`；生产同步服务仍独立运行在 `0.0.0.0:8787`。
- 后端闭环验证通过：credentials JWT 签发、PowerSync upload 写入核心表、重复 op 幂等跳过、owner/pet 同时间冲突按角色优先级收敛、头像 metadata 写入 `pet_photo_assets` 并被 PowerSync 复制日志捕获。
- 本地验证通过：`cd server && dart test test/powersync_server_test.dart`；`cd server && dart analyze lib/src/powersync_jwt.dart lib/src/powersync_upload_repository.dart lib/src/server_app.dart test/powersync_server_test.dart`。`dart format` 已格式化改动文件，但在缺少根依赖解析时提示 `flutter_lints` include warning，不影响格式化结果。
