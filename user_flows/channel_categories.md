# Channel Categories


## Overview
Channel categories are collapsible groups that organize channels within a space's sidebar. Categories are a special channel type (`ChannelType.CATEGORY`) that act as containers — other channels reference a category via their `parent_id` field. Users with `MANAGE_CHANNELS` permission can create, rename, delete, and reorder categories, as well as create channels directly within them. Collapse state persists across sessions via `Config`.

## User Steps

### Viewing categories
1. User selects a space from the space bar.
2. The channel list loads all channels for the space.
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
4. Collapse state is persisted to `Config` and restored when the space reloads or the app restarts.

### Reordering via drag-and-drop
1. User with `MANAGE_CHANNELS` permission clicks and drags a channel item or category header.
2. A label preview appears at the cursor ("# channel-name" for channels, "CATEGORY NAME" for categories).
3. A blue drop indicator line shows above or below valid drop targets.
4. Channels can be reordered within the same parent container (same category or both uncategorized). Channels can be moved between categories by dropping onto a different category's header or channels, or into the uncategorized root drop target when there are no uncategorized channels. Categories can be reordered among sibling categories.
5. On drop, the node is moved immediately for visual feedback, then a position update is sent to the server via `Client.reorder_channels()`.
6. If the API call fails, the `channels_updated` signal triggers a full rebuild from server state, reverting the visual change.

## Signal Flow
```
Space selected
  → channel_list.load_space(space_id)
    → Client.get_channels_for_space(space_id)
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
    → Config.set_category_collapsed(space_id, cat_id, is_collapsed)

Category "+" button / context menu → "Create Channel"
  → category_item._on_create_channel()
    → CreateChannelDialogScene instantiated — parent_id pre-set to category id
      → Type dropdown includes Category option (line 44)
      → User fills name + type → Client.create_channel(space_id, data)
        → If type is "category", parent_id is skipped (line 66)
        → REST: POST /spaces/{space_id}/channels
          → Gateway: channel_create event
            → client_gateway.on_channel_create()
              → _channel_cache updated
              → AppState.channels_updated.emit(space_id)
                → channel_list._on_channels_updated() → load_space() rebuilds list

Category context menu → "Edit Category"
  → category_item._on_edit_category()
    → CategoryEditDialogScene instantiated — name input pre-filled
      → User edits name → Client.update_channel(category_id, data)
        → REST: PATCH /channels/{id}
          → Gateway: channel_update event
            → AppState.channels_updated.emit(space_id)

Category context menu → "Delete Category"
  → category_item._on_delete_category()
    → Checks channel_container.get_child_count() (line 146)
    → ConfirmDialog shown with orphan warning if children > 0
      → User confirms → Client.delete_channel(category_id)
        → REST: DELETE /channels/{id}
          → Gateway: channel_delete event
            → AppState.channels_updated.emit(space_id)

Channel/category drag-and-drop
  → channel_item._get_drag_data() / category_item._get_drag_data()
    → Permission check: Client.has_permission(space_id, MANAGE_CHANNELS)
    → Returns {"type": "channel"/"category", ..., "source_node": self}
  → Header.set_drag_forwarding() provides _get_drag_data for category drags
  → channel_list inserts UncategorizedDropTarget when uncategorized list is empty
    → UncategorizedDropTarget._drop_data()
      → channel_list._on_uncategorized_drop()
        → Client.admin.update_channel(id, {"parent_id": ""})
  → _notification(DRAG_BEGIN)
    → header.mouse_filter = IGNORE (drops bypass header)
    → channel_container.mouse_filter = IGNORE
    → _plus_btn.mouse_filter = IGNORE (if exists)
  → CategoryItem._can_drop_data() (called directly on VBoxContainer)
    → Channel drop: validates different parent, applies StyleBox highlight on header
    → Category drop: validates not self, same parent container
      → Sets _drop_above based on mouse Y vs header.size.y midpoint
      → queue_redraw() for blue line indicator
  → CategoryItem._drop_data()
    → Channel drop: _move_channel_to_category(ch_id, cat_id)
      → await Client.admin.update_channel() with error logging
        → REST: PATCH /channels/{id} with {"parent_id": cat_id}
        → On success: fetch_channels(space_id) → channels_updated → load_space()
    → Category drop: container.move_child(source, target_idx) for visual feedback
      → Builds position array from new child order
      → Client.admin.reorder_channels(space_id, positions)
        → REST: PATCH /spaces/{space_id}/channels with [{"id": ..., "position": N}, ...]
  → _notification(DRAG_END) restores all mouse_filter = STOP, clears indicators
```

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

## Implementation Details

