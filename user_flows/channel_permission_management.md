# Channel Permission Management

*Last touched: 2026-02-18 20:21*

## Overview

Channel permission management allows server admins to set per-role permission overwrites on individual channels. The admin opens the Channel Permissions dialog from the channel management list, selects a role, and toggles each permission to Allow, Deny, or Inherit. Overwrites are saved via the REST API using the server's dedicated overwrite endpoints (PUT/DELETE per role), and the server resolves effective channel permissions using a Discord-style algorithm (base role perms → @everyone overwrite → role overwrites → member overwrites).

## User Steps

1. Right-click the guild icon or click the banner dropdown and select **Channels** (requires `manage_channels` permission).
2. In the Channel Management dialog, find the target channel row and click the **Perms** button.
3. The Channel Permissions dialog opens, showing a role list on the left and a permission grid on the right.
4. Click a role in the left panel to view/edit its overwrites for this channel. The selected role is highlighted with a dark background.
5. For each permission, click ✓ (Allow), / (Inherit), or ✗ (Deny) to set the overwrite state.
6. Click **Reset** to return all permissions for the selected role to Inherit.
7. Click **Save** to persist the overwrites to the server. Roles with actual overwrites are upserted individually; roles reset to all-INHERIT are deleted from the server.
8. Close the dialog via the ✕ button, Escape, or clicking the backdrop.

## Signal Flow

```
channel_row "Perms" click
  → permissions_requested signal emitted (channel_row.gd:26)
    → channel_management_dialog._on_permissions_channel() (line 213)
      → Instantiates ChannelPermissionsScene, adds to root
        → channel_permissions_dialog.setup(channel, guild_id)
          → _load_overwrites() reads channel.permission_overwrites, records _original_overwrite_ids
          → _rebuild_role_list() calls Client.get_roles_for_guild(), stores _role_buttons

User clicks role
  → _on_role_selected(role_id)
    → Initializes overwrite data for role (all INHERIT if new)
    → _update_role_selection() highlights selected role button via StyleBoxFlat
    → _rebuild_perm_list() creates PermOverwriteRow per permission

User clicks Allow/Inherit/Deny button
  → perm_overwrite_row emits state_changed(perm, new_state)
    → channel_permissions_dialog._toggle_perm() updates _overwrite_data
    → Updates single row via _perm_rows[perm].update_state(new_state)

User clicks Save
  → _on_save() builds overwrites array + deleted_ids list
    → Client.admin.update_channel_overwrites(channel_id, overwrites, deleted_ids)
      → For each deleted_id: client.channels.delete_overwrite(channel_id, id)
        → DELETE /channels/:id/overwrites/:overwrite_id (server)
      → For each overwrite: client.channels.upsert_overwrite(channel_id, id, data)
        → PUT /channels/:id/overwrites/:overwrite_id (server)
    → On success: dialog closes
    → On failure: error label shown
```

## Key Files

| File | Role |
|------|------|
| `scenes/admin/channel_permissions_dialog.gd` | Main dialog: role list, permission grid, save/reset logic |
| `scenes/admin/channel_permissions_dialog.tscn` | Dialog layout: split panel with RoleScroll + PermScroll |
| `scenes/admin/perm_overwrite_row.gd` | Single permission row with Allow/Inherit/Deny toggle buttons |
| `scenes/admin/perm_overwrite_row.tscn` | Row layout: label + 3 buttons (✓ / ✗) |
| `scenes/admin/channel_management_dialog.gd` | Parent dialog that launches the permissions dialog |
| `scenes/admin/channel_row.gd` | Channel row with "Perms" button that emits `permissions_requested` |
| `scripts/autoload/client_admin.gd` | `update_channel_overwrites()` method (line 367) |
| `addons/accordkit/models/permission.gd` | `AccordPermission` constants and `all()` / `has()` helpers |
| `addons/accordkit/models/permission_overwrite.gd` | `AccordPermissionOverwrite` model (id, type, allow, deny) |
| `addons/accordkit/models/channel.gd` | `AccordChannel` with `permission_overwrites` array field |
| `addons/accordkit/rest/endpoints/channels_api.gd` | `upsert_overwrite()`, `delete_overwrite()`, `list_overwrites()` for dedicated overwrite routes |
| `scripts/autoload/client_models.gd` | `channel_to_dict()` converts `permission_overwrites` to dict array (line 217) |
| `scripts/autoload/client.gd` | `has_permission()` (line 672) — space-level permission check, `get_roles_for_guild()` (line 409) |
| `accordserver/src/routes/channels.rs` | Server-side overwrite CRUD routes (list, upsert, delete) |
| `accordserver/src/db/permission_overwrites.rs` | DB layer: list/upsert/delete permission overwrites |
| `accordserver/src/middleware/permissions.rs` | `resolve_channel_permissions()` — Discord-style overwrite resolution algorithm |
| `tests/accordkit/unit/test_permissions.gd` | Unit tests for `AccordPermission.all()`, `has()`, administrator bypass |
| `tests/accordkit/integration/test_permissions_api.gd` | Integration tests verifying server-side permission enforcement |

