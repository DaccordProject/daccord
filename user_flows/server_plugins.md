# Server Plugins

Priority: 72
Depends on: None

## Overview

Server plugins allow individual accordserver instances to extend daccord with custom behavior: additional REST endpoints, WebSocket events, and client-side logic. Plugins are strictly scoped to the server that installed them — no plugin can read data from or affect the UI of another connected server.

Two plugin runtimes are supported:

- **Scripted plugins** — sandboxed GDScript programs for simple activities (chess, polls, trivia). Written in GDScript, compiled to RISC-V ELF binaries via [godot-sandbox](https://github.com/libriscv/godot-sandbox), and executed in an isolated virtual machine. The VM enforces memory isolation and restricts API access — sandboxed code can only call whitelisted functions. No access to the filesystem, network, autoloads, or Godot engine internals.
- **Native plugins** — full GDScript scenes and resources for complex activities (emulators, collaborative editors). Downloaded as a bundle on first launch, cached locally, and instantiated as a Godot scene tree. Requires code signing (Ed25519) and explicit user trust approval.

The first supported plugin type is **Activities**: interactive experiences users can launch from within a voice channel. Activities use a **lobby system** with player/spectator roles and communicate via **LiveKit data channels** for low-latency real-time state sync.

### What this means for non-technical users

Think of plugins like mini-apps that a server admin can install. When you join a voice channel on a server with plugins, you might see options like "Play Chess" or "Launch Trivia." Clicking one opens a small interactive panel right inside daccord — no browser or extra software needed.

- **Scripted plugins** are lightweight and safe by design. They run in a secure sandbox that prevents them from accessing your files or personal data. These are ideal for simple games and interactive widgets.
- **Native plugins** are more powerful but require a higher level of trust. Before running one for the first time, daccord asks for your permission and verifies the plugin's digital signature to confirm it hasn't been tampered with.

Both types only work on the server that installed them. A plugin from Server A cannot see your activity on Server B.

### Why GDScript instead of Lua?

The original design proposed Lua for the scripted plugin tier. GDScript (via godot-sandbox) is a better fit because:

1. **No external dependency** — Lua would require sourcing or building a Lua 5.4 GDExtension for Godot 4.x. godot-sandbox is an existing, maintained GDExtension that supports Godot 4.3+.
2. **One language** — Plugin developers already know GDScript from Godot. No need to learn a second language for simple plugins.
3. **Real VM isolation** — godot-sandbox compiles GDScript to RISC-V ELF binaries and runs them in an instruction-validated virtual machine with separate memory space. This is stronger isolation than a Lua VM with blocked APIs — the sandbox cannot be escaped through pointer manipulation or reflection.
4. **Performance** — godot-sandbox reports 2.5–10x performance over interpreted GDScript (5–50x with binary translation/JIT). This matters for frame-rate-sensitive activities like emulators.
5. **Cross-platform** — Compiled ELF binaries run on all platforms (desktop, mobile, web) without recompilation.

## User Steps

### Browsing available activities

*Who this is for: any user in a voice channel.*

1. User joins a voice channel
2. A "Launch Activity" button appears in the voice bar (rocket icon, next to the existing microphone/camera/screen share buttons)
3. User clicks "Launch Activity" → a modal lists available activities published by the server
4. Each activity card shows:
   - Activity icon (64x64)
   - Name and description
   - Runtime badge ("Scripted" or "Native") so users know the trust level
   - Max participants (e.g., "2 players")
   - Bundle size (native only, e.g., "1.0 MB")
   - "Launch" button
5. User clicks "Launch" → activity opens in a panel alongside the voice channel view

### Starting a scripted activity

*Who this is for: any user launching a lightweight plugin (chess, trivia, polls).*

1. Activity panel loads; the plugin's compiled ELF binary is fetched from the server
2. A `Sandbox` node is created and the ELF is loaded into it. The sandbox restricts the program to only the whitelisted `Plugin.*` bridge API — no filesystem, no network, no engine internals
3. The sandboxed program renders its UI into a dedicated `SubViewport` using drawing primitives (rectangles, circles, lines, text, images)
4. Other voice participants see a "Join Activity" prompt
5. Joining participants connect to the same activity session; the server broadcasts state via a `plugin.event` gateway event

**What happens under the hood (technical):** The GDScript source is compiled to a RISC-V ELF binary by godot-sandbox's toolchain (either in-editor or as part of the plugin build process). At runtime, the `ScriptedRuntime` node creates a `Sandbox` instance, loads the ELF resource, and exposes only the `Plugin` API table. The RISC-V VM enforces memory isolation — the program runs in its own address space and cannot access host memory, Godot singletons, or the scene tree outside its designated `SubViewport`.

### Starting a native activity

*Who this is for: users launching a complex plugin (emulator, collaborative editor).*

1. **Trust check (first time only):** If this is the first native plugin from this server, daccord shows a confirmation dialog: "This activity runs native code from [server name]. Trust this server's plugins?" The user can allow or deny. This preference is saved per-server in the user's profile config
2. **Signature verification:** The plugin bundle's Ed25519 signature is verified against the server-provided public key. If verification fails, the plugin is rejected with an error message
3. **Download/cache:** `PluginDownloadManager` checks the local cache (`user://plugins/<server_id>/<plugin_id>/`):
   - If not cached or version mismatch: download progress bar appears, bundle is fetched via `GET /plugins/{id}/bundle`, SHA-256 hash verified, signature verified, and extracted
   - If cached and version matches: skip download
4. The entry point scene (`entry_point` from manifest) is instantiated as a child of `ActivityViewport`
5. The scene receives a `PluginContext` resource — the bridge API for data channels, participant info, session state, and file sharing
6. Activity enters `LOBBY` state — other voice participants see a "Join Activity" prompt

### Lobby phase

*Who this is for: all participants in an activity that uses the lobby system.*

1. Activity opens in `LOBBY` state; the host (user who launched the activity) sees a lobby panel with:
   - **Player slots** — numbered slots set by `max_participants` in the manifest (e.g., 2 for a chess game, 4 for a card game). Each slot is either empty or shows a user's avatar and display name
   - **Spectator list** — all joined users who haven't claimed a player slot
   - **"Claim Slot" button** — lets a user request a player slot (greyed out when all slots are full)
   - **"Start" button** — visible only to the host, enabled when at least one player slot is filled
2. Joining participants default to `SPECTATOR` role
3. Users click "Claim Slot" → if a slot is available, their role changes to `PLAYER`. They can release the slot to go back to spectating
4. Host clicks "Start" → session state moves to `RUNNING` via a gateway broadcast to all participants
5. Late joiners (users who join the voice channel after the activity started) see the activity in its current state and join as `SPECTATOR`

### Interacting within a scripted activity (e.g., chess)

*Who this is for: players and spectators in a scripted activity.*

1. User makes a move → the sandboxed script calls `Plugin.send_action({move = "e2e4"})` → the client POSTs to the plugin's REST endpoint `POST /plugins/{plugin_id}/sessions/{session_id}/actions`
2. The server validates the move (via its server-side plugin handler), updates game state, and broadcasts a `plugin.event` via the gateway with `{plugin_id, type: "state_update", data: {...}}`
3. All participants' sandboxed runtimes receive the event via `Plugin.on_event(callback)` and re-render the board

**For non-technical users:** You interact with scripted activities by clicking, typing, or pressing keys inside the activity panel. Your actions are sent to the server, which validates them (e.g., checks if a chess move is legal) and sends the updated game state to everyone. You don't need to worry about the technical details — it works like any other multiplayer game.

### Interacting within a native activity (e.g., NES emulator)

*Who this is for: players and spectators in a native activity.*

1. Host selects a ROM file from their local filesystem via a file dialog (the plugin calls `PluginContext.request_file()`, which opens a native OS file picker filtered by allowed extensions and capped by `max_file_size` from the manifest)
2. Plugin reads the ROM into memory
3. Plugin sends the ROM to all participants via LiveKit reliable byte stream (`PluginContext.send_file()`), auto-chunked at 15 KiB packets
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

**What's in a plugin bundle:** A `.daccord-plugin` file is a ZIP archive. At minimum it contains a `plugin.json` file describing the plugin (name, type, runtime, permissions). Scripted plugins include a compiled `.elf` binary. Native plugins include GDScript scenes (`.tscn`) and scripts (`.gd`), plus a `plugin.sig` digital signature file. Both can include an `assets/` directory with images, sounds, and other resources.

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
     |                              |                              |-- fetch ELF binary
     |                              |                              |-- create Sandbox + ScriptedRuntime
     |                              |<- activity_started(id) ------|
     |<-- activity_panel_opened ----|                              |
     |   (ActivityViewport shown)   |                              |
     |                              |                              |
     |   Script: Plugin.send_action()|                             |
     |------------------------------|----------------------------->|
     |                              |                              |-- POST /plugins/{id}/actions
     |                              |                              |
     |   Gateway: plugin.event      |                              |
     |                              |<- plugin_event(id, data) ----|
     |                              |   (from GatewaySocket)       |
     |                              |-- route to ScriptedRuntime ->|
     |<-- Sandbox.on_event() ------|                              |
     |   (re-render UI in viewport) |                              |
     |                              |                              |
     |-- user leaves voice -------->|                              |
     |                              |-- cleanup_activity(id) ----->|
     |                              |                              |-- ScriptedRuntime.stop()
     |                              |                              |-- ActivityViewport freed
     |                              |<- activity_ended(id) --------|
     |<-- activity_panel_closed ----|                              |
```

### Activity Launch (Native runtime with lobby + data channels)

```
voice_bar.gd          AppState          ClientPlugins        PluginDownloadMgr     LiveKit
     |                    |                    |                    |                  |
     |-- launch --------->|                    |                    |                  |
     |                    |-- launch(id) ----->|                    |                  |
     |                    |                    |-- check cache ---->|                  |
     |                    |                    |   (miss or stale)  |                  |
     |                    |                    |                    |-- GET /bundle     |
     |                    |<- download_progress(%) ----------------|                  |
     |                    |                    |<-- bundle ready ---|                  |
     |                    |                    |-- verify hash      |                  |
     |                    |                    |-- verify signature |                  |
     |                    |                    |-- extract to cache |                  |
     |                    |                    |                    |                  |
     |                    |                    |-- POST /sessions   |                  |
     |                    |                    |-- instantiate scene|                  |
     |                    |<- activity_started(id, LOBBY) ---------|                  |
     |<-- lobby shown ----|                    |                    |                  |
     |                    |                    |                    |                  |
     |-- claim slot ----->|                    |                    |                  |
     |                    |-- assign_role() -->|                    |                  |
     |                    |                    |-- POST /sessions/{id}/roles           |
     |                    |<- role_changed ----|                    |                  |
     |                    |                    |                    |                  |
     |-- host: start ---->|                    |                    |                  |
     |                    |-- start_session -->|                    |                  |
     |                    |                    |-- POST /sessions/{id}/start           |
     |                    |                    |   gateway: session_state=RUNNING      |
     |                    |<- session_running -|                    |                  |
     |                    |                    |                    |                  |
     |   Plugin scene calls Plugin.send_data()|                    |                  |
     |                    |                    |--------------------|----------------->|
     |                    |                    |                    |  publish_data()  |
     |                    |                    |                    |                  |
     |   LiveKit: data_received              |                    |                  |
     |                    |                    |<-------------------|------ data ------|
     |                    |                    |-- route to scene   |                  |
     |<-- scene renders --|                    |                    |                  |
```

### Plugin Installation Gateway Flow

```
Admin uploads plugin bundle
    -> POST /spaces/{space_id}/plugins (server validates, stores scripts)
    -> Gateway broadcasts: plugin.installed {plugin_id, manifest}
        -> GatewaySocket emits plugin_installed(manifest)
            -> ClientPlugins.on_plugin_installed(manifest)
                -> caches manifest in _plugin_cache[conn_index][plugin_id]
                -> AppState.plugins_updated emitted
                    -> Activities modal refreshes list

Admin uninstalls plugin
    -> DELETE /spaces/{space_id}/plugins/{plugin_id}
    -> Gateway broadcasts: plugin.uninstalled {plugin_id}
        -> ClientPlugins.on_plugin_uninstalled(plugin_id)
            -> tears down active runtime (scripted or native) if running
            -> removes from _plugin_cache
            -> AppState.plugins_updated emitted
            -> AppState.activity_ended(plugin_id) emitted if activity was open
```

### File Sharing via LiveKit Data Channel

```
Host (emulator plugin)            LiveKit SFU              Participants
     |                                |                         |
     |-- Plugin.send_file(rom_data) ->|                         |
     |   (reliable byte stream,      |                         |
     |    chunked at 15KB packets)    |                         |
     |                                |-- relay chunks -------->|
     |                                |                         |-- reassemble
     |                                |                         |-- on_file_received()
     |                                |                         |
     |-- frame diff (lossy, ~1KB) --->|                         |
     |   topic: "frame_sync"          |-- relay (lossy) ------->|
     |   @ 60Hz                       |                         |-- render delta
     |                                |                         |
     |                                |<-- input (lossy, ~4B) --|
     |   topic: "input"               |                         |
     |<-- relay (lossy) --------------|                         |
     |-- apply input to emulator      |                         |
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST: list plugins, download bundle, create/delete session, send action, manage roles (new) |
| `addons/accordkit/models/plugin_manifest.gd` | `AccordPluginManifest` model: id, name, type, runtime, description, bundle_hash, max_participants (new) |
| `addons/accordkit/gateway/gateway_socket.gd` | Add `plugin_installed`, `plugin_uninstalled`, `plugin_event`, `plugin_session_state` signals; currently has `interaction_create` signal (line 68) |
| `addons/accordkit/core/accord_client.gd` | Expose `plugins: PluginsApi`; re-emit plugin gateway events; currently has `interactions: InteractionsApi` (line 113) |
| `scripts/autoload/app_state.gd` | `plugins_updated`, `activity_started`, `activity_ended`, `activity_download_progress`, `activity_role_changed`, `activity_session_state_changed` signals (new) |
| `scripts/autoload/client.gd` | Delegate plugin operations to a new `ClientPlugins` helper |
| `scripts/autoload/client_plugins.gd` | `ClientPlugins` helper: plugin cache, launch/stop activity, lobby management, role assignment (new) |
| `scripts/autoload/client_gateway_events.gd` | `on_plugin_installed`, `on_plugin_uninstalled`, `on_plugin_event`, `on_plugin_session_state` handlers; `on_interaction_create` stub exists (line 95) (new handlers) |
| `scripts/autoload/client_gateway.gd` | Wire plugin gateway signals → `ClientGatewayEvents` |
| `scripts/autoload/livekit_adapter.gd` | Wrap `publish_data()` and `data_received` for plugin data channel access; currently audio/video only |
| `scripts/autoload/plugin_download_manager.gd` | Download, verify, cache, and extract native plugin bundles (new) |
| `scenes/sidebar/voice_bar.gd` | Add "Launch Activity" button; connect to `AppState.activity_started/ended`; currently has Mic/Deaf/Cam/Share/SFX/Settings/Disconnect buttons |
| `scenes/sidebar/voice_bar.tscn` | Add rocket button node to `ButtonRow` |
| `scenes/plugins/activity_modal.gd` | Activity picker modal: fetches plugin list, shows cards with runtime badges, launches selection (new) |
| `scenes/plugins/activity_modal.tscn` | Modal scene (new) |
| `scenes/plugins/activity_panel.gd` | Side panel hosting `ActivityViewport` and the plugin runtime; shows lobby or running state (new) |
| `scenes/plugins/activity_panel.tscn` | Panel scene (new) |
| `scenes/plugins/activity_lobby.gd` | Lobby UI: participant list, role assignment, player slots, start button (new) |
| `scenes/plugins/activity_lobby.tscn` | Lobby scene (new) |
| `scenes/plugins/scripted_runtime.gd` | Sandboxed GDScript host; creates `Sandbox` node, loads ELF binary, exposes `Plugin.*` bridge API via godot-sandbox whitelisting (new) |
| `scenes/plugins/plugin_canvas.gd` | `PluginCanvas extends Node2D`: sole draw target inside the scripted plugin's `SubViewport`; translates `Plugin.draw_*` calls into CanvasItem draw commands (new) |
| `scenes/plugins/native_runtime.gd` | Native plugin host: instantiates GDScript scene, injects `PluginContext`, manages lifecycle (new) |
| `scenes/plugins/plugin_context.gd` | `PluginContext extends Resource`: bridge API for native plugins (data channels, participants, session state) (new) |
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
var type: String = ""              # "activity", "bot", "theme", "command"
var runtime: String = ""           # "scripted" or "native"
var description: String = ""
var icon_url: String = ""          # nullable
var elf_url: String = ""           # relative path on server CDN (scripted plugins)
var entry_point: String = ""       # scene path within bundle (native plugins)
var bundle_size: int = 0           # bytes (native plugins; 0 for scripted)
var bundle_hash: String = ""       # "sha256:<hex>" (native plugins)
var max_participants: int = 0      # 0 = unlimited
var max_spectators: int = 0        # 0 = unlimited; -1 = no spectators
var max_file_size: int = 0         # max user-supplied file size in bytes (0 = no file sharing)
var version: String = ""
var permissions: Array = []        # declared capabilities the plugin requests
var lobby: bool = false            # whether activity uses the lobby phase
var data_topics: Array = []        # LiveKit data channel topics this plugin uses
var signed: bool = false           # whether the bundle has a valid code signature
var signature: String = ""         # detached signature (native plugins)
```

### Plugin Runtime Enum

```gdscript
enum PluginRuntime { SCRIPTED, NATIVE }
```

### Session State Enum

```gdscript
enum SessionState { LOBBY, RUNNING, ENDED }
```

### Participant Role Enum

```gdscript
enum ParticipantRole { SPECTATOR, PLAYER }
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

# Download the full plugin bundle (native plugins)
func get_bundle(plugin_id: String) -> RestResult
    # GET /plugins/{plugin_id}/bundle (returns binary ZIP)

# Fetch the compiled ELF binary for a scripted plugin
func get_elf(plugin_id: String) -> RestResult
    # GET /plugins/{plugin_id}/elf (returns binary ELF)

# Start an activity session in a voice channel
func create_session(plugin_id: String, channel_id: String) -> RestResult
    # POST /plugins/{plugin_id}/sessions
    # Returns: { session_id, state: "lobby", participants: [] }

# End the current session (leave or close)
func delete_session(plugin_id: String, session_id: String) -> RestResult
    # DELETE /plugins/{plugin_id}/sessions/{session_id}

# Transition session state (host only)
func update_session_state(plugin_id: String, session_id: String, state: String) -> RestResult
    # PATCH /plugins/{plugin_id}/sessions/{session_id} { state: "running" }

# Assign a participant role within a session
func assign_role(plugin_id: String, session_id: String, user_id: String, role: String) -> RestResult
    # POST /plugins/{plugin_id}/sessions/{session_id}/roles { user_id, role: "player"|"spectator" }

# Send a plugin action (e.g., game move) — scripted plugins only
func send_action(plugin_id: String, session_id: String, data: Dictionary) -> RestResult
    # POST /plugins/{plugin_id}/sessions/{session_id}/actions
```

### Gateway Signals (`gateway_socket.gd`)

Add to the signals section (after `interaction_create` at line 68):

```gdscript
signal plugin_installed(manifest: AccordPluginManifest)
signal plugin_uninstalled(plugin_id: String)
signal plugin_event(plugin_id: String, event_type: String, data: Dictionary)
signal plugin_session_state(plugin_id: String, session_id: String, state: String)
signal plugin_role_changed(plugin_id: String, session_id: String, user_id: String, role: String)
```

Dispatch in `_dispatch_event()`:
```gdscript
"plugin.installed":      plugin_installed.emit(AccordPluginManifest.from_dict(data))
"plugin.uninstalled":    plugin_uninstalled.emit(str(data.get("plugin_id", "")))
"plugin.event":          plugin_event.emit(str(data.get("plugin_id", "")),
                                            str(data.get("type", "")), data)
"plugin.session_state":  plugin_session_state.emit(str(data.get("plugin_id", "")),
                                                    str(data.get("session_id", "")),
                                                    str(data.get("state", "")))
"plugin.role_changed":   plugin_role_changed.emit(str(data.get("plugin_id", "")),
                                                   str(data.get("session_id", "")),
                                                   str(data.get("user_id", "")),
                                                   str(data.get("role", "")))
```

### AppState Additions

```gdscript
signal plugins_updated()
signal activity_started(plugin_id: String, channel_id: String)
signal activity_ended(plugin_id: String)
signal activity_download_progress(plugin_id: String, progress: float)
signal activity_session_state_changed(plugin_id: String, state: String)
signal activity_role_changed(plugin_id: String, user_id: String, role: String)
```

State:
```gdscript
var active_activity_plugin_id: String = ""
var active_activity_channel_id: String = ""
var active_activity_session_id: String = ""
var active_activity_session_state: String = ""  # "lobby", "running", "ended"
var active_activity_role: String = ""            # "player", "spectator"
```

### ClientPlugins Helper (`client_plugins.gd`)

New `ClientPlugins extends RefCounted`. Instantiated in `Client._ready()` alongside `ClientVoice`:

```gdscript
# Plugin cache: conn_index -> { plugin_id -> manifest dict }
var _plugin_cache: Dictionary = {}
# Active runtime reference (scripted Sandbox or native scene)
var _active_runtime: Node = null
var _active_session_id: String = ""
var _active_conn_index: int = -1

func fetch_plugins(conn_index: int, space_id: String) -> void
func launch_activity(plugin_id: String, channel_id: String) -> void
    # 1. Look up manifest to determine runtime type
    # 2. If native: delegate to PluginDownloadManager, wait for cache hit
    # 3. If scripted: call PluginsApi.get_elf() to fetch compiled binary
    # 4. Call PluginsApi.create_session()
    # 5. Instantiate ScriptedRuntime or NativeRuntime with plugin content
    # 6. If manifest.lobby: enter LOBBY state
    # 7. Emit AppState.activity_started(plugin_id, channel_id)
func stop_activity(plugin_id: String) -> void
    # 1. Call PluginsApi.delete_session()
    # 2. Tear down runtime (ScriptedRuntime.stop() or native scene queue_free())
    # 3. Emit AppState.activity_ended(plugin_id)
func assign_role(user_id: String, role: String) -> void
    # POST role assignment to server
func start_session() -> void
    # PATCH session state to "running" (host only)
func send_action(plugin_id: String, data: Dictionary) -> void
    # Routes Plugin.send_action() calls from sandboxed scripts
func on_plugin_installed(manifest: AccordPluginManifest, conn_index: int) -> void
func on_plugin_uninstalled(plugin_id: String, conn_index: int) -> void
func on_plugin_event(plugin_id: String, event_type: String, data: Dictionary) -> void
    # Routes to active ScriptedRuntime if plugin_id matches
func on_plugin_session_state(plugin_id: String, session_id: String, state: String) -> void
    # Updates AppState.active_activity_session_state
func on_plugin_role_changed(plugin_id: String, session_id: String, user_id: String, role: String) -> void
    # Updates role display in lobby
```

### Plugin Download Manager (`plugin_download_manager.gd`)

New `PluginDownloadManager extends RefCounted`:

```gdscript
const CACHE_BASE: String = "user://plugins/"

# Check if a plugin bundle is cached and matches the expected version/hash
func is_cached(server_id: String, plugin_id: String, expected_hash: String) -> bool
    # Checks CACHE_BASE/<server_id>/<plugin_id>/manifest.json version + hash

# Download and cache a plugin bundle
func download_bundle(conn_index: int, plugin_id: String, manifest: AccordPluginManifest) -> void
    # 1. GET /plugins/{id}/bundle → binary ZIP data
    # 2. Verify SHA-256 hash matches manifest.bundle_hash
    # 3. For native plugins: verify code signature against trusted keys
    # 4. Extract to CACHE_BASE/<server_id>/<plugin_id>/
    # 5. Write manifest.json with version + hash for cache validation
    # 6. Emit AppState.activity_download_progress throughout

# Get the local path to a cached plugin's entry point
func get_entry_path(server_id: String, plugin_id: String) -> String
    # Returns CACHE_BASE/<server_id>/<plugin_id>/<entry_point>

# Delete cached plugin data
func delete_cache(server_id: String, plugin_id: String) -> void

# Delete all cached plugins for a server (on server removal)
func delete_server_cache(server_id: String) -> void
```

### Scripted Runtime Sandbox (`scripted_runtime.gd`)

`ScriptedRuntime extends Node` hosts a sandboxed GDScript program using [godot-sandbox](https://github.com/libriscv/godot-sandbox). The GDScript source is compiled to a RISC-V ELF binary (either by the plugin developer using the godot-sandbox editor toolchain, or server-side during upload). At runtime, the ELF is loaded into a `Sandbox` node which enforces memory isolation and API whitelisting.

**How godot-sandbox works:**

godot-sandbox is a GDExtension for Godot 4.3+ that runs programs inside a RISC-V virtual machine. Programs are compiled to ELF binaries and executed in an isolated address space — they cannot access host memory, escape through pointer manipulation, or use reflection to reach engine internals. The host application explicitly registers which functions are callable from inside the sandbox.

For daccord, this means:
- Plugin GDScript source is written using a restricted subset ("SafeGDScript") that compiles to RISC-V
- The compiled ELF binary is what gets distributed in the plugin bundle (not raw source code)
- The `ScriptedRuntime` creates a `Sandbox` node and registers only the `Plugin.*` bridge API
- All other Godot APIs (filesystem, network, autoloads, scene tree) are unreachable from inside the sandbox

**Rendering architecture:**

The `ScriptedRuntime` owns a `SubViewport` (the "canvas") with a configurable resolution (default 480x360, set via `canvas_size` in the manifest). A `PluginCanvas` node (extends `Node2D`) is the sole child of this viewport and serves as the draw target. Each frame, the sandboxed script's `_draw()` callback is invoked, and all `Plugin.draw_*` calls are translated into `PluginCanvas._draw()` CanvasItem commands. The viewport's render output is displayed in the `ActivityPanel` via a `TextureRect`.

```
ActivityPanel
 +-- TextureRect (displays viewport texture)
     +-- SubViewport (480x360, owned by ScriptedRuntime)
         +-- PluginCanvas (Node2D, sole draw target)
             +-- all Plugin.draw_* calls render here
```

**Confinement guarantees:**

- **VM-level isolation:** The RISC-V VM runs in its own memory space. The sandboxed program cannot read or write host process memory. This is enforced at the instruction level, not just by API restrictions
- **API whitelisting:** Only the `Plugin.*` functions listed below are registered with the `Sandbox` node. All other Godot classes and methods are inaccessible
- **SubViewport confinement:** The `SubViewport` uses `render_target_update_mode = ALWAYS` and is parented to the `ScriptedRuntime` node, not the root. The sandboxed program cannot reference any node outside the viewport
- **Coordinate clamping:** All coordinate arguments are clamped to `[0, canvas_width)` x `[0, canvas_height)` — drawing outside the bounds is silently clipped
- **Read-only viewport texture:** The sandboxed program can draw but cannot read back pixels
- **Input confinement:** Input events are only delivered when the activity panel has focus; `_input` receives only key/mouse events within the viewport bounds, never global input
- **Per-server VM isolation:** Each server connection gets its own `Sandbox` instance; programs from server A cannot call `Plugin` functions that affect server B's runtime

**Plugin bridge API (registered with the Sandbox):**

```gdscript
# Lifecycle callbacks (called by the runtime)
func _draw():             # called once per frame; all draw calls go here
func _ready():            # called once after ELF loads
func _input(event: Dictionary):  # called on user input within the activity viewport
                          # event = {type, key, pressed, position_x, position_y, button}

# Canvas info (read-only properties)
Plugin.canvas_width       # viewport width in pixels (e.g., 480)
Plugin.canvas_height      # viewport height in pixels (e.g., 360)

# Drawing primitives (only valid inside _draw; all coords clamped to canvas bounds)
Plugin.clear(color: Color)
Plugin.draw_rect(x: float, y: float, w: float, h: float, color: Color, filled: bool)
Plugin.draw_circle(x: float, y: float, radius: float, color: Color)
Plugin.draw_line(x1: float, y1: float, x2: float, y2: float, color: Color, width: float)
Plugin.draw_text(x: float, y: float, text: String, color: Color, size: int)
Plugin.draw_pixel(x: float, y: float, color: Color)

# Image / sprite support
Plugin.load_image(image_id: String, asset_path: String) -> bool
    # load image from plugin assets/ dir into cache
    # asset_path is relative to bundle root
    # returns true on success, false if not found or limit exceeded
Plugin.draw_image(image_id: String, x: float, y: float)
Plugin.draw_image_region(image_id: String, x: float, y: float,
                         src_x: float, src_y: float, src_w: float, src_h: float)
Plugin.draw_image_scaled(image_id: String, x: float, y: float,
                         scale_x: float, scale_y: float)

# Frame buffer (direct pixel manipulation for emulator-style rendering)
Plugin.create_buffer(buffer_id: String, width: int, height: int)
Plugin.set_buffer_pixel(buffer_id: String, x: int, y: int, color: Color)
Plugin.set_buffer_data(buffer_id: String, pixel_array: PackedByteArray)
    # bulk-set entire buffer from flat RGBA byte array
Plugin.draw_buffer(buffer_id: String, x: float, y: float)
Plugin.draw_buffer_scaled(buffer_id: String, x: float, y: float,
                          scale_x: float, scale_y: float)

# State & actions
Plugin.send_action(data: Dictionary)       # sends action to server REST endpoint
Plugin.get_state() -> Dictionary           # last received state from plugin.event

# Events
Plugin.on_event(type: String, callback: Callable)  # register handler for plugin.event type

# Participants
Plugin.get_participants() -> Array   # list of {user_id, display_name, role}
Plugin.get_role() -> String          # "player" or "spectator"

# Timers
Plugin.set_interval(ms: int, callback: Callable)  # recurring (capped at 16ms min for 60fps)
Plugin.set_timeout(ms: int, callback: Callable)    # one-shot

# Audio (optional, requires "audio" permission in manifest)
Plugin.load_sound(sound_id: String, asset_path: String)
Plugin.play_sound(sound_id: String)
Plugin.stop_sound(sound_id: String)
```

**Image and buffer limits:**

| Resource | Limit | Reason |
|----------|-------|--------|
| Cached images | 64 max | Prevents unbounded memory growth |
| Image dimensions | 1024x1024 per image | Keeps GPU texture allocations reasonable |
| Pixel buffers | 4 max | Enough for double-buffering + scratch |
| Buffer dimensions | 512x512 per buffer | Covers NES 256x240 with headroom |
| Total image memory | 16 MB across images + buffers | Hard cap on sandbox memory footprint |

**Manifest additions for scripted plugins:**

```json
{
  "runtime": "scripted",
  "canvas_size": [480, 360],
  "permissions": ["voice_activity"]
}
```

If `canvas_size` is omitted, defaults to `[480, 360]`. Maximum allowed canvas size is `1280x720`.

**Security constraints summary:**

| Threat | Mitigation |
|--------|-----------|
| Filesystem access | RISC-V VM has no filesystem API; `load_image`/`load_sound` read only from the plugin's own `assets/` dir within the cached bundle |
| Network access | No network APIs registered; all network goes through `Plugin.send_action()` → client proxy |
| Engine API access | Only `Plugin.*` functions are registered with the Sandbox; all other Godot classes are unreachable |
| Memory corruption | RISC-V VM runs in isolated address space; cannot read/write host process memory |
| CPU exhaustion | Execution time-limited per frame (configurable, default 4ms budget) |
| Memory exhaustion | Memory limit per runtime (default 16 MB) |
| Cross-server data leak | Each server connection gets its own Sandbox instance |
| Input snooping | `_input` only receives events when activity panel has focus, confined to viewport bounds |

### Native Runtime (`native_runtime.gd`)

`NativeRuntime extends Node` hosts a GDScript scene instantiated from the cached plugin bundle. Unlike the scripted sandbox, native plugins run as regular Godot nodes with full engine access. Security relies on code signing and user trust rather than VM isolation.

**Why native plugins exist alongside scripted plugins:**

Some use cases (emulators, collaborative document editors, complex visualizations) need capabilities that the scripted sandbox intentionally blocks: direct scene tree manipulation, custom shaders, multiple scene files, and LiveKit data channel access for peer-to-peer communication. Native plugins fill this gap at the cost of requiring a higher trust level.

**For non-technical users:** Native plugins are like installing an app on your phone — you're trusting the developer. daccord verifies the plugin's digital signature (like an app store verifying the developer identity) and asks for your permission before running it. Once trusted, native plugins can do more powerful things than scripted plugins, like running a game emulator or a collaborative whiteboard.

**Lifecycle:**

```gdscript
func start(entry_scene_path: String, context: PluginContext) -> void
    # 1. load(entry_scene_path) -> PackedScene
    # 2. instantiate() -> add as child of ActivityViewport
    # 3. Call scene.setup(context) if the method exists

func stop() -> void
    # 1. Remove child scene
    # 2. Disconnect all data channel callbacks
    # 3. queue_free()
```

### Plugin Context (`plugin_context.gd`)

`PluginContext extends Resource` — the bridge API injected into native plugin scenes:

```gdscript
# Identity
var plugin_id: String
var session_id: String
var conn_index: int
var local_user_id: String

# Session state
var session_state: String          # "lobby", "running", "ended"
var participants: Array            # [{user_id, display_name, role}]

# Signals the plugin scene can connect to
signal data_received(topic: String, data: PackedByteArray, sender_id: String)
signal file_received(filename: String, data: PackedByteArray, sender_id: String)
signal session_state_changed(new_state: String)
signal participant_joined(user_id: String, role: String)
signal participant_left(user_id: String)
signal role_changed(user_id: String, new_role: String)

# Data channel methods (delegates to LiveKitAdapter)
func send_data(data: PackedByteArray, reliable: bool, topic: String,
               destinations: Array = []) -> void
    # Wraps LiveKitLocalParticipant.publish_data()
    # reliable=true: ordered delivery, up to 15 KiB per packet
    # reliable=false: lossy/unordered, recommended max ~1300 bytes per packet

func send_file(filename: String, data: PackedByteArray,
               destinations: Array = []) -> void
    # Sends via LiveKit reliable byte stream (auto-chunked at 15 KiB)
    # Receivers get file_received signal when reassembly completes

# Participant info
func get_participants() -> Array
func get_role(user_id: String = "") -> String  # default: local user
func is_host() -> bool

# Local file access (sandboxed — only triggered by explicit user file dialog)
func request_file(extensions: Array, max_size: int) -> PackedByteArray
    # Opens a native file dialog filtered by extensions
    # Returns file contents or empty array if cancelled
    # max_size enforced from manifest.max_file_size
```

### LiveKit Data Channel Integration

The plugin system uses LiveKit data channels (already exposed by godot-livekit but not yet used by daccord) for all real-time plugin communication. This avoids routing high-frequency data through the accordserver gateway.

**LiveKit data channel specs (from LiveKit docs):**

| Property | Reliable | Lossy |
|---|---|---|
| Delivery | Guaranteed, ordered, retransmits | Fire-and-forget, unordered |
| Max packet | 15 KiB | ~1,300 bytes (MTU safe) |
| Latency | Higher (head-of-line blocking) | Sub-frame on LAN |
| Use case | File transfer, keyframes, RPC | Frame diffs, input, cursor |

**Topic conventions for plugins:**

All plugin data channel messages use a topic prefix of `plugin:<plugin_id>:` to namespace them. The `PluginContext` methods handle this transparently.

| Topic | Direction | Mode | Payload | Rate |
|-------|-----------|------|---------|------|
| `plugin:<id>:frame_sync` | Host -> all | Lossy | Delta-compressed frame diff | ~60 Hz |
| `plugin:<id>:keyframe` | Host -> all | Reliable | Full frame state | Every 2-5 sec |
| `plugin:<id>:input` | Player -> host | Lossy | Button state bitmask | ~60 Hz |
| `plugin:<id>:file:<name>` | Host -> all | Reliable (byte stream) | File chunks (15 KiB each) | Burst |
| `plugin:<id>:state` | Host -> all | Reliable | Serialized game state | On change |
| `plugin:<id>:rpc` | Any -> any | Reliable | Request/response | On demand |

**LiveKitAdapter additions:**

```gdscript
# New methods in livekit_adapter.gd

func publish_plugin_data(data: PackedByteArray, reliable: bool,
                         topic: String, destinations: Array = []) -> void
    # Delegates to _room.local_participant.publish_data()
    # _room is the existing LiveKitRoom reference

func _on_data_received(data: PackedByteArray, participant: LiveKitRemoteParticipant,
                       kind: int, topic: String) -> void
    # Connected to LiveKitRoom.data_received signal
    # If topic starts with "plugin:": route to ClientPlugins.on_data_received()
    # Otherwise: ignore (reserved for future non-plugin data channel use)
```

### Activity Panel UI (`activity_panel.gd`)

Shown alongside (or instead of) the `MessageView` when an activity is active. Layout:
- Header bar: activity name, icon, runtime badge, "Leave Activity" button, participant count
- Main area: `SubViewport` node that the runtime draws into
- Footer: participant avatars in a horizontal strip (same Avatar component used elsewhere), with role indicators (controller icon for players)

State-dependent views:
- **LOBBY state:** Shows `ActivityLobby` scene (player slots, spectator list, start button)
- **RUNNING state:** Shows `ActivityViewport` with the plugin scene
- **ENDED state:** Shows "Activity ended" message with a dismiss button

Connects to:
- `AppState.activity_started` -> `_on_activity_started(plugin_id, channel_id)`
- `AppState.activity_ended` -> `_on_activity_ended(plugin_id)` -> hides panel
- `AppState.activity_session_state_changed` -> `_on_session_state_changed(state)` -> swap lobby/running view
- `AppState.activity_download_progress` -> `_on_download_progress(progress)` -> update progress bar
- `AppState.voice_left` -> calls `ClientPlugins.stop_activity()` if active

### Activity Lobby UI (`activity_lobby.gd`)

Shown when a native activity is in `LOBBY` state:

- Player slot grid: shows `max_participants` numbered slots, each either empty or filled with a user avatar + name
- "Claim Slot" / "Release Slot" button for each slot
- Spectator list below: all joined users who are not in a player slot
- "Start" button: visible only to the host (user who launched the activity), enabled when >= 1 player slot is filled
- File section (if `manifest.max_file_size > 0`): "Select File" button for the host to pick a ROM/asset, shows filename and size once selected, "Send to All" button to distribute via `PluginContext.send_file()`

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
bin/
  plugin.elf         # compiled RISC-V ELF binary (from SafeGDScript source)
src/                 # optional: original GDScript source for transparency/audit
  main.gd            # entry-point script
  lib/               # optional helper scripts
assets/
  icon.png           # 64x64 activity icon
  images/            # optional images referenced by Plugin.draw_image()
  sounds/            # optional audio clips referenced by Plugin.play_sound()
```

**Native plugin:**
```
plugin.json          # manifest (runtime: "native")
plugin.sig           # detached Ed25519 signature over plugin.json + all files
scenes/
  emulator.tscn      # entry-point scene
  lobby.tscn          # optional custom lobby scene
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

**For non-technical users:** Plugin signing works like a seal on a letter — it proves the plugin hasn't been tampered with since the developer created it. When you see "Signed by [developer]" in the activity picker, it means the plugin's code matches what the developer originally uploaded. Unsigned native plugins are always rejected.

**For developers and admins:**

Native plugins execute arbitrary GDScript in the client process. Unlike scripted plugins (which run in the godot-sandbox RISC-V VM with no engine access), native plugins have full access to the Godot API within their scene subtree. A code signing system is required to prevent malicious plugins.

**Signing flow:**

1. Plugin developer generates an Ed25519 keypair
2. Developer signs the bundle contents (all files concatenated in sorted order) with their private key
3. `plugin.sig` contains the detached signature
4. Server admin uploads the bundle; server stores the developer's public key alongside the plugin record
5. Client downloads the bundle and verifies the signature against the public key from the manifest
6. If verification fails, the bundle is rejected and the user sees an error

**Trust levels:**

| Level | Description | Requirements |
|-------|-------------|--------------|
| Unsigned | No signature | Scripted plugins only; native plugins rejected |
| Server-signed | Signed by the server admin's key | Admin has verified the plugin manually |
| Developer-signed | Signed by a registered developer key | Developer key is registered with the server |

**Client enforcement:**
- Scripted plugins: signature optional (RISC-V VM sandbox provides security)
- Native plugins: signature required; unsigned native plugins are rejected with an error dialog
- Users see a confirmation dialog before running any native plugin for the first time: "This activity runs native code from [server name]. Trust this server's plugins?"
- Per-server trust preference stored in `Config` (per-profile)

### Scripted vs Native: Choosing the Right Runtime

*A guide for plugin developers.*

| Factor | Scripted | Native |
|--------|----------|--------|
| **Language** | SafeGDScript (subset compiled to RISC-V) | Full GDScript + scenes |
| **Isolation** | RISC-V VM sandbox (memory-isolated, API-whitelisted) | Code signing + user trust |
| **Rendering** | `Plugin.draw_*` primitives into a SubViewport canvas | Full Godot scene tree (Control, Node2D, etc.) |
| **Data exchange** | `Plugin.send_action()` → server REST → `plugin.event` gateway broadcast | LiveKit data channels (peer-to-peer, low-latency) |
| **File sharing** | Not supported | `PluginContext.send_file()` via LiveKit byte stream |
| **Custom shaders** | Not supported | Supported (bundled in `assets/shaders/`) |
| **Multiple scenes** | Not supported (single ELF) | Supported (bundle contains multiple `.tscn` files) |
| **Signing required** | No | Yes (Ed25519) |
| **User trust prompt** | No | Yes (first-run confirmation dialog) |
| **Best for** | Board games, card games, polls, trivia, simple arcade games, interactive widgets | Emulators, collaborative editors, complex visualizations, anything needing LiveKit data channels |
| **Max complexity** | ~2,000 lines of GDScript (practical limit due to ELF size and API surface) | Unlimited |
| **Bundle size** | Typically <100 KB (ELF + assets) | Up to 50 MB (configurable server limit) |

### Server-Side Requirements (accordserver)

New routes needed in accordserver:

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/spaces/{space_id}/plugins` | List installed plugins |
| POST | `/spaces/{space_id}/plugins` | Install plugin (admin; bundle upload) |
| DELETE | `/spaces/{space_id}/plugins/{id}` | Uninstall plugin (admin) |
| GET | `/plugins/{id}/elf` | Serve compiled ELF binary (scripted; authenticated) |
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
bin/
  plugin.elf           # compiled from src/main.gd
src/
  main.gd              # chess game logic + rendering
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
  "canvas_size": [480, 480],
  "max_participants": 2,
  "max_spectators": 0,
  "lobby": true,
  "permissions": ["voice_activity"]
}
```

**Step 1 — Admin installs the plugin:**
Admin uploads `chess.daccord-plugin` via Server Settings -> Plugins. Server validates the manifest, stores the ELF binary, and broadcasts `plugin.installed` to all clients. Clients cache the manifest (not the ELF).

**Step 2 — User launches the activity:**
User is in a voice channel. Clicks the rocket button -> activity modal shows "Chess" card with "Scripted" badge. Clicks "Launch."

**Step 3 — ELF download and sandbox creation:**
`ClientPlugins` calls `PluginsApi.get_elf()` to fetch the compiled binary (~50 KB). A `ScriptedRuntime` is created with a `Sandbox` node. The `Plugin.*` bridge API is registered as the only callable interface. The ELF is loaded into the sandbox.

**Step 4 — Lobby:**
Session created via `POST /plugins/{id}/sessions`. The lobby shows two player slots. Both players claim slots. Host clicks "Start."

**Step 5 — Gameplay:**
The sandboxed script's `_ready()` loads the board and piece images via `Plugin.load_image()`. Each frame, `_draw()` renders the board and pieces using `Plugin.draw_image_region()` (sprite sheet). When a player clicks a square, `_input()` detects it and calls `Plugin.send_action({from = "e2", to = "e4"})`. The server validates the move and broadcasts the updated board state. All participants' sandboxed runtimes receive the event and re-render.

**Step 6 — Game ends:**
When checkmate occurs, the script renders a "Checkmate!" overlay. Players leave the activity or the host closes it. The sandbox is freed and the session is deleted.

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
First time from this server: user sees "This activity runs native code from [server name]. Trust this server's plugins?" and clicks "Allow." `PluginDownloadManager.is_cached()` returns false (first launch). Client fetches the bundle via `GET /plugins/{id}/bundle` (1 MB). Progress bar updates via `AppState.activity_download_progress`. SHA-256 hash verified. Ed25519 signature verified. Bundle extracted to `user://plugins/<server_id>/nes-emulator/`. On subsequent launches, this step is skipped unless the server reports a new version.

