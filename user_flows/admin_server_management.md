# Admin Server Management

## Overview

Admins manage their space (server) through a set of privileged operations: editing space settings, creating/updating/deleting channels, managing roles and permissions, kicking/banning members, generating invites, and managing custom emojis. The server enforces a 37-permission model with role hierarchy and per-channel permission overwrites (Discord-style resolution), while the client exposes the full REST API through AccordKit. The client now provides admin dialogs for all major management features, accessible via right-click context menus on guild icons and member items. The `Client` autoload routes API calls, caches roles, handles gateway events for roles/bans/invites/emojis, and exposes permission checking via `has_permission()`.

## User Steps

### Space Settings
1. Admin right-clicks guild icon, selects "Space Settings" (permission-gated to `manage_space`)
2. Admin edits name, description, icon, banner, verification level, default notifications, AFK channel/timeout, system channel, rules channel, preferred locale, or public flag
3. Changes are saved via `PATCH /spaces/{id}`
4. Gateway broadcasts `space_update` to all members

### Channel Management
1. Admin right-clicks guild icon, selects "Channels" (permission-gated to `manage_channels`)
2. Admin creates a channel (name, type, parent category) via `POST /spaces/{id}/channels`
3. Admin edits channel settings (name, topic, NSFW, rate limit, bitrate, user limit) via `PATCH /channels/{id}`
4. Admin reorders channels via `PATCH /spaces/{id}/channels` with position array
5. Admin deletes a channel via `DELETE /channels/{id}`
6. Gateway broadcasts `channel_create`, `channel_update`, or `channel_delete`

### Member Management
1. Admin views member list in the right sidebar panel
2. Admin right-clicks a member to open context menu (skip if target is self)
3. "Kick" shown if user has `kick_members` permission; opens ConfirmDialog, then calls `Client.kick_member()`
4. "Ban" shown if user has `ban_members` permission; opens BanDialog with optional reason, calls `Client.ban_member()`
5. Role checkboxes shown if user has `manage_roles` permission; toggles via `Client.add_member_role()`/`Client.remove_member_role()`
6. Gateway broadcasts `member_leave`, `ban_create`, `member_update`

### Role Management
1. Admin right-clicks guild icon, selects "Roles" (permission-gated to `manage_roles`)
2. Admin creates a role (name, color, permissions, hoist, mentionable)
3. Admin edits a role's properties (hierarchy check prevents editing roles at or above own highest role)
4. Admin reorders roles (position 0 reserved for @everyone)
5. Admin deletes a role (@everyone cannot be deleted)
6. Gateway broadcasts `role_create`, `role_update`, `role_delete`

### Invite Management
1. Admin creates a space-level invite via `POST /spaces/{id}/invites` with optional max_age, max_uses, temporary
2. Admin creates a channel-level invite via `POST /channels/{id}/invites`
3. Admin lists active invites for the space or a channel
4. Admin revokes an invite via `DELETE /invites/{code}`
5. Gateway broadcasts `invite_create`, `invite_delete`

### Channel Permission Overwrites
1. Admin configures per-channel permission overrides for roles or individual members
2. Overwrites specify allow/deny lists of permission strings
3. Server validates permission strings against the full 37-permission set
4. Effective permissions are resolved using a Discord-style algorithm: base role permissions + @everyone overwrite + union of assigned role overwrites + member-specific overwrite, with deny taking precedence except where allow overrides across roles

### Emoji Management
1. Admin lists custom emojis for the space via `GET /spaces/{id}/emojis` (any member)
2. Admin creates a custom emoji (name, image as base64 data URI, optional role restrictions) via `POST /spaces/{id}/emojis` (requires `manage_emojis`)
3. Admin updates an emoji's name or role restrictions via `PATCH /spaces/{id}/emojis/{emoji_id}`
4. Admin deletes an emoji via `DELETE /spaces/{id}/emojis/{emoji_id}`
5. Gateway broadcasts `emoji_update` to all members

### Public Space Discovery
1. Any authenticated user can list public spaces via `GET /spaces/public`
2. User joins a public space via `POST /spaces/{id}/join` (ban check enforced)
3. No invite code is needed for public spaces

## Signal Flow

