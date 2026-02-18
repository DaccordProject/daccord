# Admin Server Management

*Last touched: 2026-02-18 20:21*

## Overview

Admins manage their space (server) through a set of privileged operations: editing space settings, creating/updating/deleting channels, managing roles and permissions, kicking/banning members, generating invites, and managing custom emojis. The server enforces a 37-permission model with role hierarchy and per-channel permission overwrites (Discord-style resolution), while the client exposes the full REST API through AccordKit. The client provides admin dialogs for all major management features, accessible via right-click context menus on guild icons, the channel list banner dropdown, and member items. All admin dialogs include search/filter, bulk operations (where applicable), reordering controls, unsaved changes warnings, and visual feedback for async actions. The `Client` autoload routes API calls, caches roles, handles gateway events for roles/bans/invites/emojis, and exposes permission checking via `has_permission()`.

## User Steps

### Accessing Admin Tools
1. Admin right-clicks guild icon in the guild bar to see permission-gated menu items
2. **Or** admin clicks the channel list banner (visible dropdown chevron when user has any admin permission) to see the same permission-gated menu
3. Available menu items depend on permissions: Space Settings (`manage_space`), Channels (`manage_channels`), Roles (`manage_roles`), Bans (`ban_members`), Invites (`create_invites`), Emojis (`manage_emojis`)

### Space Settings
1. Admin opens "Space Settings" dialog
2. Admin edits name, description, verification level, default notifications, or public flag
3. If admin is the space owner, a "Danger Zone" section is visible with a "Delete Server" button
4. Closing the dialog with unsaved changes shows an "Unsaved Changes" confirmation prompt
5. Changes are saved via `PATCH /spaces/{id}`
6. Gateway broadcasts `space_update` to all members

### Channel Management
1. Admin opens "Channels" dialog
2. Admin can search/filter the channel list by name via the search input
3. Admin creates a channel (name, type, parent category) via `POST /spaces/{id}/channels`
4. Admin edits channel settings (name, topic, NSFW) via a dedicated edit dialog scene; closing with unsaved changes shows a confirmation prompt
5. Admin reorders channels via up/down arrow buttons, which call `Client.reorder_channels()` -> `PATCH /spaces/{id}/channels`
6. Admin configures per-channel permission overwrites via the "Perms" button, which opens the channel permissions dialog
7. Admin selects multiple channels via checkboxes and bulk deletes them
8. Admin deletes a single channel via `DELETE /channels/{id}` with confirmation
9. Gateway broadcasts `channel_create`, `channel_update`, or `channel_delete`

### Channel Permission Overwrites
1. Admin clicks "Perms" button on a channel row in channel management dialog
2. The channel permissions dialog opens with a two-panel layout: roles on left, permissions on right
3. Admin selects a role to view/edit its overwrite state for each of the 37 permissions
4. Each permission has three states: Allow (green checkmark), Inherit (gray slash), Deny (red X)
5. Admin can reset all permissions for a role to Inherit via the "Reset" button
6. On save, the dialog builds an overwrites array and calls `Client.update_channel_overwrites()` -> `PATCH /channels/{id}`
7. Server validates permission strings against the full 37-permission set
8. Effective permissions are resolved using a Discord-style algorithm: base role permissions + @everyone overwrite + union of assigned role overwrites + member-specific overwrite, with deny taking precedence except where allow overrides across roles

### Member Management
1. Admin views member list in the right sidebar panel
2. Admin right-clicks a member to open context menu (skip if target is self)
3. "Kick" shown if user has `kick_members` permission; opens ConfirmDialog, then calls `Client.kick_member()`
4. "Ban" shown if user has `ban_members` permission; opens BanDialog with optional reason, calls `Client.ban_member()`
5. Role checkboxes shown if user has `manage_roles` permission; toggling awaits the API call, disables the menu item during the request, and shows visual feedback (green flash on success, red flash on failure with checkbox revert)
6. Gateway broadcasts `member_leave`, `ban_create`, `member_update`

### Role Management
1. Admin opens "Roles" dialog
2. Admin can search/filter the role list by name via the search input
3. Admin creates a role (name, color, permissions, hoist, mentionable)
4. Admin edits a role's properties (hierarchy check prevents editing roles at or above own highest role)
5. Admin reorders roles via up/down arrow buttons (except @everyone which stays at position 0), calling `Client.reorder_roles()` -> `PATCH /spaces/{id}/roles`
6. Admin deletes a role (@everyone cannot be deleted)
7. Closing the dialog with unsaved changes in the editor panel shows an "Unsaved Changes" confirmation prompt
8. Gateway broadcasts `role_create`, `role_update`, `role_delete`

### Ban List Management
1. Admin opens "Bans" dialog
2. Admin can search/filter the ban list by username via the search input
3. Admin unbans individual users with confirmation
4. Admin selects multiple bans via checkboxes and bulk unbans them with confirmation
5. Gateway broadcasts `ban_delete`

### Invite Management
1. Admin opens "Invites" dialog
2. Admin can search/filter the invite list by code via the search input
3. Admin creates a space-level invite via `POST /spaces/{id}/invites` with configurable max_age, max_uses, temporary
4. Admin copies an invite code to clipboard
5. Admin revokes an individual invite via `DELETE /invites/{code}` with confirmation
6. Admin selects multiple invites via checkboxes and bulk revokes them with confirmation
7. Gateway broadcasts `invite_create`, `invite_delete`

