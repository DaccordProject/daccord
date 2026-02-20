# Test Coverage

Last touched: 2026-02-20

## Overview

daccord uses the GUT (Godot Unit Test) framework for automated testing. The test suite spans three tiers: unit tests for autoloads and UI components, AccordKit integration tests that hit a live accordserver, and AccordStream tests for WebRTC/voice APIs. A Bash runner (`test.sh`) orchestrates server lifecycle and suite selection, while GitHub Actions CI runs unit tests, lint, and integration tests on every push.

## User Steps

1. Developer runs `./test.sh` (or `./test.sh unit`, `./test.sh integration`, etc.) from the project root.
2. The runner resolves which test directories to include and whether an accordserver instance is needed.
3. If a server is needed, the runner builds accordserver, clears the test database, starts the server in `ACCORD_TEST_MODE`, and polls `:39099` until ready.
4. GUT runs each suite directory via `godot --headless -s addons/gut/gut_cmdln.gd`.
5. Results print to stdout; server logs go to `test_server.log`.
6. On exit, the runner kills the server and removes the test database.

## Signal Flow

```
Developer
  │
  ▼
test.sh
  ├── resolve_dirs() ──► NEEDS_SERVER flag + GUT_DIRS
  ├── start_server()  ──► cargo build + cargo run (ACCORD_TEST_MODE=true)
  │       └── poll /api/v1/gateway until 200
  └── run_tests()
        └── for each dir in GUT_DIRS:
              godot --headless -s gut_cmdln.gd -gdir=<dir>
                ├── GutTest.before_all()  (AccordTestBase calls /test/seed)
                ├── GutTest.before_each() (creates fresh AccordClient instances)
                ├── test_*() methods
                ├── GutTest.after_each()  (queue_free clients)
                └── GutTest.after_all()
  ▼
cleanup() ──► kill server + rm accord_test.db
```

## Key Files

