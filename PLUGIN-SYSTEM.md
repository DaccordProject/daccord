# Plugin System Implementation Plan

This document is the implementation plan for the server plugins feature described in `user_flows/server_plugins.md`. It covers work across three repositories:

- **daccord** (this repo) — Godot 4.5 client
- **accordserver** (`../accordserver`) — Rust backend
- **daccord-codenames** (`../daccord-codenames`) — Example scripted plugin (Codenames board game)

The plan is split into phases. Each phase produces a working vertical slice that can be tested end-to-end before moving on.

---

## Phase 0: Foundation — AccordKit Models & Signals

**Goal:** Define all data types, signals, and API stubs so that subsequent phases can be built in parallel.

### 0.1 AccordKit: Plugin Manifest Model

**File:** `addons/accordkit/models/plugin_manifest.gd` (new)

Create `AccordPluginManifest extends RefCounted`:

```
id, name, type, runtime, description, icon_url, elf_url, entry_point,
bundle_size, bundle_hash, max_participants, max_spectators, max_file_size,
version, permissions, lobby, data_topics, signed, signature, canvas_size
```

Include `static func from_dict(d: Dictionary) -> AccordPluginManifest` and `func to_dict() -> Dictionary`.

### 0.2 AccordKit: Enums

**File:** `addons/accordkit/models/plugin_manifest.gd` (same file, top-level enums)

```gdscript
enum PluginRuntime { SCRIPTED, NATIVE }
enum SessionState { LOBBY, RUNNING, ENDED }
enum ParticipantRole { SPECTATOR, PLAYER }
```

### 0.3 AccordKit: PluginsApi REST Stubs

**File:** `addons/accordkit/rest/endpoints/plugins_api.gd` (new)

Stub all REST methods (return type `RestResult` via await):

| Method | Endpoint |
|--------|----------|
| `list_plugins(space_id, type)` | `GET /spaces/{space_id}/plugins` |
| `install_plugin(space_id, bundle_path)` | `POST /spaces/{space_id}/plugins` |
| `delete_plugin(space_id, plugin_id)` | `DELETE /spaces/{space_id}/plugins/{id}` |
| `get_elf(plugin_id)` | `GET /plugins/{id}/elf` |
| `get_bundle(plugin_id)` | `GET /plugins/{id}/bundle` |
| `create_session(plugin_id, channel_id)` | `POST /plugins/{id}/sessions` |
| `delete_session(plugin_id, session_id)` | `DELETE /plugins/{id}/sessions/{sid}` |
| `update_session_state(plugin_id, session_id, state)` | `PATCH /plugins/{id}/sessions/{sid}` |
| `assign_role(plugin_id, session_id, user_id, role)` | `POST /plugins/{id}/sessions/{sid}/roles` |
| `send_action(plugin_id, session_id, data)` | `POST /plugins/{id}/sessions/{sid}/actions` |

### 0.4 AccordKit: Gateway Signals

**File:** `addons/accordkit/gateway/gateway_socket.gd` (edit)

Add signals and dispatch cases:

```
signal plugin_installed(manifest: Dictionary)
signal plugin_uninstalled(plugin_id: String)
signal plugin_event(plugin_id: String, event_type: String, data: Dictionary)
signal plugin_session_state(plugin_id: String, session_id: String, state: String)
signal plugin_role_changed(plugin_id: String, session_id: String, user_id: String, role: String)
```

Dispatch in `_dispatch_event()` for event names `plugin.installed`, `plugin.uninstalled`, `plugin.event`, `plugin.session_state`, `plugin.role_changed`.

### 0.5 AccordClient: Expose Plugins

**File:** `addons/accordkit/core/accord_client.gd` (edit)

- Add `var plugins: PluginsApi` initialized in `_init()`
- Re-emit gateway plugin signals

### 0.6 AppState: Plugin Signals & State

**File:** `scripts/autoload/app_state.gd` (edit)

Signals:
```
plugins_updated()
activity_started(plugin_id, channel_id)
activity_ended(plugin_id)
activity_download_progress(plugin_id, progress)
activity_session_state_changed(plugin_id, state)
activity_role_changed(plugin_id, user_id, role)
```