### Emoji Management
1. Admin opens "Emojis" dialog
2. Admin can search/filter the emoji grid by name via the search input
3. Emoji grid cells display CDN images loaded via `HTTPRequest` (with colored placeholder during loading/on failure)
4. Admin uploads a new emoji from file; the emoji name is derived from the filename and validated (alphanumeric + underscore, no duplicates)
5. Admin deletes an emoji via `DELETE /spaces/{id}/emojis/{emoji_id}` with confirmation
6. Gateway broadcasts `emoji_update` to all members

### Public Space Discovery
1. Any authenticated user can list public spaces via `GET /spaces/public`
2. User joins a public space via `POST /spaces/{id}/join` (ban check enforced)
3. No invite code is needed for public spaces

## Signal Flow

```
Admin action (guild icon context menu / banner dropdown / member context menu / member list invite button)
  │
  ├─ Space settings ─────► Client.update_space() ──► PATCH /spaces/{id}
  │                        Client.delete_space() ──► DELETE /spaces/{id}
  │                                                        │
  │                                                   space_update/delete (gateway)
  │                                                        │
  │                                              AccordClient.space_update signal (line 11)
  │                                                        │
  │                                              Client._on_space_update() (line 705)
  │                                                        │
  │                                              AppState.guilds_updated
  │
  ├─ Channel CRUD ───────► Client.create_channel()           ──► POST /spaces/{id}/channels
  │                        Client.update_channel()           ──► PATCH /channels/{id}
  │                        Client.delete_channel()           ──► DELETE /channels/{id}
  │                        Client.reorder_channels() (ln741) ──► PATCH /spaces/{id}/channels
  │                        Client.update_channel_overwrites()──► PATCH /channels/{id}
  │                                                               │
  │                                             channel_create/update/delete (gateway)
  │                                                               │
  │                                             AccordClient signals (lines 15-17)
  │                                                               │
  │                                             Client._on_channel_create() (line 716)
  │                                             Client._on_channel_update() (line 737)
  │                                             Client._on_channel_delete() (line 758)
  │                                                               │
  │                                             AppState.channels_updated
  │
  ├─ Member actions ─────► Client.kick_member()       ──► DELETE /spaces/{id}/members/{uid}
  │                        Client.ban_member()        ──► PUT /spaces/{id}/bans/{uid}
  │                        Client.add_member_role()   ──► PUT /spaces/{id}/members/{uid}/roles/{rid}
  │                        Client.remove_member_role()──► DELETE /spaces/{id}/members/{uid}/roles/{rid}
  │                                                          │
  │                                            member_leave/ban_create/member_update (gateway)
  │                                                          │
  │                                            Client._on_member_join() (line 642)
  │                                            Client._on_member_leave() (line 664)
  │                                            Client._on_member_update() (line 681)
  │                                                          │
  │                                            AppState.members_updated
  │                                                          │
  │                                            member_list._on_members_updated() (line 38)
  │
  ├─ Role CRUD ──────────► Client.create_role()        ──► POST /spaces/{id}/roles
  │                        Client.update_role()        ──► PATCH /spaces/{id}/roles/{rid}
  │                        Client.delete_role()        ──► DELETE /spaces/{id}/roles/{rid}
  │                        Client.reorder_roles()(748) ──► PATCH /spaces/{id}/roles
  │                                                         │
  │                                            role_create/update/delete (gateway)
  │                                                         │
  │                                            Client._on_role_create/update/delete()
  │                                                         │
  │                                            AppState.roles_updated
  │
  ├─ Invite CRUD ────────► Client.create_invite()   ──► POST /spaces/{id}/invites
  │                        Client.delete_invite()    ──► DELETE /invites/{code}
  │                                                                │
  │                                                   invite_create/delete (gateway)
  │                                                                │
  │                                                   Client._on_invite_create/delete()
  │                                                                │
  │                                                   AppState.invites_updated
  │
  └─ Emoji CRUD ─────────► Client.create_emoji()  ──► POST /spaces/{id}/emojis
                           Client.update_emoji()   ──► PATCH /spaces/{id}/emojis/{eid}
                           Client.delete_emoji()   ──► DELETE /spaces/{id}/emojis/{eid}
                           Client.get_emoji_url()  ──► CDN URL for emoji image (line 736)
                                                               │
                                                   emoji_update (gateway)
                                                               │
                                                   Client._on_emoji_update()
                                                               │
                                                   AppState.emojis_updated
```

## Key Files

### Client (AccordKit REST API)
| File | Role |
|------|------|
| `addons/accordkit/rest/endpoints/spaces_api.gd` | Space CRUD + channel creation/reordering + public join |
| `addons/accordkit/rest/endpoints/channels_api.gd` | Channel fetch/update/delete |
| `addons/accordkit/rest/endpoints/members_api.gd` | Member list/search/fetch/update/kick + role assignment |
| `addons/accordkit/rest/endpoints/roles_api.gd` | Role CRUD + reordering |
| `addons/accordkit/rest/endpoints/bans_api.gd` | Ban list/fetch/create/remove |
| `addons/accordkit/rest/endpoints/invites_api.gd` | Invite fetch/delete/accept/list/create |
| `addons/accordkit/rest/endpoints/emojis_api.gd` | Emoji list/fetch/create/update/delete |

