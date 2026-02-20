# Member List Performance

Last touched: 2026-02-19

## Overview

The member list displays all members of the currently selected guild, grouped by online status (Online, Idle, Do Not Disturb, Offline) or by role, and sorted alphabetically within each group. To handle guilds with many members without creating hundreds of scene tree nodes, it uses a **virtual scrolling** architecture: a fixed pool of `MemberItem` and `MemberHeader` nodes is recycled as the user scrolls, with only the visible rows rendered at any time.

A search bar filters members by display name, and a toggle button switches between status grouping and role-based grouping. Single-member gateway events (join, leave, presence change) are handled incrementally without a full rebuild when possible.

## User Steps

1. User selects a guild — the member list loads all cached members for that guild.
2. The list groups members by status (or by role if toggled) and sorts each group alphabetically.
3. As the user scrolls, only the visible rows are rendered using pooled node instances.
4. Single-member gateway events (joins, leaves, presence changes) update the row data incrementally — inserting, removing, or moving a single member within `_row_data`.
5. Bulk events (member chunks, full fetch) trigger a debounced full rebuild of the row data.
6. User can search members by name using the search bar below the header.
7. User can toggle between status grouping and role-based grouping via the header toggle button.
8. User can toggle member list visibility via the header toggle button (hidden in compact/DM mode).

## Signal Flow

```
Gateway event (single-member: presence_update / member_join / member_leave)
  │
  └─► client_gateway.gd updates _member_cache
        │
        ├─► AppState.member_status_changed / member_joined / member_left
        │     │
        │     └─► member_list.gd incremental handler (if status grouping, no search)
        │           ├── _insert_member_into_group() / _remove_member_row()
        │           ├── _update_virtual_height()
        │           ├── _adjust_pool_size()
        │           └── _update_visible_items()
        │
        └─► AppState.members_updated.emit(guild_id)
              │
              └─► member_list.gd._on_members_updated(guild_id)
                    │ (skipped if incremental handler already ran)
                    └─► _debounce_timer.start() → _rebuild_row_data()

Gateway event (bulk: member_chunk / member_update / full fetch)
  │
  └─► client_gateway.gd updates _member_cache
        │
        └─► AppState.members_updated.emit(guild_id)
              │
              └─► member_list.gd._on_members_updated(guild_id)
                    │
                    └─► _debounce_timer.start() → _rebuild_row_data()
                          ├── _build_status_groups() or _build_role_groups()
                          ├── _update_virtual_height()
                          ├── _adjust_pool_size()
                          └── _update_visible_items()

ScrollContainer.value_changed
  └─► _update_visible_items(scroll_value)
        ├── _hide_all_pool_nodes()
        ├── Calculate first_row / last_row from scroll position
        └── Assign pool nodes to visible row indices (position + setup)
```

## Key Files

| File | Role |
|------|------|
| `scenes/members/member_list.gd` | Virtual scroll container, row data grouping/sorting, pool management, search, role grouping, incremental updates |
| `scenes/members/member_list.tscn` | Scene layout: header bar (label + group toggle), invite button, search bar, ScrollContainer, VirtualContent |
| `scenes/members/member_item.gd` | Individual member display, avatar/name/status dot, context menu |
| `scenes/members/member_item.tscn` | Member row layout: 32px avatar, display name, 10x10 status dot |
| `scenes/members/member_header.gd` | Status/role group header with label (e.g. "ONLINE — 5") |
| `scenes/members/member_header.tscn` | Header row layout: uppercase label, 44px height |
| `scripts/autoload/client.gd` | `_member_cache` storage (line 81), `get_members_for_guild()` (line 302), `get_roles_for_guild()` (line 305) |
| `scripts/autoload/client_fetch.gd` | `fetch_members()` REST call with paginated `limit=1000` (line 268), deduplicated user fetch (line 311) |
| `scripts/autoload/client_gateway.gd` | Gateway handlers: `on_member_chunk` (line 335), `on_member_join` (line 375), `on_member_leave` (line 401), `on_member_update` (line 418), `on_presence_update` (line 300). Emits fine-grained signals: `member_joined` (line 398), `member_left` (line 415), `member_status_changed` (line 319) |
| `scripts/autoload/client_models.gd` | `member_to_dict()` conversion, `UserStatus` enum, `status_color()` |
| `scripts/autoload/app_state.gd` | `members_updated` signal (line 30), `member_joined` (line 32), `member_left` (line 34), `member_status_changed` (line 36), `member_list_visible` state (line 130) |
| `scenes/main/main_window.gd` | Member list toggle visibility logic, layout-mode hiding |

## Implementation Details

### Virtual Scrolling (`member_list.gd`)

The core performance optimization is **object pooling with positional recycling**:

- **`ROW_HEIGHT = 44`** (line 6) — every row (member or header) is exactly 44px tall, enabling O(1) row index calculation from scroll position.
- **`_row_data: Array`** (line 12) — flat array of `{"type": "header", "label": "...", "status": N}` or `{"type": "member", "data": {...}}` dictionaries representing every row in display order. Status headers include a `status` key for incremental group lookup.
- **`_item_pool` / `_header_pool`** (lines 13-14) — separate pools of pre-instantiated `MemberItem` and `MemberHeader` nodes.
- **`_pool_size`** (line 15) — tracks current pool capacity to avoid redundant instantiation.

