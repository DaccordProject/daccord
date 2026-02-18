# Server Connection

*Last touched: 2026-02-18 00:22*

## Overview

Users connect to accordserver instances by adding a server via the Add Server dialog. The URL is parsed into components (host, port, guild name, token). If a token is not provided in the URL, an auth dialog appears for sign-in or registration. Supports multiple concurrent server connections.

## User Steps

1. User clicks "+" button in guild bar
2. Add Server dialog opens with URL input field
3. User enters URL in format: `[protocol://]host[:port][#guild-name][?token=value]`
4. If URL contains `?token=`, proceed directly to connection
5. If no token, auth dialog appears with Sign In / Register toggle
6. User enters username/password (and optional display name for registration)
7. Auth sends credentials to server, receives token
8. HTTPS attempted first; on failure, automatically falls back to HTTP
9. Config saved via `Config.add_server()`, `Client.connect_server()` called
10. Server authenticates with Bearer token, fetches user via `GET /users/@me`
11. Lists user's spaces via `GET /users/@me/spaces`, matches configured guild name
12. WebSocket gateway connects with configured intents
13. Server enters `LIVE` mode

## Signal Flow

```
User clicks "+"
    -> add_server_dialog opens
    -> URL parsed (parse_url)
    -> [If no token] auth_dialog opens
        -> auth_completed signal(base_url, token)
    -> Config.add_server(base_url, token, guild_name)
    -> Client.connect_server(index)
        -> AccordClient authenticates (Bearer token)
        -> GET /users/@me -> current_user set
        -> GET /users/@me/spaces -> match guild_name -> guild_id
        -> _derive_gateway_url() -> WebSocket connects
        -> _on_gateway_ready() -> fetch_channels(), fetch_dm_channels()
        -> AppState.guilds_updated emitted
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | URL input and parsing |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign-in / register UI with HTTPS->HTTP fallback |
| `scripts/autoload/config.gd` | Persists server configs to `user://config.cfg` |
| `scripts/autoload/client.gd` | `connect_server()` (lines 76-222), manages connections array |
| `addons/accordkit/core/accord_client.gd` | AccordClient REST + gateway |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `login()` and `register()` endpoints |
| `addons/accordkit/rest/endpoints/users_api.gd` | `get_me()`, `list_spaces()` |

## Implementation Details

- URL parsing in add_server_dialog.gd: Defaults to HTTPS, port 39099, guild "general"
- Auth dialog (auth_dialog.gd): Mode enum {SIGN_IN, REGISTER}. Sign In hides display_name field, Register shows it. HTTPS->HTTP fallback on auth failure (lines 72-75). On success, emits `auth_completed(base_url, token)` signal and calls `queue_free()`.
- Auth uses `AuthApi.login({username, password})` and `AuthApi.register({username, password, display_name})` via AccordKit REST
- Config (config.gd): Stores servers as indexed sections `[server_0]`, `[server_1]`, etc. in `user://config.cfg`. Each section has `base_url`, `token`, `guild_name`. Count tracked in `[servers]` section.
- Client.connect_server() (client.gd:76-222): Creates an AccordClient, sets Bearer token, authenticates via GET /users/@me, lists spaces, matches guild name, derives gateway URL (https->wss, http->ws + /ws), connects WebSocket with intents (default + MESSAGE_TYPING, DIRECT_MESSAGES, DM_TYPING). HTTPS->HTTP fallback (lines 119-140) retries and updates saved config URL.
- Multi-server: Each connection stored in `_connections` array as dict with keys: `client`, `guild_id`, `cdn_url`, `status`, `config`
- On startup: `Client._ready()` checks `Config.has_servers()`, calls `connect_server()` for each

## Implementation Status

- [x] Add Server dialog with URL parsing
- [x] Auth dialog (sign-in and register)
- [x] HTTPS -> HTTP fallback (both in auth_dialog and client.connect_server)
- [x] Token-based authentication (Bearer)
- [x] Config persistence (user://config.cfg)
- [x] Multi-server connections
- [x] Gateway connection with intents
- [x] Auto-connect on startup
- [x] Invite code support (connect_server has invite_code parameter)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server removal UI | Medium | `Config.remove_server()` exists but no UI button/dialog exposes it |
| No server edit/reconnect UI | Medium | `Config.update_server_url()` exists but no UI to trigger it |
| No connection progress indicator | Low | User sees no feedback during the authentication + gateway handshake |
| No error display on connection failure | Medium | `connect_server()` calls `push_error()` but user sees no notification |
| Initial tab hardcoded to "general" / "chan_3" | Low | `main_window.gd:33` adds default tab before server data is loaded |
| Token stored in plaintext | Low | Config file stores token as plain string in `user://config.cfg` |
