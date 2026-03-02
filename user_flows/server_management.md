# Server Management

Last touched: 2026-03-02

## Overview

Server management covers the instance-level administration of an accordserver: creating and managing multiple spaces, managing instance users, and configuring server-wide settings. This is distinct from [space-level admin](admin_server_management.md), which covers managing a single space's channels, roles, bans, etc.

Two admin tiers exist:

- **Super admin** (instance admin): The `is_admin` flag on the user model. Has all permissions in all spaces on the server. Can create new spaces, manage any space, and perform instance-level operations (user management, server settings).
- **Space admin**: A user with the `administrator` permission or `manage_space` permission in a specific space. Can manage that space's settings, channels, roles, etc. via the existing [space settings dialog](admin_server_management.md).

Space settings already exist and function. Server management tools do not exist yet in the daccord client and likely require new accordserver API endpoints.

## User Steps

### Super Admin: Create a New Space

1. Super admin opens a "Server Management" panel (not yet built).
2. Super admin clicks "Create Space".
3. A dialog prompts for space name, description, and optional icon.
4. Client calls `POST /spaces` with the provided data.
5. Server creates the space with default roles (@everyone, Moderator, Admin), a #general channel, and sets the super admin as the space owner.
6. The new space appears in the super admin's space bar.
7. Gateway broadcasts `space_create` to connected clients.

### Super Admin: View All Spaces on the Server

1. Super admin opens the Server Management panel.
2. Panel fetches a list of all spaces on the instance (requires new `GET /admin/spaces` endpoint).
3. Each space row shows: name, icon, owner, member count, creation date, public flag.
4. Super admin can search/filter spaces by name.
5. Clicking a space row opens management options (edit settings, transfer ownership, delete).

### Super Admin: Transfer Space Ownership

1. From the space list, super admin selects a space and clicks "Transfer Ownership".
2. A member picker dialog lets the super admin search for and select a target user.
3. Client calls a new `PATCH /admin/spaces/{id}` endpoint with `{ "owner_id": "<new_owner_id>" }`.
4. Server validates the target is a member of the space, updates `owner_id`.
5. Gateway broadcasts `space_update` with the new owner.

### Super Admin: Force-Delete a Space

1. From the space list, super admin selects a space and clicks "Delete".
2. A danger confirmation dialog shows the space name and requires typing the space name to confirm.
3. Client calls `DELETE /spaces/{id}` (existing endpoint; instance admins already bypass the owner check server-side).
4. Server deletes the space, all channels, messages, roles, bans, invites, and emojis.
5. Gateway broadcasts `space_delete` to all affected clients.

### Super Admin: Manage Instance Users

1. Super admin opens the "Users" tab in the Server Management panel.
2. Panel fetches all users on the instance (requires new `GET /admin/users` endpoint with pagination).
3. Each user row shows: username, avatar, email, `is_admin` flag, account creation date, space membership count.
4. Super admin can search by username or email.
5. Super admin can:
   - **Grant/revoke admin**: Toggle `is_admin` on another user (requires new `PATCH /admin/users/{id}` endpoint).
   - **Disable account**: Prevent a user from logging in without deleting their data (requires new server-side `disabled` flag).
   - **Delete account**: Permanently remove a user and their data from the instance (requires new `DELETE /admin/users/{id}` endpoint).
   - **Reset password**: Force a password reset on the next login (requires new server-side flow).

### Super Admin: Configure Server Settings

1. Super admin opens the "Settings" tab in the Server Management panel.
2. Panel fetches server configuration (requires new `GET /admin/settings` endpoint).
3. Available settings:
   - **Server name**: Display name for the instance.
   - **Registration policy**: Open, invite-only, or closed.
   - **Max spaces**: Limit on how many spaces can exist on the instance.
   - **Max members per space**: Default cap on space membership.
   - **MOTD (Message of the Day)**: Shown to users on login.
   - **Public listing**: Whether the instance should be listed on the master server directory.
4. Super admin edits settings and saves via `PATCH /admin/settings`.
5. Changes take effect immediately; some (like registration policy) affect new connections only.

### Space Admin: Manage a Single Space

1. Space admin right-clicks a space icon or clicks the banner dropdown (existing flow).
2. Permission-gated menu items appear: Space Settings, Channels, Roles, Bans, Invites, Emojis, Audit Log.
3. All actions are scoped to the single space where the admin has permissions.
4. This flow is fully implemented — see [Admin Server Management](admin_server_management.md).

## Signal Flow

