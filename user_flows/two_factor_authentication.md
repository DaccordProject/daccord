# Two-Factor Authentication

## Overview
Two-factor authentication (2FA) is managed from the User Settings panel under the "Two-Factor Auth" page. The flow lets a user enable 2FA by requesting a secret, verifying a 6-digit code, and receiving backup codes, then disable 2FA later with a password.

## User Steps
1. User opens User Settings and selects "Two-Factor Auth" from the left nav.
2. To enable 2FA: clicks "Enable 2FA" to request a secret, enters a 6-digit code from their authenticator, and clicks "Verify".
3. To disable 2FA: enters their password and clicks "Disable 2FA".

## Signal Flow
User click "Two-Factor Auth"
  -> `UserSettings._on_nav_pressed()` (line 138)
  -> `UserSettings._show_page()` toggles `_twofa_page` visible (lines 141-143)

Enable 2FA
  -> `UserSettingsTwofa._on_enable()` (line 73)
  -> `Client._first_connected_client()` (line 371)
  -> `AuthApi.enable_2fa()` (line 42)
  -> UI shows secret + code input (lines 85-90)

Verify 2FA
  -> `UserSettingsTwofa._on_verify()` (line 98)
  -> `Client._first_connected_client()` (line 371)
  -> `AuthApi.verify_2fa()` (line 47)
  -> UI shows enabled state + backup codes (lines 117-134)

Disable 2FA
  -> `UserSettingsTwofa._on_disable()` (line 143)
  -> `Client._first_connected_client()` (line 371)
  -> `AuthApi.disable_2fa()` (line 53)
  -> UI resets to "not enabled" state (lines 161-169)

## Key Files
| File | Role |
|------|------|
| `scenes/user/user_settings.gd:74` | Builds the settings nav and routes page selection to the 2FA page. |
| `scenes/user/user_settings.gd:512` | Creates the "Two-Factor Authentication" page and delegates to `UserSettingsTwofa`. |
| `scenes/user/user_settings_twofa.gd:16` | Builds the 2FA UI and handles enable/verify/disable actions. |
| `addons/accordkit/rest/endpoints/auth_api.gd:42` | REST endpoints for 2FA enable/verify/disable/backup codes. |
| `scripts/autoload/client.gd:371` | Chooses the first connected `AccordClient` for REST calls. |

## Implementation Details
### UserSettings panel
- Left nav builds the "Two-Factor Auth" button and wires it to `_on_nav_pressed()` (lines 74-85).
- `_build_twofa_page()` instantiates `UserSettingsTwofa` and builds the page content (lines 512-516).

### UserSettingsTwofa page
- `build()` assembles the status label, enable button, secret label, code input, verify button, backup codes label, and disable section (lines 16-71).
- Enable flow calls `AuthApi.enable_2fa()` and expects `result.data["secret"]` to display (lines 82-90).
- Verify flow validates a 6-digit code, calls `AuthApi.verify_2fa()`, then expects `result.data["backup_codes"]` (Array) to display (lines 100-134).
- Disable flow requires a non-empty password and calls `AuthApi.disable_2fa()` before resetting the UI (lines 143-169).
- Uses a hardcoded 6-digit length (`_code_input.max_length = 6`) and basic length validation (lines 40-42, 100-103).

### AuthApi (AccordKit)
- 2FA endpoints are thin wrappers over REST routes: enable, verify, disable, and backup codes (lines 42-61).

### Client connection selection
- `Client._first_connected_client()` returns the first connected client, so 2FA calls target the first active server connection (lines 371-377).

## Implementation Status
- [x] Enable 2FA via REST and reveal secret + code input
- [x] Verify 2FA code and display backup codes
- [x] Disable 2FA with password
- [ ] Load actual 2FA status on page open
- [ ] Retrieve backup codes after initial setup (using `get_backup_codes()`)
- [ ] Copy affordance for secret and backup codes

## Tasks

### 2FA-1: 2FA status not fetched on page open
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** api, config, security
- **Notes:** `_status_label` defaults to "not enabled" and never queries server state (`user_settings_twofa.gd`, line 22).

### 2FA-2: Backup codes only shown once
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** api, security
- **Notes:** `AuthApi.get_backup_codes()` exists but is unused; there is no way to re-fetch codes after setup (`auth_api.gd`, line 59).

### 2FA-3: No copy UI for secret or backup codes
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** config, ui
- **Notes:** Both are plain `Label` values with no clipboard action (`user_settings_twofa.gd`, lines 30-55, 130-133).