### ChannelType enum and data model
`ClientModels` defines `ChannelType.CATEGORY` as value `4` (line 7). The `_channel_type_to_enum()` function (line 42) maps the server string `"category"` to this enum. The `channel_to_dict()` function (line 135) converts `AccordChannel` to a dictionary with `parent_id` extracted from the model:
```
{"id", "space_id", "name", "type": 4, "parent_id": "<category_id>", "position": N, "unread": false, ...}
```

### Channel list grouping and sorting (`channel_list.gd`)
`load_space()` (line 25) fetches channels via `Client.get_channels_for_space()` and performs a two-pass grouping followed by sorting:

1. **First pass** (lines 83-85): Identifies categories by checking `type == ChannelType.CATEGORY`. Stores them in a `categories` dictionary keyed by channel ID, with `data` and empty `children` array.
2. **Second pass** (lines 87-94): Non-category channels are assigned to their parent category via `parent_id`, or added to the `uncategorized` array if `parent_id` is empty or doesn't match a known category.
3. **Sorting** (lines 96-118): All collections are sorted by `position` then `name`:
   - Uncategorized channels sorted in-place (line 103).
   - Each category's children sorted in-place (line 107).
   - Categories converted to a sorted array (lines 110-118) for deterministic render order.
4. **Rendering** (lines 120-151): Uncategorized channels are instantiated as `ChannelItemScene` first. If there are no uncategorized channels, an `UncategorizedDropTarget` is inserted before categories (lines 133-138). Then each category is instantiated as `CategoryItemScene` with its sorted children. After `setup()`, `restore_collapse_state()` is called on each category (line 145). Channel items from inside categories are tracked in `channel_item_nodes` for selection management.

The channel list auto-selects the first non-category channel after loading (lines 164-180). An empty state is shown when there are zero non-category channels (lines 57-77), with a "Create Channel" button if the user has `MANAGE_CHANNELS` permission.

### Category item component (`category_item.gd`)
Each category is a `VBoxContainer` with a header `Button` and a `ChannelContainer` VBox for children.

**Setup** (line 42): Takes `(data: Dictionary, child_channels: Array)`. Sets the category name to uppercase (line 45), creates a channel count label (lines 47-54) that's initially hidden, instantiates `ChannelItemScene` for each child (lines 56-60), and conditionally adds a "+" button for creating channels (lines 62-75). The "+" button only appears if `Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS)` returns true.

**Channel count label** (lines 47-54): A 10px gray label showing the number of child channels. Created in `setup()` and added to `$Header/HBox` before the "+" button. Initially hidden; shown only when the category is collapsed.

**Collapse toggle** (line 77): `_toggle_collapsed()` flips `is_collapsed`, toggles `channel_container.visible`, swaps the chevron between `CHEVRON_DOWN` and `CHEVRON_RIGHT`, toggles `_count_label` visibility, and persists the state via `Config.set_category_collapsed()` (lines 83-85).

**Collapse persistence** (line 87): `restore_collapse_state()` reads saved state from `Config.is_category_collapsed()` and applies it — setting `is_collapsed`, hiding `channel_container`, swapping chevron, and showing the count label.

**Context menu** (lines 113-131): Right-click on the header shows a popup with "Create Channel", "Edit Category", and "Delete Category" — only if the user has `MANAGE_CHANNELS` permission (line 115).

**Create channel dialog** (line 133): Opens `CreateChannelDialogScene` with `parent_id` pre-set to the category's ID (line 136). The dialog now includes a "Category" type option (line 44 in `create_channel_dialog.gd`); selecting Category skips setting `parent_id` since categories are always top-level.

**Edit category dialog** (line 138): Opens `CategoryEditDialogScene` with the current name pre-filled. On submit, calls `Client.update_channel()` with the new name.

**Delete category** (line 143): Opens a `ConfirmDialog`. Checks `channel_container.get_child_count()` (line 146) — if > 0, the message warns about orphaned children becoming uncategorized (line 149). On confirm, calls `Client.delete_channel()` (line 159).

**Drag-and-drop** (lines 197-312): The Header button uses `set_drag_forwarding(_get_drag_data, ...)` (line 44) so category drags can start from the header. During drags, `_notification(NOTIFICATION_DRAG_BEGIN)` sets both `header.mouse_filter` and `channel_container.mouse_filter` to `MOUSE_FILTER_IGNORE` so all drop events reach the CategoryItem VBoxContainer directly — bypassing the Header button and its children (including the dynamically added `_plus_btn`). This is restored on `NOTIFICATION_DRAG_END`. `_can_drop_data()` accepts both channel drops (re-parent via `update_channel()`) and category drops (reorder via midpoint check using `header.size.y`). For channel drops, the indicator is a `StyleBoxFlat` override applied directly to the Header button (blue background + border), ensuring it renders visibly above all header content. `_drop_data()` delegates channel re-parenting to `_move_channel_to_category()`, an async helper that awaits the API result and logs a warning on failure. Category reordering uses immediate `move_child()` for visual feedback followed by `Client.admin.reorder_channels()`.