```
Admin action (guild icon / member context menu)
  │
  ├─ Space settings ─────► Client.update_space() ──► PATCH /spaces/{id}
  │                                                        │
  │                                                   space_update (gateway)
  │                                                        │
  │                                              AccordClient.space_update signal (line 11)
  │                                                        │
  │                                              Client._on_space_update() (line 705)
  │                                                        │
  │                                              AppState.guilds_updated
  │
  ├─ Channel CRUD ───────► Client.create_channel()   ──► POST /spaces/{id}/channels
  │                        Client.update_channel()   ──► PATCH /channels/{id}
  │                        Client.delete_channel()   ──► DELETE /channels/{id}
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
  ├─ Role CRUD ──────────► Client.create_role()  ──► POST /spaces/{id}/roles
  │                        Client.update_role()  ──► PATCH /spaces/{id}/roles/{rid}
  │                        Client.delete_role()  ──► DELETE /spaces/{id}/roles/{rid}
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
| `scripts/autoload/client.gd` | Routes API calls, caches members + roles, handles all gateway events, permission helpers, admin API wrappers, `disconnect_server()` |
| `scripts/autoload/app_state.gd` | Signal bus: `members_updated`, `guilds_updated`, `channels_updated`, `roles_updated`, `bans_updated`, `invites_updated`, `emojis_updated` |
| `scripts/autoload/client_models.gd` | `member_to_dict()`, `role_to_dict()`, `invite_to_dict()`, `emoji_to_dict()` converters |
| `scripts/autoload/config.gd` | Persists server configs; `add_server()`, `remove_server()`, `clear()` |
| `scenes/members/member_list.gd` | Virtual-scrolling member list grouped by status |
| `scenes/members/member_item.gd` | Member display with right-click context menu (kick, ban, role assignment) |

### Admin Dialogs
| File | Role |
|------|------|
| `scenes/admin/confirm_dialog.tscn/.gd` | Reusable confirmation dialog with danger mode |
| `scenes/admin/ban_dialog.tscn/.gd` | Ban dialog with optional reason field |
| `scenes/admin/space_settings_dialog.tscn/.gd` | Space settings form (name, description, verification, notifications, public) |
| `scenes/admin/channel_management_dialog.tscn/.gd` | Channel list with create/edit/delete |
| `scenes/admin/role_management_dialog.tscn/.gd` | Two-panel role editor with all 37 permissions |
| `scenes/admin/ban_list_dialog.tscn/.gd` | Ban list with unban action |
| `scenes/admin/invite_management_dialog.tscn/.gd` | Invite list with create (age/uses/temporary) and revoke |
| `scenes/admin/emoji_management_dialog.tscn/.gd` | Emoji grid with upload and delete |

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
- Connects to `AppState.guild_selected` (line 27) and `AppState.members_updated` (line 28)
- `_rebuild_row_data()` (line 42) groups members by status (ONLINE, IDLE, DND, OFFLINE) and sorts alphabetically within each group
- Uses a fixed `ROW_HEIGHT` of 44px (line 5) with object pooling for performance (`_ensure_pool_size()` at line 89)
- Data source: `Client.get_members_for_guild()` (line 44) which reads from `_member_cache`

`member_item.gd` renders each member:
- Avatar with circle shader, display name, and colored status dot (lines 14-27)
- Status colors: online=green (#3BA55D), idle=yellow (#FAA81A), DND=red (#ED4245), offline=gray (#949BA4)

### Data Flow for Members

The `AccordMember` model (lines 1-69 of `member.gd`) includes a `roles` array (line 10) that is populated from the API response (lines 33-36). `ClientModels.member_to_dict()` now copies user fields + nickname override + `roles` array + `joined_at` string. The roles array is used by the member context menu for role toggle checkboxes.

The `AccordSpace` model (lines 1-137 of `space.gd`) includes `roles` (line 17) and `emojis` (line 18) arrays. `ClientModels.space_to_guild_dict()` now extracts id, name, icon_color, owner_id, description, verification_level, default_notifications, preferred_locale, and public flag. The admin settings dialog reads these fields.

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
- [x] Space settings dialog (edit name, description, verification, notifications, public; delete for owner)
- [x] Channel management dialog (create, edit, delete with inline edit dialog)
- [x] Role management dialog (two-panel editor with all 37 permissions, create/save/delete)
- [x] Member context menu (kick with confirm, ban with reason, role toggle checkboxes)
- [x] Ban list dialog (view bans, unban with confirm)
- [x] Invite management dialog (create with age/uses/temporary, list, copy code, revoke)
- [x] Emoji management dialog (grid view, upload from file, delete with confirm)
- [x] Client-side role gateway event handlers (role_create/update/delete wired + cached)
- [x] Client-side ban gateway event handlers (ban_create/delete emit bans_updated)
- [x] Client-side invite gateway event handlers (invite_create/delete emit invites_updated)
- [x] Client-side emoji gateway event handler (emoji_update emits emojis_updated)
- [x] Client-side role cache (`_role_cache` populated on gateway ready via `fetch_roles()`)
- [x] Client-side permission checking (`has_permission()`, `is_space_owner()`) gates admin UI
- [x] Server removal UI (guild icon context menu "Remove Server" with confirm dialog)
- [x] Reusable ConfirmDialog (title, message, confirm text, danger mode)
- [x] Guild icon right-click context menu as entry point for all admin dialogs
- [ ] Channel permission overwrite editor UI
- [ ] Audit log viewer
- [ ] Channel reordering UI

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No channel permission overwrite editor UI | Medium | `AccordPermissionOverwrite` model and server-side CRUD exist but no client UI for per-channel overrides. |
| No channel reordering UI | Low | `spaces_api.reorder_channels()` exists but the channel management dialog does not expose drag-to-reorder. |
| No role reordering UI | Low | `roles_api.reorder()` exists but the role management dialog does not expose drag-to-reorder. |
| `fetch_members()` uses hardcoded limit of 1000 | Low | May miss members in large spaces. The server supports cursor-based pagination but the client does not follow cursors. |
| No audit log support | Low | `AccordPermission.VIEW_AUDIT_LOG` exists and the Admin default role includes it, but no audit log API endpoints or UI exist. |
| Emoji grid uses color placeholders | Low | Emoji images are represented by colored squares. Full CDN image loading requires additional HTTP texture fetching. |