State:
```
active_activity_plugin_id, active_activity_channel_id,
active_activity_session_id, active_activity_session_state, active_activity_role
```

### 0.7 Client Gateway Events: Plugin Handlers

**File:** `scripts/autoload/client_gateway_events.gd` (edit)

Add handler stubs: `on_plugin_installed`, `on_plugin_uninstalled`, `on_plugin_event`, `on_plugin_session_state`, `on_plugin_role_changed`.

**File:** `scripts/autoload/client_gateway.gd` (edit)

Wire gateway signals to the new handlers.

---

## Phase 1: Server-Side Plugin Subsystem (accordserver)

**Goal:** accordserver can store plugins, serve ELF/bundle files, manage sessions, and broadcast gateway events.

### 1.1 Database Schema

**File:** `migrations/` (new migration)

Tables:
- `plugins` — id, space_id, name, type, runtime, description, version, manifest_json, elf_blob (BLOB), bundle_blob (BLOB), icon_blob, bundle_hash, signed, created_at
- `plugin_sessions` — id, plugin_id, channel_id, host_user_id, state (lobby/running/ended), created_at
- `plugin_session_participants` — session_id, user_id, role (player/spectator), slot_index (nullable)

### 1.2 REST Routes

**File:** `src/routes/plugins.rs` (new)

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET | `/spaces/{sid}/plugins` | Member | List plugins, optional `?type=` filter |
| POST | `/spaces/{sid}/plugins` | Admin | Upload `.daccord-plugin` bundle (multipart) |
| DELETE | `/spaces/{sid}/plugins/{pid}` | Admin | Delete plugin + broadcast `plugin.uninstalled` |
| GET | `/plugins/{pid}/elf` | Member | Serve ELF binary (scripted) |
| GET | `/plugins/{pid}/bundle` | Member | Serve ZIP bundle (native) |
| POST | `/plugins/{pid}/sessions` | Member | Create session → returns `{session_id, state}` |
| DELETE | `/plugins/{pid}/sessions/{sid}` | Host | End session |
| PATCH | `/plugins/{pid}/sessions/{sid}` | Host | Update state (`{state: "running"}`) |
| POST | `/plugins/{pid}/sessions/{sid}/roles` | Member | `{user_id, role}` |
| POST | `/plugins/{pid}/sessions/{sid}/actions` | Member | Forward action → broadcast `plugin.event` |

### 1.3 Bundle Validation

On upload:
1. Parse ZIP, extract `plugin.json`
2. Validate manifest schema (required fields, valid runtime, valid type)
3. For scripted: extract `bin/plugin.elf`, store as `elf_blob`
4. For native: verify `plugin.sig` exists, store entire ZIP as `bundle_blob`
5. Store `icon.png` as `icon_blob` if present
6. Insert into `plugins` table
7. Broadcast `plugin.installed` gateway event with manifest

### 1.4 Gateway Events

**File:** `src/gateway/dispatcher.rs` (edit)

Add dispatch for:
- `plugin.installed` — broadcast to all space members
- `plugin.uninstalled` — broadcast to all space members
- `plugin.event` — broadcast to session participants only
- `plugin.session_state` — broadcast to session participants
- `plugin.role_changed` — broadcast to session participants

### 1.5 Action Routing (Scripted Plugins)

For `POST /plugins/{pid}/sessions/{sid}/actions`:
1. Receive action data from a participant
2. Store/validate (server is authoritative for game state in scripted plugins)
3. Broadcast `plugin.event` with `{type: "state_update", data: ...}` to all session participants

**Initial approach:** The server acts as a simple relay — it broadcasts the action to all participants without game-specific validation. Game logic validation will be handled by an optional server-side plugin handler in a future phase.

### 1.6 Test Seed Support

**File:** `src/routes/test.rs` (edit)

Extend the `/test/seed` endpoint to optionally create a test plugin (scripted, with a minimal ELF stub) so integration tests can exercise the plugin API without manually uploading bundles.

---

## Phase 2: ClientPlugins Helper & Gateway Wiring (daccord)

**Goal:** Client can fetch plugin lists, launch/stop activities, and receive gateway events. No UI yet — driven by tests.

### 2.1 ClientPlugins Helper

**File:** `scripts/autoload/client_plugins.gd` (new)

