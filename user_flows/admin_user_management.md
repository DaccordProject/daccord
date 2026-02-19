# Administrative User Management

> Last touched: 2026-02-19

## Overview

Administrative user management covers the permission-gated actions that server admins and moderators perform on members: kicking, banning (with optional reasons), unbanning (single and bulk), and assigning/removing roles. The flow spans three entry points — the member list context menu, the guild icon/banner admin menus, and the role management dialog — all routed through a `ClientAdmin` delegation layer that calls AccordKit REST endpoints, refreshes caches, and emits AppState signals for real-time UI updates.

## User Steps

### Kicking a Member
1. Admin right-clicks a member in the member list (context menu suppressed for self, line 44 of `member_item.gd`).
2. "Kick" option appears if user has `kick_members` permission (line 58).
3. Admin clicks "Kick" — a ConfirmDialog opens with danger styling and the message "Are you sure you want to kick [name] from this server?" (lines 104-114).
4. On confirm, `Client.admin.kick_member()` sends `DELETE /spaces/{id}/members/{uid}` (line 123 of `client_admin.gd`).
5. On success, member cache is refreshed; gateway broadcasts `member_leave` to all connected clients.

### Banning a Member
1. Admin right-clicks a member in the member list.
2. "Ban" option appears if user has `ban_members` permission (line 62 of `member_item.gd`).
3. Admin clicks "Ban" — a BanDialog opens with a reason input field (line 116-118).
4. Admin optionally enters a ban reason and clicks "Ban" (line 25 of `ban_dialog.gd`).
5. `Client.admin.ban_member()` sends `PUT /spaces/{id}/bans/{uid}` with optional `{"reason": "..."}` (line 136 of `client_admin.gd`).
6. On success, member cache is refreshed and `AppState.bans_updated` is emitted (line 141); gateway broadcasts `ban_create` and `member_leave`.
7. On failure, an error message is displayed in the dialog (lines 39-44 of `ban_dialog.gd`).

### Viewing and Managing Bans
1. Admin opens the ban list via guild icon right-click > "Bans" (requires `ban_members`, line 127 of `guild_icon.gd`) or channel banner dropdown > "Bans" (line 72 of `banner.gd`).
2. The BanListDialog loads all bans via `Client.admin.get_bans()` (line 40 of `ban_list_dialog.gd`).
3. Each ban row shows the username, reason (if any), a checkbox for selection, and an "Unban" button.
4. Admin can search/filter bans by username (line 90).
5. Admin unbans a single user via the row's "Unban" button — shows ConfirmDialog, then calls `Client.admin.unban_member()` (lines 144-155).
6. Admin selects multiple bans via checkboxes, optionally using "Select All" (line 108), then clicks "Unban Selected (N)" for bulk unban with confirmation (lines 125-142).
7. `AppState.bans_updated` triggers a reload of the ban list (line 157).

### Assigning/Removing Roles via Member Context Menu
1. Admin right-clicks a member in the member list.
2. Role checkboxes appear if user has `manage_roles` permission (line 66 of `member_item.gd`). The @everyone role (position 0) is skipped (line 74).
3. Admin checks/unchecks a role — `_toggle_role()` (line 120) calls `Client.admin.add_member_role()` or `remove_member_role()`.
4. The menu item is disabled during the API call (line 136) to prevent double-toggling.
5. On success: green flash feedback (line 148). On failure: red flash and checkbox reverted (lines 149-152).

### Managing Roles via Role Management Dialog
1. Admin opens the role management dialog via guild icon right-click > "Roles" (requires `manage_roles`, line 123 of `guild_icon.gd`) or channel banner dropdown > "Roles" (line 68 of `banner.gd`).
2. Left panel shows all roles sorted by position (descending), with up/down reorder buttons and a search input.
3. Admin clicks a role to open the editor panel (right side) showing name, color picker, hoist, mentionable, and all 37 permission checkboxes (lines 137-160 of `role_management_dialog.gd`).
4. Admin creates a new role via "New Role" button — calls `Client.admin.create_role()` with `{"name": "New Role"}` (line 165).
5. Admin edits role properties and clicks "Save" — calls `Client.admin.update_role()` with name, color, hoist, mentionable, and permissions array (lines 174-208).
6. Admin deletes a role via "Delete" button with ConfirmDialog (lines 210-230). The @everyone role cannot be deleted (line 159).
7. Admin reorders roles via up/down arrows — swaps positions and calls `Client.admin.reorder_roles()` (lines 110-135). The @everyone role stays at position 0.
8. Closing with unsaved changes shows an "Unsaved Changes" confirmation prompt (lines 236-251).

