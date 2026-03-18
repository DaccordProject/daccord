# Administrative User Management

Priority: 19
Depends on: Role-Based Permissions, User Management

## Overview

Administrative user management covers the permission-gated actions that server admins and moderators perform on members: kicking, banning (with optional reasons and message purge), unbanning (single and bulk), assigning/removing roles, moderating (timeout/mute/deafen), editing nicknames, and reporting users or messages. The flow spans three entry points — the member list context menu, the space icon admin submenu, and the channel banner admin dropdown — all routed through a `ClientAdmin` delegation layer that calls AccordKit REST endpoints, refreshes caches, and emits AppState signals for real-time UI updates. All dialogs extend `ModalBase` for consistent overlay behavior, responsive sizing, and shared input handling.

## User Steps

### Kicking a Member
1. Admin right-clicks a member in the member list (context menu suppressed for self, line 75 of `member_item.gd`).
2. "Kick" option appears if user has `kick_members` permission (line 116).
3. Admin clicks "Kick" — `DialogHelper.confirm()` opens a ConfirmDialog with danger styling and the message "Are you sure you want to kick [name]?" (lines 219-234).
4. On confirm, `Client.admin.kick_member()` sends `DELETE /spaces/{id}/members/{uid}` (line 208 of `client_admin.gd`).
5. On success, member cache is refreshed; gateway broadcasts `member_leave` to all connected clients.

### Banning a Member
1. Admin right-clicks a member in the member list.
2. "Ban" option appears if user has `ban_members` permission (line 120 of `member_item.gd`).
3. Admin clicks "Ban" — `DialogHelper.open()` opens a BanDialog (lines 204-207).
4. The BanDialog shows a reason input, a purge duration dropdown (7 options from "Don't delete any" to "Last 7 days"), and a "Ban" button.
5. First click on "Ban" enters a confirmation step: inputs are locked, a summary label shows the ban details, and the button changes to "Confirm Ban" (lines 46-60 of `ban_dialog.gd`).
6. Second click executes the ban — `Client.admin.ban_member()` sends `PUT /spaces/{id}/bans/{uid}` with optional `reason` and `delete_message_seconds` (line 220 of `client_admin.gd`).
7. On success, member cache is refreshed and `AppState.bans_updated` is emitted (line 233); gateway broadcasts `ban_create` and `member_leave`.
8. On failure, an error message is displayed and the confirmation state resets (lines 79-84 of `ban_dialog.gd`).

### Viewing and Managing Bans
1. Admin opens the ban list via space icon right-click > Administration > "Bans" (requires `ban_members`, line 185 of `guild_icon.gd`) or channel banner dropdown > "Bans" (line 74 of `banner.gd`).
2. The BanListDialog loads all bans via `Client.admin.get_bans()` (line 55 of `ban_list_dialog.gd`).
3. Each ban row shows a checkbox, username, optional reason label, and an "Unban" button.
4. Admin can search/filter bans by username (line 107).
5. Admin unbans a single user via the row's "Unban" button — shows ConfirmDialog, then calls `Client.admin.unban_member()` (lines 167-178).
6. Admin selects multiple bans via checkboxes, optionally using "Select All" (line 125), then clicks "Unban Selected (N)" for bulk unban with confirmation (lines 142-165).
7. `AppState.bans_updated` triggers a reload of the ban list (line 185).
8. Pagination: 25 bans per page with "Load More" button using cursor-based `after` parameter (lines 50-77).

### Moderating a Member (Timeout/Mute/Deafen)
1. Admin right-clicks a member in the member list.
2. "Moderate" option appears if user has `moderate_members` permission (line 124 of `member_item.gd`).
3. Admin clicks "Moderate" — `DialogHelper.open()` opens a ModerateMemberDialog (lines 208-211).
4. The dialog shows: a duration dropdown (60s, 5m, 10m, 1h, 1d, 1w), a "Remove Timeout" button (visible only if member is currently timed out), mute and deafen checkboxes, and an "Apply" button.
5. On apply, `Client.admin.update_member()` sends `PATCH /spaces/{id}/members/{uid}` with `mute`, `deaf`, and `communication_disabled_until` fields (line 276 of `client_admin.gd`).
6. "Remove Timeout" sends an empty `communication_disabled_until` to clear the timeout (lines 84-97 of `moderate_member_dialog.gd`).

### Editing a Member's Nickname
1. Admin right-clicks a member in the member list.
2. "Edit Nickname" option appears if user has `manage_nicknames` permission (line 128 of `member_item.gd`).
3. Admin clicks "Edit Nickname" — `DialogHelper.open()` opens a NicknameDialog (lines 212-216).
4. The dialog shows the current nickname (or placeholder with display name), a "Reset" button, and a "Save" button.
5. On save, `Client.admin.update_member()` sends `PATCH /spaces/{id}/members/{uid}` with `nick` field (line 47 of `nickname_dialog.gd`).
6. Reset clears the input and immediately saves (line 62).

