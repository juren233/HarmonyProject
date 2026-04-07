# Android Release Automation Design

## Goal

Build an Android-only release automation flow for this repository using GitHub Actions.

The automation should:

- Read a repository-root control file on each push.
- Decide whether to skip, create a Release, create a pre-release, or only upload workflow artifacts.
- Build separate APK files for each configured Android CPU architecture.
- Keep release behavior stable and easy for collaborators to understand.

This design intentionally excludes iOS and HarmonyOS:

- iOS is excluded because it requires Apple account, signing assets, and macOS-specific build infrastructure.
- HarmonyOS is excluded because the current project build path depends on local DevEco / OpenHarmony tooling and is not a good fit for standard GitHub-hosted runners.

## Decision Summary

### Branch behavior

The workflow runs on pushes to all branches.

Behavior is determined by both the current branch and the root control file:

- `main` + `enabled: true`
  Create a normal GitHub Release and upload APK assets.
- `beta` + `enabled: true`
  Create a GitHub pre-release and upload APK assets.
- other branches + `enabled: true`
  Build APKs and upload them only as GitHub Actions artifacts.
- any branch + `enabled: false`
  Skip build and publish work.

### Release content

Release and pre-release notes should come directly from the pushed commits.

The workflow should not use GitHub's automatically generated release notes for this repository.

Instead, the workflow should build the release body from commit messages in the pushed range so that the published Release / pre-release content directly reflects the submitted commit descriptions.

The published notes should be written in Chinese.

Additional formatting rules:

- `beta` branch pre-releases must include a Chinese `Importance` section at the top that clearly tells users this is a beta version for testing and may contain unstable behavior.
- all published Releases, including pre-releases, must include a Chinese download selection section at the bottom
- the download selection section should use Markdown links so GitHub renders blue clickable links
- those links should point directly to each uploaded APK asset so users can download the matching package with one click

### Versioning

Release identity is based on both:

- `tag` from the root control file
- `version` from [pubspec.yaml](/F:/HarmonyProject/Pet/pubspec.yaml)

For published release branches:

- `tag` is required.
- `tag` must equal `v` plus the `pubspec.yaml` version string before the `+build` suffix.

Examples:

- `version: 1.0.0+1` -> `tag: v1.0.0`
- `version: 1.0.0-beta.1+3` -> `tag: v1.0.0-beta.1`

Pre-release version strings in `pubspec.yaml` must follow SemVer.

Allowed examples:

- `1.0.0-beta.1`
- `1.0.0-rc.1`

Disallowed example:

- `1.0.0beta.1`

### Duplicate protection

If a release with the same `tag` already exists, the workflow should skip publish work.

If the team wants to recreate the same outward-facing release version, such as when the internal build number changes but the visible version stays the same, they must first delete the existing GitHub Release and the same-named Git tag, then push again.

## Root Control File

The control file should live at the repository root as `release.yml`.

Recommended structure:

```yaml
enabled: true
tag: v1.0.0-beta.1

android:
  enabled: true
  artifacts:
    - arm64-v8a
    - armeabi-v7a
    - x86_64

# Release control file
# 1. enabled=true 时，push 后工作流才会尝试构建。
# 2. main 分支 + enabled=true：创建正式 Release。
# 3. beta 分支 + enabled=true：创建 pre-release。
# 4. 其他分支 + enabled=true：只上传 Actions artifacts，不创建 Release。
# 5. tag 必须与 pubspec.yaml 的版本号（去掉 +build 后）一致，并在前面加 v。
#    例如：tag=v1.0.0 对应 version: 1.0.0+1
#    例如：tag=v1.0.0-beta.1 对应 version: 1.0.0-beta.1+3
# 6. pubspec.yaml 的预发布版本必须使用标准 SemVer 格式，
#    例如 1.0.0-beta.1、1.0.0-rc.1，不能写成 1.0.0beta.1。
# 7. Android Release / pre-release 的类型不由文件控制，而是由分支决定：
#    main -> Release
#    beta -> pre-release
#    other branches -> artifacts only
# 8. android.enabled=true 表示本次构建包含 Android 安装包。
# 9. artifacts 用于声明要构建的 APK CPU 架构：
#    arm64-v8a = 大多数 64 位 Android 真机，推荐优先提供
#    armeabi-v7a = 较老的 32 位 Android 设备
#    x86_64 = Android 模拟器或少量 x86_64 设备
# 10. 每个架构生成独立 APK，便于用户按设备选择安装。
# 11. 如果同名 tag/release 已存在，工作流会跳过，避免重复创建。
# 12. 如果需要重新创建同名 release（例如内部 build number 变化，但外显版本号不变），
#     先手动删除 GitHub 上同名 release 和 tag，再重新 push 触发创建。
```

## Architecture Names

The control file should expose Android CPU architecture names in user-facing form:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

However, the existing build script [flutter-android.ps1](/F:/HarmonyProject/Pet/scripts/flutter-android.ps1) currently expects:

- `arm64`
- `arm`
- `x64`

The workflow should perform the following mapping:

- `arm64-v8a` -> `arm64`
- `armeabi-v7a` -> `arm`
- `x86_64` -> `x64`

This keeps the control file readable for collaborators while preserving compatibility with the existing script.

## Workflow Design

The workflow should be implemented in a single file such as:

- `.github/workflows/release.yml`

Recommended job layout:

### 1. `resolve-release-plan`

This job determines what should happen for the current push.

Responsibilities:

- Read `release.yml`.
- Read [pubspec.yaml](/F:/HarmonyProject/Pet/pubspec.yaml).
- Identify current branch.
- Decide run mode:
  - `skip`
  - `release`
  - `pre-release`
  - `artifacts-only`
