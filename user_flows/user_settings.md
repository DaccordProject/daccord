# User Settings Menu

Priority: 29
Depends on: User Configuration, Profiles

## Overview

The user settings system comprises two fullscreen modal panels: **App Settings** (global client preferences) and **Server Settings** (per-server account settings). Both extend `SettingsBase` → `ModalBase`, sharing a common layout of left nav sidebar + right scrollable content area. App Settings is opened from the user bar menu; Server Settings is opened from the same menu when a space is selected.

## User Steps

### Opening App Settings
1. User clicks the `...` menu button on the user bar (bottom of sidebar).
2. User selects "App Settings" from the popup menu (ID 6).
3. A fullscreen `AppSettings` modal is instantiated via `_APP_SETTINGS_SCENE` and added to the scene root.
4. The Profiles page is shown by default.

### Opening Server Settings
1. User clicks the `...` menu button on the user bar.
2. User selects "Server Settings" from the popup menu (ID 20). Disabled when in DM mode or no space is selected.
3. A fullscreen `ServerSettings` modal is instantiated, `setup(space_id)` is called, and added to the scene root.
4. The My Account page is shown by default.

### Navigating Pages
1. User clicks a nav button in the left panel.
2. `_show_page(index)` hides all pages and shows the selected one (line 141, `settings_base.gd`).
3. The active nav button gets white font color; others have the override removed (lines 145-151).

### Editing Profile (Server Settings, in-panel)
1. User navigates to "My Account" in Server Settings.
2. User modifies avatar (Upload/Remove), display name, bio, or accent color.
3. User clicks "Save Changes".
4. REST `PATCH /users/@me` is sent via the server-specific AccordClient; on success, `user_updated` fires.

### Changing Account Password (Server Settings)
1. User navigates to "Change Password".
2. User enters current password, new password (min 8 chars), and confirmation.
3. User clicks "Change Password".
4. On success, fields clear and a green success message appears. On failure, a red error appears.

### Deleting Account (Server Settings)
1. User navigates to "Delete Account".
2. User enters password and types "DELETE" in the confirmation field.
3. User clicks "Delete My Account" (danger button).
4. On success, `Config.wipe_active_profile()` is called and the application quits via `tree.quit()`.

### Managing 2FA (Server Settings)
1. User navigates to "Two-Factor Auth".
2. On page open, the page checks user's `mfa_enabled` flag, then fetches authoritative status via `GET /users/@me` (line 140, `user_settings_twofa.gd`).
3. To enable: enters password → clicks "Enable 2FA" → receives secret key + OTP URI (with copy buttons) → enters 6-digit code → clicks "Verify" → backup codes are displayed with copy button.
4. To disable: enters password → clicks "Disable 2FA".
5. To regenerate backup codes: enters password → clicks "Regenerate Backup Codes".

### Managing Profiles (App Settings)
1. User navigates to "Profiles".
2. Can create, switch, rename, set password, export, import, delete, or reorder profiles via the list UI and `...` context menus.
3. Switching profiles closes the settings panel and emits `profile_switched`.

### Checking for Updates (App Settings)
1. User navigates to "Updates".
2. Clicks "Check for Updates" → status shows "Checking..." → on success shows available version or "You're on the latest version."
3. If update available: can "Download & Install" (in-app download with progress bar and cancel), "View Changes" (opens release URL), or "Skip This Version".
4. After download completes, "Restart to Update" button appears.

### Closing Settings
1. User clicks the "X" button in the header, **or**
2. User clicks outside the modal (ModalBase handles background dismiss), **or**
3. User presses Escape.
4. The modal calls `_close()` which triggers `queue_free()`.

## Signal Flow

