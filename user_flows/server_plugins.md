# Server Plugins

## Overview

Server plugins allow individual accordserver instances to extend daccord with custom behavior: additional REST endpoints, WebSocket events, and Godot-side UI augmented by sandboxed Lua scripts. Plugins are strictly scoped to the server that installed them — no plugin can read data from or affect the UI of another connected server. The first supported plugin type is **Activities**: interactive experiences users can launch from within a voice channel (e.g., a two-player chess game), modeled after Discord Activities.

## User Steps

### Browsing available activities (Activity plugin type)

1. User joins a voice channel
2. A "Launch Activity" button appears in the voice bar (rocket icon)
3. User clicks "Launch Activity" → a modal lists available activities published by the server
4. Each activity card shows: icon, name, description, max participants, and a "Launch" button
5. User clicks "Launch" → activity opens in a panel alongside the voice channel view

### Starting an activity

1. Activity panel loads; the activity's Lua script is fetched from the server and executed in a sandboxed `LuaRuntime` node
2. The Lua script renders its UI into a dedicated `ActivityViewport` using Godot draw calls via the Lua bridge API
3. Other voice participants see a "Join Activity" prompt
4. Joining participants connect to the same activity session; the server broadcasts state via a plugin-specific WebSocket event

### Interacting within an activity (e.g., chess)

1. User makes a move → Lua script calls `Plugin.send_action({move: "e2e4"})` → client POSTs to the plugin's custom REST endpoint `POST /plugins/{plugin_id}/actions`
2. Server validates the move, updates game state, and broadcasts `plugin.event` via gateway with `{plugin_id, type: "state_update", data: {...}}`
3. All participants' Lua runtimes receive the event via `Plugin.on_event(callback)` and re-render the board

### Installing a plugin (server admin)

1. Admin opens Server Settings → Plugins tab
2. Admin uploads a `.daccord-plugin` bundle (ZIP containing `plugin.json` manifest + Lua scripts + optional assets)
3. Server registers the plugin, stores scripts, and broadcasts `plugin.installed` gateway event to all connected clients
4. Plugin appears in the Activities list (or other entry point) for all users on that server

### Uninstalling a plugin

1. Admin clicks "Uninstall" on a plugin
2. Server removes all plugin data and scripts
3. Gateway broadcasts `plugin.uninstalled {plugin_id}` → clients unload the Lua runtime for that plugin and close any open activity panels
4. All users actively in the activity receive a "This activity has ended" message and the panel closes

## Signal Flow

```
voice_bar.gd                  AppState                    Client / PluginManager
     |                              |                              |
     |-- launch_activity_pressed -->|                              |
     |                              |-- fetch_activities() ------->|
     |                              |                              |-- GET /plugins?type=activity
     |                              |<- activities_loaded(list) ---|
     |<-- activity_list_shown ------|                              |
     |   (modal with activity cards)|                              |
     |                              |                              |
     |-- user selects activity ----->|                              |
     |                              |-- launch_activity(id) ------>|
     |                              |                              |-- POST /plugins/{id}/sessions
     |                              |                              |-- fetch Lua script
     |                              |                              |-- create LuaRuntime
     |                              |<- activity_started(id) ------|
     |<-- activity_panel_opened ----|                              |
     |   (ActivityViewport shown)   |                              |
     |                              |                              |
     |   Lua: Plugin.send_action()  |                              |
     |------------------------------|----------------------------->|
     |                              |                              |-- POST /plugins/{id}/actions
     |                              |                              |
     |   Gateway: plugin.event      |                              |
     |                              |<- plugin_event(id, data) ----|
     |                              |   (from GatewaySocket)       |
     |                              |-- route to LuaRuntime ------>|
     |<-- LuaRuntime.on_event() ----|                              |
     |   (re-render UI in viewport) |                              |
     |                              |                              |
     |-- user leaves voice -------->|                              |
     |                              |-- cleanup_activity(id) ----->|
     |                              |                              |-- LuaRuntime.stop()
     |                              |                              |-- ActivityViewport freed
     |                              |<- activity_ended(id) --------|
     |<-- activity_panel_closed ----|                              |
```