### Client (Models & Permissions)
| File | Role |
|------|------|
| `addons/accordkit/models/permission.gd` | 37 permission string constants + `has()` check |
| `addons/accordkit/models/permission_overwrite.gd` | Channel-level overwrite model (id, type, allow, deny) |
| `addons/accordkit/models/member.gd` | Member model with user_id, space_id, nickname, roles array |
| `addons/accordkit/models/role.gd` | Role model with id, name, color, position, permissions, hoist, mentionable |
| `addons/accordkit/models/invite.gd` | Invite model with code, max_uses, max_age, temporary, expires_at |
| `addons/accordkit/models/emoji.gd` | Emoji model with id, name, animated, role_ids, creator_id |
| `addons/accordkit/models/space.gd` | Space model with roles and emojis arrays (populated on fetch) |

### Client (Autoloads & UI)
| File | Role |
|------|------|
| `scripts/autoload/client.gd` | Routes API calls, caches members + roles, handles all gateway events, permission helpers, admin API wrappers (`reorder_channels`, `reorder_roles`, `update_channel_overwrites`, `get_emoji_url`), `disconnect_server()` |
| `scripts/autoload/app_state.gd` | Signal bus: `members_updated`, `guilds_updated`, `channels_updated`, `roles_updated`, `bans_updated`, `invites_updated`, `emojis_updated` |
| `scripts/autoload/client_models.gd` | `member_to_dict()`, `role_to_dict()`, `invite_to_dict()`, `emoji_to_dict()`, `channel_to_dict()` converters. `channel_to_dict()` now includes `position` and `permission_overwrites` fields |
| `scripts/autoload/config.gd` | Persists server configs; `add_server()`, `remove_server()`, `clear()` |
| `scenes/members/member_list.gd` | Virtual-scrolling member list grouped by status; "Invite People" button (gated to `create_invites`) |
| `scenes/members/member_item.gd` | Member display with right-click context menu (kick, ban, role assignment with visual feedback) |
| `scenes/sidebar/channels/banner.gd` | Channel list banner with admin dropdown menu (permission-gated, same items as guild icon context menu) |

### Admin Dialogs
| File | Role |
|------|------|
| `scenes/admin/confirm_dialog.tscn/.gd` | Reusable confirmation dialog with danger mode |
| `scenes/admin/ban_dialog.tscn/.gd` | Ban dialog with optional reason field |
| `scenes/admin/space_settings_dialog.tscn/.gd` | Space settings form (name, description, verification, notifications, public, danger zone with delete for owner); unsaved changes warning |
| `scenes/admin/channel_management_dialog.tscn/.gd` | Channel list with search, create, edit, reorder (up/down), permissions, bulk select/delete |
| `scenes/admin/channel_edit_dialog.tscn/.gd` | Extracted channel edit form (name, topic, NSFW) with unsaved changes warning |
| `scenes/admin/channel_permissions_dialog.tscn/.gd` | Two-panel channel permission overwrite editor (role list + allow/inherit/deny toggles for all 37 permissions) |
| `scenes/admin/role_management_dialog.tscn/.gd` | Two-panel role editor with search, reorder (up/down), all 37 permissions, unsaved changes warning |
| `scenes/admin/ban_list_dialog.tscn/.gd` | Ban list with search, unban, bulk select/unban |
| `scenes/admin/invite_management_dialog.tscn/.gd` | Invite list with search, create (age/uses/temporary), copy, revoke, bulk select/revoke |
| `scenes/admin/emoji_management_dialog.tscn/.gd` | Emoji grid with search, CDN image loading, upload with name validation, delete |

### Client (Gateway Signals)
| File | Role |
|------|------|
| `addons/accordkit/core/accord_client.gd` | Declares all gateway signals including admin events |

### Server (Routes)
| File | Role |
|------|------|
| `accordserver/src/routes/spaces.rs` | Space CRUD + channel creation/reordering + public join/list |
| `accordserver/src/routes/channels.rs` | Channel CRUD + permission overwrite CRUD |
| `accordserver/src/routes/members.rs` | Member list/search/update/kick + role assignment |
| `accordserver/src/routes/roles.rs` | Role CRUD + reordering with hierarchy checks |
| `accordserver/src/routes/bans.rs` | Ban CRUD with hierarchy enforcement |
| `accordserver/src/routes/invites.rs` | Invite CRUD + accept with ban check |
| `accordserver/src/routes/emojis.rs` | Emoji CRUD with `manage_emojis` permission |
| `accordserver/src/middleware/permissions.rs` | Permission resolution, hierarchy checks, channel overwrites |