## Signal Flow

```
Member Kick:
  member_item._on_context_menu_id_pressed("Kick")
    -> ConfirmDialog.confirmed
    -> Client.admin.kick_member(guild_id, user_id)           [client_admin.gd:116]
      -> AccordClient.members.kick(guild_id, user_id)        [members_api.gd:62]
        -> DELETE /spaces/{id}/members/{uid}
      -> Client.fetch.fetch_members(guild_id)                [client_admin.gd:125]
      -> Gateway: member_leave
        -> ClientGateway.on_member_leave()                   [client_gateway.gd:355]
          -> _member_cache[guild_id] remove user
          -> AppState.members_updated(guild_id)
            -> member_list._on_members_updated()             [member_list.gd:45]

Member Ban:
  member_item._on_context_menu_id_pressed("Ban")
    -> BanDialog.setup(guild_id, user_id, display_name)
    -> BanDialog._on_ban_pressed()                           [ban_dialog.gd:25]
      -> Client.admin.ban_member(guild_id, user_id, data)    [client_admin.gd:128]
        -> AccordClient.bans.create(guild_id, user_id, data) [bans_api.gd:29]
          -> PUT /spaces/{id}/bans/{uid}
        -> Client.fetch.fetch_members(guild_id)              [client_admin.gd:140]
        -> AppState.bans_updated(guild_id)                   [client_admin.gd:141]
      -> Gateway: ban_create + member_leave
        -> ClientGateway.on_ban_create()                     [client_gateway.gd:513]
          -> AppState.bans_updated(guild_id)
        -> ClientGateway.on_member_leave()                   [client_gateway.gd:355]
          -> AppState.members_updated(guild_id)

Unban (single or bulk):
  ban_list_dialog._on_unban() / _on_bulk_unban()
    -> ConfirmDialog.confirmed
    -> Client.admin.unban_member(guild_id, user_id)          [client_admin.gd:144]
      -> AccordClient.bans.remove(guild_id, user_id)         [bans_api.gd:35]
        -> DELETE /spaces/{id}/bans/{uid}
      -> AppState.bans_updated(guild_id)                     [client_admin.gd:153]
      -> Gateway: ban_delete
        -> ClientGateway.on_ban_delete()                     [client_gateway.gd:519]
          -> AppState.bans_updated(guild_id)
    -> ban_list_dialog._on_bans_updated()                    [ban_list_dialog.gd:157]
      -> _load_bans() (refresh list)

Role Toggle (member context menu):
  member_item._toggle_role(guild_id, user_id, id)            [member_item.gd:120]
    -> Client.admin.add_member_role() / remove_member_role() [client_admin.gd:156/170]
      -> PUT/DELETE /spaces/{id}/members/{uid}/roles/{rid}
      -> Client.fetch.fetch_members(guild_id)                [client_admin.gd:167/181]
    -> Gateway: member_update
      -> ClientGateway.on_member_update()                    [client_gateway.gd:372]
        -> _member_cache[guild_id] update member dict
        -> AppState.members_updated(guild_id)
    -> _flash_feedback(green/red)                            [member_item.gd:154]

Role CRUD (role management dialog):
  role_management_dialog._on_new_role() / _on_save() / _on_delete()
    -> Client.admin.create_role() / update_role() / delete_role()
                                                             [client_admin.gd:78/90/104]
      -> POST/PATCH/DELETE /spaces/{id}/roles/{rid}
      -> Client.fetch.fetch_roles(guild_id)
    -> Gateway: role_create / role_update / role_delete
      -> ClientGateway.on_role_create/update/delete()        [client_gateway.gd:475/486/500]
        -> _role_cache[guild_id] add/update/remove
        -> AppState.roles_updated(guild_id)
    -> role_management_dialog._on_roles_updated()            [role_management_dialog.gd:232]
      -> _rebuild_role_list()
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_admin.gd` | Admin API delegation layer: `kick_member()` (line 116), `ban_member()` (line 128), `unban_member()` (line 144), `add_member_role()` (line 156), `remove_member_role()` (line 170), `get_bans()` (line 184), `create_role()` (line 78), `update_role()` (line 90), `delete_role()` (line 104), `reorder_roles()` (line 355) |
| `scripts/autoload/client.gd` | `has_permission()` (line 513), `is_space_owner()` (line 541), `get_members_for_guild()`, `get_roles_for_guild()`, member/role caches |
| `scripts/autoload/client_gateway.gd` | `on_member_join()` (line 333), `on_member_leave()` (line 355), `on_member_update()` (line 372), `on_role_create()` (line 475), `on_role_update()` (line 486), `on_role_delete()` (line 500), `on_ban_create()` (line 513), `on_ban_delete()` (line 519) |
| `scripts/autoload/app_state.gd` | `members_updated` (line 30), `roles_updated` (line 32), `bans_updated` (line 34) signals |
| `scenes/members/member_item.gd` | Member context menu with Kick/Ban/Role actions (lines 41-158) |
| `scenes/members/member_list.gd` | Virtual-scrolling member list, status grouping, invite button (lines 1-163) |
| `scenes/admin/ban_dialog.gd` | Ban dialog with reason input and error handling (lines 1-60) |
| `scenes/admin/ban_list_dialog.gd` | Ban list with search, single/bulk unban (lines 1-172) |
| `scenes/admin/ban_row.gd` | Individual ban row with checkbox, username, reason, unban button (lines 1-37) |
| `scenes/admin/role_management_dialog.gd` | Two-panel role editor with all 37 permissions, create/save/delete, search, reorder (lines 1-264) |
| `scenes/admin/role_row.gd` | Role row with up/down reorder buttons and color display (lines 1-35) |
| `scenes/admin/confirm_dialog.gd` | Reusable confirm dialog with `confirmed` signal, danger mode styling (lines 1-57) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Guild icon right-click context menu: "Roles" (line 123), "Bans" (line 127) |
| `scenes/sidebar/channels/banner.gd` | Channel banner admin dropdown: "Roles" (line 68), "Bans" (line 72) |
| `addons/accordkit/rest/endpoints/members_api.gd` | Member REST: `kick()` (line 62), `add_role()` (line 76), `remove_role()` (line 86) |
| `addons/accordkit/rest/endpoints/bans_api.gd` | Ban REST: `list()` (line 16), `create()` (line 29), `remove()` (line 35) |
| `addons/accordkit/rest/endpoints/roles_api.gd` | Role REST: `create()` (line 27), `update()` (line 35), `delete()` (line 43), `reorder()` (line 50) |
| `addons/accordkit/models/permission.gd` | 37 permission constants including `KICK_MEMBERS` (line 7), `BAN_MEMBERS` (line 8), `MANAGE_ROLES` (line 33); `has()` check (line 91) |