### Reporting a User
1. Admin (or any user) right-clicks a member in the member list.
2. "Report" option always appears (line 113 of `member_item.gd`).
3. User clicks "Report" — `DialogHelper.open()` opens a ReportDialog configured for user reporting (lines 198-201).
4. The dialog shows a category dropdown (CSAM, Terrorism, Fraud, Hate, Violence, Self-harm, Other), a description text area, and a "Submit Report" button.
5. On submit, `Client.admin.create_report()` sends a report to the server (line 554 of `client_admin.gd`).
6. On success, a "Report submitted" confirmation is shown for 1.5s, then the dialog auto-closes (lines 86-92 of `report_dialog.gd`).

### Assigning/Removing Roles via Member Context Menu
1. Admin right-clicks a member in the member list.
2. Role checkboxes appear under a "Roles" separator if user has `manage_roles` permission (line 132 of `member_item.gd`). The @everyone role (position 0) is skipped (line 141). Roles at or above the user's highest role are disabled with a tooltip (lines 149-154).
3. Admin checks/unchecks a role — `_toggle_role()` (line 236) calls `Client.admin.add_member_role()` or `remove_member_role()`.
4. The menu item is disabled during the API call (line 252) to prevent double-toggling.
5. On success: green flash feedback (line 266). On failure: red flash and checkbox reverted (lines 268-272).

### Managing Roles via Role Management Dialog
1. Admin opens the role management dialog via space icon right-click > Administration > "Roles" (requires `manage_roles`, line 182 of `guild_icon.gd`) or channel banner dropdown > "Roles" (line 70 of `banner.gd`).
2. Left panel shows all roles sorted by position (descending), with up/down reorder buttons, member count badges, and a search input.
3. Admin clicks a role to open the editor panel (right side) showing name, color picker, hoist, mentionable, and all permission checkboxes built dynamically from `AccordPermission.all()` (lines 60-67 of `role_management_dialog.gd`).
4. Roles at or above the user's highest role have the editor disabled with an error message (lines 179-194).
5. Admin creates a new role via "New Role" button — calls `Client.admin.create_role()` with `{"name": "New Role"}` (line 198).
6. Admin edits role properties and clicks "Save" — calls `Client.admin.update_role()` with name, color, hoist, mentionable, and permissions array (lines 209-236).
7. Admin deletes a role via "Delete" button with ConfirmDialog (lines 238-258). The @everyone role cannot be deleted (line 177).
8. Admin reorders roles via up/down arrows — swaps positions and calls `Client.admin.reorder_roles()` (lines 124-153). The @everyone role stays at position 0.
9. Closing with unsaved changes shows an "Unsaved Changes" confirmation prompt via `_try_close_dirty()` (lines 264-265).

### Viewing and Managing Reports
1. Admin opens the report list via space icon right-click > Administration > "Reports" (requires `moderate_members`, line 197 of `guild_icon.gd`) or channel banner dropdown > "Reports" (line 90 of `banner.gd`).
2. The ReportListDialog loads all reports via `Client.admin.get_reports()` (line 77 of `report_list_dialog.gd`).
3. Reports can be filtered by status: All, Pending, Actioned, Dismissed (lines 29-32).
4. Each report row shows category, target (user or message preview), status (color-coded), timestamp, description, and reporter name.
5. For pending reports, an action menu offers: Mark Reviewed, Delete Message (for message reports), Kick User, Ban User (lines 120-134 of `report_row.gd`).
6. "Dismiss" button resolves the report with "dismissed" status (line 236 of `report_list_dialog.gd`).
7. Server-wide reports view (`setup_server_wide()`) aggregates reports from all spaces, sorted by time (lines 41-52, 100-126).
8. Pagination: 25 reports per page with cursor-based `before` parameter (lines 68-98).

### Viewing the Audit Log
1. Admin opens the audit log via space icon right-click > Administration > "Audit Log" (requires `view_audit_log`, line 194 of `guild_icon.gd`) or channel banner dropdown > "Audit Log" (line 86 of `banner.gd`).
2. The AuditLogDialog loads entries via `Client.admin.get_audit_log()` (line 66 of `audit_log_dialog.gd`).
3. Each row shows an action icon (emoji), user name (resolved from member cache), formatted action type, target (truncated ID with type prefix), and relative timestamp.
4. Admin can search entries by action type, user ID, or reason text (lines 113-125).
5. Admin can filter by action type via the dropdown — 15 action types from "Member Kick" to "Space Update" (lines 27-41).
6. Pagination loads 25 entries per page with a "Load More" button using cursor-based `before` parameter (lines 57-86).

## Signal Flow

