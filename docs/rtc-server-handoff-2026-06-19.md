# PetNote 远程视频服务端排查说明

日期：2026-06-19

## 当前结论

远程视频目前还没有真正修好，但失败点已经从“服务端 RTC 未配置”推进到了“阿里云 RTC 媒体面鉴权失败”。

最新真机复测结果：

- 两台 Android 设备都已安装同一版 APK：`1.4.0-beta.17+39`
- 手机端可以从 PetNote 主人端爱宠页发起远程视频
- 平板端宠物端显示“已连接”，并且能自动进入通话页
- 双方 UI 都显示“阿里云视频通话已连接”
- 但双方仍然看不到对方画面，也听不到对方声音

关键日志如下：

```text
join requested channelId=rtc-pet-1-call-1781868749215656-767146564
joinChannel result=0
onJoinChannelResult result=33620485
onOccurError error=33620485 message=gslb_code=0,roomserver_code=401,room_server_desc=auth invalid,
```

解释：

- `joinChannel result=0` 只代表 SDK 同步调用被接受，不代表真正入会成功。
- 真正的入会结果要看异步回调 `onJoinChannelResult`。
- 当前两台设备的异步结果都是 `33620485`。
- 阿里云房间服务返回 `401 auth invalid`，说明 RTC Token 鉴权失败。
- 所以这不是 UI、摄像头权限、麦克风权限、配对、信令或本地预览问题。

## 已确认不是的问题

这些链路已经通过真机证据排除：

- 两台设备不是没连上同步服务
- 平板不是没有收到通话
- 手机和平板不是进了不同频道
- 摄像头和麦克风权限不是当前阻塞点
- App 本地预览不是当前阻塞点
- 页面显示“已连接”不能作为成功标准，因为 SDK 异步入会实际失败

## 服务端当前状态

公网健康检查：

```bash
curl -i https://petnote.juren233.top/healthz
```

最新结果已返回：

```text
HTTP/2 200
ok
```

伪造 `/rtc/token` 请求也已经不再返回旧的：

```text
503 rtc not configured
```

这说明 `ALICLOUD_RTC_APP_ID` / `ALICLOUD_RTC_APP_KEY` 缺失这一层大概率已经修掉。

这里需要特别区分两种 `401`：

- 我们用伪造 household/auth 去请求 PetNote 自己的 `/rtc/token` 接口时，如果返回 HTTP `401 unauthorized`，这是正常的测试结果，说明服务端没有再停在 `503 rtc not configured`，并且已经走到家庭认证校验。
- 真机 App 拿到服务端签发的 RTC Token 后，调用阿里云 RTC SDK 入会时，如果日志里出现 `roomserver_code=401, room_server_desc=auth invalid`，这不是正常结果，而是阿里云 RTC 房间服务拒绝了当前 Token。

当前真机失败的是第二种：

```text
room_server_desc=auth invalid
```

所以现在请重点检查 Token 生成逻辑和阿里云 RTC 应用配置是否一致。

## 需要服务端重点检查的内容

### 1. 确认服务器部署的是最新代码

请在服务器上的 PetNote 仓库根目录执行。必须是能看到 `pubspec.yaml`、`server/`、`packages/` 的目录。

```bash
cd /path/to/PetNote

git fetch origin
git checkout main
git pull --ff-only origin main
```

确认当前代码里 `server/lib/src/rtc_token_service.dart` 的签名串是这一版：

```dart
'$appId$appKey$normalizedChannelId$normalizedUserId$timestamp'
```

也就是：

```text
appId + appKey + channelId + userId + timestamp
```

不能还是旧版：

```text
appId + appKey + channelId + userId + nonce + timestamp
```

如果签名串里还包含 `nonce`，真机很可能继续报 `auth invalid`。

### 2. 确认客户端是单 Token 入会路径

Android 当前应该使用：

```kotlin
rtcEngine.joinChannel(singleToken, null, null, userId)
```

也就是说客户端入会主要依赖服务端返回的 `singleToken`，避免 `channelId/userId/token` 多处传参不一致。

### 3. 确认阿里云 RTC AppID 和 AppKey 匹配

服务器环境变量必须来自同一个阿里云 RTC 应用：

```bash
ALICLOUD_RTC_APP_ID
ALICLOUD_RTC_APP_KEY
```

请确认：

- `ALICLOUD_RTC_APP_ID` 是 RTC 应用的 AppID，不是别的云产品 ID
- `ALICLOUD_RTC_APP_KEY` 是同一个 RTC 应用的 AppKey，不是阿里云 AccessKey
- AppID 和 AppKey 没有前后空格
- AppID 和 AppKey 没有填反
- 没有使用旧项目、旧环境或测试项目的 AppKey

不要把 AppKey 提交到仓库，也不要发到公开聊天里。

### 4. 用环境变量重建服务

不要只 `git pull`，也不要只重启旧容器。请带环境变量重新 build：

```bash
ALICLOUD_RTC_APP_ID="实际阿里云RTC AppID" \
ALICLOUD_RTC_APP_KEY="实际阿里云RTC AppKey" \
DART_IMAGE=m.daocloud.io/docker.io/library/dart:3.6 \
RUNTIME_IMAGE=m.daocloud.io/docker.io/library/debian:bookworm-slim \
docker compose -f server/docker-compose.yml up -d --build
```

检查容器状态：

```bash
docker compose -f server/docker-compose.yml ps
```

查看日志：

```bash
docker compose -f server/docker-compose.yml logs --tail=120 petnote-sync
```

确认容器内环境变量存在：

```bash
docker compose -f server/docker-compose.yml exec petnote-sync env | grep ALICLOUD_RTC
```

注意：这里只需要确认两个变量有值，不要把真实 AppKey 截图发出来。

## 验收标准

服务端处理完成后，先确认健康接口：

```bash
curl -i https://petnote.juren233.top/healthz
```

应返回：

```text
HTTP/2 200
ok
```

然后让我们这边用两台 Android 真机复测。成功标准不是页面显示“已连接”，而是两台设备日志里都要出现：

```text
onJoinChannelResult result=0
```

并且后续应该能看到远端用户或远端媒体轨道相关回调，例如：

```text
onRemoteUserOnLineNotify
onRemoteTrackAvailableNotify
onFirstVideoPacketReceived
onFirstAudioPacketReceived
onFirstRemoteVideoFrameDrawn
```

如果仍然出现下面日志，就说明 RTC Token 鉴权还没修好：

```text
onJoinChannelResult result=33620485
room_server_desc=auth invalid
```

## 当前给朋友的最短结论

`503 rtc not configured` 这一层已经不像之前那样复现了，但真机入会仍然失败。当前失败点是阿里云 RTC 房间服务返回 `401 auth invalid`，请优先检查服务端是否部署了最新 `rtc_token_service.dart`、签名串是否去掉了 `nonce`、以及 `ALICLOUD_RTC_APP_ID` / `ALICLOUD_RTC_APP_KEY` 是否来自同一个正确的 RTC 应用。