### Plugin Installation Gateway Flow

```
Admin uploads plugin bundle
    -> POST /spaces/{space_id}/plugins (server validates, stores scripts)
    -> Gateway broadcasts: plugin.installed {plugin_id, manifest}
        -> GatewaySocket emits plugin_installed(manifest)
            -> PluginManager.on_plugin_installed(manifest)
                -> caches manifest in _plugin_cache[conn_index][plugin_id]
                -> AppState.plugins_updated emitted
                    -> Activities modal refreshes list

Admin uninstalls plugin
    -> DELETE /spaces/{space_id}/plugins/{plugin_id}
    -> Gateway broadcasts: plugin.uninstalled {plugin_id}
        -> PluginManager.on_plugin_uninstalled(plugin_id)
            -> tears down active LuaRuntime if running
            -> removes from _plugin_cache
            -> AppState.plugins_updated emitted
            -> AppState.activity_ended(plugin_id) emitted if activity was open
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST: list plugins, create/delete session, send action (new) |
| `addons/accordkit/models/plugin_manifest.gd` | `AccordPluginManifest` model: id, name, type, description, script_url, max_participants (new) |
| `addons/accordkit/gateway/gateway_socket.gd` | Add `plugin_installed`, `plugin_uninstalled`, `plugin_event` signals |
| `addons/accordkit/core/accord_client.gd` | Expose `plugins: PluginsApi`; re-emit plugin gateway events |
| `scripts/autoload/app_state.gd` | `plugins_updated`, `activity_started(plugin_id)`, `activity_ended(plugin_id)` signals |
| `scripts/autoload/client.gd` | Delegate plugin operations to a new `ClientPlugins` helper |
| `scripts/autoload/client_plugins.gd` | `ClientPlugins` helper: plugin cache, launch/stop activity, action dispatch (new) |
| `scripts/autoload/client_gateway_events.gd` | `on_plugin_installed`, `on_plugin_uninstalled`, `on_plugin_event` handlers (new) |
| `scripts/autoload/client_gateway.gd` | Wire plugin gateway signals → `ClientGatewayEvents` |
| `scenes/sidebar/voice_bar.gd` | Add "Launch Activity" button; connect to `AppState.activity_started/ended` |
| `scenes/sidebar/voice_bar.tscn` | Add rocket button node to `ButtonRow` |
| `scenes/plugins/activity_modal.gd` | Activity picker modal: fetches plugin list, shows cards, launches selection (new) |
| `scenes/plugins/activity_modal.tscn` | Modal scene (new) |
| `scenes/plugins/activity_panel.gd` | Side panel hosting `ActivityViewport` and the Lua runtime; shows join prompt (new) |
| `scenes/plugins/activity_panel.tscn` | Panel scene (new) |
| `scenes/plugins/lua_runtime.gd` | Sandboxed Lua VM node; exposes `Plugin.*` bridge API; executes server-fetched scripts (new) |
| `scenes/main/main_window.gd` | Manage `ActivityPanel` alongside `MessageView` in the content area |
| `scenes/main/main_window.tscn` | Add `ActivityPanel` node |
| `scenes/settings/plugins_settings.gd` | Admin plugin management page: upload, list, uninstall (new) |
| `scenes/settings/plugins_settings.tscn` | Plugins settings page scene (new) |

## Implementation Details

### Plugin Manifest Model (`plugin_manifest.gd`)

New `AccordPluginManifest extends RefCounted` with fields:

```gdscript
var id: String = ""
var name: String = ""
var type: String = ""          # "activity", "bot", "theme", "command"
var description: String = ""
var icon_url: String = ""      # nullable
var script_url: String = ""    # relative path on server CDN
var max_participants: int = 0  # 0 = unlimited
var version: String = ""
var permissions: Array = []    # declared capabilities the plugin requests
```

### PluginsApi REST Endpoints

New `addons/accordkit/rest/endpoints/plugins_api.gd`:

```gdscript
# List installed plugins for a space (optionally filter by type)
func list_plugins(space_id: String, type: String = "") -> RestResult
    # GET /spaces/{space_id}/plugins[?type=activity]

