# User Management

> Last touched: 2026-02-19

## Overview

User management covers authentication (sign-in/register), the current-user data model, presence/status control, the user bar UI, the member list with admin actions, avatar rendering, and user caching. The system bridges AccordKit typed models (`AccordUser`, `AccordPresence`) through `ClientModels` conversion into dictionary shapes consumed by all UI components.

## User Steps

### Authentication
1. User opens the Add Server dialog and enters a server URL.
2. If no token is provided, the auth dialog appears with Sign In / Register tabs.
3. User enters username + password (and optionally display name for registration).
4. On success, a bearer token is returned and stored in encrypted config.
5. Subsequent launches re-authenticate automatically using stored credentials if the token expires.

### Status Management
1. User clicks the "..." menu button on the user bar (bottom of sidebar).
2. User selects a status: Online, Idle, Do Not Disturb, or Invisible.
3. Status is persisted to config, sent to all connected servers, and reflected in the user bar and member list.
4. User can set a custom status message via "Set Custom Status" in the same menu.

### Viewing Members
1. User opens a guild channel.
2. The member list panel on the right shows all guild members grouped by status (Online, Idle, DND, Offline).
3. Right-clicking a member shows a context menu with Message (DM), Kick, Ban, and Role assignment options (permission-gated).

## Signal Flow

```
Authentication:
  auth_dialog._on_submit()
    -> AuthApi.login() / AuthApi.register()
    -> auth_completed signal
    -> add_server_dialog._connect_with_token()
    -> Config.add_server()
    -> Client.connect_server()
      -> UsersApi.get_me()
      -> ClientModels.user_to_dict()
      -> _user_cache[id] = dict
      -> current_user = dict
      -> AppState.guilds_updated

Status Update:
  user_bar._on_menu_id_pressed(0-3)
    -> Client.update_presence(status)
    -> ClientMutations.update_presence()
      -> current_user["status"] = status
      -> _user_cache[my_id]["status"] = status
      -> Config.set_user_status(status)
      -> AccordClient.update_presence() (all servers)
      -> AppState.user_updated(my_id)
      -> AppState.members_updated(guild_id) (all guilds)

Incoming Presence:
  Gateway PRESENCE_UPDATE
    -> ClientGateway.on_presence_update()
      -> _user_cache[user_id]["status"] = enum
      -> _member_cache[guild_id] status update
      -> AppState.user_updated(user_id)
      -> AppState.members_updated(guild_id)

Incoming User Update:
  Gateway USER_UPDATE
    -> ClientGateway.on_user_update()
      -> ClientModels.user_to_dict(user, status, cdn_url)
      -> _user_cache[user.id] = new dict
      -> current_user = new dict (if self)
      -> AppState.user_updated(user.id)
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client.gd` | `current_user` dict, `_user_cache`, `connect_server()`, `update_presence()`, `get_user_by_id()`, `trim_user_cache()` |
| `scripts/autoload/client_models.gd` | `UserStatus` enum, `user_to_dict()`, `member_to_dict()`, `_color_from_id()`, `status_color()`, `status_label()`, `USER_FLAGS`, `get_user_badges()`, status string/enum conversion |
| `scripts/autoload/client_mutations.gd` | `update_presence()`, `update_profile()`, `change_password()`, `delete_account()`, `create_dm()`, presence sync to all servers |
| `scripts/autoload/client_gateway.gd` | `on_presence_update()` (line 269), `on_user_update()` (line 282), `on_member_chunk()` (line 293), `on_member_join/leave/update()` |
| `scripts/autoload/config.gd` | `get_user_status()`/`set_user_status()` (lines 146-151), `get_custom_status()`/`set_custom_status()` (lines 153-158), server credential storage |
| `scripts/autoload/app_state.gd` | `user_updated` (line 24), `members_updated` (line 30) signals |
| `scenes/sidebar/user_bar.gd` | Status menu, custom status dialog, avatar display, About/Quit/Sound Settings/Error Reporting |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign In / Register UI, password generation, HTTPS→HTTP fallback |
| `scenes/members/member_list.gd` | Virtualized member list grouped by status, invite button |
| `scenes/members/member_item.gd` | Member display with context menu (Message/Kick/Ban/Roles) |
| `scenes/common/avatar.gd` | Image loading with cache, color fallback, circle shader, hover animation |
| `addons/accordkit/models/user.gd` | `AccordUser` model (id, username, display_name, avatar, banner, bio, is_admin, etc.) |
| `addons/accordkit/models/presence.gd` | `AccordPresence` model (user_id, status, activities, space_id) |
| `addons/accordkit/rest/endpoints/users_api.gd` | `get_me()`, `update_me()`, `fetch()`, `list_spaces()`, `list_channels()`, `create_dm()` |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `register()`, `login()`, `change_password()`, `enable_2fa()`, `verify_2fa()`, `disable_2fa()`, `get_backup_codes()`, token parsing |
| `addons/accordkit/rest/endpoints/users_api.gd` | `get_me()`, `update_me()`, `fetch()`, `list_spaces()`, `list_channels()`, `create_dm()`, `delete_me()`, `list_connections()` |
| `scenes/user/profile_edit_dialog.gd` | Profile edit modal — avatar upload/remove, display name, bio, accent color, dirty tracking |
| `scenes/user/profile_card.gd` | Floating profile card — avatar, status, bio, roles, badges, activities, per-device status, Message button |
| `scenes/user/user_settings.gd` | Full settings panel — 9 pages (My Account, Profile, Voice, Sound, Notifications, Password, Delete, 2FA, Connections) |