| File | Role |
|------|------|
| `test.sh` | Bash test runner — suite selection, server lifecycle, GUT invocation |
| `.gutconfig.json` | GUT framework config — dirs, prefix, suffix, log level |
| `.github/workflows/ci.yml` | CI pipeline — lint + unit tests + integration tests on push/PR to master |
| `.github/workflows/release.yml` | Release pipeline — cross-platform export + GitHub Release |
| `tests/unit/test_app_state.gd` | Unit tests for AppState signal bus (37 tests) |
| `tests/unit/test_config.gd` | Unit tests for Config persistence, credentials, export/import (21 tests) |
| `tests/unit/test_markdown.gd` | Unit tests for markdown-to-BBCode renderer (11 tests) |
| `tests/unit/test_auth_dialog.gd` | Unit tests for auth dialog UI (13 tests) |
| `tests/unit/test_add_server_dialog.gd` | Unit tests for add-server dialog + URL parser (18 tests) |
| `tests/unit/test_security.gd` | Security tests — BBCode sanitization, URL scheme blocking, state integrity (28 tests) |
| `tests/unit/test_client_models.gd` | Unit tests for ClientModels *_to_dict() conversions + helpers (75 tests) |
| `tests/unit/test_message_content.gd` | Unit tests for message content rendering + edit mode (10 tests) |
| `tests/unit/test_cozy_message.gd` | Unit tests for cozy message layout + context menu (8 tests) |
| `tests/unit/test_collapsed_message.gd` | Unit tests for collapsed message layout + timestamp (6 tests) |
| `tests/unit/test_composer.gd` | Unit tests for composer UI elements + reply bar (8 tests) |
| `tests/unit/test_typing_indicator.gd` | Unit tests for typing indicator show/hide + animation (6 tests) |
| `tests/unit/test_reaction_pill.gd` | Unit tests for reaction pill setup + optimistic update (7 tests) |
| `tests/unit/test_dm_channel_item.gd` | Unit tests for DM channel item setup + active state (9 tests) |
| `tests/unit/test_client_startup.gd` | Smoke tests for Client `_ready()` startup — sub-module creation, AccordVoiceSession, signal wiring (6 tests) |
| `tests/unit/test_client.gd` | Unit tests for Client autoload — data access, routing, permissions, unread tracking (60 tests) |
| `tests/unit/test_client_gateway.gd` | Unit tests for ClientGateway — event handlers, cache mutation, signal routing (36 tests) |
| `tests/unit/test_channel_item.gd` | Unit tests for channel_item — setup, type icons, NSFW, unread, active state (15 tests) |
| `tests/unit/test_category_item.gd` | Unit tests for category_item — setup, collapse, channel items (10 tests) |
| `tests/unit/test_guild_icon.gd` | Unit tests for guild_icon — setup, pill state, mention badge, active (11 tests) |
| `tests/unit/test_guild_folder.gd` | Unit tests for guild_folder — setup, expand/collapse, set_active, notifications, context menu (24 tests) |
| `tests/unit/test_reaction_bar.gd` | Unit tests for reaction_bar — setup, pill creation, ID injection (5 tests) |
| `tests/unit/test_updater.gd` | Unit tests for Updater semver parsing, comparison, is_newer, and parse_release (32 tests) |
| `tests/unit/test_user_bar.gd` | Unit tests for user_bar — avatar handling, display name, username, status icon (12 tests) |
| `tests/unit/test_error_reporting.gd` | Unit tests for ErrorReporting — guard clauses, signal handlers, PII scrubbing (20 tests) |
| `tests/unit/test_config_profiles.gd` | Unit tests for Config profiles — slugify, password hashing, CRUD, ordering (22 tests) |
| `tests/unit/test_embed.gd` | Unit tests for embed component — setup, title/URL, author, fields, footer, color, type (12 tests) |
| `tests/accordkit/helpers/test_base.gd` | AccordTestBase — seeds server, creates clients per test |
| `tests/accordkit/helpers/seed_client.gd` | SeedClient — POSTs to `/test/seed` for test data |
| `tests/accordkit/unit/test_snowflake.gd` | AccordSnowflake encode/decode (9 tests) |
| `tests/accordkit/unit/test_rest_result.gd` | RestResult value object (8 tests) |
| `tests/accordkit/unit/test_intents.gd` | GatewayIntents sets (8 tests) |
| `tests/accordkit/unit/test_cdn.gd` | AccordCDN URL generation (12 tests) |
| `tests/accordkit/unit/test_permissions.gd` | AccordPermission queries (7 tests) |
| `tests/accordkit/unit/test_multipart_form.gd` | MultipartForm builder (8 tests) |
| `tests/accordkit/unit/test_model_user.gd` | AccordUser/Member/Presence/Activity models (15 tests) |
| `tests/accordkit/unit/test_model_message.gd` | AccordMessage/Embed/Attachment/Reaction models (17 tests) |
| `tests/accordkit/unit/test_model_space.gd` | AccordSpace/Channel/Role/Emoji/PermOverwrite models (17 tests) |
| `tests/accordkit/unit/test_model_interaction.gd` | AccordInteraction/Application/Command/Invite models (17 tests) |
| `tests/accordkit/unit/test_model_voice.gd` | AccordVoiceState/VoiceServerUpdate models (11 tests) |
| `tests/accordkit/integration/test_users_api.gd` | REST /users endpoints (6 tests) |
| `tests/accordkit/integration/test_spaces_api.gd` | REST /spaces endpoints (5 tests) |
| `tests/accordkit/integration/test_channels_api.gd` | REST /channels endpoints (3 tests) |
| `tests/accordkit/integration/test_messages_api.gd` | REST /messages CRUD + typing (6 tests) |
| `tests/accordkit/integration/test_members_api.gd` | REST /members endpoints (4 tests) |
| `tests/accordkit/integration/test_permissions_api.gd` | Server-enforced permission checks (23 tests) |
| `tests/accordkit/gateway/test_gateway_connect.gd` | WebSocket connect/disconnect lifecycle (3 tests) |
| `tests/accordkit/gateway/test_gateway_events.gd` | Real-time gateway event delivery (1 test) |
| `tests/accordkit/e2e/test_full_lifecycle.gd` | Full login-to-logout lifecycle (1 test) |
| `tests/accordstream/integration/test_device_enumeration.gd` | Device listing APIs (34 tests) |
| `tests/accordstream/integration/test_media_tracks.gd` | Media track create/enable/stop (25 tests) |
| `tests/accordstream/integration/test_peer_connection.gd` | WebRTC peer connection API (51 tests) |
| `tests/accordstream/integration/test_voice_session.gd` | Voice session state machine (39 tests) |
| `tests/accordstream/integration/test_end_to_end.gd` | Multi-step WebRTC workflows (8 tests) |

## Implementation Details

### Test Runner (`test.sh`)

The runner (lines 1-250) uses `set -euo pipefail` for strict error handling. Suite resolution (lines 51-79) maps CLI arguments to `res://` paths and a `NEEDS_SERVER` boolean:

| Argument | Directories | Server needed |
|----------|-------------|---------------|
| `unit` | `res://tests/unit` | No |
| `accordkit` | `res://tests/accordkit` | Yes |
| `accordstream` | `res://tests/accordstream` | No |
| `integration` | `res://tests/accordkit`, `res://tests/accordstream` | Yes |
| `all` (default) | All three | Yes |