```
Member Kick:
  member_item._on_context_menu_id_pressed("Kick")
    -> DialogHelper.confirm(ConfirmDialogScene, ...)    [member_item.gd:219]
    -> ConfirmDialog.confirmed
    -> Client.admin.kick_member(space_id, user_id)      [client_admin.gd:208]
      -> AccordClient.members.kick(space_id, user_id)   [members_api.gd]
        -> DELETE /spaces/{id}/members/{uid}
      -> Client.fetch.fetch_members(space_id)            [client_admin.gd:217]
      -> Gateway: member_leave
        -> ClientGatewayMembers.on_member_leave()        [client_gateway_members.gd:75]
          -> _member_cache[space_id] remove user
          -> AppState.member_left(space_id, user_id)
          -> AppState.members_updated(space_id)
            -> member_list._on_members_updated()         [member_list.gd]

Member Ban:
  member_item._on_context_menu_id_pressed("Ban")
    -> DialogHelper.open(BanDialogScene, ...)            [member_item.gd:205]
    -> BanDialog._on_ban_pressed() (x2: confirm step)   [ban_dialog.gd:43]
      -> Client.admin.ban_member(space_id, user_id, data) [client_admin.gd:220]
        -> AccordClient.bans.create(space_id, user_id, data) [bans_api.gd]
          -> PUT /spaces/{id}/bans/{uid}
        -> Client.fetch.fetch_members(space_id)          [client_admin.gd:232]
        -> AppState.bans_updated(space_id)               [client_admin.gd:233]
      -> Gateway: ban_create + member_leave
        -> ClientGatewayEvents.on_ban_create()           [client_gateway_events.gd:14]
          -> _ban_cache[space_id] append
          -> AppState.bans_updated(space_id)
        -> ClientGatewayMembers.on_member_leave()        [client_gateway_members.gd:75]
          -> AppState.members_updated(space_id)

Unban (single or bulk):
  ban_list_dialog._on_unban() / _on_bulk_unban()
    -> ConfirmDialog.confirmed
    -> Client.admin.unban_member(space_id, user_id)      [client_admin.gd:236]
      -> AccordClient.bans.remove(space_id, user_id)     [bans_api.gd]
        -> DELETE /spaces/{id}/bans/{uid}
      -> AppState.bans_updated(space_id)                 [client_admin.gd:245]
      -> Gateway: ban_delete
        -> ClientGatewayEvents.on_ban_delete()           [client_gateway_events.gd:30]
          -> _ban_cache[space_id] remove
          -> AppState.bans_updated(space_id)
    -> ban_list_dialog._on_bans_updated()                [ban_list_dialog.gd:185]
      -> _load_bans() (refresh list)

Moderate Member (timeout/mute/deafen):
  member_item._on_context_menu_id_pressed("Moderate")
    -> DialogHelper.open(ModerateMemberDialogScene, ...) [member_item.gd:209]
    -> ModerateMemberDialog._on_apply()                  [moderate_member_dialog.gd:52]
      -> Client.admin.update_member(space_id, uid, data) [client_admin.gd:276]
        -> AccordClient.members.update(space_id, uid, data)
          -> PATCH /spaces/{id}/members/{uid}
        -> Client.fetch.fetch_members(space_id)          [client_admin.gd:287]
      -> Gateway: member_update
        -> ClientGatewayMembers.on_member_update()       [client_gateway_members.gd:98]
          -> _member_cache[space_id] update
          -> AppState.members_updated(space_id)

Edit Nickname:
  member_item._on_context_menu_id_pressed("Edit Nickname")
    -> DialogHelper.open(NicknameDialogScene, ...)       [member_item.gd:213]
    -> NicknameDialog._on_save()                         [nickname_dialog.gd:39]
      -> Client.admin.update_member(space_id, uid, data) [client_admin.gd:276]
        -> PATCH /spaces/{id}/members/{uid}
      -> Gateway: member_update -> AppState.members_updated

Report User:
  member_item._on_context_menu_id_pressed("Report")
    -> DialogHelper.open(ReportDialogScene, ...)         [member_item.gd:199]
    -> ReportDialog._on_submit()                         [report_dialog.gd:53]
      -> Client.admin.create_report(space_id, data)      [client_admin.gd:554]
        -> POST /spaces/{id}/reports
      -> Gateway: report_create
        -> ClientGatewayEvents.on_report_create()        [client_gateway_events.gd:44]
          -> AppState.reports_updated(space_id)

Report Management:
  space_icon/banner -> "Reports" menu item
    -> ReportListDialog.setup(space_id)                  [report_list_dialog.gd:34]
      -> Client.admin.get_reports(space_id, query)       [client_admin.gd:563]
        -> GET /spaces/{id}/reports?limit=25
      -> _rebuild_list()
        -> ReportRow.setup(report_dict)                  [report_row.gd:39]
    -> ReportRow.actioned(report_id, action_type)        [report_row.gd:3]
      -> report_list_dialog._on_action_report()          [report_list_dialog.gd:165]
        -> Client.admin.resolve_report(sid, id, data)    [client_admin.gd:572]
          -> PATCH /spaces/{id}/reports/{rid}
        -> Optional: Client.admin.kick_member() / ban_member()
    -> ReportRow.dismissed(report_id)
      -> report_list_dialog._on_dismiss_report()         [report_list_dialog.gd:236]
        -> Client.admin.resolve_report(sid, id, {status: "dismissed"})

Role Toggle (member context menu):
  member_item._toggle_role(space_id, user_id, id)        [member_item.gd:236]
    -> Client.admin.add_member_role() / remove_member_role() [client_admin.gd:248/262]
      -> PUT/DELETE /spaces/{id}/members/{uid}/roles/{rid}
      -> Client.fetch.fetch_members(space_id)            [client_admin.gd:259/273]
    -> Gateway: member_update
      -> ClientGatewayMembers.on_member_update()         [client_gateway_members.gd:98]
        -> _member_cache[space_id] update member dict
        -> AppState.members_updated(space_id)
    -> _flash_feedback(green/red)                        [member_item.gd:274]

Role CRUD (role management dialog):
  role_management_dialog._on_new_role() / _on_save() / _on_delete()
    -> Client.admin.create_role() / update_role() / delete_role()
                                                         [client_admin.gd:170/182/196]
      -> POST/PATCH/DELETE /spaces/{id}/roles/{rid}
      -> Client.fetch.fetch_roles(space_id)
    -> Gateway: role_create / role_update / role_delete
      -> ClientGateway.on_role_create/update/delete()    [client_gateway.gd:714/725/739]
        -> _role_cache[space_id] add/update/remove
        -> AppState.roles_updated(space_id)
    -> role_management_dialog._on_roles_updated()        [role_management_dialog.gd:260]
      -> _rebuild_role_list()

Audit Log:
  space_icon/banner -> "Audit Log" menu item
    -> AuditLogDialog.setup(space_id)                    [audit_log_dialog.gd:43]
      -> Client.admin.get_audit_log(space_id, query)     [client_admin.gd:290]
        -> AccordClient.audit_logs.list(space_id, query) [audit_logs_api.gd]
          -> GET /spaces/{id}/audit-log?limit=25
      -> _rebuild_list(entries)
        -> AuditLogRow.setup(entry_dict)                 [audit_log_row.gd:38]
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_admin.gd` | Admin API delegation layer: `kick_member()` (line 208), `ban_member()` (line 220), `unban_member()` (line 236), `add_member_role()` (line 248), `remove_member_role()` (line 262), `update_member()` (line 276), `get_audit_log()` (line 290), `get_bans()` (line 299), `create_role()` (line 170), `update_role()` (line 182), `delete_role()` (line 196), `reorder_roles()` (line 494), `create_report()` (line 554), `get_reports()` (line 563), `resolve_report()` (line 572) |
| `scripts/autoload/client.gd` | `has_permission()` (line 690), `is_space_owner()` (line 703), `get_my_highest_role_position()` (line 706), `get_role_color_for_user()` (line 711), `get_members_for_space()`, `get_roles_for_space()`, member/role caches |
| `scripts/autoload/client_gateway_members.gd` | `on_member_join()` (line 44), `on_member_leave()` (line 75), `on_member_update()` (line 98) — split from main gateway file |
| `scripts/autoload/client_gateway_events.gd` | `on_ban_create()` (line 14), `on_ban_delete()` (line 30), `on_report_create()` (line 44), `on_invite_create()` (line 50), `on_invite_delete()` (line 67) |
| `scripts/autoload/client_gateway.gd` | `on_role_create()` (line 714), `on_role_update()` (line 725), `on_role_delete()` (line 739) |
| `scripts/autoload/app_state.gd` | `members_updated` (line 30), `member_joined` (line 32), `member_left` (line 34), `roles_updated` (line 38), `bans_updated` (line 40), `reports_updated` (line 42), `invites_updated` (line 44) signals |
| `scenes/common/modal_base.gd` | Base class for all modal dialogs: `_bind_modal_nodes()`, `_show_rest_error()`, `_with_button_loading()`, `_clear_children()`, `_try_close_dirty()`, overlay close, Escape close, responsive sizing |
| `scripts/helpers/dialog_helper.gd` | Static helpers: `open()` (instantiate + add to tree), `confirm()` (open + setup + connect confirmed signal) |
| `scenes/members/member_item.gd` | Member context menu with Message, Friend actions, Block, Report, Kick/Ban/Moderate/Edit Nickname/Role actions (lines 72-272) |
| `scenes/members/member_list.gd` | Virtual-scrolling member list, status grouping, invite button |
| `scenes/admin/ban_dialog.gd` | Two-step ban dialog with reason input, purge duration dropdown (7 options), summary preview, error handling (lines 1-88) |
| `scenes/admin/ban_list_dialog.gd` | Ban list with search, single/bulk unban, cursor-based pagination (25/page), error tracking (lines 1-189) |
| `scenes/admin/ban_row.gd` | Individual ban row with checkbox, username, reason, unban button (lines 1-38) |
| `scenes/admin/role_management_dialog.gd` | Two-panel role editor with all permissions, create/save/delete, search, reorder, member count badges, hierarchy enforcement (lines 1-279) |
| `scenes/admin/role_row.gd` | Role row with up/down reorder buttons, color display, member count label (lines 1-42) |
| `scenes/admin/moderate_member_dialog.gd` | Timeout/mute/deafen dialog with 6 duration options, remove timeout button (lines 1-98) |
| `scenes/admin/nickname_dialog.gd` | Nickname editing dialog with reset button (lines 1-78) |
| `scenes/admin/report_dialog.gd` | User/message reporting dialog with 7 category options, description input, success auto-close (lines 1-99) |
| `scenes/admin/report_list_dialog.gd` | Report management dialog with status filter, pagination, action/dismiss controls, server-wide mode (lines 1-251) |
| `scenes/admin/report_row.gd` | Report row with category, target resolution, status coloring, action menu (reviewed/delete/kick/ban), dismiss button (lines 1-163) |
| `scenes/admin/audit_log_dialog.gd` | Audit log viewer with 15 action type filters, search, cursor-based pagination (lines 1-134) |
| `scenes/admin/audit_log_row.gd` | Audit log row with 20 action icons, user resolution from member cache, relative timestamps (lines 1-106) |
| `scenes/admin/confirm_dialog.gd` | Reusable confirm dialog with `confirmed` signal, danger mode styling via `ThemeManager.style_button()` (lines 1-36) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space icon right-click: Administration submenu with "Roles" (line 182), "Bans" (line 185), "Audit Log" (line 194), "Reports" (line 197), plus Channels, Invites, Emojis, Soundboard, Plugins, View As |
| `scenes/sidebar/channels/banner.gd` | Channel banner admin dropdown: "Roles" (line 70), "Bans" (line 74), "Audit Log" (line 86), "Reports" (line 90) |
| `addons/accordkit/rest/endpoints/members_api.gd` | Member REST: `kick()`, `add_role()`, `remove_role()`, `update()` |
| `addons/accordkit/rest/endpoints/bans_api.gd` | Ban REST: `list()`, `create()`, `remove()` |
| `addons/accordkit/rest/endpoints/roles_api.gd` | Role REST: `create()`, `update()`, `delete()`, `reorder()` |
| `addons/accordkit/rest/endpoints/audit_logs_api.gd` | Audit log REST: `list(space_id, query)` → `GET /spaces/{id}/audit-log` |
| `addons/accordkit/models/audit_log_entry.gd` | `AccordAuditLogEntry` model with `from_dict()` / `to_dict()` |
| `addons/accordkit/models/permission.gd` | Permission constants including `KICK_MEMBERS`, `BAN_MEMBERS`, `MANAGE_ROLES`, `MODERATE_MEMBERS`, `MANAGE_NICKNAMES`, `VIEW_AUDIT_LOG`; `has()` check with `administrator` wildcard |

