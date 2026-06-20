# PetNote GitHub Actions 触发说明

这份文档用于交接给协作者：什么时候会触发 PetNote 的 GitHub Actions，怎么手动确认是否真的触发，以及常见“我提交了但没跑”的原因。

## 最近几次更新内容

截至当前仓库状态，最近与构建发布相关的提交主要是这几类：

- `cdfaa05 chore: 完成iOS和Harmony平台到DingRTC的迁移`
  - iOS 从 `AliVCSDK_ARTC` 迁移到 `DingRTC_iOS`。
  - Harmony 从 `@aliyun_video_cloud/alivcsdk_artc` 迁移到 `@dingrtc/dingrtc`。
  - 服务端默认 GSLB 改为 `https://gslb.dingrtc.com`。
  - 更新了 iOS / Harmony / RTC token 相关结构测试。
- `f9a1761 ci: auto-increment build number using git commit count`
  - Release workflow 不再直接使用 `pubspec.yaml` 里的 `+build` 作为最终 build number。
  - 工作流会用 `git rev-list --count HEAD` 自动生成 build number，保证每次构建号随提交数递增。
- `c6edb1a fix: fetch full git history for accurate commit count`
  - `actions/checkout` 增加 `fetch-depth: 0`，确保 GitHub Actions 能拿到完整提交历史。
  - 没有完整历史时，`git rev-list --count HEAD` 可能只数到浅克隆提交，导致 build number 不准。
- 当前 workflow 后续改动
  - Android 构建命令显式传入 `--build-name` 和 `--build-number`。
  - iOS 未签名 IPA 构建命令也显式传入 `--build-name` 和 `--build-number`。
  - `.github/workflows/release.yml` 增加 `workflow_dispatch`，支持在 GitHub 网页手动触发同一套构建。

当前本地检查到 `main` 分支比 `origin/main` 多提交时，要先执行 `git push origin main`，否则 GitHub 上不会有这些修改，也不会触发对应 Actions。

## 自动版本号规则

当前 workflow 会把 `pubspec.yaml` 的版本拆成两部分：

```yaml
version: 1.4.0-beta.18+40
```

- `1.4.0-beta.18` 是外显版本号，用作 `--build-name` 和 Release tag `v1.4.0-beta.18`。
- `+40` 是本地兜底 build number；GitHub Actions 正常运行时会被自动 build number 覆盖。
- GitHub Actions 内部 build number 来自 `git rev-list --count HEAD`。

构建时会显式执行等价逻辑：

```bash
flutter build apk --build-name <pubspec version core> --build-number <git commit count>
flutter build ios --build-name <pubspec version core> --build-number <git commit count>
```

因此每次新的提交触发构建时：

- Android 的 `versionCode` 会随提交数递增。
- iOS 的 `CFBundleVersion` 会随提交数递增。
- 外显版本号不会自动从 `beta.18` 变成 `beta.19`；如果需要新的 Release tag，仍需手动改 `pubspec.yaml` 的外显版本号。

## 当前 workflow 触发规则

PetNote 的发布工作流文件是：

```text
.github/workflows/release.yml
```

当前触发器是：

```yaml
on:
  push:
  workflow_dispatch:
```

也就是说：

- 只有把提交 push 到 GitHub 远端仓库后才会触发。
- 只在本地 `git commit` 不会触发。
- 只改本地文件但没有 commit / push 不会触发。
- 当前 workflow 有 `workflow_dispatch`，所以也可以在 GitHub 网页上点击 “Run workflow” 手动触发。

## 发布配置由哪个文件控制

GitHub Actions 是否构建 Android / iOS，以及是否创建 GitHub Release，由仓库根目录的这个文件控制：

```text
release.yml
```

当前关键配置示例：

```yaml
enabled: true
build_if_not_enabled: true
pre_release: true

android:
  enabled: true
  artifacts:
    - arm64-v8a

ios:
  enabled: true
  artifacts:
    - unsigned-ipa
```

含义如下：

- `enabled: true`：在 `main` / `beta` 分支 push 后会尝试创建 Release 或 pre-release。
- `build_if_not_enabled: true`：如果以后把 `enabled` 改成 `false`，仍会构建产物并上传 Actions artifacts，但不会创建 Release。
- `pre_release: true`：发布为 GitHub pre-release。
- `android.enabled: true`：构建 Android APK。
- `android.artifacts: [arm64-v8a]`：当前只构建一个 64 位真机 APK。
- `ios.enabled: true`：构建 iOS 未签名 IPA。
- `ios.artifacts: [unsigned-ipa]`：iOS 产物需要自行签名后才能安装到真机。

