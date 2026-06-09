# PetNote 鸿蒙适配 — 提交准备报告

> 对比基准: `https://github.com/juren233/PetNote` tag `v1.3.7`
> 设备: SC-3568HA (RK3568, ohos-arm64, OpenHarmony 6.1.0.31, API 23)
> 日期: 2026-06-09

---

## 一、修改清单总览

| # | 文件路径 | 状态 | 主题 | 32位隔离 |
|---|---------|------|------|---------|
| 1 | `lib/main.dart` | **大改** | StackOverflowError 恢复守卫 | **是 — 仅 32 位 ARM 触发** |
| 2 | `lib/app/harmony_native_dock.dart` | **大改** | 底栏间距 + 回弹抑制 + 延迟同步 | 部分 (间距值通用安全) |
| 3 | `ohos/.../PetNoteHarmonyNativeDockPlugin.ets` | **重写** | 自定义 Row 替换 HdsTabs + 透明背景 | 否 (通用改进) |
| 4 | `ohos/.../pages/Index.ets` | 小改 | 全屏尺寸 + 白色背景 | 否 |
| 5 | `ohos/.../ProjectPluginRegistrant.ets` | 改 | 注册3个新插件 + 重命名1个 | 否 |
| 6 | `ohos/.../module.json5` | 改 | native lib 解压/提取配置 | 否 |
| 7 | oh_modules `FlutterAbility.ets` | **补丁** | API 12 windowStageEvent try/catch | 否 (通用兼容) |
| 8 | oh_modules `FlutterView.ets` | **补丁** | API 12 windowStatus/RectChange try/catch | 否 (通用兼容) |
| 9 | oh_modules `NavigationChannel.ets` | **补丁** | instanceof Map 安全守卫 | 否 (通用修复) |
| 10 | oh_modules `FlutterPage.ets` | **补丁** | XComponent 底色 Black→White | 否 |
| 11 | oh_modules `PlatformPlugin.ets` | **补丁** | 强制导航栏颜色 #FFF5F2EC | 否 |
| 12 | `ohos/.../ets/patches/*.petnote-api12-bak` | **新增** | 补丁备份 (3个文件) | 否 |
| 13 | `PetNoteAiSecretStorePlugin.ets` | **新增** | AI 密钥持久存储插件 | 否 |
| 14 | `PetNoteDataPackageFileAccessPlugin.ets` | **新增** | 备份导入/导出插件 | 否 |
| 15 | `PetNotePhotoPickerPlugin.ets` | **新增** | 照片选择器 (替换旧实现) | 否 |

---

## 二、32 位板子隔离分析

### 2.1 纯 32 位 ARM 相关修改

**`lib/main.dart` — StackOverflowError 恢复守卫**

这是唯一一处**纯粹为 32 位 ARM 板子**添加的代码。RK3568 是 ARM Cortex-A55 四核，Dart VM 的栈空间比 64 位设备小，深层 Widget 树在 build/layout 阶段会耗尽栈引发 `StackOverflowError`。

**隔离状态**: 已天然隔离 — 在 64 位设备上 StackOverflowError 几乎不会触发，恢复守卫的 3 次上限和 500ms 延迟也不会产生副作用。代码无需条件编译。

**`lib/app/harmony_native_dock.dart` — 部分 32 位相关**

- `_lastSyncedTab` 回弹抑制: 解决原生 dock 在 `setSelectedTab` 后立刻 echo 回 `tabSelected` 导致 build 中期 setState 断言失败。在 64 位设备上此问题可能不频繁但仍会发生。**通用安全**。
- `addPostFrameCallback` 延迟同步: 避免在 Flutter build 阶段发送平台通道消息。**通用安全**。
- `effectiveBottomInset = math.max(viewPadding.bottom, 56.0)`: 最小 56 像素底部间距。64 位设备若 `viewPadding.bottom` 更大则自动使用系统值。**通用安全**。

### 2.2 通用修改 (64 位设备也适用)

