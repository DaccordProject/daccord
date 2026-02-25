# Auto-Update


## Overview

This flow describes how daccord checks for new versions, notifies the user, and guides them through updating. All update interaction is centralized in the **App Settings > Updates** page. The app checks for updates automatically on startup and periodically in the background. When an update is found, the user can manage it from the Updates settings page — checking manually, downloading, skipping versions, or restarting to apply. Updates are sourced from GitHub Releases via the public API.

## User Steps

### Passive Update Check (Background)

1. User launches daccord.
2. After server connections are established (or after a short delay if no servers are configured), the client silently checks GitHub Releases for a newer version.
3. **No update available:** Nothing happens. The user is never told "you're up to date" unless they open Settings > Updates and click "Check for Updates".
4. **Update available:** The version info is cached by the Updater autoload. The next time the user opens Settings > Updates, the available update is displayed.
5. If automatic checking is disabled, no background checks occur.

### Manual Update Check (Settings > Updates)

1. User opens App Settings (from the user bar menu or the welcome screen settings button).
2. User navigates to the "Updates" page.
3. The page shows the current version and a "Check for Updates" button.
4. User clicks "Check for Updates".
5. **No update:** Status text: "You're on the latest version."
6. **Update available:** An update row appears showing the new version with "Download & Install", "View Changes", and "Skip This Version" buttons.
7. **Network error:** Error text: "Check failed: [error message]."

### Download & Install (Settings > Updates)

1. User clicks "Download & Install" on the Updates page.
2. A progress bar appears inline showing download percentage and size.
3. Download completes. A "Restart to Update" button appears.
4. **Restart to Update:** App saves any draft message text in the composer, quits, and launches the new version.
5. **Cancel:** User can cancel the download at any time. Partial file is deleted. The download button reappears.
6. **Download fails:** Error text shown with the download button available to retry.
7. On non-Linux platforms, "Download & Install" opens the GitHub release page in the browser via `OS.shell_open()`.

### Skipping a Version

1. On the Updates page, user clicks "Skip This Version".
2. That version is saved in config. The client won't prompt for it again.
3. Status text confirms: "Version v1.2.0 skipped."
4. If a newer version is released later, the client will prompt for that one.

## Signal Flow

```
Startup Update Check:
  Client._ready() (after connections established)
    -> Updater.check_for_updates(false)
    -> HTTPRequest to GitHub Releases API
    -> Response parsed: latest tag vs Client.app_version
    -> If newer:
      -> AppState.update_available.emit(version_info)
      -> Updater caches version_info
    -> If current or error: no user-facing action

Manual Check (Settings > Updates):
  app_settings._on_check_updates_pressed()
    -> Updater.check_for_updates(manual=true)
    -> If newer: AppState.update_available.emit(version_info)
      -> app_settings shows update row with download/skip buttons
    -> If current: AppState.update_check_complete.emit(null)
      -> app_settings shows "You're on the latest version."
    -> If error: AppState.update_check_failed.emit(error)
      -> app_settings shows error text

Download (Settings > Updates):
  app_settings._on_download_pressed()
    -> Updater.download_update(version_info)
    -> AppState.update_download_started.emit()
      -> Shows inline progress bar
    -> HTTPRequest downloads asset
    -> AppState.update_download_progress.emit(percent)
      -> Updates progress bar and size label
    -> On complete: AppState.update_download_complete.emit(path)
      -> Shows "Restart to Update" button
    -> On error: AppState.update_download_failed.emit(error)
      -> Shows error text, download button reappears
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Defines `update_available`, `update_download_started`, `update_download_progress`, `update_download_complete`, `update_download_failed`, `update_check_complete`, `update_check_failed` signals |
| `scripts/autoload/config.gd` | Persists `skipped_version`, `auto_check` preference, `last_check_timestamp` under `[updates]` section |
| `scripts/autoload/updater.gd` | Autoload: semver utilities, GitHub Releases API check (`check_for_updates()`), periodic timer, startup hook, dismiss/skip version logic, download/extract/install, binary replacement and restart. |
| `scenes/user/app_settings.gd` | Updates page with: current version display, "Check for Updates" button, update status, download progress, restart button, auto-check toggle, master server URL. |
| `scripts/autoload/client.gd` | Holds `app_version` (reads from `project.godot`). |
| `scenes/messages/update_download_dialog.gd/.tscn` | Modal download dialog (retained but no longer instantiated from banner; available for programmatic use). |
| `project.godot` | Sets `application/config/version` |
| `tests/unit/test_updater.gd` | Unit tests for semver parsing, comparison, and `is_newer` |

## Implementation Details

### Version Constant

The app version is read from `project.godot` via `ProjectSettings.get_setting("application/config/version")` and stored on `Client.app_version`.

### Update Source

GitHub Releases API (`GET https://api.github.com/repos/DaccordProject/daccord/releases/latest`):
- No custom server infrastructure needed.
- Release tags follow semver (e.g., `v1.2.0`).
- Response includes `tag_name`, `body` (release notes as markdown), `assets[]` with `browser_download_url` and `size`.
- Rate limit: 60 requests/hour unauthenticated (more than sufficient for hourly checks).