### Server (Database)
| File | Role |
|------|------|
| `accordserver/src/db/spaces.rs` | Space DB operations, auto-creates default roles + #general channel on space creation |
| `accordserver/src/db/members.rs` | Member DB operations + role assignment via member_roles table |
| `accordserver/src/db/roles.rs` | Role DB operations + reordering |
| `accordserver/src/db/bans.rs` | Ban DB operations (create also removes member) |
| `accordserver/src/db/permission_overwrites.rs` | Channel permission overwrite DB operations (upsert uses ON CONFLICT) |

## Implementation Details

### Permission System

The server defines 37 granular permissions as string constants in `permission.gd` (lines 6-42). The client-side `AccordPermission.has()` (line 87) checks if a user holds a permission, with `administrator` granting all permissions implicitly. The `AccordPermission.all()` static method (line 45) returns the complete list.

The server resolves permissions in `middleware/permissions.rs`:
- `resolve_member_permissions()` (line 110) -- returns `["administrator"]` for instance admins and space owners; otherwise merges @everyone role permissions with all assigned role permissions.
- `resolve_channel_permissions()` (line 216) -- applies Discord-style overwrite resolution on top of base permissions: (1) @everyone role overwrite, (2) union of user's assigned role overwrites (allow wins across roles), (3) member-specific overwrite. Administrator bypasses all overwrites.
- `require_permission()` (line 185) -- validates a user has a specific permission string.
- `require_channel_permission()` (line 312) -- validates a user has a specific permission for a channel (accounts for overwrites). Returns the space_id on success.
- `require_hierarchy()` (line 370) -- prevents actions on users with higher role positions. Space owner returns `i64::MAX`.
- `require_role_hierarchy()` (line 388) -- prevents managing roles at or above the actor's highest role position.
- `require_membership()` (line 199) -- shorthand for `require_permission(... "view_channel")`.
- `require_channel_membership()` (line 331) -- shorthand for channel-level view_channel check.

**Default roles created on space creation** (in `db/spaces.rs`, lines 64-102):
- **@everyone** (position 0): view_channel, send_messages, read_history, add_reactions, create_invites, change_nickname, connect, speak, use_vad, embed_links, attach_files, use_external_emojis, stream
- **Moderator** (position 1, color `#3498DB` / 3447003): all @everyone + kick_members, ban_members, manage_messages, mute_members, deafen_members, move_members, manage_nicknames, moderate_members, mention_everyone, manage_threads, manage_events
- **Admin** (position 2, color `#E74C3C` / 15158332): all Moderator + manage_channels, manage_space, manage_roles, manage_webhooks, manage_emojis, view_audit_log, priority_speaker

The space owner is auto-added as a member and assigned the Admin role (lines 114-127 of `db/spaces.rs`). A default `#general` text channel is also created (lines 104-112).

### Channel Permission Overwrites

Channels support per-role and per-member permission overwrites via `AccordPermissionOverwrite` (lines 1-28 of `permission_overwrite.gd`). Each overwrite has an `id` (role or member ID), `type` ("role" or "member"), and `allow`/`deny` arrays of permission strings.

Server-side, `channels.rs` exposes:
- `list_overwrites()` (line 53) -- requires `manage_roles` via channel permission check
- `upsert_overwrite()` (line 63) -- validates type is "role" or "member", validates all permission strings against `ALL_PERMISSIONS`, uses `INSERT ... ON CONFLICT DO UPDATE` (line 37 of `db/permission_overwrites.rs`)
- `delete_overwrite()` (line 96) -- requires `manage_roles`

The server resolves effective channel permissions via `resolve_channel_permissions()` (line 216 of `permissions.rs`) using a five-step Discord-style algorithm:
1. Start with base space permissions from `resolve_member_permissions()`
2. If base includes `administrator`, return immediately (bypass)
3. Apply @everyone role overwrite: deny removes, allow adds
4. Union of user's assigned role overwrites: collect all allow/deny, allow wins over deny across roles, then apply
5. Apply member-specific overwrite: deny removes, allow adds (highest precedence)

### Space CRUD (AccordKit)

`spaces_api.gd` provides:
- `create(data)` (line 16) -- POST /spaces, returns `AccordSpace`
- `fetch(space_id)` (line 24) -- GET /spaces/{id}
- `update(space_id, data)` (line 32) -- PATCH /spaces/{id}, returns updated `AccordSpace`
- `delete(space_id)` (line 40) -- DELETE /spaces/{id}, requires owner
- `list_channels(space_id)` (line 46) -- GET /spaces/{id}/channels
- `create_channel(space_id, data)` (line 58) -- POST /spaces/{id}/channels
- `reorder_channels(space_id, data)` (line 67) -- PATCH /spaces/{id}/channels
- `join(space_id)` (line 73) -- POST /spaces/{id}/join for public spaces

Server-side `spaces.rs`:
- `delete_space()` (line 48) -- requires `owner_id == auth.user_id` or instance admin
- `update_space()` (line 37) -- requires `manage_space` permission. Supports updating: name, description, icon, banner, verification_level, default_notifications, afk_channel_id, afk_timeout, system_channel_id, rules_channel_id, preferred_locale, public
- `list_public_spaces()` (line 155) -- no auth required, lists all public spaces
- `join_public_space()` (line 162) -- checks ban status before allowing join

### Channel CRUD (AccordKit)

