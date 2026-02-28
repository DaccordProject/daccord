# Nightly Branch

## Overview

This flow describes how daccord maintains a separate `nightly` branch that receives automatic builds from the latest development commits, and how clients built from that branch listen for nightly release updates instead of stable releases. The goal is a two-channel update system: **stable** (tagged releases from `master`) and **nightly** (automated pre-release builds from `nightly`), where each build knows which channel it belongs to and only checks for updates within its channel.

None of this is implemented yet. This document serves as a specification.

## User Steps

### Developer: Setting Up the Nightly Branch

1. Developer creates a long-lived `nightly` branch from `master`: `git checkout -b nightly && git push -u origin nightly`.
2. New features and experimental changes are merged into `nightly` via PRs. `master` receives only stable, tested changes.
3. Periodically, `master` is merged into `nightly` to keep it up to date: `git checkout nightly && git merge master`.
4. The `nightly` branch uses pre-release version strings in `project.godot` (e.g., `0.2.0-nightly.20260219`). The date suffix is injected automatically by CI.

### CI: Automatic Nightly Builds

1. A push to the `nightly` branch (or a scheduled daily trigger) starts the nightly release workflow (`.github/workflows/nightly.yml`).
2. The workflow generates a version string: it reads the base version from `project.godot` (e.g., `0.2.0`) and appends `-nightly.YYYYMMDD` (e.g., `0.2.0-nightly.20260219`).
3. The workflow injects this nightly version into `project.godot` and sets `application/config/update_channel` to `"nightly"` before export.
4. Four platform builds run in parallel (Linux x86_64, Linux ARM64, Windows, macOS), identical to the stable release workflow.
5. The workflow creates (or updates) a GitHub Release tagged `nightly` with `prerelease: true`. Old nightly assets are replaced by the new ones.
6. The release title includes the date: "Nightly 2026-02-19".

### End User: Using a Nightly Build

1. User downloads a nightly build from the GitHub Releases page (the release tagged `nightly`, marked as pre-release).
2. User launches daccord. The title bar shows "daccord v0.2.0-nightly.20260219".
3. On startup, the updater detects that this is a nightly build (via the `update_channel` project setting or the `-nightly` pre-release suffix in the version string).
4. The updater checks the `nightly` tag on GitHub Releases for a newer build instead of checking `latest`.
5. **Newer nightly available:** The update banner appears: "daccord nightly 2026-02-20 is available. [Update] [Dismiss]"
6. **No newer nightly:** Nothing happens.
7. The user can dismiss or download the update, identical to the stable update flow (see [Auto-Update](auto_update.md)).

### End User: Switching Channels

1. User opens the user bar menu and selects "About".
2. The About dialog shows the current version and the update channel ("stable" or "nightly").
3. To switch from stable to nightly (or vice versa), the user downloads the desired build from the GitHub Releases page and replaces their current installation. There is no in-app channel switcher.
4. Alternatively, a future "Update Channel" setting in user preferences could allow switching without manual download.

### Developer: Promoting Nightly to Stable

1. When a nightly build is deemed stable, the developer merges `nightly` into `master`.
2. Developer updates `project.godot` version to the release version (e.g., `0.2.0`, no pre-release suffix).
3. Developer pushes a version tag: `git tag v0.2.0 && git push origin v0.2.0`.
4. The stable release workflow (`.github/workflows/release.yml`) builds and publishes the tagged release.
5. Nightly users who update to the next nightly will naturally get these changes. Nightly users who want stable can download the tagged release.

## Signal Flow

```
Nightly CI Build (push to nightly branch or schedule):
  .github/workflows/nightly.yml triggers
    -> Generate version: read project.godot base version + append -nightly.YYYYMMDD
    -> Inject nightly version into project.godot
    -> Inject update_channel="nightly" into project.godot
    -> [conditional] Inject Sentry DSN with environment="nightly"
    -> 4x parallel build jobs (same matrix as release.yml)
    -> Create/update GitHub Release (tag: nightly, prerelease: true)
       -> Replaces previous nightly assets

Startup Update Check (nightly build):
  Client._ready() (after connections established)
    -> Updater.check_for_updates()
    -> Updater._get_update_channel()
      -> Reads ProjectSettings "application/config/update_channel"
      -> If "nightly" or version contains "-nightly": channel = "nightly"
      -> Else: channel = "stable"
    -> If channel == "nightly":
      -> GET https://api.github.com/repos/DaccordProject/daccord/releases/tags/nightly
      -> Parse response: compare asset timestamps or injected version string
    -> If channel == "stable":
      -> GET https://api.github.com/repos/DaccordProject/daccord/releases/latest
      -> Parse response: compare tag_name semver vs APP_VERSION
    -> If newer:
      -> AppState.update_available.emit(version_info)
      -> main_window shows update banner
    -> If current or error: no signal emitted

Stable Release (tag push):
  .github/workflows/release.yml triggers (unchanged)
    -> Validates tag matches project.godot version
    -> Builds, packages, creates GitHub Release (draft: false, prerelease: false)
```