## Implementation Details

### OverwriteState Enum (channel_permissions_dialog.gd)

The dialog defines three states (line 4):

```gdscript
enum OverwriteState { INHERIT, ALLOW, DENY }
```

`perm_overwrite_row.gd` duplicates these as constants (lines 6-8) to stay decoupled from the dialog script:

```gdscript
const INHERIT := 0
const ALLOW := 1
const DENY := 2
```

### Loading Existing Overwrites

`_load_overwrites()` (line 44) reads the `permission_overwrites` array from the channel dictionary. Each overwrite has an `id` (role or member ID), `allow` (array of permission strings), and `deny` (array of permission strings). The method iterates all permissions from `AccordPermission.all()` and classifies each as ALLOW, DENY, or INHERIT based on whether it appears in the overwrite's allow/deny lists.

The overwrite data is stored in `_overwrite_data: Dictionary` keyed by role ID, where each value is a dictionary mapping permission name → OverwriteState.

Original overwrite IDs are recorded in `_original_overwrite_ids` so that roles reset to all-INHERIT can be explicitly deleted from the server on save.

### Role List

`_rebuild_role_list()` (line 62) fetches roles via `Client.get_roles_for_guild(_guild_id)` and sorts them by descending position. Each role is rendered as a flat Button colored with the role's color (hex decoded from an integer). Clicking a role calls `_on_role_selected()`. Button references are stored in `_role_buttons` keyed by role ID.

### Selected Role Highlighting

`_update_role_selection()` (line 87) iterates `_role_buttons` and applies a dark `StyleBoxFlat` background (`SELECTED_BG = Color(0.25, 0.27, 0.3, 1.0)`) to the selected role's button, removing the override from all others.

### Permission Grid

`_rebuild_perm_list()` (line 105) creates one `PermOverwriteRow` per permission from `AccordPermission.all()` (37 permissions total). Each row shows the permission name (humanized via `perm.replace("_", " ").capitalize()`, line 27 of `perm_overwrite_row.gd`) and three toggle buttons.

The row emits `state_changed(perm, new_state)` when any button is clicked. The dialog handles this in `_toggle_perm()` (line 118), updating `_overwrite_data` and calling `update_state()` on the single changed row (no full rebuild).

### Button Color Feedback (perm_overwrite_row.gd)

`update_state()` (line 30) highlights the active state button:
- Allow (✓): green `Color(0.231, 0.647, 0.365)` when active, gray when inactive
- Inherit (/): light gray `Color(0.58, 0.608, 0.643)` when active, dark gray when inactive
- Deny (✗): red `Color(0.929, 0.259, 0.271)` when active, gray when inactive

### Reset

`_on_reset()` (line 123) sets all permissions for the selected role back to INHERIT and rebuilds the permission list.

### Save Flow

`_on_save()` (line 130) builds two data structures:

1. **`overwrites` array**: roles with actual allow/deny entries, to be upserted.
2. **`deleted_ids` array**: role IDs from `_original_overwrite_ids` that are now all-INHERIT, to be deleted from the server.

Each overwrite entry has shape:

```gdscript
{
    "id": role_id,
    "type": "role",
    "allow": ["send_messages", ...],
    "deny": ["manage_channels", ...],
}
```

The save calls `Client.admin.update_channel_overwrites(channel_id, overwrites, deleted_ids)` (line 157), which:
1. Deletes stale overwrites via `client.channels.delete_overwrite()` → `DELETE /channels/:id/overwrites/:overwrite_id`
2. Upserts each active overwrite via `client.channels.upsert_overwrite()` → `PUT /channels/:id/overwrites/:overwrite_id`
3. Refreshes the channel cache on success

### Server-Side Permission Resolution (permissions.rs)

The server implements Discord-style channel permission resolution in `resolve_channel_permissions()` (line 224):

1. **Base permissions**: Merge @everyone role permissions with all assigned role permissions.
2. **Administrator bypass**: If base includes `administrator`, return immediately.
3. **@everyone overwrite**: Apply the @everyone role's channel overwrite (deny removes, allow adds).
4. **Role overwrites**: Union all of the user's role overwrites; allow wins over deny across roles. Apply the net result.
5. **Member overwrite**: Apply member-specific overwrite (highest precedence).