**Step 4 — Lobby:**
Session created via `POST /plugins/{id}/sessions`. `NativeRuntime` instantiates `scenes/emulator.tscn` and calls `setup(context)`. The emulator scene shows a lobby: two player slots, spectator list, and a "Select ROM" button for the host.

**Step 5 — ROM distribution:**
Host clicks "Select ROM" -> `PluginContext.request_file([".nes"], 1048576)` opens a file dialog. Host selects `mario.nes` (40 KB). Plugin calls `context.send_file("mario.nes", rom_data)`. LiveKit reliable byte stream sends the file in 15 KiB chunks. All participants receive `file_received("mario.nes", data, host_id)` and load the ROM into their local emulator instance.

**Step 6 — Game starts:**
Host clicks "Start" -> `ClientPlugins.start_session()` -> `PATCH /plugins/{id}/sessions/{sid}` -> gateway broadcasts `plugin.session_state {state: "running"}`. All clients transition from lobby to running view.

**Step 7 — Gameplay:**
- **Host emulator** runs the NES CPU/PPU at 60 FPS, producing a 256x240 frame buffer each frame.
- **Frame encoder** computes a delta from the previous frame. Typical NES frame diffs are 500 B - 2 KB (tiles are reused heavily). Diffs within 1,300 bytes go via lossy channel; larger diffs are sent reliable.
- **Host** calls `context.send_data(diff, false, "frame_sync")` at 60 Hz.
- **Host** calls `context.send_data(full_frame, true, "keyframe")` every 2 seconds for drift correction.
- **Players** capture local input each frame (8 NES buttons = 1 byte bitmask per controller). Call `context.send_data(input_bitmask, false, "input")` at 60 Hz.
- **Host** receives player inputs via `context.data_received` on topic `input`, feeds them into the emulator before computing the next frame.
- **Spectators** receive frame diffs and keyframes, apply them to their local frame buffer, but never send input.

