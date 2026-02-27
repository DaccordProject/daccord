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
3. Client parses the URI from `--uri` CLI argument
4. **If token is present:** auto-connects (same flow as `_connect_with_token` in add_server_dialog.gd)
5. **If no token:** opens Add Server dialog pre-filled with host/port/space, user completes auth
6. On successful connection, navigates to the space

### Clicking a `daccord://invite/...` link

1. User clicks `daccord://invite/ABCDEF@chat.example.com`
2. OS launches daccord or forwards via IPC
3. Client parses URI, extracts invite code and server host
4. If already connected to that server, accepts invite directly via `POST /invites/{code}/accept`
5. If not connected, opens Add Server dialog pre-filled with host and invite code
6. After auth + invite acceptance, navigates to the joined space

### Clicking a `daccord://navigate/...` link

1. User clicks `daccord://navigate/123456/789012`
2. OS launches daccord or forwards via IPC
3. Client looks up space ID in connected servers
4. If found, calls `AppState.select_space()` then `AppState.select_channel()` to navigate
5. If space not connected, shows an error toast ("Not connected to that server")

## Signal Flow

```
OS launches app with --uri arg
    │
    ▼
Config._ready() ─── parses --uri alongside --profile (new)
    │
    ▼
Client._ready()
    ├── has_servers? → connect_server() for each (existing)
    │
    ▼
UriHandler._ready() ─── new autoload, processes pending URI
    │
    ├── daccord://connect/... ──► AddServerDialog.open_prefilled(url_parts)
    │                                 │
    │                                 ├── token present? → _connect_with_token()
    │                                 └── no token? → show dialog pre-filled
    │
    ├── daccord://invite/... ──► already connected? → Client.accept_invite(code)
    │                           └── not connected? → AddServerDialog.open_prefilled(url_parts)
    │
    └── daccord://navigate/... ──► AppState.select_space(space_id)
                                   AppState.select_channel(channel_id)
```

### IPC flow (app already running)

```
OS launches second instance with --uri arg
    │
    ▼
SingleInstance._ready() detects lock file exists
    │
    ▼
Writes URI to user://daccord.uri (IPC file)
    │
    ▼
Quits second instance
    │
    ▼
Running instance polls / watches daccord.uri
    │
    ▼
UriHandler picks up URI → processes as above
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/config.gd` | CLI argument parsing; currently handles `--profile` (lines 40-45) |
| `scripts/autoload/single_instance.gd` | PID-based lock file for single instance; needs IPC extension |
| `scripts/autoload/app_state.gd` | `select_space()` (line 176), `select_channel()` (line 183) for navigation |
| `scripts/autoload/client.gd` | `_ready()` startup connect flow (lines 137-198), `connect_server()` (line 244) |
| `scripts/autoload/client_connection.gd` | `connect_server()` full auth+connect flow (lines 12-234) |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `parse_server_url()` (lines 36-82), `_connect_with_token()` (lines 236-261) |
| `scenes/sidebar/guild_bar/add_server_dialog.tscn` | Add Server dialog UI |
| `scenes/main/main_window.gd` | Startup flow, welcome screen vs connecting overlay (lines 163-166) |
| `scenes/main/welcome_screen.gd` | First-run CTA → AddServerDialog (line 211) |
| `dist/installer.iss` | Windows installer -- needs `[Registry]` section for protocol handler |
| `dist/daccord.desktop` | Linux desktop entry -- needs `MimeType=x-scheme-handler/daccord` |
| `export_presets.cfg` | macOS bundle config -- needs `CFBundleURLTypes` in Info.plist |
| `project.godot` | Autoload registration; new `UriHandler` autoload goes here |
| `tests/unit/test_add_server_dialog.gd` | URL parsing tests (18 tests); extend for `daccord://` scheme |

## Implementation Details

### New autoload: `UriHandler` (`scripts/autoload/uri_handler.gd`)

A new autoload registered after `Client` in `project.godot` (line 29-36) that:

