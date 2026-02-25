# Space Folders

Last touched: 2026-02-20

## Overview

Space folders let users organize their servers into collapsible groups in the space bar sidebar. Folder assignment is purely client-side -- the server has no concept of folders. Users assign spaces to folders via the right-click context menu on a space icon, and the assignment is persisted in the local encrypted config file. Folders display a mini-grid preview (using actual space avatars) when collapsed and expand to show the full space icons when clicked. Spaces and folders can be reordered via drag-and-drop in the space bar.

## User Steps

1. User right-clicks a space icon in the space bar
2. Context menu shows "Move to Folder" (or "Remove from Folder" if already in one)
3. Clicking "Move to Folder" opens a dialog:
   a. Lists existing folder names as quick-select buttons
   b. Provides a text field for typing a new folder name
   c. Click "Move" to confirm
4. The space icon moves into the folder group in the space bar
5. Clicking the folder button toggles between collapsed (mini-grid) and expanded (full icon list) views
6. When a space inside a folder is selected, the folder shows an active pill indicator
7. Collapsed folders aggregate unread dots and mention badges from contained spaces
8. Right-clicking a folder button shows context menu: "Rename Folder", "Change Color", "Delete Folder"
9. To remove a space from a folder, right-click the space icon and choose "Remove from Folder"
10. When the last space is removed from a folder, the folder disappears
11. Drag a space icon or folder up/down in the space bar to reorder; a blue line indicator shows the drop position
12. Drag a standalone space icon onto a folder to add it to the folder

## Signal Flow

```
User right-clicks space icon -> "Move to Folder"
    -> guild_icon._show_folder_dialog()
    -> User enters folder name, clicks "Move"
        -> Config.set_space_folder(space_id, folder_name)    # persist to disk
        -> Client.update_space_folder(space_id, folder_name) # update cache
            -> _space_cache[gid]["folder"] = folder_name
            -> AppState.spaces_updated.emit()
                -> guild_bar._on_spaces_updated()
                    -> clears space_list children
                    -> _populate_spaces()
                        -> reads Config.get_space_order()
                        -> places items in saved order
                        -> appends new items at end
                        -> standalone spaces -> _add_space_icon()
                        -> grouped spaces  -> _add_space_folder()

User clicks folder button (toggle expand/collapse)
    -> guild_folder._toggle_expanded()
    -> mini_grid.visible toggled
    -> space_list alpha tweened in/out (0.15s cubic)

User clicks space icon inside expanded folder
    -> guild_folder.space_pressed signal
    -> guild_bar._on_space_pressed(space_id)
    -> (normal space selection flow)

User drags space icon/folder to new position
    -> _space_get_drag_data() / _folder_get_drag_data()
        -> returns {type: "guild_bar_item", item_type: "space"/"folder", ...}
    -> _space_can_drop_data() / _folder_can_drop_data()
        -> validates sibling, shows blue line indicator
    -> _space_drop_data() / _folder_drop_data()
        -> container.move_child(source, target_idx)
        -> _save_space_bar_order()
            -> Config.set_space_order(order)

User drags standalone space onto folder center
    -> _folder_can_drop_data() detects center zone
    -> _folder_drop_data()
        -> Config.set_space_folder(gid, folder_name)
        -> Client.update_space_folder(gid, folder_name)
        -> removes standalone entry from saved order
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_folder.gd` | Collapsible folder container with mini-grid avatar preview, expand/collapse animation, drag-drop reordering |
| `scenes/sidebar/guild_bar/guild_folder.tscn` | Scene: VBoxContainer with FolderButton (48x48), MiniGrid (2-col GridContainer), GuildList (hidden by default) |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Order-aware `_populate_spaces()` using `Config.get_space_order()`, creates folder nodes via `_add_space_folder()` |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Context menu with "Move to Folder" / "Remove from Folder" items, folder dialog UI, drag-drop reordering |
| `scripts/autoload/config.gd` | Folder persistence: `get/set_space_folder()`, `get/set_space_folder_color()`, `get_all_folder_names()`, `get/set_space_order()` |
| `scripts/autoload/client.gd` | `update_space_folder()` updates cache and emits `spaces_updated`; `connect_server()` applies folder from Config on load |
| `scripts/autoload/client_models.gd` | `space_to_dict()` initializes `folder` key to `""` |
| `scripts/autoload/client_gateway.gd` | Preserves `folder` value when gateway events rebuild space cache entries |
| `tests/unit/test_client.gd` | Unit tests for `update_space_folder()` |