`channels_api.gd` provides:
- `fetch(channel_id)` (line 15) -- GET /channels/{id}
- `update(channel_id, data)` (line 23) -- PATCH /channels/{id}, returns `AccordChannel`
- `delete(channel_id)` (line 32) -- DELETE /channels/{id}

Channel creation and reordering live on `spaces_api.gd`:
- `create_channel(space_id, data)` (line 58) -- POST /spaces/{id}/channels
- `reorder_channels(space_id, data)` (line 67) -- PATCH /spaces/{id}/channels

Server requires `manage_channels` for create, update, delete, and reorder. Channel JSON responses include `permission_overwrites` array (lines 118-141 of `spaces.rs`).

### Member Management (AccordKit)

`members_api.gd` provides:
- `list(space_id, query)` (line 16) -- cursor-based pagination with `limit` and `after`
- `search(space_id, query_str, query)` (line 29) -- search by username/nickname
- `fetch(space_id, user_id)` (line 45) -- single member lookup
- `update(space_id, user_id, data)` (line 53) -- update nickname, roles, mute, deaf
- `kick(space_id, user_id)` (line 62) -- remove member from space
- `update_me(space_id, data)` (line 68) -- update own nickname
- `add_role(space_id, user_id, role_id)` (line 76) -- assign role to member
- `remove_role(space_id, user_id, role_id)` (line 86) -- remove role from member

Server-side hierarchy enforcement:
- `kick_member()` (line 105 of `members.rs`) -- requires `kick_members` + hierarchy check
- `update_member()` (line 91) -- requires `manage_nicknames`
- `update_own_member()` (line 116) -- limits to nickname only, requires `change_nickname`
- `add_role()`/`remove_role()` (lines 136, 148) -- requires `manage_roles` + role hierarchy check

Server-side member list supports cursor-based pagination (line 26 of `members.rs`): default limit 50, max 1000, returns `cursor.has_more` and `cursor.after` when more pages exist.

### Ban Management (AccordKit)

`bans_api.gd` provides:
- `list(space_id, query)` (line 16) -- list bans with pagination
- `fetch(space_id, user_id)` (line 22) -- get specific ban
- `create(space_id, user_id, data)` (line 29) -- ban user (optional `{"reason": "..."}` in data)
- `remove(space_id, user_id)` (line 35) -- unban user

Server-side `bans.rs`:
- `create_ban()` (line 56) -- requires `ban_members` + hierarchy check; body accepts optional `reason` field. DB-level `create_ban()` (line 53 of `db/bans.rs`) also removes the member before inserting the ban.
- All ban routes require `ban_members` permission

### Invite Management (AccordKit)

`invites_api.gd` provides:
- `fetch(code)` (line 15) -- get invite details (any authenticated user)
- `delete(code)` (line 23) -- revoke invite (requires `manage_channels`)
- `accept(code)` (line 29) -- join via invite (checks ban status)
- `list_space(space_id)` (line 35) -- list space invites (requires membership)
- `list_channel(channel_id)` (line 47) -- list channel invites (requires `view_channel`)
- `create_space(space_id, data)` (line 60) -- create space invite (max_age, max_uses, temporary)
- `create_channel(channel_id, data)` (line 69) -- create channel invite

Server-side `invites.rs`:
- `accept_invite()` (line 40) -- uses invite (increments uses count), checks ban status, then adds member
- `delete_invite()` (line 23) -- requires `manage_channels` in the invite's space
- `create_space_invite()` (line 100) -- requires `create_invites`
- `create_channel_invite()` (line 81) -- requires `create_invites` via channel permission check

### Role Management (AccordKit)

`roles_api.gd` provides:
- `list(space_id)` (line 15) -- list all roles (ordered by position)
- `create(space_id, data)` (line 27) -- create role (auto-assigned next position)
- `update(space_id, role_id, data)` (line 35) -- update role (name, color, permissions, hoist, icon, position, mentionable)
- `delete(space_id, role_id)` (line 43) -- delete role
- `reorder(space_id, data)` (line 50) -- reorder roles, returns updated list

Server-side `roles.rs`:
- `create_role()` (line 22) -- requires `manage_roles`; auto-assigns position as MAX(position)+1 (line 64 of `db/roles.rs`)
- `update_role()` (line 33) -- requires `manage_roles` + role hierarchy check (cannot edit roles at or above own)
- `delete_role()` (line 46) -- prevents deleting @everyone (position 0); enforces role hierarchy
- `reorder_roles()` (line 61) -- validates only @everyone stays at position 0

### Emoji Management (AccordKit)

`emojis_api.gd` provides:
- `list(space_id)` (line 15) -- list all custom emojis (any member)
- `fetch(space_id, emoji_id)` (line 27) -- get single emoji
- `create(space_id, data)` (line 36) -- create emoji (name, image base64, optional roles)
- `update(space_id, emoji_id, data)` (line 44) -- update name or role restrictions
- `delete(space_id, emoji_id)` (line 53) -- delete emoji

Server-side `emojis.rs`:
- `list_emojis()` / `get_emoji()` -- requires membership only
- `create_emoji()` (line 31) -- requires `manage_emojis`
- `update_emoji()` (line 42) -- requires `manage_emojis`
- `delete_emoji()` (line 53) -- requires `manage_emojis`

