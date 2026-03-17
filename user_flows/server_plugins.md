# Server Plugins

Priority: 72
Depends on: None

## Overview

Server plugins allow individual accordserver instances to extend daccord with custom behavior: additional REST endpoints, WebSocket events, and client-side logic. Plugins are strictly scoped to the server that installed them — no plugin can read data from or affect the UI of another connected server.

Two plugin runtimes are supported:

- **Scripted plugins** — sandboxed Lua programs for simple activities (chess, polls, trivia). Written in Lua, executed in a sandboxed `LuaState` via [lua-gdextension](https://github.com/WilsonE/lua-gdextension). Only safe Lua standard libraries are loaded (base, coroutine, string, math, table) — io, os, package, debug, and ffi are blocked. No access to the filesystem, network, autoloads, or Godot engine internals.
- **Native plugins** — full GDScript scenes and resources for complex activities (emulators, collaborative editors). Downloaded as a bundle on first launch, cached locally, and instantiated as a Godot scene tree. Requires code signing (Ed25519) and explicit user trust approval.

The first supported plugin type is **Activities**: interactive experiences users can launch from within a voice channel. Activities use a **lobby system** with player/spectator roles and communicate via **LiveKit data channels** for low-latency real-time state sync.

### What this means for non-technical users

Think of plugins like mini-apps that a server admin can install. When you join a voice channel on a server with plugins, you might see options like "Play Chess" or "Launch Trivia." Clicking one opens a small interactive panel right inside daccord — no browser or extra software needed.

- **Scripted plugins** are lightweight and safe by design. They run in a sandboxed Lua environment that prevents them from accessing your files or personal data. These are ideal for simple games and interactive widgets.
- **Native plugins** are more powerful but require a higher level of trust. Before running one for the first time, daccord asks for your permission and verifies the plugin's digital signature to confirm it hasn't been tampered with.

Both types only work on the server that installed them. A plugin from Server A cannot see your activity on Server B.

### Why Lua?

Lua was chosen for the scripted plugin tier because:

1. **Proven embeddable language** — Lua is the industry standard for embedded game scripting. lua-gdextension provides a maintained, well-tested binding for Godot 4.5+.
2. **No compilation step** — Plugins are plain Lua source files, enabling faster iteration and transparent source auditing. No build toolchain needed.
3. **Lightweight** — The Lua VM has a very small memory footprint. Sandboxing is straightforward: only safe standard libraries are loaded (base, coroutine, string, math, table).
4. **Cross-platform** — Lua 5.4 runs on all platforms including WebAssembly. LuaJIT is available on desktop/mobile for higher performance.
5. **Broad ecosystem** — Lua has extensive documentation, tutorials, and a large community of game scripters.

## User Steps

### Browsing available activities

*Who this is for: any user in a voice channel.*

1. User joins a voice channel
2. A "Launch Activity" button appears in the voice bar (rocket icon, next to the existing microphone/camera/screen share buttons)
3. User clicks "Launch Activity" → a modal lists available activities published by the server
4. Each activity card shows:
   - Name and description
   - Runtime badge ("Scripted" or "Native") so users know the trust level
   - Max participants (e.g., "2 players max")
   - Version string
   - "Launch" button
5. User clicks "Launch" → activity opens in the voice view's spotlight area

### Starting a scripted activity

*Who this is for: any user launching a lightweight plugin (chess, trivia, polls).*

1. Activity panel loads; the plugin bundle ZIP is fetched from the server
2. The ZIP is extracted: entry Lua source, additional `.lua` modules, and assets (images/sounds)
3. A `LuaState` is created with only safe libraries enabled (no io, os, package, debug, ffi). The bridge `api` table is injected, providing drawing, networking, and state functions
4. The Lua program renders its UI into a dedicated `SubViewport` using drawing primitives (rectangles, circles, lines, text, images)
5. Other voice participants see a "Join Activity" prompt
6. Joining participants connect to the same activity session; the server broadcasts state via a `plugin.event` gateway event

**What happens under the hood (technical):** The plugin bundle ZIP is downloaded from the server via `GET /plugins/{id}/source` and extracted in memory. The entry Lua source, any additional `.lua` modules, and `assets/` directory contents are parsed. A `LuaState` is created by lua-gdextension with only safe standard libraries loaded (base, coroutine, string, math, table). The `ScriptedRuntime` node injects a bridge `api` table that provides drawing, state, networking, timer, asset, and audio functions. A sandboxed `require()` function loads bundled modules by name. The Lua code cannot access Godot singletons, the scene tree, or the filesystem — it can only interact through the bridge API.

### Starting a native activity

*Who this is for: users launching a complex plugin (emulator, collaborative editor).*

1. **Trust check (first time only):** If this native plugin has not been trusted, daccord shows a confirmation dialog: "This activity runs native code from [server name]. Trust this server's plugins?" with a "Trust & Run" / "Cancel" choice and an "Always trust plugins from this server" checkbox. This preference is saved per-server (or per-plugin) in the user's profile config
2. **Signature verification:** If the bundle is signed, the `plugin.sig` file is checked. (Full Ed25519 verification is stubbed — currently checks that the sig file exists)
3. **Download/cache:** `PluginDownloadManager` checks the local cache (`user://plugins/<server_id>/<plugin_id>/`):
   - If not cached or hash mismatch: download progress bar appears, bundle is fetched via `GET /plugins/{id}/bundle`, SHA-256 hash verified, ZIP extracted to cache directory
   - If cached and hash matches: skip download
4. The entry point scene (`entry_point` from manifest) is instantiated by `NativeRuntime` as a child node
5. The scene receives a `PluginContext` resource via `setup(context)` — the bridge API for data channels, participant info, session state, and file sharing
6. Activity enters `LOBBY` state — other voice participants see a "Join Activity" prompt

### Lobby phase

*Who this is for: all participants in an activity that uses the lobby system.*

1. Activity opens in `LOBBY` state; the host (user who launched the activity) sees a lobby panel with:
   - **Player slots** — numbered slots set by `max_participants` in the manifest (e.g., 2 for a chess game, 4 for a card game). Each slot is either empty or shows a user's display name
   - **Spectator list** — all joined users who haven't claimed a player slot
   - **"Start Activity" button** — visible only to the host, enabled when at least one player slot is filled
2. Joining participants default to `SPECTATOR` role
3. Users click "Claim Slot" → if a slot is available, their role changes to `PLAYER`. They can release the slot to go back to spectating
4. Host clicks "Start Activity" → session state moves to `RUNNING` via a gateway broadcast to all participants
5. Late joiners (users who join the voice channel after the activity started) see the activity in its current state and join as `SPECTATOR`

### Interacting within a scripted activity (e.g., chess)

*Who this is for: players and spectators in a scripted activity.*

1. User makes a move → the sandboxed script calls `api.send_action(Dictionary({move = "e2e4"}))` → the client POSTs to the plugin's REST endpoint `POST /plugins/{plugin_id}/sessions/{session_id}/actions`
2. The server validates the move (via its server-side plugin handler), updates game state, and broadcasts a `plugin.event` via the gateway with `{plugin_id, type: "state_update", data: {...}}`
3. All participants' sandboxed runtimes receive the event via the `_on_event(type, data)` callback and re-render the board

**For non-technical users:** You interact with scripted activities by clicking, typing, or pressing keys inside the activity panel. Your actions are sent to the server, which validates them (e.g., checks if a chess move is legal) and sends the updated game state to everyone. You don't need to worry about the technical details — it works like any other multiplayer game.

### Interacting within a native activity (e.g., NES emulator)

*Who this is for: players and spectators in a native activity.*

1. Host selects a ROM file from their local filesystem via a file dialog (the plugin calls `PluginContext.request_file()`, which sends a data channel request to the host)
2. Plugin reads the ROM into memory
3. Plugin sends the ROM to all participants via LiveKit reliable data channel (`PluginContext.send_file()`), with filename and data packed into a single payload
4. All participants receive the file and load it into their local emulator instance
5. Host starts the game → emulator begins running and streaming frame diffs
6. **Frame sync (host → all):** Emulator produces frame diffs (delta-compressed, typically 500B–2KB) sent via LiveKit **lossy** data channel at ~60Hz on topic `frame_sync`
7. **Input forwarding (players → host):** Player inputs (button state bitmask, ~4 bytes) sent via LiveKit **lossy** data channel at ~60Hz on topic `input`
8. **Keyframes (host → all):** Full frame state sent via LiveKit **reliable** data channel every N seconds (configurable) on topic `keyframe` for drift correction
9. Spectators receive frame diffs and render them but do not send input

**For non-technical users:** The host picks a game file from their computer, and the plugin automatically shares it with everyone in the activity. The host's computer runs the game and streams the video to all participants in real-time. Players send their button presses back to the host. Spectators just watch — they see the same game but can't control it.

### Installing a plugin (server admin)

*Who this is for: server administrators.*

1. Admin opens Server Settings → Plugins tab
2. Admin uploads a `.daccord-plugin` bundle (a ZIP file containing a `plugin.json` manifest, scripts/scenes, and optional assets like images and sounds)
3. Server validates the bundle: checks the manifest schema, verifies the code signature (native plugins require signing), and stores the contents
4. Server registers the plugin and broadcasts a `plugin.installed` gateway event to all connected clients
5. The plugin appears in the Activities list for all users on that server

**What's in a plugin bundle:** A `.daccord-plugin` file is a ZIP archive. At minimum it contains a `plugin.json` file describing the plugin (name, type, runtime, permissions). Scripted plugins include a `src/main.lua` Lua source file and optionally additional `.lua` modules and an `assets/` directory. Native plugins include GDScript scenes (`.tscn`) and scripts (`.gd`), plus a `plugin.sig` digital signature file. Both can include an `assets/` directory with images, sounds, and other resources.

### Uninstalling a plugin

*Who this is for: server administrators.*

1. Admin clicks "Uninstall" on a plugin in Server Settings → Plugins
2. Server removes all plugin data and scripts
3. Gateway broadcasts `plugin.uninstalled {plugin_id}` → clients unload the runtime for that plugin and close any open activity panels
4. All users actively in the activity receive a "This activity has ended" message and the panel closes
5. Local plugin cache (`user://plugins/<server_id>/<plugin_id>/`) is deleted on next cleanup pass

## Signal Flow

### Activity Launch (Scripted runtime)

```
voice_bar.gd                  AppState                    Client / ClientPlugins
     |                              |                              |
     |-- _on_activity_pressed() --->|                              |
     |   (opens ActivityModal)      |                              |
     |                              |                              |
     |-- activity_launched -------->|                              |
     |                              |-- launch_activity(id) ------>|
     |                              |                              |-- POST /sessions
     |                              |                              |-- update AppState vars
     |                              |<- activity_started(id) ------|
     |                              |                              |-- GET /plugins/{id}/source
     |                              |<- download_progress(0..1) ---|
     |                              |                              |-- extract ZIP bundle
     |                              |                              |-- create LuaState + ScriptedRuntime
     |                              |                              |
     |   video_grid.gd             |                              |
     |   _on_activity_started() -->|                              |
     |   (rebuild with lobby/      |                              |
     |    running/ended view)      |                              |
     |                              |                              |
     |   Script: api.send_action() |                              |
     |------------------------------|----------------------------->|
     |                              |                              |-- POST /plugins/{id}/actions
     |                              |                              |
     |   Gateway: plugin.event      |                              |
     |                              |<- on_plugin_event(data) -----|
     |                              |   (GatewaySocket -> AccordClient
     |                              |    -> ClientGateway -> ClientGatewayEvents
     |                              |    -> ClientPlugins)          |
     |                              |-- route to ScriptedRuntime ->|
     |                              |   _on_event() callback       |
     |                              |                              |
     |-- user leaves voice -------->|                              |
     |                              |-- _on_voice_left() --------->|
     |                              |                              |-- _clear_active_activity()
     |                              |<- activity_ended(id) --------|
```

### Activity Launch (Native runtime with lobby + data channels)

```
voice_bar.gd          AppState          ClientPlugins        PluginDownloadMgr     LiveKit
     |                    |                    |                    |                  |
     |-- launch --------->|                    |                    |                  |
     |                    |-- launch(id) ----->|                    |                  |
     |                    |                    |-- POST /sessions   |                  |
     |                    |<- activity_started |                    |                  |
     |                    |                    |-- download_bundle->|                  |
     |                    |                    |   (check cache)    |                  |
     |                    |                    |                    |-- GET /bundle     |
     |                    |<- download_progress(%) ----------------|                  |
     |                    |                    |<-- bundle dir -----|                  |
     |                    |                    |-- verify hash      |                  |
     |                    |                    |                    |                  |
     |                    |                    |-- trust check      |                  |
     |                    |                    |   (_show_trust_dialog if unsigned)    |
     |                    |                    |                    |                  |
     |                    |                    |-- create PluginContext                |
     |                    |                    |-- wire LiveKit adapter                |
     |                    |                    |-- NativeRuntime.start()               |
     |                    |                    |   (load scene, call setup(context))   |
     |                    |                    |                    |                  |
     |   video_grid.gd   |                    |                    |                  |
     |   _on_activity_started()               |                    |                  |
     |   (shows lobby in spotlight area)      |                    |                  |
     |                    |                    |                    |                  |
     |-- host: start ---->|                    |                    |                  |
     |                    |-- start_session -->|                    |                  |
     |                    |                    |-- PATCH /sessions/{id} {state:running}|
     |                    |<- session_state_changed("running") ----|                  |
     |                    |                    |                    |                  |
     |   Plugin: context.send_data()          |                    |                  |
     |                    |                    |--------------------|----------------->|
     |                    |                    |                    |  publish_data()  |
     |                    |                    |                    |                  |
     |   LiveKit: plugin_data_received        |                    |                  |
     |                    |                    |<-------------------|------ data ------|
     |                    |                    |-- route to NativeRuntime              |
     |                    |                    |   on_data_received()                  |
```

### Plugin Installation Gateway Flow

```
Admin uploads plugin bundle
    -> POST /spaces/{space_id}/plugins (server validates, stores scripts)
    -> Gateway broadcasts: plugin.installed {manifest}
        -> GatewaySocket emits plugin_installed(data)            (line 384)
            -> AccordClient re-emits plugin_installed(data)      (line 262)
                -> ClientGateway routes to ClientGatewayEvents   (line 82)
                    -> ClientGatewayEvents.on_plugin_installed   (line 102)
                        -> ClientPlugins.on_plugin_installed     (line 432)
                            -> caches manifest in _plugin_cache[conn_index][plugin_id]
                            -> AppState.plugins_updated emitted
                                -> ActivityModal refreshes list

Admin uninstalls plugin
    -> DELETE /spaces/{space_id}/plugins/{plugin_id}
    -> Gateway broadcasts: plugin.uninstalled {plugin_id}
        -> GatewaySocket emits plugin_uninstalled(data)          (line 386)
            -> AccordClient re-emits                             (line 263)
                -> ClientGateway -> ClientGatewayEvents          (line 107)
                    -> ClientPlugins.on_plugin_uninstalled       (line 443)
                        -> tears down active runtime if running
                        -> removes from _plugin_cache
                        -> AppState.plugins_updated emitted
                        -> AppState.activity_ended emitted if activity was open
```

### File Sharing via LiveKit Data Channel

```
Host (emulator plugin)            LiveKit SFU              Participants
     |                                |                         |
     |-- context.send_file(name,data) |                         |
     |   (reliable, topic:            |                         |
     |    "plugin:<id>:file:<name>")  |                         |
     |   payload: [4B name_len]       |                         |
     |           [name_bytes]         |                         |
     |           [file_data]          |                         |
     |                                |-- relay (reliable) ---->|
     |                                |                         |-- NativeRuntime
     |                                |                         |   _handle_file_data()
     |                                |                         |-- context.file_received
     |                                |                         |
     |-- frame diff (lossy, ~1KB) --->|                         |
     |   topic: "plugin:<id>:frame_sync"                        |
     |   @ 60Hz                       |-- relay (lossy) ------->|
     |                                |                         |-- render delta
     |                                |                         |
     |                                |<-- input (lossy, ~4B) --|
     |   topic: "plugin:<id>:input"   |                         |
     |<-- relay (lossy) --------------|                         |
     |-- apply input to emulator      |                         |
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST: list plugins, install, delete, download bundle/source, sessions, roles, actions |
| `addons/accordkit/models/plugin_manifest.gd` | `AccordPluginManifest` model with enums (`PluginRuntime`, `SessionState`, `ParticipantRole`), `from_dict()`/`to_dict()` serialization |
| `addons/accordkit/gateway/gateway_socket.gd` | `plugin_installed`, `plugin_uninstalled`, `plugin_event`, `plugin_session_state`, `plugin_role_changed` signals (lines 71-75); dispatch in `_dispatch_event()` (lines 384-393) |
| `addons/accordkit/core/accord_client.gd` | Exposes `plugins: PluginsApi` (line 121); re-emits gateway plugin signals (lines 262-266); also has `interactions: InteractionsApi` (line 120) |
| `scripts/autoload/app_state.gd` | `plugins_updated`, `activity_started`, `activity_ended`, `activity_download_progress`, `activity_session_state_changed`, `activity_role_changed` signals (lines 193-203); activity state vars (lines 233-237) |
| `scripts/autoload/client.gd` | `plugins: ClientPlugins` member (line 35), initialized in `_ready()` (line 184) |
| `scripts/autoload/client_plugins.gd` | Plugin cache, `launch_activity()`, `stop_activity()`, `start_session()`, `assign_role()`, `send_action()`, bundle extraction, trust dialog, gateway event handlers, LiveKit data routing, voice disconnect cleanup |
| `scripts/autoload/client_gateway_events.gd` | `on_plugin_installed` (line 102), `on_plugin_uninstalled` (line 107), `on_plugin_event` (line 112), `on_plugin_session_state` (line 117), `on_plugin_role_changed` (line 122) — all delegate to `_c.plugins`; also `on_interaction_create` stub (line 95) |
| `scripts/autoload/client_gateway.gd` | Wires AccordClient plugin signals → ClientGatewayEvents handlers (lines 82-91) |
| `scripts/autoload/livekit_adapter.gd` | `plugin_data_received` signal (line 14), `publish_plugin_data()` method (line 227), routes `plugin:*` topics to signal (line 402) |
| `scripts/autoload/plugin_download_manager.gd` | Download, SHA-256 verify, ZIP extract, cache native plugin bundles at `user://plugins/<server_id>/<plugin_id>/`; stub signature verification |
| `scripts/autoload/config.gd` | `get_plugin_trust()` / `set_plugin_trust()` (lines 681-688), `is_plugin_trust_all()` / `set_plugin_trust_all()` (lines 691-698) — per-server and per-plugin trust preferences |
| `scenes/sidebar/voice_bar.gd` | "Launch Activity" rocket button (line 31 `activity_btn`); `_on_activity_pressed()` opens ActivityModal (line 182); `_on_activity_launched()` calls `Client.plugins.launch_activity()` (line 188) |
| `scenes/sidebar/voice_bar.tscn` | `ActivityBtn` node in `ButtonRow` with rocket icon (line 91) |
| `scenes/plugins/activity_modal.gd` | Activity picker modal: fetches plugin list, filters to activities, shows cards with runtime badges/version/participant count, emits `activity_launched` signal |
| `scenes/plugins/activity_lobby.gd` | Lobby UI: player slot grid, spectator list, "Start Activity" button (host only), `start_requested` and `role_change_requested` signals |
| `scenes/plugins/scripted_runtime.gd` | Sandboxed Lua host: creates `LuaState` with safe libs only (bitmask `SAFE_LIBS`), injects bridge `api` table, manages `SubViewport` + `PluginCanvas`, forwards input/events, timer/sound management, bundle module `require()` support |
| `scenes/plugins/plugin_canvas.gd` | `PluginCanvas extends Node2D`: draw command queue, image/buffer management with limits (64 images, 4 buffers, 4096 commands/frame), color parsing (named, hex, RGBA array), coordinate clamping |
| `scenes/plugins/native_runtime.gd` | Native plugin host: loads entry scene from cache directory, injects `PluginContext` via `setup()`, forwards events and data channel messages, handles file data reassembly |
| `scenes/plugins/plugin_context.gd` | `PluginContext extends RefCounted`: bridge API for native plugins — `send_data()` with LiveKit topic namespacing, `send_file()` with filename+data packing, `get_participants()`, `get_role()`, `is_host()`, `send_action()`, `request_file()` |
| `scenes/plugins/plugin_trust_dialog.gd` | `PluginTrustDialog extends ModalBase`: trust/deny buttons, "Always trust plugins from this server" checkbox, `trust_granted(remember)` / `trust_denied` signals |
| `scenes/video/video_grid.gd` | Hosts activity UI in voice view spotlight area: lobby/running/ended state views, header with name/runtime/start/leave, footer with role label, viewport texture display with coordinate remapping for input, download progress bar |

## Implementation Details

### Plugin Manifest Model (`plugin_manifest.gd`)

`AccordPluginManifest extends RefCounted` with fields (lines 10-30):

```gdscript
var id: String = ""
var name: String = ""
var type: String = ""              # "activity", "bot", "theme", "command"
var runtime: String = ""           # "scripted" or "native"
var description: String = ""
var icon_url = null
var source_url = null              # Lua source URL (scripted plugins)
var entry_point = null             # scene path within bundle (native plugins)
var format: String = ""            # "lua" for scripted plugins
var bundle_size: int = 0
var bundle_hash: String = ""       # "sha256:<hex>" (native plugins)
var max_participants: int = 0      # 0 = unlimited
var max_spectators: int = 0        # 0 = unlimited; -1 = no spectators
var max_file_size: int = 0         # max user-supplied file size in bytes (0 = no file sharing)
var version: String = ""
var permissions: Array = []
var lobby: bool = false
var data_topics: Array = []
var signed: bool = false
var signature = null
var canvas_size: Array = [480, 360] # [width, height] for scripted plugins
```

Enums (line 6-8):
```gdscript
enum PluginRuntime { SCRIPTED, NATIVE }
enum SessionState { LOBBY, RUNNING, ENDED }
enum ParticipantRole { SPECTATOR, PLAYER }
```

`from_dict()` (line 33) handles both `canvas_size` as an array and legacy `canvas_width`/`canvas_height` keys. `to_dict()` (line 67) serializes all fields, omitting null optional fields.

### PluginsApi REST Endpoints (`plugins_api.gd`)

Fully implemented in `addons/accordkit/rest/endpoints/plugins_api.gd`:

```gdscript
# List installed plugins for a space (optionally filter by type)
func list_plugins(space_id: String, type: String = "") -> RestResult     # line 10
    # GET /spaces/{space_id}/plugins[?type=activity]
    # Deserializes array via AccordPluginManifest.from_dict

# Install a plugin (admin; multipart manifest + optional bundle)
func install_plugin(space_id: String, manifest_dict: Dictionary,
    bundle_data: PackedByteArray, filename: String) -> RestResult        # line 21
    # POST /spaces/{space_id}/plugins (multipart/form-data)

# Uninstall a plugin (admin)
func delete_plugin(space_id: String, plugin_id: String) -> RestResult   # line 31

# Download the plugin bundle ZIP (scripted: Lua source; native: full bundle)
func get_source(plugin_id: String) -> RestResult                        # line 38
    # GET /plugins/{plugin_id}/source (returns raw PackedByteArray)

func get_bundle(plugin_id: String) -> RestResult                        # line 45
    # GET /plugins/{plugin_id}/bundle (returns raw PackedByteArray)

# Session management
func create_session(plugin_id: String, channel_id: String) -> RestResult  # line 52
func delete_session(plugin_id: String, session_id: String) -> RestResult  # line 61
func update_session_state(plugin_id: String, session_id: String,
    state: String) -> RestResult                                          # line 69
func assign_role(plugin_id: String, session_id: String,
    user_id: String, role: String) -> RestResult                          # line 79
func send_action(plugin_id: String, session_id: String,
    data: Dictionary) -> RestResult                                       # line 88
```

### Gateway Signals (`gateway_socket.gd`)

Declared at lines 71-75:
```gdscript
signal plugin_installed(data: Dictionary)
signal plugin_uninstalled(data: Dictionary)
signal plugin_event(data: Dictionary)
signal plugin_session_state(data: Dictionary)
signal plugin_role_changed(data: Dictionary)
```

Dispatched in `_dispatch_event()` at lines 384-393:
```gdscript
"plugin.installed":      plugin_installed.emit(data)
"plugin.uninstalled":    plugin_uninstalled.emit(data)
"plugin.event":          plugin_event.emit(data)
"plugin.session_state":  plugin_session_state.emit(data)
"plugin.role_changed":   plugin_role_changed.emit(data)
```

### AppState Additions

Signals (lines 193-203):
```gdscript
signal plugins_updated()
signal activity_started(plugin_id: String, channel_id: String)
signal activity_ended(plugin_id: String)
signal activity_download_progress(plugin_id: String, progress: float)
signal activity_session_state_changed(plugin_id: String, state: String)
signal activity_role_changed(plugin_id: String, user_id: String, role: String)
```

State variables (lines 233-237):
```gdscript
var active_activity_plugin_id: String = ""
var active_activity_channel_id: String = ""
var active_activity_session_id: String = ""
var active_activity_session_state: String = ""  # "lobby", "running", "ended"
var active_activity_role: String = ""            # "player", "spectator"
```

### ClientPlugins Helper (`client_plugins.gd`)

`ClientPlugins extends RefCounted`, instantiated in `Client._ready()` (line 184). Full implementation with:

**State (lines 9-19):**
```gdscript
var _plugin_cache: Dictionary = {}    # conn_index -> { plugin_id -> manifest dict }
var _active_runtime: Node = null       # ScriptedRuntime or NativeRuntime
var _active_session_id: String = ""
var _active_conn_index: int = -1
var _scripted_runtime_class = null     # loaded on demand
var _native_runtime_class = null       # loaded on demand
var _download_manager: PluginDownloadManager = null
```

**Key methods:**
- `fetch_plugins(conn_index, space_id)` (line 29) — fetches and caches plugin manifests via REST
- `get_plugins(conn_index)` (line 47) — returns cached manifests as Array of Dictionaries
- `get_plugin(plugin_id)` (line 53) — searches all connections for a plugin
- `launch_activity(plugin_id, channel_id)` (line 71) — creates session, updates AppState, dispatches to scripted or native runtime preparation
- `_download_and_prepare_scripted_runtime()` (line 117) — downloads bundle ZIP, extracts Lua source/modules/assets via `_extract_bundle()`, creates `ScriptedRuntime` node
- `_extract_bundle(zip_bytes, manifest)` (line 174) — extracts entry Lua source, `.lua` modules, and `assets/` from ZIP; returns `{lua_source, modules, assets}`
- `_download_and_prepare_native_runtime()` (line 224) — downloads via `PluginDownloadManager`, performs trust check, creates `PluginContext`, wires LiveKit adapter, creates `NativeRuntime` node
- `_show_trust_dialog()` (line 284) — shows `PluginTrustDialog`, waits for user response, persists trust preference
- `stop_activity(plugin_id)` (line 349) — deletes session, clears state
- `start_session()` (line 365) — PATCHes session state to "running"
- `assign_role(user_id, role)` (line 385) — POSTs role assignment
- `send_action(plugin_id, data)` (line 402) — POSTs game action
- `get_activity_viewport_texture()` (line 418) — returns active runtime's viewport texture
- `forward_activity_input(event)` (line 425) — forwards input to active runtime

**Gateway handlers (lines 432-498):**
- `on_plugin_installed(data, conn_index)` — parses manifest, caches, emits `plugins_updated`
- `on_plugin_uninstalled(data, conn_index)` — removes from cache, tears down active if matching
- `on_plugin_event(data, conn_index)` — routes to active runtime's `on_plugin_event()`
- `on_plugin_session_state(data, conn_index)` — updates AppState, notifies native context, handles "ended"
- `on_plugin_role_changed(data, conn_index)` — updates local role, updates participant lists on both runtime types

**Voice disconnect cleanup (line 524):**
`_on_voice_left()` clears active activity and emits `activity_ended`.

**LiveKit data routing (line 333):**
`_on_livekit_data_received()` strips the `plugin:<id>:` topic prefix and routes to the active runtime's `on_data_received()`.

### Plugin Download Manager (`plugin_download_manager.gd`)

`PluginDownloadManager extends RefCounted`:

- `is_cached(server_id, plugin_id, expected_hash)` (line 18) — checks `.bundle_hash` file in cache dir
- `download_bundle(conn_index, plugin_id, manifest)` (line 37) — downloads ZIP, validates size (50 MB max, line 8), verifies SHA-256 hash, extracts to cache, stub signature verification, writes hash file
- `clear_cache(server_id, plugin_id)` (line 114) — removes cached bundle directory
- `_server_id_for_conn(conn)` (line 128) — uses `space_id` or URL hash as server identifier
- `_extract_zip(zip_data, dest_dir)` (line 148) — writes temp file, reads via ZIPReader, extracts to destination
- `_verify_signature(dir_path, server_id)` (line 191) — **stub**: checks `plugin.sig` exists, returns true. Full Ed25519 verification not yet implemented

### Scripted Runtime (`scripted_runtime.gd`)

`ScriptedRuntime extends Node` hosts a sandboxed Lua program using lua-gdextension. The Lua source is downloaded from the server as a ZIP bundle, extracted, and executed in a `LuaState` with only safe standard libraries enabled. The runtime injects a bridge `api` table that provides the only interface between the Lua code and the host application.

**How lua-gdextension works:**

lua-gdextension is a GDExtension for Godot 4.5+ that embeds a Lua 5.4 (or LuaJIT) interpreter. Lua states can be configured to load only specific standard libraries, providing a natural sandboxing mechanism — unsafe libraries (io, os, package, debug, ffi) are simply not loaded.

For daccord, this means:
- Plugin source is plain Lua (`*.lua` files)
- Only safe Lua libraries are loaded: base, coroutine, string, math, table (bitmask `SAFE_LIBS = 1|4|8|32|64`, line 13)
- The `ScriptedRuntime` injects a bridge `api` table as the only host interface
- All Godot APIs (filesystem, network, autoloads, scene tree) are unreachable from Lua code

**Startup flow (`start()`, line 58):**

1. Parse `canvas_size` from manifest, clamp to 64–1920 width and 64–1080 height (lines 65-73)
2. Create `SubViewport` with `UPDATE_ALWAYS` mode (lines 75-79)
3. Create `PluginCanvas` as sole child of viewport (lines 81-83)
4. Check `ClassDB.class_exists(&"LuaState")` — fails gracefully if addon missing (line 85)
5. Create `LuaState` via `ClassDB.instantiate(&"LuaState")` (line 92)
6. Open only safe libraries: `_lua.open_libraries(SAFE_LIBS)` (line 101)
7. Inject bridge API table via `_inject_bridge_api()` (line 104)
8. Execute plugin source: `_lua.do_string(lua_source, "plugin")` (line 107)
9. Cache lifecycle functions: `_ready`, `_draw`, `_input`, `_on_event` (lines 116-119)
10. Call `_ready()` callback (line 122)
11. Enable per-frame `_process()` which calls `_draw()` each frame (line 165)

**Rendering architecture:**

```
VideoGrid (voice view spotlight area)
 +-- TextureRect (displays viewport texture, with coordinate remapping)
     +-- SubViewport (canvas_size, owned by ScriptedRuntime)
         +-- PluginCanvas (Node2D, sole draw target)
             +-- all api.draw_* calls render here via command queue
```

Each frame (line 165): `_canvas.clear_commands()` → call Lua `_draw()` → `_canvas.flush()` (triggers `queue_redraw()`).

**Confinement guarantees:**

- **Library-level isolation:** Only safe Lua standard libraries are loaded. The io, os, package, debug, and ffi modules are never available
- **API whitelisting:** Only the `api.*` functions are injected into the Lua state. All Godot classes and methods are inaccessible
- **SubViewport confinement:** The `SubViewport` uses `render_target_update_mode = ALWAYS` and is parented to the `ScriptedRuntime` node, not the root
- **Coordinate clamping:** All coordinate arguments are clamped to canvas bounds (lines 204-209 in `plugin_canvas.gd`)
- **Command limit:** Max 4096 draw commands per frame (line 9 in `plugin_canvas.gd`)
- **Input confinement:** Input events are coordinate-remapped by `video_grid.gd` (lines 561-584) before forwarding to the runtime
- **Per-server isolation:** Each server connection gets its own `LuaState` instance; plugins from server A cannot interact with server B's runtime

**Plugin bridge API (injected as the `api` table, `_inject_bridge_api()` line 260):**

```lua
-- Lifecycle callbacks (defined by the plugin, called by the runtime)
function _draw()             -- called once per frame; all draw calls go here
function _ready()            -- called once after source loads
function _input(event)       -- called on user input within the activity viewport
                             -- event = {type, key, pressed, position_x, position_y, ...}
function _on_event(type, data) -- called on server action broadcasts

-- Canvas info (read-only)
api.canvas_width              -- viewport width in pixels (e.g., 480)
api.canvas_height             -- viewport height in pixels (e.g., 360)

-- Drawing primitives (only valid inside _draw; all coords clamped to canvas bounds)
api.clear()
api.draw_rect(x, y, w, h, color, filled)
api.draw_circle(x, y, radius, color)
api.draw_line(x1, y1, x2, y2, color, width)
api.draw_text(x, y, text, color, font_size)
api.draw_pixel(x, y, color)

-- Image / sprite support
api.load_image(data)              -- load image from PackedByteArray, returns handle
api.draw_image(handle, x, y)
api.draw_image_region(handle, x, y, sx, sy, sw, sh)
api.draw_image_scaled(handle, x, y, w, h)

-- Frame buffer (direct pixel manipulation for emulator-style rendering)
api.create_buffer(width, height)         -- returns handle
api.set_buffer_pixel(handle, x, y, color)
api.set_buffer_data(handle, data)        -- bulk-set from flat RGBA byte array
api.draw_buffer(handle, x, y)
api.draw_buffer_scaled(handle, x, y, w, h)

-- State & actions
api.send_action(data)            -- sends action to server REST endpoint
api.get_state()                  -- returns plugin manifest dict
api.get_participants()           -- list of {user_id, display_name, role}
api.get_participant_count()      -- number of participants
api.get_participant(index)       -- single participant by 0-based index
api.get_role()                   -- "player" or "spectator"
api.get_user_id()                -- current user's ID

-- Timers
api.set_interval(callback_name, ms)   -- recurring (capped at 16ms min for 60fps)
api.set_timeout(callback_name, ms)    -- one-shot
api.clear_timer(timer_id)

-- Assets (bundled files from the ZIP)
api.read_asset(path)             -- returns PackedByteArray for "assets/<path>"

-- Audio
api.load_sound(ogg_data)         -- load OGG Vorbis from PackedByteArray, returns handle
api.play_sound(handle)
api.stop_sound(handle)

-- Lua-to-Godot type constructors (injected as global functions)
Dictionary(t)                    -- converts Lua table to GDScript Dictionary
Array(t)                         -- converts Lua table (1-indexed) to GDScript Array
require(name)                    -- loads bundled .lua modules by name (sandboxed)
print(...)                       -- overridden to log as "[plugin_id] message"
```

**Image and buffer limits (from `plugin_canvas.gd` lines 7-9):**

| Resource | Limit | Reason |
|----------|-------|--------|
| Cached images | 64 max (`MAX_IMAGES`) | Prevents unbounded memory growth |
| Pixel buffers | 4 max (`MAX_BUFFERS`) | Enough for double-buffering + scratch |
| Draw commands per frame | 4096 (`MAX_COMMANDS_PER_FRAME`) | Prevents frame stalls |
| Sounds | 16 max (`MAX_SOUNDS` in scripted_runtime.gd line 9) | Limits audio resource usage |

**Color parsing (`_parse_color()`, plugin_canvas.gd line 315):**
Accepts `Color` objects, named strings ("white", "black", "red", "green", "blue", "yellow", "transparent"), HTML hex strings, or RGBA float arrays `[r, g, b]` / `[r, g, b, a]`.

**Lua → GDScript type conversion:**
`_dict_to_lua()` (line 224) recursively converts GDScript Dictionaries to native Lua tables. `_array_to_lua()` (line 238) converts Arrays to 1-indexed Lua tables using a helper function. `Dictionary()` and `Array()` global functions (injected via Lua code at line 407) convert in the reverse direction.

### Native Runtime (`native_runtime.gd`)

`NativeRuntime extends Node` hosts a GDScript scene instantiated from the cached plugin bundle. Unlike the scripted sandbox, native plugins run as regular Godot nodes with full engine access. Security relies on code signing and user trust rather than VM isolation.

**Lifecycle:**

```gdscript
func start(bundle_dir, entry_point, context) -> bool    # line 21
    # 1. Build scene path from bundle_dir + entry_point
    # 2. Check ResourceLoader.exists() then load() the PackedScene
    # 3. instantiate() -> add as child
    # 4. Call scene.setup(context) if the method exists

func stop() -> void                                      # line 59
    # 1. Call scene.teardown() if it exists
    # 2. queue_free() the scene instance

func on_plugin_event(event_type, data) -> void           # line 75
    # Forward to scene.on_plugin_event() if it exists

func on_data_received(sender_id, topic, payload) -> void # line 83
    # If topic starts with "file:": parse filename+data, emit context.file_received
    # Otherwise: emit context.data_received(sender_id, topic, payload)
```

**File data format (line 108):** `[4 bytes: filename_length_u32][filename_utf8][file_data]`

### Plugin Context (`plugin_context.gd`)

`PluginContext extends RefCounted` — the bridge API injected into native plugin scenes:

```gdscript
# Signals the plugin scene can connect to (lines 8-13)
signal data_received(sender_id: String, topic: String, payload: PackedByteArray)
signal file_received(sender_id: String, filename: String, data: PackedByteArray)
signal session_state_changed(new_state: String)
signal participant_joined(user_id: String, role: String)
signal participant_left(user_id: String)
signal role_changed(user_id: String, new_role: String)

# Identity (lines 16-19)
var plugin_id: String
var session_id: String
var conn_index: int
var local_user_id: String

# Session (lines 22-24)
var session_state: String          # "lobby", "running", "ended"
var participants: Array            # [{user_id, role, display_name}]
var host_user_id: String

# Data channel methods (lines 36-62)
func send_data(topic, payload, reliable, destination_ids) -> void
    # Wraps LiveKitAdapter.publish_plugin_data()
    # Automatically prefixes topic with "plugin:<plugin_id>:"

func send_file(filename, data, destination_ids) -> void
    # Packs filename + data into single payload, sends on "file:<name>" topic

# Participant info (lines 66-80)
func get_participants() -> Array
func get_role(user_id) -> String
func is_host() -> bool

# Action dispatch (line 84)
func send_action(data) -> void     # Delegates to ClientPlugins.send_action()

# File request (line 90)
func request_file(filename) -> void  # Sends data channel request to host
```

### LiveKit Data Channel Integration

The plugin system uses LiveKit data channels (exposed by godot-livekit) for all real-time native plugin communication. This avoids routing high-frequency data through the accordserver gateway.

**LiveKitAdapter additions (livekit_adapter.gd):**

- `plugin_data_received` signal (line 14): emitted when data arrives on a `plugin:*` topic
- `publish_plugin_data(data, reliable, topic, destinations)` (line 227): delegates to `_room.local_participant.publish_data()`
- Data routing (line 402): incoming data on `plugin:*` topics is routed to `plugin_data_received` signal

**Topic conventions for plugins:**

All plugin data channel messages use a topic prefix of `plugin:<plugin_id>:` to namespace them. The `PluginContext` methods handle this transparently.

| Topic | Direction | Mode | Payload | Rate |
|-------|-----------|------|---------|------|
| `plugin:<id>:frame_sync` | Host -> all | Lossy | Delta-compressed frame diff | ~60 Hz |
| `plugin:<id>:keyframe` | Host -> all | Reliable | Full frame state | Every 2-5 sec |
| `plugin:<id>:input` | Player -> host | Lossy | Button state bitmask | ~60 Hz |
| `plugin:<id>:file:<name>` | Host -> all | Reliable | [4B name_len][name][data] | Burst |
| `plugin:<id>:state` | Host -> all | Reliable | Serialized game state | On change |
| `plugin:<id>:rpc` | Any -> any | Reliable | Request/response | On demand |
| `plugin:<id>:file_request` | Any -> host | Reliable | Filename UTF-8 | On demand |

### Activity UI in Video Grid (`video_grid.gd`)

The activity panel was removed as a standalone scene. Instead, the voice view's `VideoGrid` hosts activity UI in its spotlight area (lines 51-65, 400-584).

**Signal connections (lines 51-65):**
- `AppState.activity_started` → `_on_activity_started()` — stores plugin_id, manifest, host flag, rebuilds grid
- `AppState.activity_ended` → `_on_activity_ended()` — clears state, rebuilds
- `AppState.activity_session_state_changed` → `_on_activity_state_changed()` — rebuilds
- `AppState.activity_role_changed` → `_on_activity_role_changed()` — updates role label
- `AppState.activity_download_progress` → `_on_activity_download_progress()` — updates progress bar

**`_rebuild_activity(tiles)` (line 400):** In `FULL_AREA` mode, if an activity is active, it takes priority over video spotlight. Layout:

- **Header** (`_build_activity_header()`, line 469): activity name, runtime badge, "Start" button (host in lobby), "Leave" button
- **Content area** (line 416): state-dependent:
  - `"lobby"`: instantiates `ActivityLobbyScript` with player slot grid and spectator list
  - `"running"`: `TextureRect` displaying the runtime's `ViewportTexture`
  - `"ended"`: centered "Activity ended." label
- **Progress bar** (line 452): hidden by default, shown during bundle download
- **Footer** (`_build_activity_footer()`, line 528): shows current role ("Role: Player" / "Role: Spectator")
- **Participant grid** below spotlight: video tiles for all voice participants

**Input coordinate remapping (`_on_activity_viewport_input()`, line 561):**
Mouse events are transformed from `TextureRect` coordinates to canvas coordinates, accounting for aspect-ratio scaling and centering offset. The remapped event is forwarded to `Client.plugins.forward_activity_input()`.

### Activity Lobby UI (`activity_lobby.gd`)

`ActivityLobby extends VBoxContainer` shown when session state is `"lobby"`:

- Title "Lobby" and status label ("Waiting for players..." / "N player(s) joined")
- `_slots_grid: GridContainer` with 2 columns showing player slots (line 41)
- `_spectator_list: VBoxContainer` below (line 53)
- "Start Activity" button: visible only to host, disabled until >= 1 player (lines 58-68)
- `update_participants(participants)` (line 79): rebuilds slots and spectator list, enables/disables start button
- Signals: `start_requested()`, `role_change_requested(user_id, role)`

### Plugin Trust Dialog (`plugin_trust_dialog.gd`)

`PluginTrustDialog extends ModalBase`:

- Warning text explaining native plugin risks (lines 23-32)
- "This plugin is not signed." label in error color (lines 35-41)
- "Always trust plugins from this server" checkbox (lines 43-45)
- "Cancel" and "Trust & Run" buttons (lines 52-68)
- Signals: `trust_granted(remember: bool)`, `trust_denied()`

### Activity Modal (`activity_modal.gd`)

`ActivityModal extends ModalBase`:

- Title "Activities", 480px wide (line 16)
- Loading label, empty state label, scrollable list (lines 18-43)
- Connects to `AppState.plugins_updated` for live refresh (line 45)
- `_refresh_list()` (line 54): fetches plugins via `Client.plugins.get_plugins()`, filters to `type == "activity"`, creates cards
- Activity cards (line 79): `PanelContainer` with name, description, runtime badge, participant count, version, "Launch" button
- On launch: emits `activity_launched(plugin_id, channel_id)` and closes

### Per-Server Isolation Mechanism

*Why this matters: if you're connected to multiple servers, plugins from one server must never be able to access data from another server.*

Isolation is enforced at four layers:

1. **Cache layer:** `ClientPlugins._plugin_cache` is keyed by `conn_index`. Plugins from connection 0 are never visible in connection 1's UI. Plugin bundle cache is keyed by `server_id` under `user://plugins/`.
2. **Runtime layer:** Each active activity holds a reference to its `conn_index`. `PluginContext` methods route through `Client._connections[conn_index]` so REST calls always target the originating server. Data channel topics are prefixed with `plugin:<plugin_id>:` which is globally unique per server.
3. **Gateway layer:** `on_plugin_event()` in `client_gateway_events.gd` receives the `conn_index` parameter (same pattern as all other gateway event handlers) and routes only to a runtime whose `conn_index` matches.
4. **Data channel layer:** LiveKit rooms are per-voice-channel, which are per-server. Plugin data channel messages never cross server boundaries because the LiveKit room itself is scoped to a single server's voice channel.

### Plugin Bundle Format (`.daccord-plugin`)

A ZIP archive with the following structure:

**Scripted plugin:**
```
plugin.json          # manifest (runtime: "scripted")
src/main.lua         # entry Lua source file (path set by "entry_point" or default)
src/lib/             # optional additional .lua modules (loaded via require())
assets/
  icon.png           # 64x64 activity icon
  images/            # optional images (api.read_asset() + api.load_image())
  sounds/            # optional audio clips (api.read_asset() + api.load_sound())
```

**Native plugin:**
```
plugin.json          # manifest (runtime: "native")
plugin.sig           # detached Ed25519 signature over plugin.json + all files
scenes/
  emulator.tscn      # entry-point scene
  lobby.tscn         # optional custom lobby scene
scripts/
  emulator.gd        # main logic
  input_mapper.gd    # input handling
  frame_encoder.gd   # frame diff encoding/decoding
assets/
  icon.png           # 64x64 activity icon
  shaders/           # optional shaders
```

**`plugin.json` schema (unified):**
```json
{
  "id": "nes-emulator",
  "name": "NES Emulator",
  "type": "activity",
  "runtime": "native",
  "description": "Play NES games together in voice chat",
  "version": "1.0.0",
  "entry_point": "scenes/emulator.tscn",
  "max_participants": 2,
  "max_spectators": 0,
  "max_file_size": 1048576,
  "lobby": true,
  "permissions": ["voice_activity", "data_channel", "local_file_read"],
  "data_topics": ["frame_sync", "keyframe", "input", "state"],
  "bundle_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

### Plugin Signing and Trust Model

**For non-technical users:** Plugin signing works like a seal on a letter — it proves the plugin hasn't been tampered with since the developer created it. When you see "Signed by [developer]" in the activity picker, it means the plugin's code matches what the developer originally uploaded. Unsigned native plugins trigger a trust dialog asking for your permission.

**For developers and admins:**

Native plugins execute arbitrary GDScript in the client process. Unlike scripted plugins (which run in a sandboxed Lua VM with no engine access), native plugins have full access to the Godot API within their scene subtree. A code signing system is required to prevent malicious plugins.

**Current implementation:**

1. `PluginDownloadManager._verify_signature()` (line 191) is a **stub** — it checks that `plugin.sig` exists but does not perform actual Ed25519 verification
2. `PluginTrustDialog` gates execution of unsigned native plugins (shows warning + trust/deny choice)
3. Per-server trust stored via `Config.get_plugin_trust()` / `Config.set_plugin_trust()` (config.gd lines 681-688)
4. "Trust all from this server" via `Config.is_plugin_trust_all()` / `Config.set_plugin_trust_all()` (config.gd lines 691-698)

**Trust levels:**

| Level | Description | Requirements |
|-------|-------------|--------------|
| Unsigned | No signature | Scripted plugins: allowed (Lua sandbox). Native plugins: trust dialog shown |
| Server-signed | Signed by the server admin's key | Admin has verified the plugin manually |
| Developer-signed | Signed by a registered developer key | Developer key is registered with the server |

### Scripted vs Native: Choosing the Right Runtime

*A guide for plugin developers.*

| Factor | Scripted | Native |
|--------|----------|--------|
| **Language** | Lua (executed in sandboxed LuaState) | Full GDScript + scenes |
| **Isolation** | Lua VM sandbox (safe libraries only, API-whitelisted) | Code signing + user trust |
| **Rendering** | `api.draw_*` primitives into a SubViewport canvas | Full Godot scene tree (Control, Node2D, etc.) |
| **Data exchange** | `api.send_action()` → server REST → `plugin.event` gateway broadcast | LiveKit data channels (peer-to-peer, low-latency) |
| **File sharing** | Not supported | `PluginContext.send_file()` via LiveKit data channel |
| **Custom shaders** | Not supported | Supported (bundled in `assets/shaders/`) |
| **Multiple scenes** | Not supported (single entry + modules) | Supported (bundle contains multiple `.tscn` files) |
| **Bundled modules** | Yes (`.lua` files loaded via `require()`) | N/A (GDScript `load()`) |
| **Bundled assets** | Yes (`api.read_asset()`) | Yes (loaded from cache directory) |
| **Signing required** | No | No (but trust dialog shown for unsigned) |
| **User trust prompt** | No | Yes (first-run confirmation dialog) |
| **Best for** | Board games, card games, polls, trivia, simple arcade games, interactive widgets | Emulators, collaborative editors, complex visualizations, anything needing LiveKit data channels |
| **Max complexity** | ~2,000 lines of Lua (practical limit due to API surface) | Unlimited |
| **Bundle size** | Typically <100 KB (Lua source + assets) | Up to 50 MB (configurable server limit) |

### Server-Side Requirements (accordserver)

New routes needed in accordserver:

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/spaces/{space_id}/plugins` | List installed plugins |
| POST | `/spaces/{space_id}/plugins` | Install plugin (admin; bundle upload) |
| DELETE | `/spaces/{space_id}/plugins/{id}` | Uninstall plugin (admin) |
| GET | `/plugins/{id}/source` | Serve plugin bundle ZIP (scripted; authenticated) |
| GET | `/plugins/{id}/bundle` | Serve full plugin bundle ZIP (native; authenticated) |
| POST | `/plugins/{id}/sessions` | Create activity session (returns session_id, state) |
| DELETE | `/plugins/{id}/sessions/{session_id}` | End session |
| PATCH | `/plugins/{id}/sessions/{session_id}` | Update session state (host only) |
| POST | `/plugins/{id}/sessions/{session_id}/roles` | Assign participant role |
| POST | `/plugins/{id}/sessions/{session_id}/actions` | Send action (scripted plugins) |

Gateway events to implement:
- `plugin.installed` — broadcast to space when plugin is added
- `plugin.uninstalled` — broadcast to space when plugin is removed
- `plugin.event` — routed to session participants only (not whole space)
- `plugin.session_state` — broadcast to session participants when state changes (lobby -> running -> ended)
- `plugin.role_changed` — broadcast to session participants when a role assignment changes

Plugin action routing: the server plugin handler receives `POST /plugins/{id}/sessions/{session_id}/actions`, passes the body to the plugin's server-side handler (e.g., a WebAssembly module or a registered webhook), and then broadcasts a `plugin.event` to all session participants. Native plugins bypass this entirely — their data flows through LiveKit data channels, not the server.

### Worked Example: Chess Activity (Scripted Plugin)

This section walks through the complete lifecycle of a simple chess plugin to illustrate how the scripted runtime works.

**Plugin bundle contents:**
```
plugin.json
src/main.lua         # Lua source file (entry point)
src/lib/board.lua    # optional: board logic module
assets/
  icon.png
  images/
    board.png          # chess board background
    pieces.png         # sprite sheet of chess pieces
```

**Plugin manifest (`plugin.json`):**
```json
{
  "id": "chess",
  "name": "Chess",
  "type": "activity",
  "runtime": "scripted",
  "description": "Play chess with a friend",
  "version": "1.0.0",
  "entry_point": "src/main.lua",
  "canvas_size": [480, 480],
  "max_participants": 2,
  "max_spectators": 0,
  "lobby": true,
  "permissions": ["voice_activity"]
}
```

**Step 1 — Admin installs the plugin:**
Admin uploads `chess.daccord-plugin` via Server Settings -> Plugins. Server validates the manifest, stores the bundle, and broadcasts `plugin.installed` to all clients. Clients cache the manifest (not the source).

**Step 2 — User launches the activity:**
User is in a voice channel. Clicks the rocket button → activity modal shows "Chess" card with "Scripted" badge. Clicks "Launch."

**Step 3 — Bundle download and runtime creation:**
`ClientPlugins.launch_activity()` calls `PluginsApi.create_session()` then `_download_and_prepare_scripted_runtime()`. The bundle ZIP is fetched via `PluginsApi.get_source()`. `_extract_bundle()` parses entry Lua source, additional `.lua` modules, and asset files. A `ScriptedRuntime` is created with the modules and assets injected, then `start()` creates the `LuaState` with safe libraries only and injects the bridge `api` table.

**Step 4 — Lobby:**
The `video_grid.gd` sees `activity_started` and rebuilds with a lobby view in the spotlight area. Two player slots. Both players claim slots. Host clicks "Start Activity."

**Step 5 — Gameplay:**
The sandboxed script's `_ready()` loads images via `api.read_asset("assets/images/board.png")` → `api.load_image(data)`. Each frame, `_draw()` renders the board and pieces using `api.draw_image_region()`. When a player clicks a square, `_input()` detects it and calls `api.send_action(Dictionary({from = "e2", to = "e4"}))`. The server validates the move and broadcasts the updated board state. All participants' sandboxed runtimes receive the event via `_on_event()` and re-render.

**Step 6 — Game ends:**
When checkmate occurs, the script renders a "Checkmate!" overlay. Players leave the activity or the host closes it. The runtime is stopped, the LuaState is freed, and the session is deleted.

### Worked Example: NES Emulator Activity (Native Plugin)

This section walks through the complete lifecycle of an NES emulator plugin to illustrate how native plugins, LiveKit data channels, and file sharing work together.

**Plugin bundle contents:**
```
plugin.json
plugin.sig
scenes/
  emulator.tscn          # main scene (extends Control)
scripts/
  emulator.gd            # NES CPU/PPU emulation, frame buffer
  input_mapper.gd         # maps Godot InputEvents to NES button bitmask
  frame_encoder.gd        # delta compression for frame diffs
assets/
  icon.png
```

**Step 1 — Admin installs the plugin:**
Admin uploads `nes-emulator.daccord-plugin` via Server Settings -> Plugins. Server validates the manifest, verifies the Ed25519 signature, stores the bundle, and broadcasts `plugin.installed` to all clients. Clients cache the manifest (not the bundle).

**Step 2 — User launches the activity:**
User is in a voice channel. Clicks the rocket button -> activity modal shows "NES Emulator" card with "Native" badge and "1.0 MB" size. Clicks "Launch."

**Step 3 — Trust check and bundle download:**
`ClientPlugins._download_and_prepare_native_runtime()` calls `PluginDownloadManager.download_bundle()`. First time from this server: `_is_plugin_trusted()` returns false, so `_show_trust_dialog()` displays "This activity runs native code from [server name]. Trust this server's plugins?" with "Trust & Run" / "Cancel" and the "Always trust" checkbox. User clicks "Trust & Run." Bundle is fetched via `GET /plugins/{id}/bundle` with progress bar. SHA-256 hash verified. ZIP extracted to `user://plugins/<server_id>/nes-emulator/`. On subsequent launches, cache hit skips download.

**Step 4 — Lobby:**
Session created via `POST /plugins/{id}/sessions`. `NativeRuntime` instantiates `scenes/emulator.tscn` from the cache directory and calls `setup(context)`. The emulator scene shows a lobby: two player slots, spectator list, and a "Select ROM" button for the host.

**Step 5 — ROM distribution:**
Host clicks "Select ROM" → `context.request_file("mario.nes")` sends a data channel request to the host. Plugin calls `context.send_file("mario.nes", rom_data)`. The filename and data are packed into a single payload (`[4B name_len][name][data]`) and sent via LiveKit reliable data channel on topic `plugin:<id>:file:mario.nes`. All participants receive `file_received("mario.nes", data, host_id)` via `NativeRuntime._handle_file_data()` and load the ROM.

**Step 6 — Game starts:**
Host clicks "Start" → `Client.plugins.start_session()` → `PATCH /plugins/{id}/sessions/{sid} {state: "running"}` → gateway broadcasts `plugin.session_state`. `ClientPlugins.on_plugin_session_state()` updates AppState. `video_grid.gd` rebuilds from lobby to running view with the viewport TextureRect.

**Step 7 — Gameplay:**
- **Host emulator** runs the NES CPU/PPU at 60 FPS, producing a 256x240 frame buffer each frame.
- **Frame encoder** computes a delta from the previous frame. Typical NES frame diffs are 500 B - 2 KB.
- **Host** calls `context.send_data("frame_sync", diff, false)` at 60 Hz.
- **Host** calls `context.send_data("keyframe", full_frame, true)` every 2 seconds for drift correction.
- **Players** capture local input each frame. Call `context.send_data("input", bitmask, false)` at 60 Hz.
- **Host** receives player inputs via `context.data_received` on topic `input`, feeds them into the emulator.
- **Spectators** receive frame diffs and keyframes, apply them to their local frame buffer, but never send input.

**Step 8 — Activity ends:**
Host disconnects from voice or clicks "Leave Activity." `video_grid.gd` calls `Client.plugins.stop_activity()`, which deletes the session, disconnects LiveKit data routing, frees the runtime, and emits `AppState.activity_ended`. All participants' emulator scenes are freed. The cached bundle remains for next time.

## Implementation Status

### Core plugin infrastructure
- [x] `AccordPluginManifest` model with runtime/lobby/signing/canvas_size/format fields (`plugin_manifest.gd`)
- [x] `PluginsApi` REST endpoints in AccordKit — list, install, delete, source, bundle, sessions, roles, actions (`plugins_api.gd`)
- [x] `plugin_installed` / `plugin_uninstalled` / `plugin_event` / `plugin_session_state` / `plugin_role_changed` gateway signals in `gateway_socket.gd` (lines 71-75, 384-393)
- [x] AccordClient plugin signal re-emit (lines 262-266) and `plugins: PluginsApi` exposure (line 121) in `accord_client.gd`
- [x] AppState plugin/activity/lobby signals (lines 193-203) and state variables (lines 233-237)
- [x] `ClientPlugins` helper class with launch/stop, lobby/role management, bundle extraction, trust dialog, gateway handlers (`client_plugins.gd`)
- [x] `ClientGatewayEvents` plugin event handlers — `on_plugin_installed` (line 102), `on_plugin_uninstalled` (line 107), `on_plugin_event` (line 112), `on_plugin_session_state` (line 117), `on_plugin_role_changed` (line 122)
- [x] `ClientGateway` signal wiring for all 5 plugin signals (lines 82-91)
- [x] Per-server isolation enforced in `ClientPlugins` via `conn_index` keying and `PluginContext.conn_index`

### Scripted runtime (lua-gdextension)
- [x] lua-gdextension GDExtension integrated as addon dependency
- [x] `ScriptedRuntime` node wrapping `LuaState` with safe-libs-only bitmask (`SAFE_LIBS`, line 13)
- [x] Bridge `api` table injection with all drawing, state, timer, asset, and audio functions (`_inject_bridge_api()`, line 260)
- [x] `PluginCanvas` draw target inside `SubViewport` with command queue, image/buffer management, coordinate clamping
- [x] Plugin bridge API: drawing primitives (`draw_rect`, `draw_circle`, `draw_line`, `draw_text`, `draw_pixel`)
- [x] Plugin image loading and sprite sheet rendering (`load_image`, `draw_image`, `draw_image_region`, `draw_image_scaled`)
- [x] Plugin frame buffer API (`create_buffer`, `set_buffer_pixel`, `set_buffer_data`, `draw_buffer`, `draw_buffer_scaled`)
- [x] Plugin input routing (`forward_input()` with mouse button/motion/key event translation, line 174)
- [x] Plugin audio playback (`load_sound`, `play_sound`, `stop_sound`) with 16-sound limit
- [x] Canvas coordinate clamping (lines 204-209 in plugin_canvas.gd) and command limit (4096/frame)
- [x] Image/buffer resource limits (64 images, 4 buffers in plugin_canvas.gd)
- [x] Lua `print()` override, `Dictionary()`/`Array()` constructors, sandboxed `require()` for bundled modules
- [x] Bundle ZIP extraction with entry source, modules, and assets parsing (`_extract_bundle()`, line 174)
- [x] Asset access via `api.read_asset()` for bundled images/sounds
- [ ] Execution time budget per frame (configurable, default 4ms) — not yet enforced
- [ ] Memory limit per LuaState (default 16 MB) — not yet enforced
- [ ] Lua plugin development toolchain (daccord-editor for testing)

### Native runtime
- [x] `NativeRuntime` scene host with `setup(context)` injection (`native_runtime.gd`)
- [x] `PluginContext` resource with data channel, file sharing, participant, and action APIs (`plugin_context.gd`)
- [x] `PluginDownloadManager` — download, SHA-256 verify, ZIP extract, cache at `user://plugins/` (`plugin_download_manager.gd`)
- [x] Plugin trust dialog with "Trust & Run" / "Cancel" and "Always trust" checkbox (`plugin_trust_dialog.gd`)
- [x] Per-server and per-plugin trust persistence in Config (lines 681-698)

### LiveKit data channels
- [x] `LiveKitAdapter` additions: `publish_plugin_data()` (line 227), `plugin_data_received` signal (line 14), topic routing (line 402)
- [x] Data channel topic namespacing (`plugin:<id>:<topic>`) in `PluginContext.send_data()` (line 42)
- [x] File transfer via data channel with filename+data packing in `PluginContext.send_file()` (line 51) and reassembly in `NativeRuntime._handle_file_data()` (line 108)

### Lobby system
- [x] `ActivityLobby` scene (player slots grid, spectator list, start button) — `activity_lobby.gd`
- [x] Session state machine (LOBBY -> RUNNING -> ENDED) via gateway `plugin.session_state` events
- [x] Participant role assignment (PLAYER / SPECTATOR) via REST + gateway `plugin.role_changed`
- [ ] Late joiner handling — joining users need to receive current session state on connect

### Plugin signing
- [ ] Ed25519 signature verification implementation — `_verify_signature()` is a stub (line 191 in plugin_download_manager.gd)
- [x] Trust confirmation dialog for native plugins (`plugin_trust_dialog.gd`)
- [x] Per-server trust preference in Config (`get_plugin_trust`, `set_plugin_trust`, `is_plugin_trust_all`, `set_plugin_trust_all`)

### UI
- [x] Activity UI integrated into `video_grid.gd` spotlight area (lobby/running/ended views, header/footer, progress bar)
- [x] `ActivityModal` scene (activity picker from voice bar) — `activity_modal.gd`
- [x] Voice bar "Launch Activity" rocket button — `voice_bar.gd` line 31, `voice_bar.tscn` line 91
- [x] Input coordinate remapping for viewport TextureRect (`_on_activity_viewport_input()`, video_grid.gd line 561)
- [x] Download progress bar in activity container
- [ ] Admin Plugins settings page — no `scenes/settings/plugins_settings.gd` or `.tscn` exists yet

### Server-side (accordserver)
- [ ] Plugin bundle storage and manifest registry
- [ ] REST routes for plugin management, bundle serving, sessions, roles
- [ ] Gateway `plugin.*` event dispatch (installed, uninstalled, event, session_state, role_changed)
- [ ] Plugin action routing for scripted plugins
- [ ] Session state machine with role assignment
- [ ] Lua source upload and validation (server-side)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No accordserver plugin subsystem | High | Server has no plugin routes, no session management, no bundle storage, and no `plugin.*` gateway events; entire backend must be built first |
| Ed25519 signature verification is a stub | High | `plugin_download_manager.gd` line 191 `_verify_signature()` only checks that `plugin.sig` exists; no actual cryptographic verification. A GDExtension providing Ed25519 primitives is needed |
| No Lua execution time budget | High | `scripted_runtime.gd` has no per-frame time limit; a malicious or buggy Lua script could freeze the client with an infinite loop. Need to add instruction-count limits or a timeout mechanism |
| No Lua memory limit | High | `LuaState` memory usage is uncapped; a plugin could allocate unbounded memory. Need to configure Lua's memory allocator limit (default 16 MB target) |
| No plugin sandbox isolation test suite | High | Lua sandbox security properties (no FS access, no cross-server calls, API whitelist enforcement) need automated tests before plugins ship to users |
| `interaction_create` handler is a stub | Medium | `client_gateway_events.gd` line 95 handles `interaction_create` with `pass`; bot/plugin interactions need a real dispatch path |
| No admin plugins settings page | Medium | No `scenes/settings/plugins_settings.gd` or `.tscn` exists; server admins cannot install/manage plugins from the client UI yet |
| No late joiner state sync | Medium | Users who join a voice channel after an activity started get no current session state; need a "current session" lookup on voice join |
| No activity join notification for late joiners | Medium | Users who join a voice channel after an activity has started see no indication that an activity is running; a gateway `plugin.session_state` event on join or a voice state flag is needed |
| `ChannelType` enum has no ACTIVITY type | Medium | `client_models.gd` line 7 enum has TEXT/VOICE/ANNOUNCEMENT/FORUM/CATEGORY; activities launched from voice don't need a new channel type, but a plugin-owned channel type may be needed for persistent activity channels |
| No plugin asset CDN integration | Medium | Plugin images/icons served via the plugin source/bundle endpoint; the existing CDN URL pattern (`conn.cdn_url`) needs to extend to plugin assets |
| No activity session state persistence | Medium | If the user closes and reopens the app during an active activity, there is no reconnect path; session recovery requires server-side session lookup |
| Lua plugin development toolchain | Medium | Plugin developers use daccord-editor for local testing; the workflow for building `.daccord-plugin` bundles needs documentation |
| No plugin update notification | Low | When a server updates a plugin to a new version, clients with a stale cached bundle need to be notified to re-download; could piggyback on `plugin.installed` with a version field |
| No plugin size limits on server | Low | Server should enforce maximum bundle size to prevent abuse (e.g., 50 MB cap); client already enforces via `MAX_BUNDLE_SIZE` (plugin_download_manager.gd line 8) |
| Scripted plugin font support limited | Low | `api.draw_text()` uses `ThemeDB.fallback_font` (plugin_canvas.gd line 41); no custom font loading. Could add `api.load_font()` in a future iteration |
| Max participants not enforced client-side | Low | `max_participants` in the manifest should grey out "Claim Slot" when all player slots are full; requires polling or a `plugin.session_full` event |
| No emulator core | Low | The NES emulator plugin is a worked example; an actual NES CPU/PPU emulator must be written in GDScript or provided as a GDExtension within the plugin bundle |
| Frame diff compression algorithm not specified | Low | The emulator example assumes delta compression + RLE for frame diffs; the exact algorithm needs implementation and testing to stay within the ~1,300-byte lossy packet limit |
