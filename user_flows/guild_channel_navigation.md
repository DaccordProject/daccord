# Space & Channel Navigation

Last touched: 2026-02-19

## Overview

After connecting to a server, users navigate through spaces and channels. The space bar on the far left shows space icons, space folders, and a DM button. Selecting a space loads its channel list in the channel panel. Channels are grouped into collapsible categories. Selecting a channel opens it in the message view and creates a tab in the tab bar.

## User Steps

1. User sees space icons in the space bar (left strip)
2. Click a space icon -> channel list loads for that space
3. Channels are grouped under category headers (collapsible)
4. Click a channel -> messages load, tab appears in tab bar
5. Click another channel -> new tab opens (or switches to existing tab)
6. Click tab "x" to close a tab (minimum 1 tab required)
7. Tab bar hidden when only 1 tab exists
8. Space folders group multiple spaces (collapsible in sidebar)
9. Right-click space icon -> context menu with admin tools, folder management, reconnect, remove

## Signal Flow

```
User clicks space icon
    -> guild_bar._on_space_pressed(space_id)
    -> guild_bar.space_selected signal emitted
    -> sidebar._on_space_selected(space_id)
        -> channel_list.visible = true, dm_list.visible = false
        -> channel_list.load_space(space_id)
            -> Client.get_channels_for_space(space_id)
            -> Clears existing channel nodes
            -> Groups channels by category (parent_id)
            -> Instantiates CategoryItemScene / ChannelItemScene / VoiceChannelItemScene
        -> AppState.select_space(space_id)
            -> Sets current_space_id, is_dm_mode = false
            -> AppState.space_selected emitted

User clicks channel
    -> channel_item.channel_pressed signal(channel_id)
    -> channel_list._on_channel_pressed(channel_id)
        -> If VOICE channel: toggles join/leave via Client.join/leave_voice_channel()
           and returns early (no channel_selected signal, no tab created)
        -> Deactivates previous channel (set_active(false))
        -> Activates new channel (set_active(true))
        -> channel_list.channel_selected emitted
    -> sidebar._on_channel_selected(channel_id)
        -> AppState.select_channel(channel_id)
            -> Sets current_channel_id
            -> AppState.channel_selected emitted
        -> In MEDIUM mode: hides channel panel
        -> Calls AppState.close_sidebar_drawer()
    -> main_window._on_channel_selected(channel_id)
        -> Updates window title and topic bar
        -> Checks if tab exists, switches or creates new tab
    -> message_view._on_channel_selected(channel_id)
        -> Calls Client.fetch_messages(channel_id)
        -> Renders messages (cozy/collapsed layout)

Unread tracking (on new message via gateway)
    -> client_gateway.on_message_create()
        -> If channel_id != current and author != self:
            -> Client.mark_channel_unread(channel_id, is_mention)
                -> Sets _unread_channels[cid] = true
                -> Updates _channel_cache[cid]["unread"] = true
                -> Calls _update_space_unread(space_id)
                    -> Aggregates unread/mentions across space channels
                    -> Updates _space_cache[gid]["unread"] and ["mentions"]
                -> Emits channels_updated, spaces_updated
    -> channel_list reloads (channels_updated)
        -> channel_item shows unread dot + white text
    -> guild_bar reloads (spaces_updated)
        -> space icon shows unread pill + mention badge

Clearing unread (on channel selection)
    -> Client._on_channel_selected_clear_unread(cid)
        -> Erases from _unread_channels and _channel_mention_counts
        -> Sets _channel_cache[cid]["unread"] = false
        -> Recalculates space unread via _update_space_unread()
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_bar.gd` | Space bar container, emits space_selected/dm_selected |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Individual space icon with selection pill, mentions badge, context menu, folder management |
| `scenes/sidebar/guild_bar/guild_folder.gd` | Collapsible group of space icons with mini-grid preview |
| `scenes/sidebar/channels/channel_list.gd` | Channel list, groups by category, emits channel_selected |
| `scenes/sidebar/channels/channel_item.gd` | Individual text/announcement/forum channel with type icon, unread dot, `set_active()`, drag-and-drop |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel with live participant list, mute/deaf/video/stream indicators |
| `scenes/sidebar/channels/category_item.gd` | Collapsible category header with chevron |
| `scenes/sidebar/channels/banner.gd` | Space banner (color + name) above channel list, admin dropdown |
| `scenes/sidebar/sidebar.gd` | Orchestrates space bar, channel list, DM list |
| `scenes/main/main_window.gd` | Tab management (lines 98-157) |
| `scripts/autoload/app_state.gd` | space_selected, channel_selected signals |
| `scripts/autoload/client.gd` | get_channels_for_space(), mark_channel_unread(), update_space_folder() |
| `scripts/autoload/client_gateway.gd` | Gateway event handlers that preserve unread/folder state on updates |
| `scripts/autoload/client_models.gd` | space_to_dict(), channel_to_dict() conversions |
| `scripts/autoload/config.gd` | Space folder persistence (get/set_space_folder) |

