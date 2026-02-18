# Channel Categories

*Last touched: 2026-02-18 20:21*

## Overview
Channel categories are collapsible groups that organize channels within a guild's sidebar. Categories are a special channel type (`ChannelType.CATEGORY`) that act as containers — other channels reference a category via their `parent_id` field. Users with `MANAGE_CHANNELS` permission can create, rename, delete, and reorder categories, as well as create channels directly within them. Collapse state persists across sessions via `Config`.

## User Steps

### Viewing categories
1. User selects a guild from the guild bar.
2. The channel list loads all channels for the guild.
3. Channels are sorted by `position` then `name`, grouped into uncategorized (shown first) and categories (sorted by `position` then `name`). Children within each category are also sorted by `position` then `name`.
4. User clicks a category header to collapse/expand its children. A channel count badge appears when collapsed.

### Creating a category
1. User clicks "+ Create Channel" at the bottom of the channel list, or right-clicks a category header → "Create Channel".
2. In the Create Channel dialog, user selects "Category" from the channel type dropdown (available in both the channel list dialog and the category-scoped dialog).
3. User enters a name and clicks "Create". When created from a category's context menu, the new category is created as top-level (no nesting).
4. The server creates the category and emits a `channel_create` gateway event.
5. The channel list rebuilds with the new category header.

### Creating a channel inside a category
1. User hovers over a category header — a "+" button appears (if they have `MANAGE_CHANNELS` permission).
2. User clicks the "+" button, or right-clicks the header and selects "Create Channel".
3. The Create Channel dialog opens with Text/Voice/Announcement/Forum/Category type options. The `parent_id` is pre-set to the category (skipped if Category type is selected).
4. User enters a name, selects a type, and clicks "Create".

### Editing a category
1. User right-clicks a category header → "Edit Category".
2. The Edit Category dialog opens with the current name pre-filled.
3. User changes the name and clicks "Save".

### Deleting a category
1. User right-clicks a category header → "Delete Category".
2. A confirmation dialog appears. If the category has children, the message warns: "It contains N channel(s) that will become uncategorized." If empty, the standard "This cannot be undone" message is shown.
3. User clicks "Delete".
4. The server deletes the category channel. Child channels are not deleted (they become uncategorized).

### Collapsing/expanding categories
1. User clicks a category header to toggle collapse.
2. When collapsed: child channels are hidden, chevron changes to right-pointing, channel count badge appears.
3. When expanded: child channels are visible, chevron points down, count badge hides.
4. Collapse state is persisted to `Config` and restored when the guild reloads or the app restarts.

### Reordering via drag-and-drop
1. User with `MANAGE_CHANNELS` permission clicks and drags a channel item or category header.
2. A label preview appears at the cursor ("# channel-name" for channels, "CATEGORY NAME" for categories).
3. A blue drop indicator line shows above or below valid drop targets.
4. Channels can be reordered within the same parent container (same category or both uncategorized). Categories can be reordered among sibling categories.
5. On drop, the node is moved immediately for visual feedback, then a position update is sent to the server via `Client.reorder_channels()`.
6. If the API call fails, the `channels_updated` signal triggers a full rebuild from server state, reverting the visual change.

