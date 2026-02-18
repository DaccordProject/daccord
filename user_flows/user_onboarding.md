# User Onboarding

*Last touched: 2026-02-18 21:45*

## Overview

User onboarding covers the complete first-run experience: launching daccord with no configured servers, adding the first server (including authentication), and reaching a usable state with guilds, channels, and messages displayed. It also covers subsequent launches where the previous session is restored automatically.

## User Steps

### First launch (no servers)

1. User opens daccord for the first time
2. Config file is created (or is empty) -- `Config.has_servers()` returns `false`
3. Client stays in `CONNECTING` mode; sidebar guild bar shows only the DM button and "+" Add Server button
4. Channel panel, message view, and content area are blank (no empty-state guidance)
5. User clicks "+" button in the guild bar
6. Add Server dialog opens with a URL input field
7. User enters a server URL (e.g. `example.com`, `example.com#my-space?token=abc123`)
8. Dialog probes the server for reachability (HTTPS first, HTTP fallback)
9. **If URL has `?token=`**: connects directly with that token
10. **If no token**: auth dialog opens with Sign In / Register toggle
    - **Sign In**: user enters username + password
    - **Register**: user enters username + password + display name (auto-filled from username); can generate a random password
11. Auth dialog authenticates against the server, receives a token
12. Config saves the server entry; `Client.connect_server()` is called
13. Client authenticates (`GET /users/@me`), lists spaces (`GET /users/@me/spaces`), matches the guild name, opens WebSocket gateway
14. `AppState.guilds_updated` fires -- sidebar auto-selects the new guild
15. Channel list loads, first text channel auto-selects, messages load -- user sees the chat

### Subsequent launch (servers configured)

1. User opens daccord
2. `Config.has_servers()` returns `true`
3. `Client._ready()` calls `connect_server()` for each saved server
4. On first successful connection, `AppState.guilds_updated` fires
5. `sidebar._on_guilds_updated()` reads `Config.get_last_selection()` to restore the previous guild and channel
6. If saved guild still exists, it's selected; otherwise falls back to `Client.guilds[0]`
7. Channel list loads with the saved channel pre-selected (via `pending_channel_id`)
8. Messages load, user is back where they left off

## Signal Flow

```
=== FIRST LAUNCH ===

Config._ready()
    load user://config.cfg  (empty / doesn't exist)

Client._ready()
    Config.has_servers() == false
    -> stays Mode.CONNECTING  (no connect_server calls)

UI is idle: empty guild bar ("+" only), blank channel panel, blank message view

User clicks "+"
    -> add_server_button.add_server_pressed
    -> guild_bar._on_add_server_pressed()            (line 87)
        -> AddServerDialog instantiated, added to root

User enters URL, clicks "Add"
    -> add_server_dialog._on_add_pressed()            (line 69)
    -> parse_server_url(raw)                          (line 24)
    -> _probe_server(url)                             (line 134)
    -> [No token?] AuthDialog instantiated
        -> user signs in or registers
        -> auth_completed.emit(url, token, user, pass) (line 105 of auth_dialog)
    -> _connect_with_token()                          (line 161)
        -> Config.add_server(url, token, guild_name)  (line 169)
        -> Client.connect_server(last_index)          (line 171)
            -> GET /users/@me                         (line 143 of client)
            -> GET /users/@me/spaces                  (line 223 of client)
            -> match guild_name -> guild_id           (lines 239-254)
            -> client.login() (WebSocket)             (line 275)
            -> mode = Mode.LIVE                       (line 279)
            -> AppState.guilds_updated.emit()         (line 280)

        -> sidebar._on_guilds_updated()               (line 22 of sidebar)
            -> _startup_selection_done = true          (line 27)
            -> Config.get_last_selection() (empty)     (line 29)
            -> fallback to Client.guilds[0]            (line 42)
            -> guild_bar._on_guild_pressed(guild_id)   (line 46)
                -> guild_bar.guild_selected.emit()     (line 79 of guild_bar)
        -> sidebar._on_guild_selected()                (line 48)
            -> channel_list.load_guild(guild_id)       (line 51)
                -> auto-selects first text channel
                -> channel_list.channel_selected.emit()
        -> sidebar._on_channel_selected()              (line 68)
            -> AppState.select_channel(channel_id)
            -> Config.set_last_selection()             (line 70)
        -> message_view._on_channel_selected()         (line 113 of message_view)
            -> Client.fetch.fetch_messages(channel_id) (line 124)
            -> messages render

        -> server_added.emit(guild_id)                 (line 179)
        -> guild_bar._on_server_added(guild_id)        (line 92 of guild_bar)


=== SUBSEQUENT LAUNCH ===

Config._ready()
    load user://config.cfg  (has server entries)

Client._ready()
    Config.has_servers() == true                       (line 90)
    for i in servers:
        connect_server(i)                              (line 92)
            -> authenticates, matches guild, connects gateway
            -> AppState.guilds_updated.emit()          (line 280)

sidebar._on_guilds_updated()                           (line 22)
    Config.get_last_selection()                         (line 29)
    -> {guild_id, channel_id} restored from config
    -> channel_list.pending_channel_id = saved_channel  (line 45)
    -> guild_bar._on_guild_pressed(saved_guild_id)      (line 46)
        -> channel_list.load_guild() uses pending_channel_id
        -> AppState.select_channel(saved_channel)
    -> message_view loads saved channel's messages
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/config.gd` | Persists server configs; `has_servers()` (line 85), `get_last_selection()` (line 96), `add_server()` (line 35) |
| `scripts/autoload/client.gd` | Startup check (line 90), `connect_server()` (line 112), mode transitions |
| `scripts/autoload/app_state.gd` | `guilds_updated` signal triggers sidebar startup selection |
| `scenes/sidebar/guild_bar/add_server_button.gd` | "+" button, emits `add_server_pressed` (line 3) |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | URL parsing (line 24), server probing (line 134), connection (line 161) |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign In / Register flow, emits `auth_completed` (line 3) |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Instantiates dialog (line 87), auto-selects new guild (line 92) |
| `scenes/sidebar/sidebar.gd` | Startup selection logic with `_startup_selection_done` guard (line 6), session restore (line 29) |
| `scenes/sidebar/channels/channel_list.gd` | Empty state for no channels (lines 45-61), `pending_channel_id` (line 12) |
| `scenes/messages/message_view.gd` | Empty state for no messages (line 141), loading state (line 116) |
| `scenes/main/main_window.gd` | Root scene, no special empty-state handling for first run |

