# GitHub Release CLI Migration Design

**Date:** 2026-03-29

## Goal

Replace the third-party `softprops/action-gh-release@v2` step in the Android release workflow with the built-in GitHub CLI so the workflow no longer depends on a Node 20 JavaScript action, while preserving the current release behavior.

## Current Behavior To Preserve

- Releases are only published when `should_publish_release == 'true'`.
- If the target tag or release already exists, the workflow skips publishing earlier in `resolve-release-plan`.
- The release title remains the tag value.
- The release body starts from `release-body-initial.md`.
- All downloaded APK artifacts are uploaded to the GitHub release.
- After creation, the workflow rewrites the release notes to append ABI-specific download links.
- Artifact-only builds continue to upload workflow artifacts instead of creating a GitHub release.

## Proposed Change

Replace the `Create GitHub Release` action step with a `bash` step that:

1. Authenticates through `GH_TOKEN=${{ github.token }}`.
2. Collects every `*.apk` file under `downloaded-artifacts`.
3. Fails fast if no APK files are found.
4. Creates the release with `gh release create`, using:
   - the existing tag output
   - the existing target branch output
   - the existing prerelease condition
   - `release-body-initial.md` as the initial notes file
5. Performs a lightweight `gh release view` guard so that an unexpected pre-existing release results in a clean skip rather than an overwrite.

## Why This Approach

- `gh` is already available on GitHub-hosted runners.
- It removes the remaining known Node 20 dependency in the workflow.
- It keeps release-note generation and post-processing unchanged.
- It avoids introducing overwrite or patch-up logic, matching the current "skip if already exists" behavior.

## Verification

- Validate `.github/workflows/release.yml` syntax.
- Review the final diff to confirm only the release creation mechanism changed.
- Confirm that artifact upload paths, prerelease logic, and release-note update logic remain intact.