## Signal Flow
```
Guild selected
  → channel_list.load_guild(guild_id)
    → Client.get_channels_for_guild(guild_id)
      → Returns all channels from _channel_cache (including categories)
    → First pass: collect categories (type == CATEGORY) into dictionary keyed by id
    → Second pass: assign child channels to categories via parent_id
    → Sort uncategorized by position/name, sort each category's children, sort categories
    → Render uncategorized channels as ChannelItemScene
    → Render categories as CategoryItemScene (with sorted children passed to setup())
    → restore_collapse_state() called on each category (reads from Config)

Category header clicked
  → category_item._toggle_collapsed()
    → is_collapsed toggled
    → channel_container.visible set to !is_collapsed
    → chevron texture swapped (DOWN ↔ RIGHT)
    → _count_label.visible set to is_collapsed
    → Config.set_category_collapsed(guild_id, cat_id, is_collapsed)

Category "+" button / context menu → "Create Channel"
  → category_item._on_create_channel()
    → CreateChannelDialogScene instantiated — parent_id pre-set to category id
      → Type dropdown includes Category option (line 44)
      → User fills name + type → Client.create_channel(guild_id, data)
        → If type is "category", parent_id is skipped (line 66)
        → REST: POST /spaces/{guild_id}/channels
          → Gateway: channel_create event
            → client_gateway.on_channel_create()
              → _channel_cache updated
              → AppState.channels_updated.emit(guild_id)
                → channel_list._on_channels_updated() → load_guild() rebuilds list

Category context menu → "Edit Category"
  → category_item._on_edit_category()
    → CategoryEditDialogScene instantiated — name input pre-filled
      → User edits name → Client.update_channel(category_id, data)
        → REST: PATCH /channels/{id}
          → Gateway: channel_update event
            → AppState.channels_updated.emit(guild_id)

Category context menu → "Delete Category"
  → category_item._on_delete_category()
    → Checks channel_container.get_child_count() (line 146)
    → ConfirmDialog shown with orphan warning if children > 0
      → User confirms → Client.delete_channel(category_id)
        → REST: DELETE /channels/{id}
          → Gateway: channel_delete event
            → AppState.channels_updated.emit(guild_id)

Channel/category drag-and-drop
  → channel_item._get_drag_data() / category_item._get_drag_data()
    → Permission check: Client.has_permission(guild_id, MANAGE_CHANNELS)
    → Returns {"type": "channel"/"category", ..., "source_node": self}
  → target._can_drop_data()
    → Validates same type, not self, same parent container
    → Sets _drop_above based on mouse Y vs midpoint
    → queue_redraw() for blue line indicator
  → target._drop_data()
    → container.move_child(source, target_idx) for immediate visual feedback
    → Builds position array from new child order
    → Client.reorder_channels(guild_id, positions)
      → REST: PATCH /spaces/{space_id}/channels with [{"id": ..., "position": N}, ...]
```

## Key Files
| File | Role |
|------|------|
| `scenes/sidebar/channels/category_item.gd` | Category header: collapse toggle with persistence, count label, context menu, create/edit/delete dialogs, D&D reordering |
| `scenes/sidebar/channels/category_item.tscn` | Scene: Header button (44px) with Chevron + CategoryName, ChannelContainer VBox |
| `scenes/sidebar/channels/channel_list.gd` | Groups channels by category, sorts by position/name, renders CategoryItemScene and ChannelItemScene, restores collapse state |
| `scenes/sidebar/channels/channel_list.tscn` | Channel list panel with ScrollContainer, EmptyState, banner |
| `scenes/sidebar/channels/channel_item.gd` | Individual channel display with D&D reordering within same parent |
| `scenes/admin/create_channel_dialog.gd` | Create channel/category dialog with parent_id handling and Category type support in both contexts |
| `scripts/autoload/config.gd` | `set_category_collapsed()` (line 74), `is_category_collapsed()` (line 79) — persists collapse state per guild/category |
| `scripts/autoload/client_models.gd` | `ChannelType.CATEGORY` enum (line 7), `channel_to_dict()` conversion (line 135) |
| `scripts/autoload/client.gd` | `create_channel()` (line 634), `update_channel()` (line 641), `delete_channel()` (line 648), `reorder_channels()` (line 772), `has_permission()` (line 587) |
| `scripts/autoload/client_gateway.gd` | `on_channel_create()` (line 170), `on_channel_update()` (line 191), `on_channel_delete()` (line 212) — update cache and emit `channels_updated` |
| `scripts/autoload/app_state.gd` | `channels_updated` signal (line 16) |
| `scenes/admin/channel_management_dialog.gd` | Admin UI for channel/category CRUD with type indicator "C" for categories |

## Implementation Details

### ChannelType enum and data model
`ClientModels` defines `ChannelType.CATEGORY` as value `4` (line 7). The `_channel_type_to_enum()` function (line 42) maps the server string `"category"` to this enum. The `channel_to_dict()` function (line 135) converts `AccordChannel` to a dictionary with `parent_id` extracted from the model:
```
{"id", "guild_id", "name", "type": 4, "parent_id": "<category_id>", "position": N, "unread": false, ...}
```

### Channel list grouping and sorting (`channel_list.gd`)
`load_guild()` (line 21) fetches channels via `Client.get_channels_for_guild()` and performs a two-pass grouping followed by sorting:

