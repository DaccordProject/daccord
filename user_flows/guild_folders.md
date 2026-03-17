# Space Folders

Priority: 50
Depends on: Space & Channel Navigation
Status: Complete

Client-side space grouping with folder assignment via context menu, collapsible mini-grid preview, folder persistence in Config, drag-and-drop reordering, and notification aggregation.

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
