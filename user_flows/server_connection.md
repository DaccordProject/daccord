# Server Connection

Priority: 1
Depends on: None
Status: Complete

Users connect to accordserver instances via the Add Server dialog with URL parsing, auth (sign-in/register), token management, and multi-server support.

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | URL input, parsing, server probe, duplicate check, connection orchestration |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign-in / register UI, password generation |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Right-click context menu with Reconnect and Remove Server options |
| `scripts/autoload/config.gd` | Persists encrypted server configs to `user://config.cfg` |
| `scripts/autoload/client.gd` | `connect_server()` (lines 112-281), `disconnect_server()`, `reconnect_server()`, `_try_reauth()` |
| `scripts/autoload/client_gateway.gd` | Gateway event handling, auto-reconnect on disconnect |
| `addons/accordkit/core/accord_client.gd` | AccordClient REST + gateway |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `login()` and `register()` endpoints |
| `addons/accordkit/rest/endpoints/users_api.gd` | `get_me()`, `list_spaces()` |
