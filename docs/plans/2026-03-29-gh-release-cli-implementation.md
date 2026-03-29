# GH Release CLI Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the `softprops/action-gh-release` step in the Android release workflow with `gh release create` while preserving existing release behavior.

**Architecture:** Keep the existing three-job workflow structure intact. Only the release-creation step changes: a bash step gathers APK assets and calls the GitHub CLI, while the existing post-create note update script continues to run unchanged.

**Tech Stack:** GitHub Actions workflow YAML, Bash, GitHub CLI (`gh`), existing `actions/github-script@v8`

---

### Task 1: Document the migration target

**Files:**
- Create: `docs/plans/2026-03-29-gh-release-cli-design.md`
- Create: `docs/plans/2026-03-29-gh-release-cli-implementation.md`

**Step 1: Capture the approved behavior constraints**

Write down that existing tags or releases must still cause publishing to be skipped, not overwritten.

**Step 2: Capture the implementation boundary**

Write down that only the release creation step changes; note generation, artifact-only uploads, and release-note link updates stay as-is.

### Task 2: Replace the release creation action with GitHub CLI

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Remove the third-party release action step**

Delete the `softprops/action-gh-release@v2` step from the `publish-release` job.

**Step 2: Add a bash-based CLI release step**

Create a replacement step that sets `GH_TOKEN`, gathers `downloaded-artifacts/**/*.apk`, checks that at least one APK exists, and calls `gh release create`.

**Step 3: Preserve skip semantics**

Add a `gh release view "$TAG"` guard so that if a release unexpectedly already exists, the step exits successfully without updating or overwriting anything.

**Step 4: Preserve prerelease and metadata behavior**

Pass the existing tag, target branch, title, prerelease flag, and `release-body-initial.md` into the CLI command.

### Task 3: Verify workflow correctness

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Validate workflow syntax**

Run: `Get-Content .github/workflows/release.yml -Raw | npx -y yaml valid`
Expected: exit code 0 with no YAML errors.

**Step 2: Review the workflow diff**

Run: `git diff -- .github/workflows/release.yml docs/plans/2026-03-29-gh-release-cli-design.md docs/plans/2026-03-29-gh-release-cli-implementation.md`
Expected: the diff shows only the documented workflow migration and plan files.

**Step 3: Confirm behavior assumptions in the final summary**

Note that the publish gate is still controlled by `resolve-release-plan`, and the CLI step now adds a secondary non-overwriting existence guard.
