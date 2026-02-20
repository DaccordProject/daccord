# Guild Folders

Last touched: 2026-02-20

## Overview

Guild folders let users organize their servers into collapsible groups in the guild bar sidebar. Folder assignment is purely client-side — the server has no concept of folders. Users assign guilds to folders via the right-click context menu on a guild icon, and the assignment is persisted in the local encrypted config file. Folders display a mini-grid preview (using actual guild avatars) when collapsed and expand to show the full guild icons when clicked. Guilds and folders can be reordered via drag-and-drop in the guild bar.

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
11. Drag a guild icon or folder up/down in the guild bar to reorder; a blue line indicator shows the drop position
12. Drag a standalone guild icon onto a folder to add it to the folder

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
                        -> reads Config.get_guild_order()
                        -> places items in saved order
                        -> appends new items at end
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

User drags guild icon/folder to new position
    -> _guild_get_drag_data() / _folder_get_drag_data()
        -> returns {type: "guild_bar_item", item_type: "guild"/"folder", ...}
    -> _guild_can_drop_data() / _folder_can_drop_data()
        -> validates sibling, shows blue line indicator
    -> _guild_drop_data() / _folder_drop_data()
        -> container.move_child(source, target_idx)
        -> _save_guild_bar_order()
            -> Config.set_guild_order(order)