## Implementation Details

### AccordUser Model

`AccordUser` (`addons/accordkit/models/user.gd`) is the server-side user representation with fields: `id` (line 6), `username` (line 7), `display_name` (line 8), `avatar` (line 9), `banner` (line 10), `accent_color` (line 11), `bio` (line 12), `bot` (line 13), `system` (line 14), `flags` (line 15), `public_flags` (line 16), `is_admin` (line 17), `created_at` (line 18). Constructed via `AccordUser.from_dict()` (line 21).

### User Dictionary Shape

`ClientModels.user_to_dict()` (line 134) converts `AccordUser` into the UI dictionary:

```gdscript
{
    "id": String,
    "display_name": String,  # falls back to username
    "username": String,
    "color": Color,           # deterministic from ID hash
    "status": int,            # UserStatus enum
    "avatar": String or null, # CDN URL via AccordCDN.avatar()
    "is_admin": bool,
    "bio": String,            # user bio / about me
    "banner": String or null, # CDN URL for banner
    "accent_color": int,      # profile accent color (RGBA32)
    "flags": int,             # user flags bitmask
    "public_flags": int,      # public user flags bitmask
    "created_at": String,     # ISO 8601 timestamp
    "bot": bool,              # whether user is a bot
    "client_status": Dictionary,  # device -> status string (populated by presence)
    "activities": Array,      # activity dicts (populated by presence)
}
```

Avatar color is generated deterministically from the user ID via `_color_from_id()` (line 25), which hashes the ID into one of 10 HSV colors (lines 12-23).

### UserStatus Enum

Defined at `client_models.gd:10`:
- `ONLINE = 0` — green `Color(0.231, 0.647, 0.365)`
- `IDLE = 1` — yellow `Color(0.98, 0.659, 0.157)`
- `DND = 2` — red `Color(0.929, 0.259, 0.271)`
- `OFFLINE = 3` — gray `Color(0.58, 0.608, 0.643)`

Conversion between server strings ("online", "idle", "dnd", "offline") and enum values is handled by `_status_string_to_enum()` (line 31) and `_status_enum_to_string()` (line 42).

### Authentication Flow

**AuthApi** (`addons/accordkit/rest/endpoints/auth_api.gd`):
- `register(data)` (line 19): `POST /auth/register` with `{username, password, display_name?}`.
- `login(data)` (line 29): `POST /auth/login` with `{username, password}`.
- Both return `{user: AccordUser, token: String}` via `_parse_auth_response()` (line 37).

**Auth Dialog** (`scenes/sidebar/guild_bar/auth_dialog.gd`):
- Two modes: `SIGN_IN` and `REGISTER` (line 8), toggled by tab buttons.
- Sign In mode shows username + password fields. Register mode adds display name input, Generate Password button (12-char random, line 109), and View/Hide password toggle (line 119).
- On submit (line 70): validates inputs, calls `_try_auth()` (line 131), falls back HTTPS→HTTP (lines 88-90), emits `auth_completed` signal (line 105).
- Auto-fills display name from username during registration (line 124).

**Token Re-authentication** (`client.gd:704`):
- `_try_reauth()` uses stored `username` and `password` from Config to call `AuthApi.login()` and obtain a fresh token when the saved token expires. Called during `connect_server()` (line 162).

### User Caching