## 正确触发 Actions 的步骤

### 1. 确认当前分支

```bash
git branch --show-current
```

推荐发布构建从 `main` 触发。如果在其他分支 push，也会触发 workflow，但只上传 Actions artifacts，不会创建 GitHub Release。

### 2. 确认有哪些本地提交还没推送

```bash
git log --oneline origin/main..HEAD
```

如果这条命令有输出，说明本地有提交还没到 GitHub。此时 Actions 不会看到这些提交。

### 3. 推送到 GitHub

```bash
git push origin main
```

如果当前不是 `main`，把 `main` 换成实际分支名：

```bash
git push origin <branch-name>
```

### 4. 到 GitHub 页面查看运行记录

进入仓库页面：

```text
Actions -> PetNote Release
```

也可以直接看最近 push 的 commit 旁边是否出现黄色圆点、绿色勾或红叉。

如果不想新增提交，也可以手动触发：

```text
Actions -> PetNote Release -> Run workflow
```

手动触发时同样会按当前分支的 HEAD 计算 build number。

### 5. 下载构建产物

如果是 `main` / `beta` 且 `release.yml` 允许发布：

```text
GitHub -> Releases
```

如果是其他分支，或 workflow 只构建不发布：

```text
Actions -> 对应 workflow run -> Artifacts
```

## 为什么提交后没有触发

优先按下面顺序排查。

### 只 commit 了，没有 push

现象：本地能看到新提交，GitHub 上看不到。

检查：

```bash
git log --oneline origin/main..HEAD
```

修复：

```bash
git push origin main
```

### push 到了非预期分支

现象：Actions 可能跑了，但没有出 Release。

原因：非 `main` / `beta` 分支会走 `artifacts-only`，只上传 artifacts，不创建 Release。

检查：

```bash
git branch --show-current
```

### GitHub Actions 被仓库设置禁用

现象：push 后完全没有新的 workflow run。

检查位置：

```text
GitHub -> Settings -> Actions -> General
```

需要确认 Actions 没有被禁用，并且允许该 workflow 运行。

### release.yml 配置让它只构建或跳过发布

现象：Actions 跑了，但没有 Release。

重点看：

```yaml
enabled: true
build_if_not_enabled: true
android.enabled: true
ios.enabled: true
```

如果 `enabled: false`，即使 `build_if_not_enabled: true`，也只会上传 artifacts，不会创建 Release。

### 同名 tag 或 Release 已存在

Release tag 由 `pubspec.yaml` 的版本号自动生成，例如：

```yaml
version: 1.4.0-beta.18+40
```

会生成：

```text
v1.4.0-beta.18
```

如果 GitHub 上已经有同名 Release 或 tag，workflow 会跳过创建新的 Release，避免重复发布。

处理方式：

- 推荐：更新 `pubspec.yaml` 的外显版本号，例如从 `1.4.0-beta.18+40` 改到 `1.4.0-beta.19+41`。
- 不推荐但可行：手动删除 GitHub 上同名 Release 和 tag 后重新 push。

### Android 签名 Secrets 缺失

现象：workflow 触发了，但 Android job 失败。

需要在 GitHub Secrets 中配置：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

iOS 未签名 IPA 不需要 Apple 证书或 provisioning profile。

## 一次完整发布前检查清单

发布前建议按顺序执行：

```bash
git status --short
git branch --show-current
git log --oneline origin/main..HEAD
sed -n '1,80p' release.yml
rg '^version:' pubspec.yaml
```

判断标准：

- `git status --short`：确认没有忘记提交的必要文件。
- `git branch --show-current`：确认在预期分支。
- `git log --oneline origin/main..HEAD`：确认哪些提交准备 push。
- `release.yml`：确认 Android / iOS 构建开关符合本次目标。
- `pubspec.yaml`：确认外显版本号是否需要变化，避免 Release tag 重复。

确认无误后：

```bash
git push origin main
```

## 网页手动触发注意事项

当前 `.github/workflows/release.yml` 已配置 `workflow_dispatch`，可以在 GitHub 网页上点按钮手动运行。

注意：手动触发不会新增 commit。如果同一个 commit 被重复手动构建，自动 build number 也会相同，因为它来自当前 commit count。想让 build number 继续递增，需要先产生新的提交并 push。