1. **Parses the `--uri` CLI arg** in `_ready()`, similar to how `config.gd` parses `--profile` (lines 40-45).
2. **Waits for Client to finish connecting** by awaiting a ready signal or using `call_deferred`.
3. **Dispatches** based on the URI route (`connect`, `invite`, `navigate`).
4. **Watches for IPC file** (`user://daccord.uri`) via a Timer to pick up URIs from second-instance launches.

```
# Proposed URI parsing
static func parse_daccord_uri(uri: String) -> Dictionary:
    # Returns: { "route": "connect"|"invite"|"navigate",
    #            "host": String, "port": int, "space_slug": String,
    #            "token": String, "invite_code": String,
    #            "space_id": String, "channel_id": String }
```

### Extending `parse_server_url()` in `add_server_dialog.gd`

The existing parser (lines 36-82) only recognizes `http://` and `https://`. It would need one of:
- **Option A:** Extend it to strip `daccord://connect/` prefix and delegate to existing parsing.
- **Option B (preferred):** Keep `parse_server_url` as-is for user-typed URLs. The new `UriHandler` has its own parser for the `daccord://` scheme and converts to the same Dictionary shape before calling `AddServerDialog` or `Client` methods.

### Extending `SingleInstance` for IPC

Currently (`single_instance.gd`), detecting a running instance just exits the second process. To support URI forwarding:

1. **Second instance:** Before quitting, write the `--uri` value to `user://daccord.uri`.
2. **Running instance:** A Timer (every 0.5s) checks for `user://daccord.uri`. If found, reads it, deletes it, and dispatches via `UriHandler`.

This avoids complex IPC (named pipes, sockets) and works cross-platform with Godot's `FileAccess`.

### Pre-filling AddServerDialog

Add a new method to `add_server_dialog.gd`:

```gdscript
func open_prefilled(url_parts: Dictionary) -> void:
    url_input.text = url_parts.get("host", "") + ":" + str(url_parts.get("port", 443))
    if url_parts.has("space_slug"):
        url_input.text += "#" + url_parts["space_slug"]
    popup_centered()
    if url_parts.has("token"):
        _on_add_pressed()  # auto-submit
```

### Platform registration

#### Windows (`dist/installer.iss`)

Add a `[Registry]` section:

```ini
[Registry]
Root: HKCU; Subkey: "Software\Classes\daccord"; ValueType: string; ValueData: "URL:daccord Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\daccord"; ValueName: "URL Protocol"; ValueType: string; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\daccord\DefaultIcon"; ValueType: string; ValueData: "{app}\daccord.exe,0"
Root: HKCU; Subkey: "Software\Classes\daccord\shell\open\command"; ValueType: string; ValueData: """{app}\daccord.exe"" --uri ""%1"""
```

#### Linux (`dist/daccord.desktop`)

Add to the `.desktop` file:

```ini
MimeType=x-scheme-handler/daccord;
```

Then register with `xdg-mime`:

```bash
xdg-mime default daccord.desktop x-scheme-handler/daccord
```

This could be done in a post-install script or documented for users.

#### macOS (Info.plist via export_presets.cfg)

Godot's macOS export supports custom Info.plist entries. Add `CFBundleURLTypes`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.daccord-projects.daccord</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>daccord</string>
        </array>
    </dict>
</array>
```

On macOS, the OS delivers the URL via an Apple Event, which Godot surfaces through `OS.get_cmdline_args()` when the app launches or via `NOTIFICATION_APPLICATION_FOCUS_IN` when already running. Godot 4's macOS handler puts the URL in the command-line args.

### Security considerations

- **Token in URL:** `daccord://connect/...?token=abc` exposes the auth token in browser history, clipboard, and logs. Document the risk. Consider short-lived tokens or one-time invite codes as the preferred sharing mechanism.
- **Scheme validation:** `UriHandler` must validate the URI strictly -- reject malformed URIs, enforce expected routes, sanitize all string values before passing to `parse_server_url` or API calls.
- **Invite code sanitization:** Invite codes should be alphanumeric only; reject codes with special characters to prevent injection.
- **No auto-connect without consent:** Even with a token in the URL, consider showing a confirmation dialog ("Connect to chat.example.com?") before auto-connecting, to prevent drive-by connections from malicious links.
- **Allowlist consideration:** Optionally, only process URIs for servers the user has previously connected to (for `navigate` and `invite` routes), requiring explicit `connect` for new servers.

