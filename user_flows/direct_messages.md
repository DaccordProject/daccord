# Direct Messages

## Overview

Users access direct messages by clicking the DM button in the guild bar. This switches the sidebar from the channel list to the DM list. DM channels show recipient avatar, display name, last message preview, and unread indicator. A search field filters DMs by username/display name. Selecting a DM channel loads its messages in the message view.

## User Steps

1. User clicks DM button (top of guild bar)
2. Sidebar switches: channel list hidden, DM list shown
3. DM list populated from `Client.dm_channels`
4. User can search DMs by typing in search field (filters by display_name/username)
5. Click a DM -> messages load in message view, tab created
6. Sending messages works the same as in guild channels

## Signal Flow

```
User clicks DM button
    -> guild_bar.dm_selected signal emitted
    -> sidebar._on_dm_selected()
        -> channel_list.visible = false
        -> dm_list.visible = true
        -> AppState.enter_dm_mode()
            -> is_dm_mode = true, current_guild_id = ""
            -> AppState.dm_mode_entered emitted

User clicks DM channel item
    -> dm_channel_item.dm_pressed signal(dm_id)
    -> dm_list lambda: _set_active_dm(id), dm_selected signal(dm_id)
    -> sidebar._on_dm_selected_channel(dm_id)
        -> AppState.select_channel(dm_id)
            -> current_channel_id = dm_id
            -> AppState.channel_selected emitted
        -> In MEDIUM mode: hides channel panel
        -> AppState.close_sidebar_drawer()
    -> main_window._on_channel_selected(dm_id)
        -> Updates title, creates/switches tab
    -> message_view loads messages for dm_id
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/direct/dm_list.gd` | DM list container, search filtering, dm_selected signal |
| `scenes/sidebar/direct/dm_channel_item.gd` | Individual DM: avatar, username, last message, unread dot |
| `scenes/sidebar/sidebar.gd` | Toggles between channel_list and dm_list |
| `scenes/sidebar/guild_bar/guild_bar.gd` | DM button emits dm_selected signal |
| `scripts/autoload/client.gd` | `fetch_dm_channels()`, `dm_channels` property |
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` conversion |
| `scripts/autoload/app_state.gd` | `enter_dm_mode()`, `dm_mode_entered` signal |

## Implementation Details

DM List (dm_list.gd):
- Header: "DIRECT MESSAGES" label (font size 11, gray)
- Search: LineEdit connected to `_on_search_text_changed()`
- `_populate_dms()`: Clears children, iterates `Client.dm_channels`, instantiates DMChannelItemScene
- Each item connected via lambda: `dm_pressed -> _set_active_dm(id), dm_selected.emit(id)`
- `_set_active_dm(dm_id)`: Deactivates previous, activates new via `set_active()`
- Listens to `AppState.dm_channels_updated` to repopulate
- Search filter (line 46-58): Compares query against display_name and username (case-insensitive contains)

DM Channel Item (dm_channel_item.gd):
- Avatar: ColorRect with circle shader (`theme/avatar_circle.gdshader`, radius 0.5)
- Username label from `data.user.display_name`
- Last message label from `data.last_message` with ellipsis overflow (`OVERRUN_TRIM_ELLIPSIS`)
- Unread dot: ColorRect visible when `data.unread == true`
- `set_active(bool)`: Dark background StyleBoxFlat + white text (same pattern as channel_item)

DM Channel Data (client_models.gd:205-228):
- `dm_channel_to_dict()`: Extracts first recipient from `channel.recipients`
- Returns: `{id, user: {id, display_name, username, color, status, avatar}, last_message: "", unread: false}`
- `last_message` always empty string (line 226)
- `unread` always false (line 227)
- Falls back to channel name or "DM" if no recipients

Client DM Fetching (client.gd:454-483):
- `fetch_dm_channels()`: Uses first connected client
- Calls `client.users.list_channels()` (GET /users/@me/channels)
- Caches recipients in `_user_cache` with OFFLINE status
- Stores converted dicts in `_dm_channel_cache`
- Emits `AppState.dm_channels_updated`

## Implementation Status

- [x] DM button in guild bar
- [x] DM list with channel items
- [x] DM channel item display (avatar, name, last message, unread)
- [x] Circle avatar shader on DM items
- [x] DM search by username/display name
- [x] DM selection with active highlight
- [x] DM mode toggle (channel list <-> DM list)
- [x] Message loading for DM channels
- [x] Gateway real-time updates (channel_create/update/delete for DM type)
- [x] Tab creation for DM channels

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No UI to start a new DM | High | No button or dialog to create a DM with a user. `UsersApi.create_dm()` exists in AccordKit but is unused in UI |
| last_message always empty | Medium | `dm_channel_to_dict()` hardcodes `last_message: ""` (line 226). The last message preview in each DM item is always blank |
| unread always false | Medium | `dm_channel_to_dict()` hardcodes `unread: false` (line 227). Unread dots never appear |
| No multi-server DM | Low | `fetch_dm_channels()` uses `_first_connected_client()` only. DMs from other servers are not fetched |
| No DM close/leave | Low | No way to close or leave a DM conversation from the UI |
| No group DM support in UI | Low | `dm_channel_to_dict()` only extracts first recipient; group DMs would show only one participant |