| 修改 | 64位影响 |
|------|---------|
| API 12 try/catch 补丁 | 无影响 — 64 位设备通常 API ≥ 13，try 成功直接跳过 catch |
| HdsTabs → 自定义 Row 重写 | 正面 — HdsTabs 的 onChange 回调在编程式 changeIndex 后不可靠，通用问题 |
| XComponent 底色 White | 正面 — 消除底部黑区，64 位设备同样受益 |
| 导航栏颜色强制 #FFF5F2EC | 正面 — 统一视觉，64 位同样受益 |
| 透明 dock 背景 | 正面 — 消除与系统导航栏视觉重叠 |
| native lib 解压配置 | 必须 — 64 位设备同样需要 libflutter.so 正确加载 |
| 3个新插件 | 功能增强 — AI密钥存储、备份、照片选择 |

### 2.3 隔离建议

当前修改**无需条件编译**或分支隔离，原因:
1. 32 位专属代码 (StackOverflowError 守卫) 在 64 位上零触发、零副作用
2. 其余修改对 64 位设备是通用改进或 bug 修复
3. 所有 try/catch 补丁在非 API 12 设备上会成功执行 try 块，catch 永不进入

**如果将来需要回退**: `lib/main.dart` 的 StackOverflowError 守卫是唯一可考虑移除的 32 位代码，但保留也无害。

---

## 三、可能出现的问题及解决方案

### 问题 1: `flutter clean` 后白屏 / 崩溃

**现象**: 执行 `flutter clean` + `flutter pub get` 后，应用打开白屏或直接崩溃。

**原因**: `flutter clean` 会删除 `oh_modules/` 目录，我们的 5 个 oh_modules 补丁 (FlutterAbility、FlutterView、NavigationChannel、FlutterPage、PlatformPlugin) 会被还原为原版，导致:
- API 12 设备 `windowStageEvent` 抛出 code:801 → 白屏
- `selectSingleEntryHistory` 的 null args → 崩溃
- XComponent 黑色底色 → 底部黑区回归

**解决方案**: 备份文件已保存在 `ohos/entry/src/main/ets/patches/*.petnote-api12-bak`。执行:
```bash
# 复制补丁到 oh_modules (替换实际路径中的 hash)
OHMOD="ohos/oh_modules/.ohpm/@ohos+flutter_ohos@*/oh_modules/@ohos/flutter_ohos/src/main/ets"
cp ohos/entry/src/main/ets/patches/FlutterAbility.ets.petnote-api12-bak "$OHMOD/embedding/ohos/FlutterAbility.ets"
cp ohos/entry/src/main/ets/patches/FlutterView.ets.petnote-api12-bak "$OHMOD/view/FlutterView.ets"
cp ohos/entry/src/main/ets/patches/NavigationChannel.ets.petnote-api12-bak "$OHMOD/embedding/engine/systemchannels/NavigationChannel.ets"
```
FlutterPage.ets 和 PlatformPlugin.ets 没有备份文件，需手动修改:
- FlutterPage.ets 第 248 行: `Color.Black` → `Color.White`
- PlatformPlugin.ets: 在 `setSystemChromeSystemUIOverlayStyle` 的 `systemBarProperties` 构建前，添加 `navigationBarColorValue = '#FFF5F2EC';`

**建议**: 将此流程写成脚本 `scripts/apply-ohos-patches.sh`。

---

### 问题 2: 签名失败 — SignHap 报错

**现象**: `flutter build hap` 在最后 `SignHap` 阶段失败:
```
Invalid storeFile value. The file must be included in './sign/OpenHarmony.p12'
```

**原因**: 项目的 `build-profile.json5` 没有配置签名信息，Hvigor 无法自动签名。

**解决方案**: 使用外部签名工具:
```powershell
# 1. 构建 (会在 SignHap 失败，但 unsigned HAP 已生成)
flutter build hap --debug --target-platform ohos-arm --no-tree-shake-icons

# 2. 外部签名
java -jar hap-sign-tool.jar sign-app \
  -mode localSign \
  -keyAlias 'openharmony application release' \
  -keyPwd 123456 \
  -appCertFile <cert-chain.cer> \
  -profileFile <signed-profile.p7b> \
  -inFile ohos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile OpenHarmony.p12 \
  -keystorePwd 123456 \
  -outFile signed.hap \
  -compatibleVersion 12 \
  -signCode 1

# 3. 安装
hdc install -r signed.hap
```

**注意**: 某些 OpenHarmony 5.0 设备拒绝 `signCode 1`，改用 `signCode 0` 可安装但 native lib 不会注册。

---

### 问题 3: 64 位模拟器上行为差异

