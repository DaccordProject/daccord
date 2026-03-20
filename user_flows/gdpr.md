# GDPR & Data Privacy

Priority: 57
Depends on: User Management

## Overview

daccord provides several GDPR-relevant features across its client and server interactions: account deletion (right to erasure) with full server-side cascade, server-side data export (data portability), client-side config export, opt-in error reporting with PII scrubbing, privacy policy display, data retention disclosure, OAuth connection management, and password/2FA management for data security.

## User Steps

### Deleting an account (right to erasure)

1. User opens Server Settings (via space context menu or user bar).
2. User navigates to "Delete Account" page.
3. User reads the red warning: "This action is irreversible. All your data will be permanently deleted."
4. User enters their password and types "DELETE" in the confirmation field.
5. User clicks "Delete My Account".
6. Client sends `DELETE /users/@me` with the password to the server.
7. Server verifies password, then cascade-deletes all user data (tokens, messages, reactions, memberships, applications, DM participations, bans).
8. On success, the application quits via `tree.quit()`.

### Exporting server-side data (data portability)

1. User opens Server Settings → "Privacy & Data".
2. User clicks "Request Data Export".
3. Client sends `GET /users/@me/data-export` to the server.
4. Server returns JSON containing user profile, messages, spaces, and relationships.
5. A save dialog opens for a `.json` file.
6. User chooses a location and the export is written to disk.

### Changing password (data security)

1. User opens Server Settings → "Change Password".
2. User enters current password, new password (min 8 chars), and confirms.
3. Client sends `POST /auth/change-password` to the server.
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

### Viewing privacy policy & terms

1. User opens App Settings → "About".
2. Under "Privacy & Legal", links to Privacy Policy and Terms of Service are displayed.
3. Clicking either link opens the URL in the system browser.

### Disconnecting an OAuth connection

1. User opens Server Settings → "Connections".
2. Each connection row now has a red "Disconnect" button.
3. User clicks "Disconnect" to send `DELETE /users/@me/connections/{id}`.
4. On success, the connection row is removed from the list.

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
      → Server: verify_user_password() → db::admin::delete_user()
        → Cascade: tokens, messages, reactions, members, bans, applications
      → on success: Config.wipe_active_profile() → SceneTree.quit()

Server-side data export:
  User clicks "Request Data Export"
    → server_settings._on_request_data_export()
      → AccordClient.users.request_data_export()           [GET /users/@me/data-export]
      → Server: collects user profile, messages, spaces, relationships
      → FileDialog → FileAccess.open() → write JSON to disk

Password change:
  User clicks "Change Password"
    → UserSettingsDanger._on_password_save()
      → AccordClient.auth.change_password({...})           [POST /auth/change-password]
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

OAuth disconnect:
  User clicks "Disconnect"
    → server_settings._on_disconnect_connection(conn_id, row)
      → AccordClient.rest.make_request("DELETE", "/users/@me/connections/" + conn_id)
      → on success: row.queue_free()
