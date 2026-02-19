# Guild Folders

Last touched: 2026-02-19

## Overview

Guild folders let users organize their servers into collapsible groups in the guild bar sidebar. Folder assignment is purely client-side — the server has no concept of folders. Users assign guilds to folders via the right-click context menu on a guild icon, and the assignment is persisted in the local encrypted config file. Folders display a mini-grid preview when collapsed and expand to show the full guild icons when clicked.

## User Steps

1. User right-clicks a guild icon in the guild bar
2. Context menu shows "Move to Folder" (or "Remove from Folder" if already in one)
3. Clicking "Move to Folder" opens a dialog:
   a. Lists existing folder names as quick-select buttons
   b. Provides a text field for typing a new folder name
   c. Click "Move" to confirm
4. The guild icon moves into the folder group in the guild bar
5. Clicking the folder button toggles between collapsed (mini-grid) and expanded (full icon list) views
6. When a guild inside a folder is selected, the folder shows an active pill indicator
7. Collapsed folders aggregate unread dots and mention badges from contained guilds
8. Right-clicking a folder button shows context menu: "Rename Folder", "Change Color", "Delete Folder"
9. To remove a guild from a folder, right-click the guild icon and choose "Remove from Folder"
10. When the last guild is removed from a folder, the folder disappears

## Signal Flow

```
User right-clicks guild icon -> "Move to Folder"
    -> guild_icon._show_folder_dialog()
    -> User enters folder name, clicks "Move"
        -> Config.set_guild_folder(guild_id, folder_name)    # persist to disk
        -> Client.update_guild_folder(guild_id, folder_name) # update cache
            -> _guild_cache[gid]["folder"] = folder_name
            -> AppState.guilds_updated.emit()
                -> guild_bar._on_guilds_updated()
                    -> clears guild_list children
                    -> _populate_guilds()
                        -> groups Client.guilds by "folder" field
                        -> standalone guilds -> _add_guild_icon()
                        -> grouped guilds  -> _add_guild_folder()

User clicks folder button (toggle expand/collapse)
    -> guild_folder._toggle_expanded()
    -> mini_grid.visible toggled
    -> guild_list alpha tweened in/out (0.15s cubic)

User clicks guild icon inside expanded folder
    -> guild_folder.guild_pressed signal
    -> guild_bar._on_guild_pressed(guild_id)
    -> (normal guild selection flow)
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_folder.gd` | Collapsible folder container with mini-grid preview and expand/collapse animation |
| `scenes/sidebar/guild_bar/guild_folder.tscn` | Scene: VBoxContainer with FolderButton (48x48), MiniGrid (2-col GridContainer), GuildList (hidden by default) |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Groups guilds by folder field in `_populate_guilds()`, creates folder nodes via `_add_guild_folder()` |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Context menu with "Move to Folder" / "Remove from Folder" items, folder dialog UI |
| `scripts/autoload/config.gd` | Folder persistence: `get/set_guild_folder()`, `get/set_guild_folder_color()`, `get_all_folder_names()` |
| `scripts/autoload/client.gd` | `update_guild_folder()` updates cache and emits `guilds_updated`; `connect_server()` applies folder from Config on load |
| `scripts/autoload/client_models.gd` | `space_to_guild_dict()` initializes `folder` key to `""` (line 178) |
| `scripts/autoload/client_gateway.gd` | Preserves `folder` value when gateway events rebuild guild cache entries (lines 394, 405) |
| `tests/unit/test_client.gd` | Unit tests for `update_guild_folder()` (lines 385-394) |

## Implementation Details

### Folder Assignment (guild_icon.gd)

- Context menu built in `_show_context_menu()` (line 111): adds "Move to Folder" when guild has no folder, or "Remove from Folder" when it does (lines 144-151)
- Current folder checked via `Config.get_guild_folder(guild_id)` (line 145)
- "Remove from Folder" immediately calls `Config.set_guild_folder(guild_id, "")` and `Client.update_guild_folder(guild_id, "")` (lines 197-198)
- "Move to Folder" calls `_show_folder_dialog()` (line 212)

### Folder Dialog (guild_icon.gd)

- `_show_folder_dialog()` (lines 212-258) creates a `ConfirmationDialog` programmatically
- Lists existing folder names from `Config.get_all_folder_names()` as flat `Button` widgets that auto-fill the text field on click (lines 224-236)
- Text field for entering a new folder name (line 220-222)
- On confirm: strips whitespace, calls `Config.set_guild_folder()` and `Client.update_guild_folder()` (lines 247-252)
- Dialog `queue_free()`d on both confirm and cancel

### Folder Rendering (guild_bar.gd)

- `_populate_guilds()` (line 23): Iterates `Client.guilds`, groups by the `folder` dictionary key
- Standalone guilds (empty folder) rendered via `_add_guild_icon()` (line 42)
- Grouped guilds rendered via `_add_guild_folder()` (line 45) on first encounter of each folder name
- `_add_guild_folder()` (line 54): Instantiates `GuildFolderScene`, reads `folder_color` from the first guild in the group (line 57), calls `folder.setup()` (line 58)
- All guild icons within a folder are registered in `guild_icon_nodes` pointing to the folder node (line 61), enabling `set_active()` lookups