## Implementation Details

### ModalBase Dialog Architecture

All admin dialogs extend `ModalBase` (`scenes/common/modal_base.gd`), which extends `ColorRect`. ModalBase provides:

- **`_bind_modal_nodes(panel, width, height)`** (line 97) — For scene-based modals, enables responsive sizing and shared close behavior.
- **`_show_rest_error(result, fallback)`** (line 127) — Displays error on `_error_label` if a REST call fails, returns `true` on error.
- **`_with_button_loading(btn, text, action)`** (line 141) — Disables a button and shows "Loading..." during an async action.
- **`_clear_children(container)`** (line 153) — Removes all children from a container.
- **`_try_close_dirty(dirty, confirm_scene)`** (line 160) — Shows "Unsaved Changes" discard prompt if dirty.
- **Close behavior** — Overlay click (line 187), Escape key (line 193), and explicit `_close()` (line 182) all emit `closed` and `queue_free()`.
- **Responsive sizing** — Panels shrink to fit viewport with 16px margins (lines 199-224).

### DialogHelper

`DialogHelper` (`scripts/helpers/dialog_helper.gd`) provides static helpers used throughout `member_item.gd`:

- **`open(scene, tree)`** (line 9) — Instantiates a dialog and adds it to the scene tree root. Returns the dialog node for chained `.setup()` calls.
- **`confirm(scene, tree, title, message, confirm_text, danger, callback)`** (line 17) — Opens a ConfirmDialog with full setup and connects the `confirmed` signal to a callback.

