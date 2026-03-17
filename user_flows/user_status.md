# User Status

Priority: 6
Depends on: Server Connection, Data Model
Status: Complete

The user bar displays avatar, name, and status indicator with a popup menu for changing status (Online/Idle/DND/Invisible) and custom status, persisted across restarts and synced to all servers via gateway presence events.

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