```
User bar "..." menu click
    │
    ├── ID 6: "App Settings"
    │     user_bar._show_app_settings()                    (line 176)
    │       │  _APP_SETTINGS_SCENE.instantiate()
    │       │  get_tree().root.add_child(settings)
    │       ▼
    │     AppSettings._ready() → SettingsBase._ready()     (settings_base.gd:16)
    │       │  _get_sections() returns 7-9 nav labels
    │       │  _build_pages() builds all page VBoxContainers
    │       │  _show_page(0) → Profiles visible
    │       │
    │       ├── Profile switch flow:
    │       │     user_settings_profiles_page._on_switch_profile()  (line 121)
    │       │       │  If password-protected → ProfilePasswordDialog
    │       │       ▼
    │       │     Config.profiles.switch(slug)
    │       │       ▼
    │       │     AppState.profile_switched.emit()          (app_state.gd:103)
    │       │       ▼
    │       │     AppSettings.queue_free()                  (profiles_page:48)
    │       │
    │       ├── Update check flow:
    │       │     app_settings_updates_page._on_check_updates_pressed()  (line 197)
    │       │       │  Updater.check_for_updates(true)
    │       │       ▼
    │       │     AppState.update_available.emit(info)      (app_state.gd:153)
    │       │       ▼
    │       │     Shows version + Download/Skip/View buttons (line 204)
    │       │
    │       └── Appearance flow:
    │             _on_theme_preset_changed(idx)              (line 617)
    │               │  ThemeManager.apply_preset(name) or show custom pickers
    │               ▼
    │             Config saves theme preset; live UI update
    │
    └── ID 20: "Server Settings"
          user_bar._show_server_settings()                  (line 181)
            │  ServerSettingsScene.instantiate()
            │  settings.setup(space_id)
            │  get_tree().root.add_child(settings)
            ▼
          ServerSettings._ready() → SettingsBase._ready()
            │  setup() resolves AccordClient, user dict, server name
            │  _get_sections() returns 6 nav labels
            │  _build_pages() builds account pages
            │
            ├── Profile save flow:
            │     UserSettingsProfile._on_save()             (line 135)
            │       │  await _accord_client.users.update_me(data)
            │       ▼
            │     AppState.user_updated.emit(user.id)
            │       ▼
            │     user_bar._on_user_updated() → refreshes bar (line 101)
            │
            ├── Password change flow:
            │     UserSettingsDanger._on_password_save()      (line 53)
            │       │  await client.auth.change_password(...)
            │       ▼
            │     Success: green message + fields cleared     (line 88)
            │     Failure: red error message                  (line 97)
            │
            ├── Delete account flow:
            │     UserSettingsDanger._on_delete_account()     (line 146)
            │       │  await client.users.delete_me(...)
            │       ▼
            │     Success: Config.wipe_active_profile() → tree.quit() (line 176-177)
            │
            ├── 2FA enable flow:
            │     UserSettingsTwofa._on_enable()              (line 183)
            │       │  await client.auth.enable_2fa({password})
            │       ▼
            │     Shows secret + OTP URI + code input         (line 201)
            │       │
            │     UserSettingsTwofa._on_verify()              (line 222)
            │       │  await client.auth.verify_2fa({code})
            │       ▼
            │     Shows backup codes, enables disable section (line 247)
            │
            ├── 2FA disable flow:
            │     UserSettingsTwofa._on_disable()             (line 262)
            │       │  await client.auth.disable_2fa({password})
            │       ▼
            │     Resets to "not enabled" state               (line 281)
            │
            └── Connections fetch flow:
                  _fetch_connections(vbox, loading)            (line 157)
                    │  await client.users.list_connections()
                    ▼
                  Populates connection rows or shows empty state (line 182)
```

## Key Files