### ClientAdmin Delegation Layer

`ClientAdmin` (`scripts/autoload/client_admin.gd`) is a `RefCounted` wrapper that holds a reference to the `Client` autoload node (line 8). Each method follows the same pattern:

1. Resolve the `AccordClient` for the space via `_c._client_for_space()`.
2. Call the corresponding AccordKit REST endpoint.
3. On success, refresh the relevant cache (e.g., `_c.fetch.fetch_members()`) and emit AppState signals.
4. Return the `RestResult`.

User management methods:
- `kick_member(space_id, user_id)` (line 208) — `DELETE /spaces/{id}/members/{uid}`, refreshes member cache.
- `ban_member(space_id, user_id, data)` (line 220) — `PUT /spaces/{id}/bans/{uid}`, refreshes member cache, emits `bans_updated`.
- `unban_member(space_id, user_id)` (line 236) — `DELETE /spaces/{id}/bans/{uid}`, emits `bans_updated`.
- `add_member_role(space_id, user_id, role_id)` (line 248) — `PUT /spaces/{id}/members/{uid}/roles/{rid}`, refreshes member cache.
- `remove_member_role(space_id, user_id, role_id)` (line 262) — `DELETE /spaces/{id}/members/{uid}/roles/{rid}`, refreshes member cache.
- `update_member(space_id, user_id, data)` (line 276) — `PATCH /spaces/{id}/members/{uid}`, refreshes member cache. Used for nickname, mute, deaf, and timeout.
- `get_audit_log(space_id, query)` (line 290) — `GET /spaces/{id}/audit-log`, returns raw result.
- `get_bans(space_id, query)` (line 299) — `GET /spaces/{id}/bans` with pagination. Replaces ban cache on first page, appends on subsequent pages (lines 308-316).
- `create_report(space_id, data)` (line 554) — `POST /spaces/{id}/reports`, returns raw result.
- `get_reports(space_id, query)` (line 563) — `GET /spaces/{id}/reports`, returns raw result.
- `resolve_report(space_id, report_id, data)` (line 572) — Resolves a report, emits `reports_updated`.

