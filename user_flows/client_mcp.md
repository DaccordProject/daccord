# Client MCP Server

## Overview

Daccord exposes a local MCP (Model Context Protocol) server that lets authenticated AI agents control the client — reading state, navigating channels, sending messages, managing spaces, navigating to specific UI surfaces, and capturing screenshots. The MCP server is disabled by default and uses a per-account, client-side-only bearer token for authentication. A dedicated settings page allows users to enable/disable the server, rotate tokens, and control which tool categories are exposed.

The `navigate` and `screenshot` tool groups together enable automated UI auditing: an AI agent can systematically walk through every dialog, panel, and view in the client (cataloged in [UI Audit](ui_audit.md)), capture screenshots at each state, and analyze them for design/UX issues — all without manual interaction.

## User Steps

1. Open App Settings → "AI Integration" page
2. Toggle "Enable MCP Server" (off by default)
3. A random bearer token is generated and displayed once; user copies it to their AI tool config
4. Optionally restrict which tool groups are available (read-only, moderation, messaging, navigation, screenshot)
5. Optionally change the listen port (default: 39100)
6. AI agent connects to `http://localhost:<port>/mcp` with the bearer token
7. AI agent calls MCP tools; client executes actions on the user's behalf
8. User can revoke/rotate the token or disable the server at any time

### Automated UI Audit Workflow

1. AI agent calls `list_surfaces` to get the full catalog of 121 UI surfaces
2. Agent calls `navigate_to_surface` with a surface ID (e.g., `"6.2"`) to navigate to that view
3. Agent calls `take_screenshot` to capture the current viewport as a base64-encoded PNG
4. Agent optionally calls `set_viewport_size` to test responsive breakpoints (COMPACT/MEDIUM/FULL)
5. Agent repeats for each surface × breakpoint combination
6. Agent analyzes screenshots for visual consistency, spacing, accessibility issues

## Signal Flow

```
User toggles MCP on/off in settings
  → Config.set_mcp_enabled(true/false)
    → Config._save()
    → AppState.config_changed.emit("mcp", "enabled")
      → ClientMcp receives signal
        → starts/stops HTTP listener

AI agent sends JSON-RPC request
  → ClientMcp.HttpListener receives POST /mcp
    → _validate_token(request)
    → _dispatch_method(json_rpc)
      → tools/list → return tool definitions
      → tools/call → execute tool
        → Client.fetch / Client.mutations / Client.admin / AppState signals
      → JSON-RPC response sent back

AI agent calls navigate_to_surface("6.2")
  → ClientMcp._tool_navigate_to_surface({"surface_id": "6.2"})
    → Looks up surface in _surface_catalog
    → Emits AppState.channel_selected (or opens dialog, etc.)
    → Waits one frame for scene tree to settle
    → Returns {"ok": true, "surface": "Cozy message", "scene": "scenes/messages/cozy_message.tscn"}

AI agent calls take_screenshot()
  → ClientMcp._tool_take_screenshot({})
    → _c.get_viewport().get_texture().get_image()
    → image.save_png_to_buffer()
    → Returns {"image": "<base64 PNG>", "width": 1280, "height": 720}

User rotates token
  → Config.set_mcp_token(new_token)
    → AppState.config_changed.emit("mcp", "token")
      → ClientMcp invalidates old token immediately
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_mcp.gd` | **New.** MCP server subsystem — HTTP listener, JSON-RPC dispatch, tool implementations, surface catalog |
| `scripts/autoload/client_mcp_surfaces.gd` | **New.** Surface catalog data — maps surface IDs to navigation actions and scene paths |
| `scripts/autoload/client.gd` | Parent client — initializes `mcp = ClientMcp.new(self)` alongside other subsystems (line ~184) |
| `scripts/autoload/config.gd` | Stores MCP settings in `mcp/` config section (enabled, token, port, allowed_tools) |
| `scripts/autoload/app_state.gd` | Signal bus — `space_selected`, `channel_selected`, `dm_mode_entered`, `discovery_opened`, `toggle_member_list`, `toggle_search`, `open_thread`, `open_voice_view`, etc. |
| `scenes/main/main_window.gd` | Dialog lifecycle — `_on_profile_card_requested`, `_check_rules_interstitial`, toast/lightbox instantiation |
| `scenes/user/app_settings.gd` | Hosts new "AI Integration" page via `_build_mcp_page()` |
| `scenes/user/app_settings_mcp_page.gd` | **New.** Settings page UI — toggle, token display/copy/rotate, port, tool group checkboxes |
| `tests/unit/test_client_mcp.gd` | **New.** Unit tests for token validation, tool dispatch, surface navigation, screenshot capture |
| `user_flows/ui_audit.md` | Reference — canonical list of 121 surfaces with scene paths and states to capture |