```
Super admin action (Server Management panel)
  │
  ├─ Create space ──────► AccordClient.spaces.create() ──► POST /spaces
  │                                                            │
  │                                                    space_create (gateway)
  │                                                            │
  │                                                    Client._on_space_create()
  │                                                            │
  │                                                    AppState.spaces_updated
  │
  ├─ List all spaces ───► (new) AccordClient.admin.list_spaces() ──► GET /admin/spaces
  │                       Returns Array[AccordSpace] with owner + member count
  │
  ├─ Transfer ownership ► (new) AccordClient.admin.update_space() ──► PATCH /admin/spaces/{id}
  │                                                                        │
  │                                                                space_update (gateway)
  │                                                                        │
  │                                                                Client._on_space_update()
  │
  ├─ Delete space ──────► AccordClient.spaces.delete() ──► DELETE /spaces/{id}
  │                       (existing; instance admin bypass already works server-side)
  │                                                            │
  │                                                    space_delete (gateway)
  │
  ├─ List users ────────► (new) AccordClient.admin.list_users() ──► GET /admin/users
  │                       Paginated user list with admin flag and membership info
  │
  ├─ Update user ───────► (new) AccordClient.admin.update_user() ──► PATCH /admin/users/{id}
  │                       Toggle is_admin, disable account
  │                                                                        │
  │                                                                user_update (gateway, new)
  │
  ├─ Delete user ───────► (new) AccordClient.admin.delete_user() ──► DELETE /admin/users/{id}
  │                       Cascade: remove from all spaces, delete messages, revoke tokens
  │
  └─ Server settings ──► (new) AccordClient.admin.get_settings() ──► GET /admin/settings
                          (new) AccordClient.admin.update_settings() ──► PATCH /admin/settings
```

## Key Files

### Existing (relevant to server management)

| File | Role |
|------|------|
| `addons/accordkit/models/user.gd` | `is_admin: bool` field (line 17) — the instance admin flag |
| `addons/accordkit/models/space.gd` | `owner_id` field (line 13) — space ownership |
| `addons/accordkit/rest/endpoints/spaces_api.gd` | `create()` (line 16) — `POST /spaces` already exists |
| `scripts/autoload/client_permissions.gd` | `has_permission()` (line 14) — instance admin bypass for all permissions |
| `scripts/autoload/client_permissions.gd` | `has_channel_permission()` (line 45) — instance admin bypass for channel permissions |
| `scripts/autoload/client_permissions.gd` | `get_my_highest_role_position()` (line 143) — returns 999999 for instance admins |
| `scripts/autoload/client_connection.gd` | Logs `is_admin` status at login (line 109) |
| `scenes/admin/space_settings_dialog.gd` | Existing space settings (name, description, verification, notifications, public, icon, danger zone) |

### Created (daccord client)

| File | Role |
|------|------|
| `scenes/admin/server_management_panel.tscn` | Main server management panel scene (tabs: Spaces, Users, Settings) |
| `scenes/admin/create_space_dialog.gd` | Space creation dialog (name, description, icon) — built in code, no .tscn |
| `scenes/admin/transfer_ownership_dialog.gd` | Member picker for space ownership transfer — built in code, no .tscn |
| `addons/accordkit/rest/endpoints/admin_api.gd` | Admin-only REST endpoints (spaces, users, settings) |

### Implemented (accordserver)

| File | Role |
|------|------|
| `accordserver/src/routes/admin.rs` | Admin-only route handlers (list/update spaces, list/update/delete users) |
| `accordserver/src/routes/settings.rs` | Server settings handlers (admin GET/PATCH + public GET) |
| `accordserver/src/middleware/permissions.rs` | `require_server_admin()` guard (replaces planned `middleware/admin.rs`) |
| `accordserver/src/db/admin.rs` | Admin DB queries (all spaces, all users, user cascade delete) |
| `accordserver/src/db/settings.rs` | Server settings DB queries (get, update) |
| `accordserver/migrations/011_server_settings.sql` | `server_settings` table schema |
| `accordserver/migrations/012_admin_management.sql` | `disabled`, `force_password_reset` columns + extended server settings |

## Implementation Details

### Instance Admin Flag

The `is_admin` field on `AccordUser` (line 17 of `user.gd`) is a boolean set server-side, typically on the first user created or via a CLI command. The client reads it from the `GET /users/@me` response at login. `client_connection.gd` logs the admin status (line 109). `client_permissions.gd` grants all permissions in all spaces when `is_admin` is true (lines 14, 45, 143).

Currently, there is no way for the client to check `is_admin` for *other* users — only the current user's flag is available via `@me`. The admin user list endpoint would need to expose this.

### Space Creation

The AccordKit REST layer already supports space creation via `spaces_api.gd:create()` → `POST /spaces`. The server-side handler (`spaces.rs`) auto-creates:
- Default roles: @everyone (position 0), Moderator (position 1), Admin (position 2)
- A `#general` text channel
- The creating user as both a member and Admin role holder