`require_channel_permission()` (line 320) uses this to gate per-channel operations.

### Server-Side Overwrite CRUD (channels.rs)

The server exposes dedicated overwrite REST routes:
- `GET /channels/:id/overwrites` — requires `manage_roles` channel permission (line 58)
- `PUT /channels/:id/overwrites/:overwrite_id` — upsert, validates type ("role"/"member") and permission strings against `ALL_PERMISSIONS` (lines 63-94)
- `DELETE /channels/:id/overwrites/:overwrite_id` — requires `manage_roles` channel permission (line 96)

### AccordKit Permission Model

`AccordPermission` (line 1 of `permission.gd`) defines 37 permission constants as strings. `AccordPermission.has()` (line 91) checks if a permission exists in an array, with `administrator` acting as a wildcard (grants all).

`AccordPermissionOverwrite` (line 1 of `permission_overwrite.gd`) models a single overwrite with `id`, `type` ("role" or "member"), `allow` (string array), and `deny` (string array). Includes `from_dict()` / `to_dict()` for serialization.

### AccordKit Overwrite Endpoints

`ChannelsApi` in `channels_api.gd` provides:
- `list_overwrites(channel_id)` → `GET /channels/:id/overwrites`
- `upsert_overwrite(channel_id, overwrite_id, data)` → `PUT /channels/:id/overwrites/:overwrite_id`
- `delete_overwrite(channel_id, overwrite_id)` → `DELETE /channels/:id/overwrites/:overwrite_id`

### ClientModels Conversion

`channel_to_dict()` in `client_models.gd` (lines 217-224) converts `AccordChannel.permission_overwrites` (array of `AccordPermissionOverwrite`) into raw dictionaries for UI consumption. This ensures the channel dictionary passed to the permissions dialog contains the `permission_overwrites` key.

### Client-Side Permission Checks

`Client.has_permission()` (line 672 of `client.gd`) checks space-level permissions only. It does not account for channel-level overwrites. The check merges @everyone permissions with assigned role permissions and uses `AccordPermission.has()`. Instance admins and space owners bypass all checks.

### Entry Point Gating

The channel management dialog is accessible via:
- **Guild icon context menu**: gated by `Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS)` at `guild_icon.gd:119`
- **Banner dropdown**: gated by the same check at `banner.gd:64`

Within the channel management dialog, the "Perms" button on each `channel_row.tscn` is always visible (not permission-gated). The server enforces `manage_roles` permission on the overwrite CRUD endpoints.

## Implementation Status

- [x] Channel Permissions dialog UI with role list and permission grid
- [x] Per-role Allow/Inherit/Deny toggles for all 37 permissions
- [x] Load existing overwrites from channel data
- [x] Reset selected role to all-INHERIT
- [x] Save button with loading state and error display
- [x] Role color display in role list
- [x] Role sorting by position (descending)
- [x] Close via ✕ button, Escape key, or backdrop click
- [x] Server-side dedicated overwrite CRUD routes (list/upsert/delete)
- [x] Server-side Discord-style permission resolution algorithm
- [x] AccordKit permission model and overwrite model
- [x] Integration tests for permission enforcement
- [x] Client-side save persists overwrites via individual upsert/delete endpoints
- [x] Visual indication of selected role in the role list
- [x] Stale overwrite cleanup on save (roles reset to all-INHERIT are deleted)
- [x] Efficient per-row updates on permission toggle (no full rebuild)
- [ ] Member-type overwrite support in UI
- [ ] Client-side channel-level permission checks

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No member-type overwrites | Medium | The dialog only creates overwrites with `"type": "role"` (line 149). The server supports `"member"` type overwrites, and `resolve_channel_permissions()` handles them (line 300 of `permissions.rs`), but the UI has no way to add member-specific overwrites. |
| Perms button not permission-gated | Low | The "Perms" button in `channel_row.tscn` (line 31) is always shown. While the server enforces `manage_roles` on the overwrite endpoints, users without permission see the dialog and only get a failure on save. The button should be hidden or disabled if the user lacks `manage_roles`. |
| Client-side `has_permission` ignores channel overwrites | Medium | `Client.has_permission()` at `client.gd:672` only checks space-level role permissions. It does not factor in channel-level overwrites. This means UI gating (e.g., showing edit buttons) may be inaccurate for channels with overwrites. A `has_channel_permission()` method is needed. |
| No dirty state tracking | Low | Changing permissions and closing without saving silently discards changes. No "unsaved changes" warning is shown. |
| All 37 permissions shown for every channel | Low | Some permissions are irrelevant to certain channel types (e.g., `SPEAK` and `CONNECT` for text channels, `SEND_MESSAGES` for voice channels). The grid could be filtered based on channel type. |
