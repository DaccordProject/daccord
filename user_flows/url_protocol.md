# URL Protocol (`daccord://`)

## Overview

A custom `daccord://` URL scheme enabling deep links into the application -- connecting to servers, accepting invites, and navigating to specific spaces/channels from external sources (browser links, QR codes, chat messages, desktop shortcuts). Requires platform-specific registration (Windows registry, Linux `.desktop` MimeType, macOS `CFBundleURLTypes`), CLI argument handling, and IPC to forward URIs to an already-running instance.

## URL Scheme Design

```
daccord://connect/<host>[:<port>][/<space-slug>][?token=<value>&invite=<code>]
daccord://invite/<code>@<host>[:<port>]
daccord://navigate/<space-id>[/<channel-id>]
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
3. `UriHandler` parses the URI from `--uri` CLI argument or bare `daccord://` arg (line 30-38)
4. **If token is present:** opens Add Server dialog pre-filled, user clicks Add to auto-connect
5. **If no token:** opens Add Server dialog pre-filled with host/port/space, user completes auth
6. On successful connection, navigates to the space

### Clicking a `daccord://invite/...` link

1. User clicks `daccord://invite/ABCDEF@chat.example.com`
2. OS launches daccord or forwards via IPC
3. `UriHandler` parses URI, extracts invite code and server host (line 135-169)
4. Opens Add Server dialog pre-filled with host and invite code (line 251-262)
5. After auth + invite acceptance, navigates to the joined space

### Clicking a `daccord://navigate/...` link

1. User clicks `daccord://navigate/123456/789012`
2. OS launches daccord or forwards via IPC
3. `UriHandler` looks up space ID in `Client.spaces` (line 270-275)
4. If found, calls `AppState.select_space()` then `AppState.select_channel()` to navigate (line 281-283)
5. If space not connected, logs a warning (line 278)

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
    +-- _get_cli_uri() extracts --uri or bare daccord:// arg (line 30-38)
    |
    +-- call_deferred("_process_uri", uri) (line 19)
    |       |
    |       +-- parse_uri() (line 48-78)
    |       |
    |       +-- match route:
    |           |
    |           +-- "connect" --> _handle_connect() (line 230)
    |           |                     |
    |           |                     +--> _open_add_server_prefilled(url_str)
    |           |                              |
    |           |                              +--> instantiate AddServerDialog
    |           |                              +--> dialog.open_prefilled(url_text) (line 82-84)
    |           |
    |           +-- "invite" --> _handle_invite() (line 251)
    |           |                    |
    |           |                    +--> _open_add_server_prefilled(url_str)
    |           |
    |           +-- "navigate" --> _handle_navigate() (line 265)
    |                                  |
    |                                  +--> AppState.select_space(space_id)
    |                                  +--> AppState.select_channel(channel_id)
    |
    +-- Timer (0.5s) polls user://daccord.uri for IPC URIs (line 22-26)
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
Running instance's UriHandler._poll_ipc_file() (line 307-322)
    |
    v
Reads + deletes IPC file, dispatches URI via _process_uri()
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/uri_handler.gd` | New autoload: URI parsing, CLI arg extraction, route dispatch, IPC polling, dialog opening |
| `scripts/autoload/single_instance.gd` | PID lock file + IPC URI forwarding for duplicate instances (lines 6-17, 21-28) |
| `scripts/autoload/app_state.gd` | `select_space()` (line 205), `select_channel()` (line 212) for navigate route |
| `scripts/autoload/client.gd` | `spaces` array used by navigate handler to verify connectivity |
| `scripts/autoload/config.gd` | CLI argument parsing for `--profile` (lines 42-47); `--uri` handled separately by UriHandler |
| `scripts/autoload/client_connection.gd` | `connect_server()` full auth+connect flow |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `parse_server_url()` (lines 39-77), `open_prefilled()` (lines 82-84), `_connect_with_token()` (lines 270-296) |
| `scenes/sidebar/guild_bar/add_server_dialog.tscn` | Add Server dialog UI |
| `scenes/main/main_window.gd` | Root scene; UriHandler adds dialogs as children of MainWindow |
| `scenes/main/welcome_screen.gd` | First-run CTA; instantiates AddServerDialog (line 218) |
| `dist/installer.iss` | Windows installer; `[Registry]` section registers `daccord://` protocol handler (lines 51-55) |
| `dist/daccord.desktop` | Linux desktop entry; `MimeType=x-scheme-handler/daccord;` (line 11), `Exec=daccord --uri %u` (line 4) |
| `export_presets.cfg` | macOS bundle config; needs `CFBundleURLTypes` in Info.plist (not yet added) |
| `project.godot` | Autoload registration; `UriHandler` registered after `ThemeManager` (line 38) |
| `tests/unit/test_uri_handler.gd` | 23 unit tests for URI parsing, rejection, and `build_base_url()` |