Server startup (lines 84-138): builds with `cargo build --quiet`, removes stale `accord_test.db*` files, starts with `ACCORD_TEST_MODE=true` and `DATABASE_URL=sqlite:accord_test.db?mode=rwc`, then polls `GET /api/v1/gateway` up to 30 times at 1s intervals. If the server is already running on `:39099`, it reuses the existing instance (line 221).

Each suite directory runs as a separate `godot --headless` invocation (lines 164-183). If any suite fails, the runner aborts immediately (`return 1` at line 181).

Cleanup (lines 152-159) runs via `trap cleanup EXIT INT TERM` — kills the server process and removes the test database.

### GUT Configuration (`.gutconfig.json`)

Minimal config: three directories with `include_subdirs=true`, `prefix=test_`, `suffix=.gd`, `log_level=1`. `should_exit=true` ensures the Godot process exits after tests complete. `should_exit_on_success=false` keeps Godot running briefly so logs flush on failure.

### AccordTestBase (`tests/accordkit/helpers/test_base.gd`)

Base class for all server-dependent tests. Constants `BASE_URL` and `GATEWAY_URL` point to `127.0.0.1:39099` (lines 3-4).

`before_all()` (line 21): calls `SeedClient.seed(self)` which POSTs to `/test/seed`. Extracts `user_id`, `user_token`, `bot_id`, `bot_token`, `bot_application_id`, `space_id`, `general_channel_id`, and `testing_channel_id` from the response.

`before_each()` (line 47): creates fresh `bot_client` (Bot token) and `user_client` (Bearer token) via `_create_client()`. Each `AccordClient` gets full `GatewayIntents.all()` and is added as a child node.

`after_each()` (line 52): calls `queue_free()` on both clients.

### SeedClient (`tests/accordkit/helpers/seed_client.gd`)

Static helper class. `seed()` (line 5) creates an `HTTPRequest`, POSTs `{}` to `http://127.0.0.1:39099/test/seed`, parses the JSON response, and returns `envelope.data`. Returns `{}` on any error (network failure, non-200, parse failure).

### Unit Tests (`tests/unit/`)

**test_app_state.gd** — 37 tests covering `AppState` signals and state mutations. Tests guild/channel selection, DM mode entry, message send/reply/edit/delete signals, layout mode breakpoints (COMPACT <500px, MEDIUM <768px, FULL >=768px), sidebar drawer toggle, and state transition sequences. Uses `watch_signals()` + `assert_signal_emitted_with_parameters()`.

**test_config.gd** — 21 tests for `Config` in-memory behavior (no disk I/O). Tests `add_server`, `remove_server`, `clear`, `has_servers`, `get_servers`, and edge cases (invalid/negative indices, empty state). Also covers `_load_ok` guard (default false, save/add guarded), `update_server_credentials` (valid index, invalid, negative), and `export_config` / `import_config` round-trip.

**test_markdown.gd** — 11 tests for `ClientModels.markdown_to_bbcode()`. Covers bold, italic, strikethrough, underline, inline code, code blocks (with/without language), spoiler, links, blockquotes, and plain passthrough.

**test_auth_dialog.gd** — 13 tests for the auth dialog scene. Verifies UI elements exist (username/password/display_name inputs, submit button, error label), initial sign-in mode, mode toggle (sign-in/register), validation (empty username/password shows error), signal existence, and dialog close behavior.

**test_add_server_dialog.gd** — 18 tests for the add-server dialog and URL parser. Tests UI elements, validation (empty/whitespace), URL parsing (bare host, port, protocol, fragment `#guild`, query `?token=`, `?invite=`, full URL, whitespace stripping, empty fragment defaults), signal existence, and dialog close.

**test_security.gd** — 28 tests verifying security properties. BBCode sanitization tests (8) verify that raw BBCode tags injected via user content are escaped with `[lb]` (unknown tags) or allowed through (converter-produced tags like `[color=`, `[url=`), while code blocks preserve raw tags. Malicious URL scheme tests (4) verify that `javascript:`, `data:`, `file:`, `vbscript:` schemes in markdown links are replaced with `#blocked`. Input boundary tests (5) verify no crash on empty, very long (100K chars), whitespace, null bytes, and RTL override characters. Regex abuse tests (4) verify no hang on deeply nested markdown, overlapping delimiters, unclosed delimiters, and repeated special chars. State integrity tests (7) verify signals emit even with empty/whitespace inputs and survive rapid state transitions.

