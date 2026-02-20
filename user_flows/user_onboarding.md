# User Onboarding


## Overview

User onboarding covers the complete first-run experience: launching daccord with no configured servers, adding the first server (including authentication), and reaching a usable state with guilds, channels, and messages displayed. It also covers subsequent launches where the previous session is restored automatically.

## User Steps

### First launch (no servers)

1. User opens daccord for the first time
2. Config file is created (or is empty) -- `Config.has_servers()` returns `false`
3. Client stays in `CONNECTING` mode; sidebar guild bar shows only the DM button and "+" Add Server button
4. **Welcome screen appears** in the content area: animated shader background (navy-to-purple gradient with bokeh particles and sparkle shimmer), floating CPUParticles2D rising upward, staggered entrance animations for branding and feature cards
5. Welcome screen displays: "daccord" logo, tagline "Connect. Communicate. Collaborate.", three feature cards (Multi-Server, Real-Time Chat, Voice & Video), and a pulsing "Add a Server" CTA button
6. User clicks the "Add a Server" CTA button (or the "+" button in the guild bar)
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

main_window._ready()
    Config.has_servers() == false
    -> _show_welcome_screen()
        -> WelcomeScreenScene instantiated, added to content_area
        -> content_body hidden
        -> connects AppState.guilds_updated -> _on_first_server_added (ONE_SHOT)
        -> welcome_screen._ready() -> _animate_entrance()
            -> staggered fade-in: logo (0.0s), tagline (0.15s), features (0.3s), CTA (0.5s)
            -> CTA pulse glow loop starts after entrance

UI shows: guild bar ("+" only), welcome screen with animated shader bg + particles

User clicks CTA "Add a Server" (or "+" in guild bar)
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

        -> main_window._on_first_server_added()        (ONE_SHOT)
            -> welcome_screen.dismiss()
                -> fade out + slide up (0.3s)
                -> dismissed.emit() -> content_body.visible = true
                -> queue_free()

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
| `scripts/autoload/app_state.gd` | `guilds_updated` signal triggers sidebar startup selection; `server_connecting` signal for overlay progress |
| `scripts/autoload/client_connection.gd` | Server connection lifecycle; emits `server_connecting` at start of `connect_server()` |
| `scenes/sidebar/guild_bar/add_server_button.gd` | "+" button, emits `add_server_pressed`; pulse animation when no servers configured |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | URL parsing (line 24), server probing (line 134), connection (line 161) |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Sign In / Register flow, emits `auth_completed` (line 3) |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Instantiates dialog (line 87), auto-selects new guild (line 92) |
| `scenes/sidebar/sidebar.gd` | Startup selection logic with multi-server retry (fallback + 5s timer), session restore |
| `scenes/sidebar/channels/channel_list.gd` | Empty state for no channels (lines 45-61), `pending_channel_id` (line 12) |
| `scenes/messages/message_view.gd` | Empty state for no messages (line 141), loading state (line 116) |
| `scenes/main/welcome_screen.gd` | Welcome screen with animated background, entrance animations, CTA button, responsive layout |
| `scenes/main/welcome_screen.tscn` | Welcome screen scene (shader bg, CPUParticles2D, feature cards, CTA button) |
| `theme/welcome_bg.gdshader` | Animated gradient background shader (bokeh particles, sparkle shimmer) |
| `scenes/main/connecting_overlay.gd` | Connecting overlay with animated dots, progress tracking, auto-dismiss |
| `scenes/main/connecting_overlay.tscn` | Connecting overlay scene |
| `scenes/main/main_window.gd` | Root scene; shows welcome screen when no servers configured, connecting overlay on startup, dismisses on first `guilds_updated` |

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

### Welcome screen (first-run)

`main_window._ready()` checks `Config.has_servers()`. If false, it calls `_show_welcome_screen()` which instantiates the `WelcomeScreenScene`, adds it to `content_area`, hides `content_body`, and connects `AppState.guilds_updated` to `_on_first_server_added()` as a one-shot.