| File | Role |
|------|------|
| `scenes/user/settings_base.gd` | Shared base class (extends ModalBase) — nav panel, page switching, helper builders |
| `scenes/user/app_settings.gd` | App Settings panel — Profiles, Voice & Video, Sound, Appearance, Notifications, Updates, About, Developer, Instance Admin |
| `scenes/user/app_settings.tscn` | Scene: ColorRect + AppSettings script |
| `scenes/user/server_settings.gd` | Server Settings panel — My Account, Notifications, Change Password, Delete Account, 2FA, Connections |
| `scenes/user/server_settings.tscn` | Scene: ColorRect + ServerSettings script |
| `scenes/user/user_settings_profiles_page.gd` | Delegate: Profiles page (list, CRUD, switch, import/export, reorder) |
| `scenes/user/user_settings_profile.gd` | Delegate: Profile edit (avatar, display name, bio, accent color, save) |
| `scenes/user/user_settings_danger.gd` | Delegate: Change Password + Delete Account pages |
| `scenes/user/user_settings_twofa.gd` | Delegate: 2FA enable/verify/disable page with server status check |
| `scenes/user/app_settings_updates_page.gd` | Delegate: Updates page (check, download, skip, restart) |
| `scenes/user/app_settings_about_page.gd` | Delegate: About page (version, license, open source credits, developer mode toggle) |
| `scenes/user/app_settings_developer_page.gd` | Delegate: Developer page (Test API + MCP server toggles, ports, tokens, tool groups) |
| `scenes/user/web_mic_audio.gd` | Web platform mic test via getUserMedia/AnalyserNode |
| `scenes/user/create_profile_dialog.gd` | Dialog: create new profile (name, optional password, scratch vs copy) |
| `scenes/user/create_profile_dialog.tscn` | Scene tree for create profile dialog |
| `scenes/user/profile_password_dialog.gd` | Dialog: unlock a password-protected profile |
| `scenes/user/profile_password_dialog.tscn` | Scene tree for profile unlock dialog |
| `scenes/user/profile_set_password_dialog.gd` | Dialog: set, change, or remove a profile password |
| `scenes/user/profile_set_password_dialog.tscn` | Scene tree for profile set-password dialog |
| `scenes/user/profile_card.gd` | Floating profile card popup shown on avatar/username click |
| `scenes/common/modal_base.gd` | Base modal: fullscreen overlay, background dismiss, Escape key, panel sizing |
| `scenes/common/modal_base.tscn` | Scene tree for modal base |
| `scenes/sidebar/user_bar.gd` | User bar — opens App Settings (line 176) and Server Settings (line 181) via menu |
| `scenes/admin/server_management_panel.gd` | Instance admin panel opened from App Settings admin page |
| `scripts/autoload/config.gd` | All settings persistence: voice, video, sound, notifications, profiles, theme, developer |
| `scripts/autoload/client_mutations.gd` | REST calls: `update_profile`, `change_password`, `delete_account` |
| `scripts/autoload/app_state.gd` | Signals: `user_updated` (line 24), `profile_switched` (line 103), `config_changed` (line 173), update signals (lines 153-165) |

## Implementation Details

### Panel Architecture (SettingsBase)

Both panels extend `SettingsBase` which extends `ModalBase` (line 1, `settings_base.gd`). `SettingsBase._ready()` (line 16) calls `_setup_modal()` on `ModalBase`, then builds:

1. **Header row** — "Settings" title (gray, 14pt) + "X" close button (lines 26-56)
2. **Body HBoxContainer** — left nav panel (180px min, `nav_bg` styled) + right scrollable content area (lines 58-134)

Subclasses override `_get_sections()` for nav labels, `_build_pages()` for content, `_get_modal_size()` for dimensions, and optionally `_get_subtitle()` (shown above nav buttons, used by ServerSettings to display server name).

**Page switching:** `_show_page(index)` (line 141) hides all pages and shows the selected one. Active nav button gets white font color; others have override removed.

**Shared builders:** `_page_vbox(title)` creates a titled VBoxContainer (line 169). `_section_label(text)` creates gray 11pt labels (line 181). `_error_label()` creates hidden red 13pt labels (line 199). Static methods `create_action_button()`, `create_secondary_button()`, `create_danger_button()` use `ThemeManager.style_button()` for consistent styling (lines 208-227).

### App Settings Pages