## Implementation Details

### ClientAdmin Delegation Layer

`ClientAdmin` (`scripts/autoload/client_admin.gd`) is a `RefCounted` wrapper that holds a reference to the `Client` autoload node (line 8). Each method follows the same pattern:

1. Resolve the `AccordClient` for the guild via `_c._client_for_guild()`.
2. Call the corresponding AccordKit REST endpoint.
3. On success, refresh the relevant cache (e.g., `_c.fetch.fetch_members()`) and emit AppState signals.
4. Return the `RestResult`.

User management methods:
- `kick_member(guild_id, user_id)` (line 116) — `DELETE /spaces/{id}/members/{uid}`, refreshes member cache.
- `ban_member(guild_id, user_id, data)` (line 128) — `PUT /spaces/{id}/bans/{uid}`, refreshes member cache, emits `bans_updated`.
- `unban_member(guild_id, user_id)` (line 144) — `DELETE /spaces/{id}/bans/{uid}`, emits `bans_updated`.
- `add_member_role(guild_id, user_id, role_id)` (line 156) — `PUT /spaces/{id}/members/{uid}/roles/{rid}`, refreshes member cache.
- `remove_member_role(guild_id, user_id, role_id)` (line 170) — `DELETE /spaces/{id}/members/{uid}/roles/{rid}`, refreshes member cache.
- `get_bans(guild_id)` (line 184) — `GET /spaces/{id}/bans`, returns raw result.

