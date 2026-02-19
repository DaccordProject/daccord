# Server Connection


## Overview

Users connect to accordserver instances by adding a server via the Add Server dialog. The URL is parsed into components (host, port, guild name, token). If a token is not provided in the URL, an auth dialog appears for sign-in or registration. Supports multiple concurrent server connections.

## User Steps

1. User clicks "+" button in guild bar
2. Add Server dialog opens with URL input field
3. User enters URL in format: `[protocol://]host[:port][#guild-name][?token=value&invite=code]`
4. Duplicate check: if this server+guild is already connected, show error; if a stale (failed) entry exists, remove it and continue
5. Server probe: a lightweight request verifies the server is reachable (HTTPS first, falls back to HTTP); shows error if unreachable
6. If URL contains `?token=`, proceed directly to connection
7. If no token, auth dialog appears with Sign In / Register toggle
8. User enters username/password (and optional display name for registration; register mode has password generation and view/hide toggle; display name auto-fills from username)
9. Auth sends credentials to server, receives token (HTTPS first, falls back to HTTP)
10. Config saved via `Config.add_server()` (stores base_url, token, guild_name, username, password), `Client.connect_server()` called
11. Server authenticates with Bearer token, fetches user via `GET /users/@me` (HTTPS->HTTP fallback)
12. If token is expired/invalid, auto re-auth with stored username/password via `AuthApi.login()`
13. Fetches full space details via `GET /spaces/{id}`, caches guild
14. If invite code was provided, accepts invite (non-fatal on failure)
15. Lists user's spaces via `GET /users/@me/spaces`, matches configured guild name (by slug)
16. Gateway signals connected, `client.login()` starts WebSocket with `GatewayIntents.all()`
17. Connection enters `LIVE` mode, `AppState.guilds_updated` emitted
18. On connection failure, config entry is removed and error shown in the dialog

## Signal Flow

```
User clicks "+"
    -> add_server_dialog opens
    -> URL parsed (parse_server_url)
    -> Duplicate server+guild check (remove stale entry if failed)
    -> _probe_server(url) -- GET /auth/login to verify reachability
        -> [HTTPS fails] retry with HTTP
    -> [If no token] auth_dialog opens
        -> auth_completed signal(base_url, token, username, password)
    -> _connect_with_token()
        -> Config.add_server(base_url, token, guild_name, username, password)
        -> Client.connect_server(index, invite_code)
            -> _make_client() -> AccordClient with GatewayIntents.all()
            -> GET /users/@me (Bearer token)
                -> [HTTPS fails] retry with HTTP, update config URL
                -> [Token invalid] _try_reauth(username, password) -> new token
            -> [invite_code] client.invites.accept(invite_code)
            -> GET /users/@me/spaces -> match guild_name by slug -> guild_id
            -> GET /spaces/{guild_id} -> cache full guild dict
            -> _connect_gateway_signals(client, idx)
            -> client.login() -> WebSocket connects
            -> mode = LIVE
            -> AppState.guilds_updated emitted
        -> [On failure] Config.remove_server(), show error in dialog
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | URL input, parsing, server probe, duplicate check, connection orchestration |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign-in / register UI with HTTPS->HTTP fallback, password generation |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Right-click context menu with Reconnect and Remove Server options |
| `scripts/autoload/config.gd` | Persists encrypted server configs to `user://config.cfg` |
| `scripts/autoload/client.gd` | `connect_server()` (lines 112-281), `disconnect_server()`, `reconnect_server()`, `_try_reauth()` |
| `scripts/autoload/client_gateway.gd` | Gateway event handling, auto-reconnect on disconnect |
| `addons/accordkit/core/accord_client.gd` | AccordClient REST + gateway |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `login()` and `register()` endpoints |
| `addons/accordkit/rest/endpoints/users_api.gd` | `get_me()`, `list_spaces()` |

## Implementation Details

