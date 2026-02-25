# Role-Based Permissions

## Overview
daccord implements a Discord-style role-based permission system. Each space has an ordered set of roles with attached permission strings. A user's effective permissions are the union of their assigned roles' permissions plus the @everyone role. Channel-level overwrites can further allow or deny specific permissions per-role or per-user. The client resolves permissions locally for UI gating and delegates enforcement to the server.

## User Steps
1. **View admin options** -- Right-click a space icon or click the space banner dropdown to see permission-gated admin menu items (Space Settings, Manage Channels, Manage Roles, etc.).
2. **Manage roles** -- Open the Role Management dialog to create, edit, reorder, or delete roles. Each role has a name, color, hoist flag, mentionable flag, and a set of permission checkboxes.
3. **Assign roles to members** -- Right-click a member in the member list; if the user has MANAGE_ROLES, a "Roles" section appears with toggleable checkboxes for each role below the user's highest role.
4. **Edit channel permissions** -- Open the Channel Permissions dialog from a channel's context menu. Select a role or member, then toggle each permission between Allow / Inherit / Deny.
5. **Preview as role (Imposter Mode)** -- From the space context menu (requires MANAGE_ROLES), choose "View As Role" to preview the UI as a specific role or custom permission set.

## Signal Flow
```
User right-clicks space icon
  -> guild_icon._build_context_menu()     checks has_permission() for each admin item
  -> user clicks "Manage Roles"
     -> role_management_dialog.setup(space_id)
        -> Client.get_roles_for_space()    reads _role_cache
        -> _rebuild_role_list()            populates RoleRow items

User saves role changes
  -> role_management_dialog._on_save()
     -> Client.admin.update_role()
        -> AccordClient.roles.update()     PATCH /spaces/{id}/roles/{id}
        -> Client.fetch.fetch_roles()      refreshes _role_cache
        -> AppState.roles_updated          signal emitted
           -> role_management_dialog._on_roles_updated()  rebuilds UI

Gateway role events
  -> AccordClient.role_create / role_update / role_delete
     -> client_gateway.on_role_create/update/delete()
        -> updates _role_cache
        -> AppState.roles_updated.emit()
```

## Key Files
| File | Role |
|------|------|
| `addons/accordkit/models/permission.gd` | 39 permission string constants + `has()` with admin bypass |
| `addons/accordkit/models/role.gd` | `AccordRole` model (id, name, color, hoist, position, permissions, managed, mentionable) |
| `addons/accordkit/models/permission_overwrite.gd` | `AccordPermissionOverwrite` model (id, type, allow, deny) |
| `addons/accordkit/rest/endpoints/roles_api.gd` | REST endpoints: list, create, update, delete, reorder roles |
| `addons/accordkit/rest/endpoints/members_api.gd` | REST endpoints: add_role, remove_role for member role assignment |
| `addons/accordkit/rest/endpoints/channels_api.gd` | REST endpoints: upsert_overwrite, delete_overwrite for channel permissions |
| `scripts/autoload/client_permissions.gd` | Permission resolution engine: `has_permission()`, `has_channel_permission()`, `get_my_highest_role_position()` |
| `scripts/autoload/client.gd:94` | `_role_cache` dictionary (space_id -> Array of role dicts) |
| `scripts/autoload/client.gd:586-603` | Public `has_permission()`, `has_channel_permission()`, `get_my_highest_role_position()` delegations |
| `scripts/autoload/client_admin.gd:78-114` | Admin wrappers: `create_role()`, `update_role()`, `delete_role()`, `reorder_roles()` |
| `scripts/autoload/client_admin.gd:156-182` | Admin wrappers: `add_member_role()`, `remove_member_role()` |
| `scripts/autoload/client_admin.gd:392-434` | `update_channel_overwrites()` -- batch upsert/delete channel overwrites |
| `scripts/autoload/client_fetch.gd:455-473` | `fetch_roles()` -- REST list + cache update + `roles_updated` signal |
| `scripts/autoload/client_gateway.gd:630-666` | Gateway handlers: `on_role_create`, `on_role_update`, `on_role_delete` |
| `scripts/autoload/client_models_secondary.gd:21-31` | `role_to_dict()` -- converts AccordRole to UI dictionary |
| `scripts/autoload/app_state.gd:38` | `roles_updated` signal declaration |
| `scripts/autoload/app_state.gd:95,173-313` | Imposter mode state + `enter_imposter_mode()` / `exit_imposter_mode()` |
| `scenes/admin/role_management_dialog.gd` | Full role CRUD UI: list, editor, create, save, delete, reorder, dirty tracking |
| `scenes/admin/role_row.gd` | Single role row with up/down reorder buttons and selection |
| `scenes/admin/channel_permissions_dialog.gd` | Per-channel Allow/Inherit/Deny overwrite editor |
| `scenes/admin/perm_overwrite_row.gd` | Single permission row with Allow/Inherit/Deny toggle buttons |
| `scenes/admin/imposter_picker_dialog.gd` | "View As Role" picker for imposter mode |
| `scenes/members/member_item.gd:86-109` | Context menu role assignment toggle with hierarchy enforcement |
| `scenes/sidebar/guild_bar/guild_icon.gd:155-183` | Space context menu permission gating |
| `scenes/sidebar/channels/banner.gd:43-97` | Space banner dropdown permission gating |
| `scenes/sidebar/channels/channel_list.gd:44-52` | Imposter mode channel visibility filtering (VIEW_CHANNEL) |
| `tests/accordkit/unit/test_permissions.gd` | AccordPermission unit tests (constants, has(), admin bypass) |
| `tests/unit/test_client.gd:225-269` | Client-level permission resolution tests |