**Sections** (line 62, `app_settings.gd`): Profiles, Voice & Video, Sound, Appearance, Notifications, Updates, About. Conditionally adds Developer (if developer mode on) and Instance Admin (if user is admin).

### Profiles Page

Delegated to `UserSettingsProfilesPage` (line 90). Profile list is a VBoxContainer rebuilt by `_refresh_profiles_list()` (line 53).

Each profile row is an HBoxContainer containing:
- Profile name label (14pt, expanding)
- Optional `[locked]` badge (11pt, gray) if password-protected (line 75)
- `(Active)` badge (12pt, accent color) for the current profile, **or** a "Switch" button for inactive profiles (lines 84-98)
- A `MenuButton` labeled `...` with context actions (lines 101-115):
  - Rename (ID 0) — opens an `AcceptDialog` with a `LineEdit`, 32 char max (line 158)
  - Set Password (ID 1) — opens `ProfileSetPasswordDialog`
  - Export (ID 2) — opens `FileDialog` for `.daccord-profile` files
  - Delete (ID 3) — opens `ConfirmationDialog` (not available for "default" profile)
  - Move Up (ID 4) / Move Down (ID 5) — calls `Config.profiles.move_up/down()`

**Profile switching** closes the settings panel: `AppState.profile_switched.connect(_host.queue_free)` at line 48. Password-protected profiles open `ProfilePasswordDialog` first (line 124).

**Import flow** is two-step: FileDialog for file selection → AcceptDialog for naming (lines 220-259).

### My Account Page (Server Settings)

Built by `_build_account_page()` (line 48, `server_settings.gd`). Read-only display of username and account created date, then delegates to `UserSettingsProfile` for editable fields (avatar, display name, bio, accent color). Uses the per-server AccordClient and server-specific user data.

### Profile Edit (UserSettingsProfile)

`UserSettingsProfile` (extends RefCounted) builds:
- Avatar preview (80x80) with Upload/Remove buttons (lines 34-54)
- Display name `LineEdit` (line 58)
- Bio `TextEdit` (min height 80px, line 64)
- Accent color row: label + `ColorPickerButton` (40x30) + Reset button (lines 70-89)
- Error label + Save button (lines 91-97)

**Avatar upload:** Opens `FileDialog` for PNG/JPG/WebP. Reads file to base64 data URI, previews via `Image.load()` → `ImageTexture` → `_apply_texture()` (lines 99-125).

**Save logic** (`_on_save`, line 135): Builds a diff dictionary comparing current values to the user. Only changed fields are sent. Calls `await _accord_client.users.update_me(data)` for server-specific, or `await Client.update_profile(data)` as fallback. Disables button during request.

### Voice & Video Page (App Settings)

Built by `_build_voice_page()` (line 97). Platform-aware:
- **Web:** Shows browser-manages-devices note instead of dropdowns
- **Non-web:** Input/Output device dropdowns from `AudioServer.get_input/output_device_list()`

Controls:
- **Input Volume** — HSlider 0-200%, saved via `Config.voice.set_input_volume()` (lines 129-152)
- **Output Volume** — HSlider 0-200%, saved via `Config.voice.set_output_volume()` (lines 175-197)
- **Mic Test** — "Let's Check" button toggles mic testing with level meter ProgressBar (lines 199-227)
  - Native: creates AudioBus "MicTest" with `AudioEffectCapture`, plays `AudioStreamMicrophone`
  - Web: uses `getUserMedia` + `AnalyserNode` via `web_mic_audio.gd`
  - Monitor output checkbox for playback, threshold marker from input sensitivity
- **Input Sensitivity** — HSlider 0-100%, yellow threshold marker on the level bar (lines 229-249)
- **Camera** — placeholder dropdown "System Default Camera" (non-web only, lines 252-257)
- **Video Resolution** — 480p/720p/1080p dropdown (lines 260-269)
- **Video FPS** — 15/30/60 FPS dropdown (lines 272-286)

### Sound Page (App Settings)