## Key Files

| File | Role |
|------|------|
| `.github/workflows/nightly.yml` | **New.** Nightly CI workflow. Triggers on push to `nightly` or daily schedule. Generates nightly version, injects it into `project.godot`, builds all platforms, creates/updates the `nightly` GitHub Release. |
| `.github/workflows/release.yml` | Existing stable release workflow. Unchanged — triggers on `v*` tags from `master`. |
| `.github/workflows/ci.yml` | Existing CI workflow. Would be extended to also run on push/PR to `nightly` (line 5-6). |
| `project.godot` | Version source of truth (`config/version`, line 18). Nightly CI injects the `-nightly.YYYYMMDD` suffix and a new `config/update_channel` setting. |
| `scripts/autoload/updater.gd` | Semver utilities (lines 7-67). Would add `get_update_channel()`, `check_for_updates()`, and nightly-aware version comparison logic. |
| `scripts/autoload/config.gd` | Update preferences (lines 324-348). `get_auto_update_check()`, `get_skipped_version()`, `get_last_update_check()` apply to both channels. |
| `scripts/autoload/client.gd` | Reads `app_version` from `project.godot` (lines 15-17). Nightly builds will have a version like `0.2.0-nightly.20260219`. |
| `scripts/autoload/app_state.gd` | Update signals (lines 90-102): `update_available`, `update_check_complete`, `update_check_failed`, `update_download_progress`, `update_download_complete`, `update_download_failed`. Used by both channels. |
| `scripts/autoload/error_reporting.gd` | Sentry tag setup (lines 19-29). Would add an `update_channel` tag so nightly crashes are distinguished from stable. |
| `scenes/sidebar/user_bar.gd` | "Check for Updates" menu item (id 16, line 60). Stub handler at line 356. "About" dialog (line 182) would show the update channel. |
| `tests/unit/test_updater.gd` | Semver tests (lines 1-153). Would add tests for nightly version parsing and channel detection. |

## Implementation Details

### Nightly Version Scheme

Nightly builds use semver with a pre-release suffix: `<base>-nightly.<YYYYMMDD>`, e.g., `0.2.0-nightly.20260219`. This has several advantages:

- **Semver-compatible:** The existing `parse_semver()` (updater.gd, line 7) and `compare_semver()` (line 34) already handle pre-release suffixes. A nightly version like `0.2.0-nightly.20260219` parses to `{ major: 0, minor: 2, patch: 0, pre: "nightly.20260219" }`.
- **Naturally ordered:** Date-based suffixes sort lexicographically in the correct chronological order (`nightly.20260218` < `nightly.20260219`).
- **Stable always wins:** The existing comparison logic (line 52) treats a version without a pre-release suffix as newer than the same version with one. So `0.2.0` (stable) > `0.2.0-nightly.20260219`.

