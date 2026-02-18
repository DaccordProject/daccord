# Guild & Channel Navigation

*Last touched: 2026-02-18 20:21*

## Overview

After connecting to a server, users navigate through guilds (spaces) and channels. The guild bar on the far left shows guild icons, guild folders, and a DM button. Selecting a guild loads its channel list in the channel panel. Channels are grouped into collapsible categories. Selecting a channel opens it in the message view and creates a tab in the tab bar.

## User Steps

1. User sees guild icons in the guild bar (left strip)
2. Click a guild icon -> channel list loads for that guild
3. Channels are grouped under category headers (collapsible)
4. Click a channel -> messages load, tab appears in tab bar
5. Click another channel -> new tab opens (or switches to existing tab)
6. Click tab "x" to close a tab (minimum 1 tab required)
7. Tab bar hidden when only 1 tab exists
8. Guild folders group multiple guilds (collapsible in sidebar)

## Signal Flow

```
User clicks guild icon
    -> guild_bar._on_guild_pressed(guild_id)
    -> guild_bar.guild_selected signal emitted
    -> sidebar._on_guild_selected(guild_id)
        -> channel_list.visible = true, dm_list.visible = false
        -> channel_list.load_guild(guild_id)
            -> Client.fetch_channels(guild_id)
            -> Clears existing channel nodes
            -> Groups channels by category (parent_id)
            -> Instantiates CategoryItemScene / ChannelItemScene
        -> AppState.select_guild(guild_id)
            -> Sets current_guild_id, is_dm_mode = false
            -> AppState.guild_selected emitted

User clicks channel
    -> channel_item.channel_pressed signal(channel_id)
    -> channel_list._on_channel_pressed(channel_id)
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
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_bar.gd` | Guild bar container, emits guild_selected/dm_selected |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Individual guild icon with selection pill, mentions badge, `set_active()` |
| `scenes/sidebar/guild_bar/guild_folder.gd` | Collapsible group of guild icons |
| `scenes/sidebar/channels/channel_list.gd` | Channel list, groups by category, emits channel_selected |
| `scenes/sidebar/channels/channel_item.gd` | Individual channel with type icon, unread dot, `set_active()` |
| `scenes/sidebar/channels/category_item.gd` | Collapsible category header with chevron |
| `scenes/sidebar/channels/banner.gd` | Guild banner (color + name) above channel list |
| `scenes/sidebar/sidebar.gd` | Orchestrates guild bar, channel list, DM list |
| `scenes/main/main_window.gd` | Tab management (lines 39-98) |
| `scripts/autoload/app_state.gd` | guild_selected, channel_selected signals |
| `scripts/autoload/client.gd` | fetch_channels(), get_channels_for_guild() |

## Implementation Details

### Guild Bar (guild_bar.gd)

- Contains guild icons in a VBoxContainer with scroll
- DM button at top, Add Server "+" button at bottom
- Selection tracking: `_active_guild_id` and `_guild_nodes` dictionary
- `_guild_nodes` stores both `guild_icon` and `guild_folder` nodes
- Uses `has_method("set_active")` check since both types are stored in same dict
- Guild selection pill: white indicator on left side of active guild icon
- Mention badge: small red circle with count on guild icon

### Guild Icon (guild_icon.gd)

- Colored square (ColorRect) with first letter of guild name as Label
- `setup(data)`: Sets icon_color, guild name initial, tooltip
- `set_active(bool)`: Shows/hides selection pill
- Hover effects via mouse_entered/exited signals

### Guild Folder (guild_folder.gd)

- Collapsible container for multiple guild icons
- Header button toggles collapse (chevron rotates)
- Does not implement `set_active()`; `guild_bar` checks `has_method("set_active")` before calling, so folders are skipped gracefully

### Channel List (channel_list.gd)

- `load_guild(guild_id)` (line 20): Fetches and renders channels
- Groups channels: first pass finds categories (type == CATEGORY), second pass assigns children via parent_id
- Uncategorized channels rendered first, then categories with children
- Tracks `channel_item_nodes` dict and `active_channel_id` for selection state
- Listens to `AppState.channels_updated` to reload on gateway events
- **Empty state**: When a guild has 0 non-category channels, shows a centered `EmptyState` VBoxContainer with title, description, and a prominent "Create Channel" button (for users with `MANAGE_CHANNELS` permission). Non-admins see "This space doesn't have any channels yet. Check back soon!" with no button. The `+ Create Channel` text link at the bottom only appears when channels already exist.