## Implementation Details

### Space Bar (guild_bar.gd)

- Contains space icons in a VBoxContainer with scroll
- DM button at top, Add Server "+" button at bottom
- Selection tracking: `active_space_id` and `space_icon_nodes` dictionary (line 10-11)
- `space_icon_nodes` stores both `guild_icon` and `guild_folder` nodes
- Uses `has_method("set_active")` check since both types are stored in same dict (line 67, 76)
- `_populate_spaces()` (line 23): Groups spaces by `folder` field -- standalone spaces rendered individually, spaces sharing the same folder name are grouped into a `GuildFolderScene`
- Listens to `AppState.spaces_updated` to rebuild the entire space list (line 20, 81-85)

### Space Icon (guild_icon.gd)

- AvatarRect with colored background and first letter of space name
- `setup(data)` (line 53): Sets icon_color, space name initial, tooltip; loads space icon image via `avatar_rect.set_avatar_url(icon_url)` if the server provides one (lines 64-66)
- `set_active(bool)` (line 79): Animates selection pill between ACTIVE/UNREAD/HIDDEN states
- Hover effects: avatar radius tweens between 0.5 (circle) and 0.3 (rounded square) (lines 92-104)
- Unread pill: shows UNREAD state when `_has_unread` is true and space is not active (line 74-75)
- Mention badge: `PanelContainer` with count, set from `data.mentions` (line 69-71)
- **Context menu** (right-click, line 111): Permission-gated items for Space Settings, Channels, Roles, Bans, Invites, Emojis. Also includes Reconnect (when disconnected/error), Move to Folder / Remove from Folder, and Remove Server.
- **Folder management**: "Move to Folder" opens a dialog showing existing folder names as quick-select buttons plus a text field for new folder names. "Remove from Folder" clears the assignment immediately.
- Connection status dot: yellow for disconnected/reconnecting, red for error (lines 212-223)

### Space Folder (guild_folder.gd)

- Collapsible container for multiple space icons
- Header button with mini-grid preview (up to 4 color swatches, line 40-45)
- `setup(p_name, spaces, folder_color)` (line 28): Creates mini-grid preview and full space icon list
- Folder color: darkened version of provided color on button background (line 34)
- `_toggle_expanded()` (line 57): Animated expand/collapse with alpha tween
- Does not implement `set_active()`; space_bar checks `has_method("set_active")` before calling, so folders are skipped gracefully

### Channel List (channel_list.gd)