**test_client_models.gd** — 75 tests for `ClientModels` static conversion functions. Covers `_color_from_id` (determinism, uniqueness), `_status_string_to_enum` / `_status_enum_to_string` (roundtrip for all statuses), `_channel_type_to_enum` (all channel types + unknown default), `_format_timestamp` (empty, no-T, AM/PM, midnight, noon), `user_to_dict` (basic fields, display_name fallback, avatar URL, null avatar, color, status), `space_to_guild_dict` (basic fields, null description, public from features, icon URL), `channel_to_dict` (basic fields, type mapping, null parent_id, guild_id from space_id, position, nsfw), `message_to_dict` (basic fields, author from cache, unknown author, edited flag, reactions, reply_to, system type), `member_to_dict` (from cache, unknown user, nickname override, joined_at), `dm_channel_to_dict` (single recipient, group, no recipients, last_message_id), `role_to_dict` (all fields, defaults), `invite_to_dict` (full, nulls), `emoji_to_dict` (full, null id), `sound_to_dict` (full, null id), `voice_state_to_dict` (from cache, unknown user, all flags).

**test_message_content.gd** — 10 tests for the message content component. Covers plain text rendering, edited indicator (present/absent), system message italic styling, `_format_file_size` static method (bytes/KB/MB), edit mode (hides text content, `is_editing` state).

**test_cozy_message.gd** — 8 tests for the cozy (full) message layout. Covers author name, timestamp, avatar initialization, author color override, reply reference visibility, context menu items (4 items: Reply/Edit/Delete/Add Reaction), and message data storage.

**test_collapsed_message.gd** — 6 tests for the collapsed (follow-up) message layout. Covers content setup, timestamp extraction from "Today at 10:31 AM" -> "10:31", context menu (4 items), timestamp initially hidden, and message data storage.

**test_composer.gd** — 8 tests for the message composer. Covers UI element existence (text_input, send_button, emoji_button, upload_button), initial state (reply_bar hidden, error_label hidden), `set_channel_name` placeholder update, and reply cancel behavior.

**test_typing_indicator.gd** — 6 tests for the typing indicator component. Covers initial processing state (off), `show_typing` (visible, text, processing enabled, anim_time reset), and `hide_typing` (hidden, processing disabled).

**test_reaction_pill.gd** — 7 tests for the reaction pill button. Covers `setup` (emoji_key, count label, active true/false, channel/message IDs, zero count), and optimistic toggle count increment.

**test_dm_channel_item.gd** — 9 tests for the DM channel list item. Covers `setup` (dm_id, username, last_message, unread dot visible/hidden), `set_active` (applies/removes style), and signal existence (dm_pressed, dm_closed).

**test_client_startup.gd** — 6 smoke tests for the Client `_ready()` startup path. Verifies `ClientVoice` instantiation (the sub-module most likely to break from GDExtension changes), full `_ready()` sub-module creation (ClientGateway, ClientFetch, ClientAdmin, ClientVoice, ClientMutations), AccordVoiceSession GDExtension construction and parent attachment, voice session signal wiring (session_state_changed, peer_joined, peer_left, signal_outgoing → ClientVoice callbacks), AppState.channel_selected connection, and post-_ready() initial state (CONNECTING mode, empty current_user). Uses `add_child_autofree` to trigger `_ready()`, unlike `test_client.gd` which skips it.

**test_client.gd** — 60 tests for the Client autoload's pure logic (no network). Tests URL derivation (HTTPS→WSS, HTTP→WS, CDN), cache getters (`get_channels_for_guild`, `get_messages_for_channel`, `get_user_by_id`, `get_guild_by_id`, `get_members_for_guild`, `get_roles_for_guild`, `get_message_by_id` with index hit/fallback/miss), routing helpers (`_conn_for_guild`, `_client_for_guild`, `_cdn_for_guild`, `_cdn_for_channel`, `_first_connected_client/cdn`), permission checking (admin bypass, owner bypass, role-based grant/deny, everyone role, no members), unread tracking (`mark_channel_unread` for channels/DMs/mentions, `_on_channel_selected_clear_unread`, `_update_guild_unread` aggregation), user cache trimming (below cap no-op, preserves current user + guild members), guild folder update, connection state helpers (`is_server_connected`, `is_guild_connected`, `get_guild_connection_status`), and `_find_channel_for_message` (indexed/fallback/miss). Uses `load().new()` without `add_child` to skip `_ready()` and avoid AccordVoiceSession dependency.