## Implementation Details

### Permission Model (AccordKit)
`AccordPermission` (line 1) is a static class defining 39 permission string constants. The `all()` method (line 47) returns all permissions as an array. The `has()` method (line 91) checks membership with an implicit `ADMINISTRATOR` bypass -- if the permissions array contains `"administrator"`, any permission check returns true.

Permissions use string identifiers (e.g., `"manage_channels"`, `"send_messages"`) rather than bitfields. They are stored as arrays of strings on both roles and overwrites.

### Role Model
`AccordRole` (line 1) stores: `id`, `name`, `color` (integer), `hoist` (display separately in member list), `position` (hierarchy order, 0 = @everyone), `permissions` (string array), `managed` (bot-owned), `mentionable`. The `from_dict()`/`to_dict()` methods handle serialization.

### Permission Resolution Engine
`client_permissions.gd` provides two resolution methods:

**`has_permission(gid, perm)`** (line 10):
1. If imposter mode is active for this space, checks against `AppState.imposter_permissions` (line 11-12).
2. Instance admin (`is_admin` flag) bypasses all checks (line 14).
3. Space owner bypasses all checks (line 17-18).
4. Gathers the user's assigned role IDs from `_member_cache` (lines 19-22).
5. Unions permissions from the @everyone role (position == 0) and all assigned roles (lines 23-30).
6. Returns whether the requested permission is in the union (line 31).

**`has_channel_permission(gid, channel_id, perm)`** (line 34):
Extends `has_permission` with the Discord-style overwrite resolution algorithm:
1. Same bypass checks: imposter, admin, owner (lines 38-49).
2. Computes base permissions from @everyone + assigned roles (lines 59-70).
3. `ADMINISTRATOR` permission in base perms bypasses all overwrites (line 73).
4. If no overwrites exist, falls back to base permissions (line 82).
5. Applies @everyone channel overwrite first (lines 88-95).
6. Unions all applicable role overwrites -- deny first, then allow wins (lines 98-119).
7. Applies member-specific overwrite last (highest priority) (lines 122-130).
8. Returns whether the permission exists in the effective set (line 132).

**`get_my_highest_role_position(gid)`** (line 142):
Returns the highest position among the user's assigned roles, or `999999` for admins/owners. Used for role hierarchy enforcement.

### Role Caching
Roles are cached in `Client._role_cache` (line 94 of `client.gd`), keyed by space_id. The cache is populated by `fetch_roles()` in `client_fetch.gd` (line 455), which calls `GET /spaces/{id}/roles`, converts each `AccordRole` via `ClientModels.role_to_dict()`, and emits `AppState.roles_updated`.

### Gateway Real-Time Sync
`client_gateway.gd` handles three role events:
- **`on_role_create`** (line 630): Appends the new role dict to `_role_cache[space_id]`.
- **`on_role_update`** (line 641): Finds and replaces the role in `_role_cache[space_id]` by ID.
- **`on_role_delete`** (line 655): Removes the role from `_role_cache[space_id]` by ID.
All three emit `AppState.roles_updated`.

