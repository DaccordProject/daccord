# User Status


## Overview

The user bar sits at the bottom of the sidebar's channel panel. It displays the current user's avatar, display name, username, and status indicator. Clicking the status indicator opens a popup menu for changing status (Online, Idle, Do Not Disturb, Invisible) and setting a custom status message. The "..." MenuButton provides profile, settings, and app-level options. Status changes are sent to all connected servers via AccordKit and reflected in real time. Status persists across app restarts via Config. Incoming presence updates from the gateway update caches and the user bar UI automatically. Avatar images are loaded from CDN URLs with a fallback to colored circles, and the avatar animates between circle and rounded-square on hover.

## User Steps

1. User sees their info in the user bar (bottom of sidebar)
2. Click the status indicator (colored dot) -> status popup appears
3. Popup shows status options: Online, Idle, Do Not Disturb, Invisible, Set Custom Status
4. Select a status -> status is sent to all connected servers, indicator color updates, status persists to config
5. Other users see the status change via gateway presence events
6. "Set Custom Status" opens a dialog to enter/clear a custom status message
7. The "..." MenuButton provides Edit Profile, Settings, and other app-level options
8. On next launch, the saved status is restored after the first server connects

## Signal Flow

```
User clicks status indicator -> status popup appears
User selects status from status popup
    -> _on_status_id_pressed(id)
        -> Client.update_presence(status_enum, activity)
            -> ClientMutations.update_presence(status_enum, activity)
                -> Client.current_user["status"] updated
                -> Client._user_cache[my_id]["status"] updated
                -> Config.set_user_status(status) persists to disk
                -> Status string + activity sent to all connected servers via AccordClient.update_presence()
                -> AppState.user_updated.emit(my_id)
                -> Client._member_cache updated for all spaces
                -> AppState.members_updated.emit(space_id) for each space
        -> setup(Client.current_user) refreshes indicator color

User sets custom status
    -> _show_custom_status_dialog()
        -> On confirm: Config.set_custom_status(text)
        -> Client.update_presence(current_status, {"name": text})
        -> setup() refreshes tooltip with custom status

User selects "About"
    -> _show_about_dialog()
        -> AcceptDialog with app name and version from ProjectSettings

User selects "Quit"
    -> get_tree().quit()

App startup (first server connects)
    -> Client.connect_server() enters LIVE mode
        -> Config.get_user_status() loads saved status
        -> Client.update_presence(saved_status) if not ONLINE

Presence update received from gateway
    -> ClientGateway.on_presence_update(presence, conn_index)
        -> Client._user_cache[user_id]["status"] updated (string -> enum)
        -> AppState.user_updated.emit(user_id)
        -> Client._member_cache[space_id] updated
        -> AppState.members_updated.emit(space_id)
    -> user_bar._on_user_updated(user_id)
        -> If user_id matches current user, calls setup(Client.current_user)
        -> Status indicator color refreshed
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/user_bar.gd` | User info display, status dropdown, avatar loading, hover animation, About/custom status dialogs |
| `scenes/sidebar/user_bar.tscn` | Scene: PanelContainer with avatar, labels, status icon, voice indicator, MenuButton |
| `scenes/common/avatar.gd` | Avatar component with `set_avatar_url()`, `set_avatar_color()`, `tween_radius()`, HTTP image caching |
| `theme/avatar_circle.gdshader` | Circle/rounded-square avatar shader |
| `scripts/autoload/config.gd` | `get_user_status()`/`set_user_status()`, `get_custom_status()`/`set_custom_status()` for persistence |
| `scripts/autoload/client.gd` | `current_user` dict, routes `update_presence(status, activity)` to mutations, restores saved status on first connection |
| `scripts/autoload/client_mutations.gd` | `update_presence(status, activity)` -- updates caches, persists to config, sends to servers, emits signals |
| `scripts/autoload/client_gateway.gd` | `on_presence_update()` -- handles inbound presence events |
| `scripts/autoload/client_models.gd` | `UserStatus` enum, `_status_string_to_enum()`, `_status_enum_to_string()` |
| `scripts/autoload/app_state.gd` | `user_updated` and `members_updated` signals |

## Implementation Details

### User Bar (user_bar.gd)

- Displays: avatar (ColorRect with circle shader + CDN image), display_name label, username label (gray, 11px), status indicator (14x14 clickable ColorRect), voice indicator, MenuButton ("...")
- Avatar: loads image via `set_avatar_url()` from user dict's `"avatar"` key; falls back to colored circle if no URL
- Avatar hover: tweens radius 0.5->0.3 on mouse enter, 0.3->0.5 on mouse exit (same pattern as space icons)
- Custom status: displayed as tooltip on the user bar PanelContainer
- Status indicator: clickable colored dot with pointing hand cursor and "Change status" tooltip
  - Online: green, Idle: yellow, DND: red, Offline/Invisible: gray
  - Clicking opens a dedicated status PopupMenu
