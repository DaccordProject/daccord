# GDPR & Data Privacy

## Overview

daccord provides several GDPR-relevant features across its client and server interactions: account deletion (right to erasure), client-side data export (profile config), opt-in error reporting with PII scrubbing, and password/2FA management for data security. Full GDPR compliance depends on the accordserver backend; this document covers the client-side controls and identifies gaps.

## User Steps

### Deleting an account (right to erasure)

1. User opens Server Settings (via space context menu or user bar).
2. User navigates to "Delete Account" page.
3. User reads the red warning: "This action is irreversible. All your data will be permanently deleted."
4. User enters their password and types "DELETE" in the confirmation field.
5. User clicks "Delete My Account".
6. Client sends `DELETE /users/@me` with the password to the server.
7. On success, the application quits via `tree.quit()`.

### Changing password (data security)

1. User opens Server Settings → "Change Password".
2. User enters current password, new password (min 8 chars), and confirms.
3. Client sends `POST /auth/password` to the server.
4. Success/error feedback is shown inline.

### Exporting client data (partial data portability)

1. User opens App Settings → "Profiles".
2. User clicks "Export" on a profile row.
3. A save dialog opens for a `.daccord-profile` file.
4. `Config.export_config()` writes the profile's ConfigFile to disk.

### Controlling error reporting (consent)

1. On first launch (after onboarding), a consent dialog asks: "Help improve daccord by sending anonymous crash and error reports? No personal data is included."
2. User clicks "Enable" or "No thanks".
3. The preference is stored in config and never asked again.
4. User can toggle error reporting later in App Settings → Notifications.

### Enabling 2FA (data security)

1. User opens Server Settings → "Two-Factor Auth".
2. User provides password, receives TOTP secret, enters verification code.
3. Backup codes are displayed for offline recovery.

## Signal Flow

```
Account deletion:
  User clicks "Delete My Account"
    → UserSettingsDanger._on_delete_account()
      → AccordClient.users.delete_me({"password": pw})    [DELETE /users/@me]
      → on success: SceneTree.quit()

Password change:
  User clicks "Change Password"
    → UserSettingsDanger._on_password_save()
      → AccordClient.auth.change_password({...})           [POST /auth/password]
      → inline success/error label

Error reporting consent:
  First launch (no preference stored)
    → main_window._show_error_reporting_consent()
      → Config.set_error_reporting_consent_shown()
      → User: "Enable"  → Config.set_error_reporting_enabled(true) → ErrorReporting.init_sentry()
      → User: "No thanks" → Config.set_error_reporting_enabled(false)

Profile export:
  User clicks "Export"
    → UserSettingsProfilesPage._export_profile()
      → Config.export_config(path)                         [writes .daccord-profile file]
```

## Key Files

| File | Role |
|------|------|
| `scenes/user/user_settings_danger.gd` | Change Password and Delete Account page builders and handlers |
| `scenes/user/server_settings.gd` | Per-server settings panel routing Delete Account/Password/2FA pages |
| `scenes/user/app_settings.gd` | App-wide settings panel with error reporting toggle (line 258) |
| `scenes/user/user_settings_profiles_page.gd` | Profile export/import (lines 196-210) |
| `scenes/user/user_settings_twofa.gd` | 2FA enable/disable/backup codes page |
| `scripts/autoload/client_mutations.gd` | `delete_account()` mutation (line 427) |
| `scripts/autoload/client.gd` | `delete_account()` wrapper (line 548) |
| `scripts/autoload/config.gd` | `export_config()` / `import_config()` (lines 547-569), error reporting prefs (lines 291-304) |
| `scripts/autoload/config_profiles.gd` | Profile deletion with local file cleanup (line 76) |
| `scripts/autoload/error_reporting.gd` | Sentry init, PII scrubbing, consent gating |
| `scenes/main/main_window.gd` | Error reporting consent dialog (line 615) |
| `addons/accordkit/rest/endpoints/users_api.gd` | `delete_me()` — `DELETE /users/@me` (line 72) |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `change_password()`, 2FA endpoints (lines 38-61) |
| `project.godot` | `send_default_pii=false` Sentry setting (line 74) |

## Implementation Details

### Account Deletion (Right to Erasure)

The Delete Account page is built by `UserSettingsDanger.build_delete_page()` (line 108). It displays:

- A red warning label about irreversibility (line 119)
- A secret password field (line 130)
- A confirmation field requiring the exact text "DELETE" (lines 134-137)
- A red-styled danger button "Delete My Account" (lines 142-156)

On click, `_on_delete_account()` (line 159) validates:
- Password is not empty (line 163)
- Confirmation text matches "DELETE" exactly (line 167)

The REST call is `DELETE /users/@me` with `{"password": pw}` via `AccordClient.users.delete_me()` (`users_api.gd:72`). Alternatively, `Client.delete_account()` (`client.gd:548`) routes through `client_mutations.gd:427`, which picks the first connected `AccordClient`.

On success, the app exits immediately with `_tree.quit()` (line 189). No local data cleanup occurs — the profile config, emoji cache, and registry remain on disk.

### Password Change (Data Security)

