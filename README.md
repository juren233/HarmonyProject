# 宠记 PetNote

宠物照护管理应用，当前仓库同时维护三端：

- Android
- iOS
- HarmonyOS / OpenHarmony

这三个端共用同一套 Flutter 业务代码，但不共用同一套 Flutter SDK：

- Android + iOS 固定使用官方 Flutter
- HarmonyOS 固定使用项目内 OHOS Flutter

这份 README 重点说明“怎么开工程、怎么跑三端、哪些文件该提交、哪些不要提交”。

## 分支约定

- `beta` 分支后续不再建议作为日常开发分支使用
- 后续功能开发、修复和文档更新默认直接在 `main` 主分支进行
- 如果本地当前还停留在 `beta`，开始新任务前请优先切到 `main` 并同步最新代码

## 依赖源约定

- 当前项目依赖锁文件固定使用 `https://pub.flutter-io.cn`
- 非必要不要把 [pubspec.lock](./pubspec.lock) 里的这个 URL 改成 `https://pub.dev` 或其他地址，避免产生无关锁文件噪音和团队环境不一致

## 目录结构

- Flutter 共享层：
  - [pubspec.yaml](./pubspec.yaml)
  - [lib](./lib)
  - [test](./test)
- 官方 Flutter 平台层：
  - [android](./android)
  - [ios](./ios)
- Harmony 平台层：
  - [ohos](./ohos)
  - 当前有效的 Harmony 模块入口位于 [ohos/entry](./ohos/entry)
  - 如果根目录偶发出现顶层 `entry/` 残留目录（例如只剩一个 `.gitignore`），那通常是旧结构迁移或切分支后留下的未跟踪残留，不属于当前主线工程结构，不要提交，可直接删除
- 项目内 OHOS Flutter SDK 子模块：
  - [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode)
- 脚本入口：
  - [scripts/flutter-android.ps1](./scripts/flutter-android.ps1)
  - [scripts/flutter-ios.ps1](./scripts/flutter-ios.ps1)
  - [scripts/flutter-ohos.ps1](./scripts/flutter-ohos.ps1)
  - [scripts/flutter-state.ps1](./scripts/flutter-state.ps1)
  - [scripts/post-build-macos.sh](./scripts/post-build-macos.sh)

## SDK 分流规则

- Android 默认读 [android/local.properties](./android/local.properties) 里的官方 Flutter 路径。
- iOS 默认复用 Android 同一套官方 Flutter。
- Harmony 默认读 [ohos/local.properties](./ohos/local.properties) 里的项目内 OHOS Flutter 路径。
- 根目录工作区默认以“官方 Flutter 状态”为准。
- Harmony 脚本运行前会临时切换到 OHOS Flutter 状态，结束后再恢复成官方 Flutter 状态。
- DevEco Studio 直接运行会使用仓库内自管的 OHOS hvigor 插件副本，并在构建前后自动切换 / 恢复根目录共享 Flutter 状态。

这意味着：

- 日常开发 Android / iOS 时，根目录应该保持官方 Flutter。
- 需要跑 Harmony 时，不要手动切 SDK，直接走 Harmony 脚本或 DevEco 的 Harmony 工程。

## 首次拉取

推荐直接递归拉取主仓库和子模块：

```bash
git clone --recursive <repo-url>
```

如果已经拉过主仓库，再执行一次：

```bash
git submodule update --init --recursive
```

说明：