## Implementation Details

### Config Storage (`config.gd`)

New `mcp/` section in the per-profile encrypted config:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mcp/enabled` | bool | `false` | Master on/off switch |
| `mcp/token` | String | `""` | Bearer token (generated client-side, never sent to server) |
| `mcp/port` | int | `39100` | Local HTTP listen port |
| `mcp/allowed_groups` | PackedStringArray | `["read","navigate"]` | Tool groups the AI may use |

Getter/setter pairs following the existing pattern:

```gdscript
func get_mcp_enabled() -> bool:
    return _config.get_value("mcp", "enabled", false)

func set_mcp_enabled(enabled: bool) -> void:
    _config.set_value("mcp", "enabled", enabled)
    _save()
    AppState.config_changed.emit("mcp", "enabled")
```

Token is generated via `Crypto.new().generate_random_bytes(32)` encoded as hex — never leaves the device. Stored encrypted alongside other profile credentials.

### Client Subsystem (`client_mcp.gd`)

Follows the existing subsystem pattern (like `client_plugins.gd`):

```gdscript
class_name ClientMcp extends RefCounted

var _c: Node  # Parent Client reference
var _server: TCPServer
var _token: String
var _enabled: bool = false
var _port: int = 39100
var _surfaces: ClientMcpSurfaces

func _init(client_node: Node) -> void:
    _c = client_node
    _surfaces = ClientMcpSurfaces.new(client_node)
    AppState.config_changed.connect(_on_config_changed)
```

#### HTTP Listener

Uses Godot's `TCPServer` + `StreamPeerTCP` to accept connections. Parses HTTP requests manually (Godot has no built-in HTTP server). Alternatively, could use `HTTPServer` from a lightweight addon.

- Binds to `127.0.0.1` only (localhost — never exposed to network)
- Processes requests in `_process()` tick (registered via Client's process loop)
- Validates `Authorization: Bearer <token>` header with constant-time comparison
- Responds with JSON-RPC 2.0 conforming to MCP protocol version `2025-03-26`

#### JSON-RPC Dispatch

Implements three MCP methods:

1. **`initialize`** — Returns server info, protocol version, capabilities
2. **`tools/list`** — Returns available tools filtered by `allowed_groups`
3. **`tools/call`** — Executes the requested tool, returns result

#### Tool Groups and Definitions

| Group | Tools | Description |
|-------|-------|-------------|
| `read` | `get_current_state`, `list_spaces`, `get_space`, `list_channels`, `list_members`, `list_messages`, `search_messages`, `get_user` | Read-only queries against cached client data |
| `navigate` | `select_space`, `select_channel`, `open_dm`, `open_settings`, `open_discovery`, `open_thread`, `open_voice_view`, `toggle_member_list`, `toggle_search`, `navigate_to_surface`, `open_dialog`, `set_viewport_size` | UI navigation — changes what the user sees, opens panels/dialogs, resizes viewport |
| `screenshot` | `take_screenshot`, `list_surfaces`, `get_surface_info` | Viewport capture and UI surface catalog queries |
| `message` | `send_message`, `edit_message`, `delete_message`, `add_reaction` | Message authoring on behalf of the user |
| `moderate` | `kick_member`, `ban_user`, `unban_user`, `delete_message`, `timeout_member` | Moderation actions (requires user to have server permissions) |
| `voice` | `join_voice_channel`, `leave_voice`, `toggle_mute`, `toggle_deafen` | Voice channel control |

Tools in the `read` and `navigate` groups are enabled by default. The `screenshot` group is also enabled by default (read-only capture). Destructive groups (`message`, `moderate`, `voice`) require explicit opt-in.

Each tool maps to existing Client/AppState calls:

```gdscript
func _tool_select_channel(args: Dictionary) -> Dictionary:
    var channel_id: String = args.get("channel_id", "")
    var space_id: String = _c._channel_to_space.get(channel_id, "")
    if space_id.is_empty():
        return {"error": "Channel not found"}
    AppState.channel_selected.emit(space_id, channel_id)
    return {"ok": true, "channel_id": channel_id}

func _tool_list_messages(args: Dictionary) -> Dictionary:
    var channel_id: String = args.get("channel_id", "")
    var limit: int = args.get("limit", 50)
    var messages: Array = _c._messages.get(channel_id, []).slice(-limit)
    return {"messages": messages}