### Permission Checking

`Client.has_permission()` (line 513 of `client.gd`) resolves permissions in priority order:

1. **Instance admin**: If `current_user["is_admin"]` is true, all permissions are granted (line 515).
2. **Space owner**: If `guild.owner_id == current_user.id`, all permissions are granted (line 518).
3. **Role-based**: Collects all permissions from the @everyone role (position 0) and the user's assigned roles (lines 520-533). Uses `AccordPermission.has()` (line 91 of `permission.gd`) which also checks for the `administrator` permission as a wildcard (line 92).

The member context menu suppresses actions on the current user (line 44 of `member_item.gd`) and hides admin actions when the user lacks the relevant permission.

### Ban Dialog

`ban_dialog.gd` extends `ColorRect` (modal overlay). Key behavior:
- `setup(guild_id, user_id, display_name)` (line 19) sets the title to "Ban [name]".
- `_on_ban_pressed()` (line 25) disables the ban button and shows "Banning..." text during the API call.
- The reason input supports Enter to submit (line 17 via `text_submitted`).
- On success, emits `ban_confirmed(user_id, reason)` (line 46) and closes.
- On failure, displays the server error message (lines 39-44).
- Closes via overlay click, close button, or Escape key (lines 49-59).

### Ban List Dialog

`ban_list_dialog.gd` extends `ColorRect`. Key behavior:
- `_load_bans()` (line 31) fetches all bans and builds `BanRow` instances.
- Each `BanRow` (`ban_row.gd`) shows a checkbox, username, optional reason label, and an "Unban" button (lines 18-37).
- Search filters by username using case-insensitive `contains()` (lines 90-99).
- Row selection is tracked in `_selected_user_ids` array (line 8). The bulk bar shows "Unban Selected (N)" when selections exist (lines 120-123).
- `_on_select_all()` (line 108) toggles all checkboxes and updates `_selected_user_ids`.
- `_on_bulk_unban()` (line 125) shows a ConfirmDialog, then loops through selected IDs calling `unban_member()` sequentially with `await` (lines 137-141).
- Listens to `AppState.bans_updated` (line 25) to auto-refresh after any ban/unban operation (line 157).

### Role Management Dialog

`role_management_dialog.gd` extends `ColorRect`. Two-panel layout:
- **Left panel**: Role list sorted by position descending (line 75), each with a `RoleRow` showing colored role name and up/down reorder buttons. The @everyone role's reorder buttons are disabled (line 24 of `role_row.gd`).
- **Right panel**: Editor shown when a role is selected (line 139). Contains name input, color picker, hoist checkbox, mentionable checkbox, and all 37 permission checkboxes built dynamically from `AccordPermission.all()` (lines 59-65).

State tracking:
- `_dirty: bool` (line 10) is set to `true` by input signal callbacks (lines 50-53, 63).
- `_dirty` is reset to `false` after save (line 208) or role selection (line 160).
- `_try_close()` (line 236) checks dirty state and shows "Unsaved Changes" prompt with danger styling.

Role reordering (`_on_move_role()`, line 110):
- Swaps positions between adjacent roles using `Client.admin.reorder_roles()`.
- Prevents swapping with @everyone (line 118).
- Builds a two-element reorder array with swapped position values (lines 122-127).

### Gateway Event Handlers

Member events (`client_gateway.gd`):
- `on_member_join()` (line 333) — Fetches user if not cached, appends `member_to_dict()` to `_member_cache`, emits `members_updated`.
- `on_member_leave()` (line 355) — Extracts `user_id` from event data (supports both `user_id` field and nested `user.id`), removes from `_member_cache`, emits `members_updated`.
- `on_member_update()` (line 372) — Rebuilds `member_to_dict()`, updates or appends in `_member_cache`, emits `members_updated`.

Role events (`client_gateway.gd`):
- `on_role_create()` (line 475) — Parses `AccordRole.from_dict()`, converts to dict, appends to `_role_cache`, emits `roles_updated`.
- `on_role_update()` (line 486) — Finds and replaces role in `_role_cache` by ID, emits `roles_updated`.
- `on_role_delete()` (line 500) — Finds and removes role from `_role_cache` by ID, emits `roles_updated`.