```gdscript
extends RefCounted

var _plugin_cache: Dictionary = {}   # conn_index -> { plugin_id -> manifest dict }
var _active_runtime: Node = null
var _active_session_id: String = ""
var _active_conn_index: int = -1

func fetch_plugins(conn_index: int, space_id: String) -> void
func get_plugins(conn_index: int) -> Array
func launch_activity(plugin_id: String, channel_id: String) -> void
func stop_activity(plugin_id: String) -> void
func assign_role(user_id: String, role: String) -> void
func start_session() -> void
func send_action(plugin_id: String, data: Dictionary) -> void

# Gateway event handlers
func on_plugin_installed(manifest: Dictionary, conn_index: int) -> void
func on_plugin_uninstalled(plugin_id: String, conn_index: int) -> void
func on_plugin_event(plugin_id: String, event_type: String, data: Dictionary) -> void
func on_plugin_session_state(plugin_id: String, session_id: String, state: String) -> void
func on_plugin_role_changed(plugin_id: String, session_id: String, user_id: String, role: String) -> void
```

### 2.2 Client Integration

**File:** `scripts/autoload/client.gd` (edit)

- Add `var _plugins: ClientPlugins` initialized in `_ready()`
- Expose `plugins` property
- In `connect_server()`, after space loads, call `_plugins.fetch_plugins(conn_index, space_id)`

### 2.3 Gateway Event Wiring

**File:** `scripts/autoload/client_gateway_events.gd` (edit existing stubs from Phase 0)

Implement handlers that delegate to `Client.plugins.on_plugin_*()`.

**File:** `scripts/autoload/client_gateway.gd` (edit)

Connect AccordClient gateway signals to ClientGatewayEvents handlers.

### 2.4 Integration Tests

**File:** `tests/accordkit/integration/test_plugins_api.gd` (new)

- List plugins (empty), install plugin, list plugins (1 result)
- Get ELF binary, verify non-empty
- Create session, verify response
- Assign role, update session state
- Send action, verify gateway `plugin.event` received
- Delete session, delete plugin

---

## Phase 3: Scripted Runtime — godot-sandbox Integration (daccord)

**Goal:** A scripted plugin's ELF binary can be loaded into a Sandbox node and rendered into a SubViewport.

### 3.1 ScriptedRuntime

**File:** `scenes/plugins/scripted_runtime.gd` (new)

- Creates `SubViewport` + `PluginCanvas` (Node2D child)
- Creates `Sandbox` node, loads ELF binary
- Registers `Plugin.*` bridge functions with the Sandbox:
  - Canvas info: `canvas_width`, `canvas_height`
  - Drawing: `clear`, `draw_rect`, `draw_circle`, `draw_line`, `draw_text`, `draw_pixel`
  - Images: `load_image`, `draw_image`, `draw_image_region`, `draw_image_scaled`
  - Buffers: `create_buffer`, `set_buffer_pixel`, `set_buffer_data`, `draw_buffer`, `draw_buffer_scaled`
  - State: `send_action`, `get_state`, `on_event`
  - Participants: `get_participants`, `get_role`
  - Timers: `set_interval`, `set_timeout`
  - Audio: `load_sound`, `play_sound`, `stop_sound`
- Enforces memory/image/buffer limits
- Routes `_input` events (confined to viewport bounds)
- Calls sandboxed `_ready()` once, `_draw()` each frame

### 3.2 PluginCanvas

**File:** `scenes/plugins/plugin_canvas.gd` (new)

`PluginCanvas extends Node2D` — receives draw command queue from `ScriptedRuntime` and executes them in `_draw()` override. Clamps all coordinates to canvas bounds.

### 3.3 Bridge API Implementation

The `Plugin.*` functions are host-side GDScript methods that the Sandbox calls via its registered function table. Each function validates arguments, clamps coordinates, and either queues a draw command (for rendering) or delegates to `ClientPlugins` (for actions/events).

### 3.4 Runtime Lifecycle

```
start(elf_data: PackedByteArray, manifest: AccordPluginManifest) -> void
    # Create Sandbox, load ELF, register API, call _ready()

stop() -> void
    # Stop sandbox execution, free viewport, queue_free()

on_plugin_event(event_type: String, data: Dictionary) -> void
    # Forward to sandbox's registered event handlers
```