### URL generation (sharing)

For completeness, the app should be able to **generate** `daccord://` links:

- **Space context menu:** "Copy Invite Link" → generates `daccord://invite/CODE@host:port`
- **Channel context menu:** "Copy Channel Link" → generates `daccord://navigate/space_id/channel_id` (only useful for users already on the same server)
- **Add Server dialog:** "Copy Connection Link" → generates `daccord://connect/host:port/space-slug`

### Test plan

Extend `tests/unit/test_add_server_dialog.gd` (currently 18 URL parsing tests) and add a new `tests/unit/test_uri_handler.gd`:

- Parse `daccord://connect/host:port/space?token=abc` → correct Dictionary
- Parse `daccord://connect/host` → defaults (port 443, space "general")
- Parse `daccord://invite/CODE@host:port` → correct code + host
- Parse `daccord://invite/CODE@host` → default port
- Parse `daccord://navigate/123/456` → correct space_id + channel_id
- Parse `daccord://navigate/123` → space only, no channel
- Reject `daccord://unknown/...` → null or error
- Reject malformed URIs (`daccord://`, `daccord:///`, `daccord://connect/`)
- Reject URIs with suspicious characters (injection attempts)
- IPC file write/read round-trip
- Pre-fill flow: `open_prefilled()` sets correct text
- Security: token-bearing URIs trigger confirmation dialog

## Implementation Status

- [ ] `daccord://` URL scheme design (documented above)
- [ ] `UriHandler` autoload (new `scripts/autoload/uri_handler.gd`)
- [ ] `--uri` CLI argument parsing in `UriHandler._ready()`
- [ ] URI parser for `connect`, `invite`, `navigate` routes
- [ ] `AddServerDialog.open_prefilled()` method
- [ ] IPC via `user://daccord.uri` file for already-running instances
- [ ] `SingleInstance` extension to write URI before quitting
- [ ] IPC file watcher (Timer-based) in `UriHandler`
- [ ] Windows registry protocol handler in `dist/installer.iss`
- [ ] Linux `.desktop` MimeType + `xdg-mime` registration
- [ ] macOS `CFBundleURLTypes` in Info.plist
- [ ] Confirmation dialog for auto-connect URIs (security)
- [ ] "Copy Invite Link" / "Copy Channel Link" context menu actions
- [ ] Unit tests for URI parsing (`test_uri_handler.gd`)
- [ ] Integration tests for IPC file round-trip
- [ ] Update `test_add_server_dialog.gd` for pre-fill flow

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No `daccord://` scheme exists at all | High | Entire feature is unimplemented; this document is the design spec |
| `parse_server_url()` only handles `http://` and `https://` | Medium | Lines 66-67 of `add_server_dialog.gd`; needs `daccord://` awareness or separate parser |
| `SingleInstance` has no IPC mechanism | High | `single_instance.gd` only detects duplicate instances and quits; cannot forward URIs to running instance |
| CLI arg parsing only supports `--profile` | Medium | `config.gd` lines 40-45; needs `--uri` support in a new or existing autoload |
| No confirmation dialog for URI-triggered connections | Medium | Security risk: malicious `daccord://connect/...?token=...` links could auto-connect without user consent |
| macOS Apple Event handling unclear in Godot 4 | Medium | Godot 4 may or may not surface URL scheme activations via `OS.get_cmdline_args()`; needs testing on macOS |
| No URL generation / sharing UI | Low | Users cannot generate `daccord://` links from within the app yet |
| Linux xdg-mime registration not automated | Low | Needs post-install script or user documentation for `xdg-mime default` |
| Windows uninstall cleanup | Low | `installer.iss` should remove registry keys on uninstall (`Flags: uninsdeletekey` handles this) |
| Token exposure in URLs | Low | Auth tokens in `daccord://connect/...?token=...` may leak via browser history/logs; prefer invite codes |