Built by `_build_sound_page()` (line 417). Contains:
- **Volume slider** — HSlider 0.0 to 1.0, step 0.05, with percentage label (lines 420-438)
- **Sound event checkboxes** — 11 events: `message_received`, `mention_received`, `message_sent`, `voice_join`, `voice_leave`, `peer_join`, `peer_leave`, `mute`, `unmute`, `deafen`, `undeafen` (lines 441-463)

### Appearance Page (App Settings)

Built by `_build_appearance_page()` (line 469). Contains:
- **Theme preset dropdown** — 5 presets (Dark, Light, Nord, Monokai, Solarized) + Custom (lines 472-491)
- **Theme preview swatches** — 8 colored squares with labels (lines 493-497, helper at 645-675)
- **Custom color pickers** — visible only when "Custom" selected; 8 editable keys (accent, text, muted, error, success, panel bg, nav bg, input bg) in a 2-column grid (lines 499-534)
- **Theme sharing** — Copy Theme / Paste Theme buttons + Reset to Preset (lines 536-564)
- **Reduce motion** checkbox under Accessibility section (lines 569-577)
- **Emoji skin tone** dropdown — Default through Dark, 6 options (lines 579-592)
- **Language** dropdown — 11 locales (lines 594-612)

### Notifications Page (App Settings)

Built by `_build_notifications_page()` (line 678). Contains:
- **Suppress @everyone** checkbox (lines 681-687)
- **Idle Timeout** dropdown — Disabled, 1/5/10/30 minutes mapped to seconds `[0, 60, 300, 600, 1800]` (lines 689-706)
- **Error Reporting** checkbox — toggles Sentry; initializes when enabled (lines 708-720)

### Notifications Page (Server Settings)

Built by `_build_notifications_page()` (line 77, `server_settings.gd`). Contains:
- **Mute this server** checkbox (lines 81-87)
- **Suppress @everyone** dropdown — Use global default / Suppress / Don't suppress (lines 89-104)

### Change Password Page (Server Settings)

Delegated to `UserSettingsDanger.build_password_page()` (line 23). Three secret `LineEdit` fields (current, new, confirm) and a "Change Password" button.

**Validation** (`_on_password_save`, line 53): Current password required, new password min 8 chars, new/confirm must match. Uses per-server AccordClient or falls back to `Client.change_password()`.

**Success** (line 88): Clears fields, shows green "Password changed successfully" via `ThemeManager.get_color("success")`.
**Error** (line 97): Shows red error via `ThemeManager.get_color("error")`.

### Delete Account Page (Server Settings)

Delegated to `UserSettingsDanger.build_delete_page()` (line 107). Contains: red warning, password field, "TYPE 'DELETE' TO CONFIRM" field, danger "Delete My Account" button.

**Validation** (`_on_delete_account`, line 146): Password required, confirm text must equal "DELETE" exactly. On success, calls `Config.wipe_active_profile()` then `tree.quit()`.

### Two-Factor Auth Page (Server Settings)

Delegated to `UserSettingsTwofa.build()` (line 24). State-driven UI with server status check:

**Initial load** (line 134-138): Checks `user.mfa_enabled` for quick state, then calls `_refresh_mfa_status()` which does `GET /users/@me` for authoritative status.

**Enable flow** (line 183): Requires password. Returns secret key + OTP URI, both with copy buttons. Shows 6-digit code input + Verify button.

**After verification** (line 222): Hides setup UI, calls `_show_enabled_state()`, displays backup codes with copy button.

**Disable flow** (line 262): Requires password. Calls `disable_2fa()`, resets to disabled state.

**Regenerate backup codes** (line 290): Requires password. Calls `regenerate_backup_codes()`, displays new codes.

### Connections Page (Server Settings)

Built by `_build_connections_page()` (line 143, `server_settings.gd`). Shows "Loading connections..." while fetching. Calls `await _accord_client.users.list_connections()`. Displays each connection as a row with service type (14pt) and account name (gray). Shows "Not connected", "Failed to load", or "No connections linked" for edge cases.