## Implementation Details

### Folder Assignment (guild_icon.gd)

- Context menu built in `_show_context_menu()`: adds "Move to Folder" when space has no folder, or "Remove from Folder" when it does
- Current folder checked via `Config.get_space_folder(space_id)`
- "Remove from Folder" inserts a standalone order entry after the folder, then calls `Config.set_space_folder(space_id, "")` and `Client.update_space_folder(space_id, "")`
- "Move to Folder" removes the standalone order entry, then calls `Config.set_space_folder()` and `Client.update_space_folder()`

### Folder Dialog (guild_icon.gd)

- `_show_folder_dialog()` creates a `ConfirmationDialog` programmatically
- Lists existing folder names from `Config.get_all_folder_names()` as flat `Button` widgets that auto-fill the text field on click
- Text field for entering a new folder name
- On confirm: strips whitespace, removes standalone order entry, calls `Config.set_space_folder()` and `Client.update_space_folder()`
- Dialog `queue_free()`d on both confirm and cancel

### Folder Rendering (guild_bar.gd)

- `_populate_spaces()`: Groups spaces by folder, reads `Config.get_space_order()`, places items in saved sequence, appends unsaved items at end
- Standalone spaces (empty folder) rendered via `_add_space_icon()`
- Grouped spaces rendered via `_add_space_folder()` on first encounter of each folder name
- `_add_space_folder()`: Instantiates `GuildFolderScene`, reads folder color, calls `folder.setup()`
- All space icons within a folder are registered in `space_icon_nodes` pointing to the folder node, enabling `set_active()` lookups

### Folder Component (guild_folder.gd)

- Extends `VBoxContainer` with a `FolderRow` (HBoxContainer: Pill + ButtonContainer with FolderButton and MentionBadge) and hidden `SpaceList`
- Scene structure mirrors `guild_icon.tscn` layout: PillContainer/Pill on the left, ButtonContainer with FolderButton and BadgeAnchor/MentionBadge on the right
- `setup(p_name, spaces, folder_color)`: Sets tooltip, applies darkened folder color, creates mini-grid preview (up to 4 avatar instances from `avatar.tscn`), creates space icons for expanded view, aggregates notifications
- Mini-grid uses `AvatarScene` instances (14x14) with `set_avatar_color()` and `set_avatar_url()` — shares the static LRU image cache with full-size avatars
- `set_active(bool)`: Shows/hides the active pill. When deactivated, restores UNREAD pill if any contained space has unread messages. Also deactivates all child space icons.
- `set_active_space(space_id)`: Activates the folder pill and the matching child space icon, deactivates all others. Called by space_bar when a space inside a folder is selected.
- `_update_notifications(spaces)`: Aggregates `unread` and `mentions` from all contained spaces. Shows MentionBadge with total count, shows UNREAD pill if any space is unread (unless folder is active).
- `_toggle_expanded()`: Toggles `is_expanded`, swaps mini-grid/space-list visibility, animates alpha with a 0.15s cubic tween
- Right-click context menu: "Rename Folder", "Change Color", "Delete Folder"
  - Rename: dialog with LineEdit, updates all spaces' folder config, migrates color via `Config.rename_folder_color()`, updates saved order
  - Change Color: dialog with ColorPicker, persists via `Config.set_folder_color()`, triggers space bar rebuild
  - Delete: replaces folder entry in saved order with standalone space entries, removes all spaces from folder, cleans up folder color
