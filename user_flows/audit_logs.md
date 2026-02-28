# Audit Logs

## Overview
The audit log lets server admins review administrative actions performed within a space. Users with the `VIEW_AUDIT_LOG` permission can open the audit log dialog from the space icon context menu or the channel banner dropdown, browse paginated entries, filter by action type, and search by action/user/reason.

## User Steps
1. Right-click a space icon **or** click the channel banner dropdown.
2. Select **"Audit Log"** from the context menu (only visible with `VIEW_AUDIT_LOG` permission).
3. The Audit Log dialog opens and fetches the first page of entries from the server.
4. Each row shows an icon, the acting user, the action description, the target, and a relative timestamp.
5. Optionally filter by action type via the dropdown (e.g. "Member Kick", "Role Create").
6. Optionally search entries by typing in the search box (matches action, user ID, or reason).
7. Click **"Load More"** to fetch the next page of older entries.
8. Close the dialog via the close button, clicking the backdrop, or pressing Escape.

## Signal Flow
```
User right-clicks space icon / clicks banner
    -> PopupMenu shown                                      [guild_icon.gd / banner.gd]
        -> User selects "Audit Log"
            -> AuditLogScene.instantiate()                   [guild_icon.gd:252 / banner.gd:139]
                -> dialog.setup(space_id)                    [audit_log_dialog.gd:42]
                    -> _load_entries()                        [audit_log_dialog.gd:46]
                        -> _fetch_page()                     [audit_log_dialog.gd:57]
                            -> Client.admin.get_audit_log()  [client_admin.gd:198]
                                -> AccordClient.audit_logs.list(space_id, query)  [audit_logs_api.gd:15]
                                    -> GET /spaces/{id}/audit-log?limit=25[&before=...][&action_type=...]
                        -> _rebuild_list(entries)             [audit_log_dialog.gd:93]
                            -> AuditLogRow.setup(entry_dict)  [audit_log_row.gd:28]
```

## Key Files
| File | Role |
|------|------|
| `scenes/admin/audit_log_dialog.gd` | Main dialog: pagination, search, filter, entry list management |
| `scenes/admin/audit_log_dialog.tscn` | Dialog scene: search input, filter dropdown, scroll list, load-more button, empty/error labels |
| `scenes/admin/audit_log_row.gd` | Single row: emoji icon, user resolution, action formatting, target abbreviation, relative time |
| `scenes/admin/audit_log_row.tscn` | Row scene: HBoxContainer with icon, user, action, target, and time labels |
| `addons/accordkit/rest/endpoints/audit_logs_api.gd` | REST endpoint: `list(space_id, query)` calls `GET /spaces/{id}/audit-log` |
| `addons/accordkit/models/audit_log_entry.gd` | `AccordAuditLogEntry` model with `from_dict()` / `to_dict()` |
| `scripts/autoload/client_admin.gd` | `get_audit_log()` (line 198) routes the call to the correct AccordClient |
| `addons/accordkit/models/permission.gd` | Defines `VIEW_AUDIT_LOG` constant (line 13) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space icon context menu: gates "Audit Log" on `VIEW_AUDIT_LOG` (line 179), opens dialog (line 252) |
| `scenes/sidebar/channels/banner.gd` | Channel banner dropdown: gates "Audit Log" on `VIEW_AUDIT_LOG` (line 88), opens dialog (line 139) |

## Implementation Details

### Permission Gating
The "Audit Log" menu item only appears if the user has the `VIEW_AUDIT_LOG` permission for the space. Both `guild_icon.gd` (line 179) and `banner.gd` (line 88) check `Client.has_permission(space_id, AccordPermission.VIEW_AUDIT_LOG)` before adding the item. The permission constant is defined in `permission.gd` (line 13) as the string `"view_audit_log"`.

### Dialog Lifecycle
`AuditLogDialog` extends `ColorRect` and acts as a fullscreen modal overlay with a semi-transparent black backdrop (`Color(0, 0, 0, 0.6)`). Clicking the backdrop or pressing Escape closes the dialog via `queue_free()` (lines 143-153).

The dialog is instantiated and added to the scene tree root:
- `guild_icon.gd` (line 252): `AuditLogScene.instantiate()` -> `get_tree().root.add_child(dialog)` -> `dialog.setup(space_id)`
- `banner.gd` (line 139): identical pattern.

### Pagination
`_fetch_page()` (line 57) sends `GET /spaces/{id}/audit-log` with a `limit` of `PAGE_SIZE` (25, line 5). If a previous page was loaded, the `before` parameter is set to `_last_entry_id` for cursor-based pagination. The response is expected to be an array of entry dictionaries.

After receiving entries, if the count equals `PAGE_SIZE`, `_has_more` is set to `true` and the "Load More" button becomes visible (lines 89-90). Clicking "Load More" calls `_fetch_page()` again, appending entries to `_all_entries` and advancing the cursor.

### Action Type Filtering
The filter dropdown (`_filter_option`) is populated in `_ready()` (lines 26-40) with 15 options:
- All Actions, Member Kick, Member Ban Add, Member Ban Remove, Member Update, Role Create, Role Update, Role Delete, Channel Create, Channel Update, Channel Delete, Invite Create, Invite Delete, Message Delete, Space Update