### Updates Page (App Settings)

Delegated to `AppSettingsUpdatesPage` (line 725). Shows current version, check button with status label, update available row (version + Download & Install / View Changes / Skip This Version), download progress bar with cancel, restart button, error label, auto-check toggle, and master server URL input.

Connects to 7 AppState update signals (lines 164-180). Handles cached version info for download/skip flows.

### About Page (App Settings)

Delegated to `AppSettingsAboutPage` (line 732). Shows app version, MIT license, separator, then open-source credit cards for Twemoji, godot-livekit, LiveKit SDK, Sentry Godot, GUT, and Lua GDExtension. Each card is a styled PanelContainer with title, description, copyright, license, and clickable link. Includes Developer Mode toggle at bottom.

### Developer Page (App Settings, conditional)

Delegated to `AppSettingsDeveloperPage` (line 739). Visible only when `Config.developer.get_developer_mode()` is true. Contains:

**Test API section:** Enable toggle, status label (listening/enabled/stopped), port SpinBox (1024-65535), token display (masked `dk_xxxx...xxxx`), Copy Token / Rotate Token buttons, note about optional auth.

**MCP Server section:** Enable toggle, status label, port SpinBox, token display + copy/rotate, tool group checkboxes (read, navigate, screenshot, message, moderate, voice).

Auto-generates tokens on first enable. CLI override note at bottom.

### Instance Admin Page (App Settings, conditional)

Built inline (line 746). Visible only when `Client.current_user.is_admin`. Shows description label and "Open Server Management" button that instantiates `ServerManagementPanel` and closes settings.

### Profile Dialogs

**CreateProfileDialog** (`create_profile_dialog.gd`): Fullscreen overlay with centered panel. Fields: name (max 32), optional password with dynamic confirm field, scratch vs copy radio buttons. Emits `profile_created(slug)`.

**ProfilePasswordDialog** (`profile_password_dialog.gd`): Fullscreen overlay for unlocking password-protected profiles. `setup(slug, name)` sets the title. Password input with Enter-to-submit. Emits `password_verified(slug)` on success.

**ProfileSetPasswordDialog** (`profile_set_password_dialog.gd`): Fullscreen overlay. Conditionally shows current password field and "Remove Password" button based on `has_password`. Validates current password via `Config.verify_profile_password()`, then calls `Config.set_profile_password()`.

### Profile Card (Popup)

`profile_card.gd` is a floating popup shown when clicking a user's avatar. Displays avatar, status dot, display name, username, custom status, activities, device status, bio, roles (space context), badges, member-since date, and a "Message" button for non-self users. Not part of the settings panel but shares the profile data model.

## Implementation Status

- [x] Two-panel architecture (App Settings + Server Settings) with shared SettingsBase
- [x] Profiles page with full CRUD (create, rename, delete, switch, reorder)
- [x] Profile password protection (set, change, remove, verify)
- [x] Profile export/import (`.daccord-profile` files)
- [x] My Account page (read-only user info + inline profile editing)
- [x] Profile editing (avatar upload/remove, display name, bio, accent color)
- [x] Voice & Video settings (input/output device, volume, mic test with level meter, sensitivity, resolution, FPS)
- [x] Web platform mic test via getUserMedia/AnalyserNode
- [x] Sound settings (volume slider with percentage, 11 per-event toggles)
- [x] Appearance page (theme presets, custom color pickers, theme sharing, reduce motion, emoji skin tone, language)
- [x] Notifications — global (suppress @everyone, idle timeout, error reporting)
- [x] Notifications — per-server (mute, suppress @everyone override)
- [x] Change account password with validation
- [x] Delete account with double confirmation (password + type DELETE) and profile wipe
- [x] 2FA enable/verify/disable with backup codes and copy buttons
- [x] 2FA status loaded from server on page open (checks `mfa_enabled` + `GET /users/@me`)
- [x] 2FA backup code regeneration with password
- [x] Secret key and OTP URI copy buttons
- [x] Connections page (async-loaded from server)
- [x] Updates page (check, download with progress, skip version, restart, auto-check toggle, master server URL)
- [x] About page (version, license, open-source credits, developer mode toggle)
- [x] Developer page (Test API + MCP server toggles, ports, tokens, tool groups)
- [x] Instance Admin page (opens Server Management panel)
- [x] Escape key / background click dismissal (via ModalBase)
- [x] Camera dropdown placeholder in Voice & Video
- [ ] No password visibility toggle on any password fields
- [ ] No password strength indicator
- [ ] Settings panel closes on profile switch (no way to stay open)
- [ ] Connections page is read-only (no disconnect/manage)
- [ ] Camera dropdown is a non-functional placeholder

