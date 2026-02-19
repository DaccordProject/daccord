# Member List Performance

Last touched: 2026-02-19

## Overview

The member list displays all members of the currently selected guild, grouped by online status (Online, Idle, Do Not Disturb, Offline) and sorted alphabetically within each group. To handle guilds with many members without creating hundreds of scene tree nodes, it uses a **virtual scrolling** architecture: a fixed pool of `MemberItem` and `MemberHeader` nodes is recycled as the user scrolls, with only the visible rows rendered at any time.

## User Steps

1. User selects a guild — the member list loads all cached members for that guild.
2. The list groups members by status and sorts each group alphabetically.
3. As the user scrolls, only the visible rows are rendered using pooled node instances.
4. Gateway events (presence updates, joins, leaves, member updates, chunks) trigger a full rebuild of the row data and a re-render of visible items.
5. User can toggle member list visibility via the header toggle button (hidden in compact/DM mode).

## Signal Flow

```
Gateway event (presence_update / member_join / member_leave / member_update / member_chunk)
  │
  └─► client_gateway.gd updates _member_cache
        │
        └─► AppState.members_updated.emit(guild_id)
              │
              └─► member_list.gd._on_members_updated(guild_id)
                    │
                    └─► _rebuild_row_data()
                          ├── Group members by status
                          ├── Sort each group alphabetically
                          ├── Build flat _row_data array (headers + members)
                          ├── _update_virtual_height()  (set VirtualContent min height)
                          ├── _ensure_pool_size()        (grow pools if viewport larger)
                          └── _update_visible_items()    (render visible rows from pool)

ScrollContainer.value_changed
  └─► _update_visible_items(scroll_value)
        ├── _hide_all_pool_nodes()
        ├── Calculate first_row / last_row from scroll position
        └── Assign pool nodes to visible row indices (position + setup)
```

## Key Files

| File | Role |
|------|------|
| `scenes/members/member_list.gd` | Virtual scroll container, row data grouping/sorting, pool management |
| `scenes/members/member_list.tscn` | Scene layout: header label, invite button, ScrollContainer, VirtualContent |
| `scenes/members/member_item.gd` | Individual member display, avatar/name/status dot, context menu |
| `scenes/members/member_item.tscn` | Member row layout: 32px avatar, display name, 10x10 status dot |
| `scenes/members/member_header.gd` | Status group header with label (e.g. "ONLINE — 5") |
| `scenes/members/member_header.tscn` | Header row layout: uppercase label, 44px height |
| `scripts/autoload/client.gd` | `_member_cache` storage (line 48), `get_members_for_guild()` (line 260) |
| `scripts/autoload/client_fetch.gd` | `fetch_members()` REST call with `limit=1000` (line 261) |
| `scripts/autoload/client_gateway.gd` | Gateway handlers: `on_member_chunk` (line 331), `on_member_join` (line 370), `on_member_leave` (line 392), `on_member_update` (line 409), `on_presence_update` (line 300) |
| `scripts/autoload/client_models.gd` | `member_to_dict()` conversion (line 413), `UserStatus` enum, `status_color()` |
| `scripts/autoload/app_state.gd` | `members_updated` signal (line 30), `member_list_visible` state (line 120) |
| `scenes/main/main_window.gd` | Member list toggle visibility logic, layout-mode hiding |

## Implementation Details

### Virtual Scrolling (`member_list.gd`)

The core performance optimization is **object pooling with positional recycling**:

- **`ROW_HEIGHT = 44`** (line 6) — every row (member or header) is exactly 44px tall, enabling O(1) row index calculation from scroll position.
- **`_row_data: Array`** (line 9) — flat array of `{"type": "header", "label": "..."}` or `{"type": "member", "data": {...}}` dictionaries representing every row in display order.
- **`_item_pool` / `_header_pool`** (lines 10-11) — separate pools of pre-instantiated `MemberItem` and `MemberHeader` nodes. Pools grow but never shrink.
- **`_pool_size`** (line 12) — tracks current pool capacity to avoid redundant instantiation.

**Pool sizing** (`_ensure_pool_size`, line 96): Calculates `ceili(viewport_height / ROW_HEIGHT) + 8` to determine how many nodes are needed — the viewport's worth of rows plus an 8-row buffer for smooth scrolling. If the pool is already large enough, it returns immediately.

**Rendering** (`_update_visible_items`, line 125):
1. Hides all pool nodes (line 126).
2. Computes `first_row` and `last_row` from the scroll position and viewport height (lines 130-133).
3. Iterates from `first_row` to `last_row`, assigning each visible row to the next available pool node (lines 138-157).
4. Each assigned node gets `setup(data)` called, its `position.y` set to `row_index * ROW_HEIGHT`, and `visible = true`.

**Virtual height** (`_update_virtual_height`, line 93): Sets `VirtualContent.custom_minimum_size.y = _row_data.size() * ROW_HEIGHT` so the ScrollContainer's scrollbar accurately reflects the total list length without instantiating every row.

### Row Data Rebuild (`_rebuild_row_data`, line 49)

Triggered by `members_updated` signal or `guild_selected`:

1. Retrieves the full member array from `Client.get_members_for_guild()` (line 51).
2. Groups members into 4 status buckets: ONLINE, IDLE, DND, OFFLINE (lines 53-65).
3. Sorts each bucket alphabetically by `display_name` using `sort_custom()` with a case-insensitive comparator (lines 67-70).
4. Flattens groups into `_row_data` with a header row before each non-empty group (lines 79-87).
5. Calls `_update_virtual_height()`, `_ensure_pool_size()`, and `_update_visible_items()` (lines 89-91).

### Member Cache (`client.gd`)