**Step 8 — Bandwidth estimate:**
- Frame diffs: ~1 KB x 60/sec = ~60 KB/sec (480 kbps) outbound from host
- Keyframes: ~60 KB x 0.5/sec = ~30 KB/sec (240 kbps) outbound from host
- Input: ~4 bytes x 60/sec x 2 players = ~480 B/sec inbound to host
- Total host upload: ~720 kbps — well within typical broadband and LiveKit capacity

**Step 9 — Activity ends:**
Host disconnects from voice or clicks "Leave Activity." `ClientPlugins.stop_activity()` tears down the runtime, deletes the session, and emits `AppState.activity_ended`. All participants' emulator scenes are freed. The cached bundle remains for next time.

## Implementation Status

### Core plugin infrastructure
- [ ] `AccordPluginManifest` model with runtime/lobby/signing fields
- [ ] `PluginsApi` REST endpoints in AccordKit (list, install, delete, bundle download, sessions, roles)
- [ ] `plugin_installed` / `plugin_uninstalled` / `plugin_event` / `plugin_session_state` / `plugin_role_changed` gateway signals in `gateway_socket.gd`
- [ ] AccordClient plugin signal re-emit and `plugins: PluginsApi` exposure
- [ ] AppState plugin/activity/lobby signals and state variables
- [ ] `ClientPlugins` helper class with lobby and role management
- [ ] `ClientGatewayEvents` plugin event handlers (`on_plugin_installed`, `on_plugin_uninstalled`, `on_plugin_event`, `on_plugin_session_state`, `on_plugin_role_changed`)
- [ ] `ClientGateway` signal wiring for plugin signals
- [ ] Per-server isolation enforced in `ClientPlugins` via `conn_index`

