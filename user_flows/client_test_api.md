# Client Test API

Priority: 79
Depends on: Test Coverage

## Overview

Daccord embeds a local HTTP API in the running client that allows any external process — test harness, shell script, CI job, or AI agent — to programmatically read state, navigate the UI, perform actions, and capture screenshots. This is the **core layer** that the [Client MCP Server](client_mcp.md) wraps as a protocol adapter. The API itself is a plain JSON-over-HTTP interface with no MCP, JSON-RPC, or AI-specific concepts.

The primary use case is **integration testing of a running app**: a test runner starts Daccord with the test API enabled, issues HTTP calls to drive the client through scenarios, and asserts on the returned state. This replaces fragile input simulation and allows testing the full stack (UI ↔ Client ↔ AccordKit ↔ server) from the outside.

The test API can be enabled two ways:
1. **CLI flag** (`--test-api`) — for CI and automated test runs, no UI interaction needed
2. **Developer Mode** — a checkbox in App Settings that reveals a "Developer" page where the test API (and MCP server) can be toggled on. Disabled by default

## User Steps

### Test harness usage

1. Start Daccord with `--test-api` flag (or `DACCORD_TEST_API=true` env var)
2. Client starts the HTTP listener on `127.0.0.1:39100` (configurable via `--test-api-port`)
3. Test harness sends HTTP requests: `POST http://localhost:39100/api/<endpoint>`
4. Client executes the action and returns a JSON response
5. Test harness asserts on the response body (state values, success/error)
6. Optionally capture a screenshot via `POST /api/screenshot` for visual verification
7. On test completion, the test harness sends `POST /api/quit` or kills the process

### CI integration

1. CI builds and exports Daccord
2. CI starts accordserver in test mode (same as existing `test.sh`)
3. CI starts Daccord with `--test-api --headless` (or windowed for screenshot tests)
4. CI runs a test script (bash/Python/GDScript) that calls the API endpoints
5. Test script exits 0/1 based on assertions
6. CI collects screenshots as artifacts if produced

## Signal Flow

```
Test harness sends HTTP POST /api/select_channel {"channel_id": "456"}
  → ClientTestApi.HttpListener receives request
    → _parse_request(stream)
    → _route_endpoint("select_channel", body)
      → AppState.select_channel("456")
      → await get_tree().process_frame
      → return {"ok": true, "channel_id": "456"}
    → _send_json_response(stream, 200, result)

Test harness sends HTTP POST /api/get_state
  → ClientTestApi._endpoint_get_state()
    → Reads AppState.current_space_id, current_channel_id, is_dm_mode, etc.
    → Reads Client cache counts and connection status
    → return {"space_id": "123", "channel_id": "456", ...}

Test harness sends HTTP POST /api/screenshot
  → ClientTestApi._endpoint_screenshot()
    → await RenderingServer.frame_post_draw
    → viewport.get_texture().get_image()
    → image.save_png_to_buffer()
    → return {"image_base64": "...", "width": 1280, "height": 720}

Startup with --test-api flag:
  Client._ready()
    → _parse_cmdline_args()
    → if test_api_enabled:
      → test_api = ClientTestApi.new(self)
      → test_api.start(port)
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_test_api.gd` | Core test API subsystem — HTTP listener, request routing, 38 endpoint implementations, verbose audit logging |
| `scripts/autoload/client_test_api_navigate.gd` | Navigation endpoint helpers — surface catalog (10 sections), dialog map (30 dialogs), viewport resize |
| `scripts/autoload/client.gd` | Parent client — initializes `test_api = ClientTestApi.new(self)` when `--test-api` flag present (line 242) |
| `scripts/autoload/app_state.gd` | Signal bus — `select_space()` (line 252), `select_channel()` (line 259), `enter_dm_mode()` (line 275), `toggle_member_list()` (line 328), `toggle_search()` (line 336), `open_discovery()` (line 431) |
| `scripts/autoload/config.gd` | Loads `ConfigDeveloper` sub-object via `Config.developer` (line 54) |
| `scripts/autoload/config_developer.gd` | Developer Mode settings in `developer/` config section (developer_mode, test_api_enabled, test_api_port, tokens, MCP) |
| `scripts/autoload/error_reporting.gd` | PII scrubbing — `scrub_pii_text()` covers `dk_` tokens and 64-char hex strings (line 35) |
| `scenes/user/app_settings.gd` | Hosts "Developer" page (visible only when `Config.developer.get_developer_mode()` is true) (line 62) |
| `scenes/user/app_settings_developer_page.gd` | Developer settings page — test API toggle + port + token, MCP toggle + token/port/groups |
| `scenes/user/app_settings_about_page.gd` | About page — Developer Mode toggle in ADVANCED section (line 91) |
| `test.sh` | Updated with `client` test suite that starts Daccord with `--test-api` and runs endpoint tests |
| `tests/client_api/` | Bash test scripts: `test_state_endpoints.sh`, `test_navigation.sh`, `test_lifecycle.sh` |
| `tests/unit/test_client_test_api.gd` | GUT unit tests for request parsing, auth, rate limiting, endpoint routing (25 tests) |
| `.github/workflows/ci.yml` | CI workflow — `integration-test` job runs client API bash tests after AccordKit tests |

