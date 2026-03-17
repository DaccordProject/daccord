# Two-Factor Authentication

Priority: 66
Depends on: User Management
Status: Complete

Enable/verify/disable 2FA from User Settings, MFA challenge during login with TOTP and backup codes, regenerate backup codes, and revoke sessions endpoint.

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
