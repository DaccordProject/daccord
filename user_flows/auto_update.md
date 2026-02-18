# Auto-Update

## Overview

This flow describes how daccord checks for new versions, notifies the user, and guides them through updating. The goal is a non-intrusive, user-controlled experience: the app checks for updates on startup and periodically, shows a dismissible banner when an update is available, and lets the user choose when to download and install. Updates are sourced from GitHub Releases via the public API.

None of this is implemented yet. This document serves as a UX specification.

## User Steps

### Passive Update Check (Startup)

1. User launches daccord.
2. After server connections are established (or after a short delay if no servers are configured), the client silently checks GitHub Releases for a newer version.
3. **No update available:** Nothing happens. The user is never told "you're up to date" unless they asked.
4. **Update available:** A slim banner slides down from the top of the content area: "daccord v1.2.0 is available. [View changes] [Update] [Dismiss]".
5. User can click **Dismiss** (or the X) to hide the banner for this session. The same version won't re-prompt until the next app launch.
6. User can click **View changes** to see the release notes in-app (or open the GitHub release page in the browser).
7. User can click **Update** to begin the download.

### Manual Update Check (User Bar Menu)

1. User clicks the menu button (gear icon) in the user bar at the bottom of the sidebar.
2. User selects "Check for Updates" from the popup menu.
3. A brief spinner appears next to the menu item text (or in a small toast): "Checking for updates..."
4. **No update:** Toast message: "You're on the latest version (v1.1.0)."
5. **Update available:** Same banner as the passive flow appears. If the user had previously dismissed it, it reappears.
6. **Network error:** Toast message: "Couldn't check for updates. Try again later."

### About Dialog (Version Info)

1. User clicks the menu button in the user bar.
2. User selects "About".
3. A dialog shows: app name, current version, build date, license (GPL-3.0), and a link to the GitHub repository.
4. The dialog also shows whether an update is available and provides an "Update" button if so.

### Download & Install

1. User clicks "Update" (from banner, About dialog, or toast).
2. A modal dialog appears: "Downloading daccord v1.2.0..." with a progress bar.
3. Download completes. Dialog updates: "Download complete. Restart to apply the update." [Restart Now] [Later]
4. **Restart Now:** App saves any draft message text in the composer, quits, and launches the new version.
5. **Later:** Dialog closes. A persistent (but non-intrusive) indicator appears in the user bar or title bar showing "Update ready". The update applies on next manual restart.
6. **Download fails:** Dialog shows error with a "Retry" button: "Download failed: [error message]. [Retry] [Cancel]"

### Skipping a Version

1. In the update banner, user clicks a "Skip this version" option (accessible via a small dropdown or secondary action).
2. That version is saved in config. The client won't prompt for it again.
3. If a newer version is released later, the client will prompt for that one.

## Signal Flow

```
Startup Update Check:
  Client._ready() (after connections established)
    -> Updater.check_for_updates()
    -> HTTPRequest to GitHub Releases API
    -> Response parsed: latest tag vs APP_VERSION
    -> If newer:
      -> AppState.update_available.emit(version_info)
      -> main_window._on_update_available()
        -> Shows update banner in content area
    -> If current or error: no signal emitted

Manual Check:
  user_bar._on_menu_id_pressed(12)  # "Check for Updates"
    -> Updater.check_for_updates(manual=true)
    -> If newer: AppState.update_available.emit(version_info)
    -> If current: AppState.update_check_complete.emit(null)
      -> user_bar shows "Up to date" toast
    -> If error: AppState.update_check_failed.emit(error)
      -> user_bar shows error toast

Download:
  update_banner "Update" clicked / about_dialog "Update" clicked
    -> Updater.download_update(version_info)
    -> AppState.update_download_started.emit()
      -> Shows download dialog with progress bar
    -> HTTPRequest downloads asset
    -> AppState.update_download_progress.emit(percent)
      -> Updates progress bar
    -> On complete: AppState.update_download_complete.emit(path)
      -> Dialog shows "Restart to apply"
    -> On error: AppState.update_download_failed.emit(error)
      -> Dialog shows error with Retry
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Would add `update_available`, `update_download_started`, `update_download_progress`, `update_download_complete`, `update_download_failed`, `update_check_complete`, `update_check_failed` signals |
| `scripts/autoload/config.gd` | Would persist `skipped_version`, `dismissed_version`, `auto_update_enabled` preference, `last_update_check` timestamp |
| `scripts/autoload/client.gd` | Would hold `APP_VERSION` constant and trigger update check after connections are established |
| `scenes/sidebar/user_bar.gd` | Would add "Check for Updates" menu item (id 12) and "About" handler (id 10, currently unhandled) |
| `scenes/main/main_window.gd` | Would host the update banner in content area and update download dialog |
| `project.godot` | Would set `application/config/version` for the canonical version string |

## Implementation Details

### Version Constant

The app currently has no version string anywhere. `project.godot` does not define `application/config/version`. The first step is adding a `APP_VERSION` constant (e.g., in `client.gd` or a dedicated `version.gd` autoload) and setting the version in `project.godot` so it can be read at runtime via `ProjectSettings.get_setting("application/config/version")`.

### Update Source

GitHub Releases API (`GET https://api.github.com/repos/daccord-projects/daccord/releases/latest`) is the natural choice:
- No custom server infrastructure needed.
- Release tags follow semver (e.g., `v1.2.0`).
- Response includes `tag_name`, `body` (release notes as markdown), `assets[]` with `browser_download_url` and `size`.
- Rate limit: 60 requests/hour unauthenticated (more than sufficient for hourly checks).