### Scripted runtime (godot-sandbox)
- [ ] godot-sandbox GDExtension integrated as addon dependency (Godot 4.3+)
- [ ] `ScriptedRuntime` node wrapping `Sandbox` with `Plugin.*` API registration
- [ ] `PluginCanvas` draw target inside sandboxed `SubViewport`
- [ ] Plugin bridge API: drawing primitives (`draw_rect`, `draw_circle`, `draw_line`, `draw_text`, `draw_pixel`)
- [ ] Plugin image loading and sprite sheet rendering (`load_image`, `draw_image`, `draw_image_region`)
- [ ] Plugin frame buffer API (`create_buffer`, `set_buffer_data`, `draw_buffer`) for emulator-style rendering
- [ ] Plugin input routing (`_input` callback with viewport-confined events)
- [ ] Plugin audio playback (`load_sound`, `play_sound`) for plugin sound effects
- [ ] Canvas coordinate clamping and viewport confinement enforcement
- [ ] Image/buffer memory budget enforcement (16 MB cap, 64 images, 4 buffers)
- [ ] SafeGDScript compilation toolchain (editor integration or CLI for plugin developers)

### Native runtime
- [ ] `NativeRuntime` scene host with `PluginContext` injection
- [ ] `PluginContext` resource with data channel, file sharing, and participant APIs
- [ ] `PluginDownloadManager` — download, hash verify, cache, extract

