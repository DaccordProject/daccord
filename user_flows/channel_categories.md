# Channel Categories

Priority: 13
Depends on: Space & Channel Navigation
Status: Complete

Collapsible category groups that organize channels within a space's sidebar, with create/edit/delete/reorder operations and drag-and-drop support.

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/category_item.gd` | Category header: collapse toggle with persistence, count label, context menu, create/edit/delete dialogs, D&D reordering with `set_drag_forwarding` for Header drops |
| `scenes/sidebar/channels/category_item.tscn` | Scene: Header button (44px) with Chevron + CategoryName, ChannelContainer VBox |
| `scenes/sidebar/channels/channel_list.gd` | Groups channels by category, sorts by position/name, renders CategoryItemScene and ChannelItemScene, restores collapse state |
| `scenes/sidebar/channels/channel_list.tscn` | Channel list panel with ScrollContainer, EmptyState, banner |
| `scenes/sidebar/channels/channel_item.gd` | Individual channel display with D&D reordering within same parent |
| `scenes/sidebar/channels/uncategorized_drop_target.gd` | Drop target that clears `parent_id` when uncategorized list is empty |
| `scenes/sidebar/channels/uncategorized_drop_target.tscn` | Scene: 8px-tall control used as the uncategorized drop target |
| `scenes/admin/create_channel_dialog.gd` | Create channel/category dialog with parent_id handling and Category type support in both contexts |
| `scripts/autoload/config.gd` | `set_category_collapsed()` (line 74), `is_category_collapsed()` (line 79) — persists collapse state per space/category |
| `scripts/autoload/client_models.gd` | `ChannelType.CATEGORY` enum (line 7), `channel_to_dict()` conversion (line 135) |
| `scripts/autoload/client.gd` | `create_channel()` (line 634), `update_channel()` (line 641), `delete_channel()` (line 648), `reorder_channels()` (line 772), `has_permission()` (line 587) |
| `scripts/autoload/client_gateway.gd` | `on_channel_create()` (line 170), `on_channel_update()` (line 191), `on_channel_delete()` (line 212) — update cache and emit `channels_updated` |
| `scripts/autoload/app_state.gd` | `channels_updated` signal (line 16) |
| `scenes/admin/channel_management_dialog.gd` | Admin UI for channel/category CRUD with type indicator "C" for categories |
