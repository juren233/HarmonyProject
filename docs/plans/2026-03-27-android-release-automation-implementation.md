# Android Release Automation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Android-only GitHub Actions automation that reads `release.yml`, builds per-ABI APKs, publishes Releases from `main`, publishes pre-releases from `beta`, and uploads artifacts for other enabled branches.

**Architecture:** A workflow-level planning job will parse repository configuration and branch context, then pass normalized outputs into a matrix Android build job and a final publish job. Release notes will be assembled from commit messages in the pushed range instead of GitHub-generated notes so the published content mirrors submitted commit descriptions.

**Tech Stack:** GitHub Actions YAML, PowerShell, existing Android build script, repository-root YAML configuration

---

### Task 1: Add the repository release control file

**Files:**
- Create: `F:/HarmonyProject/Pet/release.yml`

**Step 1: Write the control file with collaborator-facing comments**

Create `F:/HarmonyProject/Pet/release.yml` with:

```yaml
enabled: false
tag: ""

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

**Step 2: Verify the file is readable and uses the intended defaults**

Run:

```powershell
Get-Content F:\HarmonyProject\Pet\release.yml
```

Expected:
- `enabled` defaults to `false`
- `tag` defaults to empty string
- Android ABI comments are present

**Step 3: Commit**

```bash
git add release.yml
git commit -m "chore: add release control file"
```

### Task 2: Create the release workflow skeleton

**Files:**
- Create: `F:/HarmonyProject/Pet/.github/workflows/release.yml`

**Step 1: Write the workflow trigger and base job structure**

Create a workflow with:

- `on: push`
- jobs:
  - `resolve-release-plan`
  - `build-android`
  - `publish-release`

Include top-level permissions needed for:

- reading contents
- creating releases
- uploading artifacts

**Step 2: Validate workflow syntax locally by inspection**

Check that the YAML includes:

- `on: push`
- `needs` links between jobs
- branch-aware conditions

**Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "chore: scaffold android release workflow"
```

### Task 3: Implement release plan resolution

**Files:**
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`
- Reference: `F:/HarmonyProject/Pet/release.yml`
- Reference: `F:/HarmonyProject/Pet/pubspec.yaml`

**Step 1: Add the `resolve-release-plan` job**

Implement a job that:

- checks out the repo
- reads `release.yml`
- reads `pubspec.yaml`
- extracts:
  - branch name
  - `enabled`
  - `tag`
  - Android ABI list
  - version core from `pubspec.yaml`

Use PowerShell in the job to normalize outputs into `$GITHUB_OUTPUT`.

**Step 2: Add branch-to-mode mapping**

Map branch names to publish modes:

- `main` -> `release`
- `beta` -> `pre-release`
- any other branch -> `artifacts-only`

If `enabled` is false, set mode to `skip`.

**Step 3: Add release-only validation**

For `main` and `beta` modes:

- fail if `tag` is empty
- fail if `tag` does not equal `v` + version-core

For `artifacts-only` mode:

- allow empty `tag`

**Step 4: Add duplicate release guard**

Use GitHub CLI or REST API to check whether the same tag or release already exists.

Set an output such as:

```text
release_exists=true|false
```

If duplicate exists for `main` or `beta`, mark downstream publish as skipped.

**Step 5: Emit matrix JSON**

Build a JSON array from the configured ABI list, for example:

```json
[
  {"abi":"arm64-v8a","scriptTarget":"arm64"},
  {"abi":"armeabi-v7a","scriptTarget":"arm"},
  {"abi":"x86_64","scriptTarget":"x64"}
]
```

**Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: resolve android release plan in workflow"
```

### Task 4: Implement per-ABI Android builds

**Files:**
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`
- Reference: `F:/HarmonyProject/Pet/scripts/flutter-android.ps1`

**Step 1: Add the `build-android` matrix job**

The job should:

- depend on `resolve-release-plan`
- run only when build is needed
- use the normalized ABI matrix from job outputs

**Step 2: Set up build dependencies**

Add steps to:

- check out the repo
- install Java
- install Flutter
- prepare Android tooling needed by the existing script

**Step 3: Call the existing Android build script**

Use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\flutter-android.ps1 -Mode build -BuildMode release -TargetPlatform ${{ matrix.scriptTarget }}
```

**Step 4: Rename each built APK immediately**

After the script finishes, copy:

`F:/HarmonyProject/Pet/build/app/outputs/flutter-apk/app-release.apk`

to an ABI-specific filename such as:

```text
pet-android-arm64-v8a-v1.0.0.apk
pet-android-arm64-v8a-v1.0.0-beta.1.apk
pet-android-arm64-v8a-feature-login-v1.0.0-beta.1-a1b2c3d.apk
```

The name should vary by publish mode:

- `release` / `pre-release`: include ABI + tag
- `artifacts-only`: include ABI + branch + version + short SHA

**Step 5: Upload the renamed file as an intermediate artifact**

Use `actions/upload-artifact@v4` with a stable per-matrix artifact name.

**Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: build android apks per abi"
```

### Task 5: Build release notes from commit messages

**Files:**
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`

**Step 1: Add a note-generation step to the publish flow**

Create a step that collects commit messages from the pushed range using the push event SHAs:

- before SHA
- after SHA

Use a command shaped like:

```bash
git log --pretty=format:%s BEFORE_SHA..AFTER_SHA
```

