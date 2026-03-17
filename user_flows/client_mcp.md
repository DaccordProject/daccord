# Client MCP Server

Depends on: Client Test API

## Overview

Daccord exposes a local MCP (Model Context Protocol) server that lets authenticated AI agents control the client — reading state, navigating channels, sending messages, managing spaces, navigating to specific UI surfaces, and capturing screenshots. The MCP server is a **protocol adapter** that wraps the [Client Test API](client_test_api.md) with JSON-RPC 2.0 framing, bearer token authentication, and tool group permissions conforming to the MCP specification.

Both the test API and MCP server are gated behind a **Developer Mode** toggle in App Settings. Developer Mode is disabled by default; enabling it reveals the "Developer" settings page where users can independently enable the test API (plain HTTP) and/or the MCP server (authenticated JSON-RPC). See [Client Test API — Developer Mode](client_test_api.md#developer-mode-settings-page) for the shared settings page design.

The `navigate` and `screenshot` tool groups together enable automated UI auditing: an AI agent can systematically walk through every dialog, panel, and view in the client (cataloged in [UI Audit](ui_audit.md)), capture screenshots at each state, and analyze them for design/UX issues — all without manual interaction.

## User Steps

1. Open App Settings → "Developer" page (visible only when Developer Mode is enabled)
2. Enable Developer Mode checkbox (off by default)
3. Toggle "Enable MCP Server" (off by default, requires Developer Mode)
4. A random bearer token is generated and displayed once; user copies it to their AI tool config
5. Optionally restrict which tool groups are available (read-only, moderation, messaging, navigation, screenshot)
6. Optionally change the MCP listen port (default: 39101)
7. AI agent connects to `http://localhost:<port>/mcp` with the bearer token
8. AI agent calls MCP tools; ClientMcp translates to test API endpoint calls on the user's behalf
9. User can revoke/rotate the token or disable the server at any time

### Automated UI Audit Workflow

1. AI agent calls `list_surfaces` to get the full catalog of 121 UI surfaces
2. Agent calls `navigate_to_surface` with a surface ID (e.g., `"6.2"`) to navigate to that view
3. Agent calls `take_screenshot` to capture the current viewport as a base64-encoded PNG
4. Agent optionally calls `set_viewport_size` to test responsive breakpoints (COMPACT/MEDIUM/FULL)
5. Agent repeats for each surface × breakpoint combination
6. Agent analyzes screenshots for visual consistency, spacing, accessibility issues

## Signal Flow

```
User enables Developer Mode in settings
  → Config.set_developer_mode(true)
    → Config._save()
    → AppState.config_changed.emit("developer", "enabled")
      → App Settings reveals "Developer" page

User toggles MCP on/off in Developer settings
  → Config.set_mcp_enabled(true/false)
    → Config._save()
    → AppState.config_changed.emit("mcp", "enabled")
      → ClientMcp receives signal
        → starts/stops HTTP listener on port 39101

AI agent sends JSON-RPC request
  → ClientMcp.HttpListener receives POST /mcp
    → _validate_token(request)
    → _dispatch_method(json_rpc)
      → tools/list → return tool definitions (filtered by allowed_groups)
      → tools/call → translate to ClientTestApi endpoint call
        → ClientTestApi._route(endpoint, args)
          → Client.fetch / Client.mutations / Client.admin / AppState signals
        → Wrap result in MCP content format
      → JSON-RPC response sent back

User rotates token
  → Config.set_mcp_token(new_token)
    → AppState.config_changed.emit("mcp", "token")
      → ClientMcp invalidates old token immediately
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_mcp.gd` | MCP protocol adapter — HTTP listener on port 39101, JSON-RPC 2.0 dispatch, bearer token auth, tool group filtering, MCP content wrapping. Delegates actual work to `ClientTestApi` |
| `scripts/autoload/client_test_api.gd` | Core endpoint implementations — see [Client Test API](client_test_api.md). MCP tools map 1:1 to test API endpoints |
| `scripts/autoload/client_test_api_navigate.gd` | Shared navigation helpers — surface catalog, dialog map, viewport resize |
| `scripts/autoload/client.gd` | Parent client — initializes `mcp` subsystem when Developer Mode + MCP enabled (line 256), polls in `_process` (line 271), stops on shutdown (line 293) |
| `scripts/autoload/config.gd` | Loads `ConfigDeveloper` sub-object via `Config.developer` (line 54) |
| `scripts/autoload/config_developer.gd` | Developer Mode and MCP settings in `developer/` config section (developer_mode, test_api_enabled, mcp_enabled, mcp_token, ports, allowed_groups) |
| `scripts/autoload/app_state.gd` | Signal bus — `config_changed` (line 173), `settings_opened` (line 195), plus navigation signals used by MCP tools |
| `scenes/user/app_settings.gd` | Hosts "Developer" page (visible only when `Config.developer.get_developer_mode()` is true) (line 62) |
| `scenes/user/app_settings_developer_page.gd` | Developer settings page — test API toggle, MCP toggle + token/port/groups, tool group checkboxes |
| `tests/unit/test_client_mcp.gd` | Unit tests for tool registration, group filtering, JSON-RPC dispatch, MCP content wrapping, auth, rate limiting (40+ tests) |
| `user_flows/ui_audit.md` | Reference — canonical list of 121 surfaces with scene paths and states to capture |
| `../accordserver-mcp/src/client-mcp.ts` | TypeScript MCP client library for connecting to daccord's client MCP server — `DaccordClientMCPClient` class with typed methods for all 35 tools |
| `../accordserver-mcp/src/client-cli.ts` | Interactive CLI for the client MCP — `daccord-mcp` binary with commands for all 6 tool groups |
| `../accordserver-mcp/client-tools.json` | JSON Schema definitions for all 35 client MCP tools organized by group |
| `../accordserver-mcp/mcp.json` | AI tool configuration for both server (`accord`) and client (`daccord`) MCP endpoints |

## Implementation Details

### Architecture — MCP as Protocol Adapter

The MCP server does **not** implement endpoint logic. It translates MCP protocol calls to `ClientTestApi` endpoint calls:

```
┌─────────────────────────────────┐
│  AI agent (Claude, etc.)        │
│  POST /mcp + Bearer token       │
└──────────┬──────────────────────┘
           │ JSON-RPC 2.0
           ▼
┌─────────────────────────────────┐
│  ClientMcp (port 39101)         │
│  - Bearer token validation      │
│  - JSON-RPC framing             │
│  - Tool group permission filter │
│  - MCP content type wrapping    │
└──────────┬──────────────────────┘
           │ Direct method call
           ▼
┌─────────────────────────────────┐
│  ClientTestApi (port 39100)     │
│  - Endpoint implementations     │
│  - AppState / Client calls      │
│  - Screenshot capture           │
│  - Navigation helpers           │
└─────────────────────────────────┘
```

`ClientMcp` holds a reference to `ClientTestApi` and calls its endpoint methods directly (not via HTTP). The test API's own HTTP listener is independent — both can run simultaneously on different ports, or the test API can run alone without MCP.

### Config Storage (`config.gd`)

New `developer/` section in the per-profile encrypted config:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `developer/enabled` | bool | `false` | Master Developer Mode switch — gates visibility of developer settings and subsystem initialization |
| `developer/test_api_enabled` | bool | `false` | Enable the plain HTTP test API (no auth) |
| `developer/test_api_port` | int | `39100` | Test API listen port |
| `developer/mcp_enabled` | bool | `false` | Enable the MCP server (authenticated) |
| `developer/mcp_token` | String | `""` | MCP bearer token (generated client-side, never sent to server) |
| `developer/mcp_port` | int | `39101` | MCP listen port |
| `developer/mcp_allowed_groups` | PackedStringArray | `["read","navigate","screenshot"]` | Tool groups the AI may use |

Getter/setter pairs following the existing pattern (like `config_voice.gd`):

```gdscript
func get_developer_mode() -> bool:
    return _config.get_value("developer", "enabled", false)

func set_developer_mode(enabled: bool) -> void:
    _config.set_value("developer", "enabled", enabled)
    _save()
    AppState.config_changed.emit("developer", "enabled")

func get_mcp_enabled() -> bool:
    return _config.get_value("developer", "mcp_enabled", false)

func set_mcp_enabled(enabled: bool) -> void:
    _config.set_value("developer", "mcp_enabled", enabled)
    _save()
    AppState.config_changed.emit("mcp", "enabled")
```

Token is generated via `Crypto.new().generate_random_bytes(32)` encoded as hex — never leaves the device. Stored encrypted alongside other profile credentials.

### Client Subsystem (`client_mcp.gd`)

Follows the existing subsystem pattern (like `client_plugins.gd`). Depends on `ClientTestApi` being initialized first:

```gdscript
class_name ClientMcp extends RefCounted

var _c: Node  # Parent Client reference
var _test_api: ClientTestApi  # Underlying endpoint implementations
var _server: TCPServer
var _token: String
var _enabled: bool = false
var _port: int = 39101
var _allowed_groups: PackedStringArray = ["read", "navigate", "screenshot"]

func _init(client_node: Node, test_api: ClientTestApi) -> void:
    _c = client_node
    _test_api = test_api
    AppState.config_changed.connect(_on_config_changed)
    _load_config()
```

#### HTTP Listener

Uses Godot's `TCPServer` + `StreamPeerTCP` to accept connections, same approach as the test API but on a separate port.

- Binds to `127.0.0.1` only (localhost — never exposed to network)
- Processes requests in `_process()` tick (registered via Client's process loop)
- Validates `Authorization: Bearer <token>` header with constant-time comparison
- Responds with JSON-RPC 2.0 conforming to MCP protocol version `2025-03-26`

#### JSON-RPC Dispatch

Implements three MCP methods:

1. **`initialize`** — Returns server info, protocol version, capabilities
2. **`tools/list`** — Returns available tools filtered by `_allowed_groups`
3. **`tools/call`** — Maps tool name to test API endpoint, executes, wraps result in MCP content format

```gdscript
func _handle_tools_call(tool_name: String, args: Dictionary) -> Dictionary:
    # Check tool group permissions
    var group: String = _tool_to_group.get(tool_name, "")
    if group.is_empty():
        return _jsonrpc_error(-32601, "Unknown tool: %s" % tool_name)
    if group not in _allowed_groups:
        return _jsonrpc_error(-32600, "Tool group '%s' is not enabled" % group)

    # Delegate to test API
    var endpoint: String = _tool_to_endpoint.get(tool_name, tool_name)
    var result: Dictionary = await _test_api._route(endpoint, args)

    # Wrap in MCP content format
    return _wrap_mcp_result(tool_name, result)
```

#### Tool-to-Endpoint Mapping

MCP tool names map directly to test API endpoint names. The MCP layer only adds group-based filtering:

| MCP Tool Name | Test API Endpoint | Group |
|---------------|------------------|-------|
| `get_current_state` | `get_state` | `read` |
| `list_spaces` | `list_spaces` | `read` |
| `list_channels` | `list_channels` | `read` |
| `list_members` | `list_members` | `read` |
| `list_messages` | `list_messages` | `read` |
| `search_messages` | `search_messages` | `read` |
| `get_user` | `get_user` | `read` |
| `get_space` | `get_space` | `read` |
| `select_space` | `select_space` | `navigate` |
| `select_channel` | `select_channel` | `navigate` |
| `open_dm` | `open_dm` | `navigate` |
| `open_settings` | `open_settings` | `navigate` |
| `open_discovery` | `open_discovery` | `navigate` |
| `open_thread` | `open_thread` | `navigate` |
| `open_voice_view` | `open_voice_view` | `navigate` |
| `toggle_member_list` | `toggle_member_list` | `navigate` |
| `toggle_search` | `toggle_search` | `navigate` |
| `navigate_to_surface` | `navigate_to_surface` | `navigate` |
| `open_dialog` | `open_dialog` | `navigate` |
| `set_viewport_size` | `set_viewport_size` | `navigate` |
| `take_screenshot` | `screenshot` | `screenshot` |
| `list_surfaces` | `list_surfaces` | `screenshot` |
| `get_surface_info` | `get_surface_info` | `screenshot` |
| `send_message` | `send_message` | `message` |
| `edit_message` | `edit_message` | `message` |
| `delete_message` | `delete_message` | `message` |
| `add_reaction` | `add_reaction` | `message` |
| `kick_member` | `kick_member` | `moderate` |
| `ban_user` | `ban_user` | `moderate` |
| `unban_user` | `unban_user` | `moderate` |
| `timeout_member` | `timeout_member` | `moderate` |
| `join_voice_channel` | `join_voice` | `voice` |
| `leave_voice` | `leave_voice` | `voice` |
| `toggle_mute` | `toggle_mute` | `voice` |
| `toggle_deafen` | `toggle_deafen` | `voice` |

Tools in the `read`, `navigate`, and `screenshot` groups are enabled by default. Destructive groups (`message`, `moderate`, `voice`) require explicit opt-in via the Developer settings page.

#### MCP Content Wrapping

The MCP layer wraps test API responses in MCP-spec content types. Most responses become `text` content. Screenshots use `image` content:

```gdscript
func _wrap_mcp_result(tool_name: String, result: Dictionary) -> Dictionary:
    if tool_name == "take_screenshot" and result.has("image_base64"):
        var image_data: String = result["image_base64"]
        result.erase("image_base64")
        return {
            "content": [
                {"type": "image", "data": image_data, "mimeType": "image/png"},
                {"type": "text", "text": JSON.stringify(result)},
            ]
        }
    return {"content": [{"type": "text", "text": JSON.stringify(result)}]}
```

### Developer Settings Page (`app_settings_developer_page.gd`)

This is a **shared settings page** for both the test API and MCP server. It is only visible when Developer Mode is enabled. See [Client Test API — Developer Mode](client_test_api.md#developer-mode-settings-page) for the full page layout.

The MCP-specific section of the page includes:

1. **MCP Toggle** — CheckButton "Enable MCP Server" with description: "Authenticated JSON-RPC endpoint for AI tools"
2. **Status Indicator** — Label showing "Listening on 127.0.0.1:39101" or "Stopped"
3. **Token Section** — Masked token display + Copy button + Rotate button (with confirmation dialog)
4. **Port** — SpinBox (range 1024–65535, default 39101)
5. **Tool Groups** — CheckButton per group with description:
   - [x] Read — "Query spaces, channels, members, messages"
   - [x] Navigate — "Change active space/channel, open dialogs and panels"
   - [x] Screenshot — "Capture viewport screenshots"
   - [ ] Message — "Send and edit messages as you"
   - [ ] Moderate — "Kick, ban, timeout members"
   - [ ] Voice — "Join/leave voice channels, toggle mute"
6. **Connection Log** — Collapsible section showing recent MCP requests (tool name, timestamp, success/fail) — kept in memory, not persisted

### Security Model

| Concern | Mitigation |
|---------|------------|
| Disabled by default | Requires Developer Mode → MCP toggle — two explicit opt-in steps |
| Token leakage | Token stored in encrypted per-profile config; displayed masked in UI; copy requires explicit click |
| Network exposure | Listener bound to `127.0.0.1` only; refuses non-loopback connections |
| Privilege escalation | Tool groups gated by config; moderation tools additionally check user's server permissions before executing |
| Token brute-force | Constant-time comparison; 256-bit token entropy; optional rate limiting |
| Multi-profile isolation | Each profile has its own token; switching profiles stops the listener and restarts with the new profile's config |
| Screenshot data | Screenshots are base64-encoded in JSON responses over localhost only; never persisted unless `save_path` is provided; the `screenshot` group can be disabled independently |
| Dialog injection | `open_dialog` only accepts names from a hardcoded allowlist; arbitrary scene paths are rejected |
| Viewport resize | `set_viewport_size` is clamped to reasonable bounds (320–3840px) to prevent abuse |

### Multi-Server Awareness

The MCP tools operate on the user's current view state. Tools like `select_space` and `select_channel` work across connections transparently via Client's `_space_to_conn` routing. Read tools that need a connection index derive it from the space/channel ID the same way the UI does.

### Compatibility with accordserver MCP

The server-side MCP endpoint (`POST /mcp` on accordserver) uses a server-wide API key and operates at the server admin level. The client-side MCP server is complementary:

| Aspect | Server MCP | Client MCP |
|--------|-----------|------------|
| Runs on | accordserver (remote) | daccord client (local) |
| Default port | 39099 | 39101 |
| Auth | Server-wide `MCP_API_KEY` | Per-account client-side token |
| Scope | Full server admin | User's permissions only |
| Transport | Streamable HTTP on server port | Streamable HTTP on localhost |
| Message attribution | `"mcp"` author | Current logged-in user |
| Use case | Server automation, bots | Personal AI assistant, UI auditing |
| Screenshot | N/A | Viewport capture via `take_screenshot` |
| Navigation | N/A | Full UI control via `navigate`/`screenshot` groups |
| Tool count | 15 tools | 35 tools (6 groups) |
| Network | Can be remote | Localhost only (`127.0.0.1`) |

An AI agent could use both: server MCP for admin tasks and data seeding, client MCP for navigating the UI, taking screenshots, and visually verifying the results.

### accordserver-mcp TypeScript Client (`../accordserver-mcp/`)

The `accordserver-mcp` package provides TypeScript MCP clients for both the server and client endpoints. The client MCP integration lives in separate files to maintain clear separation:

#### Architecture

```
accordserver-mcp/
├── src/
│   ├── client.ts        # AccordMCPClient — server MCP (port 39099, admin)
│   ├── index.ts          # Server CLI entry point (accord-mcp binary)
│   ├── client-mcp.ts     # DaccordClientMCPClient — client MCP (port 39101, user-scoped)
│   └── client-cli.ts     # Client CLI entry point (daccord-mcp binary)
├── tools.json            # Server MCP tool schemas (15 tools)
├── client-tools.json     # Client MCP tool schemas (35 tools, 6 groups)
├── mcp.json              # AI tool config for both endpoints
└── package.json          # Exports both binaries
```

#### `DaccordClientMCPClient` class (`src/client-mcp.ts`)

Typed async methods covering all 35 client MCP tools across 6 groups:

- **Read (8):** `getCurrentState()`, `listSpaces()`, `getSpace()`, `listChannels()`, `listMembers()`, `getUser()`, `listMessages()`, `searchMessages()`
- **Navigate (12):** `selectSpace()`, `selectChannel()`, `openDm()`, `openSettings()`, `openDiscovery()`, `openThread()`, `openVoiceView()`, `toggleMemberList()`, `toggleSearch()`, `navigateToSurface()`, `openDialog()`, `setViewportSize()`
- **Screenshot (3):** `takeScreenshot()`, `listSurfaces()`, `getSurfaceInfo()`
- **Message (4):** `sendMessage()`, `editMessage()`, `deleteMessage()`, `addReaction()`
- **Moderate (4):** `kickMember()`, `banUser()`, `unbanUser()`, `timeoutMember()`
- **Voice (4):** `joinVoiceChannel()`, `leaveVoice()`, `toggleMute()`, `toggleDeafen()`

Uses `StreamableHTTPClientTransport` from `@modelcontextprotocol/sdk` with bearer token auth. Environment: `DACCORD_MCP_URL` (default `http://localhost:39101/mcp`), `DACCORD_MCP_TOKEN` (required).

#### Client CLI (`daccord-mcp` binary, `src/client-cli.ts`)

Interactive readline shell with `daccord>` prompt. Supports all 35 tools via human-friendly commands:

```
$ export DACCORD_MCP_TOKEN="dk_a1b2...c3d4"
$ daccord-mcp

daccord> state                          # get_current_state
daccord> select-space abc123            # select_space
daccord> screenshot /tmp/audit.png      # take_screenshot
daccord> viewport compact               # set_viewport_size {preset: "compact"}
daccord> viewport 1920x1080             # set_viewport_size {width: 1920, height: 1080}
daccord> navigate 6.2 with_reply        # navigate_to_surface
daccord> dialog ban                     # open_dialog
daccord> send def456 Hello world        # send_message
daccord> react msg123 thumbsup          # add_reaction
daccord> call any_tool {"key": "val"}   # generic callTool
```

Image content from screenshots is displayed as `[image: N bytes base64]` in the CLI.

#### AI Tool Configuration (`mcp.json`)

Both endpoints can be configured simultaneously in AI tools:

```json
{
  "mcpServers": {
    "accord": {
      "type": "streamable-http",
      "url": "http://localhost:39099/mcp",
      "headers": { "Authorization": "Bearer SERVER_API_KEY" }
    },
    "daccord": {
      "type": "streamable-http",
      "url": "http://localhost:39101/mcp",
      "headers": { "Authorization": "Bearer CLIENT_MCP_TOKEN" }
    }
  }
}
```

This enables workflows like: seed test data via server MCP → navigate to it via client MCP → screenshot for verification.

#### Key Differences from Server Client (`AccordMCPClient`)

| | `AccordMCPClient` (server) | `DaccordClientMCPClient` (client) |
|---|---|---|
| File | `src/client.ts` | `src/client-mcp.ts` |
| CLI | `src/index.ts` (`accord-mcp`) | `src/client-cli.ts` (`daccord-mcp`) |
| Default URL | `http://localhost:39099/mcp` | `http://localhost:39101/mcp` |
| Env: URL | `ACCORD_MCP_URL` | `DACCORD_MCP_URL` |
| Env: Auth | `ACCORD_MCP_API_KEY` | `DACCORD_MCP_TOKEN` |
| Methods | 15 (read/write/moderate) | 35 (read/navigate/screenshot/message/moderate/voice) |
| Unique tools | `serverInfo()`, `createChannel()`, `deleteChannel()` | `getCurrentState()`, navigate/screenshot/voice tools |
| CLI prompt | `accord>` | `daccord>` |

### Automated UI Audit Example

A complete audit session using the MCP tools:

```
# 1. Connect and get current state
→ tools/call get_current_state
← {"current_space_id": "123", "layout_mode": "FULL", ...}

# 2. List all auditable surfaces
→ tools/call list_surfaces {"section": "Messages — Message View"}
← {"surfaces": [...], "count": 14}

# 3. Set viewport to FULL breakpoint
→ tools/call set_viewport_size {"preset": "full"}
← {"ok": true, "width": 1280, "height": 720, "layout_mode": "FULL"}

# 4. Navigate to surface 6.2 (Cozy message)
→ tools/call navigate_to_surface {"surface_id": "6.2", "state": "with_reply"}
← {"ok": true, "surface_name": "Cozy message", "scene": "scenes/messages/cozy_message.tscn"}

# 5. Capture screenshot
→ tools/call take_screenshot {"save_path": "user://audit/6.2_cozy_message_full.png"}
← {"image_base64": "...", "width": 1280, "height": 720}

# 6. Resize to COMPACT and capture again
→ tools/call set_viewport_size {"preset": "compact"}
← {"ok": true, "width": 480, "height": 800, "layout_mode": "COMPACT"}

→ tools/call take_screenshot {"save_path": "user://audit/6.2_cozy_message_compact.png"}
← {"image_base64": "...", "width": 480, "height": 800}

# 7. Open a dialog and screenshot it
→ tools/call open_dialog {"dialog_name": "ban"}
← {"ok": true, "dialog": "ban", "scene": "res://scenes/admin/ban_dialog.tscn"}

→ tools/call take_screenshot {}
← {"image_base64": "...", "width": 480, "height": 800}

# 8. Repeat for all 121 surfaces × 3 breakpoints
```

## Implementation Status

- [x] `ClientMcp` subsystem as protocol adapter over `ClientTestApi` (`client_mcp.gd`)
- [x] JSON-RPC 2.0 + MCP protocol handler (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`)
- [x] Bearer token authentication with constant-time comparison
- [x] Tool group permission filtering (6 groups: read, navigate, screenshot, message, moderate, voice)
- [x] Tool-to-endpoint mapping (34 tools across 6 groups)
- [x] MCP content type wrapping (text + image for screenshots)
- [x] Developer settings page — MCP section (token, port, groups) (`app_settings_developer_page.gd`)
- [x] Token generation and rotation (256-bit random via `Crypto.generate_random_bytes(32)`)
- [x] Connection activity log (in-memory ring buffer, 100 entries)
- [x] Client integration — init, poll, shutdown in `client.gd` (lines 256–263, 271, 293)
- [x] MCP auto-creates test API backend if not already started (no separate test API toggle needed)
- [x] Developer page status checks actual listener state (`Client.mcp.is_listening()`)
- [x] HTTP listener with rate limiting (60 req/s), read timeout (5s), connection limit (4)
- [x] Unit tests for tool registration, group filtering, JSON-RPC dispatch, content wrapping, auth (40+ tests in `test_client_mcp.gd`)
- [x] accordserver-mcp TypeScript client (`DaccordClientMCPClient` in `../accordserver-mcp/src/client-mcp.ts`)
- [x] Client CLI binary (`daccord-mcp` in `../accordserver-mcp/src/client-cli.ts`)
- [x] Client tool schema definitions (`../accordserver-mcp/client-tools.json`, 35 tools)
- [x] Dual AI tool config (`../accordserver-mcp/mcp.json` — `accord` + `daccord` entries)
- [ ] Integration test with real HTTP round-trips (client MCP server ↔ `DaccordClientMCPClient`)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~Shared HTTP parsing with test API~~ | ~~Medium~~ | **Resolved.** Both subsystems use the same pattern (TCPServer + StreamPeerTCP) but independently — duplication is acceptable given the different paths (`/api/` vs `/mcp`) and auth models |
| ~~Rate limiting not designed~~ | ~~Medium~~ | **Resolved.** 60 req/s burst window via `_is_rate_limited()` in `client_mcp.gd` |
| ~~Integration test with accordserver-mcp~~ | ~~Medium~~ | **Resolved.** `DaccordClientMCPClient` in `../accordserver-mcp/src/client-mcp.ts` provides a typed TypeScript client. End-to-end HTTP round-trip test still needed |
| No SSE/streaming support | Low | Initial implementation uses request-response only. MCP spec supports server-sent events for streaming; can be added later |
| No per-tool granularity | Low | Current design uses tool groups, not individual tool toggles. Could add per-tool overrides later if users need finer control |
| No audit trail persistence | Low | Connection log is in-memory ring buffer (100 entries). Could optionally write to a local log file for debugging |
| Token migration on profile export/import | Low | Exported profiles include the MCP token in encrypted config; re-importing on another machine works but user should rotate token |
| Web export incompatibility | Medium | TCPServer is unavailable in HTML5 exports. MCP disabled entirely on web builds |
| Android localhost networking | Medium | Android may restrict localhost server sockets depending on OS version. Needs testing |
| E2E round-trip test | Medium | Need a test that starts the daccord MCP server and connects `DaccordClientMCPClient` to verify real HTTP protocol compliance |