## Implementation Details

### Config: first-run detection

There is no explicit "first run" flag. `Config._ready()` (line 8) attempts to load an encrypted config file from `user://config.cfg`. If the file doesn't exist or can't be decrypted, it falls back to plaintext load (line 13), then re-saves encrypted (line 16). On a true first launch, neither load succeeds, and `has_servers()` returns `false` because the default count is 0 (line 85).

Config stores servers as indexed sections (`[server_0]`, `[server_1]`, ...) with a count in `[servers]`. Each entry holds `base_url`, `token`, `guild_name`, `username`, and `password`. The config is encrypted with a key derived from `"daccord-config-v1"` + the user data directory path (line 18-19).

### Client: startup auto-connect

`Client._ready()` (line 68) initializes sub-systems (`ClientGateway`, `ClientFetch`, `ClientAdmin`, `ClientVoice`, `ClientMutations`), then checks `Config.has_servers()` at line 90. If true, it loops through all server configs and calls `connect_server(i)` for each (lines 91-92). If false, the client stays in `Mode.CONNECTING` (line 15) and the UI remains empty.

### Add Server dialog: URL input and probing

The dialog (line 69, `_on_add_pressed()`) validates the URL is non-empty, checks for duplicates against existing configs (lines 84-104), and probes the server via a lightweight `GET /auth/login` request (line 134, `_probe_server()`). HTTPS is tried first; on connection-level failure (status_code 0), it falls back to HTTP (line 143-148). The button shows "Checking..." during the probe (line 108).

URL parsing (`parse_server_url`, line 24) supports `[protocol://]host[:port][#guild-name][?token=value&invite=code]` with defaults: HTTPS, port 39099, guild "general".

### Auth dialog: sign-in and registration

If no `?token=` is in the URL, the auth dialog is shown (line 118-126). It defaults to Sign In mode (line 36). Register mode shows additional fields: display name (auto-filled from username, line 124-128), generate password button (line 109, 12 random characters), and view/hide password toggle (line 119).

On submit (line 70), it validates username and password, then calls `_try_auth()` (line 131) which uses `AuthApi.login()` or `AuthApi.register()`. On HTTPS failure, it retries with HTTP (lines 88-90). On success, emits `auth_completed(base_url, token, username, password)` (line 105) and self-destructs (`queue_free()`).

### Connection and guild matching

`_connect_with_token()` (line 161) saves the config via `Config.add_server()` (line 169), then calls `Client.connect_server()` (line 171). The button shows "Connecting..." during this phase (line 167).

`Client.connect_server()` (line 112) runs the full async connection:
1. Creates an `AccordClient` with Bearer token (lines 137-139)
2. `GET /users/@me` -- fetches the current user (line 143). Falls back HTTPS->HTTP (lines 144-158). Falls back to re-auth with stored credentials if token is expired (lines 160-175)
3. `GET /users/@me/spaces` -- lists the user's spaces (line 223), matches `guild_name` to find `guild_id` (lines 239-254)
4. Fetches full space details (line 256)
5. Opens the WebSocket gateway via `client.login()` (line 275)
6. Sets `mode = Mode.LIVE` (line 279), emits `AppState.guilds_updated` (line 280)