**Pool sizing** (`_adjust_pool_size`, line 426): Calculates `ceili(viewport_height / ROW_HEIGHT) + 8` to determine how many nodes are needed — the viewport's worth of rows plus an 8-row buffer for smooth scrolling. Grows the pool if needed. **Shrinks** when `needed < _pool_size - 8` (hysteresis via `POOL_SHRINK_HYSTERESIS`, line 9), freeing excess nodes from the end of the pools to reclaim memory after window resize.

**Virtual height** (`_update_virtual_height`): Sets `VirtualContent.custom_minimum_size.y = _row_data.size() * ROW_HEIGHT` so the ScrollContainer's scrollbar accurately reflects the total list length without instantiating every row.

### Row Data Rebuild (`_rebuild_row_data`, line 106)

Triggered by debounced `members_updated` signal, `guild_selected`, search text changes, or grouping toggle:

1. Clears `_row_data` and delegates to `_build_status_groups()` (line 118) or `_build_role_groups()` (line 170) based on `_group_by_role`.
2. Both builders filter members against `_search_text` (case-insensitive substring match, line 19).
3. Calls `_update_virtual_height()`, `_adjust_pool_size()`, and `_update_visible_items()`.

**Status grouping** (`_build_status_groups`, line 118): Groups members into 4 status buckets (ONLINE, IDLE, DND, OFFLINE), sorts each alphabetically, and flattens into `_row_data` with status headers.

**Role grouping** (`_build_role_groups`, line 170): Groups members by their highest role (by position). Roles are sorted by position descending (highest first). Members with no roles (or only @everyone) go in a "No Role" group at the end.

### Debounced Rebuild (`member_list.gd`)

- **`DEBOUNCE_MS = 100`** (line 8) — a one-shot `Timer` coalesces rapid `members_updated` signals into a single `_rebuild_row_data()` call. Prevents multiple full rebuilds from burst gateway events.
- `_on_members_updated()` starts the debounce timer unless `_incremental_handled` is true (meaning a fine-grained handler already processed this event).

### Incremental Updates (`member_list.gd`, lines 240-284)

For single-member events (join, leave, presence change), the member list avoids a full rebuild:

- **`_can_incremental()`** (line 243): Returns `true` only when no search filter is active and status grouping is in use. Role grouping and search fall back to full rebuild.
- **`_on_member_joined()`** (line 246): Inserts the new member into the correct status group at its alphabetical position. Checks for duplicates first.
- **`_on_member_left()`** (line 259): Removes the member row and updates the group header count. Removes the header if the group becomes empty.
- **`_on_member_status_changed()`** (line 268): Removes the member from its current group (found by scanning upward for the header), then inserts into the new status group.
- **`_incremental_handled`** flag: Set by incremental handlers so the subsequent `members_updated` signal (emitted by the same gateway handler) skips the full rebuild.

