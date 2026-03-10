# Two-Factor Authentication

Priority: 66
Depends on: User Management

## Overview
Two-factor authentication (2FA) is managed from two places: the login dialog (MFA challenge during sign-in) and the User Settings panel under "Two-Factor Auth" (enable/disable/backup codes). The login flow detects `mfa_required` responses and presents a TOTP/backup code input before issuing a token. The settings flow lets a user enable 2FA by providing their password, verifying a TOTP code, and receiving backup codes.

## User Steps
1. **Login with 2FA enabled:** User enters username/password → server returns `mfa_required` + ticket → dialog shows "TWO-FACTOR CODE" input → user enters 6-digit TOTP code or 8-char backup code → server issues token.
2. **Enable 2FA:** User opens User Settings → "Two-Factor Auth" → enters password → clicks "Enable 2FA" → receives secret + otpauth URI → enters 6-digit code from authenticator → clicks "Verify" → receives backup codes.
3. **Regenerate backup codes:** User clicks "Regenerate Backup Codes" → enters password → receives new set of 10 codes (old codes invalidated).
4. **Disable 2FA:** User enters password → clicks "Disable 2FA".
5. **Revoke all sessions:** `AuthApi.revoke_all_sessions()` endpoint is available but not yet wired to UI.

## Signal Flow
Login (no 2FA)
  -> `AuthDialog._on_submit()` (line 104)
  -> `AuthDialog._try_auth()` (line 238)
  -> `AuthApi.login()` (line 30)
  -> Returns `{ "user": AccordUser, "token": String }`
  -> `auth_completed` signal emitted (line 158)

Login (2FA enabled)
  -> `AuthDialog._on_submit()` (line 104)
  -> `AuthApi.login()` returns `{ "mfa_required": true, "ticket": String }` (line 142)
  -> `_enter_mfa_mode()` shows MFA input (line 90)
  -> `AuthDialog._on_submit_mfa()` (line 165)
  -> `AuthApi.login_mfa()` (line 42)
  -> Returns `{ "user": AccordUser, "token": String }`
  -> `auth_completed` signal emitted (line 207)

Enable 2FA (settings)
  -> `UserSettingsTwofa._on_enable()` (line 166)
  -> `AuthApi.enable_2fa({"password": pw})` (line 59)
  -> Returns `{ "secret": String, "otpauth_uri": String }`
  -> UI shows secret, otpauth URI, copy buttons, code input (lines 184-197)

Verify 2FA (settings)
  -> `UserSettingsTwofa._on_verify()` (line 205)
  -> `AuthApi.verify_2fa({"code": code})` (line 65)
  -> Returns `{ "backup_codes": Array }`
  -> `_show_enabled_state()` + `_display_backup_codes()` (lines 230-236)

Regenerate Backup Codes
  -> `UserSettingsTwofa._on_show_backup()` (line 273)
  -> `AuthApi.regenerate_backup_codes({"password": pw})` (line 77)
  -> `_display_backup_codes()` shows new codes (line 294)

Disable 2FA
  -> `UserSettingsTwofa._on_disable()` (line 245)
  -> `AuthApi.disable_2fa({"password": pw})` (line 71)
  -> `_show_disabled_state()` resets UI (line 147)