1. **First pass** (lines 68-70): Identifies categories by checking `type == ChannelType.CATEGORY`. Stores them in a `categories` dictionary keyed by channel ID, with `data` and empty `children` array.
2. **Second pass** (lines 72-79): Non-category channels are assigned to their parent category via `parent_id`, or added to the `uncategorized` array if `parent_id` is empty or doesn't match a known category.
3. **Sorting** (lines 81-103): All collections are sorted by `position` then `name`:
   - Uncategorized channels sorted in-place (line 88).
   - Each category's children sorted in-place (lines 91-92).
   - Categories converted to a sorted array (lines 95-103) for deterministic render order.
4. **Rendering** (lines 105-124): Uncategorized channels are instantiated as `ChannelItemScene` first, then each category is instantiated as `CategoryItemScene` with its sorted children. After `setup()`, `restore_collapse_state()` is called on each category (line 118). Channel items from inside categories are tracked in `channel_item_nodes` for selection management.

The channel list auto-selects the first non-category channel after loading (lines 137-148). An empty state is shown when there are zero non-category channels (lines 36-62), with a "Create Channel" button if the user has `MANAGE_CHANNELS` permission.

### Category item component (`category_item.gd`)
Each category is a `VBoxContainer` with a header `Button` and a `ChannelContainer` VBox for children.

**Setup** (line 42): Takes `(data: Dictionary, child_channels: Array)`. Sets the category name to uppercase (line 45), creates a channel count label (lines 47-54) that's initially hidden, instantiates `ChannelItemScene` for each child (lines 56-60), and conditionally adds a "+" button for creating channels (lines 62-75). The "+" button only appears if `Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS)` returns true.

**Channel count label** (lines 47-54): A 10px gray label showing the number of child channels. Created in `setup()` and added to `$Header/HBox` before the "+" button. Initially hidden; shown only when the category is collapsed.

**Collapse toggle** (line 77): `_toggle_collapsed()` flips `is_collapsed`, toggles `channel_container.visible`, swaps the chevron between `CHEVRON_DOWN` and `CHEVRON_RIGHT`, toggles `_count_label` visibility, and persists the state via `Config.set_category_collapsed()` (lines 83-85).

**Collapse persistence** (line 87): `restore_collapse_state()` reads saved state from `Config.is_category_collapsed()` and applies it — setting `is_collapsed`, hiding `channel_container`, swapping chevron, and showing the count label.

**Context menu** (lines 113-131): Right-click on the header shows a popup with "Create Channel", "Edit Category", and "Delete Category" — only if the user has `MANAGE_CHANNELS` permission (line 115).

**Create channel dialog** (line 133): Opens `CreateChannelDialogScene` with `parent_id` pre-set to the category's ID (line 136). The dialog now includes a "Category" type option (line 44 in `create_channel_dialog.gd`); selecting Category skips setting `parent_id` since categories are always top-level.

**Edit category dialog** (line 138): Opens `CategoryEditDialogScene` with the current name pre-filled. On submit, calls `Client.update_channel()` with the new name.

**Delete category** (line 143): Opens a `ConfirmDialog`. Checks `channel_container.get_child_count()` (line 146) — if > 0, the message warns about orphaned children becoming uncategorized (line 149). On confirm, calls `Client.delete_channel()` (line 159).

**Drag-and-drop** (lines 165-232): Categories support D&D reordering within `channel_vbox`. `_get_drag_data()` (line 167) is gated on `MANAGE_CHANNELS` and returns `{"type": "category", ...}` with an uppercase label preview. `_can_drop_data()` (line 177) validates same type and same parent. `_drop_data()` (line 194) moves the source node, builds a position array from all categories via `get_category_id()`, and calls `Client.reorder_channels()`. A blue line indicator is drawn via `_draw()` (line 225).

### Channel item drag-and-drop (`channel_item.gd`)
Channels support D&D reordering within the same parent container (lines 148-213). `_get_drag_data()` (line 150) is gated on `MANAGE_CHANNELS` and returns `{"type": "channel", ...}` with a "# name" label preview. `_can_drop_data()` (line 159) validates same type and same parent container (either `channel_container` within a category or `channel_vbox` for uncategorized). `_drop_data()` (line 176) moves the source node and builds a position array from sibling channels. A blue line indicator is drawn at the drop position via `_draw()` (line 206).