### Gateway Event Handling

`AccordClient` (lines 1-70 of `accord_client.gd`) declares gateway signals for all admin events:
- Space: `space_create`, `space_update`, `space_delete` (lines 10-12)
- Channel: `channel_create`, `channel_update`, `channel_delete` (lines 15-17); also `channel_pins_update` (line 18)
- Member: `member_join`, `member_leave`, `member_update` (lines 21-23); also `member_chunk` (line 24)
- Role: `role_create`, `role_update`, `role_delete` (lines 27-29)
- Ban: `ban_create`, `ban_delete` (lines 56-57)
- Invite: `invite_create`, `invite_delete` (lines 60-61)
- Emoji: `emoji_update` (line 67)

`Client` autoload connects gateway signals in `connect_server()` (lines 207-222):

**Connected signals (with handlers):**
- `space_create` → `_on_space_create()` (line 698) -- updates `_guild_cache` if space matches connection's guild_id, emits `guilds_updated`
- `space_update` → `_on_space_update()` (line 705) -- updates `_guild_cache`, emits `guilds_updated`
- `space_delete` → `_on_space_delete()` (line 710) -- removes from `_guild_cache` and `_guild_to_conn`, emits `guilds_updated`
- `member_join` → `_on_member_join()` (line 642) -- fetches user if not cached, appends to `_member_cache`, emits `members_updated`
- `member_leave` → `_on_member_leave()` (line 664) -- removes from `_member_cache`, emits `members_updated`
- `member_update` → `_on_member_update()` (line 681) -- updates in `_member_cache`, emits `members_updated`
- `channel_create` → `_on_channel_create()` (line 716) -- handles both DM and space channels; updates `_channel_cache` or `_dm_channel_cache`, emits `channels_updated` or `dm_channels_updated`
- `channel_update` → `_on_channel_update()` (line 737) -- same DM/space routing as create
- `channel_delete` → `_on_channel_delete()` (line 758) -- removes from cache, cleans up `_channel_to_guild` map

**Also connected (with handlers):**
- `role_create` → `_on_role_create()` -- adds role to `_role_cache`, emits `roles_updated`
- `role_update` → `_on_role_update()` -- updates role in `_role_cache`, emits `roles_updated`
- `role_delete` → `_on_role_delete()` -- removes role from `_role_cache`, emits `roles_updated`
- `ban_create` → `_on_ban_create()` -- emits `bans_updated`
- `ban_delete` → `_on_ban_delete()` -- emits `bans_updated`
- `invite_create` → `_on_invite_create()` -- emits `invites_updated`
- `invite_delete` → `_on_invite_delete()` -- emits `invites_updated`
- `emoji_update` → `_on_emoji_update()` -- emits `emojis_updated`

**NOT connected (no handlers):**
- `channel_pins_update`, `member_chunk` -- not processed

### Member List UI

`member_list.gd` displays a virtual-scrolling member panel:
- Connects to `AppState.guild_selected` (line 31) and `AppState.members_updated` (line 32)
- `_rebuild_row_data()` (line 49) groups members by status (ONLINE, IDLE, DND, OFFLINE) and sorts alphabetically within each group
- Uses a fixed `ROW_HEIGHT` of 44px (line 6) with object pooling for performance (`_ensure_pool_size()` at line 96)
- Data source: `Client.get_members_for_guild()` (line 51) which reads from `_member_cache`
- **Invite People button**: An "Invite People" button (blue, centered) appears between the "MEMBERS" header and the member scroll area when the user has `CREATE_INVITES` permission. Clicking it opens the Invite Management dialog for the current guild.