**Cache structure** (`client.gd`):
- `_user_cache: Dictionary` (line 37): maps `user_id -> user_dict`. Populated on login (`connect_server()`, line 199), message receipt (when author unknown), member chunks, and presence updates.
- `USER_CACHE_CAP := 500` (line 13): maximum cache size.
- `trim_user_cache()` (line 726): evicts users not in the keep set (current user, current guild members, current channel message authors).
- `current_user: Dictionary` (line 16): the authenticated user's dict, set during `connect_server()` (line 200-201).

**Member cache** (`client.gd:42`):
- `_member_cache: Dictionary` maps `guild_id -> Array[member_dict]`. Members include user fields plus `roles` and `joined_at` via `ClientModels.member_to_dict()` (line 318 of `client_models.gd`).

### Presence Management

**Outgoing** (`client_mutations.gd:273`):
1. Updates `current_user["status"]` (line 276).
2. Updates `_user_cache[my_id]["status"]` (line 279).
3. Persists via `Config.set_user_status()` (line 280).
4. Converts to server string and sends to all connected servers via `AccordClient.update_presence()` (lines 282-286).
5. Emits `AppState.user_updated(my_id)` (line 287).
6. Updates `_member_cache` status for every guild and emits `AppState.members_updated()` (lines 288-293).

**Incoming presence** (`client_gateway.gd:269`):
- Updates `_user_cache` status via `_status_string_to_enum()` (line 271).
- Updates `_member_cache` for the source guild (lines 275-280).
- Emits `user_updated` and `members_updated` signals.

**Incoming user update** (`client_gateway.gd:282`):
- Preserves existing status from cache (line 287).
- Rebuilds user dict via `user_to_dict()` (line 288).
- Updates `current_user` if the updated user is self (lines 289-290).

**Status restoration** (`client.gd:284-288`):
- On first server connection, restores saved status from `Config.get_user_status()`. If not ONLINE, calls `update_presence()` to sync the saved status to the server.

### User Bar

`scenes/sidebar/user_bar.gd` is the bottom sidebar panel showing the current user's avatar, display name, username, status indicator, and voice indicator.

**Setup** (line 52): Renders display_name, username, avatar color/URL, and status indicator dot with enum-matched colors (lines 65-81). Custom status is shown as a tooltip (lines 83-85).

**Menu**: MenuButton with items:
- IDs 0-3: Status changes (Online, Idle, DND, Invisible)
- ID 4: Custom status dialog
- ID 5: Edit Profile (opens `ProfileEditDialog`)
- ID 6: Settings (opens `UserSettings` panel)
- ID 10: About dialog
- ID 11: Quit
- ID 12: Sound settings
- ID 13: Report a Problem
- ID 14: Toggle error reporting (checkbox)

**Custom status dialog** (line 155): Creates an `AcceptDialog` with a `LineEdit` and "Clear Status" button. On confirm, saves to `Config.set_custom_status()` and sends presence update with activity name (lines 174-186).

**Signal connections** (lines 49-50): Listens to `AppState.guilds_updated` and `AppState.user_updated` to refresh display when user data changes.

**Avatar hover animation** (lines 100-104): Tweens the shader `radius` parameter between 0.5 (circle) and 0.3 (rounded square).

### Avatar Component

`scenes/common/avatar.gd` is a reusable `ColorRect` with the circle shader.

- **Static image cache** (line 6): `_image_cache: Dictionary` shared across all avatar instances.
- **`set_avatar_url(url)`** (line 39): checks cache first, then fetches via `HTTPRequest`. Supports PNG, JPG, WebP (lines 65-69).
- **`set_avatar_color(c)`** (line 29): sets background color and auto-picks black/white font color based on luminance.
- **`tween_radius(from, to, duration)`** (line 100): animated shader parameter change for hover effects.

### Member List

`scenes/members/member_list.gd` is a virtualized scrollable list.

- **Status grouping** (lines 49-87): Members are grouped into ONLINE, IDLE, DND, OFFLINE buckets, each sorted alphabetically by display name. Headers show status label and count (e.g., "ONLINE — 5").
- **Virtual scrolling** (lines 96-157): Uses pooled `member_item` and `member_header` instances repositioned during scroll, with `ROW_HEIGHT = 44` (line 6).
- **Invite button** (line 41): Visible only if user has `CREATE_INVITES` permission.
- **Refresh triggers** (lines 31-32): `guild_selected` and `members_updated` signals.

### Member Item