- Emits `space_pressed(space_id)` when any contained space icon is clicked
- Emits `folder_changed()` after rename/delete operations

### Drag-and-Drop Reordering

- Follows the `category_item.gd` / `channel_item.gd` pattern: blue line indicator, `_get_drag_data`/`_can_drop_data`/`_drop_data`, `NOTIFICATION_DRAG_END` cleanup
- **guild_icon.gd**: Uses `set_drag_forwarding()` on `icon_button` to forward drag events. Only top-level icons (in `SpaceList` under `VBox`) are draggable -- icons inside expanded folders are not.
- **guild_folder.gd**: Uses `set_drag_forwarding()` on `folder_button`. Supports both sibling reorder and drag-to-folder (standalone space dropped onto center zone adds to folder).
- Drag data type: `{"type": "guild_bar_item", "item_type": "space"/"folder", ...}` -- shared between icons and folders
- Drop indicator: blue line (2px, `Color(0.34, 0.52, 0.89)`) drawn above or below via `_draw()`
- On drop: `container.move_child(source, target_idx)` followed by `_save_space_bar_order()` which iterates children and calls `Config.set_space_order()`
- Order array format: `[{"type": "space", "id": "..."}, {"type": "folder", "name": "..."}, ...]`

### Persistence (config.gd)

- `get_space_folder(space_id)`: Returns folder name from `[folders]` config section, defaults to `""`
- `set_space_folder(space_id, folder_name)`: Sets folder name; passing empty string deletes the key (sets to `null`)
- `get_space_folder_color(space_id)`: Returns color from `[folder_colors]` section, defaults to `Color(0.212, 0.224, 0.247)`
- `set_space_folder_color(space_id, color)`: Persists color per space
- `get_all_folder_names()`: Iterates `[folders]` section, returns deduplicated array of non-empty folder names
- `get_space_order()`: Returns saved order array from `[space_order]` section, defaults to `[]`
- `set_space_order(order)`: Persists order array to `[space_order]` section

### Cache Integration (client.gd, client_gateway.gd)

- `Client.connect_server()`: After converting space to space dict, applies `Config.get_space_folder(d["id"])`
- `Client.update_space_folder(gid, folder_name)`: Updates `_space_cache[gid]["folder"]` and emits `AppState.spaces_updated`
- `ClientModels.space_to_dict()` initializes `folder` to `""`
- Gateway `on_space_create()`: Applies `Config.get_space_folder()` when adding new space to cache
- Gateway `on_space_update()`: Preserves existing `folder` value from old cache entry

### Tests (test_client.gd)

- `test_update_space_folder()`: Verifies cache update from `""` to `"MyFolder"`
- `test_update_space_folder_missing_space_noop()`: Verifies no crash when space ID doesn't exist in cache

## Implementation Status

- [x] Folder assignment via space icon context menu ("Move to Folder" / "Remove from Folder")
- [x] Folder dialog with existing folder quick-select and new folder text input
- [x] Folder persistence in encrypted config file (`[folders]` section)
- [x] Folder color persistence API (`get/set_space_folder_color` in Config)
- [x] Collapsible folder UI with mini-grid preview (space avatars)
- [x] Animated expand/collapse (alpha tween, 0.15s cubic)
- [x] Space selection from within expanded folders
- [x] Folder state preserved across gateway space updates
- [x] Space bar rebuilds on `spaces_updated` signal
- [x] Unit tests for `update_space_folder()`
- [x] `set_active()` on folder nodes (active pill for selected space inside folder)
- [x] Notification aggregation (unread/mention badges) on folder level
- [x] Folder color chooser in UI (right-click folder -> Change Color)
- [x] Folder rename/delete via context menu (right-click folder -> Rename/Delete)
- [x] Active state restored after space bar rebuild
- [x] Space/folder drag-and-drop reordering with order persistence
- [x] Drag-to-folder (drop standalone space onto folder to add it)
- [x] Order maintenance on rename/delete/move-to-folder/remove-from-folder

## Gaps / TODO

None.