### Update Check Logic

The `Updater` autoload:
1. Reads `Client.app_version` and parses as semver.
2. GETs the latest release from GitHub.
3. Parses `tag_name` (strip leading `v`), compares against current version.
4. If newer and not in `Config.skipped_version` and not already dismissed this session: emits `AppState.update_available` with a dictionary `{ "version": "1.2.0", "notes": "...", "download_url": "...", "download_size": 12345678 }`.
5. Saves `last_check_timestamp` in config to throttle passive checks (at most once per hour).

### Settings-Based Update UX

All update interaction is centralized in **App Settings > Updates**:
- **Current version** displayed at the top.
- **Check for Updates** button with inline status text.
- **Update available row** (hidden until update found): version label, "View Changes", "Download & Install", "Skip This Version".
- **Download progress** (hidden until downloading): progress bar, size label, cancel button.
- **Restart to Update** button (hidden until download complete).
- **Error label** for failed checks or downloads.
- **Auto-check toggle** and master server URL below a separator.

When the settings page opens, it checks `Updater.get_latest_version_info()` and `Updater.is_update_ready()` to show the current state immediately.

### Download & Install

- On Linux: downloads tar.gz from GitHub release assets, extracts to `user://update_staging`, replaces the current binary, and relaunches.
- On Windows/macOS: opens the GitHub release page in the browser via `OS.shell_open()`.

### Config Persistence

Keys in `user://config.cfg` under `[updates]` section:
- `auto_check`: `bool` (default `true`) — whether to check on startup and periodically.
- `skipped_version`: `String` — version the user explicitly skipped (e.g., `"1.2.0"`).
- `last_check_timestamp`: `int` — Unix timestamp of last successful check (throttle to once per hour).

## Implementation Status

- [x] `Client.app_version` reads from `project.godot`'s `config/version`
- [x] Version displayed in About dialog with license and GitHub link
- [x] "About" menu item handler in user_bar.gd (id 10)
- [x] Updater autoload with semver utilities (`scripts/autoload/updater.gd`)
- [x] GitHub Releases API integration (`Updater.check_for_updates()`)
- [x] Semver comparison logic (with unit tests)
- [x] Startup update check (after connection or 5s delay)
- [x] Periodic re-check (hourly timer)
- [x] Centralized Updates page in App Settings with check button, status, download, restart
- [x] Skip-version logic (persistent via config)
- [x] Release notes link (opens GitHub release page in browser)
- [x] Inline download progress in settings page
- [x] In-place binary replacement (Linux)
- [x] "Restart to Update" flow in settings
- [x] Draft message preservation on restart
- [x] Config persistence for update preferences (`auto_check`, `skipped_version`, `last_check_timestamp`)
- [x] Update signals in AppState (`update_available`, `update_check_complete`, `update_check_failed`, `update_download_started`, `update_download_progress`, `update_download_complete`, `update_download_failed`)
- [x] Platform-specific update strategies (Linux: in-place binary replacement; Windows/macOS: fallback to `OS.shell_open()`)

## Removed UI Surfaces

The following update UI surfaces were removed to centralize updates into Settings:
- Update banner in message_view (removed from `message_view.tscn`)
- "Check for Updates" / "Restart to Update" menu item in user bar
- "Update ready" persistent label in user bar
- "[Update ready]" window title suffix in main_window