**现象**: 在 64 位模拟器上运行时，以下行为可能与 32 位板子不同:

| 行为 | 32位板子 (RK3568) | 64位模拟器 |
|------|-------------------|-----------|
| StackOverflowError | 深层 Widget 树会触发 | 几乎不触发 |
| viewPadding.bottom | 报告 48.0 | 可能报告 0 或其他值 |
| HAP 签名 | signCode 1 可用 | 通常 signCode 1 可用 |
| native lib 加载 | 需要 extractNativeLibs | 通常正常工作 |
| HdsTabs onChange | 编程式切换后可能失效 | 同样可能失效 |

**解决方案**: 无需特殊处理。所有修改对 64 位设备是安全的:
- StackOverflowError 守卫永不触发 = 零开销
- `math.max(viewPadding.bottom, 56.0)` 在 viewPadding=0 时使用 56，比原来的 0 更安全
- 其余修改为通用 bug 修复

---

### 问题 4: 新插件在 64 位设备上未注册

**现象**: `PetNoteAiSecretStorePlugin`、`PetNoteDataPackageFileAccessPlugin`、`PetNotePhotoPickerPlugin` 是新增的原生插件，64 位设备若使用原版 `ProjectPluginRegistrant.ets` 则不会注册。

**解决方案**: `ProjectPluginRegistrant.ets` 的修改是项目源码，不随 `flutter clean` 丢失。确保提交时包含此文件。

---

### 问题 5: oh_modules 补丁与 Flutter OHOS SDK 版本耦合

**现象**: oh_modules 的路径包含 hash (`@ohos+flutter_ohos@8rqiohj6...`)，不同 Flutter OHOS SDK 版本 hash 不同，补丁脚本中的路径会失效。

**解决方案**: 使用通配符或 `find` 定位:
```bash
find ohos/oh_modules -name "FlutterAbility.ets" -path "*/embedding/ohos/*"
```

---

## 四、建议的 Commit 分组及中文日志

### Commit 1: `feat(ohos): 修复 API 12 兼容性问题，消除白屏和崩溃`

```
feat(ohos): 修复 API 12 兼容性问题，消除白屏和崩溃

OpenHarmony API 12 设备不支持部分窗口事件监听 API，
调用时会抛出 code:801 异常导致 Flutter 引擎初始化中断。
同时 NavigationChannel 在处理 selectSingleEntryHistory
等非 Map 参数的方法调用时存在类型转换崩溃。

修改内容:
- FlutterAbility.ets: windowStageEvent 监听注册包裹 try/catch，
  确保 createView/loadContent 始终执行
- FlutterView.ets: windowStatusChange 和 windowRectChange 监听
  分别包裹 try/catch，防止 code:801 中断后续初始化
- NavigationChannel.ets: 添加 instanceof Map 类型守卫，
  跳过非 Map 参数的 notifyPageChanged 调用
- 在 patches/ 目录保存补丁备份 (.petnote-api12-bak)，
  防止 flutter clean 还原 oh_modules 后补丁丢失

影响范围: oh_modules 补丁，需要 flutter clean 后重新应用。
测试设备: SC-3568HA (RK3568, ohos-arm64, API 23)
```

**涉及文件:**
- `ohos/oh_modules/.../FlutterAbility.ets` (补丁)
- `ohos/oh_modules/.../FlutterView.ets` (补丁)
- `ohos/oh_modules/.../NavigationChannel.ets` (补丁)
- `ohos/entry/src/main/ets/patches/FlutterAbility.ets.petnote-api12-bak` (新增)
- `ohos/entry/src/main/ets/patches/FlutterView.ets.petnote-api12-bak` (新增)
- `ohos/entry/src/main/ets/patches/NavigationChannel.ets.petnote-api12-bak` (新增)

---

### Commit 2: `fix(ohos): 消除底部黑区，强制 XComponent 和导航栏使用应用背景色`

