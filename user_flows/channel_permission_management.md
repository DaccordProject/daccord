# Channel Permission Management


## Overview

Channel permission management allows server admins to set per-role permission overwrites on individual channels. The admin opens the Channel Permissions dialog from the channel management list, selects a role, and toggles each permission to Allow, Deny, or Inherit. Overwrites are saved via the REST API using the server's dedicated overwrite endpoints (PUT/DELETE per role), and the server resolves effective channel permissions using a Discord-style algorithm (base role perms → @everyone overwrite → role overwrites → member overwrites).

## User Steps

1. Right-click the guild icon or click the banner dropdown and select **Channels** (requires `manage_channels` permission).
2. In the Channel Management dialog, find the target channel row and click the **Perms** button (only visible if user has `manage_roles` permission).
3. The Channel Permissions dialog opens, showing a role list on the left and a permission grid on the right. The permission grid is filtered by channel type (text channels hide voice perms, voice channels hide text perms).
4. Click a role in the left panel to view/edit its overwrites for this channel. The selected role is highlighted with a dark background.
5. To add a member-specific overwrite, click **+ Add Member** below the role list and search for a member.
6. For each permission, click ✓ (Allow), / (Inherit), or ✗ (Deny) to set the overwrite state.
7. Click **Reset** to return all permissions for the selected role/member to Inherit.
8. Click **Save** to persist the overwrites to the server. Roles/members with actual overwrites are upserted individually; those reset to all-INHERIT are deleted from the server.
9. Close the dialog via the ✕ button, Escape, or clicking the backdrop. If there are unsaved changes, a confirmation dialog asks whether to discard them.

## Signal Flow

```
channel_row "Perms" click (button hidden if user lacks manage_roles)
  → permissions_requested signal emitted (channel_row.gd:26)
    → channel_management_dialog._on_permissions_channel() (line 213)
      → Instantiates ChannelPermissionsScene, adds to root
        → channel_permissions_dialog.setup(channel, guild_id)
          → _load_overwrites() reads channel.permission_overwrites, records _original_overwrite_ids
          → Snapshots _original_overwrite_data and _original_overwrite_types for dirty tracking
          → _rebuild_role_list() calls Client.get_roles_for_guild(), stores _role_buttons

User clicks role or member
  → _on_entity_selected(entity_id, entity_type)
    → Initializes overwrite data for entity (all INHERIT if new)
    → _update_role_selection() highlights selected button via StyleBoxFlat
    → _rebuild_perm_list() creates PermOverwriteRow per permission, filtered by channel type

User clicks "+ Add Member"
  → _on_add_member_overwrite() opens searchable member picker popup
    → Selecting a member adds "user"-type overwrite data and selects that member

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

User closes dialog with unsaved changes
  → _try_close() checks _is_dirty() by comparing current state to original snapshot
    → If dirty: shows ConfirmDialog ("Unsaved Changes" / "Discard")
      → On confirm: dialog closes
    → If clean: dialog closes immediately
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
| `scripts/autoload/client.gd` | `has_permission()` — space-level permission check, `has_channel_permission()` — channel-level with overwrite resolution, `get_roles_for_guild()` |
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

`_rebuild_perm_list()` creates one `PermOverwriteRow` per permission from `_perms_for_channel_type()`, which filters `AccordPermission.all()` based on the channel type:

- **Text / Announcement / Forum** channels: voice-only permissions are hidden (`connect`, `speak`, `mute_members`, `deafen_members`, `move_members`, `use_vad`, `priority_speaker`, `stream`).
- **Voice** channels: text-only permissions are hidden (`send_messages`, `send_tts`, `manage_messages`, `embed_links`, `attach_files`, `read_history`, `mention_everyone`, `use_external_emojis`, `manage_threads`, `create_threads`, `use_external_stickers`, `send_in_threads`).
- **Category** channels: all permissions are shown.

Each row shows the permission name (humanized via `perm.replace("_", " ").capitalize()`) and three toggle buttons. The row emits `state_changed(perm, new_state)` when any button is clicked. The dialog handles this in `_toggle_perm()`, updating `_overwrite_data` and calling `update_state()` on the single changed row (no full rebuild).

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

Two permission check methods exist:

- **`Client.has_permission(guild_id, perm)`** — checks space-level permissions only. Merges @everyone permissions with assigned role permissions. Instance admins and space owners bypass all checks.
- **`Client.has_channel_permission(guild_id, channel_id, perm)`** — resolves channel-level permissions using the Discord-style algorithm: base role perms → administrator bypass → @everyone channel overwrite → role overwrites (union, allow wins) → member overwrite. Uses `permission_overwrites` from the cached channel dictionary.

### Entry Point Gating

The channel management dialog is accessible via:
- **Guild icon context menu**: gated by `Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS)` at `guild_icon.gd:119`
- **Banner dropdown**: gated by the same check at `banner.gd:64`

Within the channel management dialog, the "Perms" button on each `channel_row` is hidden if the user lacks `manage_roles` permission. The `channel_row.setup()` method accepts a `guild_id` parameter and checks `Client.has_permission(guild_id, AccordPermission.MANAGE_ROLES)` to control visibility. The server also enforces `manage_roles` permission on the overwrite CRUD endpoints as a second layer of protection.

### Dirty State Tracking

The dialog snapshots `_overwrite_data` and `_overwrite_types` at load time into `_original_overwrite_data` and `_original_overwrite_types`. When the user attempts to close (via close button, Escape, or backdrop click), `_is_dirty()` compares the current state to the snapshot. If changes exist, a `ConfirmDialog` asks whether to discard them. If the user confirms, the dialog closes; otherwise it stays open.

## Implementation Status

- [x] Channel Permissions dialog UI with role list and permission grid
- [x] Per-role Allow/Inherit/Deny toggles for all 39 permissions
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
- [x] Member-type overwrite support in UI (+ Add Member button with searchable picker)
- [x] Client-side channel-level permission checks (`has_channel_permission()`)
- [x] Perms button gated by `manage_roles` permission
- [x] Dirty state tracking with unsaved changes confirmation dialog
- [x] Permission grid filtered by channel type (text vs voice)