### Create channel dialog (`create_channel_dialog.gd`)
The dialog (`setup()`, line 20) always adds Text/Voice/Announcement/Forum types (lines 25-28). The "Category" type (item id `4`) is added in both contexts: when called from `channel_list` (line 32) and when called from a category's context menu (line 44). When `parent_id` is set and the selected type is "category", the `parent_id` is skipped in `_on_create()` (line 66) since categories are always top-level. The parent dropdown is shown only when called from `channel_list` (lines 33-41).

### Collapse state persistence (`config.gd`)
Two methods added (lines 74-81):
- `set_category_collapsed(guild_id, category_id, collapsed)`: Stores under ConfigFile section `[collapsed_GUILD_ID]` with category IDs as keys. Calls `save()` immediately.
- `is_category_collapsed(guild_id, category_id)`: Returns the stored bool, defaulting to `false` (expanded).

### Gateway event handling (`client_gateway.gd`)
All three channel events handle categories the same as regular channels:
- `on_channel_create()` (line 170): Adds to `_channel_cache`, emits `channels_updated`.
- `on_channel_update()` (line 191): Replaces entry in `_channel_cache`, emits `channels_updated`.
- `on_channel_delete()` (line 212): Erases from `_channel_cache` and `_channel_to_guild`, emits `channels_updated`.

On any of these events, `channel_list._on_channels_updated()` (line 163) calls `load_guild()` to fully rebuild the list. This natural rebuild also serves as the rollback mechanism for failed D&D reorder operations.

### Styling
- Category name: uppercase, 11px font size, gray `Color(0.58, 0.608, 0.643)` (lines 31-32).
- Chevron: 12x12 `TextureRect`, same gray modulate (line 30).
- Header: 44px minimum height, flat button (no background).
- "+" button: 16x16, hidden by default, shown on hover (lines 105-111), gray icon that turns white on hover (lines 72-73).
- Channel count label: 10px font size, gray, shown only when collapsed (lines 48-53).
- Channel container: VBox with 2px separation between child items.
- Drag preview: white text label ("# channel-name" or "CATEGORY NAME").
- Drop indicator: blue line `Color(0.34, 0.52, 0.89)`, 2px wide, drawn at top or bottom edge.

### Permission gating
Category CRUD and reorder operations are gated behind `AccordPermission.MANAGE_CHANNELS`:
- The "+" button on category headers only renders if the user has permission (line 63).
- The right-click context menu only appears if the user has permission (line 115).
- The "+ Create Channel" button at the bottom of the channel list checks permission (line 127).
- Drag-and-drop initiation is gated in `_get_drag_data()` (channel_item.gd line 151, category_item.gd line 168).

## Implementation Status
- [x] Category grouping — channels grouped by `parent_id` in two-pass algorithm
- [x] Sorting — uncategorized, category children, and categories sorted by `position` then `name`
- [x] Collapsible categories — toggle visibility with chevron animation
- [x] Channel count label — shown when collapsed, displays child count
- [x] Collapse state persistence — saved to `Config` per guild/category, restored on load
- [x] Create category — via channel list "Create Channel" dialog or category context menu
- [x] Create channel in category — via "+" button or context menu on category header
- [x] Category type in category-scoped dialog — Category type available in both create dialog contexts
- [x] Edit category name — via context menu → Edit Category dialog
- [x] Delete category with orphan warning — confirmation mentions child count if children exist
- [x] Drag-and-drop reordering — channels within same parent, categories among siblings
- [x] Permission gating — MANAGE_CHANNELS required for all CRUD and reorder operations
- [x] Real-time sync — gateway events trigger full channel list rebuild
- [x] Admin channel management — categories listed with "C" type indicator
- [x] Empty state — shown when no non-category channels exist

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No cross-category channel drag | Low | Channels can only be reordered within their current parent. Moving a channel to a different category requires the channel edit dialog to change `parent_id`. A future enhancement could allow dropping channels onto category headers to re-parent them. |
| No drag handle visual affordance | Low | There is no visual grip/handle icon indicating items are draggable. Users must discover drag-and-drop by attempting it. |