### Permission Checking

`Client.has_permission()` (line 690 of `client.gd`) resolves permissions in priority order:

1. **Instance admin**: If `current_user["is_admin"]` is true, all permissions are granted.
2. **Space owner**: If `space.owner_id == current_user.id`, all permissions are granted.
3. **Role-based**: Collects all permissions from the @everyone role (position 0) and the user's assigned roles. Uses `AccordPermission.has()` which also checks for the `administrator` permission as a wildcard.

The member context menu suppresses actions on the current user (line 75 of `member_item.gd`) and hides admin actions when the user lacks the relevant permission.

### Ban Dialog

`ban_dialog.gd` extends `ModalBase`. Key behavior:
- `setup(space_id, user_id, display_name)` (line 36) sets the title to "Ban [name]".
- **Two-step confirmation**: First press (line 46) locks inputs, shows summary label with ban details (target, reason, purge duration), and changes button to "Confirm Ban". Second press executes the ban.
- **Purge options** (`PURGE_OPTIONS`, line 5): 7 durations from 0 (no purge) to 604800 (7 days). The selected duration is sent as `delete_message_seconds` in the ban request.
- The reason input supports Enter to submit (line 32 via `text_submitted`).
- On success, emits `ban_confirmed(user_id, reason)` (line 86) and closes.
- On failure, displays the server error message and resets the confirmation state (lines 79-84).

### Ban List Dialog

`ban_list_dialog.gd` extends `ModalBase`. Key behavior:
- `_fetch_page()` (line 50) fetches 25 bans per page with optional `after` cursor for pagination.
- Each `BanRow` (`ban_row.gd`) shows a checkbox, username, optional reason label, and an "Unban" button (lines 19-38). User data is extracted from nested `user` dict or flat `user_id` field.
- Search filters by username using case-insensitive `contains()` (lines 107-116).
- Row selection is tracked in `_selected_user_ids` array (line 10). The bulk bar shows "Unban Selected (N)" when selections exist (lines 137-140).
- `_on_select_all()` (line 125) toggles all checkboxes and updates `_selected_user_ids`.
- `_on_bulk_unban()` (line 142) shows a ConfirmDialog, then loops through selected IDs calling `unban_member()` sequentially with `await`. Failed unbans are counted and displayed as an error (lines 154-164).
- Listens to `AppState.bans_updated` (line 32) to auto-refresh after any ban/unban operation (line 185).

### Role Management Dialog

`role_management_dialog.gd` extends `ModalBase`. Two-panel layout:
- **Left panel**: Role list sorted by position descending (line 76), each with a `RoleRow` showing colored role name, up/down reorder buttons, and member count badge. The @everyone role's reorder buttons are disabled (line 26 of `role_row.gd`).
- **Right panel**: Editor shown when a role is selected (line 157). Contains name input, color picker, hoist checkbox, mentionable checkbox, and all permission checkboxes built dynamically from `AccordPermission.all()` (lines 60-67).
- **Member count**: `_compute_role_member_counts()` (line 97) iterates all members and counts role assignments.

State tracking:
- `_dirty: bool` (line 10) is set to `true` by input signal callbacks (lines 51-54, 65).
- `_dirty` is reset to `false` after save (line 236) or role selection (lines 159, 196).
- `_try_close()` (line 264) delegates to `_try_close_dirty()` from ModalBase.

Role hierarchy enforcement:
- `_select_role()` (line 155) disables all editor controls and shows an error for roles at or above the user's highest position (lines 179-194).
- `_on_move_role()` (line 124) prevents reordering roles at or above the user's own (lines 136-142).
- Builds a two-element reorder array with swapped position values (lines 147-150).

### Moderate Member Dialog

`moderate_member_dialog.gd` extends `ModalBase`. Key behavior:
- 6 timeout duration options (`DURATIONS`, line 4): 60s, 5m, 10m, 1h, 1d, 1w.
- `setup()` (line 39) pre-populates mute/deaf checkboxes from existing member data.
- `_on_apply()` (line 52) builds data dict with `mute`, `deaf`, and computed ISO 8601 `communication_disabled_until` timestamp.
- `_on_remove_timeout()` (line 84) sends empty `communication_disabled_until` to clear timeout.

### Report Dialog

`report_dialog.gd` extends `ModalBase`. Key behavior:
- 7 report categories (`CATEGORY_KEYS`, line 3): CSAM, terrorism, fraud, hate, violence, self-harm, other.
- Two setup modes: `setup_message()` (line 38) for message reports, `setup_user()` (line 46) for user reports.
- On submit, builds data with `target_type`, `target_id`, `category`, optional `channel_id` and `description`.
- On success, shows confirmation for 1.5s then auto-closes (lines 86-92).