# Install a plugin (admin; multipart bundle upload)
func install_plugin(space_id: String, bundle_path: String) -> RestResult
    # POST /spaces/{space_id}/plugins (multipart/form-data)

# Uninstall a plugin (admin)
func delete_plugin(space_id: String, plugin_id: String) -> RestResult
    # DELETE /spaces/{space_id}/plugins/{plugin_id}

# Start an activity session in a voice channel
func create_session(plugin_id: String, channel_id: String) -> RestResult
    # POST /plugins/{plugin_id}/sessions
    # Returns: { session_id, participants: [] }

# End the current session (leave or close)
func delete_session(plugin_id: String, session_id: String) -> RestResult
    # DELETE /plugins/{plugin_id}/sessions/{session_id}

# Send a plugin action (e.g., game move)
func send_action(plugin_id: String, session_id: String, data: Dictionary) -> RestResult
    # POST /plugins/{plugin_id}/sessions/{session_id}/actions

# Fetch the Lua script content for a plugin
func get_script(plugin_id: String) -> RestResult
    # GET /plugins/{plugin_id}/script  (returns plain text)
```

### Gateway Signals (`gateway_socket.gd`)

Add to the signals section (after `interaction_create`):

```gdscript
signal plugin_installed(manifest: AccordPluginManifest)
signal plugin_uninstalled(plugin_id: String)
signal plugin_event(plugin_id: String, event_type: String, data: Dictionary)
```

Dispatch in `_dispatch_event()`:
```gdscript
"plugin.installed":  plugin_installed.emit(AccordPluginManifest.from_dict(data))
"plugin.uninstalled": plugin_uninstalled.emit(str(data.get("plugin_id", "")))
"plugin.event":      plugin_event.emit(str(data.get("plugin_id", "")),
                                        str(data.get("type", "")), data)
```

### AppState Additions

```gdscript
signal plugins_updated()
signal activity_started(plugin_id: String, channel_id: String)
signal activity_ended(plugin_id: String)
```

State:
```gdscript
var active_activity_plugin_id: String = ""
var active_activity_channel_id: String = ""
```

### ClientPlugins Helper (`client_plugins.gd`)

New `ClientPlugins extends RefCounted`. Instantiated in `Client._ready()` alongside `ClientVoice`:

```gdscript
# Plugin cache: conn_index -> { plugin_id -> manifest dict }
var _plugin_cache: Dictionary = {}

func fetch_plugins(conn_index: int, space_id: String) -> void
func launch_activity(plugin_id: String, channel_id: String) -> void
    # 1. Call PluginsApi.get_script() to fetch Lua source
    # 2. Call PluginsApi.create_session()
    # 3. Instantiate LuaRuntime with script text
    # 4. Emit AppState.activity_started(plugin_id, channel_id)
func stop_activity(plugin_id: String) -> void
    # 1. Call PluginsApi.delete_session()
    # 2. Call LuaRuntime.stop()
    # 3. Emit AppState.activity_ended(plugin_id)
func send_action(plugin_id: String, data: Dictionary) -> void
    # Routes Plugin.send_action() calls from Lua bridge
func on_plugin_installed(manifest: AccordPluginManifest, conn_index: int) -> void
func on_plugin_uninstalled(plugin_id: String, conn_index: int) -> void
func on_plugin_event(plugin_id: String, event_type: String, data: Dictionary) -> void
    # Routes to active LuaRuntime if plugin_id matches