- URL parsing in `add_server_dialog.gd`: `parse_server_url()` defaults to HTTPS, port 39099, guild "general". Also extracts `invite` query param.
- Duplicate detection in `add_server_dialog.gd`: Checks existing config entries by URL (including HTTP/HTTPS variants) and guild name. If a match is already connected, shows error. If a stale failed entry exists, removes it before proceeding.
- Server probe in `add_server_dialog.gd`: `_probe_server()` sends a GET to `/auth/login` to verify reachability. Tries HTTPS first, falls back to HTTP. Any HTTP response (even 405) means reachable. Shows the error message from AccordRest on failure.
- Auth dialog (`auth_dialog.gd`): Mode enum {SIGN_IN, REGISTER}. Sign In hides display_name/generate/view fields. Register shows them, with password generation (12 random chars) and view/hide toggle. Display name auto-fills from username as the user types. HTTPS->HTTP fallback on auth failure. On success, emits `auth_completed(base_url, token, username, password)` and calls `queue_free()`.
- Auth uses `AuthApi.login({username, password})` and `AuthApi.register({username, password, display_name})` via AccordKit REST.
- Config (`config.gd`): Stores servers as indexed sections `[server_0]`, `[server_1]`, etc. Each section has `base_url`, `token`, `guild_name`, `username`, `password`. Count tracked in `[servers]` section. File is encrypted via `save_encrypted_pass()` / `load_encrypted_pass()` with a key derived from a salt + user data dir. Falls back to plaintext on first run and migrates to encrypted.
- `Client.connect_server()` (`client.gd:112-281`): Creates an AccordClient via `_make_client()` with `GatewayIntents.all()`, authenticates via GET /users/@me, HTTPS->HTTP fallback, token re-auth via `_try_reauth()` with stored credentials, accepts invite if provided, lists spaces, matches guild name by slug, fetches full space details, derives gateway URL (https->wss, http->ws + /ws), connects gateway signals, calls `client.login()`.
- Multi-server: Each connection stored in `_connections` array as dict with keys: `client`, `guild_id`, `cdn_url`, `status`, `config`.
- On startup: `Client._ready()` checks `Config.has_servers()`, calls `connect_server()` for each.
- Server removal: Guild icon right-click context menu has "Remove Server" which shows a confirm dialog, then calls `Client.disconnect_server()`. This logs out, cleans up all caches (guild, channels, messages, roles, members, voice state, unread tracking), removes config entry, and re-indexes connections.
- Reconnect: Guild icon context menu shows "Reconnect" when status is `disconnected` or `error`. Calls `Client.reconnect_server()`.
- Auto-reconnect on gateway failure: `ClientGateway` triggers `_handle_gateway_reconnect_failed()` which attempts a full reconnect with re-auth once per disconnect cycle.
- On shutdown: `Client._notification(NOTIFICATION_WM_CLOSE_REQUEST)` calls `logout()` on all connected clients.

## Implementation Status

- [x] Add Server dialog with URL parsing (including invite code)
- [x] Auth dialog (sign-in and register with password generation)
- [x] HTTPS -> HTTP fallback (in probe, auth_dialog, and client.connect_server)
- [x] Token-based authentication (Bearer)
- [x] Auto re-auth with stored credentials on token expiry
- [x] Config persistence (user://config.cfg, encrypted)
- [x] Multi-server connections
- [x] Gateway connection with all intents
- [x] Auto-connect on startup
- [x] Invite code support (parsed from URL, accepted during connect)
- [x] Server removal UI (guild icon right-click -> Remove Server with confirm dialog)
- [x] Reconnect UI (guild icon right-click -> Reconnect when disconnected/error)
- [x] Error display on connection failure (shown in add server dialog)
- [x] Duplicate server detection (with stale entry cleanup)
- [x] Server probe before auth (verifies reachability)
- [x] Auto-reconnect on gateway failure (with re-auth, once per cycle)
- [x] Graceful shutdown (logout all clients on window close)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No connection progress indicator | Low | User sees "Connecting..." on the Add button but no progress bar or status during the multi-step handshake |
