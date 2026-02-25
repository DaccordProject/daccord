# User Settings Menu

## Overview

The user settings menu is a fullscreen panel with a left navigation sidebar and right content area, hosting 10 pages: Profiles, My Account, Profile (edit), Voice & Video, Sound, Notifications, Change Password, Delete Account, Two-Factor Auth, and Connections. It is opened from the user bar context menu and dismissed via the Close button or Escape key.

## User Steps

### Opening Settings
1. User clicks the `...` menu button on the user bar (bottom of sidebar).
2. User selects "Settings" from the popup menu.
3. A fullscreen `UserSettings` ColorRect is instantiated and added to the scene root.
4. The Profiles page is shown by default.

### Navigating Pages
1. User clicks a nav button in the left panel (Profiles, My Account, Profile, Voice & Video, Sound, Notifications, Change Password, Delete Account, Two-Factor Auth, Connections).
2. The corresponding content page becomes visible; all others are hidden.
3. The active nav button is highlighted white; others use default color.

### Editing Profile (in-panel)
1. User navigates to the "Profile" page.
2. User modifies avatar (Upload/Remove), display name, bio, or accent color.
3. User clicks "Save Changes".
4. REST `PATCH /users/@me` is sent; on success, `user_updated` fires.

### Changing Account Password
1. User navigates to "Change Password".
2. User enters current password, new password (min 8 chars), and confirmation.
3. User clicks "Change Password".
4. On success, fields clear and a green success message appears. On failure, a red error appears.

### Deleting Account
1. User navigates to "Delete Account".
2. User enters password and types "DELETE" in the confirmation field.
3. User clicks "Delete My Account" (red button).
4. On success, the application quits via `tree.quit()`.

### Managing 2FA
1. User navigates to "Two-Factor Auth".
2. To enable: clicks "Enable 2FA" → receives secret key → enters 6-digit code → clicks "Verify" → backup codes are displayed.
3. To disable: enters password → clicks "Disable 2FA".

### Managing Profiles
1. User navigates to "Profiles".
2. Can create, switch, rename, set password, export, import, delete, or reorder profiles via the list UI and `...` context menus.
3. Switching profiles closes the settings panel and emits `profile_switched`.

### Closing Settings
1. User clicks the "Close" button at the bottom of the nav panel, **or**
2. User presses Escape.
3. The settings panel calls `queue_free()`.

## Signal Flow

```
User bar "Settings" menu click
    │
    ▼
user_bar._show_user_settings()                        (line 160)
    │  load("res://scenes/user/user_settings.tscn")
    │  get_tree().root.add_child(settings)
    ▼
UserSettings._ready()                                  (line 45)
    │  Builds nav panel (10 buttons) + content area (10 pages)
    │  _show_page(0) → Profiles page visible
    │
    ├── Profile save flow:
    │     UserSettingsProfile._on_save()                (line 138)
    │       │  await Client.update_profile(data)
    │       ▼
    │     client_mutations.update_profile()             (line 327)
    │       │  await client.users.update_me(data)
    │       │  Updates _user_cache + current_user
    │       ▼
    │     AppState.user_updated.emit(user.id)           (line 354)
    │       │
    │       ▼
    │     user_bar._on_user_updated() → refreshes bar   (line 95)
    │
    ├── Password change flow:
    │     UserSettingsDanger._on_password_save()         (line 50)
    │       │  await Client.change_password(current, new_pw)
    │       ▼
    │     client_mutations.change_password()             (line 359)
    │       │  await client.auth.change_password(...)
    │       ▼
    │     Success: green message + fields cleared        (line 76)
    │     Failure: red error message                     (line 85)
    │
    ├── Delete account flow:
    │     UserSettingsDanger._on_delete_account()        (line 140)
    │       │  await Client.delete_account(pw)
    │       ▼
    │     client_mutations.delete_account()              (line 377)
    │       │  await client.users.delete_me(...)
    │       ▼
    │     Success: tree.quit()                           (line 156)
    │
    ├── 2FA enable flow:
    │     UserSettingsTwofa._on_enable()                 (line 73)
    │       │  await client.auth.enable_2fa({})
    │       ▼
    │     Shows secret key + code input                  (line 86)
    │       │
    │     UserSettingsTwofa._on_verify()                 (line 98)
    │       │  await client.auth.verify_2fa({code})
    │       ▼
    │     Shows backup codes, enables disable section    (line 123)
    │
    ├── 2FA disable flow:
    │     UserSettingsTwofa._on_disable()                (line 143)
    │       │  await client.auth.disable_2fa({password})
    │       ▼
    │     Resets to "not enabled" state                  (line 161)
    │
    ├── Profile switch flow:
    │     _on_switch_profile(slug, pname, has_pw)        (line 255)
    │       │  If password-protected → ProfilePasswordDialog
    │       ▼
    │     Config.switch_profile(slug)                    (line 601)
    │       ▼
    │     AppState.profile_switched.emit()               (line 84)
    │       ▼
    │     UserSettings.queue_free()                      (line 184)
    │
    └── Connections fetch flow:
          _fetch_connections(vbox, loading)               (line 657)
            │  await client.users.list_connections()
            ▼
          Populates connection rows or shows empty state  (line 683)
```