```

### Lua Runtime Sandbox (`lua_runtime.gd`)

`LuaRuntime extends Node` wraps a Lua 5.4 VM via a GDExtension (e.g., `lua_gdextension`). The sandbox exposes only the `Plugin` table; all Godot engine APIs are blocked.

**Plugin bridge API available to Lua scripts:**

```lua
-- Rendering (draws into ActivityViewport via Godot CanvasItem calls)
Plugin.clear()
Plugin.draw_text(x, y, text, color)
Plugin.draw_rect(x, y, w, h, color)
Plugin.draw_image(x, y, image_id)  -- image_id registered during plugin install

-- State & actions
Plugin.send_action(data_table)     -- sends action to server REST endpoint
Plugin.get_state() -> table        -- last received state from plugin.event

-- Events
Plugin.on_event(type, callback)    -- register handler for plugin.event type

-- Participants
Plugin.get_participants() -> table  -- list of {user_id, display_name} in this activity

-- Timer
Plugin.set_interval(ms, callback)  -- recurring timer (capped at 100ms minimum)
Plugin.set_timeout(ms, callback)   -- one-shot timer
```

**Security constraints:**
- No file I/O, no network calls (all network goes through `Plugin.send_action` → client proxy)
- No access to Godot autoloads, scenes, or nodes outside the ActivityViewport
- Script execution time-limited per frame (configurable, default 2ms budget)
- Memory limit per runtime (default 8 MB)
- Each server connection gets its own VM; scripts from server A cannot call `Plugin` functions that affect server B's runtime

### Activity Panel UI (`activity_panel.gd`)

Shown alongside (or instead of) the `MessageView` when an activity is active. Layout:
- Header bar: activity name, icon, "Leave Activity" button, participant count
- Main area: `SubViewport` node that the LuaRuntime draws into
- Footer: participant avatars in a horizontal strip (same Avatar component used elsewhere)

Connects to:
- `AppState.activity_started` → `_on_activity_started(plugin_id, channel_id)`
- `AppState.activity_ended` → `_on_activity_ended(plugin_id)` → hides panel
- `AppState.voice_left` → calls `ClientPlugins.stop_activity()` if active

### Per-Server Isolation Mechanism

Isolation is enforced at three layers:

1. **Cache layer:** `ClientPlugins._plugin_cache` is keyed by `conn_index`. Plugins from connection 0 are never visible in connection 1's UI.
2. **LuaRuntime layer:** Each active activity holds a reference to its `conn_index`. `Plugin.send_action()` routes through `Client._connections[conn_index]` so REST calls always target the originating server.
3. **Gateway layer:** `on_plugin_event()` in `client_gateway_events.gd` receives the `conn_index` parameter (same pattern as all other gateway event handlers) and routes only to a runtime whose `conn_index` matches.

### Plugin Bundle Format (`.daccord-plugin`)

A ZIP archive with the following structure:

```
plugin.json          # manifest
scripts/
  main.lua           # entry-point script
  lib/               # optional additional Lua modules
assets/
  icon.png           # 64x64 activity icon
  images/            # optional images referenced by Plugin.draw_image()
```

`plugin.json` schema:
```json
{
  "id": "chess",
  "name": "Chess",
  "type": "activity",
  "description": "2-player chess game in your voice channel",
  "version": "1.0.0",
  "max_participants": 2,
  "permissions": ["voice_activity"],
  "entry_point": "scripts/main.lua"
}
```

### Server-Side Requirements (accordserver)

New routes needed in accordserver:

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/spaces/{space_id}/plugins` | List installed plugins |
| POST | `/spaces/{space_id}/plugins` | Install plugin (admin; bundle upload) |
| DELETE | `/spaces/{space_id}/plugins/{id}` | Uninstall plugin (admin) |
| GET | `/plugins/{id}/script` | Serve Lua script text (authenticated) |
| POST | `/plugins/{id}/sessions` | Create activity session |
| DELETE | `/plugins/{id}/sessions/{session_id}` | End session |
| POST | `/plugins/{id}/sessions/{session_id}/actions` | Send action |

Gateway events to implement:
- `plugin.installed` — broadcast to space when plugin is added
- `plugin.uninstalled` — broadcast to space when plugin is removed
- `plugin.event` — routed to session participants only (not whole space)

