# User Status

## Overview

The user bar sits at the bottom of the sidebar's channel panel. It displays the current user's avatar, display name, username, and status indicator. A dropdown menu allows changing status (Online, Idle, Do Not Disturb, Invisible) and provides About and Quit options. Avatar rendering uses a custom circle shader with hover animation between circle and rounded square.

## User Steps

1. User sees their info in the user bar (bottom of sidebar)
2. Click the user bar -> dropdown menu appears
3. Menu shows status options: Online, Idle, Do Not Disturb, Invisible
4. Select a status -> indicator color changes locally
5. Menu also shows "About" and "Quit" items
6. "Quit" closes the application

## Signal Flow

```
User clicks user bar
    -> PopupMenu shown at user bar position

User selects status
    -> _on_menu_item_pressed(index)
        -> _current_status updated locally
        -> _update_status_indicator() changes indicator color
        -> (Status NOT sent to server)

User selects "Quit"
    -> get_tree().quit()

User presence update from gateway
    -> Client._on_presence_update(presence)
        -> _user_cache[user_id].status updated
        -> AppState.user_updated.emit(user_id)
    -> (user_bar does not currently listen to this signal)
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/user_bar.gd` | User info display, status dropdown menu |
| `theme/avatar_circle.gdshader` | Circle/rounded-square avatar shader |
| `scripts/autoload/client.gd` | `current_user` dict, presence update handler |
| `scripts/autoload/client_models.gd` | `UserStatus` enum, `user_to_dict()` |
| `scripts/autoload/app_state.gd` | `user_updated` signal |

## Implementation Details

### User Bar (user_bar.gd)

- Displays: avatar (ColorRect with circle shader), display_name label, username label (gray, smaller), status indicator (small ColorRect)
- Avatar: ColorRect with `avatar_circle.gdshader`, radius parameter 0.5 (circle)
- Avatar color from `Client.current_user.color`
- Status indicator: small colored circle next to avatar
  - Online: green, Idle: yellow, DND: red, Offline/Invisible: gray
- PopupMenu created in code with items:
  - "Online" (index 0)
  - "Idle" (index 1)
  - "Do Not Disturb" (index 2)
  - "Invisible" (index 3)
  - Separator
  - "About" (index 10)
  - "Quit" (index 11)
- Status change is local only - updates `_current_status` and indicator color
- "About" item: does nothing (no handler)
- "Quit" item: calls `get_tree().quit()`
- Populated from `Client.current_user` dict on `_ready()` or when guilds_updated fires

### Avatar Circle Shader (theme/avatar_circle.gdshader)

- Fragment shader that clips a ColorRect into a rounded shape
- `uniform float radius : hint_range(0.0, 0.5) = 0.5` parameter
- radius = 0.5 -> perfect circle; radius = 0.3 -> rounded square
- Used by: user_bar, cozy_message avatars, dm_channel_item avatars
- Hover animation: tweens radius from 0.5 to 0.3 on guild icons (not on user bar)

### User Status Colors (user_bar.gd)

- Online: `Color(0.231, 0.647, 0.365)` (green)
- Idle: `Color(0.98, 0.659, 0.157)` (yellow/amber)
- DND: `Color(0.929, 0.259, 0.271)` (red)
- Offline/Invisible: `Color(0.58, 0.608, 0.643)` (gray)

### ClientModels UserStatus enum (client_models.gd:10)

- `enum UserStatus { ONLINE, IDLE, DND, OFFLINE }`
- `_status_string_to_enum()` maps "online"/"idle"/"dnd" strings, default OFFLINE

### Presence Updates (client.gd:587-590)

- `_on_presence_update(presence)`: Updates `_user_cache[user_id].status` and emits `AppState.user_updated`
- Gateway sends `presence.update` events with AccordPresence model
- AccordPresence (presence.gd): user_id, status, client_status, activities, space_id

## Implementation Status

- [x] User bar with avatar, display name, username
- [x] Circle avatar shader rendering
- [x] Status indicator with color-coded dot
- [x] Status dropdown menu (Online/Idle/DND/Invisible)
- [x] Local status change (updates indicator color)
- [x] Quit menu item (exits application)
- [x] Presence updates received from gateway
- [x] User cache updated on presence events

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Status change is local-only | High | Selecting a status in the dropdown never sends it to the server. AccordKit has `AccordClient.update_presence(status, activity)` but it's unused |
| Status doesn't persist | Medium | Changing status is lost on restart; no config storage for user status |
| "About" menu does nothing | Low | The "About" menu item has no handler; clicking it does nothing |
| User bar doesn't listen to user_updated | Medium | `AppState.user_updated` is emitted on presence changes but user_bar doesn't connect to it; own user's status changes from other clients won't reflect |
| No avatar image loading | Medium | Avatar is a colored square; even though `user_to_dict()` generates avatar URLs via `AccordCDN.avatar()`, no code loads the actual image |
| No hover animation on user bar avatar | Low | Guild icons have radius 0.5->0.3 hover tween but user bar avatar stays at 0.5 |
| No custom status message | Low | AccordPresence supports activities but the UI has no way to set a custom status text |