```

Read tools pull from Client's in-memory caches (`_users`, `_spaces`, `_channels`, `_messages`, `_members`) — no API calls needed for cached data.

### Navigate Tool Group — Expanded

The `navigate` group has been expanded beyond basic space/channel selection to support full UI traversal. Each tool maps to an AppState signal or method:

| Tool | Parameters | AppState Signal/Method | Effect |
|------|-----------|----------------------|--------|
| `select_space` | `space_id` | `AppState.select_space(space_id)` | Switches to a space, loads channel list |
| `select_channel` | `channel_id` | `AppState.select_channel(channel_id)` | Switches to a channel, loads messages |
| `open_dm` | `user_id?` | `AppState.enter_dm_mode()` | Enters DM mode; if user_id given, opens that DM |
| `open_settings` | `page?` | Instantiates `app_settings.tscn` | Opens settings; optional page name (e.g., `"voice"`, `"profiles"`, `"ai_integration"`) |
| `open_discovery` | — | `AppState.open_discovery()` | Opens the server discovery panel |
| `open_thread` | `message_id` | `AppState.open_thread(message_id)` | Opens thread side panel for a message |
| `open_voice_view` | — | `AppState.open_voice_view()` | Opens full video grid (must be in voice first) |
| `toggle_member_list` | — | `AppState.toggle_member_list()` | Shows/hides the member list panel |
| `toggle_search` | — | `AppState.toggle_search()` | Shows/hides the search panel |
| `navigate_to_surface` | `surface_id` | (compound — see below) | Navigates to a specific UI audit surface by catalog ID |
| `open_dialog` | `dialog_name`, `args?` | (compound — see below) | Opens a specific dialog by name |
| `set_viewport_size` | `width`, `height?` | `DisplayServer.window_set_size()` | Resizes the viewport to test responsive breakpoints |

#### `navigate_to_surface` Implementation

This tool is the bridge between the UI audit surface catalog and live navigation. It accepts a surface ID (e.g., `"6.2"`, `"11.1"`, `"2.9"`) from the catalog in `ui_audit.md` and performs the multi-step navigation required to reach that surface.

```gdscript
func _tool_navigate_to_surface(args: Dictionary) -> Dictionary:
    var surface_id: String = args.get("surface_id", "")
    var state: String = args.get("state", "default")
    var entry: Dictionary = _surfaces.get_surface(surface_id)
    if entry.is_empty():
        return {"error": "Unknown surface ID: %s" % surface_id}

    # Execute the navigation steps for this surface
    var result: Dictionary = await _surfaces.navigate_to(surface_id, state)
    if result.has("error"):
        return result

    # Wait one frame for the scene tree to settle
    await _c.get_tree().process_frame

    return {
        "ok": true,
        "surface_id": surface_id,
        "surface_name": entry.get("name", ""),
        "scene_file": entry.get("scene", ""),
        "state": state,
        "description": entry.get("description", ""),
    }
