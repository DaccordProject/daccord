# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

daccord is a Godot 4.6 chat client that connects to [accordserver](https://github.com/daccord-projects/accordserver) instances -- a custom Rust backend with a REST API and WebSocket gateway.

The client connects to one or more accordserver instances using token-based authentication. Supports multi-server connections, real-time messaging via WebSocket, and full CRUD for messages. If no servers are configured, the UI is empty until the user adds a server via the Add Server dialog.

## Running

Open in Godot 4.6 and run. Main scene: `scenes/main/main_window.tscn`. Renderer: GL Compatibility.

## User Flows

See user_flows/README.md. If a user flow is out of date, update it.

## Architecture

**Autoloads (singletons):**
- `AppState` (`scripts/autoload/app_state.gd`) -- Central signal bus. Emits `guild_selected`, `channel_selected`, `dm_mode_entered`, `message_sent`, `reply_initiated`, `reply_cancelled`, `message_edited`, `message_deleted`, `guilds_updated`, `channels_updated`, `dm_channels_updated`, `messages_updated`, `user_updated`, `typing_started`, `typing_stopped`, `layout_mode_changed`, `sidebar_drawer_toggled`, `profile_switched`. Tracks `current_guild_id`, `current_channel_id`, `is_dm_mode`, `replying_to_message_id`, `editing_message_id`, `current_layout_mode`, `sidebar_drawer_open`. All cross-component communication goes through here.
- `Client` (`scripts/autoload/client.gd`) -- Manages server connections and data access. Has `LIVE` and `CONNECTING` modes. Maintains an array of server connections (each with an `AccordClient`, guild ID, CDN URL, and status). Routes API calls to the correct server based on guild/channel ID. Provides a unified data access API (`guilds`, `channels`, `dm_channels`, `get_messages_for_channel()`, etc.). Also hosts shared constants (`MESSAGE_CAP`, dimension constants), `emoji_textures`, and `markdown_to_bbcode()`. Handles gateway events (message create/update/delete, typing, presence, space/channel changes).
- `Config` (`scripts/autoload/config.gd`) -- Multi-profile config manager. Each profile stores its data under `user://profiles/<slug>/config.cfg` (encrypted). Manages a `user://profile_registry.cfg` for profile metadata (names, order, password hashes). Supports profile CRUD (`create_profile()`, `delete_profile()`, `switch_profile()`, `rename_profile()`), password protection (`set_profile_password()`, `verify_profile_password()`), and per-profile emoji cache paths. On first run, migrates legacy `user://config.cfg` to `user://profiles/default/`. Supports `--profile <slug>` CLI override. Also provides server connection config (`add_server()`, `remove_server()`, `get_servers()`, `has_servers()`) and all user preferences.
- `ClientModels` (`scripts/autoload/client_models.gd`) -- Static helper class that converts AccordKit typed models (`AccordUser`, `AccordSpace`, `AccordChannel`, `AccordMessage`) into the dictionary shapes UI components expect. Also defines `ChannelType` and `UserStatus` enums used by both AccordKit conversion and UI components.

**Addons:**
- `accordkit` -- GDScript client library for the accordserver API. Provides `AccordClient` (REST + WebSocket gateway), typed models (`AccordUser`, `AccordSpace`, `AccordChannel`, `AccordMessage`, `AccordInvite`, etc.), REST endpoints, and gateway event handling.
- `accordstream` -- GDExtension (native binary) for audio/voice streaming.
- `gut` -- GUT (Godot Unit Test) framework for testing.

**Server connection flow:** On startup, `Client._ready()` checks `Config.has_servers()`. If servers exist, it calls `connect_server()` for each. Each connection authenticates with a Bearer token, fetches the current user via `GET /users/@me`, lists the user's spaces (guilds) via `GET /users/@me/spaces`, matches the configured guild name, connects the WebSocket gateway, and enters `LIVE` mode. If no servers are configured, the client stays in `CONNECTING` mode (UI is empty until a server is added).

**Adding a server:** The "Add Server" dialog (`sidebar/guild_bar/add_server_dialog`) parses URLs in the format `[protocol://]host[:port][#guild-name][?token=value]` (defaults: HTTPS, port 39099, guild "general"). It saves the config via `Config.add_server()` and calls `Client.connect_server()`.

**Scene hierarchy:**
- `main/main_window` -- Root HBoxContainer. Holds sidebar + content area. Manages a TabBar for open channels. Collapses sidebar on narrow viewports (<500px).
- `sidebar/sidebar` -- Orchestrates guild bar, channel list, and DM list. Switches between channel list and DM list based on selection.
  - `sidebar/guild_bar/` -- Vertical icon strip. Guild icons, guild folders (collapsible groups), DM button, pills (selection indicators), mention badges.
  - `sidebar/channels/` -- Channel panel with banner, categories (collapsible), and channel items (text/voice/announcement/forum).
  - `sidebar/direct/` -- DM channel list.
  - `sidebar/user_bar` -- Bottom user info bar.
- `messages/message_view` -- Scrollable message list with auto-scroll. Uses cozy vs collapsed message layout (collapsed when same author sends consecutive messages with no reply). Includes composer and typing indicator.
  - `messages/cozy_message` -- Full message with avatar, author, timestamp, reply reference. Has right-click context menu for Reply/Edit/Delete (Edit/Delete only enabled for own messages).
  - `messages/collapsed_message` -- Compact follow-up message (no avatar/header).
  - `messages/message_content` -- Renders text via `markdown_to_bbcode` in RichTextLabel, plus optional embed and reaction bar. Supports inline edit mode (Enter to save, Escape to cancel).
  - `messages/composer/` -- Message input with send button and reply bar. Enter sends, Shift+Enter for newline.

**Signal flow:** User clicks guild icon -> `guild_bar` emits `guild_selected` -> `sidebar` calls `channel_list.load_guild()` and `AppState.select_guild()` -> `AppState` emits `guild_selected`. Channel click -> similar chain -> `AppState.channel_selected` -> `message_view` loads messages, `main_window` manages tabs. `Client` fetches data from the server and emits `AppState` signals (`messages_updated`, `channels_updated`, etc.) when gateway events arrive.

**Responsive layout:** `AppState` tracks a `LayoutMode` enum (`COMPACT` <500px, `MEDIUM` <768px, `FULL` >=768px). In compact mode, the sidebar becomes a drawer overlay toggled by a hamburger button.

**Theme:** `theme/discord_dark.tres` is the global theme. Icons are SVGs in `theme/icons/`. Avatar rendering uses a custom shader (`theme/avatar_circle.gdshader`) with a `radius` parameter that animates between 0.5 (circle) and 0.3 (rounded square) on hover.

## GDScript Type Inference Pitfalls

GDScript's `:=` operator infers the type from the right-hand side. This **fails at compile time** when the right-hand side returns a `Variant` (untyped value). Common cases:

1. **Dictionary access:** `var x := dict["key"]` -- Dictionaries return `Variant`. Use `var x: String = dict["key"]` instead.
2. **Comparison with Dictionary values:** `var match := dict["a"] == other` -- The `==` on a `Variant` produces a `Variant`. Use `var match: bool = dict["a"] == other`.
3. **Methods on a `Node`/`Variant`-typed variable:** If a variable is typed as `Node` (e.g., `var _c: Node`), calls like `var client := _c.some_method()` return `Variant` because the compiler doesn't know the concrete type. Use an explicit type: `var client: AccordClient = _c.some_method()`.
4. **`await` expressions:** `var result := await some_async()` can fail if the return type isn't statically known. Use `var result: RestResult = await some_async()`.

**Rule of thumb:** If the value comes from a Dictionary, a `Variant`-typed variable, or an `await` on a loosely-typed call, always use explicit type annotations (`var x: Type = ...`) instead of `:=`.

## Conventions

- Each scene (`.tscn`) has a corresponding `.gd` script in the same directory.
- Components expose a `setup(data: Dictionary)` method to initialize from mock data dictionaries. Exception: `category_item.setup()` takes `(data: Dictionary, children: Array)`.
- Selection state uses `set_active(bool)` methods on interactive items (guild icons, channel items). Guild bar uses `has_method("set_active")` checks since both `guild_icon` and `guild_folder` are stored in the same lookup dictionary.
- Scene references use `preload()` constants at class level, not dynamic `load()`.
- Dictionary shapes (users, guilds, channels, messages) serve as the data contract between components. `ClientModels` converts AccordKit typed models into these shapes so the UI layer doesn't depend on AccordKit types directly.
- UI components should read data through `Client` to stay decoupled from the network layer.
- License: MIT.

## Testing

**Framework:** GUT (Godot Unit Test) via `addons/gut/`.

**Running tests:**
```bash
./test.sh              # All tests (starts accordserver automatically)
./test.sh unit         # Unit tests only (no server needed)
./test.sh integration  # AccordKit + AccordStream integration/e2e tests
./test.sh accordkit    # AccordKit tests only
./test.sh accordstream # AccordStream tests only (no server needed)
```

Server logs are written to `test_server.log` -- tail them with `tail -f test_server.log` while tests run.

**Test layout:**
- `tests/unit/` -- Unit tests for autoloads and UI components. No server needed.
- `tests/accordkit/unit/` -- Unit tests for AccordKit models and utilities (snowflake, permissions, CDN, intents, REST result).
- `tests/accordkit/integration/` -- Integration tests that hit the AccordKit REST API (users, spaces, channels, messages, members).
- `tests/accordkit/gateway/` -- WebSocket gateway connect and event tests.
- `tests/accordkit/e2e/` -- Full lifecycle test (login, API calls, gateway events, logout).
- `tests/accordkit/helpers/` -- `AccordTestBase` (base class for server-dependent tests) and `SeedClient` (calls `POST /test/seed` to populate test data).
- `tests/accordstream/integration/` -- WebRTC peer connection, media track, and voice session tests. No server needed.

**Server-dependent tests** (accordkit integration/gateway/e2e) require accordserver running on `127.0.0.1:39099` with `ACCORD_TEST_MODE=true`. The `test.sh` script handles this automatically. The test base class (`AccordTestBase`) calls `/test/seed` in `before_all()` to create a user, bot, space, and channels for each test file.

**Known issues:**
- None at present. Previous issues (type inference in test_add_server_dialog.gd and seed cascade failures) have been fixed.