### Update Check Logic

An `Updater` class (autoload or instantiated by `Client`) would:
1. Read `APP_VERSION` and parse as semver.
2. GET the latest release from GitHub.
3. Parse `tag_name` (strip leading `v`), compare against current version.
4. If newer and not in `Config.skipped_version` and not already dismissed this session: emit `AppState.update_available` with a dictionary `{ "version": "1.2.0", "notes": "...", "download_url": "...", "size": 12345678 }`.
5. Save `last_update_check` timestamp in config to avoid checking too frequently (at most once per hour).

### Update Banner UX

- **Position:** Top of the content area, below the tab bar / topic bar, above the message list. Same horizontal region as the message view -- not over the sidebar.
- **Style:** Matches the existing theme (`discord_dark.tres`). Accent color for the background (subtle blue or green). White text. Small font size.
- **Layout:** `[icon] daccord v1.2.0 is available  [View changes]  [Update]  [X]`
- **Animation:** Slides down with a tween (consistent with the drawer animation style in `main_window.gd`, lines 209-222).
- **Dismissal:** Clicking X hides the banner for this session. Stored in memory only (not config), so it reappears on next launch.
- **Non-blocking:** The banner does not prevent the user from chatting. It compresses the message list slightly but doesn't overlay messages.

### Download Dialog UX

- **Style:** Modal overlay (same pattern as `add_server_dialog` -- a `ColorRect` backdrop with centered `Panel`).
- **Progress bar:** A `ProgressBar` node showing download percentage. Below it, text showing "12.4 MB / 45.2 MB".
- **Cancel:** User can cancel the download at any time. Partial file is deleted.
- **Restart:** On "Restart Now", the app saves composer draft text to config, then calls `OS.execute()` to launch the new binary and `get_tree().quit()` to exit.

### Platform Considerations

Godot exports to Windows, macOS, and Linux. Each platform has different update mechanics:
- **Windows:** Download `.exe` or `.zip` from GitHub release assets. Replace the binary. May require the app to close itself before overwriting (a small updater script or launching the new binary which waits for the old process to exit).
- **Linux:** Download the binary or AppImage. Similar replacement strategy.
- **macOS:** Download `.dmg` or `.app.zip`. macOS may require notarization for Gatekeeper. Replacing the running binary is more complex.
- **Fallback:** If in-place update is too complex for a platform, the "Update" button opens the GitHub release page in the user's browser via `OS.shell_open()`. This is the simplest MVP approach.

### Config Persistence

New keys in `user://config.cfg` under an `[updates]` section:
- `auto_check`: `bool` (default `true`) -- whether to check on startup.
- `skipped_version`: `String` -- version the user explicitly skipped (e.g., `"1.2.0"`).
- `last_check_timestamp`: `int` -- Unix timestamp of last successful check (throttle to once per hour).

### User Bar Menu Changes

`user_bar.gd` currently has a menu with status options, "About" (id 10), and "Quit" (id 11). The "About" handler is missing from the `match` statement (line 52). Changes needed:
- Add `10:` case to show an About dialog with version info.
- Add `popup.add_item("Check for Updates", 12)` after the "About" item (line 19).
- Add `12:` case to trigger `Updater.check_for_updates(true)`.

## Implementation Status

- [ ] `APP_VERSION` constant defined anywhere in the codebase
- [ ] Version displayed in window title or About dialog
- [ ] "About" menu item handler in user_bar.gd (id 10 has no match case)
- [ ] "Check for Updates" menu item in user bar
- [ ] Updater autoload or class
- [ ] GitHub Releases API integration
- [ ] Semver comparison logic
- [ ] Startup update check (after connection or delay)
- [ ] Periodic re-check (hourly)
- [ ] Update available banner in content area
- [ ] Banner dismiss / skip-version logic
- [ ] Release notes display (in-app or browser)
- [ ] Download dialog with progress bar
- [ ] In-place binary replacement
- [ ] "Restart Now" / "Later" flow
- [ ] Draft message preservation on restart
- [ ] Config persistence for update preferences
- [ ] "Update ready" indicator after download
- [ ] Platform-specific update strategies (Windows/macOS/Linux)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No version constant | High | No `APP_VERSION` or `application/config/version` in `project.godot`. Cannot compare versions without one. This is the prerequisite for everything else. |
| "About" menu item does nothing | Medium | `user_bar.gd` adds "About" (id 10, line 19) but the `_on_menu_id_pressed` match block (line 52) has no case for id 10. Users click "About" and nothing happens. |
| No update check mechanism | High | No code checks for new versions. Users must manually visit GitHub to discover updates. |
| No download/install flow | Medium | Even once an update is detected, there's no in-app way to download or apply it. The MVP could simply open the release page in the browser via `OS.shell_open()`. |
| No update preferences in config | Low | `config.gd` has no `[updates]` section. Users cannot disable auto-check or skip versions. |
| Cross-platform update complexity | Medium | In-place binary replacement is platform-specific and error-prone. The pragmatic first step is browser-based download (`OS.shell_open(release_url)`), upgrading to in-app download later. |
