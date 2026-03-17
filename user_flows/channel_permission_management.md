# Channel Permission Management

Priority: 20
Depends on: Role-Based Permissions, Channel Categories
Status: Complete

Per-role and per-member permission overwrites on individual channels with Allow/Inherit/Deny toggles, using Discord-style server-side resolution.

## Key Files

| File | Role |
|------|------|
| `scenes/admin/channel_permissions_dialog.gd` | Main dialog: role list, permission grid, save/reset logic |
| `scenes/admin/channel_permissions_dialog.tscn` | Dialog layout: split panel with RoleScroll + PermScroll |
| `scenes/admin/perm_overwrite_row.gd` | Single permission row with Allow/Inherit/Deny toggle buttons |
| `scenes/admin/perm_overwrite_row.tscn` | Row layout: label + 3 buttons |
| `scenes/admin/channel_management_dialog.gd` | Parent dialog that launches the permissions dialog |
| `scenes/admin/channel_row.gd` | Channel row with "Perms" button that emits `permissions_requested` |
| `scripts/autoload/client_admin.gd` | `update_channel_overwrites()` method (line 367) |
| `addons/accordkit/models/permission.gd` | `AccordPermission` constants and `all()` / `has()` helpers |
| `addons/accordkit/models/permission_overwrite.gd` | `AccordPermissionOverwrite` model (id, type, allow, deny) |
| `addons/accordkit/models/channel.gd` | `AccordChannel` with `permission_overwrites` array field |
| `addons/accordkit/rest/endpoints/channels_api.gd` | `upsert_overwrite()`, `delete_overwrite()`, `list_overwrites()` for dedicated overwrite routes |
| `scripts/autoload/client_models.gd` | `channel_to_dict()` converts `permission_overwrites` to dict array (line 217) |
| `scripts/autoload/client.gd` | `has_permission()` — space-level permission check, `has_channel_permission()` — channel-level with overwrite resolution, `get_roles_for_space()` |
| `accordserver/src/routes/channels.rs` | Server-side overwrite CRUD routes (list, upsert, delete) |
| `accordserver/src/db/permission_overwrites.rs` | DB layer: list/upsert/delete permission overwrites |
| `accordserver/src/middleware/permissions.rs` | `resolve_channel_permissions()` — Discord-style overwrite resolution algorithm |
| `tests/accordkit/unit/test_permissions.gd` | Unit tests for `AccordPermission.all()`, `has()`, administrator bypass |
| `tests/accordkit/integration/test_permissions_api.gd` | Integration tests verifying server-side permission enforcement |