The base version in `project.godot` on the `nightly` branch should be the *next* planned release version (e.g., if stable is `0.1.0`, nightly's base is `0.2.0`). The CI workflow appends the date suffix automatically.

### Update Channel Detection

The updater needs to know which channel the current build belongs to. Two detection methods, used in priority order:

1. **Explicit project setting:** `ProjectSettings.get_setting("application/config/update_channel", "stable")`. The nightly workflow injects `config/update_channel="nightly"` into `project.godot` before export. This is the primary method.
2. **Version string fallback:** If the setting is absent, check whether `Client.app_version` contains `-nightly`. This covers builds made outside CI.

A new static function in `updater.gd`:

```gdscript
static func get_update_channel() -> String:
    var channel: String = ProjectSettings.get_setting(
        "application/config/update_channel", ""
    )
    if not channel.is_empty():
        return channel
    var version: String = ProjectSettings.get_setting(
        "application/config/version", "0.0.0"
    )
    if "-nightly" in version:
        return "nightly"
    return "stable"
```

### Nightly Release Strategy (Rolling Tag)

Unlike stable releases (which create a new tag per version), nightly builds reuse a single `nightly` tag. Each nightly build:

1. Deletes the existing `nightly` release (if any) via `gh release delete nightly --cleanup-tag --yes`.
2. Creates a fresh `nightly` tag pointing at the current commit.
3. Creates a new release with `prerelease: true` and all four platform artifacts.

This keeps exactly one nightly release on the GitHub Releases page, avoiding clutter. The release body includes a short changelog (commits since last stable tag).

Alternative: Instead of rolling a single tag, each nightly could create a new tag like `nightly-20260219`. This preserves history but creates many tags. The rolling approach is recommended for simplicity.

### Nightly CI Workflow (`.github/workflows/nightly.yml`)

```yaml
name: Nightly

on:
  push:
    branches: [nightly]
  schedule:
    - cron: '0 4 * * *'  # Daily at 4:00 AM UTC
  workflow_dispatch:       # Manual trigger

env:
  GODOT_VERSION: "4.5.0"

permissions:
  contents: write

jobs:
  build:
    # Same matrix as release.yml (linux, linux-arm64, windows, macos)
    # ...
    steps:
      # Checkout, addon setup, Godot setup — identical to release.yml

      - name: Generate nightly version
        id: version
        run: |
          BASE_VER=$(grep 'config/version=' project.godot | sed 's/.*="//' | sed 's/"//')
          DATE=$(date +%Y%m%d)
          NIGHTLY_VER="${BASE_VER}-nightly.${DATE}"
          echo "version=$NIGHTLY_VER" >> "$GITHUB_OUTPUT"
          echo "Generated nightly version: $NIGHTLY_VER"

      - name: Inject nightly version
        run: |
          sed -i 's/config\/version="[^"]*"/config\/version="${{ steps.version.outputs.version }}"/' project.godot

      - name: Inject update channel
        run: |
          # Add update_channel under [application] if not present
          if ! grep -q 'config/update_channel' project.godot; then
            sed -i '/config\/version=/a config/update_channel="nightly"' project.godot
          else
            sed -i 's/config\/update_channel="[^"]*"/config\/update_channel="nightly"/' project.godot
          fi

      # Export, package, upload — identical to release.yml

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Generate changelog
        id: changelog
        run: |
          LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
          if [ -n "$LAST_TAG" ]; then
            NOTES=$(git log --oneline "${LAST_TAG}..HEAD" | head -30)
          else
            NOTES=$(git log --oneline -30)
          fi
          echo "notes<<EOF" >> "$GITHUB_OUTPUT"
          echo "Commits since last stable release:" >> "$GITHUB_OUTPUT"
          echo "" >> "$GITHUB_OUTPUT"
          echo "$NOTES" >> "$GITHUB_OUTPUT"
          echo "EOF" >> "$GITHUB_OUTPUT"

      - name: Delete previous nightly release
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release delete nightly --cleanup-tag --yes

      - name: Create nightly release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: nightly
          name: "Nightly ${{ steps.version.outputs.version }}"
          body: ${{ steps.changelog.outputs.notes }}
          draft: false
          prerelease: true
          files: artifacts/*
```

### Nightly Update Check Logic

When the updater determines the build is on the nightly channel, it checks the `nightly` tag release instead of `latest`:

```
Stable channel:
  GET /repos/DaccordProject/daccord/releases/latest
  -> Compare tag_name (semver) against APP_VERSION
  -> Newer if compare_semver(remote, current) > 0

Nightly channel:
  GET /repos/DaccordProject/daccord/releases/tags/nightly
  -> Compare the nightly version embedded in the release name or body
  -> Or compare asset upload timestamps against the build date
  -> Newer if remote nightly date > current nightly date
```

For nightly, the version comparison uses the pre-release suffix date. Since `nightly.20260219` < `nightly.20260220` lexicographically, the existing `compare_semver()` (updater.gd, line 34) handles this correctly — `0.2.0-nightly.20260220` is newer than `0.2.0-nightly.20260219`.

### Sentry Environment Tagging

`error_reporting.gd` should tag nightly builds so crash reports are grouped separately:

```gdscript
# In init_sentry() (line 9), after existing tags:
var channel: String = Updater.get_update_channel()
SentrySDK.set_tag("update_channel", channel)
if channel == "nightly":
    SentrySDK.set_context("runtime", {"environment": "nightly"})
```

This allows filtering GlitchTip/Sentry issues by channel, preventing nightly-only bugs from cluttering stable reports.

### About Dialog Changes

The About dialog in `user_bar.gd` (line 182) should display the update channel:

```
daccord v0.2.0-nightly.20260219
Update channel: nightly
License: MIT
github.com/daccord-projects/daccord
```

### CI Workflow Extension

The existing CI workflow (`.github/workflows/ci.yml`) should be extended to also run on the `nightly` branch:

```yaml
on:
  push:
    branches: [master, nightly]
  pull_request:
    branches: [master, nightly]
```

This ensures lint and tests run for nightly commits before they generate a release.

### Config Persistence

Update preferences in `config.gd` (lines 324-348) apply uniformly to both channels. No new config keys are needed — the channel is determined by the build itself, not user config. The `skipped_version` key works naturally: skipping a nightly version (e.g., `0.2.0-nightly.20260219`) only suppresses that specific nightly.

### Branch Management Strategy

```
master (stable)          nightly
  │                        │
  ├─ v0.1.0 (tag)          │
  │                        │
  │     ┌──────────────────>│  (merge master into nightly)
  │     │                  │
  │     │                  ├─ nightly.20260219 (auto-build)
  │     │                  │
  │     │                  ├─ nightly.20260220 (auto-build)
  │     │                  │
  │     │<─────────────────┤  (merge nightly into master for release)
  │     │                  │
  ├─ v0.2.0 (tag)          │
  │     │                  │
  │     ┌──────────────────>│  (merge master into nightly)
  │                        │
```

- Feature branches merge into `nightly` for testing.
- When ready for release, `nightly` merges into `master`, the version is finalized, and a tag is pushed.
- After tagging, `master` merges back into `nightly` to keep them synchronized.

## Implementation Status

- [x] Semver parsing with pre-release suffix support (`updater.gd`, lines 7-28)
- [x] Pre-release comparison logic: `nightly.YYYYMMDD` sorts chronologically (`updater.gd`, lines 46-61)
- [x] Stable release workflow triggered by `v*` tags (`.github/workflows/release.yml`)
- [x] Prerelease detection in stable releases: tags with hyphens marked as prerelease (`release.yml`, line 277)
- [x] Update signals defined in `AppState` (lines 90-102)
- [x] Update config persistence: `auto_check`, `skipped_version`, `last_check_timestamp` (`config.gd`, lines 324-348)
- [x] Version displayed in About dialog (`user_bar.gd`, line 191)
- [x] "Check for Updates" menu item registered (id 16, `user_bar.gd`, line 60)
- [x] Sentry tag infrastructure for `app_version` (`error_reporting.gd`, line 22)
- [ ] `nightly` git branch created
- [ ] Nightly CI workflow (`.github/workflows/nightly.yml`)
- [ ] Nightly version injection (date-suffixed pre-release string)
- [ ] `update_channel` project setting injection
- [ ] Rolling `nightly` tag release creation
- [ ] `Updater.get_update_channel()` function
- [ ] Channel-aware `check_for_updates()` (nightly tag vs `latest`)
- [ ] Nightly-aware version comparison in update check
- [ ] GitHub Releases API integration in updater
- [ ] Sentry `update_channel` tag
- [ ] About dialog shows update channel
- [ ] CI workflow extended to `nightly` branch
- [ ] Update banner for nightly builds
- [ ] Nightly changelog generation (commits since last stable tag)
- [ ] `workflow_dispatch` for manual nightly triggers

## Tasks

### NIGHTLY-1: No `nightly` branch exists
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** general
- **Notes:** The `nightly` branch has not been created yet. All development currently happens on `master`.

### NIGHTLY-2: No nightly CI workflow
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** ci
- **Notes:** `.github/workflows/nightly.yml` does not exist. Must be created with the version injection, build matrix, and rolling release logic.

### NIGHTLY-3: No update channel detection
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** ci
- **Notes:** `updater.gd` has no `get_update_channel()` function. The build has no way to know if it's stable or nightly.

### NIGHTLY-4: No GitHub Releases API integration
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** api, ci
- **Notes:** `updater.gd` only has semver utilities (lines 7-67). No code checks GitHub for new versions — the "Check for Updates" handler (user_bar.gd, line 356) is a stub that shows a toast. Prerequisite for both stable and nightly update checks.

### NIGHTLY-5: No `update_channel` project setting
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** config
- **Notes:** `project.godot` has no `config/update_channel` key. The nightly workflow needs to inject this, and `updater.gd` needs to read it.

### NIGHTLY-6: CI only runs on `master`
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci
- **Notes:** `.github/workflows/ci.yml` (lines 4-6) only triggers on push/PR to `master`. Must be extended to include `nightly` to catch regressions before nightly builds ship.

### NIGHTLY-7: Sentry does not distinguish channels
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** general
- **Notes:** `error_reporting.gd` tags `app_version` (line 22) but has no `update_channel` tag. Nightly crash reports would be mixed with stable reports in GlitchTip.

### NIGHTLY-8: About dialog does not show channel
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ci, ui
- **Notes:** The About dialog (`user_bar.gd`, line 182) shows the version but not whether the build is stable or nightly.

### NIGHTLY-9: No automated merge strategy
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** general
- **Notes:** Keeping `nightly` and `master` in sync requires manual merges. Could be partially automated with a scheduled workflow that merges `master` into `nightly`.