---

## Phase 4: UI — Activity Modal, Panel, Lobby, Voice Bar Button (daccord)

**Goal:** Users can browse, launch, and interact with activities from the voice bar.

### 4.1 Voice Bar: Launch Activity Button

**File:** `scenes/sidebar/voice_bar.gd` (edit), `scenes/sidebar/voice_bar.tscn` (edit)

- Add rocket icon button to `ButtonRow` (after existing buttons)
- On press: emit `AppState.launch_activity_pressed` or directly open `ActivityModal`
- Only visible when user is in a voice channel

### 4.2 Activity Modal

**Files:** `scenes/plugins/activity_modal.gd`, `scenes/plugins/activity_modal.tscn` (new)

- Popup modal listing available activities for the current server
- Each card: icon, name, description, runtime badge ("Scripted"/"Native"), max participants, bundle size (native only), "Launch" button
- Fetches list from `Client.plugins.get_plugins(conn_index)`
- On launch: calls `Client.plugins.launch_activity(plugin_id, channel_id)`

### 4.3 Activity Panel

**Files:** `scenes/plugins/activity_panel.gd`, `scenes/plugins/activity_panel.tscn` (new)

- Header: activity name, icon, runtime badge, participant count, "Leave Activity" button
- Main area switches based on session state:
  - LOBBY → shows `ActivityLobby`
  - RUNNING → shows `TextureRect` displaying the runtime's `SubViewport` texture
  - ENDED → shows "Activity ended" message
- Footer: participant avatars with role indicators
- Download progress bar (for native plugins)

### 4.4 Activity Lobby

**Files:** `scenes/plugins/activity_lobby.gd`, `scenes/plugins/activity_lobby.tscn` (new)

- Player slot grid (count from `max_participants`)
- "Claim Slot" / "Release Slot" per slot
- Spectator list
- "Start" button (host only, enabled when >= 1 player)

### 4.5 Main Window Integration

**File:** `scenes/main/main_window.gd` (edit), `scenes/main/main_window.tscn` (edit)

- Add `ActivityPanel` node alongside `MessageView`
- When activity starts: show panel (either side-by-side or replacing messages, depending on layout mode)
- When activity ends: hide panel, restore message view

---

## Phase 5: Codenames — Example Scripted Plugin

**Goal:** A fully working Codenames game demonstrating the scripted plugin runtime end-to-end.

### 5.1 Project Setup

**Directory:** `../daccord-codenames/`

This is a standalone Godot project used to develop and compile the plugin. It uses godot-sandbox's editor toolchain to compile GDScript → RISC-V ELF.

```
daccord-codenames/
  project.godot
  addons/
    godot_sandbox/          # symlink or copy from daccord
  plugin.json               # plugin manifest
  src/
    main.gd                 # entry point — compiled to ELF
    words.gd                # word list data
    board.gd                # board state management
  assets/
    icon.png                # 64x64 activity icon
    images/
      card_red.png
      card_blue.png
      card_neutral.png
      card_assassin.png
      card_back.png
  export/
    plugin.elf              # compiled output
    codenames.daccord-plugin  # packaged bundle (ZIP)
```

### 5.2 Game Rules (Codenames)

- **Players:** 4+ (2 teams of 2+), but we'll support 2–8 with flexible team assignment
- **Board:** 5x5 grid of 25 word cards
- **Roles:** Spymaster (1 per team, sees card colors) and Operative (guesses)
- **Turn flow:**
  1. Spymaster gives a one-word clue + number (how many cards match)
  2. Operatives click cards to guess
  3. Card revealed: red, blue, neutral (end turn), or assassin (lose)
  4. First team to find all their cards wins
- **Simplified for scripted plugin:** Server-authoritative state, all game logic in the sandboxed script

### 5.3 Plugin Manifest

```json
{
  "id": "codenames",
  "name": "Codenames",
  "type": "activity",
  "runtime": "scripted",
  "description": "Give clues. Guess words. Find your agents before the other team.",
  "version": "1.0.0",
  "canvas_size": [640, 480],
  "max_participants": 8,
  "max_spectators": -1,
  "lobby": true,
  "permissions": ["voice_activity"]
}
```