## Tasks

### SETTINGS-1: Settings close after profile switch
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** `AppState.profile_switched.connect(_host.queue_free)` (`user_settings_profiles_page.gd`, line 48) closes the entire panel. Users must reopen settings to continue configuring.

### SETTINGS-2: No password visibility toggle
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** a11y, config, security, ui
- **Notes:** All password fields in `user_settings_danger.gd` (lines 32, 37, 42, 130), `user_settings_twofa.gd` (lines 38, 107, 121), `profile_password_dialog.gd`, and `profile_set_password_dialog.gd` use `secret = true` with no eye icon to reveal text. Standard accessibility expectation.

### SETTINGS-3: No password strength indicator
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config, security, ui
- **Notes:** Account password requires 8 chars minimum (`user_settings_danger.gd`, line 62) but shows no real-time strength feedback. Profile passwords have no minimum at all (`create_profile_dialog.gd`).

### SETTINGS-4: Profile context menu not discoverable
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** The `...` MenuButton (`user_settings_profiles_page.gd`, line 101) has no tooltip. Contains 6 actions (Rename, Set Password, Export, Delete, Move Up, Move Down) that users may not find.

### SETTINGS-5: No tooltips or help text on settings
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** config, ui
- **Notes:** Idle timeout, reduce motion, error reporting, suppress @everyone, video resolution/FPS, input sensitivity — none have descriptions explaining their effect.

### SETTINGS-6: No sound test/preview button
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** audio, config, ui
- **Notes:** Sound event checkboxes toggle events but there's no way to hear what each sound is (`app_settings.gd`, lines 454-463).

### SETTINGS-7: Profile reorder has no visual feedback
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** "Move Up" / "Move Down" silently call `Config.profiles.move_up/down()` and refresh the list (`user_settings_profiles_page.gd`, lines 151-155). No animation or confirmation.

### SETTINGS-8: No character counters on inputs
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** Profile name has 32 char `max_length` (`user_settings_profiles_page.gd`, line 164; `create_profile_dialog.tscn`) but no visible counter. Bio has no limit shown.

### SETTINGS-9: Camera dropdown is non-functional
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** config, ui, video
- **Notes:** Camera dropdown shows only "System Default Camera" (`app_settings.gd`, lines 252-257). Not connected to any device enumeration or Config persistence.

### SETTINGS-10: Import/export has no description
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** Users don't know what data is included in a `.daccord-profile` export. No help text on the Import or Export buttons.

### SETTINGS-11: Connections page is read-only
- **Status:** open
- **Impact:** 2
- **Effort:** 4
- **Tags:** config, ui
- **Notes:** `_fetch_connections()` (`server_settings.gd`, line 157) displays connections but provides no disconnect or manage buttons. Requires server-side support.

### SETTINGS-12: Inconsistent label casing
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** Section labels use ALL CAPS via `_section_label()` but some inline labels use sentence case ("Accent Color" at `user_settings_profile.gd`, line 75; "Reduce motion" at `app_settings.gd`, line 572; "Monitor output" at `app_settings.gd`, line 205).