### Channel Item (channel_item.gd)

- Type icon: TEXT_ICON, VOICE_ICON, ANNOUNCEMENT_ICON, FORUM_ICON (preloaded SVGs)
- NSFW indicator: tints type icon red (Color(0.9, 0.2, 0.2)) when `data.nsfw == true`
- Voice user count: adds Label with participant count for voice channels (if voice_users > 0)
- Unread dot: ColorRect visible when `data.unread == true` (currently always false)
- `set_active(bool)`: Applies/removes dark background StyleBoxFlat + white text

### Category Item (category_item.gd)

- `setup(data, child_channels)`: Note the unique signature (data + children array)
- Category name displayed in UPPERCASE, font size 11, gray color
- Chevron toggles between CHEVRON_DOWN and CHEVRON_RIGHT
- `_toggle_collapsed()`: Toggles `channel_container.visible`
- `get_channel_items()`: Returns child channel items for node tracking

### Tab Management (main_window.gd)

- `tabs: Array[Dictionary]` with `{name, channel_id}` entries
- Initial tab: "general" with channel_id "chan_3" (hardcoded in _ready(), line 33)
- `_on_channel_selected()` (line 39): Searches for existing tab by channel_id, switches or creates
- `_add_tab()` (line 75): Appends to array, adds to TabBar, sets current
- `_on_tab_close()` (line 86): Prevents closing last tab, removes from array and TabBar
- `_update_tab_visibility()` (line 96): Hides TabBar when only 1 tab
- Tab close policy: `tab_close_display_policy = 1` (show on hover)
- Channel name lookup: searches Client.channels then Client.dm_channels
- Topic bar: Shows channel topic if present, hidden if empty

### Banner (banner.gd)

- Displays guild name (white, 16px) on darkened icon_color background
- `setup(guild_data)`: Sets name and color from guild dict, shows/hides dropdown icon based on admin permissions
- **Clickable admin dropdown**: The entire banner is clickable (left-click) for users with any admin permission. Opens a `PopupMenu` with permission-gated items: Space Settings (`manage_space`), Channels (`manage_channels`), Roles (`manage_roles`), Bans (`ban_members`), Invites (`create_invites`), Emojis (`manage_emojis`). A small `▼` icon in the bottom-right corner indicates the dropdown is available. Cursor changes to pointing hand on hover.
- This provides a discoverable alternative to the guild icon right-click context menu for accessing admin tools.

## Implementation Status

- [x] Guild bar with icons for each connected guild
- [x] Guild selection with active pill indicator
- [x] Guild folders (collapsible groups)
- [x] Channel list grouped by categories
- [x] Category headers (collapsible with chevron)
- [x] Channel type icons (text, voice, announcement, forum)
- [x] Channel selection with active highlight
- [x] Tab bar for open channels
- [x] Tab creation on channel select
- [x] Tab close with minimum-1-tab safety
- [x] Guild banner with name and color
- [x] Banner dropdown menu for admin settings (clickable, permission-gated)
- [x] Channel list empty state (admin CTA vs non-admin message)
- [x] NSFW channel indicator (red-tinted icon)
- [x] Voice channel user count display (if voice_users > 0)
- [x] Mention badge on guild icons

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Unread indicators always false | High | `ClientModels.channel_to_dict()` hardcodes `unread: false` (line 142); `space_to_guild_dict()` hardcodes `unread: false, mentions: 0` (lines 120-121) |
| No actual guild icons (images) | Medium | Guild icons are colored squares with initials; `space_to_guild_dict()` returns `icon_color` but no `icon` URL, even though AccordSpace has an `icon` field |
| Guild folder assignment not from server | Medium | `space_to_guild_dict()` hardcodes `folder: ""` (line 119); folders exist in UI but guilds are never assigned to them from server data |
| Default tab hardcoded | Low | `main_window.gd:33` creates initial tab "general" with "chan_3" before server data loads |
| No channel reordering | Low | Channels rendered in server-returned order; no drag-to-reorder |
| Voice channel voice_users never populated | Medium | `channel_item.gd:43` reads `voice_users` from data dict but `channel_to_dict()` never sets it |