**test_client_gateway.gd** — 36 tests for ClientGateway event handlers. Calls `on_*` methods directly with `AccordMessage.from_dict()` etc. Tests message create (append, index update, bucket creation, MESSAGE_CAP eviction, unread marking), message update (in-place replacement), message delete (single + bulk), typing (signal emission, own-user skip), presence/user updates (user cache status, member cache status, current_user update), space CRUD (preserves unread/mentions/folder on update, delete removes, create adds), channel CRUD (text vs DM, preserves unread/voice_users on update), role CRUD (create/update/delete), reactions via `gw._reactions` (add new emoji, increment existing, active flag for current user, remove decrement, remove at zero, clear all, clear specific emoji), voice state via `gw._events` (add user, move user between channels), and gateway lifecycle (reconnected sets status, disconnected non-fatal).

**test_user_bar.gd** — 12 tests for the user bar sidebar component. Covers `setup` with null/missing/empty avatar (no crash), avatar URL handling, display name and username from dict (with defaults when missing), avatar letter from display name, and status icon color (online/offline via `ClientModels.status_color()`).

**test_error_reporting.gd** — 20 tests for the ErrorReporting autoload. Guard clause tests (4) verify `_initialized` is false by default and that `_add_breadcrumb`, `update_context`, and `report_problem` return early without crashing when Sentry is not initialized. Signal handler tests (9) verify that `_on_guild_selected`, `_on_channel_selected`, `_on_dm_mode_entered`, `_on_message_sent`, `_on_reply_initiated`, `_on_layout_mode_changed` (COMPACT/MEDIUM/FULL), and `_on_sidebar_drawer_toggled` do not crash when uninitialized. PII scrubbing tests (7) verify that `scrub_pii_text` redacts Bearer tokens (single and multiple), `token=` query parameters, URLs with ports (HTTPS and HTTP), preserves plain text, and handles combined PII in a single string.

**test_config_profiles.gd** — 22 tests for Config multi-profile management. Covers `_slugify` (basic, special chars, truncation to 32 chars, collision appends `-2`, empty input becomes "profile"), `_hash_password` (deterministic, different slugs produce different hashes, different passwords produce different hashes), `create_profile` (fresh, with password, copy from current), `delete_profile` (default blocked, removes from registry), `rename_profile`, `set_profile_password` / `verify_profile_password` (set and verify, wrong old password fails, remove by setting empty), `get_profiles` ordering, `get_active_profile_slug`, and `move_profile_up` / `move_profile_down` (swap, no-op at boundaries).

**test_embed.gd** — 12 tests for the embed message component. Covers `setup` with empty data (hides embed), title only (shows title, hides author/fields/image/thumbnail/footer), title with URL (BBCode link in title_rtl), description only, author with/without URL (author_row visibility, name rendering), fields (container visible with fields, hidden without), footer (visible with text, hidden without), custom color (border_color on StyleBoxFlat), and type "image" (hides title/description, shows image_rect).

**test_channel_item.gd** — 15 tests for the channel item sidebar component. Covers `setup` (stores IDs, sets name text), type icon selection (TEXT/VOICE/ANNOUNCEMENT/FORUM), NSFW red tint vs default, unread dot visibility and font color, `set_active` (adds/removes style override), signal existence, and data storage.

**test_category_item.gd** — 10 tests for the category item sidebar component. Covers `setup` (stores guild_id, uppercases name, creates count label, instantiates text + voice channel items), collapse toggle (hides channels, shows count label, restores on double-toggle), `get_category_id`, and signal existence.

**test_guild_icon.gd** — 11 tests for the guild icon sidebar component. Covers `setup` (stores IDs, tooltip, avatar letter), pill state (UNREAD/HIDDEN based on unread flag), mention badge count, `set_active` (ACTIVE/UNREAD/HIDDEN transitions), initial state, and signal existence.

**test_guild_folder.gd** — 24 tests for the guild folder sidebar component. Covers `setup` (stores folder name, tooltip, mini grid swatches, guild icon creation), expand/collapse toggle (visibility, mini grid hidden when expanded, double-toggle restores), `set_active` / `set_active_guild` (pill state transitions, child icon activation, deactivation clears children, restores unread pill), notification aggregation (mention badge sum, unread pill, hidden when no unread, active overrides unread), context menu (exists, has Rename/Change Color/Delete items), and signal existence (guild_pressed, folder_changed).

**test_reaction_bar.gd** — 5 tests for the reaction bar container. Covers empty reactions (hidden), non-empty pill creation (count verification), channel/message ID injection into reaction data, setup clears previous children, and single reaction creates single pill.

