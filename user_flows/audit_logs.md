# Audit Logs

Priority: 52
Depends on: Moderation

## Overview
The audit log lets server admins review administrative actions performed within a space. Users with the `VIEW_AUDIT_LOG` permission can open the audit log dialog from the space icon context menu or the channel banner dropdown, browse paginated entries, filter by action type, search by action/user/reason, view change diffs, and receive real-time updates via gateway events.

## User Steps
1. Right-click a space icon **or** click the channel banner dropdown.
2. Select **"Audit Log"** from the context menu (only visible with `VIEW_AUDIT_LOG` permission).
3. The Audit Log dialog opens and fetches the first page of entries from the server.
4. Each row shows an icon, the acting user (resolved from cache), the action description, the resolved target name, and a relative timestamp.
5. If an entry has changes data, a "Show Details" toggle reveals old/new value diffs.
6. Optionally filter by action type via the dropdown (e.g. "Member Kick", "Role Create").
7. Optionally search entries by typing in the search box (matches action, user ID, or reason).
8. Click **"Load More"** to fetch the next page of older entries.
9. New entries arriving via gateway are prepended to the list in real-time.
10. Close the dialog via the close button, clicking the backdrop, or pressing Escape.

## Signal Flow
```
User right-clicks space icon / clicks banner
    -> PopupMenu shown                                      [guild_icon.gd / banner.gd]
        -> User selects "Audit Log"
            -> AuditLogScene.instantiate()                   [guild_icon.gd:264 / banner.gd:151]
                -> dialog.setup(space_id)                    [audit_log_dialog.gd:45]
                    -> connects AppState.audit_log_entry_created  [audit_log_dialog.gd:47]
                    -> _load_entries()                        [audit_log_dialog.gd:56]
                        -> _fetch_page()                     [audit_log_dialog.gd:66]
                            -> Client.admin.get_audit_log()  [client_admin.gd:286]
                                -> AccordClient.audit_logs.list(space_id, query)  [audit_logs_api.gd:9]
                                    -> GET /spaces/{id}/audit-log?limit=25[&before=...][&action_type=...]
                        -> _rebuild_list(entries)             [audit_log_dialog.gd:97]
                            -> AuditLogRow.setup(entry_dict, space_id)  [audit_log_row.gd:43]

Gateway real-time path:
    Server creates audit log entry
        -> broadcast_entry() sends audit_log.create event   [audit_log.rs:41]
            -> GatewaySocket.audit_log_create signal         [gateway_socket.gd:100]
                -> AccordClient.audit_log_create signal      [accord_client.gd:97]
                    -> ClientGatewayEvents.on_audit_log_create  [client_gateway_events.gd:54]
                        -> AppState.audit_log_entry_created  [app_state.gd:42]
                            -> dialog._on_gateway_entry()    [audit_log_dialog.gd:146]
                                -> prepends row to entry list
```

## Key Files
| File | Role |
|------|------|
| `scenes/admin/audit_log_dialog.gd` | Main dialog: pagination, search, filter, entry list management, gateway subscription |
| `scenes/admin/audit_log_dialog.tscn` | Dialog scene: search input, filter dropdown, scroll list, load-more button, empty/error labels |
| `scenes/admin/audit_log_row.gd` | Single row: emoji icon, user/target name resolution, action formatting, relative time, expandable change diffs |
| `scenes/admin/audit_log_row.tscn` | Row scene: VBoxContainer wrapping HBox row + collapsible ChangesPanel |
| `addons/accordkit/rest/endpoints/audit_logs_api.gd` | REST endpoint: `list(space_id, query)` calls `GET /spaces/{id}/audit-log` |
| `addons/accordkit/models/audit_log_entry.gd` | `AccordAuditLogEntry` model with `from_dict()` / `to_dict()` |
| `addons/accordkit/gateway/gateway_socket.gd` | `audit_log_create` signal (line 100), dispatch on `"audit_log.create"` event |
| `addons/accordkit/core/accord_client.gd` | Forwards `audit_log_create` signal from gateway (line 97) |
| `scripts/client/client_admin.gd` | `get_audit_log()` (line 286) routes the call to the correct AccordClient |
| `scripts/client/client_gateway.gd` | Connects `audit_log_create` to `_events.on_audit_log_create` (line 70) |
| `scripts/client/client_gateway_events.gd` | `on_audit_log_create()` (line 54) emits `AppState.audit_log_entry_created` |
| `scripts/autoload/app_state.gd` | `audit_log_entry_created(space_id, entry)` signal (line 42) |
| `addons/accordkit/models/permission.gd` | Defines `VIEW_AUDIT_LOG` constant (line 13) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space icon context menu: gates "Audit Log" on `VIEW_AUDIT_LOG` (line 194), opens dialog (line 264) |
| `scenes/sidebar/channels/banner.gd` | Channel banner dropdown: gates "Audit Log" on `VIEW_AUDIT_LOG` (line 96), opens dialog (line 151) |