### Report List Dialog

`report_list_dialog.gd` extends `ModalBase`. Key behavior:
- **Per-space mode** (`setup()`, line 34): Shows reports for one space. Listens to `AppState.reports_updated`.
- **Server-wide mode** (`setup_server_wide()`, line 41): Aggregates reports from all connected spaces, sorted by `created_at` descending. Accessed via "Server Reports" item in guild_icon context menu (instance admin only).
- 4 status filters (lines 29-32): All, Pending, Actioned, Dismissed.
- Cursor-based pagination, 25 per page (lines 68-98).

### Report Row

`report_row.gd` extends `VBoxContainer`. Key behavior:
- Shows category label (7 categories with readable names), target (user name or message preview with author), status (color-coded: yellow=pending, green=actioned, gray=dismissed), relative timestamp, description, and reporter name.
- Target resolution (line 79): For message reports, shows `author: preview...` (truncated at 60 chars). For user reports, resolves user display name.
- Reporter resolution (line 105): Shows "Reported by [name]" if reporter_id is present.
- **Action menu** (lines 120-145): Only visible for pending reports. Offers: Mark Reviewed, Delete Message (message reports only), Kick User, Ban User.
- **Action handling** (lines 165-208 of `report_list_dialog.gd`): "Mark Reviewed" resolves as "reviewed". "Delete Message" calls `Client.remove_message()` then resolves as "message deleted". "Kick" and "Ban" show ConfirmDialog before executing the admin action and resolving the report.
- **Dismiss** (line 236): Resolves the report with status "dismissed".

### Audit Log Dialog

`audit_log_dialog.gd` extends `ModalBase`. Key behavior:
- 15 action type filters (lines 27-41): Member Kick, Ban Add/Remove, Update, Role Create/Update/Delete, Channel Create/Update/Delete, Invite Create/Delete, Message Delete, Space Update.
- Cursor-based pagination using `before` parameter (line 60), 25 entries per page.
- Client-side search filters by action type, user ID, or reason text (lines 113-125).
- Filter change triggers a full reload (line 128).

### Audit Log Row

`audit_log_row.gd` extends `HBoxContainer`. Key behavior:
- 20 action-to-emoji mappings including automod and report actions (lines 3-25).
- User resolution via member cache with fallback to raw user ID (lines 55-64).
- Target formatting with type prefix (user:, role:, ch:) and last 4-6 chars of ID (lines 67-80).
- Relative timestamp thresholds: just now, minutes, hours, days, then falls back to date string (lines 83-105).

### Gateway Event Handlers

Member events (`client_gateway_members.gd`):
- `on_member_join()` (line 44) — Fetches user if not cached, appends `member_to_dict()` to `_member_cache`, updates member ID index, emits `member_joined` and `members_updated`.
- `on_member_leave()` (line 75) — Extracts `user_id` from event data (supports both `user_id` field and nested `user.id`), removes from `_member_cache`, rebuilds index, emits `member_left` and `members_updated`.
- `on_member_update()` (line 98) — Rebuilds `member_to_dict()`, updates or appends in `_member_cache`, updates index, emits `members_updated`.

Role events (`client_gateway.gd`):
- `on_role_create()` (line 714) — Parses `AccordRole.from_dict()`, converts to dict, appends to `_role_cache`, emits `roles_updated`.
- `on_role_update()` (line 725) — Finds and replaces role in `_role_cache` by ID, emits `roles_updated`.
- `on_role_delete()` (line 739) — Finds and removes role from `_role_cache` by ID, emits `roles_updated`.

Ban/report events (`client_gateway_events.gd`):
- `on_ban_create()` (line 14) — Appends ban to `_ban_cache` with duplicate check, emits `bans_updated`.
- `on_ban_delete()` (line 30) — Removes ban from `_ban_cache` by user ID, emits `bans_updated`.
- `on_report_create()` (line 44) — Emits `reports_updated`.

### Role Toggle Feedback

The member context menu role toggle (`_toggle_role()`, line 236 of `member_item.gd`) provides visual feedback:
- The menu item is disabled during the API call (line 252) to prevent double-clicks.
- On success: `_flash_feedback()` (line 274) tweens the member item's `modulate` to a success-tinted color for 0.15s then back over 0.3s. Skipped if `Config.get_reduced_motion()` is true (line 275).
- On failure: error-tinted flash and the checkbox state is reverted to its previous value (line 272).
- Colors are sourced from `ThemeManager.get_color("success")` / `ThemeManager.get_color("error")` with 0.3 alpha.

### Confirm Dialog

`confirm_dialog.gd` extends `ModalBase` with `confirmed` signal (line 3):
- `setup(title, message, confirm_text, danger)` (line 17) configures the dialog.
- When `danger` is true (line 27), `ThemeManager.style_button()` applies error styling to the confirm button.
- Inherits close behavior from ModalBase (overlay click, Escape, cancel/close buttons).