## Key Files
| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/auth_dialog.gd:104` | Login dialog with MFA challenge step (`_on_submit`, `_on_submit_mfa`). |
| `scenes/sidebar/guild_bar/auth_dialog.tscn` | Scene with MfaLabel + MfaInput nodes for 2FA code entry during login. |
| `scenes/user/server_settings.gd:132` | Creates the "Two-Factor Authentication" page and delegates to `UserSettingsTwofa`. |
| `scenes/user/user_settings_twofa.gd:24` | Builds the 2FA settings UI and handles enable/verify/disable/regenerate actions. |
| `addons/accordkit/rest/endpoints/auth_api.gd:30` | REST endpoints: `login`, `login_mfa`, `enable_2fa`, `verify_2fa`, `disable_2fa`, `regenerate_backup_codes`, `revoke_all_sessions`. |
| `addons/accordkit/models/user.gd:18` | `AccordUser.mfa_enabled` field for 2FA status. |
| `scripts/autoload/client.gd:355` | `_first_connected_client()` — chooses the first connected `AccordClient` for REST calls. |

## Implementation Details

### AuthDialog — MFA login flow
- `_on_submit()` calls `_try_auth()` which calls `AuthApi.login()` (line 127).
- `AuthApi.login()` now detects `mfa_required` in the response and skips auth response parsing when present (line 34 in auth_api.gd).
- If `result.data.mfa_required` is true, stores the ticket in `_mfa_ticket` and calls `_enter_mfa_mode()` (lines 142-148).
- `_enter_mfa_mode()` shows the MfaLabel and MfaInput nodes, changes submit text to "Verify", and focuses the input (lines 90-95).
- `_on_submit_mfa()` creates a temporary `AccordRest` + `AuthApi`, calls `login_mfa({"ticket": ticket, "code": code})`, and emits `auth_completed` on success (lines 165-211).
- Accepts both 6-digit TOTP codes and 8-character alphanumeric backup codes — the server determines which type based on format.
- The MFA ticket expires after 5 minutes server-side; if expired, the user sees "MFA ticket has expired" and must re-enter credentials.
- Switching between Sign In / Register modes clears the MFA ticket and hides MFA inputs (line 65-66).

### ServerSettings panel
- `_build_twofa_page()` instantiates `UserSettingsTwofa` and passes the `_accord_client` and `_server_user` dict (lines 132-139).

### UserSettingsTwofa page
- `build()` assembles: status label, enable password input, enable button, secret row (label + copy), URI row (label + copy), code input + verify button, backup codes row, regenerate password input + button, disable section (password + button), error label (lines 24-136).
- On page open, checks `user.get("mfa_enabled", false)` and calls `_show_enabled_state()` if true (lines 134-136).
- Enable flow requires password, calls `AuthApi.enable_2fa({"password": pw})`, shows secret + otpauth URI with copy buttons + code input (lines 166-203).
- The `otpauth_uri` is displayed alongside the base32 secret so users can either scan a QR code (rendered from the URI) or manually enter the secret (lines 189-193).
- Verify flow validates 6-digit code, calls `AuthApi.verify_2fa()`, shows enabled state and backup codes with copy button (lines 205-243).
- Regenerate backup codes requires password, calls `AuthApi.regenerate_backup_codes({"password": pw})` via POST (lines 273-305). This replaces the old `get_backup_codes()` GET endpoint.
- Disable flow requires password and calls `AuthApi.disable_2fa()` (lines 245-271).
- Copy buttons use `DisplayServer.clipboard_set()` to copy secret, otpauth URI, and backup codes (lines 315-331).

### AuthApi (AccordKit)
- `login()` detects `mfa_required` in response and skips `_parse_auth_response()` when present (lines 30-36).
- `login_mfa()` sends `POST /auth/login/mfa` with `{ "ticket": String, "code": String }` (lines 42-48).
- `enable_2fa()` sends `POST /auth/2fa/enable` with `{ "password": String }` (line 59).
- `verify_2fa()` sends `POST /auth/2fa/verify` with `{ "code": String }` (line 65).
- `disable_2fa()` sends `POST /auth/2fa/disable` with `{ "password": String }` (line 71).
- `regenerate_backup_codes()` sends `POST /auth/2fa/backup-codes` with `{ "password": String }` (lines 77-80).
- `revoke_all_sessions()` sends `POST /auth/sessions/revoke-all` (lines 84-87).

### Client connection selection
- `Client._first_connected_client()` returns the first connected client, so 2FA settings calls target the first active server connection (line 355 in client.gd).
- `UserSettingsTwofa._get_client()` prefers the explicitly-passed `_accord_client` over the fallback (lines 161-164).

## Implementation Status
- [x] Enable 2FA with password confirmation
- [x] Display TOTP secret and otpauth URI with copy buttons
- [x] Verify 2FA code and display backup codes
- [x] Disable 2FA with password
- [x] Load actual 2FA status on page open
- [x] Regenerate backup codes with password (POST endpoint)
- [x] Copy affordance for secret, otpauth URI, and backup codes
- [x] MFA challenge during login (detect `mfa_required`, show code input, call `login_mfa`)
- [x] Backup code support during MFA login (server accepts 8-char alphanumeric codes)
- [x] Revoke all sessions REST endpoint (`AuthApi.revoke_all_sessions()`)

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No QR code rendering for otpauth URI | Medium | The `otpauth_uri` is displayed as text with a copy button but not rendered as a scannable QR code. Users must copy the URI or manually enter the secret. |
| Revoke all sessions has no UI | Low | `AuthApi.revoke_all_sessions()` (line 84) is implemented but not wired to any settings button. Could be added to server_settings.gd. |
| No rate-limit feedback in MFA login UI | Low | Server returns `RateLimited` with `retry_after` (15-min window, 5 attempts). The client shows the error message but doesn't display a countdown or disable the input for the retry period. |
| MFA ticket expiry not communicated proactively | Low | The 5-minute ticket TTL is enforced server-side. If the user waits too long, they get an error and must re-enter credentials. No client-side timer warns them. |

## Tasks

### 2FA-1: 2FA status not fetched on page open
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** api, config, security
- **Notes:** `build()` accepts a `user` dict and checks `mfa_enabled` to set the initial UI state. `AccordUser` model includes `mfa_enabled` field; `ClientModels.user_to_dict()` propagates it.

### 2FA-2: Backup codes only shown once
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** api, security
- **Notes:** "Regenerate Backup Codes" button visible when 2FA is enabled. Calls `AuthApi.regenerate_backup_codes()` (POST with password) to generate new codes on demand.

### 2FA-3: No copy UI for secret or backup codes
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** config, ui
- **Notes:** Copy buttons next to secret, otpauth URI, and backup codes using `DisplayServer.clipboard_set()`.

### 2FA-4: MFA challenge during login
- **Status:** done
- **Impact:** 5
- **Effort:** 3
- **Tags:** api, security, auth
- **Notes:** `AuthDialog` detects `mfa_required` response, shows MFA code input, calls `AuthApi.login_mfa()` with ticket + code. Supports both TOTP codes and backup codes.

### 2FA-5: Password required for enable/regenerate
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** api, security
- **Notes:** `enable_2fa()` and `regenerate_backup_codes()` now require password in request body. UI includes password input fields for both actions.

### 2FA-6: Revoke all sessions endpoint
- **Status:** done (endpoint only)
- **Impact:** 3
- **Effort:** 1
- **Tags:** api, security
- **Notes:** `AuthApi.revoke_all_sessions()` sends `POST /auth/sessions/revoke-all`. No UI button yet.