**Helper methods:**
- `_find_group_range(status)` (line 309): Finds the header row and member range for a status group.
- `_find_member_row(user_id)` (line 322): Linear scan for a member by ID in `_row_data`.
- `_insert_member_into_group(member_data)` (line 329): Creates the group header if needed (positioned among existing groups), then inserts the member at its alphabetical position.
- `_remove_member_row(user_id)` (line 385): Removes a member and updates/removes the group header by scanning upward (avoids depending on the member's `status` field, which may already be mutated by the cache update).

### Search/Filter (`member_list.gd`)

- **`_search_text`** (line 19): Stores the current filter text (lowercased, stripped).
- **`search_bar`**: `LineEdit` node below the header bar. `text_changed` signal triggers `_on_search_changed()` (line 95), which updates `_search_text` and does a full `_rebuild_row_data()`.
- Both `_build_status_groups()` and `_build_role_groups()` skip members whose `display_name` doesn't contain `_search_text` (case-insensitive).

### Role-Based Grouping (`member_list.gd`)

- **`_group_by_role`** (line 20): Boolean toggle.
- **`group_toggle`**: `Button` in the header bar. Clicking it toggles `_group_by_role` and updates the button text ("Status" / "Roles"), then triggers a full rebuild.
- **`_build_role_groups()`** (line 170): Groups members by their highest role's position. Uses `Client.get_roles_for_guild()` to get role data. @everyone (position 0) is skipped. Roles are ordered by position descending (highest first). Members with no assignable roles go in "No Role".
- Listens to `AppState.roles_updated` to rebuild when roles change.

### Member Cache (`client.gd`)

- **`_member_cache: Dictionary`** (line 81) — maps `guild_id → Array[Dictionary]`. Each dictionary is a member dict produced by `ClientModels.member_to_dict()`.
- **`_member_id_index: Dictionary`** (line 94) — maps `guild_id → { user_id → array_index }` for O(1) lookups via `_member_index_for()`.
- **`get_members_for_guild(gid)`** (line 302) — returns `_member_cache.get(gid, [])`, direct reference (not a copy).
- **`get_roles_for_guild(gid)`** (line 305) — returns `_role_cache.get(gid, [])`.

### Initial Fetch (`client_fetch.gd`, line 268)

- Uses paginated fetch with `limit=1000` and cursor-based pagination (line 278).
- Collects unique missing user IDs upfront (deduplicated, line 301), then fetches each sequentially (line 311).
- Stores the full array in `_member_cache[guild_id]` and rebuilds the member ID index.

### Gateway Updates (`client_gateway.gd`)

Each gateway event modifies `_member_cache` in-place and emits both fine-grained and bulk signals:

- **`on_presence_update`** (line 300): Uses O(1) `_member_index_for()` lookup. Updates status and emits `member_status_changed` only when the status actually changes (line 318). Always emits `members_updated`.
- **`on_member_chunk`** (line 335): Bulk update — builds an ID→index map of existing members, then merges new member data. Emits only `members_updated`.
- **`on_member_join`** (line 375): Appends a new member dict, updates the member ID index. Emits `member_joined` (line 398) and `members_updated`.
- **`on_member_leave`** (line 401): Uses O(1) lookup, `remove_at()`, and index rebuild. Emits `member_left` (line 415) and `members_updated` only when the member was actually found.
- **`on_member_update`** (line 418): Uses O(1) lookup, replaces or appends. Emits `members_updated`.

### Member Item Recycling (`member_item.gd`)

Each `setup(data)` call (line 22) overwrites the previous state:
- Sets `display_name.text` (line 24)
- Updates avatar color, letter, and URL (lines 25-33)
- Sets `status_dot.color` from the status enum (line 36)

The context menu (`PopupMenu`) is created once in `_ready()` (line 16) and rebuilt on each right-click via `_show_context_menu()` (line 49), which calls `_context_menu.clear()` before repopulating.

### Visibility Toggle (`main_window.gd`)

- **`AppState.member_list_visible`** (line 130 of app_state.gd) — tracks whether the member list panel is shown.
- **`toggle_member_list()`** — flips the bool and emits `member_list_toggled`.
- **Layout-mode gating**: In FULL/MEDIUM mode the toggle button is visible and the panel follows `member_list_visible`. In COMPACT mode both are hidden.

## Implementation Status

- [x] Virtual scrolling with object pooling (fixed 44px row height)
- [x] Separate pools for member items and header items
- [x] Pool grows on-demand based on viewport height + 8-row buffer
- [x] Pool shrinks with hysteresis when viewport gets smaller
- [x] Status grouping (Online, Idle, DND, Offline) with alphabetical sort
- [x] Role-based grouping (by highest role, ordered by position)
- [x] Search/filter within the member list (case-insensitive display_name match)
- [x] Gateway-driven incremental cache updates (join, leave, update, chunk, presence)
- [x] Incremental row data updates for single-member events (insert/remove vs full rebuild)
- [x] Debounced rebuild (100ms) on rapid gateway events
- [x] O(1) member lookup via `_member_id_index` / `_member_index_for()`
- [x] Paginated member fetch with cursor in `client_fetch.gd`
- [x] Presence emit guarded by `if idx != -1` and status-change check
- [x] Member leave emit guarded — only fires when member was actually removed
- [x] `_hide_all_pool_nodes()` only iterates `_active_items` / `_active_headers`
- [x] `has_permission()` uses `_member_index_for()` (O(1))
- [x] Avatar static image cache (200 entries with LRU eviction in `avatar.gd`)
- [x] Fine-grained signals (`member_joined`, `member_left`, `member_status_changed`) for incremental UI updates
- [x] Member list visibility toggle with layout-mode awareness
- [x] Flat row data array for O(1) index-to-position mapping
- [x] Avatar, display name, and status dot recycled per `setup()` call
- [ ] Lazy avatar image loading (only fetch visible avatar URLs)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `_hide_all_pool_nodes()` called on every scroll tick | Low | `_update_visible_items()` iterates `_active_items` and `_active_headers` to hide them before re-showing visible ones. With typical pool sizes of ~30 items this is cheap. A dirty-tracking approach (only hide nodes that moved out of view) would be marginally more efficient. |
| Sequential user fetch during `fetch_members` | Medium | `client_fetch.gd` (line 311) awaits a REST call per missing user in series. GDScript 4.5+ requires `await` on coroutine calls, preventing true parallelism at the language level. Deduplicated upfront to avoid redundant fetches. Best fix is for the server to include user data in the member list response. |
| No avatar image caching across pool recycles | Low | `member_item.gd:setup()` calls `set_avatar_url()` on every recycle. Depends on `avatar.gd`'s internal caching behavior (currently has a 200-entry LRU cache, so this is largely mitigated). |
| Incremental updates disabled during search/role grouping | Low | When a search filter is active or role grouping is enabled, single-member events fall back to a full debounced rebuild. Incremental updates for these modes would add significant complexity for minimal benefit. |
