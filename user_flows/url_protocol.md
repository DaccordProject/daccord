# URL Protocol (`daccord://`)

Priority: 61
Depends on: Server Connection

## Overview

A custom `daccord://` URL scheme enabling deep links into the application -- connecting to servers, accepting invites, and navigating to specific spaces/channels from external sources (browser links, QR codes, chat messages, desktop shortcuts). Requires platform-specific registration (Windows registry, Linux `.desktop` MimeType, macOS `CFBundleURLTypes`), CLI argument handling, and IPC to forward URIs to an already-running instance.

## URL Scheme Design

```
daccord://connect/<host>[:<port>][/<space-slug>][?token=<value>&invite=<code>&channel=<name>]
daccord://invite/<code>@<host>[:<port>]
daccord://navigate/<space-id>[/<channel-id>][?msg=<message-id>]
```

| Route | Purpose | Example |
|-------|---------|---------|
| `connect` | Open Add Server dialog pre-filled (or auto-connect if token present) | `daccord://connect/chat.example.com/general?token=abc123` |
| `invite` | Accept an invite on a specific server | `daccord://invite/ABCDEF@chat.example.com` |
| `navigate` | Jump to a space/channel already connected | `daccord://navigate/123456/789012` |

Defaults (matching existing `parse_server_url` behavior):
- Port: `443` when omitted
- Space slug: `"general"` when omitted
- Protocol to server: HTTPS, falling back to HTTP (existing probe behavior)

## User Steps

### Clicking a `daccord://connect/...` link

1. User clicks a `daccord://connect/chat.example.com/general` link in a browser or another app
2. OS launches daccord (or forwards to running instance via IPC)
3. `UriHandler` parses the URI from `--uri` CLI argument or bare `daccord://` arg (line 32-40)
4. **If already connected:** navigates directly to the space/channel (line 285-294)
5. **If token is present:** shows confirmation dialog ("Connect to X with an embedded token?"), then opens Add Server dialog pre-filled (line 308-311)
6. **If no token:** opens Add Server dialog pre-filled with host/port/space, user completes auth
7. On successful connection, navigates to the space

### Clicking a `daccord://invite/...` link

1. User clicks `daccord://invite/ABCDEF@chat.example.com`
2. OS launches daccord or forwards via IPC
3. `UriHandler` parses URI, extracts invite code and server host (line 143-177)
4. **If already connected to that server:** accepts invite directly via REST API and shows toast (line 321-328)
5. **If not connected:** opens Add Server dialog pre-filled with host and invite code (line 330-336)
6. After auth + invite acceptance, navigates to the joined space

### Clicking a `daccord://navigate/...` link

1. User clicks `daccord://navigate/123456/789012`
2. OS launches daccord or forwards via IPC
3. `UriHandler` looks up space ID in `Client.spaces` (line 344-350)
4. If found, calls `AppState.select_space()` then `AppState.select_channel()` to navigate (line 357-361)
5. If space not connected, shows error toast and logs a warning (line 353-354)

## Signal Flow

```
OS launches app with --uri arg (or bare daccord:// arg on macOS)
    |
    v
SingleInstance._ready() ── another instance running?
    |                           |
    | no                        | yes: write URI to user://daccord.uri, quit
    v
UriHandler._ready() (line 14)
    |
    +-- _get_cli_uri() extracts --uri or bare daccord:// arg (line 32-40)
    |
    +-- call_deferred("_process_uri", uri) (line 21)
    |       |
    |       +-- parse_uri() (line 50-80)
    |       |
    |       +-- match route:
    |           |
    |           +-- "connect" --> _handle_connect() (line 277)
    |           |                     |
    |           |                     +-- already connected? --> navigate directly
    |           |                     |
    |           |                     +-- has token? --> _confirm_token_connect() (line 390)
    |           |                     |                     |
    |           |                     |                     +--> ConfirmationDialog
    |           |                     |                     +--> on confirm: _open_add_server_prefilled()
    |           |                     |
    |           |                     +--> _open_add_server_prefilled(url_str)
    |           |                              |
    |           |                              +--> instantiate AddServerDialog
    |           |                              +--> dialog.open_prefilled(url_text) (line 416-418)
    |           |
    |           +-- "invite" --> _handle_invite() (line 316)
    |           |                    |
    |           |                    +-- already connected? --> _accept_invite_directly() (line 374)
    |           |                    |                              |
    |           |                    |                              +--> accord_client.invites.accept(code)
    |           |                    |                              +--> toast: "Invite accepted!" or error
    |           |                    |
    |           |                    +--> _open_add_server_prefilled(url_str)
    |           |
    |           +-- "navigate" --> _handle_navigate() (line 339)
    |                                  |
    |                                  +--> AppState.select_space(space_id)
    |                                  +--> AppState.select_channel(channel_id)
    |                                  +--> AppState.navigate_to_message (if msg param)
    |                                  +--> toast: "Space not found" (if not connected)
    |
    +-- Timer (0.5s) polls user://daccord.uri for IPC URIs (line 24-28)
            |
            +--> _poll_ipc_file() reads file, deletes it, calls _process_uri()
```