The Create Space flow was intentionally removed from the "Add Server" dialog (per `multi_server_plan.md`) because space creation is a server-admin operation, not something regular users should do. The Server Management panel would restore this capability exclusively for instance admins.

### Ownership Transfer

Space ownership is tracked by the `owner_id` field on `AccordSpace` (line 13 of `space.gd`). Currently, only the space owner sees the "Delete Server" danger zone button (`space_settings_dialog.gd` line 114: `_danger_zone.visible = Client.is_space_owner(space_id)`). Ownership transfer would update this field, which affects:
- Who can delete the space
- Who bypasses the role hierarchy (space owners return `i64::MAX` in `require_hierarchy()`)
- UI visibility of danger zone actions

**Missing on accordserver:** No endpoint exists to transfer ownership. Would need a new `PATCH /admin/spaces/{id}` or extend `PATCH /spaces/{id}` with an `owner_id` field that only instance admins can set.

### Instance User Management

No instance-level user management exists on either the client or server. The only user-related admin operations are space-scoped: kick, ban, role assignment. Instance-level operations need:

- **List all users:** Server would need `GET /admin/users` with pagination, search, and filter. Currently, user data is only accessible per-space via the members endpoint.
- **Toggle admin:** Requires `PATCH /admin/users/{id}` with `{ "is_admin": true/false }`. Should prevent removing admin from the last remaining admin.
- **Disable account:** A new `disabled` boolean column on the users table. Disabled users would be rejected at token validation, effectively blocking all API access without deleting data.
- **Delete account:** `DELETE /admin/users/{id}` would cascade: remove from all spaces, delete or anonymize messages, revoke all tokens. This has significant data implications and should require confirmation.
- **Password reset:** Requires a server-side "force reset" flag that invalidates the current password and requires a new one on next login.

### Server Settings

No server settings table or API exists. The accordserver currently uses environment variables or a config file for server-wide settings. A `server_settings` table would allow runtime configuration:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `server_name` | string | `"Accord Server"` | Display name for the instance |
| `registration_policy` | enum | `"open"` | `open`, `invite_only`, `closed` |
| `max_spaces` | integer | `0` (unlimited) | Maximum number of spaces on the instance |
| `max_members_per_space` | integer | `0` (unlimited) | Default member cap per space |
| `motd` | string | `""` | Message shown to users on login |
| `public_listing` | boolean | `false` | Whether to register with the master server directory |

### Entry Points

The Server Management panel should be accessible:
1. **Space bar**: A gear/wrench icon visible only to instance admins, placed below the DM button.
2. **User settings**: An "Instance Admin" link in the settings panel, visible only when `current_user.is_admin` is true.

The `is_admin` check should gate both the UI entry point and the panel itself. This matches the existing pattern: admin dialogs check permissions before showing menu items.

### Relationship to Existing Admin Tools

Server management is a superset of space management:

| Capability | Space Admin | Super Admin |
|-----------|-------------|-------------|
| Edit space settings | Own space only | Any space |
| Manage channels/roles/bans | Own space only | Any space |
| Create new spaces | No | Yes |
| Delete any space | No (owner only) | Yes |
| Transfer space ownership | No | Yes |
| Manage instance users | No | Yes |
| Configure server settings | No | Yes |
| View all spaces | No | Yes |

The client-side `has_permission()` check already grants all permissions to instance admins (line 14 of `client_permissions.gd`). This means all existing space admin dialogs already work for super admins — no changes needed there. Server management adds the *additional* capabilities that don't exist at the space level.

## Implementation Status

### Existing (functional)
- [x] `is_admin` flag on AccordUser model (`user.gd` line 17)
- [x] Instance admin permission bypass in `client_permissions.gd` (lines 14, 45, 143)
- [x] Space creation API in AccordKit (`spaces_api.gd:create()` → `POST /spaces`)
- [x] Space deletion with instance admin bypass server-side (`spaces.rs` line 48)
- [x] Space settings dialog (name, description, verification, notifications, public, icon, danger zone)
- [x] Full space admin tooling (channels, roles, bans, invites, emojis, audit log)
- [x] Gateway signals for space create/update/delete
- [x] Default role + #general channel auto-creation on space create

### Implemented (daccord client)
- [x] Server Management panel (entry point for instance admins)
- [x] Create Space dialog (uses existing `POST /spaces` API)
- [x] All-spaces list view (search, filter, member counts)
- [x] Space ownership transfer dialog
- [x] Instance user list (paginated, searchable)
- [x] Admin grant/revoke toggle for users
- [x] Account deletion (instance-level)
- [x] Server settings editor
- [x] Entry point in space bar (admin-only icon)
- [x] Entry point in user settings (admin-only link)
- [x] `admin_api.gd` AccordKit endpoints for admin routes