### Channel item drag-and-drop (`channel_item.gd`)
Channels support D&D reordering within the same parent container and cross-category moves. `_get_drag_data()` is gated on `MANAGE_CHANNELS` and returns `{"type": "channel", ...}` with a "# name" label preview. `_can_drop_data()` validates same type and same space. `_drop_data()` checks if the source and target share the same parent — if so, it reorders within the container; if not, it performs a cross-category move by calling `Client.admin.update_channel()` to change `parent_id`. A blue line indicator is drawn at the drop position via `_draw()`. The same cross-category logic exists in `voice_channel_item.gd`.

### Uncategorized root drop target (`uncategorized_drop_target.gd`)
When the uncategorized list is empty and there are categories, `channel_list` inserts an `UncategorizedDropTarget` (line 133). It accepts channel drops from the same space (lines 14-24) and emits `channel_dropped`, which `channel_list` handles by clearing the channel's `parent_id` (lines 230-236). The control draws a blue horizontal line on hover to indicate a valid drop target (lines 44-49).

### Create channel dialog (`create_channel_dialog.gd`)
The dialog (`setup()`, line 20) always adds Text/Voice/Announcement/Forum types (lines 25-28). The "Category" type (item id `4`) is added in both contexts: when called from `channel_list` (line 32) and when called from a category's context menu (line 44). When `parent_id` is set and the selected type is "category", the `parent_id` is skipped in `_on_create()` (line 66) since categories are always top-level. The parent dropdown is shown only when called from `channel_list` (lines 33-41).

### Collapse state persistence (`config.gd`)
Two methods added (lines 74-81):
- `set_category_collapsed(space_id, category_id, collapsed)`: Stores under ConfigFile section `[collapsed_SPACE_ID]` with category IDs as keys. Calls `save()` immediately.
- `is_category_collapsed(space_id, category_id)`: Returns the stored bool, defaulting to `false` (expanded).

### Gateway event handling (`client_gateway.gd`)
All three channel events handle categories the same as regular channels:
- `on_channel_create()` (line 170): Adds to `_channel_cache`, emits `channels_updated`.
- `on_channel_update()` (line 191): Replaces entry in `_channel_cache`, emits `channels_updated`.
- `on_channel_delete()` (line 212): Erases from `_channel_cache` and `_channel_to_space`, emits `channels_updated`.

On any of these events, `channel_list._on_channels_updated()` (line 201) calls `load_space()` to fully rebuild the list. This natural rebuild also serves as the rollback mechanism for failed D&D reorder operations.

### Styling
- Category name: uppercase, 11px font size, gray `Color(0.58, 0.608, 0.643)` (lines 31-32).
- Chevron: 12x12 `TextureRect`, same gray modulate (line 30).
- Header: 44px minimum height, flat button (no background).
- "+" button: 16x16, hidden by default, shown on hover (lines 105-111), gray icon that turns white on hover (lines 72-73).
- Channel count label: 10px font size, gray, shown only when collapsed (lines 48-53).
- Channel container: VBox with 2px separation between child items.
- Drag preview: white text label ("# channel-name" or "CATEGORY NAME").
- Drop indicator: blue line `Color(0.34, 0.52, 0.89)`, 2px wide, drawn at top or bottom edge. When dropping a channel onto a category, the entire header area highlights with a semi-transparent blue background and border.

### Permission gating
Category CRUD and reorder operations are gated behind `AccordPermission.MANAGE_CHANNELS`:
- The "+" button on category headers only renders if the user has permission (line 63).
- The right-click context menu only appears if the user has permission (line 115).
- The "+ Create Channel" button at the bottom of the channel list checks permission (line 154).
- Drag-and-drop initiation is gated in `_get_drag_data()` (channel_item.gd, voice_channel_item.gd, category_item.gd).

## Implementation Status
- [x] Category grouping — channels grouped by `parent_id` in two-pass algorithm
- [x] Sorting — uncategorized, category children, and categories sorted by `position` then `name`
- [x] Collapsible categories — toggle visibility with chevron animation
- [x] Channel count label — shown when collapsed, displays child count
- [x] Collapse state persistence — saved to `Config` per space/category, restored on load
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
- [x] Cross-category channel drag — channels can be dropped onto channel items in other categories to re-parent them
- [x] Drag handle visual affordance — 6-dot grip icon appears on hover for channels, voice channels, and category headers (permission-gated)
- [x] Channel-to-category header drop — dropping a channel directly onto a category header to re-parent it
- [x] Channel-to-uncategorized drop — drop onto the uncategorized root target when the root list is empty

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| None | - | - |