### Member Context Menu

`member_item.gd` builds a dynamic context menu (lines 72-162) with:
- **Always visible**: "Message" (opens DM)
- **Relationship actions**: Add/Remove Friend, Accept/Decline/Cancel Friend Request (lines 89-104)
- **Block/Unblock** (lines 106-111)
- **Report** (always visible, line 113) — opens `ReportDialog` configured for user
- **Permission-gated admin actions**: Kick (`KICK_MEMBERS`, line 116), Ban (`BAN_MEMBERS`, line 120), Moderate (`MODERATE_MEMBERS`, line 124), Edit Nickname (`MANAGE_NICKNAMES`, line 128)
- **Role assignment** (`MANAGE_ROLES`, lines 132-155): Check items with hierarchy enforcement. Roles at/above user's highest are disabled with tooltip.

### Admin Entry Points

Both `guild_icon.gd` and `banner.gd` provide admin entry points via an "Administration" submenu:
- Space Settings (MANAGE_SPACE)
- Channels (MANAGE_CHANNELS)
- Roles (MANAGE_ROLES)
- Bans (BAN_MEMBERS)
- Invites (CREATE_INVITES in guild_icon, MANAGE_CHANNELS in banner)
- Emojis (MANAGE_EMOJIS)
- Audit Log (VIEW_AUDIT_LOG)
- Reports (MODERATE_MEMBERS)
- Soundboard (MANAGE_SOUNDBOARD or USE_SOUNDBOARD)
- Plugins (MANAGE_SPACE, guild_icon only)
- View As... (MANAGE_ROLES, not in imposter mode, guild_icon only)

## Implementation Status

- [x] Kick member with confirmation dialog
- [x] Ban member with optional reason field
- [x] Two-step ban confirmation with summary preview
- [x] Ban message purge duration options (7 levels from none to 7 days)
- [x] Ban dialog error handling and loading state with confirmation reset
- [x] Ban list viewer with search/filter
- [x] Single unban with confirmation
- [x] Bulk unban with select all, confirmation, and error tracking
- [x] Ban list cursor-based pagination (25 per page with Load More)
- [x] Timeout member via Moderate dialog (6 duration options, requires MODERATE_MEMBERS)
- [x] Mute/deafen member via Moderate dialog
- [x] Remove timeout via Moderate dialog
- [x] Member nickname editing via Edit Nickname dialog (requires MANAGE_NICKNAMES)
- [x] User reporting with 7 categories (CSAM, terrorism, fraud, hate, violence, self-harm, other)
- [x] Message reporting (same dialog, different setup method)
- [x] Role assignment via member context menu checkboxes
- [x] Role toggle visual feedback (green/red flash, reduced motion aware)
- [x] Role toggle disabled state during API call
- [x] Role management dialog (create, edit, delete, search, reorder)
- [x] All permission checkboxes in role editor (dynamically from AccordPermission.all())
- [x] Role member count badges in role management dialog
- [x] Unsaved changes warning on role management close
- [x] @everyone role protection (cannot delete, cannot reorder)
- [x] Role hierarchy enforcement (cannot edit/reorder/assign roles at or above own highest)
- [x] Permission-gated context menu items (kick_members, ban_members, manage_roles, moderate_members, manage_nicknames)
- [x] Self-protection (context menu suppressed for own user)
- [x] Permission checking with admin/owner bypass
- [x] Friend/block/report actions in member context menu
- [x] Gateway event handlers for member join/leave/update (in client_gateway_members.gd)
- [x] Gateway event handlers for role create/update/delete (in client_gateway.gd)
- [x] Gateway event handlers for ban create/delete (in client_gateway_events.gd)
- [x] Gateway event handler for report create (in client_gateway_events.gd)
- [x] Ban cache management with duplicate prevention and page append
- [x] Audit log viewer with pagination, search, and 15 action type filters (requires VIEW_AUDIT_LOG)
- [x] Audit log row with 20 action icons, user resolution, relative timestamps
- [x] Administration submenu in space icon context menu (11 items, all permission-gated)
- [x] Administration dropdown in channel banner (9 items, all permission-gated)
- [x] All dialogs extend ModalBase (responsive sizing, overlay/Escape close, error display, button loading)
- [x] DialogHelper for consistent dialog instantiation and confirmation patterns
- [x] Profile card on left-click of member item
- [x] Reusable ConfirmDialog with danger mode (ThemeManager styling)
- [x] Report list dialog with status filter and pagination (requires MODERATE_MEMBERS)
- [x] Report row with action menu (reviewed, delete message, kick, ban) and dismiss
- [x] Server-wide reports view aggregating all spaces (instance admin)
- [x] Report action: delete offending message from report context
- [x] Report action: kick/ban reported user with confirmation dialog
- [x] Gateway event handler for report create (in client_gateway_events.gd)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No audit log entry detail view | Low | Rows show truncated target IDs; clicking a row could show full details with changes/reason |
| No audit log export | Low | No way to export audit log entries for external review |
| Bulk operations lack progress indicator | Low | Bulk unban loops sequentially with no per-item progress; only shows failure count at end |