```

#### `open_dialog` Implementation

Opens a named dialog, passing optional arguments. Dialog names map to preloaded scene paths:

```gdscript
const DIALOG_MAP: Dictionary = {
    # .tscn dialogs — instantiated via load().instantiate()
    "add_server": "res://scenes/sidebar/guild_bar/add_server_dialog.tscn",
    "auth": "res://scenes/sidebar/guild_bar/auth_dialog.tscn",
    "change_password": "res://scenes/sidebar/guild_bar/change_password_dialog.tscn",
    "ban": "res://scenes/admin/ban_dialog.tscn",
    "ban_list": "res://scenes/admin/ban_list_dialog.tscn",
    "create_channel": "res://scenes/admin/create_channel_dialog.tscn",
    "channel_edit": "res://scenes/admin/channel_edit_dialog.tscn",
    "channel_permissions": "res://scenes/admin/channel_permissions_dialog.tscn",
    "channel_management": "res://scenes/admin/channel_management_dialog.tscn",
    "category_edit": "res://scenes/admin/category_edit_dialog.tscn",
    "role_management": "res://scenes/admin/role_management_dialog.tscn",
    "moderate_member": "res://scenes/admin/moderate_member_dialog.tscn",
    "nickname": "res://scenes/admin/nickname_dialog.tscn",
    "invite_management": "res://scenes/admin/invite_management_dialog.tscn",
    "report": "res://scenes/admin/report_dialog.tscn",
    "report_list": "res://scenes/admin/report_list_dialog.tscn",
    "audit_log": "res://scenes/admin/audit_log_dialog.tscn",
    "emoji_management": "res://scenes/admin/emoji_management_dialog.tscn",
    "soundboard_management": "res://scenes/admin/soundboard_management_dialog.tscn",
    "space_settings": "res://scenes/admin/space_settings_dialog.tscn",
    "imposter_picker": "res://scenes/admin/imposter_picker_dialog.tscn",
    "reset_password": "res://scenes/admin/reset_password_dialog.tscn",
    "confirm": "res://scenes/admin/confirm_dialog.tscn",
    "nsfw_gate": "res://scenes/admin/nsfw_gate_dialog.tscn",
    "add_friend": "res://scenes/sidebar/direct/add_friend_dialog.tscn",
    "add_member": "res://scenes/sidebar/direct/add_member_dialog.tscn",
    "create_group_dm": "res://scenes/sidebar/direct/create_group_dm_dialog.tscn",
    "screen_picker": "res://scenes/sidebar/screen_picker_dialog.tscn",
    "create_profile": "res://scenes/user/create_profile_dialog.tscn",
    "profile_password": "res://scenes/user/profile_password_dialog.tscn",
    "profile_set_password": "res://scenes/user/profile_set_password_dialog.tscn",
    "server_settings": "res://scenes/user/server_settings.tscn",
    "update_download": "res://scenes/messages/update_download_dialog.tscn",
    "app_settings": "res://scenes/user/app_settings.tscn",
    # .gd-only dialogs — instantiated via ScriptClass.new()
    "create_space": "res://scenes/admin/create_space_dialog.gd",
    "transfer_ownership": "res://scenes/admin/transfer_ownership_dialog.gd",
    "rules_interstitial": "res://scenes/admin/rules_interstitial_dialog.gd",
    "plugin_management": "res://scenes/admin/plugin_management_dialog.gd",
    "active_threads": "res://scenes/messages/active_threads_dialog.gd",
    "plugin_trust": "res://scenes/plugins/plugin_trust_dialog.gd",
}

func _tool_open_dialog(args: Dictionary) -> Dictionary:
    var dialog_name: String = args.get("dialog_name", "")
    var res_path: String = DIALOG_MAP.get(dialog_name, "")
    if res_path.is_empty():
        return {"error": "Unknown dialog: %s" % dialog_name, "available": DIALOG_MAP.keys()}
    # Close any previously opened MCP dialog
    if _active_dialog != null and is_instance_valid(_active_dialog):
        _active_dialog.queue_free()
        _active_dialog = null
    # .gd-only dialogs use Script.new(), .tscn use load().instantiate()
    var dialog: Node
    if res_path.ends_with(".gd"):
        var script: GDScript = load(res_path)
        dialog = script.new()
    else:
        var scene: PackedScene = load(res_path)
        dialog = scene.instantiate()
    # Pass setup args if the dialog has a setup() method
    var setup_args: Dictionary = args.get("args", {})
    if dialog.has_method("setup") and not setup_args.is_empty():
        dialog.callv("setup", [setup_args])
    _c.get_tree().root.add_child(dialog)
    if dialog.has_method("popup_centered"):
        dialog.popup_centered()
    _active_dialog = dialog
    await _c.get_tree().process_frame
    return {"ok": true, "dialog": dialog_name, "path": res_path}
```

#### `set_viewport_size` Implementation

Allows the agent to test responsive breakpoints by resizing the window:

```gdscript
const BREAKPOINTS: Dictionary = {
    "compact": Vector2i(480, 800),
    "medium": Vector2i(700, 900),
    "full": Vector2i(1280, 720),
}

func _tool_set_viewport_size(args: Dictionary) -> Dictionary:
    var width: int = args.get("width", 0)
    var height: int = args.get("height", 0)
    var preset: String = args.get("preset", "")
    if not preset.is_empty():
        var size: Vector2i = BREAKPOINTS.get(preset, Vector2i.ZERO)
        if size == Vector2i.ZERO:
            return {"error": "Unknown preset: %s" % preset, "available": BREAKPOINTS.keys()}
        width = size.x
        height = size.y
    if width <= 0:
        return {"error": "width is required (or use preset: compact/medium/full)"}
    if height <= 0:
        height = int(width * 0.75)
    DisplayServer.window_set_size(Vector2i(width, height))
    # Wait for layout to re-settle after resize
    await _c.get_tree().process_frame
    await _c.get_tree().process_frame
    var actual: Vector2i = DisplayServer.window_get_size()
    return {
        "ok": true,
        "width": actual.x,
        "height": actual.y,
        "layout_mode": AppState.LayoutMode.keys()[AppState.current_layout_mode],
    }