### 5.4 Game State (Server-Authoritative)

The game state dictionary broadcast via `plugin.event`:

```gdscript
{
  "phase": "lobby" | "clue" | "guess" | "game_over",
  "board": [
    {"word": "APPLE", "color": "red", "revealed": false},
    # ... 25 cards
  ],
  "teams": {
    "red": {"spymaster": "user_id", "operatives": ["user_id", ...]},
    "blue": {"spymaster": "user_id", "operatives": ["user_id", ...]}
  },
  "current_team": "red",
  "clue": {"word": "", "count": 0},
  "guesses_remaining": 0,
  "scores": {"red": 0, "blue": 0},
  "winner": ""
}
```

### 5.5 Actions

| Action | Payload | Who |
|--------|---------|-----|
| `join_team` | `{team: "red"\|"blue", role: "spymaster"\|"operative"}` | Any (lobby) |
| `start_game` | `{}` | Host |
| `give_clue` | `{word: "fruit", count: 2}` | Spymaster (clue phase) |
| `guess_card` | `{index: 7}` | Operative (guess phase) |
| `end_guessing` | `{}` | Operative (pass remaining guesses) |

### 5.6 Rendering (Plugin.draw_* API)

Layout (640x480):
- **Top bar** (0–40): Team scores, current phase, whose turn
- **Board** (40–420): 5x5 grid of cards (each ~120x72)
  - Unrevealed: show word text on neutral background
  - Revealed: show colored background (red/blue/neutral/black)
  - Spymaster sees all colors (semi-transparent overlay on unrevealed)
- **Bottom bar** (420–480): Clue input area or current clue display
- **Card hover:** highlight border on mouse hover
- **Card click:** send `guess_card` action

Uses `Plugin.draw_rect()` for card backgrounds, `Plugin.draw_text()` for words, `Plugin.draw_image()` for card textures if available (falls back to colored rects).

### 5.7 Input Handling

```gdscript
func _input(event: Dictionary):
    if event.type == "mouse_button" and event.pressed:
        var card_index = _hit_test_card(event.position_x, event.position_y)
        if card_index >= 0:
            if game_state.phase == "guess":
                Plugin.send_action({"action": "guess_card", "index": card_index})
    if event.type == "key" and event.pressed and event.key == KEY_ENTER:
        if game_state.phase == "clue" and _is_spymaster():
            Plugin.send_action({"action": "give_clue", "word": _clue_input, "count": _clue_count})
```

### 5.8 Build & Package

```bash
# In daccord-codenames/
# 1. Compile GDScript to ELF using godot-sandbox toolchain
#    (exact command depends on godot-sandbox CLI — may be editor button or cmake build)

# 2. Package as .daccord-plugin
cd export/
cp ../plugin.json .
cp plugin.elf bin/plugin.elf
cp -r ../assets/ assets/
zip -r codenames.daccord-plugin plugin.json bin/ assets/
```

---

## Phase 6: Native Runtime & LiveKit Data Channels (daccord)

**Goal:** Native plugins can run full GDScript scenes with LiveKit data channel communication.

### 6.1 PluginContext Resource

**File:** `scenes/plugins/plugin_context.gd` (new)

Bridge API for native plugins:
- Identity: `plugin_id`, `session_id`, `conn_index`, `local_user_id`
- Session: `session_state`, `participants`
- Signals: `data_received`, `file_received`, `session_state_changed`, `participant_joined`, `participant_left`, `role_changed`
- Methods: `send_data()`, `send_file()`, `get_participants()`, `get_role()`, `is_host()`, `request_file()`

### 6.2 NativeRuntime

**File:** `scenes/plugins/native_runtime.gd` (new)

- `start(entry_scene_path, context)` — load scene, instantiate, call `setup(context)`
- `stop()` — disconnect data channels, free scene

### 6.3 PluginDownloadManager

**File:** `scripts/autoload/plugin_download_manager.gd` (new)

- Cache at `user://plugins/<server_id>/<plugin_id>/`
- `is_cached(server_id, plugin_id, expected_hash) -> bool`
- `download_bundle(conn_index, plugin_id, manifest) -> void`
- Hash + signature verification
- Progress reporting via `AppState.activity_download_progress`