### Server-Side Files
| File | Role |
|------|------|
| `../accordserver/src/routes/audit_log.rs` | REST endpoint `list_audit_log()`, `broadcast_entry()` gateway helper, `entry_to_json()` |
| `../accordserver/src/db/audit_log.rs` | `create_entry()` inserts row, `list_entries()` with action_type/user_id/before filters |
| `../accordserver/src/gateway/intents.rs` | Maps `audit_log.create` to `"moderation"` intent (line 45) |

## Implementation Details

### Permission Gating
The "Audit Log" menu item only appears if the user has the `VIEW_AUDIT_LOG` permission for the space. Both `guild_icon.gd` (line 194) and `banner.gd` (line 96) check `Client.has_permission(space_id, AccordPermission.VIEW_AUDIT_LOG)` before adding the item. The permission constant is defined in `permission.gd` (line 13) as the string `"view_audit_log"`.

### Dialog Lifecycle
`AuditLogDialog` extends `ModalBase` (scene-based modal). On `setup(space_id)` (line 45), it stores the space ID, connects to `AppState.audit_log_entry_created` for real-time updates, and loads the first page. On `_exit_tree()` (line 51), it disconnects the gateway signal.

The dialog is instantiated and added to the scene tree via `DialogHelper.open()` from `guild_icon.gd` (line 264) or direct instantiation from `banner.gd` (line 151).

### Pagination
`_fetch_page()` (line 66) sends `GET /spaces/{id}/audit-log` with a `limit` of `PAGE_SIZE` (25, line 5). If a previous page was loaded, the `before` parameter is set to `_last_entry_id` for cursor-based pagination. The response is unwrapped from the `{"data": [...]}` envelope by `AccordRest._interpret_parsed()`.

After receiving entries, if the count equals `PAGE_SIZE`, `_has_more` is set to `true` and the "Load More" button becomes visible (lines 93-94). Clicking "Load More" calls `_fetch_page()` again, appending entries to `_all_entries` and advancing the cursor.

### Action Type Filtering
The filter dropdown (`_filter_option`) is populated in `_ready()` (lines 27-43) with 17 options:
- All Actions, Member Kick, Member Ban Add, Member Ban Remove, Member Update, Role Create, Role Update, Role Delete, Channel Create, Channel Update, Channel Delete, Invite Create, Invite Delete, Message Delete, Space Update, Invite Accept, Member Join

`_get_selected_action_type()` (line 110) maps the selected index to an action type string (e.g. `"member_kick"`, `"role_create"`). When a filter is selected, `_on_filter_changed()` (line 137) calls `_load_entries()` which clears all cached entries and re-fetches from page 1 with the `action_type` query parameter.

### Client-Side Search
`_on_search_changed()` (line 123) filters the already-fetched `_all_entries` array by checking if the query appears (case-insensitive) in the entry's `action_type`, `user_id`, or `reason`. This is local-only and does not re-fetch from the server.

### Row Rendering
Each `AuditLogRow` extends `VBoxContainer` wrapping a summary HBox and a collapsible `ChangesPanel`. The `setup(entry, space_id)` method (audit_log_row.gd, line 43) populates:

- **Icon**: emoji from `_ACTION_ICONS` dictionary (lines 3-27), keyed by action type (e.g. member_kick -> door emoji, member_ban_add -> hammer emoji). 27 action types mapped.
- **User**: `_resolve_user()` (line 63) checks the space member cache first, then falls back to `Client.get_user_by_id()` for the global user cache. Returns the raw user ID only if both lookups miss.
- **Action**: `_format_action()` (line 59) replaces underscores with spaces and capitalizes.
- **Target**: `_format_target()` (line 78) resolves target names by type:
  - `"member"/"user"` -> resolved username via `_resolve_user()`
  - `"role"` -> role name from `Client.get_roles_for_space()` via `_resolve_role()` (line 105)
  - `"channel"` -> channel name prefixed with `#` from `Client.get_channels_for_space()` via `_resolve_channel()` (line 113)
  - `"invite"` -> invite code and inviter name from changes dict
  - Falls back to abbreviated ID suffix for unknown types