### Role Management Dialog
`role_management_dialog.gd` provides full CRUD for roles:
- **Role list** (line 70): Fetches roles via `Client.get_roles_for_space()`, sorts by position descending, instantiates `RoleRow` scenes with member counts.
- **Role editor** (line 160): Populates name, color picker, hoist/mentionable checkboxes, and per-permission checkboxes from `AccordPermission.all()`.
- **Hierarchy enforcement** (lines 185-198): Roles at or above the user's highest position are read-only (all inputs disabled, error message shown).
- **Create** (line 203): `Client.admin.create_role()` with default name "New Role".
- **Save** (line 215): Builds a data dict with name, color (hex-to-int), hoist, mentionable, and checked permissions, then calls `Client.admin.update_role()`.
- **Delete** (line 251): Confirmation dialog, then `Client.admin.delete_role()`. @everyone role (position 0) cannot be deleted.
- **Reorder** (line 124): Swaps positions of two adjacent roles via `Client.admin.reorder_roles()`. Blocked for roles at or above the user's highest.
- **Search** (line 113): Client-side name filter.
- **Dirty tracking** (lines 49-53): Tracks unsaved changes, prompts on close.
- **Real-time updates** (line 47): Listens to `AppState.roles_updated` to rebuild the list.

### Channel Permission Overwrites Dialog
`channel_permissions_dialog.gd` manages per-channel permission overwrites:
- **Overwrite states** (line 4): `INHERIT`, `ALLOW`, `DENY` enum.
- **Channel type filtering** (line 265): Filters out voice-only permissions for text channels and vice versa.
- **Role list** (line 89): Shows all space roles sorted by position, plus existing member overwrites and an "+ Add Member" button.
- **Permission rows** (line 282): Each permission renders as a `PermOverwriteRow` with Allow (green checkmark), Inherit (gray slash), Deny (red X) buttons.
- **Save** (line 319): Builds overwrites array (only entities with non-INHERIT values), identifies deleted overwrites (previously existed but now all-INHERIT), calls `Client.admin.update_channel_overwrites()`.
- **Dirty tracking** (line 370): Compares current state against original snapshot.

### Member Role Assignment
`member_item.gd` (line 86) adds role checkboxes to the member context menu when the user has `MANAGE_ROLES`:
- Skips @everyone (position 0).
- Disables roles at or above the user's highest role with tooltip (lines 103-108).
- `_toggle_role()` (line 168) calls `Client.admin.add_member_role()` or `remove_member_role()` based on current state.

### UI Permission Gating
Permission checks gate admin UI elements across the application:

| Permission | Gating Location |
|-----------|-----------------|
| `MANAGE_SPACE` | Space Settings menu item (`guild_icon.gd:155`, `banner.gd:64`) |
| `MANAGE_CHANNELS` | Channel management menu items, create/edit/delete channel buttons (`guild_icon.gd:159`, `banner.gd:68`, `channel_list.gd:61`, `channel_item.gd:86`, `voice_channel_item.gd:63`, `category_item.gd:89`, `channel_row.gd:46`) |
| `MANAGE_ROLES` | Role management menu item, member role assignment, imposter mode (`guild_icon.gd:163`, `banner.gd:72`, `member_item.gd:86`) |
| `BAN_MEMBERS` | Ban management menu item, member ban button (`guild_icon.gd:167`, `banner.gd:76`, `member_item.gd:74`) |
| `KICK_MEMBERS` | Member kick button (`member_item.gd:70`) |
| `CREATE_INVITES` | Invite management menu item (`guild_icon.gd:171`, `banner.gd:80`) |
| `MANAGE_EMOJIS` | Emoji management menu item (`guild_icon.gd:175`, `banner.gd:84`) |
| `VIEW_AUDIT_LOG` | Audit log menu item (`guild_icon.gd:179`, `banner.gd:88`) |
| `MANAGE_SOUNDBOARD` / `USE_SOUNDBOARD` | Soundboard menu item (`banner.gd:92-93`), manage UI (`soundboard_management_dialog.gd:34`) |
| `MODERATE_MEMBERS` | Moderate member button (`member_item.gd:78`) |
| `MANAGE_NICKNAMES` | Edit nickname button (`member_item.gd:82`) |
| `MANAGE_MESSAGES` | Message delete/pin in action bar (`message_action_bar.gd:35`) |
| `MANAGE_THREADS` | Forum thread management (`forum_view.gd:270`) |
| `MENTION_EVERYONE` | @everyone mention filtering in composer (`composer.gd:117`) |
| `VIEW_CHANNEL` | Channel visibility in imposter mode (`channel_list.gd:50`) |
| `USE_SOUNDBOARD` | Soundboard play button in voice bar (`voice_bar.gd:57`) |