```

### Screenshot Tool Group

The `screenshot` group provides viewport capture and surface catalog querying. These tools enable AI agents to visually inspect the client UI.

#### `take_screenshot`

Captures the current viewport as a PNG image and returns it base64-encoded. The MCP response uses the `image` content type defined in the MCP spec.

```gdscript
func _tool_take_screenshot(args: Dictionary) -> Dictionary:
    # Wait for current frame to finish rendering
    await RenderingServer.frame_post_draw

    var viewport: Viewport = _c.get_viewport()
    var image: Image = viewport.get_texture().get_image()

    # Optional: crop to a specific region
    var x: int = args.get("x", 0)
    var y: int = args.get("y", 0)
    var w: int = args.get("width", 0)
    var h: int = args.get("height", 0)
    if w > 0 and h > 0:
        image = image.get_region(Rect2i(x, y, w, h))

    var png_data: PackedByteArray = image.save_png_to_buffer()
    var base64: String = Marshalls.raw_to_base64(png_data)

    # Optional: save to disk
    var save_path: String = args.get("save_path", "")
    if not save_path.is_empty():
        image.save_png(save_path)

    return {
        "image_base64": base64,
        "width": image.get_width(),
        "height": image.get_height(),
        "format": "png",
        "size_bytes": png_data.size(),
    }
```

The MCP JSON-RPC response wraps this in the standard MCP content format:

```json
{
  "content": [
    {
      "type": "image",
      "data": "<base64 PNG>",
      "mimeType": "image/png"
    },
    {
      "type": "text",
      "text": "{\"width\": 1280, \"height\": 720, \"format\": \"png\", \"size_bytes\": 45231}"
    }
  ]
}
```

#### `list_surfaces`

Returns the full UI audit surface catalog, optionally filtered by section:

```gdscript
func _tool_list_surfaces(args: Dictionary) -> Dictionary:
    var section: String = args.get("section", "")
    var surfaces: Array = _surfaces.get_catalog(section)
    return {"surfaces": surfaces, "count": surfaces.size()}
```

Response example:

```json
{
  "surfaces": [
    {
      "id": "6.2",
      "name": "Cozy message",
      "section": "Messages — Message View",
      "scene": "scenes/messages/cozy_message.tscn",
      "script": "cozy_message.gd",
      "states": ["normal", "with_reply", "with_attachments", "with_embeds", "with_reactions", "with_thread_indicator", "edited", "system_message"]
    },
    {
      "id": "6.5",
      "name": "Message action bar",
      "section": "Messages — Message View",
      "scene": "scenes/messages/message_action_bar.tscn",
      "script": "message_view_actions.gd",
      "states": ["hover_actions"]
    }
  ],
  "count": 2
}
```

#### `get_surface_info`

Returns detailed info for a single surface including its navigation prerequisites:

```gdscript
func _tool_get_surface_info(args: Dictionary) -> Dictionary:
    var surface_id: String = args.get("surface_id", "")
    var entry: Dictionary = _surfaces.get_surface(surface_id)
    if entry.is_empty():
        return {"error": "Unknown surface ID: %s" % surface_id}
    return entry
```

### Surface Catalog (`client_mcp_surfaces.gd`)

The surface catalog is a structured data file that maps each UI audit surface ID to the navigation steps needed to reach it. This is derived from the [UI Audit](ui_audit.md) checklist.

```gdscript
class_name ClientMcpSurfaces extends RefCounted

var _c: Node

func _init(client_node: Node) -> void:
    _c = client_node

# Each entry maps a surface ID to:
#   name: Human-readable surface name
#   section: UI audit section name
#   scene: Scene file path (for reference)
#   script: Script file (for reference)
#   states: Array of capturable states
#   navigate: Callable that navigates to this surface
#   prereqs: What must be true before navigation (e.g., "connected to a server")

