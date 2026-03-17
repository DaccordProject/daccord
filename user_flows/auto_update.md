# Auto-Update

Priority: 42
Depends on: Cross-Platform GitHub Releases
Status: Complete

Automatic and manual update checking via GitHub Releases API, with download, install, skip, and restart functionality centralized in App Settings > Updates.

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