### IPC flow (app already running)

```
OS launches second instance with --uri arg
    |
    v
SingleInstance._ready() detects lock file exists (line 6)
    |
    v
_get_cli_uri() extracts URI from CLI args (line 21-28)
    |
    v
Writes URI to user://daccord.uri (line 10-13)
    |
    v
Quits second instance (line 16)
    |
    v
Running instance's UriHandler._poll_ipc_file() (line 513-528)
    |
    v
Reads + deletes IPC file, dispatches URI via _process_uri()
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/uri_handler.gd` | Autoload: URI parsing, CLI arg extraction, route dispatch, IPC polling, dialog opening, token confirmation, direct invite acceptance |
| `scripts/autoload/single_instance.gd` | PID lock file + IPC URI forwarding for duplicate instances (lines 6-17, 21-28) |
| `scripts/autoload/app_state.gd` | `select_space()` (line 205), `select_channel()` (line 212), `toast_requested` signal (line 130) for navigate/invite feedback |
| `scripts/autoload/client.gd` | `spaces` array, `get_base_url_for_space()` (line 750), `_client_for_space()` (line 375) for invite acceptance |
| `scripts/autoload/config.gd` | CLI argument parsing for `--profile` (lines 42-47); `--uri` handled separately by UriHandler |
| `scripts/autoload/client_connection.gd` | `connect_server()` full auth+connect flow |
| `addons/accordkit/rest/endpoints/invites_api.gd` | `accept(code)` (line 21) for direct invite acceptance via REST |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `parse_server_url()` (lines 39-77), `open_prefilled()` (lines 82-84), `_connect_with_token()` (lines 270-296) |
| `scenes/sidebar/guild_bar/add_server_dialog.tscn` | Add Server dialog UI |
| `scenes/sidebar/guild_bar/guild_icon.gd` | "Copy Server Link" context menu (line 237, 303, 308-324) |
| `scenes/sidebar/channels/channel_item.gd` | "Copy Channel Link" context menu (line 222, 236, 257-274) |
| `scenes/messages/message_view_actions.gd` | "Copy Message Link" context menu (line 35, 137, 222-230) |
| `scenes/main/main_window.gd` | Root scene; toast_requested connection (line 115); UriHandler adds dialogs as children of MainWindow |
| `scenes/main/welcome_screen.gd` | First-run CTA; instantiates AddServerDialog (line 218) |
| `dist/installer.iss` | Windows installer; `[Registry]` section registers `daccord://` protocol handler (lines 51-55) |
| `dist/daccord.desktop` | Linux desktop entry; `MimeType=x-scheme-handler/daccord;` (line 11), `Exec=daccord --uri %u` (line 4) |
| `export_presets.cfg` | macOS bundle config; `CFBundleURLTypes` in `additional_plist_content` (line 157) |
| `project.godot` | Autoload registration; `UriHandler` registered after `ThemeManager` (line 38) |
| `tests/unit/test_uri_handler.gd` | 30 unit tests for URI parsing, URL building, and rejection cases |

## Implementation Details

### UriHandler autoload (`scripts/autoload/uri_handler.gd`)

Registered as the last autoload in `project.godot` (line 38), after `ThemeManager`, so all other autoloads (`Client`, `AppState`, `Config`) are available when it runs.