var _catalog: Dictionary = {
    # --- 1. Main Window & Navigation ---
    "1.1": {
        "name": "Main window (full layout)",
        "section": "Main Window & Navigation",
        "scene": "scenes/main/main_window.tscn",
        "script": "main_window.gd",
        "states": ["compact", "medium", "full"],
        "navigate": func(_state: String) -> Dictionary:
            return {"ok": true},
    },
    "1.2": {
        "name": "Welcome screen (no servers)",
        "section": "Main Window & Navigation",
        "scene": "scenes/main/welcome_screen.tscn",
        "script": "welcome_screen.gd",
        "states": ["empty"],
        "prereqs": "No servers configured",
        "navigate": func(_state: String) -> Dictionary:
            # Welcome screen only shows when no servers exist
            return {"ok": true, "note": "Requires no server connections"},
    },
    # --- 2. Sidebar — Guild Bar ---
    "2.9": {
        "name": "Add server dialog",
        "section": "Sidebar — Guild Bar",
        "scene": "scenes/sidebar/guild_bar/add_server_dialog.tscn",
        "script": "add_server_dialog.gd",
        "states": ["join_tab", "create_tab", "loading", "error"],
        "navigate": func(_state: String) -> Dictionary:
            var scene: PackedScene = load(
                "res://scenes/sidebar/guild_bar/add_server_dialog.tscn"
            )
            var dialog: Node = scene.instantiate()
            _c.get_tree().root.add_child(dialog)
            return {"ok": true},
    },
    "2.10": {
        "name": "Auth dialog (login/register)",
        "section": "Sidebar — Guild Bar",
        "scene": "scenes/sidebar/guild_bar/auth_dialog.tscn",
        "script": "auth_dialog.gd",
        "states": ["login_form", "register_form", "loading", "error", "2fa_prompt"],
        "navigate": func(_state: String) -> Dictionary:
            var scene: PackedScene = load(
                "res://scenes/sidebar/guild_bar/auth_dialog.tscn"
            )
            var dialog: Node = scene.instantiate()
            _c.get_tree().root.add_child(dialog)
            return {"ok": true},
    },
    # --- 3. Sidebar — Channel List ---
    "3.1": {
        "name": "Channel list panel",
        "section": "Sidebar — Channel List",
        "scene": "scenes/sidebar/channels/channel_list.tscn",
        "script": "channel_list.gd",
        "states": ["populated", "empty", "loading_skeleton"],
        "prereqs": "Connected to a server with a space selected",
        "navigate": func(_state: String) -> Dictionary:
            AppState.toggle_channel_panel()
            if not AppState.channel_panel_visible:
                AppState.toggle_channel_panel()
            return {"ok": true},
    },
    # --- 4. Sidebar — DMs & Friends ---
    "4.2": {
        "name": "Friends list",
        "section": "Sidebar — DMs & Friends",
        "scene": "scenes/sidebar/direct/friends_list.tscn",
        "script": "friends_list.gd",
        "states": ["all", "online", "pending", "blocked", "empty"],
        "navigate": func(_state: String) -> Dictionary:
            AppState.enter_dm_mode()
            return {"ok": true},
    },
    # --- 6. Messages — Message View ---
    "6.1": {
        "name": "Message view (full)",
        "section": "Messages — Message View",
        "scene": "scenes/messages/message_view.tscn",
        "script": "message_view.gd",
        "states": ["normal", "nsfw_gate", "guest_banner", "connection_lost", "empty_channel"],
        "prereqs": "Connected with a channel selected",
        "navigate": func(_state: String) -> Dictionary:
            # Already visible when a channel is selected
            return {"ok": true},
    },
    # --- 9. Members ---
    "9.1": {
        "name": "Member list",
        "section": "Members",
        "scene": "scenes/members/member_list.tscn",
        "script": "member_list.gd",
        "states": ["populated", "search_active", "empty_search", "loading"],
        "navigate": func(_state: String) -> Dictionary:
            if not AppState.member_list_visible:
                AppState.toggle_member_list()
            return {"ok": true},
    },
    # --- 10. User Profile & Settings ---
    "10.2": {
        "name": "App settings panel",
        "section": "User Profile & Settings",
        "scene": "scenes/user/app_settings.tscn",
        "script": "app_settings.gd",
        "states": ["profiles", "voice_video", "sound", "appearance", "notifications", "updates", "about"],
        "navigate": func(state: String) -> Dictionary:
            var scene: PackedScene = load("res://scenes/user/app_settings.tscn")
            var dialog: Node = scene.instantiate()
            _c.get_tree().root.add_child(dialog)
            return {"ok": true},
    },
    # --- 11-16. Admin dialogs ---
    "11.1": {
        "name": "Server management panel",
        "section": "Admin — Server & Space",
        "scene": "scenes/admin/server_management_panel.tscn",
        "script": "server_management_panel.gd",
        "states": ["spaces_tab", "users_tab", "settings_tab", "reports_tab"],
        "prereqs": "Connected with admin permissions",
        "navigate": func(_state: String) -> Dictionary:
            var scene: PackedScene = load(
                "res://scenes/admin/server_management_panel.tscn"
            )
            var dialog: Node = scene.instantiate()
            _c.get_tree().root.add_child(dialog)
            return {"ok": true},
    },
    # --- 17. Discovery ---
    "17.1": {
        "name": "Discovery panel",
        "section": "Discovery",
        "scene": "scenes/discovery/discovery_panel.tscn",
        "script": "discovery_panel.gd",
        "states": ["server_grid", "search", "tag_filter", "loading", "empty_results"],
        "navigate": func(_state: String) -> Dictionary:
            AppState.open_discovery()
            return {"ok": true},
    },
    # --- 18. Search ---
    "18.1": {
        "name": "Search panel",
        "section": "Search",
        "scene": "scenes/search/search_panel.tscn",
        "script": "search_panel.gd",
        "states": ["empty", "with_results", "no_results", "loading"],
        "navigate": func(_state: String) -> Dictionary:
            if not AppState.search_open:
                AppState.toggle_search()
            return {"ok": true},
    },
    # Remaining 100+ surfaces follow the same pattern...
    # Full catalog covers all 121 entries from ui_audit.md
}
```

The catalog includes navigation callables for all 121 surfaces from the UI audit. Surfaces fall into categories by navigation complexity:

| Category | Example Surfaces | Navigation Method |
|----------|-----------------|-------------------|
| Always visible | Main window, sidebar, guild bar | No-op (already on screen) |
| Panel toggles | Member list, search, thread panel | `AppState.toggle_*()` signals |
| View switches | DM mode, discovery, voice view | `AppState.enter_dm_mode()` / `open_discovery()` / `open_voice_view()` |
| Space/channel selection | Channel list, message view | `AppState.select_space()` + `select_channel()` |
| Dialog popups | All admin dialogs, settings, auth | `load()` + `instantiate()` + `add_child()` + `popup_centered()` |
| Nested state | Forum view, thread panel, voice text | Multi-step: select channel type → open sub-panel |
| Context menus | Message/channel/member right-click | Simulated via `InputEventMouseButton` at target position |

### Settings Page (`app_settings_mcp_page.gd`)

Added to `app_settings.gd:_get_sections()` as "AI Integration" and `_build_pages()` via a new page class.

**Page layout:**

1. **Master Toggle** — CheckButton "Enable MCP Server" with warning label: "Allows AI tools on your machine to control this client"
2. **Status Indicator** — Label showing "Listening on 127.0.0.1:39100" or "Stopped"
3. **Token Section** — Masked token display + Copy button + Rotate button (with confirmation dialog)
4. **Port** — SpinBox (range 1024–65535, default 39100)
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
| Token leakage | Token stored in encrypted per-profile config; displayed masked in UI; copy requires explicit click |
| Network exposure | Listener bound to `127.0.0.1` only; refuses non-loopback connections |
| Privilege escalation | Tool groups gated by config; moderation tools additionally check user's server permissions before executing |
| Token brute-force | Constant-time comparison; 256-bit token entropy; optional rate limiting |
| Replay attacks | Stateless JSON-RPC; each request independently authenticated; no session tokens |
| Disabled by default | MCP server does not start unless explicitly enabled; no token generated until first enable |
| Multi-profile isolation | Each profile has its own token; switching profiles stops the listener and restarts with the new profile's config |
| Screenshot data | Screenshots are base64-encoded in JSON responses over localhost only; never persisted unless `save_path` is provided; the `screenshot` group can be disabled independently |
| Dialog injection | `open_dialog` only accepts names from a hardcoded allowlist (`DIALOG_MAP`); arbitrary scene paths are rejected |
| Viewport resize | `set_viewport_size` is clamped to reasonable bounds (320–3840px) to prevent abuse |

### Multi-Server Awareness

The MCP tools operate on the user's current view state. Tools like `select_space` and `select_channel` work across connections transparently via Client's `_space_to_conn` routing. Read tools that need a connection index derive it from the space/channel ID the same way the UI does.

The `get_current_state` tool returns:

```json
{
  "current_space_id": "123",
  "current_channel_id": "456",
  "connected_servers": ["https://server1.example.com", "https://server2.example.com"],
  "user_id": "789",
  "username": "alice",
  "layout_mode": "FULL",
  "viewport_size": {"width": 1280, "height": 720},
  "member_list_visible": true,
  "search_open": false,
  "thread_open": false,
  "discovery_open": false,
  "voice_channel_id": "",
  "is_voice_view_open": false
}
```

### Compatibility with accordserver MCP

The server-side MCP endpoint (`POST /mcp` on accordserver) uses a server-wide API key and operates at the server admin level. The client-side MCP server is complementary:

| Aspect | Server MCP | Client MCP |
|--------|-----------|------------|
| Runs on | accordserver (remote) | daccord client (local) |
| Auth | Server-wide `MCP_API_KEY` | Per-account client-side token |
| Scope | Full server admin | User's permissions only |
| Transport | Streamable HTTP on server port | Streamable HTTP on localhost |
| Use case | Server automation, bots | Personal AI assistant, UI auditing |
| Screenshot | N/A | Viewport capture via `take_screenshot` |
| Navigation | N/A | Full UI control via `navigate`/`screenshot` groups |

An AI agent could use both: server MCP for admin tasks and data seeding, client MCP for navigating the UI, taking screenshots, and visually verifying the results.

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

- [ ] Config storage (`mcp/` section in config.gd)
- [ ] ClientMcp subsystem with HTTP listener
- [ ] JSON-RPC 2.0 + MCP protocol handler
- [ ] `initialize` / `tools/list` / `tools/call` dispatch
- [ ] Read tool group (8 tools)
- [ ] Navigate tool group — basic (4 tools: `select_space`, `select_channel`, `open_dm`, `open_settings`)
- [ ] Navigate tool group — expanded (8 tools: `open_discovery`, `open_thread`, `open_voice_view`, `toggle_member_list`, `toggle_search`, `navigate_to_surface`, `open_dialog`, `set_viewport_size`)
- [ ] Screenshot tool group (3 tools: `take_screenshot`, `list_surfaces`, `get_surface_info`)
- [ ] Surface catalog (`client_mcp_surfaces.gd`) covering all 121 UI audit entries
- [ ] Message tool group (4 tools)
- [ ] Moderate tool group (5 tools)
- [ ] Voice tool group (4 tools)
- [ ] App Settings "AI Integration" page
- [ ] Token generation and rotation
- [ ] Tool group permission toggles (including screenshot group)
- [ ] Connection activity log
- [ ] Unit tests for token validation and tool dispatch
- [ ] Unit tests for surface navigation and screenshot capture
- [ ] Integration test with accordserver-mcp client

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Godot has no built-in HTTP server | High | Need to implement HTTP parsing over TCPServer/StreamPeerTCP, or use a lightweight GDScript HTTP server addon. WebSocketServer exists but MCP uses HTTP POST |
| Surface catalog is large (121 entries) | Medium | `client_mcp_surfaces.gd` will be a sizable file. Consider generating it from `ui_audit.md` via a build script, or loading from a JSON resource |
| Dialog state variants hard to automate | Medium | Many surfaces have states like "loading", "error", "with_data" that require specific server responses or timing. May need mock data injection for complete audit coverage |
| Context menus require input simulation | Medium | Right-click menus (on messages, channels, members) are created dynamically. `navigate_to_surface` would need to synthesize `InputEventMouseButton` at the correct position, which is fragile |
| Screenshot timing | Medium | Some surfaces have animations (modal open/close, drawer slide). `take_screenshot` should optionally wait N milliseconds after navigation to capture the settled state |
| Base64 image size | Low | Full-viewport PNGs at 1280x720 are ~50-200KB base64-encoded. MCP responses could be large. Consider optional JPEG compression or downscaling |
| Rate limiting not designed | Medium | Localhost-only reduces risk, but a runaway AI agent could flood requests. Consider per-second request cap in ClientMcp |
| No TLS on localhost | Low | Localhost traffic is not routable; TLS would require certificate management. Document as acceptable for local-only use |
| Web export incompatibility | Medium | TCPServer is not available in HTML5 exports. Web builds would need a different transport (e.g., JavaScript interop via `JavaScriptBridge`) or MCP disabled entirely |
| No per-tool granularity | Low | Current design uses tool groups, not individual tool toggles. Could add per-tool overrides later if users need finer control |
| No audit trail persistence | Low | Connection log is in-memory only. Could optionally write to a local log file for debugging |
| Android localhost networking | Medium | Android may restrict localhost server sockets depending on OS version. Needs testing on target devices |
| No SSE/streaming support | Low | Initial implementation uses request-response only. MCP spec supports server-sent events for streaming; can be added later |
| Token migration on profile export/import | Low | Exported profiles include the MCP token in encrypted config; re-importing on another machine works but user should rotate token |
| Dialog cleanup after screenshot | Medium | Dialogs opened via `open_dialog` need to be tracked and closed/freed before navigating to the next surface. ClientMcp should maintain a `_active_dialog` reference and call `queue_free()` on it before opening a new one |
| Viewport resize on Wayland/multi-monitor | Low | `DisplayServer.window_set_size()` behavior may differ across display servers. Actual size should be verified via the return value |