### Folder Component (guild_folder.gd)

- Extends `VBoxContainer` with a `FolderRow` (HBoxContainer: Pill + ButtonContainer with FolderButton and MentionBadge) and hidden `GuildList`
- Scene structure mirrors `guild_icon.tscn` layout: PillContainer/Pill on the left, ButtonContainer with FolderButton and BadgeAnchor/MentionBadge on the right
- `setup(p_name, guilds, folder_color)`: Sets tooltip, applies darkened folder color, creates mini-grid preview (up to 4 swatches), creates guild icons for expanded view, aggregates notifications
- `set_active(bool)`: Shows/hides the active pill. When deactivated, restores UNREAD pill if any contained guild has unread messages. Also deactivates all child guild icons.
- `set_active_guild(guild_id)`: Activates the folder pill and the matching child guild icon, deactivates all others. Called by `guild_bar` when a guild inside a folder is selected.
- `_update_notifications(guilds)`: Aggregates `unread` and `mentions` from all contained guilds. Shows MentionBadge with total count, shows UNREAD pill if any guild is unread (unless folder is active).
- `_toggle_expanded()`: Toggles `is_expanded`, swaps mini-grid/guild-list visibility, animates alpha with a 0.15s cubic tween
- Right-click context menu: "Rename Folder", "Change Color", "Delete Folder"
  - Rename: dialog with LineEdit, updates all guilds' folder config and migrates color via `Config.rename_folder_color()`
  - Change Color: dialog with ColorPicker, persists via `Config.set_folder_color()`, triggers guild bar rebuild
  - Delete: removes all guilds from folder (become standalone), cleans up folder color via `Config.delete_folder_color()`
- Emits `guild_pressed(guild_id)` when any contained guild icon is clicked
- Emits `folder_changed()` after rename/delete operations

### Persistence (config.gd)

- `get_guild_folder(guild_id)` (line 174): Returns folder name from `[folders]` config section, defaults to `""`
- `set_guild_folder(guild_id, folder_name)` (line 177): Sets folder name; passing empty string deletes the key (sets to `null`)
- `get_guild_folder_color(guild_id)` (line 184): Returns color from `[folder_colors]` section, defaults to `Color(0.212, 0.224, 0.247)`
- `set_guild_folder_color(guild_id, color)` (line 187): Persists color per guild
- `get_all_folder_names()` (line 191): Iterates `[folders]` section, returns deduplicated array of non-empty folder names

### Cache Integration (client.gd, client_gateway.gd)

- `Client.connect_server()`: After converting space to guild dict, applies `Config.get_guild_folder(d["id"])` (client.gd lines 261, 270)
- `Client.update_guild_folder(gid, folder_name)` (client.gd line 536): Updates `_guild_cache[gid]["folder"]` and emits `AppState.guilds_updated`
- `ClientModels.space_to_guild_dict()` initializes `folder` to `""` (client_models.gd line 178)
- Gateway `on_space_create()`: Applies `Config.get_guild_folder()` when adding new guild to cache (client_gateway.gd line 394)
- Gateway `on_space_update()`: Preserves existing `folder` value from old cache entry (client_gateway.gd line 405)

### Tests (test_client.gd)

- `test_update_guild_folder()` (line 385): Verifies cache update from `""` to `"MyFolder"`
- `test_update_guild_folder_missing_guild_noop()` (line 391): Verifies no crash when guild ID doesn't exist in cache

## Implementation Status

- [x] Folder assignment via guild icon context menu ("Move to Folder" / "Remove from Folder")
- [x] Folder dialog with existing folder quick-select and new folder text input
- [x] Folder persistence in encrypted config file (`[folders]` section)
- [x] Folder color persistence API (`get/set_guild_folder_color` in Config)
- [x] Collapsible folder UI with mini-grid preview (up to 4 color swatches)
- [x] Animated expand/collapse (alpha tween, 0.15s cubic)
- [x] Guild selection from within expanded folders
- [x] Folder state preserved across gateway space updates
- [x] Guild bar rebuilds on `guilds_updated` signal
- [x] Unit tests for `update_guild_folder()`
- [x] `set_active()` on folder nodes (active pill for selected guild inside folder)
- [x] Notification aggregation (unread/mention badges) on folder level
- [x] Folder color chooser in UI (right-click folder → Change Color)
- [x] Folder rename/delete via context menu (right-click folder → Rename/Delete)
- [x] Active state restored after guild bar rebuild
- [ ] Folder drag-and-drop reordering

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No drag-and-drop reordering | Low | Guilds can't be dragged between folders or reordered within folders; assignment is only via context menu |
| Mini-grid uses color swatches not icons | Low | Collapsed folder preview shows `icon_color` squares, not actual guild icons/avatars |