- **Time**: `_relative_time()` (line 185) computes time differences with thresholds: "just now" (<60s), "Xm ago" (<1h), "Xh ago" (<1d), "Xd ago" (<7d), then falls back to the date string.

### Change Diff Display
`_setup_changes()` (line 121) processes the entry's `changes` field (Dictionary or Array). If non-empty, it creates a "Show Details" toggle button and a hidden `VBoxContainer` with change labels. Each key-value pair is rendered as:
- `Key: old_value -> new_value` for Dictionary values with `old`/`new` keys
- `Key: value` for simple values

The toggle button shows/hides the detail box on click (lines 151-155).

### Gateway Real-Time Updates
The server broadcasts `audit_log.create` events via `broadcast_entry()` (audit_log.rs) after creating new entries. The event is gated behind the `"moderation"` intent (intents.rs, line 45).

On the client, the signal chain is: `GatewaySocket.audit_log_create` -> `AccordClient.audit_log_create` -> `ClientGatewayEvents.on_audit_log_create()` -> `AppState.audit_log_entry_created(space_id, entry)`.

The dialog's `_on_gateway_entry()` (line 146) checks the space ID matches, verifies the entry passes the current action type filter, and prepends the new entry to both `_all_entries` and the visible row list.

### AccordKit Model
`AccordAuditLogEntry` (audit_log_entry.gd) is a `RefCounted` model with fields: `id`, `user_id`, `action_type`, `target_id`, `target_type`, `reason`, `changes` (Array), `created_at`. It has `from_dict()` / `to_dict()` conversions. The dialog currently works with raw dictionaries for flexibility with the changes panel.

### REST API
`AuditLogsApi.list()` (audit_logs_api.gd, line 9) sends `GET /spaces/{space_id}/audit-log` with optional query parameters (`limit`, `before`, `user_id`, `action_type`). Returns a `RestResult` whose `data` is the unwrapped array of entry dictionaries.

`ClientAdmin.get_audit_log()` (client_admin.gd, line 286) routes the call to the correct `AccordClient` for the given space ID.

### Server-Side
`db::audit_log::create_entry()` (audit_log.rs) inserts a row with snowflake ID and returns the full `AuditLogRow`. Currently called from `invites.rs` (invite acceptance) and `spaces.rs` (public join). Both call sites now also broadcast the entry via `audit_log::broadcast_entry()`.

`list_entries()` supports optional filters: `action_type`, `user_id`, `before` (cursor), and `limit` (max 100, default 25).

## Implementation Status
- [x] Permission gating via `VIEW_AUDIT_LOG`
- [x] Entry point from space icon context menu
- [x] Entry point from channel banner dropdown
- [x] Paginated fetching with cursor-based "Load More"
- [x] Action type filter dropdown (17 action types)
- [x] Client-side search by action, user ID, or reason
- [x] Row rendering with emoji icons, relative timestamps
- [x] User resolution with global cache fallback
- [x] Target name resolution (roles, channels, users from cache)
- [x] Expandable change diff display (old/new value pairs)
- [x] Real-time updates via `audit_log.create` gateway event
- [x] Error display on fetch failure
- [x] Empty state label
- [x] Modal close via button, backdrop click, and Escape key
- [x] AccordKit model (`AccordAuditLogEntry`) and REST endpoint (`AuditLogsApi`)
- [x] Server-side gateway broadcast for new entries
- [ ] Date range filtering
- [ ] Export/download audit log
- [ ] Server-side search (API supports `user_id` param but dialog doesn't use it)
- [ ] Audit log entries for most admin actions (only invite_accept and member_join currently logged)

## Tasks

### AUDIT-3: Search is client-side only
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, ui
- **Notes:** `_on_search_changed()` (audit_log_dialog.gd, line 123) filters the in-memory `_all_entries` array. If only one page was loaded, search can't find entries on unfetched pages. The `AuditLogsApi.list()` endpoint supports a `user_id` query param but the dialog doesn't use it for server-side search.

### AUDIT-7: No date range filter
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Only action type filtering is supported. There's no way to filter entries by date range (e.g. "last 24 hours", "last week").

### AUDIT-9: Most admin actions don't create audit log entries
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** api
- **Notes:** Only `invite_accept` and `member_join` actions call `db::audit_log::create_entry()` on the server. Kicks, bans, role changes, channel changes, space updates, message deletes, and other admin actions are not logged. Each route handler needs a `create_entry()` + `broadcast_entry()` call after the action succeeds.