## Implementation Details

### Activation

The test API can be enabled via CLI flags (for CI) or via Developer Mode in the settings (for interactive use). Both paths are disabled by default.

#### CLI activation (for CI and automated tests)

```gdscript
# In client.gd _ready(), after existing subsystem initialization:
if _is_test_api_enabled():
    test_api = ClientTestApi.new(self)
    test_api.start(_get_test_api_port())

func _is_test_api_enabled() -> bool:
    # CLI / env override (for CI — no UI interaction needed)
    if OS.has_feature("test_api") \
        or "--test-api" in OS.get_cmdline_args() \
        or OS.get_environment("DACCORD_TEST_API") == "true":
        return true
    # Developer Mode setting (for interactive use)
    return Config.get_developer_mode() and Config.get_test_api_enabled()

func _get_test_api_port() -> int:
    var args: PackedStringArray = OS.get_cmdline_args()
    var idx: int = args.find("--test-api-port")
    if idx >= 0 and idx + 1 < args.size():
        return args[idx + 1].to_int()
    var env: String = OS.get_environment("DACCORD_TEST_API_PORT")
    if not env.is_empty():
        return env.to_int()
    return Config.get_test_api_port()  # default 39100
```

#### Developer Mode activation (for interactive use)

Developer Mode is a checkbox in App Settings that reveals a "Developer" page. The test API toggle lives on that page. See [Developer Mode Settings Page](#developer-mode-settings-page) below.

An optional bearer token can be configured for authentication (enabled by default in Developer Mode, skippable via `--test-api-no-auth` for CI). The test API binds to `127.0.0.1` only and is only active when explicitly enabled. When a token is configured, all requests must include an `Authorization: Bearer <token>` header.

### HTTP Listener (`client_test_api.gd`)

Uses Godot's `TCPServer` + `StreamPeerTCP` to implement a minimal HTTP/1.1 server. No external addons required.

```gdscript
class_name ClientTestApi extends RefCounted

var _c: Node  # Parent Client reference
var _server: TCPServer
var _port: int = 39100
var _navigate: ClientTestApiNavigate

func _init(client_node: Node) -> void:
    _c = client_node
    _navigate = ClientTestApiNavigate.new(client_node)

func start(
    port: int = 39100, token: String = "",
    require_auth: bool = false, verbose: bool = false,
) -> bool:
    _port = port
    _auth_token = token
    _require_auth = require_auth
    _verbose = verbose
    _server = TCPServer.new()
    var err: int = _server.listen(_port, LOOPBACK_ADDR)
    if err != OK:
        push_error("ClientTestApi: Failed to listen on port %d: %s" % [_port, error_string(err)])
        return false
    # Verify loopback binding
    if not _server.is_listening():
        push_warning("ClientTestApi: loopback binding may have failed silently")
        return false
    print("ClientTestApi: Listening on %s:%d" % [LOOPBACK_ADDR, _port])
    return true

func stop() -> void:
    if _server != null:
        _server.stop()
        _server = null

func poll() -> void:
    if _server == null or not _server.is_listening():
        return
    if _server.is_connection_available():
        var peer: StreamPeerTCP = _server.take_connection()
        _handle_connection(peer)
```

The `poll()` method is called from Client's `_process()` loop (same pattern as other subsystems that need per-frame work).

#### Request Parsing

Parses a minimal HTTP/1.1 POST request — enough for test tooling, not a general-purpose server:

```gdscript
func _handle_connection(peer: StreamPeerTCP) -> void:
    peer.set_no_delay(true)
    # Read request line + headers
    var request_data: String = ""
    var content_length: int = 0
    # ... parse headers, extract Content-Length ...

    # Read JSON body
    var body: String = peer.get_utf8_string(content_length)
    var json: Dictionary = JSON.parse_string(body) if not body.is_empty() else {}

    # Route to endpoint
    var path: String = _extract_path(request_data)  # e.g., "/api/select_channel"
    var endpoint: String = path.trim_prefix("/api/")
    var result: Dictionary = await _route(endpoint, json)

    # Send response
    _send_response(peer, 200, result)
    peer.disconnect_from_host()
```

#### Endpoint Routing

Flat dispatch table mapping endpoint names to methods:

```gdscript
var _endpoints: Dictionary = {
    # State
    "get_state": _endpoint_get_state,
    "list_spaces": _endpoint_list_spaces,
    "get_space": _endpoint_get_space,
    "list_channels": _endpoint_list_channels,
    "list_members": _endpoint_list_members,
    "list_messages": _endpoint_list_messages,
    "search_messages": _endpoint_search_messages,
    "get_user": _endpoint_get_user,

    # Navigation
    "select_space": _endpoint_select_space,
    "select_channel": _endpoint_select_channel,
    "open_dm": _endpoint_open_dm,
    "open_settings": _endpoint_open_settings,
    "open_discovery": _endpoint_open_discovery,
    "open_thread": _endpoint_open_thread,
    "open_voice_view": _endpoint_open_voice_view,
    "toggle_member_list": _endpoint_toggle_member_list,
    "toggle_search": _endpoint_toggle_search,
    "navigate_to_surface": _endpoint_navigate_to_surface,
    "open_dialog": _endpoint_open_dialog,
    "set_viewport_size": _endpoint_set_viewport_size,

    # Screenshot
    "screenshot": _endpoint_screenshot,
    "list_surfaces": _endpoint_list_surfaces,
    "get_surface_info": _endpoint_get_surface_info,

    # Actions
    "send_message": _endpoint_send_message,
    "edit_message": _endpoint_edit_message,
    "delete_message": _endpoint_delete_message,
    "add_reaction": _endpoint_add_reaction,

    # Moderation
    "kick_member": _endpoint_kick_member,
    "ban_user": _endpoint_ban_user,
    "unban_user": _endpoint_unban_user,
    "timeout_member": _endpoint_timeout_member,

    # Voice
    "join_voice": _endpoint_join_voice,
    "leave_voice": _endpoint_leave_voice,
    "toggle_mute": _endpoint_toggle_mute,
    "toggle_deafen": _endpoint_toggle_deafen,

    # Lifecycle
    "wait_frames": _endpoint_wait_frames,
    "quit": _endpoint_quit,
}

func _route(endpoint: String, args: Dictionary) -> Dictionary:
    var handler: Callable = _endpoints.get(endpoint, Callable())
    if not handler.is_valid():
        return {"error": "Unknown endpoint: %s" % endpoint, "available": _endpoints.keys()}
    return await handler.call(args)
```

### Endpoint Groups

#### State Endpoints

Read-only queries against Client's in-memory caches. No API calls — instant responses.

| Endpoint | Parameters | Returns | Source |
|----------|-----------|---------|--------|
| `get_state` | — | Current space/channel/DM/voice/layout state | `AppState` state vars (lines 212-235) |
| `list_spaces` | — | All spaces the user is in | `Client._space_cache` (line 98) |
| `get_space` | `space_id` | Single space data | `Client._space_cache[space_id]` |
| `list_channels` | `space_id` | Channels for a space | `Client._channel_cache` filtered |
| `list_members` | `space_id` | Members of a space | `Client._member_cache[space_id]` (line 102) |
| `list_messages` | `channel_id`, `limit?` | Recent messages in a channel | `Client._message_cache[channel_id]` (line 101) |
| `search_messages` | `query`, `channel_id?`, `space_id?` | Search results | Via `Client.fetch` → AccordKit REST |
| `get_user` | `user_id` | User data | `Client._user_cache[user_id]` (line 97) |

Example `get_state` response:

```json
{
  "space_id": "123",
  "channel_id": "456",
  "is_dm_mode": false,
  "layout_mode": "FULL",
  "viewport_size": {"width": 1280, "height": 720},
  "member_list_visible": true,
  "search_open": false,
  "thread_open": false,
  "thread_id": "",
  "discovery_open": false,
  "voice_channel_id": "",
  "voice_view_open": false,
  "connected_servers": 2,
  "space_count": 5,
  "user_id": "789",
  "username": "testuser"
}
```

#### Navigation Endpoints

Drive the UI by calling AppState methods. Each waits one frame for the scene tree to settle before responding.

| Endpoint | Parameters | AppState Method | Effect |
|----------|-----------|----------------|--------|
| `select_space` | `space_id` | `select_space()` (line 248) | Switches to a space |
| `select_channel` | `channel_id` | `select_channel()` (line 255) | Switches to a channel |
| `open_dm` | `user_id?` | `enter_dm_mode()` (line 271) | Enters DM mode |
| `open_settings` | `page?` | Instantiates `app_settings.tscn` | Opens settings dialog |
| `open_discovery` | — | `open_discovery()` (line 427) | Opens discovery panel |
| `open_thread` | `message_id` | `thread_opened.emit()` (line 129) | Opens thread panel |
| `open_voice_view` | — | `open_voice_view()` (line 379) | Opens voice video grid |
| `toggle_member_list` | — | `toggle_member_list()` (line 324) | Shows/hides member list |
| `toggle_search` | — | `toggle_search()` (line 332) | Shows/hides search panel |
| `navigate_to_surface` | `surface_id`, `state?` | Compound (see client_test_api_navigate.gd) | Navigates to a UI audit surface |
| `open_dialog` | `dialog_name`, `args?` | Instantiate from dialog map | Opens a named dialog |
| `set_viewport_size` | `width`, `height?` or `preset` | `DisplayServer.window_set_size()` | Resizes for responsive testing |

```gdscript
func _endpoint_select_channel(args: Dictionary) -> Dictionary:
    var channel_id: String = args.get("channel_id", "")
    if channel_id.is_empty():
        return {"error": "channel_id is required"}
    var space_id: String = _c._channel_to_space.get(channel_id, "")
    if space_id.is_empty():
        return {"error": "Channel not found: %s" % channel_id}
    AppState.select_channel(channel_id)
    await _c.get_tree().process_frame
    return {"ok": true, "channel_id": channel_id, "space_id": space_id}
```

#### Screenshot Endpoints

| Endpoint | Parameters | Returns |
|----------|-----------|---------|
| `screenshot` | `x?`, `y?`, `width?`, `height?`, `save_path?` | `{"image_base64": "...", "width": N, "height": N}` |
| `list_surfaces` | `section?` | Array of surface catalog entries |
| `get_surface_info` | `surface_id` | Single surface entry with navigation prereqs |

#### Action Endpoints

Perform user actions. These call through Client subsystems to AccordKit REST.

| Endpoint | Parameters | Client Method |
|----------|-----------|--------------|
| `send_message` | `channel_id`, `content` | `Client.mutations.send_message()` |
| `edit_message` | `channel_id`, `message_id`, `content` | `Client.mutations.edit_message()` |
| `delete_message` | `channel_id`, `message_id` | `Client.mutations.delete_message()` |
| `add_reaction` | `channel_id`, `message_id`, `emoji` | `Client.mutations.add_reaction()` |
| `kick_member` | `space_id`, `user_id` | `Client.admin.kick_member()` |
| `ban_user` | `space_id`, `user_id`, `reason?` | `Client.admin.ban_user()` |
| `unban_user` | `space_id`, `user_id` | `Client.admin.unban_user()` |
| `timeout_member` | `space_id`, `user_id`, `duration` | `Client.admin.timeout_member()` |

#### Voice Endpoints

| Endpoint | Parameters | Effect |
|----------|-----------|--------|
| `join_voice` | `channel_id` | `Client.voice.join()` |
| `leave_voice` | — | `Client.voice.leave()` |
| `toggle_mute` | — | `Client.voice.toggle_mute()` |
| `toggle_deafen` | — | `Client.voice.toggle_deafen()` |

#### Lifecycle Endpoints

| Endpoint | Parameters | Effect |
|----------|-----------|--------|
| `wait_frames` | `count` (default 1) | Waits N process frames, returns when settled — useful for animations/transitions |
| `quit` | — | Calls `_c.get_tree().quit()` to cleanly exit |

### Navigation Helpers (`client_test_api_navigate.gd`)

Extracted to a separate file because the surface catalog and dialog map are large. Same data as described in [Client MCP Server](client_mcp.md) — the MCP layer delegates to the same navigate helper.

```gdscript
class_name ClientTestApiNavigate extends RefCounted

var _c: Node

func _init(client_node: Node) -> void:
    _c = client_node

# Surface catalog: maps ui_audit.md surface IDs to navigation callables
var _catalog: Dictionary = { ... }  # 121 entries from ui_audit.md

# Dialog map: name → scene path
const DIALOG_MAP: Dictionary = { ... }  # 30+ dialogs

func navigate_to_surface(surface_id: String, state: String = "default") -> Dictionary:
    ...

func open_dialog(dialog_name: String, args: Dictionary = {}) -> Dictionary:
    ...

func set_viewport_size(args: Dictionary) -> Dictionary:
    ...
```

### HTTP Response Format

All responses are JSON with a consistent shape:

**Success:**
```json
{"ok": true, "channel_id": "456", ...}
```

**Error:**
```json
{"error": "Channel not found: 999", "code": "NOT_FOUND"}
```

**Screenshot (binary data):**
```json
{
  "image_base64": "<base64 PNG>",
  "width": 1280,
  "height": 720,
  "format": "png",
  "size_bytes": 45231
}
```

HTTP status codes: `200` for success, `400` for bad request, `404` for unknown endpoint, `500` for internal error.

### Test Runner Integration (`test.sh`)

A new `client` suite is added to `test.sh`:

```bash
./test.sh client         # Client API integration tests
```

This suite:
1. Builds and starts accordserver in test mode (same as `integration`)
2. Starts Daccord with `--test-api --headless` (or windowed if `DACCORD_SCREENSHOTS=true`)
3. Waits for `http://localhost:39100/api/get_state` to return 200
4. Runs test scripts from `tests/client_api/`
5. Collects exit code and any screenshot artifacts
6. Kills Daccord and accordserver

### Example Test Script

A bash test that verifies channel navigation and message state:

```bash
#!/bin/bash
API="http://localhost:39100/api"

# Wait for connection
for i in $(seq 1 30); do
  STATE=$(curl -sf "$API/get_state") && break
  sleep 1
done

# Select a space
SPACES=$(curl -sf "$API/list_spaces")
SPACE_ID=$(echo "$SPACES" | jq -r '.spaces[0].id')
curl -sf "$API/select_space" -d "{\"space_id\": \"$SPACE_ID\"}"

# Select first channel
CHANNELS=$(curl -sf "$API/list_channels" -d "{\"space_id\": \"$SPACE_ID\"}")
CHANNEL_ID=$(echo "$CHANNELS" | jq -r '.channels[0].id')
RESULT=$(curl -sf "$API/select_channel" -d "{\"channel_id\": \"$CHANNEL_ID\"}")

# Assert channel was selected
echo "$RESULT" | jq -e '.ok == true' || exit 1

# Verify state
STATE=$(curl -sf "$API/get_state")
echo "$STATE" | jq -e ".channel_id == \"$CHANNEL_ID\"" || exit 1

# Send a message and verify it appears
curl -sf "$API/send_message" -d "{\"channel_id\": \"$CHANNEL_ID\", \"content\": \"test message\"}"
sleep 0.5  # wait for gateway round-trip

MESSAGES=$(curl -sf "$API/list_messages" -d "{\"channel_id\": \"$CHANNEL_ID\", \"limit\": 1}")
echo "$MESSAGES" | jq -e '.messages[-1].content == "test message"' || exit 1

# Screenshot for visual verification
curl -sf "$API/screenshot" -d '{"save_path": "user://test_screenshots/channel_view.png"}'

echo "PASS"
```

### Config Storage (`config.gd`)

New `developer/` section in the per-profile encrypted config (shared with MCP server):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `developer/enabled` | bool | `false` | Master Developer Mode switch — gates the Developer settings page and subsystem initialization |
| `developer/test_api_enabled` | bool | `false` | Enable the plain HTTP test API |
| `developer/test_api_port` | int | `39100` | Test API listen port |
| `developer/test_api_token` | String | `""` | Bearer token for test API auth (256-bit random, hex-encoded). Empty = generate on first enable |
| `developer/mcp_enabled` | bool | `false` | Enable the MCP server (see [Client MCP Server](client_mcp.md)) |
| `developer/mcp_token` | String | `""` | MCP bearer token |
| `developer/mcp_port` | int | `39101` | MCP listen port |
| `developer/mcp_allowed_groups` | PackedStringArray | `["read","navigate","screenshot"]` | MCP tool groups |

CLI flags (`--test-api`, `--test-api-port`) bypass the config and enable the test API directly without requiring Developer Mode.

### Developer Mode Settings Page

Added to `app_settings.gd:_get_sections()` as "Developer" — only visible when Developer Mode is enabled. The Developer Mode toggle itself lives at the bottom of the existing "About" page (or a similar discoverable location) so users can find it.

**Page layout (`app_settings_developer_page.gd`):**

1. **Header** — "Developer Tools" with description: "Tools for testing and AI integration. These bind to localhost only."
2. **Test API Section**
   - CheckButton "Enable Test API" — toggles the plain HTTP endpoint
   - Status label: "Listening on 127.0.0.1:39100" or "Stopped"
   - Port SpinBox (range 1024–65535, default 39100)
   - Info label: "No authentication required. For local testing only."
3. **MCP Server Section** — see [Client MCP Server](client_mcp.md) for details
   - CheckButton "Enable MCP Server"
   - Token display/copy/rotate
   - Port SpinBox (default 39101)
   - Tool group checkboxes
4. **CLI Override Notice** — Info label: "These can also be enabled via `--test-api` and `--test-api-port` flags for CI use."

### Relationship to MCP Layer

The test API provides the raw HTTP endpoints. The MCP server (`client_mcp.gd`) wraps these same endpoints in the MCP protocol (JSON-RPC 2.0, `tools/list`, `tools/call`, bearer token auth):

```
┌──────────────────────────────────────────────────────┐
│  Test harness        │  AI agent (Claude, etc.)      │
│  (bash, Python, CI)  │                               │
└──────┬───────────────┴──────────┬────────────────────┘
       │ POST /api/<endpoint>     │ POST /mcp (JSON-RPC)
       │                          │ + Bearer token
       ▼                          ▼
┌──────────────────┐    ┌──────────────────┐
│ ClientTestApi    │    │ ClientMcp        │
│ (port 39100)     │    │ (port 39101)     │
│ Plain HTTP/JSON  │    │ MCP protocol     │
└──────┬───────────┘    └──────┬───────────┘
       │                       │
       ▼                       ▼
┌──────────────────────────────────────────┐
│ Shared endpoint implementations          │
│ (AppState signals, Client caches,        │
│  Client.mutations, Client.admin, etc.)   │
└──────────────────────────────────────────┘
```

Both subsystems call the same underlying AppState/Client methods. The MCP layer adds:
- Bearer token authentication
- JSON-RPC 2.0 framing
- Tool group permissions (read/navigate/screenshot/message/moderate/voice)
- MCP protocol methods (`initialize`, `tools/list`, `tools/call`)
- Settings page UI for enable/disable/token management

The test API omits all of that — it's just endpoints and responses.

### Security Model

| Concern | Mitigation |
|---------|------------|
| Only active when requested | Requires `--test-api` flag or `DACCORD_TEST_API=true` — never auto-enabled |
| Localhost only | Binds to `127.0.0.1`, refuses non-loopback connections |
| Authentication | Optional bearer token (enabled by default in Developer Mode, skippable via `--test-api-no-auth` for CI). Token is 256-bit random, stored in encrypted config, rotatable from Developer settings |
| Token timing attacks | Constant-time comparison prevents timing side-channels |
| Request size limits | `Content-Length` capped at 1 MB; missing/invalid headers rejected |
| Read timeout | 5-second timeout per connection prevents slowloris-style poll loop blocking |
| Rate limiting | Token-bucket limiter (60 req/s burst) prevents client degradation from runaway scripts |
| Error information leakage | Error responses never include token values, config paths, endpoint lists, or internal file paths |
| Token in error reporting | PII scrubbing regex in `error_reporting.gd` covers test API and MCP token patterns |
| No persistent config (CLI mode) | `--test-api` flag is ephemeral — no risk of accidentally leaving it enabled |
| Production builds | Can be compile-time excluded via `OS.has_feature("release")` guard or Godot feature tags |
| Connection limits | Max 4 concurrent pending connections to mitigate local DoS |

## Implementation Status

- [x] Developer Mode config storage (`config_developer.gd` + `Config.developer` sub-object)
- [x] Developer Mode settings page (`app_settings_developer_page.gd`)
- [x] Developer Mode toggle on About page (`app_settings_about_page.gd` — ADVANCED section)
- [x] `ClientTestApi` subsystem with TCP listener and request parsing
- [x] Endpoint routing and response formatting
- [x] State endpoints (8 endpoints: `get_state`, `list_spaces`, etc.)
- [x] Navigation endpoints — basic (5: `select_space`, `select_channel`, `open_dm`, `open_settings`, `open_discovery`)
- [x] Navigation endpoints — extended (7: `open_thread`, `open_voice_view`, `toggle_member_list`, `toggle_search`, `set_viewport_size`, `navigate_to_surface`, `open_dialog`)
- [x] Screenshot endpoints (3: `screenshot`, `list_surfaces`, `get_surface_info`)
- [x] Action endpoints (4: `send_message`, `edit_message`, `delete_message`, `add_reaction`)
- [x] Moderation endpoints (4: `kick_member`, `ban_user`, `unban_user`, `timeout_member`)
- [x] Voice endpoints (4: `join_voice`, `leave_voice`, `toggle_mute`, `toggle_deafen`)
- [x] Lifecycle endpoints (`wait_frames`, `quit`)
- [x] Navigation helpers (`client_test_api_navigate.gd`) with surface catalog and dialog map (30 dialogs, 10 surface sections)
- [x] CLI flag parsing (`--test-api`, `--test-api-port`, `--test-api-no-auth`, env vars)
- [x] `test.sh` updated with `client` suite
- [x] Example bash test scripts in `tests/client_api/` (3 scripts: state, navigation, lifecycle)
- [x] Unit tests for request parsing and endpoint routing (`tests/unit/test_client_test_api.gd` — 25 tests covering validation, headers, auth, rate limiting, routing, start/stop)
- [x] CI integration — client API bash tests run in the `integration-test` job after AccordKit tests (`.github/workflows/ci.yml`)

### Security

- [x] Optional bearer token authentication for test API (token stored in encrypted config `developer/test_api_token`)
- [x] Constant-time token comparison to prevent timing attacks (byte-by-byte XOR in `_constant_time_compare()`)
- [x] Token generation — 256-bit random via `Crypto.generate_random_bytes(32)`, hex-encoded, rotatable from Developer settings page (`_generate_token()` in `app_settings_developer_page.gd`)
- [x] Request read timeout — 5-second timeout per connection (`READ_TIMEOUT_MS`) prevents poll loop blocking
- [x] Rate limiting — 60 req/s burst via timestamp-based window (`_is_rate_limited()`)
- [x] Validate `Content-Length` header — reject negative or >1 MB values with 413
- [x] Method validation — reject non-POST HTTP methods with 405 Method Not Allowed
- [x] Path validation — reject paths outside `/api/` prefix with 404 instead of leaking endpoint list
- [x] JSON parse error handling — return 400 with generic error message, do not echo malformed input back
- [x] Scrub tokens from error reporting — `error_reporting.gd` PII regex covers `dk_` prefixed tokens and bare 64-char hex strings
- [x] Verify loopback binding — `start()` checks `_server.is_listening()` after bind, warns if binding fails silently (line 58)
- [x] Compile-time exclusion — `_is_test_api_enabled()` in `client.gd` returns `false` when `OS.has_feature("release")` is set (line 296)
- [x] Token display masking — Developer settings page shows `dk_a1b2...f9e8` (first 4 + last 4 chars), full token only on explicit copy action
- [x] Endpoint audit logging — `--test-api-verbose` flag logs endpoint name, HTTP status, and elapsed time per request (line 93 in `client_test_api.gd`); never logs request bodies
- [x] Connection limit — cap concurrent pending connections (4) to mitigate local DoS from misbehaving test scripts
- [x] No credential echo — error responses never include token values, config paths, or internal file paths

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~Godot has no built-in HTTP server~~ | ~~High~~ | **Resolved.** Implemented minimal HTTP/1.1 parser over `TCPServer` + `StreamPeerTCP` in `client_test_api.gd` |
| ~~Async endpoint handling~~ | ~~High~~ | **Resolved.** Endpoint handlers use `await` naturally; response sent after await completes in `_handle_connection` |
| ~~No authentication on test API~~ | ~~High~~ | **Resolved.** Optional bearer token auth with constant-time comparison; `--test-api-no-auth` flag for CI |
| ~~No request body size limit~~ | ~~High~~ | **Resolved.** Content-Length capped at 1 MB, rejected with 413 |
| ~~No read timeout on connections~~ | ~~High~~ | **Resolved.** 5-second read timeout per connection |
| Token stored with deterministic encryption key | Medium | Config encryption key is `_SALT` only (`config.gd:246`). Anyone with filesystem access + the app binary can derive the key and read `developer/test_api_token`. Improving this requires platform-specific keychain integration (libsecret on Linux, Credential Manager on Windows, Keychain on macOS) |
| Headless screenshot support | Medium | `--headless` mode may not render a viewport. Screenshot tests may need `--test-api` without `--headless`, or use Godot's `--rendering-driver opengl3` with a virtual framebuffer (Xvfb on CI) |
| Concurrent requests | Medium | Single-threaded poll loop handles one request at a time. Sufficient for sequential test scripts. If parallel requests are needed, queue them |
| Web export incompatibility | Medium | `TCPServer` is unavailable in HTML5 exports. Web builds would need `JavaScriptBridge` interop or test API disabled |
| ~~Surface catalog size~~ | ~~Medium~~ | **Resolved.** `client_test_api_navigate.gd` uses a section-based dispatch (10 sections) with per-section handlers, keeping the file under 350 lines |
| Dialog state variants | Medium | States like "loading", "error" require specific server responses. May need a `set_mock_state` endpoint for injecting test conditions |
| ~~Rate limiting not implemented~~ | ~~Medium~~ | **Resolved.** 60 req/s burst window via `_is_rate_limited()` |
| ~~Endpoint responses may leak internal state~~ | ~~Medium~~ | **Resolved.** Unknown endpoints return generic 404 with endpoint name only, no key listing |
| Screenshot data exposure | Medium | `screenshot` endpoint returns full viewport as base64 PNG — may contain private messages, DMs, or credentials visible on screen. Consider requiring explicit opt-in per session or restricting to `read` + `screenshot` tool group |
| ~~No request logging~~ | ~~Low~~ | **Resolved.** `--test-api-verbose` flag logs endpoint, status code, and elapsed time per request |
| Android localhost restrictions | Low | Android may restrict localhost server sockets. Needs testing |
| No CORS headers | Low | If the test API is ever accessed from a browser context (e.g., web-based test dashboard), missing CORS headers would block requests. Low priority since primary consumers are CLI tools |