**test_updater.gd** — 32 tests for the Updater semver utilities. Covers `parse_semver` (basic version, v-prefix, prerelease tag, combined v-prefix + prerelease, invalid too-few-parts, non-numeric, empty string, whitespace stripping), `compare_semver` (equal, major/minor/patch greater/less, release beats prerelease, prerelease less than release, prerelease lexicographic ordering, prerelease equal, v-prefix, invalid returns zero), `is_newer` (true, false-equal, false-older, prerelease not newer than release, release newer than prerelease, next-version prerelease is newer), and `parse_release` (valid release with Linux asset, missing tag, invalid tag, no Linux asset, prerelease tag).

### AccordKit Unit Tests (`tests/accordkit/unit/`)

Eleven test files covering AccordKit's utility classes and model layer:

- **test_snowflake.gd** (9 tests) — Encode/decode roundtrip, epoch constant (`1704067200000`), nonce uniqueness (100 nonces), datetime conversion.
- **test_rest_result.gd** (8 tests) — Success/failure construction, cursor/has_more, null data (204), array data.
- **test_intents.gd** (8 tests) — Default/all/privileged/unprivileged intent sets, counts (3 privileged, 11 unprivileged), union property.
- **test_cdn.gd** (12 tests) — URL generation for avatars, default avatars, space icons/banners, emojis (static + gif), attachments, animated hash detection.
- **test_permissions.gd** (7 tests) — All permissions count (39), has/has-not, administrator grants all, empty set, uniqueness.
- **test_multipart_form.gd** (8 tests) — Content-type boundary, field/JSON/file parts, closing boundary, empty form, multiple parts.
- **test_model_*.gd** (5 files, 77 tests total) — `from_dict` (full/minimal), `to_dict` roundtrip, null field omission, field aliases (`guild_id`/`space_id`, `nick`/`nickname`), nested dict extraction for user/member fields.

### AccordKit Integration Tests (`tests/accordkit/integration/`)

Six test files, all extending `AccordTestBase`:

- **test_users_api.gd** (6 tests) — `get_me` for bot and user, `get_user` by ID, 404 for nonexistent, `list_spaces`, `update_me`.
- **test_spaces_api.gd** (5 tests) — `get_space`, `create_space` (checks `owner_id`), `update_space`, `list_channels`, `create_channel`.
- **test_channels_api.gd** (3 tests) — `get_channel`, get general channel, `update_channel` topic.
- **test_messages_api.gd** (6 tests) — Create, list, get, edit, delete (verify 404 after), typing indicator.
- **test_members_api.gd** (4 tests) — List members (>=2), get member (handles nested `user.id`), get bot member, update nickname.
- **test_permissions_api.gd** (23 tests) — Verifies server-enforced permissions: bot (regular member) gets 403 for space/channel/role/ban/member-role/invite/emoji management; owner succeeds. Includes an escalation test where owner grants `manage_channels` role to bot, then bot creates a channel successfully.

### AccordKit Gateway Tests (`tests/accordkit/gateway/`)

- **test_gateway_connect.gd** (3 tests) — Bot and user connect, poll for `ready_received` signal (up to 10s with 0.1s timer), verify `ready_data` contains `user` or `session_id`, clean disconnect.
- **test_gateway_events.gd** (1 test) — Bot connects, user sends message via REST, bot waits up to 5s for `message_create` signal with matching content and channel_id.

### AccordKit E2E Tests (`tests/accordkit/e2e/`)

- **test_full_lifecycle.gd** (1 test) — 7-step sequential flow: bot login, get_me verification, user creates space, list channels, send+fetch message, cross-client gateway event (user sends, bot receives `message_create`), bot logout.

### AccordStream Tests (`tests/accordstream/integration/`)

Four test files plus an end-to-end file, no server needed:

- **test_device_enumeration.gd** (34 tests) — Singleton access, camera/microphone/screen/window listing, dict key validation, uniqueness. Skips gracefully if no hardware available.
- **test_media_tracks.gd** (25 tests) — Create camera/mic/screen/window tracks, initial state (LIVE), enable/disable toggle, stop emits `state_changed` with `TRACK_STATE_ENDED`, invalid device handling, idempotent stop.
- **test_peer_connection.gd** (51 tests) — Creation with various ICE configs, initial state checks, stats dict, senders/receivers, add/remove track, SDP offer creation (contains `m=audio`/`m=video`), set descriptions, ICE candidates, close lifecycle, enum constants.
- **test_voice_session.gd** (39 tests) — Initial state (DISCONNECTED), mute/deafen toggle and interaction, disconnect idempotency, poll interval, enum constants, `handle_voice_signal` resilience, LiveKit stub, signal existence, `connect_custom_sfu` state transitions.
- **test_end_to_end.gd** (8 tests) — Publish audio/video/screen flows, two-PC offer-answer loopback, add-remove-add cycle, rapid create-close (10x), kitchen-sink (all device types + all tracks + single offer).