### Missing (daccord client)
- [x] Account disable/enable controls (server-side `disabled` flag is implemented)

### Implemented (accordserver)
- [x] `GET /admin/spaces` — list all spaces with owner and member count (`src/routes/admin.rs`)
- [x] `PATCH /admin/spaces/{id}` — update space including `owner_id` transfer (`src/routes/admin.rs`)
- [x] `GET /admin/users` — paginated user list with admin flag, disabled, space count (`src/routes/admin.rs`)
- [x] `PATCH /admin/users/{id}` — toggle `is_admin`, `disabled`, `force_password_reset` with self-demotion and last-admin protection (`src/routes/admin.rs`)
- [x] `DELETE /admin/users/{id}` — delete user with full cascade; prevents deleting self or admins; requires ownership transfer first (`src/db/admin.rs`)
- [x] `GET /admin/settings` — fetch server settings, admin-only (`src/routes/settings.rs`)
- [x] `PATCH /admin/settings` — update server settings with hot-reload (`src/routes/settings.rs`)
- [x] `GET /settings` — public settings endpoint for client upload limits, server name, registration policy, MOTD (`src/routes/settings.rs`)
- [x] `require_server_admin()` middleware guard (`src/middleware/permissions.rs`)
- [x] `server_settings` database table (`migrations/011_server_settings.sql`, `migrations/012_admin_management.sql`)
- [x] `disabled` column on users table (`migrations/012_admin_management.sql`)
- [x] `force_password_reset` column on users table (`migrations/012_admin_management.sql`)
- [x] Registration policy enforcement — open/invite_only/closed checked at `POST /auth/register` (`src/routes/auth.rs`)
- [x] MOTD delivery in gateway READY payload (`src/gateway/mod.rs`)
- [x] Disabled user rejection at token validation, login, and gateway connect (`src/middleware/auth.rs`, `src/routes/auth.rs`, `src/gateway/mod.rs`)

## Tasks

### SRVMGMT-1: Create Server Management panel scaffold
- **Status:** done
- **Impact:** 5
- **Effort:** 3
- **Tags:** ui, admin
- **Notes:** Tabbed panel (Spaces, Users, Settings) accessible only to instance admins. Needs entry point in space bar (gear icon) and user settings. Can start with just the Spaces tab since space creation API already exists.

### SRVMGMT-2: Build Create Space dialog
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** ui, admin
- **Notes:** Simple form: name, description, optional icon upload. Calls existing `AccordClient.spaces.create()`. Can be built before any server changes. The first usable piece of server management.

### SRVMGMT-3: Add admin API routes to accordserver
- **Status:** done
- **Impact:** 5
- **Effort:** 4
- **Tags:** api, server
- **Notes:** `/admin/*` route group with `require_server_admin()` guard. Covers: list all spaces, list all users, update user admin flag, server settings CRUD. Routes registered in `src/routes/mod.rs`, handlers in `src/routes/admin.rs` and `src/routes/settings.rs`, DB layer in `src/db/admin.rs`.

### SRVMGMT-4: Build instance user management UI
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** ui, admin, api
- **Notes:** Paginated user list with search, admin toggle, disable, delete. Server-side endpoints are ready (`/admin/users`).

### SRVMGMT-5: Implement space ownership transfer
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** api, admin
- **Notes:** Server-side `PATCH /admin/spaces/{id}` with `owner_id` field implemented. Ensures new owner is a member of the space. Client transfer dialog implemented.

### SRVMGMT-6: Add server settings table and API
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** api, server
- **Notes:** `server_settings` table with columns for server_name, registration_policy, max_spaces, max_members_per_space, motd, public_listing, plus upload size limits. `GET/PATCH /admin/settings` (admin-only) and `GET /settings` (public). Registration policy enforced at `POST /auth/register`. MOTD included in gateway READY payload. Settings hot-reloaded via `ArcSwap` in `AppState`.

### SRVMGMT-7: Add `disabled` flag to user accounts
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** api, server
- **Notes:** `disabled` and `force_password_reset` columns added to users table. Disabled users rejected at: bearer/bot token resolution (`src/middleware/auth.rs`), login (`src/routes/auth.rs`), and gateway connect (`src/gateway/mod.rs`). Toggled via `PATCH /admin/users/{id}`.

### SRVMGMT-8: AccordKit admin endpoint wrappers
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** api
- **Notes:** `admin_api.gd` in AccordKit with methods for all `/admin/*` endpoints.