Built by `UserSettingsDanger.build_password_page()` (line 23). Three secret fields: current, new, confirm. Validates new password is at least 8 characters (line 63) and both entries match (line 67). Calls `AccordClient.auth.change_password()` (`auth_api.gd:38`) which POSTs to `/auth/password`. Success clears the fields and shows a green message (lines 89-97).

### Error Reporting Consent & PII Scrubbing

**Consent flow:** On first launch, `main_window._show_error_reporting_consent()` (line 615) presents a `ConfirmationDialog`. The consent flag is written immediately via `Config.set_error_reporting_consent_shown()` (line 617) so the dialog never reappears, even if dismissed via the X button. Default is disabled (safe).

**PII scrubbing:** `error_reporting.gd:_before_send()` (line 35) gates on the enabled flag and filters editor events. `_scrub_pii()` (line 43) redacts:
- Bearer tokens: `Bearer [REDACTED]` (line 52)
- `token=` query parameters: `token=[REDACTED]` (line 55)
- URLs with port numbers: `[URL REDACTED]` (line 58)

**Project settings:** `project.godot` sets `send_default_pii=false` (line 74), so the Sentry SDK never auto-collects PII.

**Breadcrumbs:** Space/channel IDs and UI events are recorded (lines 62-73) but no message content or usernames.

### Profile Export (Partial Data Portability)

`UserSettingsProfilesPage._export_profile()` (line 196) opens a FileDialog in save mode for `*.daccord-profile`. It calls `Config.export_config()` (`config.gd:547`) which saves the in-memory ConfigFile to the chosen path.

**What's exported:** Client-side preferences only — voice/video settings, sound settings, notification settings, error reporting preference, UI scale, emoji skin tone, per-server mute settings, master server URL, space folder assignments, and server connection credentials (base URL, space name, token, username, password).

**What's NOT exported:** Server-side user data — messages, profile information (display name, avatar, bio), reactions, attachments, DM history, roles, or any other data stored on the accordserver.

### Profile Deletion (Local Data Cleanup)

`config_profiles.gd:delete()` (line 76) removes a profile's local directory including its emoji cache and config file, and removes the entry from the profile registry. The "default" profile cannot be deleted (line 77). If deleting the active profile, it switches to "default" first (lines 79-80).

### 2FA (Data Security)

`user_settings_twofa.gd` manages 2FA through three AccordKit endpoints:
- `POST /auth/2fa/enable` — returns TOTP secret
- `POST /auth/2fa/verify` — confirms setup with a code
- `POST /auth/2fa/disable` — requires password
- `GET /auth/2fa/backup-codes` — retrieves offline recovery codes

### OAuth Connections (Read-Only)

`server_settings.gd:_build_connections_page()` (line 139) fetches linked connections via `GET /users/@me/connections` and displays them in a read-only list. No disconnect or revoke functionality is exposed.

## Implementation Status

- [x] Account deletion with password + "DELETE" confirmation
- [x] Password change with validation
- [x] Opt-in error reporting consent dialog (first launch)
- [x] PII scrubbing in error reports (tokens, URLs)
- [x] `send_default_pii=false` in project settings
- [x] Error reporting toggle in App Settings → Notifications
- [x] Client config export (`.daccord-profile`)
- [x] Client config import with pre-import backup
- [x] Local profile deletion (config + emoji cache)
- [x] 2FA enable/disable/verify with backup codes
- [x] OAuth connections listing (read-only)
- [ ] Server-side data export (messages, profile, attachments)
- [ ] Local data cleanup after account deletion
- [ ] Privacy policy / terms display in-app
- [ ] OAuth connection disconnect/revoke
- [ ] Per-server data deletion request
- [ ] Message content purge confirmation (cascade behavior unclear)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side data export | High | Users cannot download their messages, attachments, or profile data from the server. Only client config is exportable. GDPR Article 20 (data portability) requires export of personal data in a machine-readable format. |
| No local cleanup after account deletion | Medium | `_on_delete_account()` calls `tree.quit()` (line 189) but does not clear `user://profiles/`, emoji cache, or the profile registry. Stale credentials and cached data remain on disk. |
| No privacy policy display | Medium | No in-app privacy policy, terms of service, or data processing disclosure. Users have no way to review what data is collected or how it's processed. |
| Message cascade behavior unknown | Medium | `DELETE /users/@me` deletes the account, but it's unclear whether server-side messages, reactions, and attachments are also purged. GDPR Article 17 requires erasure of all personal data. |
| OAuth connections are read-only | Low | `server_settings.gd:139` lists connections but provides no disconnect/revoke button. Users cannot revoke third-party access from within daccord. |
| No data retention policy | Low | No indication of how long server-side data is retained. No TTL on message cache, attachment storage, or audit logs. |
| Error breadcrumbs include IDs | Low | `error_reporting.gd` sends space/channel IDs as breadcrumbs (lines 75-83) and Sentry tags (lines 124-135). While not PII, these are pseudonymous identifiers that could be cross-referenced. |
| Exported profile includes credentials | Low | `Config.export_config()` writes the full ConfigFile including server tokens and stored username/password pairs (`config.gd:540-543`). The export file is unencrypted. |