If the push creates a new branch or the before SHA is empty / all zeros, fall back to a safe short-history query based on the current branch tip.

**Step 2: Format the release body**

Turn the commit subjects into markdown like:

```markdown
## 本次更新

- feat: add onboarding flow
- fix: correct settings save behavior
- docs: update release instructions
```

Do not use GitHub auto-generated release notes.

The release body must be written in Chinese.

For `beta` pre-releases, prepend:

```markdown
## Importance

这是一个 Beta 预发布版本，主要用于测试和提前体验新功能，可能包含不稳定行为或未完全验证的问题，请谨慎安装。
```

**Step 3: Persist the generated body for later publish steps**

Expose the note text through:

- a job output, or
- a temporary file downloaded in the publish job

**Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: generate release notes from commit messages"
```

### Task 6: Publish releases for `main` and `beta`

**Files:**
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`

**Step 1: Add the `publish-release` job**

This job should:

- depend on `build-android`
- run only when mode is `release` or `pre-release`
- skip if duplicate release already exists

**Step 2: Download all intermediate APK artifacts**

Use `actions/download-artifact@v5` to gather all matrix outputs into one directory.

**Step 3: Create GitHub Release / pre-release**

Use GitHub CLI or a release action to create:

- normal release for `main`
- pre-release for `beta`

Pass:

- `tag`
- release title = `tag`
- body = generated commit-message notes

Set:

- `prerelease: false` for `main`
- `prerelease: true` for `beta`

Do not create drafts.

**Step 4: Upload all APKs as release assets**

Upload every renamed APK collected from the build matrix.

**Step 5: Read asset download URLs and update the release body**

After the assets are uploaded, collect each asset download URL and append a Chinese download section like:

```markdown
## 版本选择

- [Android arm64-v8a 安装包](...)
  适用于大多数 64 位 Android 真机
- [Android armeabi-v7a 安装包](...)
  适用于较老的 32 位 Android 设备
- [Android x86_64 安装包](...)
  适用于 Android 模拟器或少量 x86_64 设备
```

This step must update the already-created release so the final visible body includes direct clickable blue download links.

**Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: publish android releases by branch"
```

### Task 7: Publish workflow artifacts for non-release branches

**Files:**
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`

**Step 1: Add artifacts-only branch handling**

When mode is `artifacts-only`:

- do not create any Release
- download all intermediate APKs
- upload them again as a grouped final artifact for the workflow run

**Step 2: Set artifact retention**

Set a shorter retention period, such as:

```yaml
retention-days: 7
```

or:

```yaml
retention-days: 14
```

**Step 3: Name grouped artifacts clearly**

Use names like:

```text
android-apks-feature-login-a1b2c3d
android-apks-dev-a1b2c3d
```

**Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: upload branch build artifacts for android"
```

### Task 8: Document usage in the main project guide

**Files:**
- Modify: `F:/HarmonyProject/Pet/README.md`

**Step 1: Add a short release automation section**

Document:

- root `release.yml`
- branch behavior:
  - `main` -> Release
  - `beta` -> pre-release
  - others -> artifacts only
- `tag` / `pubspec.yaml` matching rule
- ABI meanings
- how to recreate a same-name release by deleting the existing release and tag first

**Step 2: Keep the README brief**

The detailed collaborator guidance remains in `release.yml`; README should only summarize behavior.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add android release automation usage"
```

### Task 9: Verify configuration and workflow output

**Files:**
- Test: `F:/HarmonyProject/Pet/release.yml`
- Test: `F:/HarmonyProject/Pet/.github/workflows/release.yml`

**Step 1: Verify YAML files render as expected**

Run:

```powershell
Get-Content F:\HarmonyProject\Pet\release.yml
Get-Content F:\HarmonyProject\Pet\.github\workflows\release.yml
```

Expected:

- branch rules are clearly encoded
- notes are generated from commit messages, not GitHub-generated notes
- ABI mapping is present

**Step 2: Dry-run logic by inspecting key conditions**

Check that the workflow contains conditions for:

- `main`
- `beta`
- non-release branches
- duplicate release skip

**Step 3: If available, validate workflow with GitHub CLI**

Run:

```bash
gh workflow view release.yml
```

Expected:

- workflow is discoverable

If this cannot run locally, note the limitation and rely on YAML inspection.

**Step 4: Commit**

```bash
git add release.yml .github/workflows/release.yml README.md
git commit -m "test: verify android release automation configuration"
```

### Task 10: Final review pass

**Files:**
- Modify: `F:/HarmonyProject/Pet/release.yml`
- Modify: `F:/HarmonyProject/Pet/.github/workflows/release.yml`
- Modify: `F:/HarmonyProject/Pet/README.md`

**Step 1: Review for consistency**

Confirm the following all match:

- `pre-release` wording in comments and docs
- fixed `beta` branch behavior
- no draft release logic
- release notes sourced from commit messages
- release / pre-release notes are written in Chinese
- `beta` releases include the `Importance` section at the top
- all published releases include the `版本选择` section at the bottom
- download entries use direct Markdown links to APK assets
- user-facing ABI names stay readable

**Step 2: Review for YAGNI**

Remove anything not required for the agreed scope:

- no iOS
- no HarmonyOS
- no manual release-type flag in config
- no extra changelog field

**Step 3: Commit**

```bash
git add release.yml .github/workflows/release.yml README.md
git commit -m "refactor: finalize android release automation"
```