## Implementation Details

### UriHandler autoload (`scripts/autoload/uri_handler.gd`)

Registered as the last autoload in `project.godot` (line 38), after `ThemeManager`, so all other autoloads (`Client`, `AppState`, `Config`) are available when it runs.

**Startup flow (line 14-26):**
1. `_ready()` calls `_get_cli_uri()` to extract `--uri <value>` or a bare `daccord://` argument from the command line.
2. If a URI is found, uses `call_deferred("_process_uri", uri)` to let `Client._ready()` finish its startup connect flow first.
3. Creates a `Timer` (0.5s interval) that polls for `user://daccord.uri`, the IPC file written by duplicate instances.

**URI parser (`parse_uri`, line 48-78):**
- Static method, returns a Dictionary or `{}` on invalid input.
- Strips the `daccord://` scheme, extracts the route (first path segment), then dispatches to `_parse_connect`, `_parse_invite`, or `_parse_navigate`.
- Unknown routes return `{}`.

**Connect parser (`_parse_connect`, line 81-132):**
- Extracts query parameters (`?token=...&invite=...`) first.
- Splits remaining payload into `host[:port][/space-slug]`.
- Defaults: port 443, space slug `"general"`.
- Validates host via `_is_valid_host()` (rejects spaces, quotes, angle brackets, semicolons).
- Returns `{ route, host, port, space_slug, token, invite_code }`.

**Invite parser (`_parse_invite`, line 135-169):**
- Format: `<code>@<host>[:<port>]`.
- Validates invite code is alphanumeric only via `_is_alphanumeric()` (line 189-194).
- Returns `{ route, invite_code, host, port }`.

**Navigate parser (`_parse_navigate`, line 172-186):**
- Format: `<space-id>[/<channel-id>]`.
- Returns `{ route, space_id }` with optional `channel_id`.

**Route handlers:**
- `_handle_connect` (line 230-248): Builds a URL string in the format `add_server_dialog.parse_server_url()` expects (`host:port#slug?token=...&invite=...`), then opens a pre-filled AddServerDialog.
- `_handle_invite` (line 251-262): Builds `host:port?invite=CODE` and opens a pre-filled AddServerDialog.
- `_handle_navigate` (line 265-283): Searches `Client.spaces` for matching space ID, then calls `AppState.select_space()` and optionally `AppState.select_channel()`. Logs a warning if the space isn't connected.

**Dialog opening (`_open_add_server_prefilled`, line 287-295):**
- Finds `MainWindow` in the scene tree.
- Instantiates a fresh `AddServerDialogScene` (same pattern as `guild_bar.gd` line 142 and `welcome_screen.gd` line 218).
- Adds it as a child of `MainWindow` and calls `open_prefilled()`.

**IPC file watcher (`_poll_ipc_file`, line 307-322):**
- Runs every 0.5s via Timer.
- Checks for `user://daccord.uri`, reads it, deletes it immediately, then dispatches via `_process_uri()`.

### SingleInstance IPC extension (`scripts/autoload/single_instance.gd`)

Extended with `_get_cli_uri()` (lines 21-28) that extracts `--uri` or bare `daccord://` arguments from the command line. When a duplicate instance is detected (line 6):

1. Calls `_get_cli_uri()` to check if this launch was triggered by a URI.
2. If a URI is present, writes it to `user://daccord.uri` (lines 10-13) so the running instance's `UriHandler` can pick it up.
3. If no URI, shows the existing "already running" alert (line 15).
4. Quits in both cases (line 16).

### AddServerDialog pre-fill (`scenes/sidebar/guild_bar/add_server_dialog.gd`)

New method `open_prefilled()` (lines 82-84):
- Sets `_url_input.text` to the provided URL string.
- Switches `_tab_container` to tab 1 ("Enter URL") so the user sees the pre-filled input.
- The user can then review the pre-filled URL and click "Add" to proceed through the normal `_on_add_pressed()` flow (line 156).

### Platform registration

**Windows (`dist/installer.iss`, lines 51-55):**
- `[Registry]` section registers `HKCU\Software\Classes\daccord` as a URL protocol handler.
- Sets `URL Protocol` value (required for Windows to recognize it as a URL handler).
- Points `shell\open\command` to `daccord.exe --uri "%1"`.
- `Flags: uninsdeletekey` ensures cleanup on uninstall.

**Linux (`dist/daccord.desktop`, lines 4, 11):**
- `Exec=daccord --uri %u` passes the URI as `--uri` argument (`%u` is the freedesktop URL placeholder).
- `MimeType=x-scheme-handler/daccord;` declares the scheme handler.
- Users must run `xdg-mime default daccord.desktop x-scheme-handler/daccord` to register (not yet automated).