Ban events (`client_gateway.gd`):
- `on_ban_create()` (line 513) — Emits `AppState.bans_updated(guild_id)`.
- `on_ban_delete()` (line 519) — Emits `AppState.bans_updated(guild_id)`.

### Role Toggle Feedback

The member context menu role toggle (`_toggle_role()`, line 120 of `member_item.gd`) provides visual feedback:
- The menu item is disabled during the API call (line 136) to prevent double-clicks.
- On success: `_flash_feedback()` (line 154) tweens the member item's `modulate` to a green-tinted color for 0.15s then back over 0.3s.
- On failure: red flash and the checkbox state is reverted to its previous value (line 152).

### Confirm Dialog

`confirm_dialog.gd` is a reusable modal with `confirmed` signal (line 3):
- `setup(title, message, confirm_text, danger)` (line 16) configures the dialog.
- When `danger` is true (line 26), the confirm button gets a red `StyleBoxFlat` background and lighter red hover state (lines 27-40).
- Closes via cancel button, close button, overlay click, or Escape key (lines 46-56).

## Implementation Status

- [x] Kick member with confirmation dialog
- [x] Ban member with optional reason field
- [x] Ban dialog error handling and loading state
- [x] Ban list viewer with search/filter
- [x] Single unban with confirmation
- [x] Bulk unban with select all and confirmation
- [x] Role assignment via member context menu checkboxes
- [x] Role toggle visual feedback (green/red flash)
- [x] Role toggle disabled state during API call
- [x] Role management dialog (create, edit, delete, search, reorder)
- [x] All 37 permission checkboxes in role editor
- [x] Unsaved changes warning on role management close
- [x] @everyone role protection (cannot delete, cannot reorder)
- [x] Permission-gated context menu items (kick_members, ban_members, manage_roles)
- [x] Self-protection (context menu suppressed for own user)
- [x] Permission checking with admin/owner bypass
- [x] Gateway event handlers for member join/leave/update
- [x] Gateway event handlers for role create/update/delete
- [x] Gateway event handlers for ban create/delete
- [x] Two entry points for admin dialogs (guild icon context menu, channel banner dropdown)
- [x] Reusable ConfirmDialog with danger mode
- [ ] Role hierarchy enforcement on client side (cannot assign roles at or above own highest)
- [ ] Timeout/mute member (AccordPermission.MODERATE_MEMBERS exists but no UI)
- [ ] Member nickname editing UI (MembersApi.update() exists, no UI)
- [ ] Audit log for admin actions (AccordPermission.VIEW_AUDIT_LOG exists, no API/UI)
- [ ] Ban reason display in ban creation confirmation
- [ ] Member-specific permission overwrites (server supports, UI only supports role overwrites)
- [ ] Pagination for ban list (server supports cursor-based, client loads all at once)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No client-side role hierarchy enforcement | High | The server enforces hierarchy checks, but the client does not prevent assigning roles at or above the user's highest role. If the server rejects it, the user sees a red flash but no explanatory message. |
| No timeout/mute member UI | Medium | `AccordPermission.MODERATE_MEMBERS` (line 44 of `permission.gd`) exists and is included in the default Moderator role, but no UI or API call for timing out or muting members is implemented. |
| No member nickname editing | Medium | `MembersApi.update()` (line 53 of `members_api.gd`) supports updating nicknames, but no UI exposes this to admins. The member context menu only has Message, Kick, Ban, and Role options. |
| Bulk unban is sequential | Low | `_on_bulk_unban()` (line 138 of `ban_list_dialog.gd`) loops through selected IDs with `await` for each API call. Could be parallelized or batched for large selections. |
| Ban list doesn't paginate | Low | `Client.admin.get_bans()` (line 184 of `client_admin.gd`) loads all bans in a single request. The server `BansApi.list()` (line 16 of `bans_api.gd`) supports pagination via query parameters but the client doesn't use them. |
| No ban reason preview before confirming | Low | The BanDialog shows a reason input but there's no summary step showing what will be submitted. The reason is sent directly on button press. |
| Role editor doesn't show member count per role | Low | The role management dialog shows role names and permissions but doesn't indicate how many members hold each role. |
| No audit log viewer | Low | `AccordPermission.VIEW_AUDIT_LOG` (line 13 of `permission.gd`) exists and the Admin default role includes it, but no audit log API endpoints or UI exist. |