### 6.4 LiveKit Data Channel Wiring

**File:** `scripts/autoload/livekit_adapter.gd` (edit)

- Add `publish_plugin_data(data, reliable, topic, destinations)`
- Connect `LiveKitRoom.data_received` signal
- Route `plugin:*` topics to `ClientPlugins.on_data_received()`

### 6.5 Plugin Signing

- Ed25519 signature verification in `PluginDownloadManager`
- Trust confirmation dialog for first-run native plugins
- Per-server trust preference in `Config`

---

## Phase 7: Admin UI & Polish

**Goal:** Server admins can manage plugins. Polish and edge cases.

### 7.1 Plugins Settings Page

**Files:** `scenes/settings/plugins_settings.gd`, `scenes/settings/plugins_settings.tscn` (new)

- List installed plugins with name, runtime badge, version, uninstall button
- Upload button → file dialog for `.daccord-plugin` files
- Calls `PluginsApi.install_plugin()` / `delete_plugin()`

### 7.2 Edge Cases

- Late joiner handling (join as spectator, receive current state via gateway)
- Activity cleanup on voice disconnect
- Plugin uninstall while activity is running → graceful teardown
- Session recovery on reconnect (future — mark as "nice to have")

### 7.3 Tests

- Unit tests for `ClientPlugins`, `ScriptedRuntime`, `PluginCanvas`
- Integration tests for full activity lifecycle (install → launch → lobby → play → end)
- Sandbox isolation tests (verify no FS/network/autoload access)

---

## Phase Order & Dependencies

```
Phase 0 ─── Foundation (models, signals, stubs)
  │
  ├── Phase 1 ─── Server-side (accordserver, can be done in parallel with Phase 2)
  │     │
  │     └── Phase 2 ─── ClientPlugins + gateway wiring (needs server for integration tests)
  │           │
  │           ├── Phase 3 ─── Scripted runtime (godot-sandbox)
  │           │     │
  │           │     └── Phase 5 ─── Codenames plugin (needs scripted runtime working)
  │           │
  │           └── Phase 4 ─── UI (can start after Phase 2, needs Phase 3 for running view)
  │
  └── Phase 6 ─── Native runtime + LiveKit (independent of scripted runtime)
        │
        └── Phase 7 ─── Admin UI + polish
```

**Recommended build order:**

1. **Phase 0** — Do first, unlocks everything else
2. **Phase 1 + Phase 2** — In parallel where possible; Phase 2 integration tests need Phase 1
3. **Phase 3** — Scripted runtime; this is the critical path for the Codenames demo
4. **Phase 4** — UI; can start activity modal/panel while Phase 3 is in progress
5. **Phase 5** — Codenames plugin; validates the entire scripted pipeline end-to-end
6. **Phase 6** — Native runtime; lower priority, not needed for initial demo
7. **Phase 7** — Admin UI and polish; last

---

## Key Risks

| Risk | Mitigation |
|------|-----------|
| godot-sandbox API differs from what we've designed | Phase 3 starts with a spike: load a minimal ELF, register one function, verify it works. Adjust bridge API design based on actual Sandbox class API |
| SafeGDScript compilation toolchain unclear | Research godot-sandbox's actual compile flow early in Phase 3. May need cmake + zig (the addon's `downloader.gd` installs these) |
| LiveKit data channels not exposed by godot-livekit | Check `LiveKitRoom` API for `publish_data` / `data_received`. If missing, this blocks Phase 6 and needs godot-livekit changes |
| Server-side game logic validation for scripted plugins | Phase 1 starts with simple relay (no validation). Game-specific validation (e.g., chess move legality) deferred to a future "server-side plugin handler" phase |
| Bundle size and memory limits | Enforce early: 50 MB bundle cap, 16 MB runtime memory, 64 image / 4 buffer limits in ScriptedRuntime |

---

## What's NOT In Scope

- Server-side game logic execution (WASM/scripting on accordserver) — scripted plugins use client-relay for now
- Plugin marketplace / discovery beyond the current server
- Custom fonts for scripted plugins
- Plugin update notifications (future iteration)
- Activity channels (persistent plugin-owned channels)