## Key Files

| File | Role |
|------|------|
| `scenes/user/user_settings.gd` | Main settings panel — builds all 10 pages, nav logic, profile list management |
| `scenes/user/user_settings.tscn` | Minimal scene: ColorRect + script attachment |
| `scenes/user/user_settings_profile.gd` | Delegate: Profile page (avatar, display name, bio, accent color, save) |
| `scenes/user/user_settings_danger.gd` | Delegate: Change Password + Delete Account pages |
| `scenes/user/user_settings_twofa.gd` | Delegate: 2FA enable/verify/disable page |
| `scenes/user/create_profile_dialog.gd` | Dialog: create new profile (name, optional password, scratch vs copy) |
| `scenes/user/create_profile_dialog.tscn` | Scene tree for create profile dialog |
| `scenes/user/profile_password_dialog.gd` | Dialog: unlock a password-protected profile |
| `scenes/user/profile_password_dialog.tscn` | Scene tree for profile unlock dialog |
| `scenes/user/profile_set_password_dialog.gd` | Dialog: set, change, or remove a profile password |
| `scenes/user/profile_set_password_dialog.tscn` | Scene tree for profile set-password dialog |
| `scenes/user/profile_card.gd` | Floating profile card popup shown on avatar/username click |
| `scenes/sidebar/user_bar.gd` | User bar at bottom of sidebar — opens settings via menu (line 160) |
| `scripts/autoload/config.gd` | All settings persistence: voice, video, sound, notifications, profiles, passwords |
| `scripts/autoload/client_mutations.gd` | REST calls: `update_profile`, `change_password`, `delete_account` |
| `scripts/autoload/app_state.gd` | Signals: `user_updated` (line 24), `profile_switched` (line 84) |

## Implementation Details

### Panel Architecture

The entire UI is built programmatically in `_ready()` (line 45). No scene tree nodes beyond the root ColorRect — all children are created in code.

**Layout:** HBoxContainer with a fixed-width (200px) left nav panel and an expanding right content ScrollContainer. The nav panel has a dark background (`Color(0.153, 0.161, 0.176)`) with 8px horizontal margins and 12px vertical margins (lines 57-76).

**Page switching:** `_show_page(index)` (line 146) hides all pages and shows the selected one. The active nav button gets a white font color override; others have the override removed (lines 151-157).

**Dismissal:** Close button calls `queue_free()` (line 98). Escape key handler in `_unhandled_input()` also calls `queue_free()` (line 740-743).

### Profiles Page

Built by `_build_profiles_page()` (line 161). The profile list is a VBoxContainer that gets rebuilt by `_refresh_profiles_list()` (line 188) any time profiles change.