**Startup flow (line 14-28):**
1. `_ready()` calls `_ensure_protocol_registered()` to auto-register the URL handler on Linux/Windows.
2. Calls `_get_cli_uri()` to extract `--uri <value>` or a bare `daccord://` argument from the command line.
3. If a URI is found, uses `call_deferred("_process_uri", uri)` to let `Client._ready()` finish its startup connect flow first.
4. Creates a `Timer` (0.5s interval) that polls for `user://daccord.uri`, the IPC file written by duplicate instances.

**URI parser (`parse_uri`, line 50-80):**
- Static method, returns a Dictionary or `{}` on invalid input.
- Strips the `daccord://` scheme, extracts the route (first path segment), then dispatches to `_parse_connect`, `_parse_invite`, or `_parse_navigate`.
- Unknown routes return `{}`.

**Connect parser (`_parse_connect`, line 83-140):**
- Extracts query parameters (`?token=...&invite=...&channel=...`) first.
- Splits remaining payload into `host[:port][/space-slug]`.
- Defaults: port 443, space slug `"general"`.
- Validates host via `_is_valid_host()` (rejects spaces, quotes, angle brackets, semicolons).
- Returns `{ route, host, port, space_slug, token, invite_code }` with optional `channel` key.

**Invite parser (`_parse_invite`, line 143-177):**
- Format: `<code>@<host>[:<port>]`.
- Validates invite code is alphanumeric only via `_is_alphanumeric()` (line 210-215).
- Returns `{ route, invite_code, host, port }`.

**Navigate parser (`_parse_navigate`, line 180-207):**
- Format: `<space-id>[/<channel-id>][?msg=<message-id>]`.
- Returns `{ route, space_id }` with optional `channel_id` and `message_id`.

**Route handlers:**
- `_handle_connect` (line 277-313): First checks if already connected to the target space — if so, navigates directly. Otherwise builds a URL string in the format `add_server_dialog.parse_server_url()` expects. If the URI contains a token, shows a `ConfirmationDialog` via `_confirm_token_connect()` (line 390-406) before proceeding. Otherwise opens a pre-filled AddServerDialog.
- `_handle_invite` (line 316-336): Checks if already connected to the server by comparing `base_url`. If connected, calls `_accept_invite_directly()` (line 374-387) which uses `accord_client.invites.accept(code)` and shows a toast for success/failure. If not connected, opens a pre-filled AddServerDialog with the invite code.
- `_handle_navigate` (line 339-361): Searches `Client.spaces` for matching space ID, then calls `AppState.select_space()` and optionally `AppState.select_channel()`. Emits `AppState.navigate_to_message` if a `msg` query param is present. Shows an error toast if the space isn't connected.

**Token confirmation dialog (`_confirm_token_connect`, line 390-406):**
- Shows a `ConfirmationDialog` warning the user about connecting with an embedded token.
- Dialog text: "Connect to {host} with an embedded token? Only proceed if you trust the source of this link."
- On confirm, proceeds to `_open_add_server_prefilled()`.

**Direct invite acceptance (`_accept_invite_directly`, line 374-387):**
- Gets the `AccordClient` for an existing connection via `Client._client_for_space()`.
- Calls `accord_client.invites.accept(code)` (REST `POST /invites/{code}/accept`).
- Shows toast: "Invite accepted!" on success, "Failed to accept invite" on failure.

**Dialog opening (`_open_add_server_prefilled`, line 409-418):**
- Finds `MainWindow` in the scene tree.
- Instantiates a fresh `AddServerDialogScene` (same pattern as `guild_bar.gd` line 142 and `welcome_screen.gd` line 218).
- Adds it as a child of `MainWindow` and calls `open_prefilled()`.

**IPC file watcher (`_poll_ipc_file`, line 513-528):**
- Runs every 0.5s via Timer.
- Checks for `user://daccord.uri`, reads it, deletes it immediately, then dispatches via `_process_uri()`.

### URL builders

- `build_base_url(host, port)` (line 228-231): Constructs `https://host[:port]` for internal use.
- `build_connect_url(host, port, space_slug, channel_name)` (line 235-245): Constructs `daccord://connect/...` URLs for sharing.
- `build_navigate_url(space_id, channel_id, message_id)` (line 249-257): Constructs `daccord://navigate/...` URLs for sharing.