On error, it rolls back the config entry via `Config.remove_server()` (line 176 of add_server_dialog) and shows an error message.

### Sidebar: startup selection and session restore

`sidebar._on_guilds_updated()` (line 22) is the critical startup hook. It guards with `_startup_selection_done` (line 23) so it only fires once. If `Client.guilds` is empty, it returns early (line 25-26).

On first invocation with guilds available, it reads `Config.get_last_selection()` (line 29) which returns `{guild_id, channel_id}`. If the saved guild exists in `Client.guilds`, it's used (lines 34-38); otherwise it falls back to `Client.guilds[0]` (line 42). The saved channel ID is passed to `channel_list.pending_channel_id` (line 45), and the guild is selected via `guild_bar._on_guild_pressed()` (line 46).

### Guild bar: auto-select after adding server

After `Client.connect_server()` succeeds, the Add Server dialog emits `server_added(guild_id)` (line 179 of add_server_dialog). `guild_bar._on_server_added()` (line 92) receives this and calls `_on_guild_pressed(guild_id)` (line 94) to auto-select the newly added server, so the user immediately sees its channels.

### Empty states

**Channel list empty state** (channel_list.gd, lines 45-61): When a guild has zero non-category channels, an `EmptyState` VBox appears. If the user has `MANAGE_CHANNELS` permission, it shows "No channels yet" / "Create your first channel to get started." with a "Create Channel" button. Otherwise: "No channels yet" / "This space doesn't have any channels yet. Check back soon!"

**Message view empty state** (message_view.gd, lines 141-159): Three states:
- **Loading** (`_is_loading = true`): Shows "Loading messages..." label with a 15-second timeout timer (line 84)
- **No messages**: Shows "Welcome to #channel_name" / "This is the beginning of this channel. Send a message to get the conversation started!" (or "No messages yet" / "Send a message to start the conversation." in DM mode)
- **Has messages**: Both hidden

**Main window**: No empty-state handling for the no-servers case. The content area (message view, tab bar, member list) simply starts blank.

## Implementation Status

- [x] Config persistence with encrypted storage
- [x] First-run detection via `has_servers()` (implicit -- no config file means no servers)
- [x] Add Server dialog with URL parsing and server probing
- [x] Auth dialog with Sign In / Register toggle
- [x] HTTPS -> HTTP fallback (both auth dialog and client)
- [x] Token re-authentication with stored credentials on reconnect
- [x] Invite code support in URL (`?invite=code`)
- [x] Duplicate server detection with stale-entry cleanup
- [x] Auto-connect on startup for saved servers
- [x] Session restore (last selected guild + channel)
- [x] Auto-select newly added guild
- [x] Channel list empty state (with permission-aware create button)
- [x] Message view empty/loading states
- [x] Connection error rollback (removes config entry on failure)
- [ ] Welcome screen / first-run tutorial
- [ ] Connection progress indicator during startup auto-connect
- [ ] Main window empty state when no servers are configured

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No welcome screen on first launch | Medium | When no servers are configured, the user sees a completely blank UI with only the "+" button. No guidance text, illustration, or tooltip points the user toward the Add Server button. |
| No connection progress during startup | Medium | `Client._ready()` calls `connect_server()` for each saved server but provides no visual feedback. The user sees a blank screen until `guilds_updated` fires. Message view shows "Loading messages..." only after a channel is selected. |
| No main window empty state | Medium | `main_window.gd` has no special handling for `Mode.CONNECTING` with zero servers. The content area (message view, tab bar) is simply blank rather than showing a helpful prompt. |
| No onboarding tooltip or callout | Low | First-time users have no visual cue that the "+" button is how to get started. The button has a tooltip ("Add a Server") but no attention-drawing animation or highlight. |
| No server removal UI | Medium | `Config.remove_server()` exists (line 49) but no UI button or dialog exposes it to the user. Once a server is added, the only way to remove it is to edit the config file. |
| `_startup_selection_done` blocks multi-server restore | Low | The `_startup_selection_done` guard in `sidebar.gd` (line 6) means only the first `guilds_updated` event triggers session restore. If the saved guild belongs to a server that connects second, the fallback guild from the first server is selected instead. |
| No password strength validation on register | Low | `auth_dialog._on_generate_password()` (line 109) generates 12-char random passwords, but manual password entry has no length or complexity requirements -- validation is server-side only. |
| Display name not synced to username on sign-in | Low | When signing in (not registering), the display name field is hidden. The stored `current_user` display name comes from the server, but if the user registered with a different display name elsewhere, there's no way to update it from the auth dialog. |