Each profile row is an HBoxContainer containing:
- Profile name label (14pt font, expanding)
- Optional `[locked]` badge (11pt, gray) if password-protected (line 210)
- `(Active)` badge (12pt, blue `Color(0.345, 0.396, 0.949)`) for the current profile, **or** a "Switch" button for inactive profiles (lines 219-233)
- A `MenuButton` labeled `...` with context actions (lines 236-251):
  - Rename (ID 0) — opens an `AcceptDialog` with a `LineEdit`, 32 char max (line 290)
  - Set Password (ID 1) — opens `ProfileSetPasswordDialog`
  - Export (ID 2) — opens `FileDialog` for `.daccord-profile` files
  - Delete (ID 3) — opens `ConfirmationDialog` (not available for "default" profile)
  - Move Up (ID 4) / Move Down (ID 5) — calls `Config.move_profile_up/down()`

Action buttons: "New Profile" and "Import Profile" (lines 173-181).

**Profile switching** closes the settings panel: `AppState.profile_switched.connect(queue_free)` at line 184. Password-protected profiles open `ProfilePasswordDialog` first (line 259).

**Import flow** is two-step: FileDialog for file selection → AcceptDialog for naming (lines 348-386).

### My Account Page

Built by `_build_account_page()` (line 390). Read-only display of:
- Username (via `_labeled_value()` helper)
- Avatar (80x80 with letter fallback)
- Account created date (ISO date portion extracted at line 417)
- "Edit Profile" button that navigates to page index 2 (line 423)

### Profile Edit Page (In-Panel)

Delegated to `UserSettingsProfile` (line 434). Builds:
- Avatar preview (80x80) with Upload/Remove buttons (lines 44-56)
- Display name `LineEdit` (line 60)
- Bio `TextEdit` (min height 80px, line 67)
- Accent color row: label + `ColorPickerButton` (40x30) + Reset button (lines 72-92)
- Error label + Save button (lines 95-101)

**Avatar upload:** Opens `FileDialog` for PNG/JPG/WebP. Reads file to base64, previews via `Image.load()` → `ImageTexture` → `_apply_texture()` (lines 103-128).

**Save logic** (`_on_save`, line 138): Builds a diff dictionary comparing current values to `Client.current_user`. Only changed fields are sent. Calls `await Client.update_profile(data)`. Disables button during request.

### Voice & Video Page

Built by `_build_voice_page()` (line 440). Four dropdowns:
- **Input Device** — populated from `AudioServer.get_input_device_list()`, saved via `Config.set_voice_input_device()` (lines 445-459)
- **Output Device** — populated from `AudioServer.get_output_device_list()`, saved via `Config.set_voice_output_device()` (lines 462-477)
- **Video Resolution** — hardcoded options: 480p, 720p, 1080p (lines 481-489)
- **Video FPS** — hardcoded options: 15, 30, 60 FPS with index-to-value mapping (lines 493-506)

All settings save immediately on selection (auto-save pattern).

### Sound Page

Built by `_build_sound_page()` (line 512). Contains:
- **Volume slider** — `HSlider` from 0.0 to 1.0, step 0.05, auto-saves via `Config.set_sfx_volume()` (lines 516-524)
- **Sound event checkboxes** — five events: `message_received`, `message_sent`, `voice_join`, `voice_leave`, `notification`. Label text is generated by replacing underscores and capitalizing. Auto-saves via `Config.set_sound_enabled()` (lines 527-538)

### Notifications Page

Built by `_build_notifications_page()` (line 544). Contains:
- **Suppress @everyone** checkbox — auto-saves via `Config.set_suppress_everyone()` (lines 547-553)
- **Idle Timeout** dropdown — options: Disabled, 1/5/10/30 minutes, mapped to seconds `[0, 60, 300, 600, 1800]` (lines 556-572)
- **Error Reporting** checkbox — toggles Sentry reporting; also initializes Sentry when enabled (lines 575-586)
- **Accessibility** section with "Reduce motion" checkbox — auto-saves via `Config.set_reduced_motion()` (lines 589-596)
- **Server Mute** — dynamically generates one checkbox per space from `Client.spaces`, labeled "Mute [name]" (lines 599-609)