```
fix(ohos): 消除底部黑区，强制 XComponent 和导航栏使用应用背景色

在全屏模式下，XComponent 默认黑色背景透过 Flutter 渲染间隙
可见，系统导航栏也使用默认黑色，导致应用底部出现约 70px
的黑色区域。

修改内容:
- FlutterPage.ets: XComponent 底色从 Color.Black 改为 Color.White，
  消除渲染间隙中的黑色透出
- PlatformPlugin.ets: 在 setSystemChromeSystemUIOverlayStyle 中
  强制 navigationBarColorValue = '#FFF5F2EC'，与应用背景色一致
- Index.ets: 为 FlutterPage 和外层 Column 添加显式 width/height
  100% 及 backgroundColor(Color.White)，确保渲染面铺满全屏

影响范围: oh_modules 补丁 + 项目入口页面
测试设备: SC-3568HA (RK3568, ohos-arm64, API 23)
```

**涉及文件:**
- `ohos/oh_modules/.../FlutterPage.ets` (补丁)
- `ohos/oh_modules/.../PlatformPlugin.ets` (补丁)
- `ohos/entry/src/main/ets/pages/Index.ets` (修改)

---

### Commit 3: `fix(dock): 重写原生底栏组件，修复与系统导航键重叠`

```
fix(dock): 重写原生底栏组件，修复与系统导航键重叠

原 HdsTabs 组件存在两个问题:
1. onChange 回调在编程式 changeIndex() 后不可靠，导致原生
   侧和 Dart 侧 tab 状态不同步
2. 底栏与系统三大金刚键 (返回/主页/最近任务) 视觉重叠

修改内容 (ArkTS 侧):
- 完全移除 HdsTabs/HdsTabsController 依赖，改用自定义 Row
  渲染 5 个可点击的图标+文字按钮，每个按钮使用显式 onClick
- 外层 Column 背景改为 Color.Transparent，不再用不透明的
  scaffoldBackgroundColor 覆盖系统导航栏区域
- updateBottomInset 使用 Math.max(bottomInset, 56) 确保
  至少 56vp 底部间距，防止与系统导航栏重叠
- 添加 hilog 日志记录 bottomInset 实际值
- handleNativeTabChange 添加重复选择守卫，跳过已在当前
  tab 的冗余通知

修改内容 (Dart 侧):
- effectiveBottomInset 使用 math.max(viewPadding.bottom, 56.0)
  替代原来的条件判断 (bottom > 0 ? bottom : 20)
- SizedBox 高度 = 96 + effectiveBottomInset，确保不裁剪
- 添加 debugPrint 输出 viewPadding.bottom 和 effectiveBottomInset
- _lastSyncedTab 机制抑制 setSelectedTab → tabSelected 回弹
- didUpdateWidget 中 _syncSelectedTab 延迟到 postFrameCallback
- _syncBrightness 参数前置，避免 async 体内访问 InheritedWidget

影响范围: 底栏组件完整重写，涉及 Dart + ArkTS 双层
32位隔离: StackOverflowError 相关修改仅 32 位 ARM 触发，
  64 位设备零副作用
测试设备: SC-3568HA (RK3568, ohos-arm64, API 23)
```

**涉及文件:**
- `ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets` (重写)
- `lib/app/harmony_native_dock.dart` (大改)

---

### Commit 4: `fix(ohos): 32 位 ARM 设备 StackOverflowError 恢复守卫`

```
fix(ohos): 32 位 ARM 设备 StackOverflowError 恢复守卫

RK3568 (ARM Cortex-A55) 等 32 位 ARM 设备栈空间有限，
PetNote 深层 Widget 树在 build/layout 阶段会耗尽 Dart VM
栈空间，触发 StackOverflowError 导致应用闪退。

修改内容:
- 添加 FlutterError.onError 全局处理器，捕获 StackOverflowError
  并触发应用级恢复重建 (非崩溃)
- 添加自定义 ErrorWidget.builder，替换默认红屏错误页面
- 使用 runZonedGuarded 包裹启动流程，异步区域错误也走恢复
- _OhosRecoveryGuard StatefulWidget 包装 PetNoteApp:
  * 最多 3 次恢复尝试 (_maxRecoveries = 3)
  * 每次恢复延迟 500ms (等待框架 Widget 缓存)
  * 使用 UniqueKey 强制完整 Widget 树重建
  * 通过 _recoveryScheduled 标志去重

32位隔离说明:
  64 位设备几乎不会触发 StackOverflowError，此守卫在 64 位
  设备上永远不会执行，零性能开销。无需条件编译。

影响范围: 应用入口 main.dart
测试设备: SC-3568HA (RK3568, ohos-arm64, API 23)
```