```

## Key Files

| File | Role |
|------|------|
| `scenes/user/user_settings_danger.gd` | Change Password and Delete Account page builders and handlers |
| `scenes/user/server_settings.gd` | Per-server settings panel: Connections with disconnect, Privacy & Data page with export |
| `scenes/user/app_settings.gd` | App-wide settings panel with error reporting toggle (line 704) |
| `scenes/user/app_settings_about_page.gd` | About page with Privacy & Legal links |
| `scenes/user/user_settings_profiles_page.gd` | Profile export/import |
| `scenes/user/user_settings_twofa.gd` | 2FA enable/disable/backup codes page |
| `scripts/autoload/client_mutations.gd` | `delete_account()` mutation (line 468) |
| `scripts/autoload/client.gd` | `delete_account()` wrapper |
| `scripts/autoload/config.gd` | `export_config()` / `import_config()`, error reporting prefs |
| `scripts/autoload/config_profiles.gd` | Profile deletion with local file cleanup |
| `scripts/autoload/error_reporting.gd` | Sentry init, PII scrubbing, consent gating |
| `scenes/main/main_window.gd` | Error reporting consent dialog |
| `addons/accordkit/rest/endpoints/users_api.gd` | `delete_me()`, `request_data_export()` |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `change_password()`, 2FA endpoints |
| `project.godot` | `send_default_pii=false` Sentry setting |
| `../accordserver/src/routes/users.rs` | `delete_current_user()`, `export_current_user_data()` |
| `../accordserver/src/routes/auth.rs` | `verify_user_password()` (now pub(crate)) |
| `../accordserver/src/db/admin.rs` | `delete_user()` cascade logic |

## Implementation Details

### Account Deletion (Right to Erasure)

The Delete Account page is built by `UserSettingsDanger.build_delete_page()`. It displays:

- A red warning label about irreversibility
- A secret password field
- A confirmation field requiring the exact text "DELETE"
- A red-styled danger button "Delete My Account"

On click, `_on_delete_account()` validates password is not empty and confirmation text matches "DELETE".

The REST call is `DELETE /users/@me` with `{"password": pw}` via `AccordClient.users.delete_me()`. The server-side handler (`users.rs:delete_current_user()`) verifies the password using `verify_user_password()`, then calls `db::admin::delete_user()` which performs a full cascade deletion:

1. `user_tokens` — all session tokens
2. `bot_tokens` — all bot tokens
3. `applications` — all owned applications
4. `reactions` — all reactions by the user
5. `dm_participants` — all DM participations
6. `member_roles` — all role assignments
7. `members` — all space memberships
8. `bans` — all ban records where user is banned
9. NULLs out `banned_by`, `inviter_id`, `creator_id`, `owner_id` references
10. `messages` — all messages authored by the user
11. `users` — the user record itself

The client also calls `Config.wipe_active_profile()` to clean up local data before `tree.quit()`.

### Server-Side Data Export (Data Portability)

The Privacy & Data page in Server Settings (`server_settings.gd:_build_privacy_page()`, line 222) provides a "Request Data Export" button.

On click, `_on_request_data_export()` (line 286) calls `AccordClient.users.request_data_export()` which sends `GET /users/@me/data-export`. The server-side handler (`users.rs:export_current_user_data()`) collects:

- **User profile**: Full user object (username, display name, avatar, bio, created_at, etc.)
- **Spaces**: List of spaces the user is a member of (id, name)
- **Messages**: All messages authored by the user (id, channel_id, content, created_at)
- **Relationships**: All friend/block relationships
- **Export metadata**: Export date, message count

The response is saved as a JSON file via a FileDialog save prompt.

### Password Change (Data Security)

Built by `UserSettingsDanger.build_password_page()`. Three secret fields: current, new, confirm. Validates new password is at least 8 characters and both entries match. Calls `AccordClient.auth.change_password()` which POSTs to `/auth/change-password`.

### Error Reporting Consent & PII Scrubbing

**Consent flow:** On first launch, `main_window._show_error_reporting_consent()` presents a `ConfirmationDialog`. The consent flag is written immediately so the dialog never reappears. Default is disabled (safe).

**PII scrubbing:** `error_reporting.gd:scrub_pii_text()` redacts:
- Bearer tokens: `Bearer [REDACTED]`
- `token=` query parameters: `token=[REDACTED]`
- Hex token strings: `[TOKEN REDACTED]`
- URLs with port numbers: `[URL REDACTED]`

**Project settings:** `project.godot` sets `send_default_pii=false`, so the Sentry SDK never auto-collects PII.

**Breadcrumbs:** Space/channel IDs are truncated to the last 4 characters via `_truncate_id()` before being recorded in breadcrumbs and Sentry tags. No message content or usernames are included.

### Profile Export (Partial Data Portability)

`UserSettingsProfilesPage._export_profile()` opens a FileDialog in save mode for `*.daccord-profile`. It calls `Config.export_config()` which saves the in-memory ConfigFile to the chosen path.

**What's exported:** Client-side preferences only — voice/video settings, sound settings, notification settings, error reporting preference, UI scale, emoji skin tone, per-server mute settings, master server URL, space folder assignments, and server connection metadata (base URL, space name). Credentials (`token`, `password`) are stripped by `export_config()`.

**What's NOT exported:** Server-side user data — use the server-side data export for messages, profile information, and other server data.

### Privacy Policy & Terms Display

`app_settings_about_page.gd` includes a "Privacy & Legal" section with:
- A description of daccord's data practices
- A link to the Privacy Policy (`https://daccord.cc/privacy`)
- A link to the Terms of Service (`https://daccord.cc/terms`)

Both links open in the system browser via Godot's `LinkButton.uri` property.

### OAuth Connection Disconnect

`server_settings.gd:_fetch_connections()` now renders each connection row with a red "Disconnect" button (line 199). Clicking it calls `_on_disconnect_connection()` (line 209) which sends `DELETE /users/@me/connections/{id}`. On success, the connection row is removed from the UI.