### LiveKit data channels
- [ ] `LiveKitAdapter` additions: `publish_plugin_data()`, `_on_data_received()` routing
- [ ] Data channel topic namespacing (`plugin:<id>:<topic>`)
- [ ] File transfer via reliable byte stream (chunking + reassembly)

### Lobby system
- [ ] `ActivityLobby` scene (player slots, spectator list, start button)
- [ ] Session state machine (LOBBY -> RUNNING -> ENDED)
- [ ] Participant role assignment (PLAYER / SPECTATOR)
- [ ] Late joiner handling (join as spectator, receive current state)

### Plugin signing
- [ ] Ed25519 signature generation tooling
- [ ] Client-side signature verification for native plugins
- [ ] Trust confirmation dialog for first-run native plugins
- [ ] Per-server trust preference in Config

### UI
- [ ] `ActivityPanel` scene (viewport host + lobby/running state views)
- [ ] `ActivityModal` scene (activity picker from voice bar)
- [ ] Voice bar "Launch Activity" rocket button
- [ ] `MainWindow` layout integration for `ActivityPanel`
- [ ] Download progress bar in activity panel
- [ ] Admin Plugins settings page

### Server-side (accordserver)
- [ ] Plugin bundle storage and manifest registry
- [ ] REST routes for plugin management, bundle serving, sessions, roles
- [ ] Gateway `plugin.*` event dispatch (installed, uninstalled, event, session_state, role_changed)
- [ ] Plugin action routing for scripted plugins
- [ ] Session state machine with role assignment
- [ ] SafeGDScript -> RISC-V ELF compilation (server-side or require pre-compiled upload)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No accordserver plugin subsystem | High | Server has no plugin routes, no session management, no bundle storage, and no `plugin.*` gateway events; entire backend must be built first |
| godot-sandbox addon not yet integrated | High | The [godot-sandbox](https://github.com/libriscv/godot-sandbox) GDExtension must be added as a project dependency; supports Godot 4.3+ and all target platforms |
| SafeGDScript compilation toolchain | High | Plugin developers need a way to compile GDScript to RISC-V ELF binaries; godot-sandbox provides editor integration but the workflow for building `.daccord-plugin` bundles needs design |
| `interaction_create` handler is a stub | High | `client_gateway_events.gd` line 95 handles `interaction_create` with `pass`; bot/plugin interactions need a real dispatch path |
| No plugin sandbox isolation test suite | High | Sandbox security properties (no FS access, no cross-server calls, API whitelist enforcement) need automated tests before plugins ship to users |
| No plugin signing implementation | High | Native plugins execute arbitrary GDScript; without Ed25519 signing + verification, any server admin can push malicious code to clients |
| LiveKit data channels not wired in daccord | High | `publish_data()` and `data_received` are available in godot-livekit (see godot_livekit.md LIVEKIT-2) but `livekit_adapter.gd` has no data channel methods; must be added before any plugin data flow works |
| No file transfer via LiveKit byte streams | High | LiveKit supports byte stream API for large payloads but godot-livekit may not expose it; if not, file transfer must be implemented as manual chunking over `publish_data(reliable=true)` with reassembly |
| No native plugin scene sandboxing | High | Native plugins run as regular Godot nodes; they could potentially access autoloads, other scenes, or the filesystem. Mitigation: code signing + user trust (VM-level sandboxing is not feasible for native plugins in GDScript) |
| `ChannelType` enum has no ACTIVITY type | Medium | `client_models.gd` line 7 enum has TEXT/VOICE/ANNOUNCEMENT/FORUM/CATEGORY; activities launched from voice don't need a new channel type, but a plugin-owned channel type may be needed for persistent activity channels |
| No plugin asset CDN integration | Medium | Plugin images/icons served via the plugin ELF/bundle endpoint; the existing CDN URL pattern (`conn.cdn_url`) needs to extend to plugin assets |
| Voice bar has no "Launch Activity" button | Medium | `voice_bar.gd` currently has Mic/Deaf/Cam/Share/SFX/Settings/Disconnect; the rocket button and its signal wiring need to be added |
| No activity session state persistence | Medium | If the user closes and reopens the app during an active activity, there is no reconnect path; session recovery requires server-side session lookup |
| No emulator core | Medium | The NES emulator plugin is a worked example; an actual NES CPU/PPU emulator must be written in GDScript or provided as a GDExtension within the plugin bundle |
| Frame diff compression algorithm not specified | Medium | The emulator example assumes delta compression + RLE for frame diffs; the exact algorithm needs implementation and testing to stay within the 1,300-byte lossy packet limit for typical NES frames |
| Max participants not enforced client-side | Low | `max_participants` in the manifest should grey out "Claim Slot" when all player slots are full; requires polling or a `plugin.session_full` event |
| No activity join notification for late joiners | Low | Users who join a voice channel after an activity has started see no indication that an activity is running; a gateway `plugin.session_state` event or a voice state flag is needed |
| Scripted plugin font support limited | Low | `Plugin.draw_text()` uses a built-in bitmap font; no custom font loading is supported. Could add `Plugin.load_font()` for plugin-supplied bitmap fonts in a future iteration |
| No plugin update notification | Low | When a server updates a plugin to a new version, clients with a stale cached bundle need to be notified to re-download; could piggyback on `plugin.installed` with a version field |
| No plugin size limits | Low | Server should enforce maximum bundle size to prevent abuse (e.g., 50 MB cap); client should also reject bundles exceeding a configurable limit |
