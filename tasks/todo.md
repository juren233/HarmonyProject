# 删除爱宠功能闭环

- [x] 复核 README 三端运行、版本与提交边界约束
- [x] 蓝军检查长按删除策略的误触、透明度、数据级联和发布口径风险
- [x] 修正长按进度条为手势生命周期驱动，避免横向滚动误触
- [x] 保证删除确认弹窗卡片 surface 与内部提示区为不透明同色
- [x] 同步 README 顶部版本徽章到 `pubspec.yaml` 的 `1.4.0-beta.16+38`
- [x] 跑 Dart/Flutter 相关测试
- [x] 跑 iOS、Android、Harmony 最低构建验证
- [ ] 提交并触发 GitHub Actions Release workflow

## Review

- `dart analyze lib/app/petnote_pages_pets.dart lib/state/petnote_store.dart test/pets_page_subtitle_test.dart test/pet_care_store_test.dart` 通过。
- `flutter test test/pets_page_subtitle_test.dart test/pet_care_store_test.dart test/harmony_rtc_bridge_structure_test.dart` 通过，覆盖长按进度、弹窗不透明、取消、确认删除、数据级联与远端删除不回写本地 mutation。
- `flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons` 通过，产物 `build/app/outputs/flutter-apk/app-release.apk`。
- `flutter build ios --release --no-codesign --no-tree-shake-icons` 通过，产物 `build/ios/iphoneos/Runner.app`。
- `flutter build ios --simulator --debug` 未通过，失败点是 Flutter/Xcode 工具链在 `debug_unpack_ios` 报 Flutter.framework 不含 `arm64 x86_64`，但同一日志里的 `lipo -info` 显示二者都存在；这不是删除爱宠业务代码错误。
- Harmony macOS DevEco 命令链 `ohpm install --all && hvigorw assembleHap -p product=default -p buildMode=debug --no-daemon` 已推进到 `PackageHap` 并产出 `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`；此前 `url_launcher_harmonyos` 缺模块问题已修复，`ohos/.hvigor/dependencyMap/entry/oh-package.json5` 已包含真实 `file:` 依赖。最终 `SignHap` 因本机缺少 gitignored 的 `ohos/sign/OpenHarmony.p12` 签名材料失败。
- `git diff --check` 通过，仅提示 PowerShell 脚本在 Git 触碰时会按仓库规则转 CRLF。