Plugin action routing: the server plugin handler receives `POST /plugins/{id}/sessions/{session_id}/actions`, passes the body to the plugin's server-side handler (e.g., a WebAssembly module or a registered webhook), and then broadcasts a `plugin.event` to all session participants.

## Implementation Status

- [ ] `AccordPluginManifest` model
- [ ] `PluginsApi` REST endpoints in AccordKit
- [ ] `plugin_installed` / `plugin_uninstalled` / `plugin_event` gateway signals in `gateway_socket.gd`
- [ ] AccordClient plugin signal re-emit and `plugins: PluginsApi` exposure
- [ ] AppState `plugins_updated`, `activity_started`, `activity_ended` signals
- [ ] `ClientPlugins` helper class
- [ ] `ClientGatewayEvents` plugin event handlers (`on_plugin_installed`, `on_plugin_uninstalled`, `on_plugin_event`)
- [ ] `ClientGateway` signal wiring for plugin signals
- [ ] `LuaRuntime` GDExtension (Lua 5.4 VM + bridge API)
- [ ] `ActivityPanel` scene (viewport host + participant strip)
- [ ] `ActivityModal` scene (activity picker from voice bar)
- [ ] Voice bar "Launch Activity" button
- [ ] `MainWindow` layout integration for `ActivityPanel`
- [ ] Admin Plugins settings page
- [ ] Plugin bundle format and server-side plugin storage
- [ ] accordserver REST routes for plugin management
- [ ] accordserver plugin action routing + session management
- [ ] accordserver gateway `plugin.*` event dispatch
- [ ] Per-server isolation enforced in `ClientPlugins` via `conn_index`
- [ ] Lua sandbox memory/CPU limits enforced in `LuaRuntime`

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No Lua GDExtension available | High | A Lua 5.4 GDExtension for Godot 4.x must be built or sourced (e.g., `luagdextension`); without this the entire client-side scripting layer cannot ship |
| No accordserver plugin subsystem | High | Server has no plugin routes, no session management, no bundle storage, and no `plugin.*` gateway events; entire backend must be built first |
| `interaction_create` handler is a stub | High | `client_gateway_events.gd` lines 95-98 handle `interaction_create` with `pass`; bot/plugin interactions need a real dispatch path |
| No plugin sandbox isolation test suite | High | Sandbox security properties (no FS access, no cross-server calls, CPU budget) need automated tests before plugins ship to users |
| No plugin signing / trust model | High | Server can serve arbitrary Lua; without code signing or an approval process, any space admin can push malicious scripts to all users of their server |
| `ChannelType` enum has no ACTIVITY type | Medium | `client_models.gd` line 7 enum has TEXT/VOICE/ANNOUNCEMENT/FORUM/CATEGORY; activities launched from voice don't need a new channel type, but a plugin-owned channel type may be needed for persistent activity channels |
| No plugin asset CDN integration | Medium | Plugin images/icons served via the plugin script endpoint; the existing CDN URL pattern (`conn.cdn_url`) needs to extend to plugin assets |
| Voice bar has no "Launch Activity" button | Medium | `voice_bar.tscn` currently has Mic/Deaf/Cam/Share/SFX/Settings/Disconnect; the rocket button and its signal wiring need to be added |
| No activity session state persistence | Medium | If the user closes and reopens the app during an active activity, there is no reconnect path; session recovery requires server-side session lookup |
| Max participants not enforced client-side | Low | `max_participants` in the manifest should grey out "Launch" when the voice channel already has a full session; requires polling or a `plugin.session_full` event |
| No activity join notification for late joiners | Low | Users who join a voice channel after an activity has started see no indication that an activity is running; a gateway `plugin.session_state` event or a voice state flag is needed |
| Lua `Plugin.draw_*` API scope | Low | The exact drawing API surface needs design validation: using Godot CanvasItem draw calls from Lua requires GDExtension hooks; alternatively, Lua could output a JSON scene description that a native renderer interprets (safer sandbox) |
