# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Daccord is a multi-platform (Linux, Windows, Android, Web) real-time chat client built with **Godot 4.5** and **GDScript**. It connects to [accordserver](https://github.com/daccord-projects/accordserver) (Rust backend) via REST + WebSocket APIs. The in-tree **AccordKit** addon (`addons/accordkit/`) provides the typed API client library.

## Commands

### Lint
```bash
gdlint scripts/ scenes/          # Quick check (CI-equivalent)
./lint.sh                        # Full report with complexity analysis
```

### Tests
```bash
./test.sh              # All tests (unit + accordkit + livekit)
./test.sh unit         # Unit tests only — no server needed, fast
./test.sh integration  # AccordKit REST integration (requires accordserver at ../accordserver)
./test.sh accordkit    # Same as integration
./test.sh gateway      # Gateway/e2e tests — requires non-headless Godot
./test.sh livekit      # LiveKit adapter tests — no server needed
```

Server-dependent tests require `accordserver` cloned as a sibling directory (`../accordserver/`). The test runner auto-builds and starts the server. Tail logs with `tail -f test_server.log`.

### Run against remote test server
```bash
ACCORD_TEST_URL=http://<host>:39099 ./test.sh accordkit
```

## Architecture

### Autoload Singletons (registered in project.godot)

- **AppState** (`scripts/autoload/app_state.gd`) — Central signal bus. All cross-component communication goes through AppState signals (80+). Tracks current selection state (space, channel, DM mode, layout mode).
- **Client** (`scripts/autoload/client.gd`) — Core client managing an array of server connections. Routes data requests to the correct server via `_space_to_conn` and `_channel_to_space` lookup dictionaries. Caches users, spaces, channels, messages, members, roles, and voice states.
- **Config** (`scripts/autoload/config.gd`) — Multi-profile encrypted config system. Per-profile data at `user://profiles/<slug>/config.cfg`.
- **ClientModels** (`scripts/autoload/client_models.gd`) — Converts AccordKit typed models to dictionary shapes consumed by UI scenes.

Client has namespaced sub-objects: `Client.fetch`, `Client.admin`, `Client.voice`, `Client.mutations`, `Client.plugins`, `Client.unread`, `Client.permissions`, `Client.relationships`, `Client.connection`, `Client.emoji`.

### Signal Flow Pattern

User action → Component calls AppState → AppState emits signal → Listeners update. UI reads data through `Client`, never makes direct API calls.

### AccordKit Addon (`addons/accordkit/`)

In-tree API client library (v2.0.0):
- `core/` — AccordClient (auth + REST + WebSocket), RestResult
- `rest/endpoints/` — 24 typed endpoint classes
- `models/` — 24 typed model classes (AccordUser, AccordSpace, AccordMessage, PluginManifest, etc.)
- `gateway/` — WebSocket event dispatch (80+ event types)
- `utils/` — Snowflake IDs, CDN URLs, Permission bitmasks, Intent flags

### Scene Organization

Each `.tscn` scene has a matching `.gd` script in the same directory. Components expose `setup(data: Dictionary)` for initialization. Scene references use `preload()` constants.

Main scene: `scenes/main/main_window.tscn` (HBoxContainer → Sidebar + Content TabBar).

### Responsive Layout

`AppState.current_layout_mode` tracks COMPACT (<500px), MEDIUM (<768px), FULL (≥768px). COMPACT mode converts sidebar to a drawer overlay.

### Multi-Server Support

Client maintains separate connections per server in `_connections[]`. Each connection has its own AccordClient instance, caches, and CDN URL.

### Voice/Video

Platform-specific: `LiveKitAdapter` (desktop/mobile GDExtension) vs `WebVoiceSession` (web). Both present the same signal API to UI components.

## Lint Rules (gdlintrc)

- Max line length: 100
- Max file lines: 900
- Max public methods: 90
- Max returns per function: 6
- Naming: PascalCase classes, snake_case functions/variables, UPPER_CASE constants
- Class definition order: tools → classnames → extends → docstrings → signals → enums → consts → staticvars → exports → pubvars → prvvars → onreadypubvars → onreadyprvvars → others

## GDScript Gotchas

- `:=` type inference fails on Variant returns (Dictionary access, `await`, loosely-typed variables). Always use explicit type annotations: `var x: Type = ...` for these cases.
- Test framework is GUT (`addons/gut/`, gitignored — installed at setup). Config in `.gutconfig.json`.

**Known issues:**
- None at present. Previous issues (type inference in test_add_server_dialog.gd and seed cascade failures) have been fixed.

## External Addons (gitignored, installed separately)

- `addons/gut/` — GUT test framework
- `addons/godot-livekit/` — LiveKit C++ GDExtension (download from NodotProject/godot-livekit releases)
- `addons/lua-gdextension/` — Lua scripting runtime, LuaJIT variant (download from gilzoide/lua-gdextension releases)
- `addons/sentry/` — Error reporting (CI-installed)

## Related Projects

Implementing some tasks will require working in separate codebases.

- ../accordserver: Server-side logic
- ../daccord-editor: Plugin related logic
- ../accordmasterserver: The master server
- ../accordserver-mcp: A typescript based mcp-client for accordserver
- ../accordwebsite: The daccord website
- ../godotlite: A slimmed down version of godot used for reduced size releases
- ../godot-livekit: The video/voice communication gdextension client
- ../frametap: The library that takes care of screenshots and screen recording (built into godot-livekit)
- ../accordman: A project manager for viewing user flows

## Agent-Specific Notes

This repository includes a compiled documentation database/knowledgebase at `AGENTS.db`.
For context for any task, you MUST use MCP `agents_search` to look up context including architectural, API, and historical changes.
Treat `AGENTS.db` layers as immutable; avoid in-place mutation utilities unless required by the design.