- `load_space(space_id)` (line 22): Fetches and renders channels
- Groups channels: first pass finds categories (type == CATEGORY), second pass assigns children via parent_id (lines 66-80)
- Channels and categories sorted by position then name (lines 83-104)
- Uncategorized channels rendered first, then categories with children
- Voice channels use `VoiceChannelItemScene` instead of `ChannelItemScene` (lines 108-113)
- Tracks `channel_item_nodes` dict and `active_channel_id` for selection state
- Listens to `AppState.channels_updated` to reload on gateway events (line 20)
- Auto-select: pending channel if set, otherwise first non-voice/non-category channel (lines 143-157)
- **Empty state** (lines 44-63): When a space has 0 non-category channels, shows a centered `EmptyState` VBoxContainer with title, description, and a prominent "Create Channel" button (for users with `MANAGE_CHANNELS` permission). Non-admins see "This space doesn't have any channels yet. Check back soon!" with no button. The `+ Create Channel` text link at the bottom only appears when channels already exist.

### Channel Item (channel_item.gd)

- Type icon: TEXT_ICON, VOICE_ICON, ANNOUNCEMENT_ICON, FORUM_ICON (preloaded SVGs, lines 5-8)
- NSFW indicator: tints type icon red (Color(0.9, 0.2, 0.2)) when `data.nsfw == true` (lines 55-58)
- Unread dot: ColorRect visible when `data.unread == true` (line 72); text turns white when unread (line 74)
- `set_active(bool)` (line 91): Applies/removes dark background StyleBoxFlat + white text
- Gear button: shown on hover for users with MANAGE_CHANNELS permission (lines 79-89)
- Context menu (right-click): Edit Channel and Delete Channel options (lines 112-146)
- **Drag-and-drop reordering** (lines 150-213): Users with MANAGE_CHANNELS can drag channels within the same parent container. Drop indicator line shows above/below target. Calls `Client.admin.reorder_channels()` with new position array.

### Voice Channel Item (voice_channel_item.gd)

- Dedicated scene for voice channels, separate from `channel_item.gd`
- Listens to `AppState.voice_state_updated`, `voice_joined`, `voice_left` signals (lines 20-22)
- `_refresh_participants()` (line 50): Queries `Client.get_voice_users(channel_id)` to get live voice state
- User count label shown when count > 0 (lines 59-63)
- Green tint on icon and white text when user is connected to this channel (lines 66-71)
- Participant list: avatar, display name, mute/deaf indicators (M/D in red), video/stream indicators (V in green, S in blue) (lines 73-148)

### Category Item (category_item.gd)

- `setup(data, child_channels)`: Note the unique signature (data + children array)
- Category name displayed in UPPERCASE, font size 11, gray color
- Chevron toggles between CHEVRON_DOWN and CHEVRON_RIGHT
- `_toggle_collapsed()`: Toggles `channel_container.visible`
- `get_channel_items()`: Returns child channel items for node tracking
- Collapse state persisted via `Config.set_category_collapsed()` / `Config.is_category_collapsed()`

### Tab Management (main_window.gd)

- `tabs: Array[Dictionary]` with `{name, channel_id}` entries (line 8)
- No hardcoded initial tab — tabs are created dynamically when channels are selected
- `_on_channel_selected()` (line 98): Searches for existing tab by channel_id, switches or creates new tab; also updates window title and topic bar
- `_add_tab()` (line 134): Appends to array, adds to TabBar, sets current
- `_on_tab_close()` (line 145): Prevents closing last tab, removes from array and TabBar
- `_update_tab_visibility()` (line 155): Hides TabBar when only 1 tab
- Tab close policy: `tab_close_display_policy = 1` (show on hover)
- Channel name lookup: searches Client.channels then Client.dm_channels (lines 102-111)
- Topic bar: Shows channel topic if present, hidden if empty (lines 119-124)

### Banner (banner.gd)

- Displays space name (white, 16px) on darkened icon_color background
- `setup(space_data)`: Sets name and color from space dict, shows/hides dropdown icon based on admin permissions
- **Clickable admin dropdown**: The entire banner is clickable (left-click) for users with any admin permission. Opens a `PopupMenu` with permission-gated items: Space Settings (`manage_space`), Channels (`manage_channels`), Roles (`manage_roles`), Bans (`ban_members`), Invites (`create_invites`), Emojis (`manage_emojis`). A small `▼` icon in the bottom-right corner indicates the dropdown is available. Cursor changes to pointing hand on hover.
- This provides a discoverable alternative to the space icon right-click context menu for accessing admin tools.