### Profile Deletion (Local Data Cleanup)

`config_profiles.gd:delete()` removes a profile's local directory including its emoji cache and config file, and removes the entry from the profile registry. The "default" profile cannot be deleted.

### 2FA (Data Security)

`user_settings_twofa.gd` manages 2FA through AccordKit endpoints:
- `POST /auth/2fa/enable` — returns TOTP secret
- `POST /auth/2fa/verify` — confirms setup with a code
- `POST /auth/2fa/disable` — requires password
- `POST /auth/2fa/backup-codes` — retrieves offline recovery codes

### Data Retention & Deletion Disclosure

The Privacy & Data page (`server_settings.gd:_build_privacy_page()`, line 222) displays:
- **Data Deletion**: Explains that account deletion permanently removes all personal data (profile, messages, reactions, memberships, tokens, applications)
- **Data Retention**: Explains that data is retained for the lifetime of the account with no automatic expiration; server administrators may configure retention policies

## Implementation Status

- [x] Account deletion with password + "DELETE" confirmation
- [x] Server-side cascade deletion (messages, reactions, tokens, memberships, etc.)
- [x] Self-deletion endpoint (`DELETE /users/@me` with password verification)
- [x] Server-side data export (`GET /users/@me/data-export`)
- [x] Data export save-to-file UI in Privacy & Data page
- [x] Password change with validation
- [x] Opt-in error reporting consent dialog (first launch)
- [x] PII scrubbing in error reports (tokens, URLs)
- [x] `send_default_pii=false` in project settings
- [x] Error reporting toggle in App Settings → Notifications
- [x] Client config export (`.daccord-profile`)
- [x] Client config import with pre-import backup
- [x] Local profile deletion (config + emoji cache)
- [x] 2FA enable/disable/verify with backup codes
- [x] OAuth connections listing with disconnect button
- [x] Local data cleanup after account deletion
- [x] Privacy policy and terms links in About page
- [x] Data deletion disclosure in Privacy & Data page
- [x] Data retention disclosure in Privacy & Data page
- [ ] Per-server data deletion request (delete data from one server without deleting account)

## Tasks

### GDPR-1: No server-side data export
- **Status:** done
- **Impact:** 4
- **Effort:** 4
- **Tags:** ci, config, gdpr
- **Notes:** `GET /users/@me/data-export` endpoint added to accordserver (`users.rs:export_current_user_data()`). Exports user profile, all messages, spaces, and relationships as JSON. Client-side "Request Data Export" button in Server Settings → Privacy & Data page saves the export to a user-chosen file.

### GDPR-2: No local cleanup after account deletion
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** emoji, performance
- **Notes:** `_on_delete_account()` now calls `Config.wipe_active_profile()` before `tree.quit()`. This deletes the active profile's directory (config + emoji cache) and removes its registry entry.

### GDPR-3: No privacy policy display
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** gdpr
- **Notes:** "Privacy & Legal" section added to App Settings → About page with Privacy Policy and Terms of Service links. Data practices summary displayed inline.

### GDPR-4: Message cascade behavior unknown
- **Status:** done
- **Impact:** 3
- **Effort:** 4
- **Tags:** gdpr
- **Notes:** Confirmed: `db::admin::delete_user()` (`accordserver/src/db/admin.rs:266`) performs full cascade deletion including `DELETE FROM messages WHERE author_id = ?` (line 336). All user data is purged. Self-deletion endpoint `DELETE /users/@me` now calls this same cascade via password-verified `delete_current_user()`.

### GDPR-5: OAuth connections are read-only
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** config, security, ui
- **Notes:** Connection rows now include a red "Disconnect" button that sends `DELETE /users/@me/connections/{id}`. On success the row is removed from the UI.

### GDPR-6: No data retention policy
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** performance
- **Notes:** Data retention and deletion disclosures added to Server Settings → Privacy & Data page. Explains that data is retained for account lifetime with no automatic expiration, and that account deletion cascades all personal data.

### GDPR-7: Error breadcrumbs include IDs
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** security
- **Notes:** `error_reporting.gd` now truncates space/channel IDs to the last 4 characters in both breadcrumbs and Sentry tags via `_truncate_id()`. This preserves debugging correlation while preventing full identifier cross-referencing.

### GDPR-8: Exported profile includes credentials
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** ci, config, security
- **Notes:** `Config.export_config()` already strips `token` and `password` keys from server sections via a sanitized copy (skips keys in `_IMPORT_BLOCKED_KEYS`). The export file contains only preferences, not credentials.