`member_item.gd` renders each member:
- Avatar with circle shader, display name, and colored status dot (lines 14-27)
- Status colors: online=green (#3BA55D), idle=yellow (#FAA81A), DND=red (#ED4245), offline=gray (#949BA4)

### Data Flow for Members

The `AccordMember` model (lines 1-69 of `member.gd`) includes a `roles` array (line 10) that is populated from the API response (lines 33-36). `ClientModels.member_to_dict()` now copies user fields + nickname override + `roles` array + `joined_at` string. The roles array is used by the member context menu for role toggle checkboxes.

The `AccordSpace` model (lines 1-137 of `space.gd`) includes `roles` (line 17) and `emojis` (line 18) arrays. `ClientModels.space_to_guild_dict()` now extracts id, name, icon_color, owner_id, description, verification_level, default_notifications, preferred_locale, and public flag. The admin settings dialog reads these fields.

### Admin Dialog UX Features

The following cross-cutting UX improvements are implemented across all admin dialogs:

**Banner Admin Dropdown** (`banner.gd`):
- Caches `_has_admin` (line 12) by checking all six admin permissions in `_has_any_admin_perm()` (line 35)
- Shows a dropdown chevron (`$DropdownIcon`) when user has any admin permission (line 33)
- Clicking the banner opens a `PopupMenu` (line 53) with permission-gated items matching the guild icon context menu
- Each menu item instantiates the corresponding admin dialog scene (line 88)

**Search/Filter** (all admin list dialogs):
- Each dialog has a `_search_input: LineEdit` between the header and scroll container
- Connected to `_on_search_changed()` which filters the stored full list (`_all_channels`, `_all_roles`, `_all_bans`, `_all_invites`, `_all_emojis`) by name/code (case-insensitive `contains()`)
- Clearing the search restores the full list
- Channel management: `_on_search_changed()` at line 163
- Role management: `_on_search_changed()` at line 133
- Ban list: `_on_search_changed()` at line 142
- Invite management: `_on_search_changed()` at line 167
- Emoji management: `_on_search_changed()` at line 141

**Bulk Operations** (channel, invite, ban dialogs):
- Each row has a `CheckBox` for selection; a "Select All" checkbox toggles all items
- When items are selected, a bulk action button appears with a count badge (e.g., "Delete Selected (3)")
- Bulk delete/revoke/unban shows a ConfirmDialog before proceeding
- Bulk operations loop through selected items with `await` for each API call
- Channel management: `_on_bulk_delete()` at line 197, `_on_select_all()` at line 181
- Invite management: `_on_bulk_revoke()` at line 201, `_on_select_all()` at line 185
- Ban list: `_on_bulk_unban()` at line 177, `_on_select_all()` at line 160

**Channel/Role Reordering** (channel and role management dialogs):
- Each channel/role row has up (`▲`) and down (`▼`) flat buttons
- On press, swaps the item's position with its neighbor and calls `Client.reorder_channels()` (line 741 of client.gd) or `Client.reorder_roles()` (line 748)
- Role reordering prevents moving @everyone (position 0) and skips @everyone as a swap target
- Channel management: `_on_move_channel()` at line 216
- Role management: `_on_move_role()` at line 144

**Channel Permission Overwrites UI** (`channel_permissions_dialog.gd`):
- Two-panel layout: role list on left (`$Content/RoleScroll/RoleList`), permission toggles on right (`$Content/PermScroll/PermList`)
- `OverwriteState` enum (line 4): `INHERIT`, `ALLOW`, `DENY`
- `_overwrite_data` dict (line 10) maps `role_id -> { perm_name -> OverwriteState }`
- `_load_overwrites()` (line 35) reads existing overwrites from channel's `permission_overwrites` array
- `_rebuild_perm_list()` (line 90) creates a row per permission with three buttons: Allow (green `✓`), Inherit (gray `/`), Deny (red `✗`)
- `_toggle_perm()` (line 145) sets the new state and rebuilds the permission list
- `_on_reset()` (line 153) sets all permissions for the selected role to INHERIT
- `_on_save()` (line 163) builds overwrites array (only includes roles with non-INHERIT entries) and calls `Client.update_channel_overwrites()` (line 755 of client.gd)

**Channel Edit Dialog** (`channel_edit_dialog.gd`):
- Extracted from inline code-built dialog into a proper `.tscn`/`.gd` pair
- `setup(channel: Dictionary)` (line 28) populates name, topic, NSFW from channel data
- `saved` signal (line 5) emitted on successful update
- Includes unsaved changes warning (see below)

**Unsaved Changes Warning** (space settings, channel edit, role management):
- Each dialog tracks `_dirty: bool` (set to `false` initially)
- Input signals (`text_changed`, `toggled`, `color_changed`, `item_selected`) set `_dirty = true`
- `_try_close()` checks if dirty: if yes, shows a ConfirmDialog ("You have unsaved changes. Discard?") with danger mode; on confirm, resets dirty and calls `queue_free()`
- All close paths (`_close`, `_gui_input` overlay click, `_unhandled_input` ESC key) route through `_try_close()`
- After successful save, `_dirty` is reset to `false`
- Space settings: `_dirty` at line 6, `_try_close()` at line 120
- Channel edit: `_dirty` at line 8, `_try_close()` at line 61
- Role management: `_dirty` at line 9, `_try_close()` at line 270

**Space Settings Danger Zone** (`space_settings_dialog.tscn/.gd`):
- A "DANGER ZONE" section with a red label and HSeparator is placed below the save button
- Contains the "Delete Server" button, isolated from the save area
- The entire `_danger_zone` VBoxContainer is only visible when the current user is the space owner (`Client.is_space_owner()` at line 64)

**Emoji CDN Images** (`emoji_management_dialog.gd`):
- Each emoji cell displays a CDN image loaded via `HTTPRequest` (line 93)
- The URL is obtained from `Client.get_emoji_url()` (line 92) which calls `AccordCDN.emoji()`
- A colored `ColorRect` placeholder is shown during loading; hidden when the image loads successfully (line 117)
- On HTTP failure (non-200), the placeholder remains visible

**Emoji Name Validation** (`emoji_management_dialog.gd`):
- Emoji name derived from filename: spaces/hyphens replaced with underscores, lowercased (line 172)
- Empty name check (line 175)
- Regex validation: `^[a-z0-9_]+$` (line 181) rejects names with special characters
- Duplicate name check against `_all_emojis` (line 188)

**Role Toggle Feedback** (`member_item.gd`):
- `_toggle_role()` (line 115) now `await`s the API result from `Client.add_member_role()` or `Client.remove_member_role()`
- The context menu item is disabled during the API call (line 131) to prevent double-toggling
- On success: green flash via `_flash_feedback()` (line 149) using a `Tween` on modulate
- On failure: red flash and checkbox state is reverted (lines 142-147)

## Implementation Status

- [x] Full REST API for space CRUD (AccordKit `spaces_api.gd`)
- [x] Full REST API for channel CRUD (AccordKit `channels_api.gd` + `spaces_api.gd`)
- [x] Full REST API for member management (AccordKit `members_api.gd`)
- [x] Full REST API for role management (AccordKit `roles_api.gd`)
- [x] Full REST API for ban management (AccordKit `bans_api.gd`)
- [x] Full REST API for invite management (AccordKit `invites_api.gd`)
- [x] Full REST API for emoji management (AccordKit `emojis_api.gd`)
- [x] Permission model with 37 permissions (AccordKit `permission.gd`)
- [x] Channel permission overwrites model (AccordKit `permission_overwrite.gd`)
- [x] Discord-style channel permission resolution with overwrites (`permissions.rs:216`)
- [x] Server-side permission enforcement with role hierarchy
- [x] Gateway signals for all admin events (AccordClient lines 10-67)
- [x] Client-side member cache + gateway handlers for member join/leave/update
- [x] Client-side space cache + gateway handlers for space create/update/delete
- [x] Client-side channel cache + gateway handlers for channel create/update/delete (both DM and space)
- [x] Member list UI with virtual scrolling and status grouping
- [x] Public space listing and join (server-side)
- [x] Auto-creation of default roles (@everyone, Moderator, Admin) and #general channel on space creation
- [x] Space settings dialog (edit name, description, verification, notifications, public; danger zone with delete for owner; unsaved changes warning)
- [x] Channel management dialog (create, edit via extracted scene, delete, search/filter, reorder up/down, permissions button, bulk select/delete)
- [x] Channel edit dialog (extracted `.tscn`/`.gd` pair with name, topic, NSFW; unsaved changes warning)
- [x] Channel permission overwrite editor UI (two-panel: role list + allow/inherit/deny toggles for all 37 permissions)
- [x] Role management dialog (two-panel editor with all 37 permissions, create/save/delete, search/filter, reorder up/down, unsaved changes warning)
- [x] Member context menu (kick with confirm, ban with reason, role toggle checkboxes with visual feedback)
- [x] Ban list dialog (view bans, unban with confirm, search/filter, bulk select/unban)
- [x] Invite management dialog (create with age/uses/temporary, list, copy code, revoke, search/filter, bulk select/revoke)
- [x] Emoji management dialog (grid view with CDN images, upload from file with name validation, delete with confirm, search/filter)
- [x] Client-side role gateway event handlers (role_create/update/delete wired + cached)
- [x] Client-side ban gateway event handlers (ban_create/delete emit bans_updated)
- [x] Client-side invite gateway event handlers (invite_create/delete emit invites_updated)
- [x] Client-side emoji gateway event handler (emoji_update emits emojis_updated)
- [x] Client-side role cache (`_role_cache` populated on gateway ready via `fetch_roles()`)
- [x] Client-side permission checking (`has_permission()`, `is_space_owner()`) gates admin UI
- [x] Server removal UI (guild icon context menu "Remove Server" with confirm dialog)
- [x] Reusable ConfirmDialog (title, message, confirm text, danger mode)
- [x] Guild icon right-click context menu as entry point for all admin dialogs
- [x] Guild banner clickable dropdown as additional admin entry point
- [x] "Invite People" button in member list (gated to `create_invites`, opens invite management dialog)
- [x] Channel reordering UI (up/down buttons calling `Client.reorder_channels()`)
- [x] Role reordering UI (up/down buttons calling `Client.reorder_roles()`)
- [x] Search/filter in all admin list dialogs (channels, roles, bans, invites, emojis)
- [x] Bulk operations (channels: bulk delete; invites: bulk revoke; bans: bulk unban)
- [x] Unsaved changes warning (space settings, channel edit, role management)
- [x] Emoji CDN image loading (via `HTTPRequest` + `Client.get_emoji_url()`)
- [x] Emoji name validation (alphanumeric + underscore, no duplicates)
- [x] Role toggle visual feedback (green/red flash, disabled during API call)
- [ ] Audit log viewer

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `fetch_members()` uses hardcoded limit of 1000 | Low | May miss members in large spaces. The server supports cursor-based pagination but the client does not follow cursors. |
| No audit log support | Low | `AccordPermission.VIEW_AUDIT_LOG` exists and the Admin default role includes it, but no audit log API endpoints or UI exist. |
| Channel permission overwrite editor only supports role overwrites | Low | The dialog builds all overwrites as `"type": "role"` (line 184 of `channel_permissions_dialog.gd`). Member-specific overwrites are supported by the server but not exposed in the UI. |
| Emoji CDN GIF loading uses `load_png_from_buffer()` | Low | Animated emojis (`.gif`) are loaded using `load_png_from_buffer()` (line 103 of `emoji_management_dialog.gd`), which won't decode GIF frames correctly. Requires a GIF decoder or sprite sheet approach. |
| Bulk operations are sequential | Low | Bulk delete/revoke/unban calls `await` in a loop for each item. Could be parallelized or batched for better performance on large selections. |