- [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 是正式子模块，不是普通目录。
- 不要把 OHOS Flutter 整套源码直接复制进主仓库历史。
- Harmony 相关兼容修复通过仓库内自管插件副本、补丁文件和脚本自动应用，不依赖子模块里的本地脏改动。
- 对应补丁文件是 [tooling/ohos-flutter/flutter-hvigor-plugin.patch](./tooling/ohos-flutter/flutter-hvigor-plugin.patch)。
- 仓库内自管插件副本位于 [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)。
- 当前受控入口是 [ohos/hvigorfile.ts](./ohos/hvigorfile.ts) 和 [ohos/hvigorconfig.ts](./ohos/hvigorconfig.ts) 的相对导入，不依赖 `ohos/package.json` 这种本地生成物长期保持某个值。

## IDE 使用方式

这是最容易混乱的地方，建议严格按下面用。

### Android / iOS

- 打开项目根目录 `.`
- 使用官方 Flutter
- 在 Android Studio / IntelliJ / VS Code 里调试 Android 和 iOS

你在根工程里稳定会看到：

- Android 真机 / 模拟器
- iOS 设备 / 模拟器

如果你的本机另外启用了 Flutter 的 Web / 桌面端支持，IDE 里也**可能**额外显示 Web、macOS、Windows 或 Linux 设备；这不代表仓库当前维护了这些平台目录。

你在根工程里通常**看不到**鸿蒙虚拟机，这是正常的。

### HarmonyOS

- 在 DevEco Studio 里打开 [ohos](./ohos)
- 使用 OHOS Flutter
- 在这个工程里调试鸿蒙真机 / 虚拟机
- 新机器首次拉仓库后，先执行一次 `powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode init`
- 初始化完成后可以直接点 DevEco 的运行按钮，不需要再手动先跑一次 Harmony 脚本来切状态
- DevEco Studio 直接运行会使用仓库内自管的 OHOS hvigor 插件副本，而不是直接改动子模块里的 upstream 插件源码
- DevEco Studio 的一键编译 / 运行流程可用于 Windows，也可用于 macOS

当前仓库对 DevEco / Harmony 的协作约定补充如下：

- [ohos/build-profile.json5](./ohos/build-profile.json5) 是**共享签名基线文件**，提交时必须保持仓库约定的相对路径和配套密文；不要因为某台机器的 DevEco / IDE 自动刷新了本地 Signing Config，就把它改成本机绝对路径，或只替换其中的 `storePassword` / `keyPassword`
- [ohos/build-profile.json5](./ohos/build-profile.json5) 里的 `storePassword` / `keyPassword` 不是随便一段字符串，也不是“谁本机能编过就提交谁的”；它们和本机 `ohos/sign/material` 解密材料是一一对应的。只改这两个密文、却不保证配套材料一致，会直接导致其他机器在 `SignHap` 阶段报 `Signature material verification failed`
- [ohos/sign/debug-profile.json](./ohos/sign/debug-profile.json) 现在作为“共享调试 profile 基线文件”提交到仓库，用来保证 bundle name 与仓库内应用配置保持一致，并作为本地设备绑定 profile 的生成基线
- `ohos/local.properties` 仍然是本地文件，不进仓库；它由 `scripts/flutter-ohos.ps1 -Mode init` 按当前机器的 DevEco SDK、Node.js 和项目内 OHOS Flutter 路径自动生成 / 校正
- `ohos/sign/` 目录下其余证书、签名链、`p7b`、`cer`、设备绑定 profile 等内容，仍然属于本地生成物，不要提交

Harmony 签名协作时，额外遵守下面这组硬规则：

- 新机器、切换 DevEco / SDK、或本地签名突然异常后，先执行一次 `powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode init`
- 如果只是为了恢复本机 DevEco 一键编译 / 运行，不要手改 [ohos/build-profile.json5](./ohos/build-profile.json5) 里的密文，更不要把 IDE 自动写入的本机绝对路径提交进仓库
- 如果 [ohos/build-profile.json5](./ohos/build-profile.json5) 的 diff 只体现为 `storePassword` / `keyPassword` 变化，或 `storeFile` / `profile` / `certpath` 变成了 `C:\Users\...` 之类本机路径，默认把它视为本地环境噪音，不要提交
- 如果确实要调整共享签名基线，必须把“为什么要改、改了哪些成套材料、如何验证”的说明一起补进提交说明或评审说明，不能只提交一份孤立的 [ohos/build-profile.json5](./ohos/build-profile.json5) 密文变化
- 任何涉及 [ohos/build-profile.json5](./ohos/build-profile.json5) 的改动，提交前至少执行一次 `powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode build -TargetPlatform x64`，确认不是只在当前 IDE 表面可见、而是命令行签名链路也真实可用

你在 `ohos` 子工程里通常会看到：

- HarmonyOS 真机
- HarmonyOS 虚拟机

你在 `ohos` 子工程里不一定会像根工程那样完整显示 Flutter 设备列表，这是 DevEco 和普通 Flutter IDE 的识别方式差异，不是仓库坏了。

## 常用命令

以下命令默认都在项目根目录 `.` 执行。

### Android

Windows PowerShell：

```powershell
# 构建 Android release arm64 安装包
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode build -BuildMode release -TargetPlatform arm64

# 构建同时兼容 32 位和 64 位真机的 release 安装包
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode build -BuildMode release -TargetPlatform arm64+arm

# 调试 Android 真机
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode run -BuildMode debug -TargetPlatform arm64 -DeviceId <adb-device-id>

# 调试 Android 模拟器
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode run -BuildMode debug -TargetPlatform x64 -DeviceId <adb-device-id>

# 安装到指定 Android 设备
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode install -BuildMode release -TargetPlatform arm64 -DeviceId <adb-device-id>
```

macOS 终端：

```bash
# 先同步官方 Flutter 依赖
flutter pub get

# 构建 Android release arm64 安装包
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons

# 构建同时兼容 32 位和 64 位真机的 release 安装包
flutter build apk --release --target-platform android-arm,android-arm64 --no-tree-shake-icons

# 安装 arm64 release 包到指定 Android 设备
adb -s <adb-device-id> install -r build/app/outputs/flutter-apk/app-release.apk

# 调试 Android 真机 / 模拟器
flutter run --debug -d <adb-device-id>
```

说明：

- `arm64`：大多数 64 位 Android 真机
- `arm`：较老的 32 位 Android 真机
- `arm64+arm`：同时兼容 32 位和 64 位真机，适合本地手动发包
- `x64`：Android 模拟器
- 如果本机同时连了多台设备，建议显式传 `-DeviceId`
- release 构建统一要求使用正式签名；如果 [android/key.properties](./android/key.properties) 或 [android/signing/pet-release.jks](./android/signing/) 未准备完成，构建会直接失败，不再回退到 debug 签名
- 上面的 macOS `flutter build apk` 默认产物是 `build/app/outputs/flutter-apk/app-release.apk`
- 如果你要单独产出 `app-arm64-v8a-release.apk` 这类按 ABI 拆分的包，请执行 `flutter build apk --release --target-platform android-arm64 --split-per-abi`
- macOS 上默认按上面的终端命令执行
- 直接走原生命令时，不会自动帮你切换 / 恢复共享 Flutter 状态；执行前请确认仓库根目录当前处于 `official` 状态

#### Android release 签名统一方案

Android release 安装包现在统一走同一套本地忽略文件：

- [android/key.properties](./android/key.properties)
- `android/signing/pet-release.jks`

这两个文件都不要手写、不要提交，统一通过签名脚本生成。
任何 Android keystore 原件都不能放进仓库历史，包括根目录 `pet-release.jks`、`*.jks`、`*.keystore`、`*.p12`、`*.pfx` 等文件；如果需要交给协作同事或 GitHub Actions，只能通过线下安全渠道或 GitHub Secrets 传递。

如果旧正式签名已经丢失，需要直接重建一套新的 Android 正式签名，可在项目根目录执行：

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create-android-signing.ps1
```

macOS / Linux 终端：

```bash
bash ./scripts/create-android-signing.sh
```

默认行为：

- Windows 默认在 `%USERPROFILE%\.petnote-signing\pet-release.jks` 生成新的正式 keystore 原件
- Windows 默认在 `%USERPROFILE%\.petnote-signing\pet-release.summary.json` 生成本次 keystore 的摘要信息
- macOS / Linux 默认在 `$HOME/.petnote-signing/pet-release.jks` 生成新的正式 keystore 原件
- macOS / Linux 默认在 `$HOME/.petnote-signing/pet-release.summary.json` 生成本次 keystore 的摘要信息
- 自动把签名接入当前仓库的 [android/key.properties](./android/key.properties) 和 `android/signing/pet-release.jks`

如果你想自定义 keystore 存放目录、alias 或密码，可以显式传参：

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create-android-signing.ps1 `
  -OutputDirectory 'D:\secure\petnote' `
  -Alias 'petnote_release'
```

macOS / Linux 终端：

```bash
bash ./scripts/create-android-signing.sh \
  --output-directory "$HOME/.petnote-signing" \
  --alias 'petnote_release'
```

生成完新的正式签名后，再交给协作同事和 GitHub Actions 继续复用。

本机或协作同事拿到同一份 keystore 后，在项目根目录执行：

Windows PowerShell：

```powershell
$env:ANDROID_KEYSTORE_FILE="$env:USERPROFILE\.petnote-signing\pet-release.jks"
$env:ANDROID_KEYSTORE_PASSWORD='<store-password>'
$env:ANDROID_KEY_ALIAS='<key-alias>'
$env:ANDROID_KEY_PASSWORD='<key-password>'
powershell -ExecutionPolicy Bypass -File .\scripts\prepare-android-signing.ps1
```

macOS / Linux 终端：

```bash
export ANDROID_KEYSTORE_FILE="$HOME/.petnote-signing/pet-release.jks"
export ANDROID_KEYSTORE_PASSWORD='<store-password>'
export ANDROID_KEY_ALIAS='<key-alias>'
export ANDROID_KEY_PASSWORD='<key-password>'
bash ./scripts/prepare-android-signing.sh
```

说明：

- `ANDROID_KEYSTORE_FILE` 指向你本机保存的正式 keystore 原文件，脚本会把它复制到仓库忽略目录 `android/signing/pet-release.jks`
- 生成完成后，本机 Android Studio、`flutter build apk --release`、以及 [scripts/flutter-android.ps1](./scripts/flutter-android.ps1) 都会复用同一份正式签名
- 协作开发同事只需要拿到同一份 keystore 和对应密码 / alias，按同样步骤执行一次即可
- 如果是新重建的签名，从这一刻起所有 Android release 包都必须统一切到这份新 keystore；旧签名安装包无法直接覆盖升级
- macOS / Linux 当前可直接使用 [scripts/create-android-signing.sh](./scripts/create-android-signing.sh) 和 [scripts/prepare-android-signing.sh](./scripts/prepare-android-signing.sh)，不依赖 PowerShell 7

GitHub Actions 自动构建也复用同一套字段，只是把 keystore 文件改成 Base64 Secret：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

如果你需要把本地 `pet-release.jks` 转成 GitHub Secret 可用的 Base64，可以在 PowerShell 执行：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.petnote-signing\pet-release.jks"))
```

macOS / Linux 终端可以执行：

```bash
base64 < "$HOME/.petnote-signing/pet-release.jks" | tr -d '\n'
```

当前仓库里的 [`.github/workflows/release.yml`](./.github/workflows/release.yml) 会直接调用同一个 [scripts/prepare-android-signing.ps1](./scripts/prepare-android-signing.ps1)，确保“本机、协作开发、GitHub Actions”三条链路最终落到同一份 `android/key.properties` 结构和同一个 keystore 相对路径上。

GitHub Actions 的发布配置由根目录 [release.yml](./release.yml) 控制：

- `android.enabled=true` 时会按 `android.artifacts` 声明的 ABI 构建 Android APK
- `ios.enabled=true` 且 `ios.artifacts` 包含 `unsigned-ipa` 时，会在 macOS 26 runner 上执行 `flutter build ios --release --no-codesign` 并打包未签名 IPA
- iOS 图标使用 Xcode Icon Composer 的 `PetNote.icon`，GitHub Actions 也必须使用支持该格式的 Xcode 26+ 环境，不能为了 CI 兼容性改回传统 `AppIcon.appiconset`
- 未签名 IPA 不需要 Apple 证书、provisioning profile 或 GitHub Secrets，但产物仍需自行签名后才能安装到真机或分发
- main / beta 分支发布到 GitHub Release 时，APK 和 IPA 会一起出现在“版本选择”区块；其他分支只上传 Actions artifacts

### iOS

Windows PowerShell：

```powershell
# 仅同步官方 Flutter 依赖状态
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ios.ps1 -Mode prepare
```

macOS 终端：

```bash
# 先同步官方 Flutter 依赖
flutter pub get

# 安装 / 刷新 Pods
cd ios && pod install && cd ..

# 构建 iOS debug 包（不签名）
flutter build ios --debug --no-codesign --no-tree-shake-icons

# 构建 iOS 模拟器 debug 包
flutter build ios --simulator --debug

# 安装到当前已启动的 iOS 模拟器
xcrun simctl install booted build/ios/iphonesimulator/Runner.app

# 构建未签名 release App
flutter build ios --release --no-codesign

# 直接运行到指定 iPhone / 模拟器
flutter run --debug -d <device-id>
```

说明：

- Windows 上只能做 `prepare`
- 真正的 iOS 构建和运行必须在 macOS + Xcode + CocoaPods 环境完成
- 本机可用环境至少应满足：`xcode-select -p` 正常返回、`pod` 可执行、`flutter doctor` 的 iOS toolchain 为绿色
- macOS 上默认按上面的终端命令执行
- 如果你要安装到模拟器，先确保已经启动至少一个 iOS 模拟器；`xcrun simctl install booted ...` 和 [scripts/post-build-macos.sh](./scripts/post-build-macos.sh) 都依赖这个前提
- 如果你想串行完成“模拟器构建并安装 + 未签名 IPA + arm64-v8a APK”，可以在仓库根目录执行 [scripts/post-build-macos.sh](./scripts/post-build-macos.sh)
- 这个脚本会严格串行跑 `ios simulator debug -> simctl install -> ios release --no-codesign -> unsigned ipa -> android arm64-v8a apk`，避免多个 Flutter / Xcode build 互相抢锁
- 当前仓库生成的 `.ipa` 是未签名包，默认产物路径是 `build/ios/Runner-unsigned.ipa`
- 直接走原生命令时，不会自动帮你切换 / 恢复共享 Flutter 状态；执行前请确认仓库根目录当前处于 `official` 状态

### HarmonyOS

Windows PowerShell：

```powershell
# 新机器首次初始化 Harmony 本地环境
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode init

# 跑测试
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode test

# 构建 x64 模拟器 HAP
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode build -TargetPlatform x64

# 构建 arm64 真机 HAP
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode build -TargetPlatform arm64

# 安装到 Harmony 虚拟机
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode install -TargetPlatform x64 -DeviceId 127.0.0.1:5555

# 构建、安装并启动 Harmony 虚拟机
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode run -TargetPlatform x64 -DeviceId 127.0.0.1:5555

# 构建、安装并启动 Harmony 真机
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode run -TargetPlatform arm64 -DeviceId <hdc-device-id>
```

如果你的 DevEco Studio、SDK 或 OpenHarmony toolchains 不在默认安装路径，先在当前终端设置 `DEVECO_HOME`、`DEVECO_SDK_HOME` 或 `HARMONY_TOOLCHAIN_HOME`，再执行上面的 `-Mode init`。

macOS 终端：

当前仓库没有提供经过验证的 macOS Harmony PowerShell 脚本，但可以直接用 DevEco Studio 自带的命令行工具在默认终端里做构建。先准备环境变量：

```bash
# DevEco Studio 默认安装目录
export DEVECO_HOME="/Applications/DevEco-Studio.app/Contents"
export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export HARMONY_TOOLCHAIN_HOME="$DEVECO_SDK_HOME/default/openharmony/toolchains"

# 命令行工具加入 PATH
export PATH="$DEVECO_HOME/tools/ohpm/bin:$DEVECO_HOME/tools/hvigor/bin:$DEVECO_HOME/tools/node/bin:$HARMONY_TOOLCHAIN_HOME:$PATH"
```

构建命令：

```bash
# 进入 Harmony 工程
cd ./ohos

# 安装 / 刷新 OHPM 依赖
ohpm install --all

# 构建 debug HAP
hvigorw assembleHap -p product=default -p buildMode=debug --no-daemon

# 构建 release HAP
hvigorw assembleHap -p product=default -p buildMode=release --no-daemon

# 产物通常位于这个目录，常见文件名包括 entry-default-signed.hap 或 entry-default-unsigned.hap
ls ./entry/build/default/outputs/default/
```

如果你已经连上 Harmony 真机或启动了 Harmony 模拟器，也可以继续在终端里安装：

```bash
# 查看设备
hdc list targets

# 按实际产物文件名安装 HAP 到指定设备
hdc -t <hdc-device-id> install -r ./entry/build/default/outputs/default/<your-hap-file>.hap
```

如果你的 DevEco SDK 版本不是 `default/openharmony` 这一套，或者终端里仍然找不到 `hdc`，先执行一次：

```bash
find "$DEVECO_HOME/sdk" -name hdc
```

把查到的 `hdc` 所在目录补进 `PATH` 后再继续。

如果你更习惯 IDE，也可以从终端直接打开 DevEco Studio：

```bash
cd ./ohos

# 从终端打开 DevEco Studio
open -a "DevEco Studio" .
```

随后在 DevEco Studio 中：

1. 安装 DevEco Studio for Mac，并在 SDK Manager 里装好 HarmonyOS / OpenHarmony SDK、toolchains、模拟器或真机调试组件
2. 打开 [ohos](./ohos)
3. 等待工程索引和依赖同步完成
4. 在运行配置里选择 `entry`
5. 连接 Harmony 真机或启动 Harmony 模拟器
6. 点击 DevEco 的运行按钮直接编译并运行

如果只想在 DevEco 里做一次纯构建，不直接启动设备，也可以：

1. 打开 [ohos](./ohos)
2. 选中 `entry`
3. 执行 DevEco 的 Build / Make Project
4. 让 IDE 直接产出对应 HAP

说明：

- 这套 macOS 场景依赖 DevEco Studio 自带的 `ohpm`、`hvigorw`、`node` 和 `hdc`
- `hvigorw assembleHap` 是当前 OHOS Flutter 工具链实际使用的构建入口；这里补的是默认终端等价命令，不是把 Windows PowerShell 脚本直接搬到 mac 上
- 如果你要复用仓库内那套自动签名、自动切 Flutter 状态、自动恢复状态的完整流程，仍然优先使用 Windows + [scripts/flutter-ohos.ps1](./scripts/flutter-ohos.ps1)

说明：

- Harmony 模拟器通常使用 `x64`
- Harmony 真机通常使用 `arm64`
- Harmony 命令行脚本当前按 Windows + DevEco Studio 工具链编写，建议只在 Windows 上执行
- macOS 可走 DevEco Studio 一键编译 / 运行，也可以走上面的 `ohpm + hvigorw` 终端构建命令
- Windows 新机器第一次使用 Harmony / DevEco 前，先执行一次 `powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode init`
- 脚本会自动处理本地调试签名
- `-Mode init` 会自动生成 / 校正本机的 [ohos/local.properties](./ohos/local.properties)，并固定让 Harmony 继续使用项目内 OHOS Flutter，不会把 Android / iOS 切到 OHOS Flutter
- 脚本也会自动校验仓库内 hvigor 插件副本，避免 IDE / hvigor 误读根目录的官方 Flutter `package_config`
- DevEco 直跑链路也会做同样的状态隔离，不需要额外手动切 Flutter SDK

## 依赖状态管理

仓库里有两套本地状态快照：

- `official`：给 Android + iOS
- `ohos`：给 HarmonyOS

状态管理脚本是 [scripts/flutter-state.ps1](./scripts/flutter-state.ps1)，它会维护这些文件：

- [pubspec.lock](./pubspec.lock)
- `.flutter-plugins`
- `.flutter-plugins-dependencies`
- `.dart_tool/package_config.json`
- `.dart_tool/package_config_subset`
- `.dart_tool/package_graph.json`
- `.dart_tool/version`
- [android/local.properties](./android/local.properties)
- [ohos/local.properties](./ohos/local.properties)

结论很简单：

- 不要在 `official` 和 `ohos` 两套 SDK 状态之间混用裸 `flutter pub get`
- 需要哪一端，就走哪一端脚本
- 如果你在 macOS 上按 README 直接执行 Android / iOS 原生命令，这属于“明确留在 official 状态下”的例外场景
- Harmony 构建完后，根目录会恢复成官方 Flutter 状态，这是设计如此，不是状态错乱
- DevEco 直跑 Harmony 时，也会先备份根目录共享生成物，再切到 OHOS 状态，结束后恢复

## OHOS Hvigor 插件归属

- [`tooling/ohos-hvigor-plugin`](./tooling/ohos-hvigor-plugin) 是仓库内自管的 OHOS hvigor 插件副本。
- [ohos/hvigorfile.ts](./ohos/hvigorfile.ts) 和 [ohos/hvigorconfig.ts](./ohos/hvigorconfig.ts) 会直接相对导入这份仓库内副本。
- 不再直接修改 OHOS Flutter 子模块里的 hvigor 插件源码。
- [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 仍然只是 OHOS Flutter SDK 子模块，不承载项目本地业务定制。

这样做的原因很明确：

- upstream 子模块仓库不是我们的，不能依赖向上游提交本地定制。
- 如果把关键行为建立在子模块脏改动上，`git status` 会长期脏，而且新机器难以复现。
- 把 hvigor 插件副本收回主仓库后，DevEco 直跑能力才能随主仓库一起提交、评审和同步。
- upstream Flutter 工具偶尔会重写 `ohos/package.json` 和 `ohos/node_modules`，但那只是本地生成物；真正决定 DevEco 入口的是 [ohos/hvigorfile.ts](./ohos/hvigorfile.ts) 和 [ohos/hvigorconfig.ts](./ohos/hvigorconfig.ts)。

升级注意事项：

- 升级 [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 时，不要直接在子模块里手改 hvigor 插件源码。
- 应该对照 upstream 的 hvigor 插件变更，再同步更新 [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)。
- 提交前确认 [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 没有本地脏改动。

## 提交规范

建议提交：

- 共享业务代码改动
- Android / iOS / Harmony 平台代码改动
- 脚本改动
- [`.gitmodules`](./.gitmodules)
- [README.md](./README.md)
- [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)
- [tooling/ohos-flutter/flutter-hvigor-plugin.patch](./tooling/ohos-flutter/flutter-hvigor-plugin.patch)
- 子模块指针 [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 的版本更新

不要提交：

- `.tooling/flutter-state/`
- `.dart_tool/`
- `.flutter-plugins`
- `.flutter-plugins-dependencies`
- `*.iml`、`.idea/`、`.vscode/` 等 IDE 本地工程状态
- `ohos/.idea/` 本地 IDE 状态文件
- `ohos/node_modules/`
- `ohos/oh_modules/`
- `ohos/sign/` 下除 [ohos/sign/debug-profile.json](./ohos/sign/debug-profile.json) 之外的任何文件，包括证书、签名链、`p7b`、`cer`、`p12`、设备绑定 profile、本机签名材料和临时辅助脚本
- `.signing-temp/`
- `android/key.properties`
- `android/signing/`
- 根目录或任意子目录下的 Android keystore / 证书原件，例如 `pet-release.jks`、`*.jks`、`*.keystore`、`*.p12`、`*.pfx`
- 构建产物目录

特别注意：

- 如果 [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode) 在主仓库里显示为 `dirty`，先清掉子模块内部的本地改动再提主仓库。
- 根目录 [pubspec.lock](./pubspec.lock) 提交前应保持“官方 Flutter 默认状态”。
- 如果需要改 DevEco 直跑逻辑，请优先改 [tooling/ohos-hvigor-plugin](./tooling/ohos-hvigor-plugin)，不要去改子模块里的 upstream hvigor 插件源码。
- 如果确实需要共享 Harmony 签名辅助脚本，不要放在 `ohos/sign/` 下，应放到 [scripts](./scripts) 或其他受控源码目录，并在 README 中说明用途和验证方式。
- 如果 diff 里出现 [ohos/build-profile.json5](./ohos/build-profile.json5)，先肉眼检查是否只改了 `storePassword` / `keyPassword` 或签名文件路径；这类改动默认不该提交，除非你正在做一次经过验证的共享签名基线升级。
- 不要把“本机能在 DevEco 里点运行”当成 [ohos/build-profile.json5](./ohos/build-profile.json5) 可提交的依据；必须以脚本构建通过为准，再决定是否允许进入评审。

## 团队协作建议

三个人协作时，推荐按“两条工具链 + 共享层”分工，而不是按三个平台硬切。

- 1 人主看共享业务层：
  - [lib](./lib)
  - [test](./test)
- 1 人主看官方 Flutter 平台层：
  - [android](./android)
  - [ios](./ios)
- 1 人主看 Harmony 平台层：
  - [ohos](./ohos)
  - [`.flutter_ohos_sdk_gitcode`](./.flutter_ohos_sdk_gitcode)

提交前最低验证建议：

- 共享层改动：至少验证 Android 和 Harmony
- Android 平台改动：跑一次 [scripts/flutter-android.ps1](./scripts/flutter-android.ps1)
- iOS 平台改动：在 macOS 上跑一次 [scripts/post-build-macos.sh](./scripts/post-build-macos.sh) 或至少完成一遍 iOS 原生命令链
- Harmony 平台改动：跑一次 [scripts/flutter-ohos.ps1](./scripts/flutter-ohos.ps1)

## 常见误区

- “为什么根工程设备列表里没有鸿蒙虚拟机？”
  因为根工程走的是官方 Flutter，不会列出 OHOS 设备。
- “为什么跑完 Harmony 脚本后，根目录又变回官方 Flutter 了？”
  因为这正是分流设计，避免影响 Android / iOS。
- “为什么 DevEco 现在可以直接运行了？”
  因为 hvigor 插件会在构建前自动备份共享状态、切换到 OHOS Flutter、必要时刷新 `package_config`，构建后再恢复。
- “为什么 DevEco 运行前有时仍然建议先跑一次 Harmony 脚本？”
  因为脚本会顺手完成子模块初始化、本机 `ohos/local.properties` 校正、签名修复和 hvigor 补丁兜底，适合首次拉仓库或本地环境刚变化之后使用。
- “为什么 `GeneratedPluginRegistrant.ets` 偶发报 `Cannot find module 'url_launcher_harmonyos'`？”
  这通常是 DevEco / hvigor daemon 或 ArkTS / OHPM 增量缓存还在使用旧依赖图。先在 [ohos](./ohos) 下执行 `./hvigorw.bat --stop-daemon` 后重试；如果仍失败，再删除本地生成的 `ohos/.hvigor`、`ohos/entry/build`、`ohos/oh_modules` 后重新执行 `./hvigorw.bat assembleHap --stacktrace`。这些目录都是本地生成物，不要提交。
- “为什么我只改了 `ohos/build-profile.json5` 里的密文，自己机器能跑，别人却在 `SignHap` 报 `Signature material verification failed`？”
  因为这两个密文和本机 `ohos/sign/material` 是配套关系，不是通用密码。只提密文、不带成套材料，其他机器大概率无法解密通过；这种 diff 默认应视为本地签名噪音，而不是共享改动。
- “为什么不要直接把 OHOS Flutter SDK 当普通目录提交？”
  因为体积太大，而且不利于升级和团队同步，子模块更可控。