`scenes/members/member_item.gd` displays a single member with avatar, name, and status dot.

- **Context menu** (line 41): Right-click shows:
  - "Message" — creates a DM via `Client.create_dm()` (line 102).
  - "Kick" — gated by `KICK_MEMBERS` permission (line 58), shows confirm dialog.
  - "Ban" — gated by `BAN_MEMBERS` permission (line 62), shows ban dialog.
  - "Roles" — gated by `MANAGE_ROLES` permission (line 66), shows checkable role list with toggle support.
- **Self-protection** (line 44): Context menu is suppressed for the current user.
- **Role toggle** (line 120): Calls `Client.admin.add_member_role()` or `remove_member_role()` with visual feedback flash (green = success, red = failure).

### Config Persistence

`scripts/autoload/config.gd` stores user-related settings in an encrypted `ConfigFile` at `user://config.cfg`:

- **Server credentials** (lines 35-47): `base_url`, `token`, `guild_name`, `username`, `password` per server section.
- **User status** (lines 146-151): `get_user_status()` / `set_user_status()` — persists UserStatus enum int.
- **Custom status** (lines 153-158): `get_custom_status()` / `set_custom_status()` — persists string.
- **Error reporting consent** (lines 160-172): `get_error_reporting_enabled()`, `set_error_reporting_enabled()`, `has_error_reporting_preference()`.
- **Encryption** (lines 8-16): Config is encrypted with a key derived from `_SALT + OS.get_user_data_dir()`. Falls back to plaintext on first run and auto-migrates.

## Implementation Status

- [x] User registration with username, password, and optional display name
- [x] User sign-in with username and password
- [x] Bearer token storage in encrypted config
- [x] Automatic token re-authentication with stored credentials
- [x] HTTPS to HTTP fallback for authentication
- [x] Current user display in user bar (avatar, name, status)
- [x] Status selection (Online, Idle, DND, Invisible)
- [x] Status persistence across sessions
- [x] Custom status message with activity payload
- [x] Real-time presence updates via gateway
- [x] User cache with 500-entry cap and eviction
- [x] Member list with status grouping and virtual scrolling
- [x] Member context menu (Message, Kick, Ban, Role assignment)
- [x] Permission-gated admin actions on members
- [x] Avatar image loading with CDN URLs and in-memory cache
- [x] Avatar hover animation (circle to rounded square)
- [x] Deterministic avatar color from user ID hash
- [x] About dialog with version info
- [x] Sound settings dialog
- [x] Error reporting toggle and feedback dialog
- [x] User profile editing (display name, avatar, bio, accent color) via Edit Profile dialog and Settings > Profile
- [x] User profile popup/card on click (avatar/name click in messages and member list)
- [x] User settings panel (My Account, Profile, Voice & Video, Sound, Notifications, Change Password, Delete Account, 2FA, Connections)
- [x] Password change (Settings > Change Password, calls `AuthApi.change_password()`)
- [x] Account deletion (Settings > Delete Account, requires password + "DELETE" confirmation)
- [x] Two-factor authentication (Settings > 2FA, enable/verify/disable flow via `AuthApi`)
- [x] Idle timeout (auto-set Idle after configurable inactivity, restores on input)
- [x] Per-device status (displayed in profile card with colored device labels)
- [x] Activity display (profile card shows "Playing X", "Listening to Y", etc.)
- [x] User flags/badges display (profile card shows badge pills from `public_flags`)
- [x] OAuth connections UI (Settings > Connections, lists linked services)
- [x] Avatar LRU cache eviction (200-entry cap with access-order tracking)
- [x] Centralized status colors via `ClientModels.status_color()` and `status_label()`

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Server-side 2FA endpoints may not exist yet | Low | `AuthApi` stubs (`enable_2fa`, `verify_2fa`, `disable_2fa`, `get_backup_codes`) are wired but depend on accordserver implementing the corresponding routes. |
| Server-side password change endpoint may not exist yet | Low | `AuthApi.change_password()` calls `POST /auth/password` which may not be implemented in accordserver. |
| Server-side account deletion endpoint may not exist yet | Low | `UsersApi.delete_me()` calls `DELETE /users/@me` which may not be implemented in accordserver. |
| Banner image upload not supported | Low | Profile editing supports avatar upload but not banner image upload (would need a separate CDN upload endpoint). |
| Profile card positioning on small screens | Low | Profile card position clamping may not be ideal on very small viewports where the card is larger than available space. |