### Change Password Page

Delegated to `UserSettingsDanger.build_password_page()` (line 21). Three secret `LineEdit` fields (current, new, confirm) and a "Change Password" button.

**Validation** (`_on_password_save`, line 50):
1. Current password required (line 55)
2. New password minimum 8 characters (line 59)
3. New and confirm must match (line 63)
4. Calls `await Client.change_password(current, new_pw)` (line 68)

**Success handling** (line 72): Clears fields, shows green success message by overriding `font_color` to `Color(0.231, 0.647, 0.365)`.

**Error handling** (line 82): Resets to red `Color(0.929, 0.259, 0.271)` and shows server error.

### Delete Account Page

Delegated to `UserSettingsDanger.build_delete_page()` (line 91). Contains:
- Red warning label with `autowrap_mode` (lines 99-108)
- Password field (secret `LineEdit`)
- "TYPE 'DELETE' TO CONFIRM" field with placeholder "DELETE" (lines 115-118)
- Red "Delete My Account" button with custom `StyleBoxFlat` (lines 123-137)

**Validation** (`_on_delete_account`, line 140): Password required, confirm text must equal "DELETE" exactly. Calls `await Client.delete_account(pw)`. On success, `tree.quit()`.

### Two-Factor Auth Page

Delegated to `UserSettingsTwofa.build()` (line 16). State-driven UI:

**Initial state:** Status label ("not enabled"), "Enable 2FA" button visible.

**After enable request** (line 73): Secret key displayed, 6-digit code input + Verify button shown, Enable button hidden.

**After verification** (line 98): Status changes to "enabled", backup codes displayed, Disable section (password + button) shown, setup UI hidden.

**Disable flow** (line 143): Requires password, calls `client.auth.disable_2fa()`, resets to initial state.

### Connections Page

Built by `_build_connections_page()` (line 642). Shows "Loading connections..." while fetching.

**Fetch** (`_fetch_connections`, line 657): Gets the first connected `AccordClient`, calls `await client.users.list_connections()`. Displays each connection as a row with service type (bold, 14pt) and account name (gray). Shows "Not connected", "Failed to load", or "No connections linked" for edge cases.

### Profile Dialogs

**CreateProfileDialog** (`create_profile_dialog.gd`): Fullscreen overlay (ColorRect, alpha 0.6) with centered panel. Fields: name (max 32), optional password with dynamic confirm field, scratch vs copy radio buttons. Emits `profile_created(slug)`. Closes on background click or Escape (lines 65-73).

**ProfilePasswordDialog** (`profile_password_dialog.gd`): Fullscreen overlay for unlocking password-protected profiles. `setup(slug, name)` sets the title. Password input with Enter-to-submit. Emits `password_verified(slug)` on success. Closes on background click or Escape (lines 51-59).

**ProfileSetPasswordDialog** (`profile_set_password_dialog.gd`): Fullscreen overlay. Conditionally shows current password field and "Remove Password" button based on `has_password`. Validates current password via `Config.verify_profile_password()`, then calls `Config.set_profile_password()`. Closes on background click or Escape (lines 78-86).

### Profile Card (Popup)

`profile_card.gd` is a floating popup shown when clicking a user's avatar. Displays avatar, status dot, display name, username, custom status, activities, device status, bio, roles (space context), badges, member-since date, and a "Message" button for non-self users. Not part of the settings panel but shares the profile data model.

## Implementation Status