- Status PopupMenu (`_status_popup`) created in `_ready()` with items:
  - "Online" (id 0)
  - "Idle" (id 1)
  - "Do Not Disturb" (id 2)
  - "Invisible" (id 3)
  - Separator
  - "Set Custom Status" (id 4)
- `_on_status_id_pressed(id)`: calls `Client.update_presence()` for status items 0-3, custom status dialog for 4
- MenuButton ("...") popup provides: Edit Profile, Settings, Suppress @everyone, Export/Import Profile, Report a Problem, Check for Updates, About, Quit
- Signal connections:
  - `AppState.spaces_updated` -> `_on_spaces_updated()` -> refreshes from `Client.current_user`
  - `AppState.user_updated` -> `_on_user_updated(user_id)` -> refreshes if ID matches current user
  - `AppState.voice_joined` / `voice_left` -> toggles voice indicator visibility
  - `avatar.mouse_entered` / `mouse_exited` -> hover radius animation

### Status Persistence (config.gd)

- `get_user_status() -> int`: reads from `"state"` section, defaults to 0 (ONLINE)
- `set_user_status(status: int)`: writes to `"state"` section, saves encrypted config
- `get_custom_status() -> String`: reads custom status text, defaults to `""`
- `set_custom_status(text: String)`: writes custom status text, saves encrypted config

### Status Restore on Startup (client.gd)

- After `connect_server()` transitions from CONNECTING to LIVE for the first time:
  - Loads saved status via `Config.get_user_status()`
  - If not ONLINE, calls `update_presence(saved_status)` to restore it

### Status Update Flow (client_mutations.gd)

- `update_presence(status, activity)`:
  1. Sets `Client.current_user["status"]` to the enum value
  2. Updates `Client._user_cache[my_id]["status"]`
  3. Persists to config via `Config.set_user_status(status)`
  4. Converts enum to string via `ClientModels._status_enum_to_string()`
  5. Sends to all connected servers: `conn["client"].update_presence(status_string, activity)`
  6. Emits `AppState.user_updated(my_id)`
  7. Updates `Client._member_cache` for all spaces where user is a member
  8. Emits `AppState.members_updated(space_id)` for each space

### Gateway Presence Handler (client_gateway.gd)

- `on_presence_update(presence, conn_index)`:
  1. Updates `Client._user_cache[user_id]["status"]` (string -> enum via `_status_string_to_enum`)
  2. Emits `AppState.user_updated(user_id)`
  3. Updates `Client._member_cache[space_id]` for the connection's space
  4. Emits `AppState.members_updated(space_id)`

### Avatar Circle Shader (theme/avatar_circle.gdshader)

- Fragment shader that clips a ColorRect into a rounded shape
- `uniform float radius : hint_range(0.0, 0.5) = 0.5` parameter
- radius = 0.5 -> perfect circle; radius = 0.3 -> rounded square
- Used by: user_bar, cozy_message avatars, dm_channel_item avatars, space icons
- Hover animation: tweens radius from 0.5 to 0.3 on space icons and user bar avatar

### User Status Colors (user_bar.gd)

- Online: `Color(0.231, 0.647, 0.365)` (green)
- Idle: `Color(0.98, 0.659, 0.157)` (yellow/amber)
- DND: `Color(0.929, 0.259, 0.271)` (red)
- Offline/Invisible: `Color(0.58, 0.608, 0.643)` (gray)

### ClientModels UserStatus enum (client_models.gd:10)

- `enum UserStatus { ONLINE, IDLE, DND, OFFLINE }`
- `_status_string_to_enum()` maps "online"/"idle"/"dnd" strings, default OFFLINE
- `_status_enum_to_string()` maps enum values back to server strings

## Implementation Status

- [x] User bar with avatar, display name, username
- [x] Circle avatar shader rendering
- [x] Avatar image loading from CDN URL (with fallback to colored circle)
- [x] Avatar hover animation (circle to rounded-square)
- [x] Status indicator with color-coded dot
- [x] Status dropdown menu (Online/Idle/DND/Invisible)
- [x] Status sent to all connected servers via AccordKit
- [x] Status persists across app restarts (Config storage)
- [x] Status restored on startup after first server connects
- [x] Local caches updated (current_user, user_cache, member_cache)
- [x] User bar listens to `user_updated` signal for real-time sync
- [x] About dialog with app name and version
- [x] Custom status message (set/clear via dialog, sent as activity, persisted to config)
- [x] Quit menu item (exits application)
- [x] Presence updates received from gateway
- [x] User and member caches updated on inbound presence events
- [x] Voice indicator toggled via `voice_joined`/`voice_left` signals