### CI Pipeline (`.github/workflows/ci.yml`)

Three jobs on push/PR to `master`:

1. **lint** — Python 3.12 + `gdtoolkit`, runs `gdlint scripts/ scenes/` (line 32). Also runs code complexity analysis via `gdradon cc scripts/ scenes/` (lines 34-45), emitting a warning annotation for functions graded C-F.
2. **test** — Checks out project + accordkit + accordstream addons, installs Godot 4.6 via `chickensoft-games/setup-godot@v2`, caches GUT and Sentry SDK, imports project, runs unit tests (`res://tests/unit`) with 5-minute timeout (line 137-148). Also runs AccordStream tests with `continue-on-error: true` (lines 150-162). Generates a test result summary to `$GITHUB_STEP_SUMMARY` (lines 164-175).
3. **integration-test** — Checks out project + accordkit + accordstream + accordserver, installs Rust with `sccache` caching, builds accordserver with fallback if sccache fails (lines 271-280), starts in test mode, polls `/health` until ready (lines 289-301). Runs AccordKit suites individually: unit tests (line 322-333), REST integration tests (lines 335-346), and gateway + e2e tests with `continue-on-error: true` (lines 348-368). Uploads server log as artifact on failure (lines 390-396).

### Test Count Summary

| Suite | Files | Tests | Server needed |
|-------|-------|-------|---------------|
| Unit (`tests/unit/`) | 27 | 522 | No |
| AccordKit unit (`tests/accordkit/unit/`) | 11 | 129 | No |
| AccordKit integration (`tests/accordkit/integration/`) | 6 | 47 | Yes |
| AccordKit gateway (`tests/accordkit/gateway/`) | 2 | 4 | Yes |
| AccordKit e2e (`tests/accordkit/e2e/`) | 1 | 1 | Yes |
| AccordStream (`tests/accordstream/integration/`) | 5 | 157 | No |
| **Total** | **52** | **860** | |

## Implementation Status