- **`_member_cache: Dictionary`** (line 48) — maps `guild_id → Array[Dictionary]`. Each dictionary is a member dict produced by `ClientModels.member_to_dict()`.
- **`get_members_for_guild(gid)`** (line 260) — returns `_member_cache.get(gid, [])`, direct reference (not a copy).

### Initial Fetch (`client_fetch.gd`, line 261)

- Calls `GET /spaces/{id}/members?limit=1000` (line 267).
- For each member, checks `_user_cache` and fetches the user individually if missing (lines 273-284) — **sequential `await` per missing user**, which is a performance concern for large guilds.
- Stores the full array in `_member_cache[guild_id]` (line 290) and emits `members_updated`.

### Gateway Updates (`client_gateway.gd`)

Each gateway event modifies `_member_cache` in-place and emits `members_updated`:

- **`on_presence_update`** (line 300): Linear scan of `_member_cache[guild_id]` to find the member by ID (lines 314-316) and update their status. Emits `members_updated` even if the user isn't found.
- **`on_member_chunk`** (line 331): Bulk update — builds an ID→index map of existing members (lines 340-342), then merges new member data, either replacing or appending (lines 343-358).
- **`on_member_join`** (line 370): Appends a new member dict. Fetches the user via REST if not in cache (sequential `await`, lines 377-385).
- **`on_member_leave`** (line 392): Linear scan + `remove_at()` (lines 403-406).
- **`on_member_update`** (line 409): Linear scan + replace or append (lines 417-423).

### Member Item Recycling (`member_item.gd`)

Each `setup(data)` call (line 20) overwrites the previous state:
- Sets `display_name.text` (line 22)
- Updates avatar color, letter, and URL (lines 23-31)
- Sets `status_dot.color` from the status enum (line 34)

The context menu (`PopupMenu`) is created once in `_ready()` (line 15) and rebuilt on each right-click via `_show_context_menu()` (line 47), which calls `_context_menu.clear()` before repopulating.

### Visibility Toggle (`main_window.gd`)

- **`AppState.member_list_visible`** (line 120 of app_state.gd) — tracks whether the member list panel is shown.
- **`toggle_member_list()`** (line 197 of app_state.gd) — flips the bool and emits `member_list_toggled`.
- **Layout-mode gating** (main_window.gd lines 182-203): In FULL/MEDIUM mode the toggle button is visible and the panel follows `member_list_visible`. In COMPACT mode both are hidden. On transition from MEDIUM→FULL, the previous visibility state is restored.

## Implementation Status

- [x] Virtual scrolling with object pooling (fixed 44px row height)
- [x] Separate pools for member items and header items
- [x] Pool grows on-demand based on viewport height + 8-row buffer
- [x] Status grouping (Online, Idle, DND, Offline) with alphabetical sort
- [x] Gateway-driven incremental cache updates (join, leave, update, chunk, presence)
- [x] Member list visibility toggle with layout-mode awareness
- [x] Flat row data array for O(1) index-to-position mapping
- [x] Avatar, display name, and status dot recycled per `setup()` call
- [ ] Pool shrinking when viewport gets smaller
- [ ] Debounced/throttled rebuild on rapid gateway events
- [ ] Incremental row data update (insert/remove single row vs full rebuild)
- [ ] Lazy avatar image loading (only fetch visible avatar URLs)
- [ ] Search/filter within the member list
- [ ] Role-based grouping (in addition to status grouping)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Full rebuild on every `members_updated` | Medium | `_rebuild_row_data()` (line 49) re-groups, re-sorts, and re-renders the entire list on every gateway event — including single-member presence changes. For large guilds, a presence flicker rebuilds 1000+ row entries. Should debounce rapid events or do incremental inserts/removals. |
| Sequential user fetch during `fetch_members` | High | `client_fetch.gd` (lines 273-284) awaits a REST call per missing user in series. For a guild with 500 members and 400 cache misses, this means 400 sequential HTTP requests. Should batch-fetch users or rely on the server including user data in the member response. |
| `_hide_all_pool_nodes()` called on every scroll tick | Medium | `_update_visible_items()` (line 126) iterates all pool nodes to hide them before re-showing visible ones. With a pool of ~30 items this is cheap, but the pattern scales with pool size. A dirty-tracking approach (only hide nodes that moved out of view) would be more efficient. |
| Presence update emits even when member not found | Low | `on_presence_update` (line 318) emits `members_updated` unconditionally after the linear scan, triggering a full rebuild even if the presence was for a user not in the guild's member cache. Should guard the emit with a `found` flag. |
| Linear scan for member lookup in gateway handlers | Low | `on_presence_update`, `on_member_leave`, `on_member_update` all do `O(n)` scans of the member cache array to find a member by ID (lines 314, 403, 417). An ID→index dictionary (like `on_member_chunk` builds at line 340) would make these O(1). |
| `has_permission()` scans member cache | Low | `client.gd:has_permission()` (line 403) iterates the full member array to find the current user's roles. Called on guild select (line 41 of member_list.gd) and on every context menu open. Should cache the current user's roles per guild. |
| No pool shrinking | Low | `_ensure_pool_size()` (line 96) only grows pools. If the user resizes the window smaller, orphaned pool nodes remain in memory. Not a practical problem since pool sizes are small (typically <40 nodes). |
| `limit=1000` hardcoded in fetch | Medium | `client_fetch.gd` (line 267) fetches at most 1000 members. Guilds with more than 1000 members will have an incomplete list. Should paginate or use gateway member chunking for the remainder. |
| No avatar image caching across pool recycles | Low | `member_item.gd:setup()` calls `set_avatar_url()` (line 31) on every recycle. If the avatar component re-downloads the image each time a pool node is recycled to a different member, this creates redundant network requests. Depends on `avatar.gd`'s internal caching behavior. |