### SingleInstance IPC extension (`scripts/autoload/single_instance.gd`)

Extended with `_get_cli_uri()` (lines 21-28) that extracts `--uri` or bare `daccord://` arguments from the command line. When a duplicate instance is detected (line 6):

1. Calls `_get_cli_uri()` to check if this launch was triggered by a URI.
2. If a URI is present, writes it to `user://daccord.uri` (lines 10-13) so the running instance's `UriHandler` can pick it up.
3. If no URI, shows the existing "already running" alert (line 15).
4. Quits in both cases (line 16).

### AddServerDialog pre-fill (`scenes/sidebar/guild_bar/add_server_dialog.gd`)

Method `open_prefilled()` (lines 82-84):
- Sets `_url_input.text` to the provided URL string.
- Switches `_tab_container` to tab 1 ("Enter URL") so the user sees the pre-filled input.
- The user can then review the pre-filled URL and click "Add" to proceed through the normal `_on_add_pressed()` flow (line 156).

### URL sharing context menus

"Copy Link" context menu items generate `daccord://` URLs and copy them to the clipboard:
- **Space links:** `guild_icon.gd` — "Copy Server Link" item (line 237), handler `_copy_server_link()` (line 308-324) uses `UriHandler.build_connect_url()`.
- **Channel links:** `channel_item.gd` — "Copy Channel Link" item (line 222), handler `_on_copy_channel_link()` (line 257-274) uses `UriHandler.build_connect_url()` with channel name.
- **Message links:** `message_view_actions.gd` — "Copy Message Link" item (line 35), handler `_copy_message_link()` (line 222-230) uses `UriHandler.build_navigate_url()` with message ID.

All handlers copy to clipboard and emit `AppState.toast_requested.emit(tr("Link copied!"))` for visual feedback.

### Platform registration

**Windows (`dist/installer.iss`, lines 51-55):**
- `[Registry]` section registers `HKCU\Software\Classes\daccord` as a URL protocol handler.
- Sets `URL Protocol` value (required for Windows to recognize it as a URL handler).
- Points `shell\open\command` to `daccord.exe --uri "%1"`.
- `Flags: uninsdeletekey` ensures cleanup on uninstall.

**Windows runtime (`_ensure_protocol_windows`, line 474-501):**
- At startup, checks if the registry key exists. If not, writes the same keys the installer would.

**Linux (`dist/daccord.desktop`, lines 4, 11):**
- `Exec=daccord --uri %u` passes the URI as `--uri` argument (`%u` is the freedesktop URL placeholder).
- `MimeType=x-scheme-handler/daccord;` declares the scheme handler.

**Linux runtime (`_ensure_protocol_linux`, line 433-471):**
- At startup, queries `xdg-mime` to check if the handler is registered.
- If not, writes a `.desktop` file to `~/.local/share/applications/daccord.desktop` and registers it via `xdg-mime default`.
- No manual `xdg-mime` command needed — registration is fully automated.

**macOS (`export_presets.cfg`, line 157):**
- `additional_plist_content` contains `CFBundleURLTypes` with the `daccord` URL scheme.
- On macOS, the OS delivers the URL via an Apple Event; Godot surfaces it through `OS.get_cmdline_args()`. The `_get_cli_uri()` method handles bare `daccord://` arguments for this case (line 38).

### Security considerations

- **Host validation:** `_is_valid_host()` (line 218-224) rejects hosts containing spaces, quotes, angle brackets, and semicolons to prevent injection.
- **Invite code sanitization:** `_is_alphanumeric()` (line 210-215) ensures invite codes contain only `[A-Za-z0-9]`.
- **Token confirmation:** Token-bearing URIs (`daccord://connect/...?token=abc`) now show a `ConfirmationDialog` before proceeding, warning the user to only proceed if they trust the source (line 390-406).
- **Token in URL:** `daccord://connect/...?token=abc` exposes the auth token in browser history, clipboard, and logs. Prefer invite codes for sharing.

### Test coverage (`tests/unit/test_uri_handler.gd`)