`_get_selected_action_type()` (line 107) maps the selected index to an action type string (e.g. `"member_kick"`, `"role_create"`). When a filter is selected, `_on_filter_changed()` (line 133) calls `_load_entries()` which clears all cached entries and re-fetches from page 1 with the `action_type` query parameter.

### Client-Side Search
`_on_search_changed()` (line 119) filters the already-fetched `_all_entries` array by checking if the query appears (case-insensitive) in the entry's `action_type`, `user_id`, or `reason`. This is local-only and does not re-fetch from the server.

### Row Rendering
Each `AuditLogRow` (line 103) is instantiated from `audit_log_row.tscn` and set up with an entry dictionary via `setup()` (audit_log_row.gd, line 28):

- **Icon**: emoji from `_ACTION_ICONS` dictionary (lines 3-19), keyed by action type (e.g. member_kick -> door emoji, member_ban_add -> hammer emoji).
- **User**: `_resolve_user()` (line 45) looks up the user ID in the current space's member list via `Client.get_members_for_space()`. Falls back to the raw user ID if no member match.
- **Action**: `_format_action()` (line 41) replaces underscores with spaces and capitalizes.
- **Target**: `_format_target()` (line 57) abbreviates the target ID by type (e.g. `"user:1234"`, `"role:5678"`, `"ch:9012"`), showing only the last 4-6 characters.
- **Time**: `_relative_time()` (line 73) computes time differences with thresholds: "just now" (<60s), "Xm ago" (<1h), "Xh ago" (<1d), "Xd ago" (<7d), then falls back to the date string (first 10 characters).

### AccordKit Model
`AccordAuditLogEntry` (audit_log_entry.gd) is a `RefCounted` model with fields: `id`, `user_id`, `action_type`, `target_id`, `target_type`, `reason`, `changes` (Array), `created_at`. It has `from_dict()` / `to_dict()` conversions. Note: the dialog currently works with raw dictionaries from the REST response rather than converting to `AccordAuditLogEntry` objects.

### REST API
`AuditLogsApi.list()` (audit_logs_api.gd, line 15) sends `GET /spaces/{space_id}/audit-log` with optional query parameters (`limit`, `before`, `user_id`, `action_type`). Returns a `RestResult` whose `data` is expected to be an array of entry dictionaries.

`ClientAdmin.get_audit_log()` (client_admin.gd, line 198) routes the call to the correct `AccordClient` for the given space ID.

## Implementation Status
- [x] Permission gating via `VIEW_AUDIT_LOG`
- [x] Entry point from space icon context menu
- [x] Entry point from channel banner dropdown
- [x] Paginated fetching with cursor-based "Load More"
- [x] Action type filter dropdown (15 action types)
- [x] Client-side search by action, user ID, or reason
- [x] Row rendering with emoji icons, user resolution, relative timestamps
- [x] Error display on fetch failure
- [x] Empty state label
- [x] Modal close via button, backdrop click, and Escape key
- [x] AccordKit model (`AccordAuditLogEntry`) and REST endpoint (`AuditLogsApi`)
- [ ] Real-time updates via gateway events
- [ ] User-id-based server-side search
- [ ] Expandable detail view for change diffs
- [ ] Date range filtering
- [ ] Export/download audit log

## Tasks

### AUDIT-1: No gateway event for new audit log entries
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** api, gateway, ui
- **Notes:** The dialog fetches data on open but has no mechanism to receive real-time updates. A new entry created while the dialog is open won't appear until the user re-opens or changes filters.

### AUDIT-2: AccordAuditLogEntry model unused
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** `audit_log_entry.gd` defines a typed model with `from_dict()`, but `audit_log_dialog.gd` works directly with raw dictionaries from `result.data` (line 84). The model could be used for type safety.

### AUDIT-3: Search is client-side only
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, ui
- **Notes:** `_on_search_changed()` (audit_log_dialog.gd, line 119) filters the in-memory `_all_entries` array. If only one page was loaded, search can't find entries on unfetched pages. The `AuditLogsApi.list()` endpoint supports a `user_id` query param but the dialog doesn't use it for server-side search.

### AUDIT-4: User resolution falls back to raw ID
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** performance
- **Notes:** `_resolve_user()` (audit_log_row.gd, line 45) only checks the current space's member cache. If the acting user has left the server, the row displays a raw snowflake ID instead of a username.

### AUDIT-5: Target names not resolved
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** performance, permissions
- **Notes:** `_format_target()` (audit_log_row.gd, line 57) shows abbreviated IDs (e.g. `"role:1234"`) rather than resolving target names from cache (role names, channel names, usernames).

### AUDIT-6: No change diff display
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** ci, permissions, ui
- **Notes:** The `AccordAuditLogEntry` model has a `changes` array field, but the row UI does not render it. Admins can't see what specifically changed (e.g. which role permission was toggled, what the channel name was changed to).

### AUDIT-7: No date range filter
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Only action type filtering is supported. There's no way to filter entries by date range (e.g. "last 24 hours", "last week").

### AUDIT-8: `admin_server_management.md` gap entry is stale
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, ui
- **Notes:** Line 590 of `admin_server_management.md` says "no audit log API endpoints or UI exist" but both now exist. The gap entry should be removed or updated.