### Unread & Mention Tracking (client.gd)

- `_unread_channels: Dictionary` and `_channel_mention_counts: Dictionary` track per-channel unread state (lines 48-49)
- `mark_channel_unread(cid, is_mention)` (line 564): Sets channel and space cache unread flags, emits `channels_updated` and `spaces_updated`
- `_on_channel_selected_clear_unread(cid)` (line 549): Clears unread state when user views a channel
- `_update_space_unread(gid)` (line 582): Aggregates per-channel unread/mentions into space-level totals
- Gateway events (`on_message_create`, line 180-184 in client_gateway.gd): Calls `mark_channel_unread()` for messages arriving on non-active channels from other users
- **State preservation**: `on_channel_update()` and `on_space_update()` in `client_gateway.gd` preserve existing `unread`, `mentions`, `voice_users`, and `folder` values when rebuilding cache entries from gateway events (lines 430-458, 392-401)

### Space Folder Persistence (config.gd, client.gd)

- `Config.get_space_folder(space_id)` / `Config.set_space_folder(space_id, folder_name)`: Persists folder assignment per space in the encrypted config file
- `Config.get_all_folder_names()`: Returns deduplicated list of all folder names in use
- `Client.update_space_folder(gid, folder_name)` (line 536): Updates the space cache and emits `spaces_updated`
- On initial connection, `Client.connect_server()` applies `Config.get_space_folder()` to each space dict after conversion
- guild_bar `_populate_spaces()` groups spaces by `folder` field -- spaces sharing the same folder name are grouped into a `GuildFolderScene`

## Implementation Status

- [x] Space bar with icons for each connected space
- [x] Space selection with active pill indicator
- [x] Space icon images loaded from server when available (AccordCDN URL)
- [x] Space folders (collapsible groups with mini-grid preview)
- [x] Space folder assignment via context menu (client-side persistence in Config)
- [x] Channel list grouped by categories
- [x] Category headers (collapsible with chevron, collapse state persisted)
- [x] Channel type icons (text, voice, announcement, forum)
- [x] Channel selection with active highlight
- [x] Tab bar for open channels (dynamic, no hardcoded initial tab)
- [x] Tab creation on channel select
- [x] Tab close with minimum-1-tab safety
- [x] Space banner with name and color
- [x] Banner dropdown menu for admin settings (clickable, permission-gated)
- [x] Channel list empty state (admin CTA vs non-admin message)
- [x] NSFW channel indicator (red-tinted icon)
- [x] Voice channel with live participant list (avatar, name, mute/deaf/video/stream indicators)
- [x] Mention badge on space icons
- [x] Unread indicators on channels (dot + white text) and spaces (pill + mention count)
- [x] Unread state preserved across gateway channel/space update events
- [x] Unread cleared on channel selection
- [x] Voice channel click toggles join/leave (no tab or message view)
- [x] Drag-to-reorder channels and categories (calls Client.admin.reorder_channels())
- [x] Channel edit/delete via context menu and gear button (MANAGE_CHANNELS permission)
- [x] Space icon connection status dot (yellow for disconnected, red for error)
- [x] Space icon context menu (admin tools, reconnect, folder management, remove server)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side read state | Medium | Unread tracking is client-side only (starts fresh each session); the server doesn't provide a "last read" marker per channel, so unreads reset on reconnect |
| Space folder color not configurable from UI | Low | `Config.get/set_space_folder_color()` exists but the folder dialog only sets the name; color defaults to `Color(0.212, 0.224, 0.247)` |
| Space folder drag-to-reorder | Low | Spaces can't be dragged between folders or reordered within folders; assignment is only via context menu |