30 unit tests covering:
- **Connect route (10 tests):** full URL with all params, host-only, host+slug, host+port, token-only, invite-only, default port, channel param, channel+token, no-channel-key.
- **Invite route (4 tests):** full with port, default port, reject non-alphanumeric code, reject empty code.
- **Navigate route (4 tests):** space+channel, space-only, with message ID, without message key.
- **Rejection cases (9 tests):** empty URI, wrong scheme, bare scheme, scheme with trailing slash, unknown route, empty host, empty navigate payload, host with angle brackets, host with semicolon, host with quotes.
- **build_base_url (2 tests):** default port (443 omitted), custom port (included).
- **build_connect_url (5 tests):** space-only, with port, with channel, channel with spaces, empty slug.
- **build_navigate_url (3 tests):** channel-only, with message, space-only.

## Implementation Status

- [x] `daccord://` URL scheme design
- [x] `UriHandler` autoload (`scripts/autoload/uri_handler.gd`)
- [x] `UriHandler` registered in `project.godot` (line 38)
- [x] `--uri` CLI argument parsing in `UriHandler._get_cli_uri()` (line 32-40)
- [x] URI parser for `connect`, `invite`, `navigate` routes (line 50-207)
- [x] Host validation and invite code sanitization (lines 210-224)
- [x] `AddServerDialog.open_prefilled()` method (line 82-84)
- [x] Route handlers: connect, invite, navigate (lines 277-361)
- [x] Dialog instantiation via `_open_add_server_prefilled()` (line 409-418)
- [x] IPC via `user://daccord.uri` file for already-running instances
- [x] `SingleInstance` extension to write URI before quitting (lines 6-17)
- [x] IPC file watcher (Timer-based) in `UriHandler` (lines 24-28, 513-528)
- [x] Windows registry protocol handler in `dist/installer.iss` (lines 51-55)
- [x] Windows runtime protocol registration (`_ensure_protocol_windows`, line 474-501)
- [x] Linux `.desktop` MimeType + Exec with `%u` (lines 4, 11)
- [x] Linux runtime xdg-mime registration (`_ensure_protocol_linux`, line 433-471)
- [x] macOS `CFBundleURLTypes` in `additional_plist_content` (`export_presets.cfg`, line 157)
- [x] Unit tests for URI parsing (`test_uri_handler.gd`, 30 tests)
- [x] URL builder helpers: `build_connect_url`, `build_navigate_url` (lines 235-257)
- [x] "Copy Server Link" context menu (`guild_icon.gd`, line 237)
- [x] "Copy Channel Link" context menu (`channel_item.gd`, line 222)
- [x] "Copy Message Link" context menu (`message_view_actions.gd`, line 35)
- [x] Toast feedback for copy actions and navigation errors
- [x] Confirmation dialog for token-bearing URIs (`_confirm_token_connect`, line 390-406)
- [x] Direct invite acceptance when already connected (`_accept_invite_directly`, line 374-387)
- [x] Error toast for failed navigate (line 354) and channel-not-found (line 371)
- [x] Fix channel navigation on cold start (navigate routes await `server_synced` signal)
- [x] Fix IPC forwarding (heartbeat-based lock detection for reliable instance detection)
- [ ] macOS Apple Event delivery testing (CFBundleURLTypes is configured but untested)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Channel navigation fails on cold start | High | **Fixed.** Navigate routes now await `AppState.server_synced` for the target space before dispatching. A 15s fallback timeout prevents indefinite waiting if the space never syncs. Connect/invite routes still use `call_deferred` since they open dialogs that don't need channel data. |
| Second instance does not forward URI to running instance | High | **Fixed.** `SingleInstance` now writes a heartbeat to the lock file every 2s. The second instance checks if the lock file was modified within the last 5s (more reliable than `kill -0` which can fail due to permissions or PID reuse). Falls back to process-alive check for the brief startup window before the first heartbeat. |
| macOS Apple Event delivery untested | Medium | `CFBundleURLTypes` is configured in `export_presets.cfg` (line 157) but Godot 4's handling of Apple Events has not been verified on a real macOS build |
| Token exposure in URLs | Low | Auth tokens in `daccord://connect/...?token=...` may leak via browser history/logs; confirmation dialog mitigates but doesn't prevent exposure. Prefer invite codes for sharing |
