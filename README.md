# Pet Care Harmony

宠物照护管理 Flutter HarmonyOS 工程。

## 当前结构

- 根目录是 Flutter 主工程：
  - [pubspec.yaml](/F:/HarmonyProject/Pet/pubspec.yaml)
  - [lib/main.dart](/F:/HarmonyProject/Pet/lib/main.dart)
  - [test](/F:/HarmonyProject/Pet/test)
- HarmonyOS 平台工程位于：
  - [ohos](/F:/HarmonyProject/Pet/ohos)
- 旧 ArkUI 根工程已禁用归档到：
  - [\.legacy_arkui_disabled](/F:/HarmonyProject/Pet/.legacy_arkui_disabled)

## 运行

推荐直接使用脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode run -TargetPlatform x64 -DeviceId 127.0.0.1:5555
```

常用命令：

```powershell
# 运行测试
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode test

# 构建 x64 模拟器包
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode build -TargetPlatform x64

# 构建并安装到设备
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode install -TargetPlatform x64 -DeviceId 127.0.0.1:5555

# 构建、安装并启动
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-ohos.ps1 -Mode run -TargetPlatform x64 -DeviceId 127.0.0.1:5555
```

## 说明

- `flutter build hap` 会先产出 unsigned hap，然后脚本会自动补做本地调试签名。
- HarmonyOS 模拟器通常使用 `x64`，真机通常使用 `arm64`。
- 如果你在 DevEco 里打开根目录，默认应看到 Flutter 的 `main.dart` 运行配置，而不是旧 ArkUI 的 `entry`。