User drags standalone guild onto folder center
    -> _folder_can_drop_data() detects center zone
    -> _folder_drop_data()
        -> Config.set_guild_folder(gid, folder_name)
        -> Client.update_guild_folder(gid, folder_name)
        -> removes standalone entry from saved order
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_folder.gd` | Collapsible folder container with mini-grid avatar preview, expand/collapse animation, drag-drop reordering |
| `scenes/sidebar/guild_bar/guild_folder.tscn` | Scene: VBoxContainer with FolderButton (48x48), MiniGrid (2-col GridContainer), GuildList (hidden by default) |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Order-aware `_populate_guilds()` using `Config.get_guild_order()`, creates folder nodes via `_add_guild_folder()` |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Context menu with "Move to Folder" / "Remove from Folder" items, folder dialog UI, drag-drop reordering |
| `scripts/autoload/config.gd` | Folder persistence: `get/set_guild_folder()`, `get/set_guild_folder_color()`, `get_all_folder_names()`, `get/set_guild_order()` |
| `scripts/autoload/client.gd` | `update_guild_folder()` updates cache and emits `guilds_updated`; `connect_server()` applies folder from Config on load |
| `scripts/autoload/client_models.gd` | `space_to_guild_dict()` initializes `folder` key to `""` |
| `scripts/autoload/client_gateway.gd` | Preserves `folder` value when gateway events rebuild guild cache entries |
| `tests/unit/test_client.gd` | Unit tests for `update_guild_folder()` |

## Implementation Details

### Folder Assignment (guild_icon.gd)

- Context menu built in `_show_context_menu()`: adds "Move to Folder" when guild has no folder, or "Remove from Folder" when it does
- Current folder checked via `Config.get_guild_folder(guild_id)`
- "Remove from Folder" inserts a standalone order entry after the folder, then calls `Config.set_guild_folder(guild_id, "")` and `Client.update_guild_folder(guild_id, "")`
- "Move to Folder" removes the standalone order entry, then calls `Config.set_guild_folder()` and `Client.update_guild_folder()`

### Folder Dialog (guild_icon.gd)

- `_show_folder_dialog()` creates a `ConfirmationDialog` programmatically
- Lists existing folder names from `Config.get_all_folder_names()` as flat `Button` widgets that auto-fill the text field on click
- Text field for entering a new folder name
- On confirm: strips whitespace, removes standalone order entry, calls `Config.set_guild_folder()` and `Client.update_guild_folder()`
- Dialog `queue_free()`d on both confirm and cancel

### Folder Rendering (guild_bar.gd)

- `_populate_guilds()`: Groups guilds by folder, reads `Config.get_guild_order()`, places items in saved sequence, appends unsaved items at end
- Standalone guilds (empty folder) rendered via `_add_guild_icon()`
- Grouped guilds rendered via `_add_guild_folder()` on first encounter of each folder name
- `_add_guild_folder()`: Instantiates `GuildFolderScene`, reads folder color, calls `folder.setup()`
- All guild icons within a folder are registered in `guild_icon_nodes` pointing to the folder node, enabling `set_active()` lookups

### Folder Component (guild_folder.gd)

- Extends `VBoxContainer` with a `FolderRow` (HBoxContainer: Pill + ButtonContainer with FolderButton and MentionBadge) and hidden `GuildList`
- Scene structure mirrors `guild_icon.tscn` layout: PillContainer/Pill on the left, ButtonContainer with FolderButton and BadgeAnchor/MentionBadge on the right
- `setup(p_name, guilds, folder_color)`: Sets tooltip, applies darkened folder color, creates mini-grid preview (up to 4 avatar instances from `avatar.tscn`), creates guild icons for expanded view, aggregates notifications
- Mini-grid uses `AvatarScene` instances (14x14) with `set_avatar_color()` and `set_avatar_url()` — shares the static LRU image cache with full-size avatars
- `set_active(bool)`: Shows/hides the active pill. When deactivated, restores UNREAD pill if any contained guild has unread messages. Also deactivates all child guild icons.
- `set_active_guild(guild_id)`: Activates the folder pill and the matching child guild icon, deactivates all others. Called by `guild_bar` when a guild inside a folder is selected.
- `_update_notifications(guilds)`: Aggregates `unread` and `mentions` from all contained guilds. Shows MentionBadge with total count, shows UNREAD pill if any guild is unread (unless folder is active).
- `_toggle_expanded()`: Toggles `is_expanded`, swaps mini-grid/guild-list visibility, animates alpha with a 0.15s cubic tween
- Right-click context menu: "Rename Folder", "Change Color", "Delete Folder"
  - Rename: dialog with LineEdit, updates all guilds' folder config, migrates color via `Config.rename_folder_color()`, updates saved order
  - Change Color: dialog with ColorPicker, persists via `Config.set_folder_color()`, triggers guild bar rebuild
  - Delete: replaces folder entry in saved order with standalone guild entries, removes all guilds from folder, cleans up folder color
- Emits `guild_pressed(guild_id)` when any contained guild icon is clicked
- Emits `folder_changed()` after rename/delete operations

### Drag-and-Drop Reordering

- Follows the `category_item.gd` / `channel_item.gd` pattern: blue line indicator, `_get_drag_data`/`_can_drop_data`/`_drop_data`, `NOTIFICATION_DRAG_END` cleanup
- **guild_icon.gd**: Uses `set_drag_forwarding()` on `icon_button` to forward drag events. Only top-level icons (in `GuildList` under `VBox`) are draggable — icons inside expanded folders are not.
- **guild_folder.gd**: Uses `set_drag_forwarding()` on `folder_button`. Supports both sibling reorder and drag-to-folder (standalone guild dropped onto center zone adds to folder).
- Drag data type: `{"type": "guild_bar_item", "item_type": "guild"/"folder", ...}` — shared between icons and folders
- Drop indicator: blue line (2px, `Color(0.34, 0.52, 0.89)`) drawn above or below via `_draw()`
- On drop: `container.move_child(source, target_idx)` followed by `_save_guild_bar_order()` which iterates children and calls `Config.set_guild_order()`
- Order array format: `[{"type": "guild", "id": "..."}, {"type": "folder", "name": "..."}, ...]`

### Persistence (config.gd)

- `get_guild_folder(guild_id)`: Returns folder name from `[folders]` config section, defaults to `""`
- `set_guild_folder(guild_id, folder_name)`: Sets folder name; passing empty string deletes the key (sets to `null`)
- `get_guild_folder_color(guild_id)`: Returns color from `[folder_colors]` section, defaults to `Color(0.212, 0.224, 0.247)`
- `set_guild_folder_color(guild_id, color)`: Persists color per guild
- `get_all_folder_names()`: Iterates `[folders]` section, returns deduplicated array of non-empty folder names
- `get_guild_order()`: Returns saved order array from `[guild_order]` section, defaults to `[]`
- `set_guild_order(order)`: Persists order array to `[guild_order]` section

### Cache Integration (client.gd, client_gateway.gd)

- `Client.connect_server()`: After converting space to guild dict, applies `Config.get_guild_folder(d["id"])`
- `Client.update_guild_folder(gid, folder_name)`: Updates `_guild_cache[gid]["folder"]` and emits `AppState.guilds_updated`
- `ClientModels.space_to_guild_dict()` initializes `folder` to `""`
- Gateway `on_space_create()`: Applies `Config.get_guild_folder()` when adding new guild to cache
- Gateway `on_space_update()`: Preserves existing `folder` value from old cache entry

### Tests (test_client.gd)

- `test_update_guild_folder()`: Verifies cache update from `""` to `"MyFolder"`
- `test_update_guild_folder_missing_guild_noop()`: Verifies no crash when guild ID doesn't exist in cache

## Implementation Status

- [x] Folder assignment via guild icon context menu ("Move to Folder" / "Remove from Folder")
- [x] Folder dialog with existing folder quick-select and new folder text input
- [x] Folder persistence in encrypted config file (`[folders]` section)
- [x] Folder color persistence API (`get/set_guild_folder_color` in Config)
- [x] Collapsible folder UI with mini-grid preview (guild avatars)
- [x] Animated expand/collapse (alpha tween, 0.15s cubic)
- [x] Guild selection from within expanded folders
- [x] Folder state preserved across gateway space updates
- [x] Guild bar rebuilds on `guilds_updated` signal
- [x] Unit tests for `update_guild_folder()`
- [x] `set_active()` on folder nodes (active pill for selected guild inside folder)
- [x] Notification aggregation (unread/mention badges) on folder level
- [x] Folder color chooser in UI (right-click folder -> Change Color)
- [x] Folder rename/delete via context menu (right-click folder -> Rename/Delete)
- [x] Active state restored after guild bar rebuild
- [x] Guild/folder drag-and-drop reordering with order persistence
- [x] Drag-to-folder (drop standalone guild onto folder to add it)
- [x] Order maintenance on rename/delete/move-to-folder/remove-from-folder

## Gaps / TODO

None.