- Validate Android configuration.
- Validate `tag` for `main` and `beta`.
- Check whether the same release / tag already exists.
- Emit job outputs for downstream jobs.

Suggested outputs:

- `enabled`
- `branch_name`
- `publish_mode`
- `should_build`
- `should_publish_release`
- `tag`
- `version_core`
- `android_enabled`
- `android_matrix_json`
- `release_exists`

### 2. `build-android`

This job runs only when `should_build == true`.

It should use a matrix over the configured Android architectures and call the existing script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode build -BuildMode release -TargetPlatform <mapped>
```

Responsibilities:

- Set up Java and Flutter.
- Build one APK per configured architecture.
- Copy or rename the generated APK immediately after each matrix build to avoid overwrite.
- Upload each renamed APK as a temporary workflow artifact for the final publish step.

Expected source artifact path after each build:

- [build/app/outputs/flutter-apk/app-release.apk](/F:/HarmonyProject/Pet/build/app/outputs/flutter-apk/app-release.apk)

### 3. `publish-release`

This job runs after all matrix builds succeed.

Responsibilities:

- Download matrix artifacts.
- If mode is `release`, create a normal GitHub Release.
- If mode is `pre-release`, create a GitHub pre-release.
- If mode is `artifacts-only`, upload a final grouped artifact and stop.
- Build the release body from the pushed commit messages and use that text as the Release / pre-release notes.
- Write the final body in Chinese.
- Add a Chinese `Importance` section at the top for `beta` pre-releases.
- After assets are uploaded, append a Chinese download selection section with direct Markdown download links for each APK.

## Naming Rules

### Release asset filenames

Suggested filenames:

- `pet-android-arm64-v8a-v1.0.0.apk`
- `pet-android-armeabi-v7a-v1.0.0.apk`
- `pet-android-x86_64-v1.0.0.apk`
- `pet-android-arm64-v8a-v1.0.0-beta.1.apk`

### Non-release artifact filenames

Suggested filenames should also include branch and short SHA:

- `pet-android-arm64-v8a-feature-login-v1.0.0-beta.1-a1b2c3d.apk`

Suggested grouped artifact names:

- `android-apks-main-v1.0.0`
- `android-apks-beta-v1.0.0-beta.1`
- `android-apks-feature-login-a1b2c3d`

## Release Notes Layout

### Normal release notes

Suggested Chinese structure:

```markdown
## 本次更新

- feat: ...
- fix: ...
- docs: ...

## 版本选择

- [Android arm64-v8a 安装包](...)
  适用于大多数 64 位 Android 真机
- [Android armeabi-v7a 安装包](...)
  适用于较老的 32 位 Android 设备
- [Android x86_64 安装包](...)
  适用于 Android 模拟器或少量 x86_64 设备
```

### Pre-release notes

Suggested Chinese structure:

```markdown
## Importance

这是一个 Beta 预发布版本，主要用于测试和提前体验新功能，可能包含不稳定行为或未完全验证的问题，请谨慎安装。

## 本次更新

- feat: ...
- fix: ...
- docs: ...

## 版本选择

- [Android arm64-v8a 安装包](...)
  适用于大多数 64 位 Android 真机
- [Android armeabi-v7a 安装包](...)
  适用于较老的 32 位 Android 设备
- [Android x86_64 安装包](...)
  适用于 Android 模拟器或少量 x86_64 设备
```

Because the final download links depend on uploaded assets, the workflow must create the release first, upload assets, collect the resulting download URLs, and then update the release body with the final Chinese version-selection section.

## GitHub Release Semantics

This design does not use draft releases.

The publish modes are:

- `release`
  A normal published GitHub Release from `main`
- `pre-release`
  A published but non-stable GitHub pre-release from `beta`
- `artifacts-only`
  No GitHub Release; APKs are downloadable from the workflow run's artifact section

This keeps the repository release feed clean:

- `main` is the public stable line
- `beta` is the public preview line
- all other branches stay internal

## Actions Artifact Behavior

For non-release branches:

- APKs are not published in the repository Releases feed.
- APKs remain downloadable from the GitHub Actions run summary.
- Artifacts expire according to repository or workflow retention settings.

Recommended retention for non-release branch artifacts:

- 7 to 14 days

## Error Handling

The workflow should fail early with clear messages for:

- missing `release.yml`
- malformed YAML
- `android.enabled != true` when a build is expected
- empty Android artifact list
- invalid architecture name
- missing `tag` on `main` or `beta`
- `tag` / `pubspec.yaml` version mismatch
- duplicate existing release tag
- missing expected APK output after script execution

## Tradeoffs

### Why use a root YAML file instead of Markdown

Structured YAML is safer than Markdown for machine decisions because:

- field names are explicit
- parsing is more stable
- collaborators are less likely to break the logic by changing prose formatting

### Why branch decides release type

Removing release-type selection from the control file prevents conflicts such as:

- `main` accidentally marked as pre-release
- `beta` accidentally marked as normal release

Branch-driven publish type is simpler and more predictable.

### Why reuse the existing PowerShell script

Reusing [flutter-android.ps1](/F:/HarmonyProject/Pet/scripts/flutter-android.ps1) reduces risk because the repository already depends on that script's Flutter state management and local environment assumptions.

## Implementation Notes

Implementation should add:

- root `release.yml`
- `.github/workflows/release.yml`

Optional future follow-ups:

- support Android App Bundle (`aab`) in addition to APK
- support generated branch-aware run names
- support manual `workflow_dispatch`
- support release notes customization later if needed

## Approval State

The following design choices were confirmed during discussion:

- Android only
- root control file decides whether build work is enabled
- `main` creates Release
- fixed `beta` branch creates pre-release
- all other branches only upload artifacts
- release notes come from commit history
- APKs are built separately per CPU architecture
- collaborator instructions should be embedded directly in the control file