- [x] Profiles page with full CRUD (create, rename, delete, switch, reorder)
- [x] Profile password protection (set, change, remove, verify)
- [x] Profile export/import (`.daccord-profile` files)
- [x] My Account page (read-only user info)
- [x] Profile editing (avatar upload/remove, display name, bio, accent color)
- [x] Voice & Video settings (input/output device, resolution, FPS)
- [x] Sound settings (volume slider, per-event toggles)
- [x] Notifications (suppress @everyone, idle timeout, error reporting, reduce motion, per-server mute)
- [x] Change account password with validation
- [x] Delete account with double confirmation (password + type DELETE)
- [x] 2FA enable/verify/disable with backup codes
- [x] Connections page (async-loaded from server)
- [x] Escape key dismissal
- [ ] 2FA status not loaded from server on page open (defaults to "not enabled")
- [ ] No password visibility toggle on any password fields
- [ ] No password strength indicator
- [ ] Settings panel closes on profile switch (no way to stay open)
- [ ] Video device dropdown stored in Config but not exposed in UI
- [ ] Connections page is read-only (no disconnect/manage)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| 2FA page doesn't check actual status on open | High | `_status_label` defaults to "not enabled" (`user_settings_twofa.gd`, line 22) but never queries the server for current 2FA state. Users may see wrong status. |
| Settings close after profile switch | High | `AppState.profile_switched.connect(queue_free)` (`user_settings.gd`, line 184) closes the entire panel. Users must reopen settings to continue configuring. |
| No password visibility toggle | Medium | All password fields (`user_settings_danger.gd` lines 28, 33, 38, 112; `profile_password_dialog.gd` line 74; `profile_set_password_dialog.gd` lines 68, 80, 92) use `secret = true` with no eye icon to reveal text. Standard accessibility expectation. |
| No password strength indicator | Medium | Account password requires 8 chars minimum (`user_settings_danger.gd`, line 59) but shows no real-time strength feedback. Profile passwords have no minimum at all (`create_profile_dialog.gd`, line 47). |
| Profile context menu not discoverable | Medium | The `...` MenuButton (`user_settings.gd`, line 237) has no tooltip. Contains 6 actions (Rename, Set Password, Export, Delete, Move Up, Move Down) that users may not find. |
| No tooltips or help text on settings | Medium | Idle timeout, reduce motion, error reporting, suppress @everyone, video resolution/FPS — none have descriptions explaining their effect. |
| Dialogs close on background click | Medium | `create_profile_dialog.gd` (line 65), `profile_password_dialog.gd` (line 51), `profile_set_password_dialog.gd` (line 78) all call `queue_free()` on any background mouse click. Risk of accidental dismissal during input. |
| 2FA backup codes have no copy button | Medium | Backup codes display as a plain `Label` with newline-separated text (`user_settings_twofa.gd`, line 130). No clipboard copy affordance. |
| Success/error messages share same label | Low | Password change success reuses the error label with a green color override (`user_settings_danger.gd`, lines 77-80). No distinct success styling pattern. |
| No character counters on inputs | Low | Profile name has 32 char `max_length` (`user_settings.gd`, line 296; `create_profile_dialog.tscn`, line 67) but no visible counter. Bio has no limit shown. |
| Video device dropdown not in UI | Low | `Config.get_voice_video_device()` / `set_voice_video_device()` exist (config.gd, lines 241-247) but no UI control is built for it in the Voice page. |
| Import/export has no description | Low | Users don't know what data is included in a `.daccord-profile` export. No help text on the Import or Export buttons (`user_settings.gd`, lines 179, 324). |
| No sound test/preview button | Low | Sound event checkboxes toggle events but there's no way to hear what each sound is (`user_settings.gd`, lines 527-538). |
| Profile reorder has no visual feedback | Low | "Move Up" / "Move Down" silently call `Config.move_profile_up/down()` and refresh the list (`user_settings.gd`, lines 284-288). No animation or confirmation. |
| Inconsistent label casing | Low | Section labels use ALL CAPS ("USERNAME", "INPUT DEVICE") via `_section_label()` but some inline labels use sentence case ("Accent Color" at `user_settings_profile.gd`, line 77; "Reduce motion" at `user_settings.gd`, line 592). |
| Inconsistent button styling | Low | Delete Account button has a custom red `StyleBoxFlat` (`user_settings_danger.gd`, lines 125-135). Most other buttons use default theme. No shared primary/danger button style variants. |