- [x] Test runner with suite selection (`unit`, `integration`, `accordkit`, `accordstream`, `all`)
- [x] Automatic server lifecycle (build, start, poll, cleanup)
- [x] Fresh database per test run (removes stale `accord_test.db*`)
- [x] Reuse of existing server instance if already running
- [x] AccordTestBase with `/test/seed` integration
- [x] CI lint job (`gdlint scripts/ scenes/`)
- [x] CI unit test job (Godot 4.6 headless)
- [x] CI integration test job (accordserver + AccordKit tests, `continue-on-error`)
- [x] Release pipeline (cross-platform export + GitHub Release)
- [x] Unit tests for AppState (37 tests)
- [x] Unit tests for Config (21 tests)
- [x] Unit tests for markdown rendering (11 tests)
- [x] Unit tests for auth dialog (13 tests)
- [x] Unit tests for add-server dialog + URL parser (18 tests)
- [x] Security tests — BBCode sanitization, URL scheme blocking, state integrity (28 tests)
- [x] Unit tests for ClientModels conversions (75 tests)
- [x] Unit tests for message content rendering (10 tests)
- [x] Unit tests for cozy message layout (8 tests)
- [x] Unit tests for collapsed message layout (6 tests)
- [x] Unit tests for composer UI (8 tests)
- [x] Unit tests for typing indicator (6 tests)
- [x] Unit tests for reaction pill (7 tests)
- [x] Unit tests for DM channel item (9 tests)
- [x] AccordKit model serialization tests (77 tests across 5 files)
- [x] AccordKit utility tests — snowflake, REST result, intents, CDN, permissions, multipart (52 tests)
- [x] AccordKit REST integration tests — users, spaces, channels, messages, members (24 tests)
- [x] AccordKit permission enforcement tests (23 tests)
- [x] AccordKit gateway connect/event tests (4 tests)
- [x] AccordKit full lifecycle e2e test (1 test)
- [x] AccordStream device enumeration tests (34 tests)
- [x] AccordStream media track tests (25 tests)
- [x] AccordStream peer connection tests (51 tests)
- [x] AccordStream voice session tests (39 tests)
- [x] AccordStream e2e workflow tests (8 tests)
- [x] Unit tests for Client autoload — data access, routing, permissions, unread (60 tests)
- [x] Unit tests for ClientGateway — event dispatch, cache mutation (36 tests)
- [x] Unit tests for channel_item sidebar component (15 tests)
- [x] Unit tests for category_item sidebar component (10 tests)
- [x] Unit tests for guild_icon sidebar component (11 tests)
- [x] Unit tests for guild_folder sidebar component (24 tests)
- [x] Unit tests for reaction_bar container (5 tests)
- [x] Unit tests for Updater semver + parse_release (32 tests)
- [x] Unit tests for user_bar — avatar, display name, status icon (12 tests)
- [x] Unit tests for ErrorReporting — guard clauses, signal handlers, PII scrubbing (20 tests)
- [x] Unit tests for Config profiles — slugify, CRUD, passwords, ordering (22 tests)
- [x] Unit tests for embed component — setup, title, author, fields, footer, color, type (12 tests)
- [x] Smoke tests for Client `_ready()` startup — sub-modules, AccordVoiceSession, signal wiring (6 tests)
- [ ] AccordStream tests in CI (require media hardware)
- [ ] No mock/stub/double usage anywhere (real objects only)
- [ ] Cross-file seed isolation (server-side `/test/seed` conflicts)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No tests for `ClientFetch` | High | `scripts/autoload/client_fetch.gd` handles REST data fetching. No unit tests. |
| No tests for `ClientAdmin` | Medium | `scripts/autoload/client_admin.gd` handles admin operations. No unit tests. |
| No tests for `ClientMutations` | Medium | `scripts/autoload/client_mutations.gd` handles message send/edit/delete, reactions, typing. No unit tests. |
| No tests for `ClientConnection` | Medium | `scripts/autoload/client_connection.gd` handles server connect/disconnect/reconnect lifecycle. No unit tests. |
| No tests for message_view | Medium | `scenes/messages/message_view.gd` (the scroll container / message list manager) is untested due to heavy `Client` dependency. Individual message components (cozy, collapsed, content) are tested. |
| No tests for sidebar containers | Medium | Parent containers (`sidebar.gd`, `channel_list.gd`, `guild_bar.gd`) are untested due to heavy `Client` dependency. Leaf components (channel_item, category_item, guild_icon, guild_folder) are tested. |
| No tests for member_list | Low | `scenes/members/member_list.gd` — member panel display untested. |
| No tests for admin dialogs | Medium | 13 admin dialog scenes (`space_settings_dialog`, `channel_management_dialog`, `role_management_dialog`, `ban_list_dialog`, `invite_management_dialog`, `emoji_management_dialog`, `channel_edit_dialog`, `category_edit_dialog`, `create_channel_dialog`, `channel_permissions_dialog`, `soundboard_management_dialog`, etc.) have zero test coverage. |
| No tests for emoji_picker | Low | `scenes/messages/composer/emoji_picker.gd` — emoji search, category filtering, insertion untested. |
| No tests for search_panel | Low | `scenes/search/search_panel.gd` — search UI untested. |
| No tests for `SoundManager` autoload | Low | `scripts/autoload/sound_manager.gd` — sound event playback and volume control have no tests. |
| `/test/seed` fails after first test file | High | AccordTestBase's `before_all()` calls `/test/seed`, which returns 500 after the first test file runs. All subsequent integration/gateway/e2e test files fail. Server-side fix needed in `accordserver/src/routes/test_seed.rs`. |
| Gateway/e2e CI is non-blocking | Medium | `.github/workflows/ci.yml` gateway + e2e step runs with `continue-on-error: true` (line 349). AccordStream tests also use `continue-on-error: true` (line 151). AccordKit unit and REST integration tests are blocking. |
| AccordStream tests skip in headless CI | Medium | Tests guard with `pass_test("No X available — skipping")` when no hardware is detected. Most tests will be skipped in headless environments. |
| `test_disconnect_clean_state` is a smoke test | Low | `tests/accordkit/gateway/test_gateway_connect.gd` — the disconnect test just asserts `true` after logout; does not verify internal connection state. |
| No mock/stub/double usage | Medium | All tests use real instantiated objects. GUT's mock/double/stub capabilities are unused. This makes unit testing of components with dependencies (Client, AppState) impractical without a live server or full scene tree. |
| GDExtension binary staleness undetected | Medium | AccordStream source changes (e.g., adding `set_output_device()`) are not automatically rebuilt. Stale binaries cause GDScript parse errors that cascade through dependent scripts. CI doesn't verify that the binary matches the source. |
| No tests for responsive layout behavior | Low | Layout mode breakpoints are tested in `test_app_state.gd`, but the actual UI response (sidebar drawer, hamburger button, panel visibility) in `main_window.gd` is untested. |