The welcome screen (`welcome_screen.gd`) layers three visual elements:
1. **Shader background** (`welcome_bg.gdshader`): Animated navy-to-purple gradient with 15 bokeh particles (soft glowing circles drifting upward using layered sine waves) and procedural hash-based sparkle shimmer. All GL Compatibility safe.
2. **CPUParticles2D**: 30 particles with 8s lifetime, rising from the bottom with slight spread, blurple-tinted gradient fading to transparent. Chosen over GPUParticles2D for GL Compatibility reliability.
3. **Content**: Logo, tagline, three feature cards (Multi-Server, Real-Time Chat, Voice & Video) with semi-transparent panel backgrounds, and a large blurple CTA button.

**Entrance animation** (tween-based, ~1.2s total): All content starts at `modulate.a = 0` offset 30px down. Elements stagger in with EASE_OUT CUBIC: logo (0.0s), tagline (0.15s), features (0.3s), CTA (0.5s with scale bounce from 0.9 to 1.0 via TRANS_BACK). After entrance, the CTA gets a looping pulse glow (modulate oscillates between 1.0 and 1.1 brightness, 2s period).

**Dismiss animation**: On `_on_first_server_added()`, calls `dismiss()` which fades the entire screen out over 0.3s, emits `dismissed`, and `queue_free()`s. The callback re-shows `content_body`.

**Responsive**: Listens to `AppState.layout_mode_changed`. In COMPACT mode (<500px), feature cards switch from HBox to VBox layout. On wider viewports, they revert to horizontal.

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
- [x] Welcome screen with animated shader background, particle effects, staggered entrance animations, and CTA button
- [x] Main window empty state when no servers are configured (welcome screen replaces blank content area)
- [x] Connection progress indicator during startup auto-connect
- [x] Pulse animation on "+" button when no servers configured
- [x] Password minimum length validation on register
- [x] Multi-server session restore (retry logic with fallback timer)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~No welcome screen on first launch~~ | ~~Medium~~ | **Resolved.** Welcome screen now shows animated shader background, floating particles, branding, feature cards, and "Add a Server" CTA. Dismissed automatically when first server connects. |
| ~~No connection progress during startup~~ | ~~Medium~~ | **Resolved.** `ConnectingOverlay` scene appears during startup auto-connect, showing server name, progress count, and animated dots. Fades out when all servers have connected or failed. `AppState.server_connecting` signal emitted by `ClientConnection.connect_server()`. |
| ~~No main window empty state~~ | ~~Medium~~ | **Resolved.** Welcome screen fills the content area when no servers are configured. |
| ~~No onboarding tooltip or callout~~ | ~~Low~~ | **Resolved.** The "+" button now pulses with a looping modulate animation when no servers are configured. Pulse stops on first `guilds_updated`. |
| ~~No server removal UI~~ | ~~Medium~~ | **Resolved.** Guild icon context menu (right-click) provides "Remove Server" option via `guild_icon.gd`. |
| ~~`_startup_selection_done` blocks multi-server restore~~ | ~~Low~~ | **Resolved.** `sidebar.gd` now retries on each `guilds_updated`: selects the first available guild as a temporary fallback, then switches to the saved guild when its server connects. A 5-second timer accepts the current selection if the saved guild never appears. |
| ~~No password strength validation on register~~ | ~~Low~~ | **Resolved.** Register mode now shows a "Minimum 8 characters" hint below the password field. Passwords shorter than 8 characters are rejected with a client-side error before the server request. |
| ~~Display name not synced to username on sign-in~~ | ~~Low~~ | **Resolved.** `auth_completed` signal now carries `display_name` (from the Register form, or `""` for Sign In). Threaded through `add_server_dialog` into `Config.add_server()`, which persists it in the server config section. `GET /users/@me` still provides the authoritative value at runtime. |