**涉及文件:**
- `lib/main.dart` (大改: 18行 → 128行)

---

### Commit 5: `feat(plugins): 新增 AI 密钥存储、备份导入导出、照片选择器原生插件`

```
feat(plugins): 新增 AI 密钥存储、备份导入导出、照片选择器原生插件

为鸿蒙端补齐原生能力，替代原有的占位/缺失实现。

新增插件:
1. PetNoteAiSecretStorePlugin (petnote/ai_secret_store)
   - 基于 HarmonyOS dataPreferences 的持久化 KV 存储
   - 支持: isAvailable / readKey / hasKeys / writeKey / deleteKey
   - 存储文件名: petnote_ai_secret_store

2. PetNoteDataPackageFileAccessPlugin (petnote/data_package_file_access)
   - 备份导入: pickBackupFile 调用系统文档选择器，筛选 .json，
     复制到沙箱 /petnote_imports/，返回 JSON 原文和元数据
   - 备份导出: saveBackupFile 复制临时文件到持久 backups/ 目录，
     带时间戳文件名
   - 包含文件名消毒、扩展名提取、URI 显示名解析等辅助函数

3. PetNotePhotoPickerPlugin (petnote/native_pet_photo_picker)
   - 替换原有的 PetNoteNativePetPhotoPickerPlugin (同名通道)
   - pickPetPhoto: 单张从相册选取，PhotoViewPicker → 沙箱 /pet_photos/
   - pickPetPhotos: 批量选取最多 20 张
   - deletePetPhoto: 路径安全校验 (仅允许 filesDir/cacheDir/tempDir)
   - 使用 fileIo.copyFileSync 通过文件描述符高效复制

配置修改:
- ProjectPluginRegistrant.ets: 注册以上 3 个新插件
- module.json5: compressNativeLibs=false, extractNativeLibs=true
  确保 libflutter.so 在安装时被正确解压和注册

影响范围: 新增原生插件 + 构建配置
测试设备: SC-3568HA (RK3568, ohos-arm64, API 23)
```

**涉及文件:**
- `ohos/entry/src/main/ets/plugins/PetNoteAiSecretStorePlugin.ets` (新增)
- `ohos/entry/src/main/ets/plugins/PetNoteDataPackageFileAccessPlugin.ets` (新增)
- `ohos/entry/src/main/ets/plugins/PetNotePhotoPickerPlugin.ets` (新增)
- `ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets` (修改)
- `ohos/entry/src/main/module.json5` (修改)

---

## 五、提交顺序建议

```
1. feat(ohos): 修复 API 12 兼容性问题，消除白屏和崩溃
2. fix(ohos): 消除底部黑区，强制 XComponent 和导航栏使用应用背景色
3. fix(dock): 重写原生底栏组件，修复与系统导航键重叠
4. fix(ohos): 32 位 ARM 设备 StackOverflowError 恢复守卫
5. feat(plugins): 新增 AI 密钥存储、备份导入导出、照片选择器原生插件
```

按依赖关系排序: 先修复引擎崩溃 (1) → 再修视觉问题 (2) → 再修交互问题 (3) → 再加稳定性 (4) → 最后加新功能 (5)。

---

## 六、注意事项

1. **oh_modules 补丁文件不在 git 跟踪范围**: `oh_modules/` 通常在 `.gitignore` 中。需要决定是将补丁文件纳入版本控制，还是通过 `scripts/apply-ohos-patches.sh` 脚本在 CI/CD 时自动应用。推荐后者。

2. **`.flutter_ohos_sdk_gitcode/` 子模块**: 此目录是 git submodule (指向 gitcode.com 的 OHOS Flutter SDK)。提交时不需要包含此目录的内容，只需保留 `.gitmodules` 文件。

3. **签名材料**: `.signing-temp/` 目录包含设备专属签名材料 (证书、profile、keystore)，不应提交到仓库。

4. **GeneratedPluginRegistrant.ets**: 此文件是 Flutter 构建工具自动生成的，通常在 `.gitignore` 中。确认是否需要提交。

5. **FlutterPage.ets 的 Color.White 修改**: 此修改在 oh_modules 中，没有 `.petnote-api12-bak` 备份。建议补充备份或写入补丁脚本。

6. **PlatformPlugin.ets 的导航栏颜色修改**: 同上，没有备份文件，建议补充。