**macOS (`export_presets.cfg`):**
- Needs `CFBundleURLTypes` added to the Info.plist section. Not yet implemented.
- On macOS, the OS delivers the URL via an Apple Event; Godot may surface it through `OS.get_cmdline_args()`. The `_get_cli_uri()` method handles bare `daccord://` arguments for this case (line 36).

### Security considerations

- **Host validation:** `_is_valid_host()` (line 197-203) rejects hosts containing spaces, quotes, angle brackets, and semicolons to prevent injection.
- **Invite code sanitization:** `_is_alphanumeric()` (line 189-194) ensures invite codes contain only `[A-Za-z0-9]`.
- **Token in URL:** `daccord://connect/...?token=abc` exposes the auth token in browser history, clipboard, and logs. Prefer invite codes for sharing.
- **No auto-connect yet:** URIs always open the AddServerDialog for user review before connecting. A confirmation dialog for auto-connect URIs is a future enhancement.

### Test coverage (`tests/unit/test_uri_handler.gd`)

23 unit tests covering:
- **Connect route (7 tests):** full URL with all params, host-only, host+slug, host+port, token-only, invite-only, default port.
- **Invite route (4 tests):** full with port, default port, reject non-alphanumeric code, reject empty code.
- **Navigate route (2 tests):** space+channel, space-only.
- **Rejection cases (7 tests):** empty URI, wrong scheme, bare scheme, scheme with trailing slash, unknown route, empty host, empty navigate payload, host with angle brackets, host with semicolon, host with quotes.
- **build_base_url (2 tests):** default port (443 omitted), custom port (included).

## Implementation Status

- [x] `daccord://` URL scheme design
- [x] `UriHandler` autoload (`scripts/autoload/uri_handler.gd`)
- [x] `UriHandler` registered in `project.godot` (line 38)
- [x] `--uri` CLI argument parsing in `UriHandler._get_cli_uri()` (line 30-38)
- [x] URI parser for `connect`, `invite`, `navigate` routes (line 48-186)
- [x] Host validation and invite code sanitization (lines 189-203)
- [x] `AddServerDialog.open_prefilled()` method (line 82-84)
- [x] Route handlers: connect, invite, navigate (lines 230-283)
- [x] Dialog instantiation via `_open_add_server_prefilled()` (line 287-295)
- [x] IPC via `user://daccord.uri` file for already-running instances
- [x] `SingleInstance` extension to write URI before quitting (lines 6-17)
- [x] IPC file watcher (Timer-based) in `UriHandler` (lines 22-26, 307-322)
- [x] Windows registry protocol handler in `dist/installer.iss` (lines 51-55)
- [x] Linux `.desktop` MimeType + Exec with `%u` (lines 4, 11)
- [x] Unit tests for URI parsing (`test_uri_handler.gd`, 23 tests)
- [ ] macOS `CFBundleURLTypes` in Info.plist via `export_presets.cfg`
- [ ] Confirmation dialog for auto-connect URIs with tokens (security)
- [ ] "Copy Invite Link" / "Copy Channel Link" / "Copy Connection Link" context menu actions
- [ ] Linux `xdg-mime` registration automation (post-install script or user docs)
- [ ] Error toast for failed navigate (currently only `push_warning`)
- [ ] Direct invite acceptance when already connected to server (currently always opens dialog)

## Tasks

### URL-1: macOS `CFBundleURLTypes` not configured
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** general
- **Notes:** `export_presets.cfg` needs `CFBundleURLTypes` added to the macOS Info.plist section; Godot 4 Apple Event delivery needs testing

### URL-2: No confirmation dialog for token-bearing URIs
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** security, ui
- **Notes:** Malicious `daccord://connect/...?token=...` links currently open the dialog pre-filled -- user must still click "Add", but a dedicated confirmation ("Connect to X?") would be clearer

### URL-3: No URL generation / sharing UI
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** Users cannot generate `daccord://` links from within the app; needs context menu items on spaces, channels, and Add Server dialog

### URL-4: Linux xdg-mime registration not automated
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** general
- **Notes:** Users must manually run `xdg-mime default daccord.desktop x-scheme-handler/daccord`; needs post-install script or documentation

### URL-5: Navigate route has no user-visible error feedback
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** ui
- **Notes:** `_handle_navigate` only calls `push_warning` (line 278) when the space isn't connected; should show an error toast

### URL-6: Invite route always opens dialog even if already connected
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** `_handle_invite` (line 251-262) always opens AddServerDialog with invite code; should check if already connected and accept invite directly via `POST /invites/{code}/accept`

### URL-7: Token exposure in URLs
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** security
- **Notes:** Auth tokens in `daccord://connect/...?token=...` may leak via browser history/logs; prefer invite codes for sharing
