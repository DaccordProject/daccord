# Direct Messages


## Overview

Users access direct messages by clicking the DM button in the space bar. This switches the sidebar from the channel list to the DM list. DM channels show recipient avatar, display name, last message preview, and unread indicator. A search field filters DMs by username/display name. Selecting a DM channel loads its messages in the message view.

## User Steps

1. User clicks DM button (top of space bar)
2. Sidebar switches: channel list hidden, DM list shown
3. DM list populated from `Client.dm_channels`
4. User can search DMs by typing in search field (filters by display_name/username)
5. Click a DM -> messages load in message view, tab created
6. Sending messages works the same as in space channels

## Signal Flow

```
User clicks DM button
    -> space_bar.dm_selected signal emitted
    -> sidebar._on_dm_selected()
        -> channel_list.visible = false
        -> dm_list.visible = true
        -> AppState.enter_dm_mode()
            -> is_dm_mode = true, current_space_id = ""
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
| `scenes/sidebar/guild_bar/guild_bar.gd` | DM button emits dm_selected signal (space bar) |
| `scripts/autoload/client.gd` | `fetch_dm_channels()`, `dm_channels` property |
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` conversion |
| `scripts/autoload/app_state.gd` | `enter_dm_mode()`, `dm_mode_entered` signal |

## Implementation Details

DM List (dm_list.gd):
- Header: "DIRECT MESSAGES" label (font size 11, gray)
- Search: LineEdit connected to `_on_search_text_changed()`
- `_populate_dms()`: Clears children, iterates `Client.dm_channels`, instantiates DMChannelItemScene
- Each item connected via lambda: `dm_pressed -> _set_active_dm(id), dm_selected.emit(id)`
- Close button: Each item's `dm_closed` signal calls `Client.close_dm(id)`
- `_set_active_dm(dm_id)`: Deactivates previous, activates new via `set_active()`
- Listens to `AppState.dm_channels_updated` to repopulate
- Search filter: Compares query against display_name and username (case-insensitive contains)

DM Channel Item (dm_channel_item.gd):
- Avatar: ColorRect with circle shader (`theme/avatar_circle.gdshader`, radius 0.5)
- Username label from `data.user.display_name` (group DMs show comma-separated names)
- Last message label from `data.last_message` with ellipsis overflow (`OVERRUN_TRIM_ELLIPSIS`)
- Unread dot: ColorRect visible when `data.unread == true`
- Close button: Flat "X" button, visible on hover, emits `dm_closed(dm_id)`
- `set_active(bool)`: Dark background StyleBoxFlat + white text (same pattern as channel_item)

DM Channel Data (client_models.gd):
- `dm_channel_to_dict()`: Extracts all recipients from `channel.recipients`
- Group DMs (`recipients.size() > 1`): Builds comma-separated display name, sets `is_group: true`
- Returns: `{id, user, recipients, is_group, last_message, last_message_id, unread}`
- `last_message` populated asynchronously after initial fetch via `_fetch_dm_previews()`
- `unread` preserved across re-fetches
- Falls back to channel name or "DM" if no recipients

Client DM Fetching (client_fetch.gd):
- `fetch_dm_channels()`: Iterates all connected servers (multi-server support)
- Calls `client.users.list_channels()` (GET /users/@me/channels) per server
- Caches recipients in `_user_cache` with OFFLINE status
- Stores converted dicts in `_dm_channel_cache`
- Tracks connection routing in `_dm_to_conn` for correct API routing
- Preserves unread state and existing last_message previews across re-fetches
- Emits `AppState.dm_channels_updated`
- Calls `_fetch_dm_previews()` to asynchronously fetch last message content

DM Creation (client.gd):
- `create_dm(user_id)`: Called from member context menu "Message" action
- Uses `UsersApi.create_dm({"recipient_id": user_id})`
- Caches result, enters DM mode, selects the channel

DM Close (client.gd):
- `close_dm(channel_id)`: Called from DM item close button
- Uses `ChannelsApi.delete()` (closes DM, does not permanently delete)
- Removes from cache and emits `dm_channels_updated`

DM Channel Routing (client.gd):
- `_client_for_channel()` and `_cdn_for_channel()` fall back to `_dm_to_conn` routing map for DM channels, then to first connected client/CDN
- Enables message fetching, sending, and typing in DM channels

## Implementation Status

- [x] DM button in space bar
- [x] DM list with channel items
- [x] DM channel item display (avatar, name, last message, unread)
- [x] Circle avatar shader on DM items
- [x] DM search by username/display name
- [x] DM selection with active highlight
- [x] DM mode toggle (channel list <-> DM list)
- [x] Message loading for DM channels
- [x] Gateway real-time updates (channel_create/update/delete for DM type)
- [x] Tab creation for DM channels
- [x] DM channel routing (message fetch/send/typing works)
- [x] Create DM from member context menu ("Message" action)
- [x] Last message preview on initial load
- [x] Unread state preserved across re-fetches
- [x] Multi-server DM fetching
- [x] DM close button (X on hover)
- [x] Group DM display (comma-separated names)

## Gaps / TODO

| Gap | Status | Notes |
|-----|--------|-------|
| ~~No UI to start a new DM~~ | Done | Right-click member -> "Message" creates/opens DM via `Client.create_dm()` |
| ~~last_message always empty~~ | Done | `_fetch_dm_previews()` fetches last message content asynchronously after initial load |
| ~~unread always false~~ | Done | Unread state preserved across re-fetches; `mark_channel_unread()` works for DM channels |
| ~~No multi-server DM~~ | Done | `fetch_dm_channels()` iterates all connected servers; `_dm_to_conn` routes API calls |
| ~~No DM close/leave~~ | Done | Close button (X) on hover in DM items, calls `Client.close_dm()` |
| ~~No group DM support in UI~~ | Done | `dm_channel_to_dict()` extracts all recipients; group DMs show comma-separated names |