### Imposter Mode (View As Role)
`imposter_picker_dialog.gd` lets admins with `MANAGE_ROLES` preview the UI as a specific role:
- Lists all roles sorted by position descending (line 35).
- Offers a "Custom..." option to manually select permissions (line 86).
- On "Preview", calls `AppState.enter_imposter_mode(role_data)` (line 139) which stores the role's permissions, name, and space ID.
- `has_permission()` and `has_channel_permission()` check `AppState.is_imposter_mode` first and resolve against the impersonated permission set instead of the user's real permissions.
- `channel_list.gd` (line 44) filters channels by `VIEW_CHANNEL` during imposter mode.
- Exiting the space or switching to another space auto-exits imposter mode (`app_state.gd:179-191`).

### REST API Surface
| Method | Endpoint | Used By |
|--------|----------|---------|
| `GET` | `/spaces/{id}/roles` | `roles_api.list()` via `fetch_roles()` |
| `POST` | `/spaces/{id}/roles` | `roles_api.create()` via `admin.create_role()` |
| `PATCH` | `/spaces/{id}/roles/{id}` | `roles_api.update()` via `admin.update_role()` |
| `DELETE` | `/spaces/{id}/roles/{id}` | `roles_api.delete()` via `admin.delete_role()` |
| `PATCH` | `/spaces/{id}/roles` (array body) | `roles_api.reorder()` via `admin.reorder_roles()` |
| `PUT` | `/spaces/{id}/members/{id}/roles/{id}` | `members_api.add_role()` via `admin.add_member_role()` |
| `DELETE` | `/spaces/{id}/members/{id}/roles/{id}` | `members_api.remove_role()` via `admin.remove_member_role()` |
| `PUT` | `/channels/{id}/overwrites/{id}` | `channels_api.upsert_overwrite()` via `admin.update_channel_overwrites()` |
| `DELETE` | `/channels/{id}/overwrites/{id}` | `channels_api.delete_overwrite()` via `admin.update_channel_overwrites()` |

## Implementation Status
- [x] 39 permission string constants with `ADMINISTRATOR` bypass
- [x] Role CRUD (create, read, update, delete) via REST + gateway sync
- [x] Role reordering with position swap
- [x] Role hierarchy enforcement (cannot edit/delete/reorder roles at or above own)
- [x] Permission resolution: union of @everyone + assigned roles
- [x] Channel permission overwrites with Discord-style resolution (everyone -> role union -> member)
- [x] Allow / Inherit / Deny tri-state toggle UI
- [x] Channel type filtering (voice-only vs text-only permissions)
- [x] Member role assignment via context menu with hierarchy enforcement
- [x] UI gating for 16+ permission types across admin menus and actions
- [x] Imposter mode (View As Role) for permission preview
- [x] Gateway real-time sync for role create/update/delete
- [x] Dirty tracking and unsaved changes prompts in both role and overwrite dialogs
- [x] Role search/filter in management dialog
- [x] Member count per role in management dialog
- [ ] Hoist-based member list grouping by role
- [ ] Role color applied to usernames in messages and member list
- [ ] Drag-and-drop role reordering
- [ ] Channel visibility filtering by VIEW_CHANNEL for non-imposter users
- [ ] SEND_MESSAGES permission gating on the composer
- [ ] Per-permission descriptions/tooltips in management dialogs

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No VIEW_CHANNEL filtering for real users | High | `channel_list.gd:44-52` only filters channels in imposter mode; real users see all channels regardless of VIEW_CHANNEL permission |
| No SEND_MESSAGES gating on composer | High | `composer.gd` only checks MENTION_EVERYONE (line 117); should disable input when user lacks SEND_MESSAGES for the current channel |
| Role colors not applied to usernames | Medium | Role `color` is stored and editable but never rendered on member names in messages or the member list |
| No hoist-based member list sections | Medium | `AccordRole.hoist` is stored and editable but the member list does not group members by hoisted roles |
| VIEW_CHANNEL imposter filter is coarse | Medium | `channel_list.gd:50` checks if the role has VIEW_CHANNEL globally, not per-channel via overwrites -- so all channels are shown or hidden uniformly |
| No drag-and-drop role reorder | Low | Role reordering uses up/down arrow buttons (`role_row.gd:14-15`); drag-and-drop would be more intuitive |
| No permission descriptions | Low | Permission checkboxes show formatted names only (e.g., "Manage Channels"); no tooltip or description explains what each permission does |
| No CONNECT permission check for voice | Medium | Voice channel join does not check `CONNECT` permission before attempting to join |
| No ATTACH_FILES permission check | Low | File upload in composer does not check `ATTACH_FILES` permission |
| No EMBED_LINKS permission check | Low | URL previews are not gated by `EMBED_LINKS` permission |
