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
