# Server Management

Priority: 65
Depends on: Admin Server Management
Status: Complete

Server management covers the instance-level administration of an accordserver: creating and managing multiple spaces, managing instance users, and configuring server-wide settings. This is distinct from space-level admin, which covers managing a single space's channels, roles, bans, etc.

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
