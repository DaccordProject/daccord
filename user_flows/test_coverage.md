# Test Coverage

Last touched: 2026-03-25
Priority: 38
Depends on: None

## Overview

daccord uses the GUT (Godot Unit Test) framework for automated testing. The test suite spans seven tiers: unit tests for autoloads and UI components, AccordKit unit/integration/gateway/e2e tests that hit a live accordserver, LiveKit adapter tests for the voice/video bridge, sync integration tests for the daccord-sync service, and Client API bash tests for the test API HTTP endpoints. A Bash runner (`test.sh`) orchestrates server lifecycle and suite selection, while GitHub Actions CI runs lint, unit tests, integration tests, Client API tests, GodotLite/Web/Windows export validation, and Chrome smoke tests on every PR.

## User Steps

1. Developer runs `./test.sh` (or `./test.sh unit`, `./test.sh integration`, `./test.sh livekit`, `./test.sh sync`, `./test.sh client`, etc.) from the project root.
2. The runner resolves which test directories to include and whether an accordserver instance is needed.
3. If a server is needed, the runner builds accordserver, clears the test database, starts the server in `ACCORD_TEST_MODE`, and polls `:39099` until ready. Alternatively, `ACCORD_TEST_URL` can point to a remote server.
4. GUT runs each suite directory via `godot --headless -s addons/gut/gut_cmdln.gd`.
5. For the `client` suite, the runner starts Daccord itself with `--test-api` and runs bash test scripts from `tests/client_api/`.
6. Results print to stdout; server logs go to `test_server.log`.
7. On exit, the runner kills the server (and Daccord if running) and removes the test database.

## Signal Flow

```
Developer
  |
  v
test.sh
  +-- resolve_dirs() --> NEEDS_SERVER flag + GUT_DIRS
  +-- setup_godot_user_dir() --> isolated XDG_DATA_HOME / HOME
  +-- start_server()  --> cargo build + cargo run (ACCORD_TEST_MODE=true)
  |       +-- poll /api/v1/gateway until 200
  +-- run_tests()              [for GUT suites]
  |     +-- for each dir in GUT_DIRS:
  |           godot --headless -s gut_cmdln.gd -gdir=<dir>
  |             +-- GutTest.before_all()  (AccordTestBase calls /test/seed)
  |             +-- GutTest.before_each() (creates fresh AccordClient instances)
  |             +-- test_*() methods
  |             +-- GutTest.after_each()  (queue_free clients)
  |             +-- GutTest.after_all()
  +-- run_client_api_tests()   [for client suite]
  |     +-- start_daccord() --> godot --test-api --test-api-port 39100
  |     +-- for each tests/client_api/test_*.sh:
  |           bash test_script (curl-based HTTP assertions)
  |     +-- stop_daccord() --> POST /api/quit + kill
  v
cleanup() --> kill server + kill daccord + rm accord_test.db
```

## Key Files

| File | Role |
|------|------|
| `test.sh` | Bash test runner -- suite selection, server lifecycle, GUT invocation, Client API runner |
| `.gutconfig.json` | GUT framework config -- dirs, prefix, suffix, log level, failure_error_types |
| `.github/workflows/ci.yml` | CI pipeline -- lint + unit + integration + Client API + GodotLite/Web/Windows export validation |
| `.github/workflows/release.yml` | Release pipeline -- cross-platform export + GitHub Release |
| `tests/helpers/test_data_factory.gd` | Shared test data factory for creating mock dictionaries |
| `tests/unit/helpers/mock_message_view.gd` | Minimal mock of MessageView for scroll tests |
| `tests/accordkit/helpers/test_base.gd` | AccordTestBase -- seeds server, creates clients per test |
| `tests/accordkit/helpers/seed_client.gd` | SeedClient -- POSTs to `/test/seed` for test data |
| `tests/unit/test_app_state.gd` | AppState signal bus (37 tests) |
| `tests/unit/test_config.gd` | Config persistence, credentials, export/import (24 tests) |
| `tests/unit/test_config_profiles.gd` | Config profiles -- slugify, CRUD, passwords, ordering (28 tests) |
| `tests/unit/test_markdown.gd` | Markdown-to-BBCode renderer (11 tests) |
| `tests/unit/test_auth_dialog.gd` | Auth dialog UI (13 tests) |
| `tests/unit/test_add_server_dialog.gd` | Add-server dialog + URL parser (18 tests) |
| `tests/unit/test_security.gd` | BBCode sanitization, URL scheme blocking, state integrity (28 tests) |
| `tests/unit/test_client_models.gd` | ClientModels *_to_dict() conversions + helpers (82 tests) |
| `tests/unit/test_client.gd` | Client autoload -- data access, routing, permissions, unread (60 tests) |
| `tests/unit/test_client_startup.gd` | Client `_ready()` startup -- sub-modules, voice session wiring (6 tests) |
| `tests/unit/test_client_gateway.gd` | ClientGateway -- event dispatch, cache mutation, signal routing (36 tests) |
| `tests/unit/test_client_fetch.gd` | ClientFetch primary -- spaces, channels, messages, older messages, threads, forums (27 tests) |
| `tests/unit/test_client_fetch_secondary.gd` | ClientFetch secondary -- members, roles, voice states, current user, DMs (21 tests) |
| `tests/unit/test_client_admin.gd` | ClientAdmin -- null-client guards, ban/unban, invite, emoji, audit log (35 tests) |
| `tests/unit/test_client_connection.gd` | ClientConnection -- is_space_connected, connection status, disconnect (20 tests) |
| `tests/unit/test_client_mutations.gd` | ClientMutations -- send/edit/delete message, update presence (14 tests) |
| `tests/unit/test_client_relationships.gd` | ClientRelationships -- friend requests, accept/decline, block/unblock (22 tests) |
| `tests/unit/test_client_permissions.gd` | ClientPermissions -- has_permission, has_channel_permission, overwrites (24 tests) |
| `tests/unit/test_client_voice.gd` | ClientVoice -- join voice channel signal behavior, session state (7 tests) |
| `tests/unit/test_client_plugins.gd` | ClientPlugins -- caching, gateway events, sessions, roles, voice cleanup (51 tests) |
| `tests/unit/test_client_mcp.gd` | ClientMcp -- JSON-RPC dispatch, tool groups, content wrapping, token validation (45 tests) |
| `tests/unit/test_client_test_api.gd` | ClientTestApi -- request parsing, endpoint routing (29 tests) |
| `tests/unit/test_message_content.gd` | Message content rendering + edit mode (10 tests) |
| `tests/unit/test_cozy_message.gd` | Cozy message layout + context menu (8 tests) |
| `tests/unit/test_collapsed_message.gd` | Collapsed message layout + timestamp (6 tests) |
| `tests/unit/test_composer.gd` | Composer UI elements + reply bar (8 tests) |
| `tests/unit/test_typing_indicator.gd` | Typing indicator show/hide + animation (6 tests) |
| `tests/unit/test_reaction_pill.gd` | Reaction pill setup + optimistic update (7 tests) |
| `tests/unit/test_reaction_bar.gd` | Reaction bar container (5 tests) |
| `tests/unit/test_message_action_bar.gd` | Message action bar interaction buttons (18 tests) |
| `tests/unit/test_message_view_scroll.gd` | MessageViewScroll helper class (8 tests) |
| `tests/unit/test_message_view_banner.gd` | MessageViewBanner -- UI node wrapping, space lookup (23 tests) |
| `tests/unit/test_embed.gd` | Embed component -- title, author, fields, footer, color, type (12 tests) |
| `tests/unit/test_channel_item.gd` | Channel item -- setup, type icons, NSFW, unread, active (21 tests) |
| `tests/unit/test_category_item.gd` | Category item -- setup, collapse, channel items (10 tests) |
| `tests/unit/test_guild_icon.gd` | Guild icon -- setup, pill state, mention badge (11 tests) |
| `tests/unit/test_guild_folder.gd` | Guild folder -- setup, expand/collapse, notifications, context menu (24 tests) |
| `tests/unit/test_dm_channel_item.gd` | DM channel item -- setup, active state (9 tests) |
| `tests/unit/test_dm_list.gd` | DM list sidebar component (13 tests) |
| `tests/unit/test_create_group_dm_dialog.gd` | Create group DM dialog -- user selection, creation (18 tests) |
| `tests/unit/test_user_bar.gd` | User bar -- avatar, display name, status icon (12 tests) |
| `tests/unit/test_member_list.gd` | Member list -- display, sorting, filtering (14 tests) |
| `tests/unit/test_updater.gd` | Updater semver + parse_release + instance state (34 tests) |
| `tests/unit/test_error_reporting.gd` | ErrorReporting -- guard clauses, signal handlers, PII scrubbing (22 tests) |
| `tests/unit/test_user_settings.gd` | Settings panels -- script loading, pages, navigation, input sensitivity (16 tests) |
| `tests/unit/test_emoji_picker.gd` | Emoji picker -- category tabs, emoji rendering, custom tab (15 tests) |
| `tests/unit/test_search_panel.gd` | Search panel -- message/channel search, result filtering (25 tests) |
| `tests/unit/test_sound_manager.gd` | SoundManager -- audio playback, volume, status changes (16 tests) |
| `tests/unit/test_voice_bar.gd` | Voice bar sidebar -- visibility, signals, buttons (12 tests) |
| `tests/unit/test_voice_channel_item.gd` | Voice channel item -- setup, set_active, signals (11 tests) |
| `tests/unit/test_voice_text_panel.gd` | Voice text panel -- UI elements, visibility lifecycle (17 tests) |
| `tests/unit/test_web_voice_session.gd` | WebVoiceSession -- public API, state machine transitions (25 tests) |
| `tests/unit/test_screen_picker_dialog.gd` | Screen picker dialog -- UI structure, source listing (13 tests) |
| `tests/unit/test_password_field.gd` | Password field -- input, visibility toggle (12 tests) |
| `tests/unit/test_profile_password_dialog.gd` | Profile password dialog -- verification, UI (13 tests) |
| `tests/unit/test_create_profile_dialog.gd` | Create profile dialog -- name/password input, creation (17 tests) |
| `tests/unit/test_add_friend_dialog.gd` | Add friend dialog -- username input, request UI (9 tests) |
| `tests/unit/test_friend_item.gd` | Friend item component -- setup, display name, status (22 tests) |
| `tests/unit/test_friends_list.gd` | Friends list -- tab switching (all/online/blocked), filtering (15 tests) |
| `tests/unit/test_uri_handler.gd` | UriHandler -- parse_uri for connect/chat/server routes (38 tests) |
| `tests/unit/test_sync_encryption.gd` | SyncManager encryption -- PBKDF2-HMAC-SHA256, AES-256-CBC, key derivation (19 tests) |
| `tests/unit/test_plugin_canvas.gd` | PluginCanvas -- color parsing, command limits, buffer management (31 tests) |
| `tests/unit/test_plugin_context.gd` | PluginContext -- get_role, is_host, send_file, binary format (27 tests) |
| `tests/unit/test_plugin_download_manager.gd` | PluginDownloadManager -- SHA-256 hashing, cache, signature verification (28 tests) |
| `tests/unit/test_scripted_runtime.gd` | ScriptedRuntime -- Lua sandbox pure-logic methods (21 tests) |
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
| `tests/accordkit/unit/test_model_plugin_manifest.gd` | AccordPluginManifest model from_dict/to_dict/enums (5 tests) |
| `tests/accordkit/integration/test_users_api.gd` | REST /users endpoints (6 tests) |
| `tests/accordkit/integration/test_spaces_api.gd` | REST /spaces endpoints (5 tests) |
| `tests/accordkit/integration/test_channels_api.gd` | REST /channels endpoints (3 tests) |
| `tests/accordkit/integration/test_messages_api.gd` | REST /messages CRUD + typing (6 tests) |
| `tests/accordkit/integration/test_members_api.gd` | REST /members endpoints (4 tests) |
| `tests/accordkit/integration/test_permissions_api.gd` | Server-enforced permission checks (23 tests) |
| `tests/accordkit/integration/test_plugins_api.gd` | REST /plugins endpoints -- list, sessions, roles, actions (10 tests) |
| `tests/accordkit/integration/test_dm_api.gd` | REST /dm endpoints -- list, create, fetch, delete, update, recipients (15 tests) |
| `tests/accordkit/gateway/test_gateway_connect.gd` | WebSocket connect/disconnect lifecycle (3 tests) |
| `tests/accordkit/gateway/test_gateway_events.gd` | Real-time gateway event delivery (1 test) |
| `tests/accordkit/e2e/test_full_lifecycle.gd` | Full login-to-logout lifecycle (1 test) |
| `tests/accordkit/e2e/test_add_server.gd` | Full invite flow (1 test) |
| `tests/accordkit/e2e/test_voice_auth_handshake.gd` | Voice REST join/leave flow (5 tests) |
| `tests/livekit/unit/test_livekit_adapter.gd` | LiveKitAdapter -- state machine, mute/deafen, signals (12 tests) |
| `tests/livekit/unit/test_local_video_preview.gd` | LocalVideoPreview -- frame updates, RGBA8 texture handling (10 tests) |
| `tests/livekit/unit/test_screen_capture_lifecycle.gd` | Screen capture lifecycle -- unshare crash prevention (7 tests) |
| `tests/integration/test_sync_manager.gd` | SyncManager -- push/pull flow integration (5 tests) |
| `tests/client_api/test_state_endpoints.sh` | Client API state endpoint assertions (bash) |
| `tests/client_api/test_navigation.sh` | Client API navigation endpoint assertions (bash) |
| `tests/client_api/test_lifecycle.sh` | Client API lifecycle endpoint assertions (bash) |

## Implementation Details

### Test Runner (`test.sh`)

The runner (lines 1-413) uses `set -euo pipefail` for strict error handling. Suite resolution (lines 82-127) maps CLI arguments to `res://` paths and a `NEEDS_SERVER` boolean:

| Argument | Directories | Server needed |
|----------|-------------|---------------|
| `unit` | `res://tests/unit` | No |
| `accordkit` / `integration` | `res://tests/accordkit/unit,res://tests/accordkit/integration` | Yes |
| `gateway` | `res://tests/accordkit/gateway,res://tests/accordkit/e2e` | Yes |
| `livekit` | `res://tests/livekit` | No |
| `sync` | `res://tests/integration` | No (requires Docker on port 3001) |
| `client` | N/A (runs bash scripts) | Yes |
| `all` (default) | `res://tests/unit,res://tests/accordkit/unit,res://tests/accordkit/integration,res://tests/livekit` | Yes |

Extra positional arguments after the suite name are passed as `-gselect` filters (e.g., `./test.sh unit test_emoji_picker`).

The runner sets up an isolated Godot user directory via `setup_godot_user_dir()` (lines 60-75) -- `XDG_DATA_HOME` on Linux, overridden `HOME` on macOS.

Server startup (lines 132-190): builds with `cargo build --quiet`, removes stale `accord_test.db*` files, starts with `ACCORD_TEST_MODE=true` and `DATABASE_URL=sqlite:accord_test.db?mode=rwc`, then polls `GET /api/v1/gateway` up to 30 times at 1s intervals. If the server is already running on `:39099`, it reuses the existing instance (line 380). The `ACCORD_TEST_URL` environment variable allows running against a remote server (lines 370-378).

The Client API test runner (lines 267-352) starts Daccord with `--test-api --test-api-port 39100 --test-api-no-auth`, polls `/api/get_state` until ready, then runs each `tests/client_api/test_*.sh` script. Daccord is stopped via POST to `/api/quit` then `kill`.

Cleanup (lines 204-212) runs via `trap cleanup EXIT INT TERM` -- kills both Daccord and the server process, and removes the test database.

### GUT Configuration (`.gutconfig.json`)

Minimal config: three directories (`res://tests/unit`, `res://tests/accordkit`, `res://tests/livekit`) with `include_subdirs=true`, `prefix=test_`, `suffix=.gd`, `log_level=1`. `should_exit=true` ensures the Godot process exits after tests complete. `should_exit_on_success=false` keeps Godot running briefly so logs flush on failure. `failure_error_types` includes both `gut` and `push_error`.

### AccordTestBase (`tests/accordkit/helpers/test_base.gd`)

Base class for all server-dependent tests. Constants `BASE_URL` and `GATEWAY_URL` point to `127.0.0.1:39099` (lines 3-4).

`before_all()` (line 41): calls `SeedClient.seed(self)` which POSTs to `/test/seed`. Extracts `user_id`, `user_token`, `bot_id`, `bot_token`, `bot_application_id`, `space_id`, `general_channel_id`, `testing_channel_id`, and `plugin_id` from the response.

`before_each()` (line 71): creates fresh `bot_client` (Bot token) and `user_client` (Bearer token) via `_create_client()`. Each `AccordClient` gets full `GatewayIntents.all()` and is added as a child node.

`after_each()` (line 76): calls `queue_free()` on both clients.

### Unit Tests (`tests/unit/`)

65 test files, 1339 tests. All extend `GutTest`.

**test_app_state.gd** -- 37 tests covering `AppState` signals and state mutations. Tests space/channel selection, DM mode entry, message send/reply/edit/delete signals, layout mode breakpoints (COMPACT <500px, MEDIUM <768px, FULL >=768px), sidebar drawer toggle, and state transition sequences.

**test_config.gd** -- 24 tests for `Config` in-memory behavior (no disk I/O). Tests `add_server`, `remove_server`, `clear`, `has_servers`, `get_servers`, edge cases, `_load_ok` guard, `update_server_credentials`, `export_config`/`import_config` round-trip, `export_strips_secrets`, `_migrate_clear_passwords`, and `add_server_no_password_key`.

**test_config_profiles.gd** -- 28 tests for Config multi-profile management. Covers `_slugify` (basic, special chars, truncation, collision, empty input), `_hash_password` (determinism, different slugs/passwords), `create_profile` (fresh, with password, copy from current), `delete_profile`, `rename_profile`, `set_profile_password`/`verify_profile_password`, `get_profiles` ordering, `get_active_profile_slug`, and `move_profile_up`/`move_profile_down`.

**test_markdown.gd** -- 11 tests for `ClientModels.markdown_to_bbcode()`. Covers bold, italic, strikethrough, underline, inline code, code blocks, spoiler, links, blockquotes, and plain passthrough.

**test_auth_dialog.gd** -- 13 tests for the auth dialog scene. Verifies UI elements, initial sign-in mode, mode toggle, validation (empty username/password), signal existence, and dialog close.

**test_add_server_dialog.gd** -- 18 tests for the add-server dialog and URL parser. Tests UI elements, validation, URL parsing (bare host, port, protocol, fragment, query, full URL, whitespace stripping), signal existence, and dialog close.

**test_security.gd** -- 28 tests verifying security properties. BBCode sanitization (8), malicious URL schemes (4), input boundary (5), regex abuse (4), and state integrity (7).

**test_client_models.gd** -- 82 tests for `ClientModels` static conversion functions. Covers `_color_from_id`, `_status_string_to_enum`/`_status_enum_to_string`, `_channel_type_to_enum`, `_format_timestamp`, `user_to_dict`, `space_to_dict`, `channel_to_dict`, `message_to_dict`, `member_to_dict`, `dm_channel_to_dict`, `role_to_dict`, `invite_to_dict`, `emoji_to_dict`, `sound_to_dict`, `voice_state_to_dict`, `embed_to_dict`.

**test_client.gd** -- 60 tests for the Client autoload's pure logic. Tests URL derivation, cache getters, routing helpers, permission checking, unread tracking, user cache trimming, space folder update, connection state helpers, and `_find_channel_for_message`.

**test_client_startup.gd** -- 6 smoke tests for the Client `_ready()` startup path. Verifies sub-module creation, AccordVoiceSession, signal wiring, and initial state.

**test_client_gateway.gd** -- 36 tests for ClientGateway event handlers. Tests message create/update/delete, typing, presence/user updates, space/channel/role CRUD, reactions, voice state, and gateway lifecycle.

**test_client_fetch.gd** -- 27 tests for ClientFetch primary methods. Uses `StubRest` to intercept REST calls. Covers `fetch_spaces`, `fetch_channels`, `fetch_messages`, `fetch_older_messages`, `fetch_thread_messages`, `fetch_forum_posts`, `fetch_active_threads`.

**test_client_fetch_secondary.gd** -- 21 tests for ClientFetch secondary methods. Covers `fetch_members`, `fetch_roles`, `fetch_voice_states`, `refresh_current_user`, `fetch_dm_channels`, `_fetch_unknown_authors`, `resync_voice_states`.

**test_client_admin.gd** -- 35 tests for ClientAdmin. Tests null-client guard clauses for all admin methods, happy-path routing, and success-path side effects.

**test_client_connection.gd** -- 20 tests for ClientConnection. Tests `is_space_connected`, `get_space_connection_status`, `_all_failed`, `disconnect_server`, and connection lifecycle.

**test_client_mutations.gd** -- 14 tests for ClientMutations. Tests `send_message_to_channel`, `update_message_content`, `remove_message`, `update_presence`, and null-client guards.

**test_client_relationships.gd** -- 22 tests for ClientRelationships. Tests friend request send/accept/decline, block/unblock, friendship cache, and relationship state transitions.

**test_client_permissions.gd** -- 24 tests for ClientPermissions. Tests `has_permission` (admin bypass, owner bypass, role-based grant/deny, everyone role), `has_channel_permission` (overwrite resolution, allow/deny/inherit), and edge cases.

**test_client_voice.gd** -- 7 tests for ClientVoice. Tests `join_voice_channel` signal behavior, voice session state tracking, and error paths.

**test_client_plugins.gd** -- 51 tests for ClientPlugins. Covers plugin cache operations, gateway install/uninstall events, role changes, session state transitions (lobby/running/ended), voice disconnect cleanup, connection isolation, and comprehensive session lifecycle.

**test_client_mcp.gd** -- 45 tests for ClientMcp. Tests JSON-RPC 2.0 dispatch, tool group filtering and permissions, MCP content type wrapping, bearer token validation, error responses, and tool listing.

**test_client_test_api.gd** -- 29 tests for ClientTestApi. Tests HTTP request parsing, endpoint routing for state/navigate/screenshot/action/moderation/voice groups, and error handling.

**test_message_content.gd** -- 10 tests for message content rendering. Covers plain text, edited indicator, system message styling, `_format_file_size`, and edit mode.

**test_cozy_message.gd** -- 8 tests for cozy message layout. Covers author name, timestamp, avatar, color override, reply reference, context menu, and data storage.

**test_collapsed_message.gd** -- 6 tests for collapsed message layout. Covers content setup, timestamp extraction, context menu, and data storage.

**test_composer.gd** -- 8 tests for the message composer. Covers UI elements, initial state, `set_channel_name`, and reply cancel.

**test_typing_indicator.gd** -- 6 tests for the typing indicator. Covers initial state, `show_typing`, and `hide_typing`.

**test_reaction_pill.gd** -- 7 tests for the reaction pill. Covers `setup`, active/inactive state, and optimistic toggle.

**test_reaction_bar.gd** -- 5 tests for the reaction bar container. Covers empty/non-empty, ID injection, clearing, and single reaction.

**test_message_action_bar.gd** -- 18 tests for the message action bar. Tests button visibility, interaction callbacks, permission gating, and hover behavior.

**test_message_view_scroll.gd** -- 8 tests for MessageViewScroll. Covers `_old_message_count`, `auto_scroll`, `is_loading_older`, and `get_last_message_child`.

**test_message_view_banner.gd** -- 23 tests for MessageViewBanner. Tests RefCounted wrapping of UI nodes, space lookup, channel header rendering, and topic display.

**test_embed.gd** -- 12 tests for the embed component. Covers setup, title/URL, description, author, fields, footer, color, and type "image".

**test_channel_item.gd** -- 21 tests for channel item sidebar. Covers setup, type icon selection (TEXT/VOICE/ANNOUNCEMENT/FORUM), NSFW tint, unread dot, `set_active`, threads indicator, and signal existence.

**test_category_item.gd** -- 10 tests for category item sidebar. Covers setup, collapse toggle, `get_category_id`, and signal existence.

**test_guild_icon.gd** -- 11 tests for guild icon sidebar. Covers setup, pill state, mention badge, `set_active`, and signal existence.

**test_guild_folder.gd** -- 24 tests for guild folder sidebar. Covers setup, expand/collapse, `set_active`/`set_active_space`, notification aggregation, context menu, and signals.

**test_dm_channel_item.gd** -- 9 tests for DM channel list item. Covers setup, `set_active`, and signal existence.

**test_dm_list.gd** -- 13 tests for DM list sidebar. Tests DM channel listing, ordering, group DM display, and selection management.

**test_create_group_dm_dialog.gd** -- 18 tests for group DM creation dialog. Tests user selection UI, recipient chips, search filtering, and creation flow.

**test_user_bar.gd** -- 12 tests for user bar. Covers avatar handling (null/missing/empty), display name, username, avatar letter, and status icon color.

**test_member_list.gd** -- 14 tests for member list panel. Tests member display, role-based grouping, sorting, online/offline filtering, and refresh behavior.

**test_updater.gd** -- 34 tests for Updater semver utilities. Covers `parse_semver`, `compare_semver`, `is_newer`, `parse_release`, and instance state.

**test_error_reporting.gd** -- 22 tests for ErrorReporting. Guard clause tests (4), signal handler tests (9+), and PII scrubbing tests (7+).

**test_user_settings.gd** -- 16 smoke tests for settings panels. Script loading (6), instantiation (1), profile type (2), page building (2), input sensitivity (4), Escape key (1).

**test_emoji_picker.gd** -- 15 tests for emoji picker. Tests category tab rendering, emoji grid population, custom emoji tab, search functionality, and picker insertion callback.

**test_search_panel.gd** -- 25 tests for search panel. Tests message/channel search, query input, result list rendering, result filtering, pagination, and panel visibility toggling.

**test_sound_manager.gd** -- 16 tests for SoundManager. Tests audio playback triggers, volume control, status change sounds, mute state, and AudioBus routing.

**test_voice_bar.gd** -- 12 tests for voice bar sidebar. Tests visibility toggling, signal surface, button structure, mute/deafen indicators, and disconnect button.

**test_voice_channel_item.gd** -- 11 tests for voice channel item. Tests setup with channel data, `set_active` behavior, participant count display, and signals.

**test_voice_text_panel.gd** -- 17 tests for voice text panel. Tests UI element structure, visibility lifecycle, message display, composer targeting, and panel toggle.

**test_web_voice_session.gd** -- 25 tests for WebVoiceSession. Tests public API surface, state machine transitions (DISCONNECTED -> CONNECTING -> CONNECTED -> DISCONNECTED), mute/deafen state, and signal emission.

**test_screen_picker_dialog.gd** -- 13 tests for screen picker dialog. Tests UI structure, screen/window source listing, selection handling, and dialog close.

**test_password_field.gd** -- 12 tests for password field component. Tests input field behavior, visibility toggle button, show/hide password text, and signal emission.

**test_profile_password_dialog.gd** -- 13 tests for profile password dialog. Tests password verification flow, wrong password error, UI elements, and dialog lifecycle.

**test_create_profile_dialog.gd** -- 17 tests for create profile dialog. Tests name input, password fields, copy-from option, validation (empty name, matching passwords), and creation signal.

**test_add_friend_dialog.gd** -- 9 tests for add friend dialog. Tests username input, validation, error display, and request submission.

**test_friend_item.gd** -- 22 tests for friend item component. Tests setup with user data, display_name rendering, status display, avatar, action buttons (message/remove/block), and signal emission.

**test_friends_list.gd** -- 15 tests for friends list panel. Tests tab switching (All/Online/Pending/Blocked), friend item rendering, filtering logic, and empty state display.

**test_uri_handler.gd** -- 38 tests for UriHandler. Tests `parse_uri` for `daccord://connect`, `daccord://chat`, `daccord://server` routes, parameter extraction (host, port, token, invite, channel, message), malformed URIs, empty/missing parameters, and security validation.

**test_sync_encryption.gd** -- 19 tests for SyncManager E2E encryption. Tests PBKDF2-HMAC-SHA256 key derivation, AES-256-CBC encrypt/decrypt round-trip, IV uniqueness, wrong-password rejection, empty/large payloads, and binary compatibility.

**test_plugin_canvas.gd** -- 31 tests for PluginCanvas. Tests color parsing (hex, named, invalid), draw command limits, pixel buffer management, text rendering, rect/circle/line drawing, clear command, and canvas size constraints.

**test_plugin_context.gd** -- 27 tests for PluginContext. Tests `get_role`, `is_host`, `send_file` binary framing, data channel message format, action dispatch, state access, and binary protocol consistency.

**test_plugin_download_manager.gd** -- 28 tests for PluginDownloadManager. Tests SHA-256 hash computation, cache directory management, ZIP integrity checks, signature verification (Ed25519), manifest extraction, path traversal prevention, and cache invalidation.

**test_scripted_runtime.gd** -- 21 tests for ScriptedRuntime. Tests Lua sandbox pure-logic: safe library list, forbidden module blocking, canvas API command generation, context bridge methods, and runtime lifecycle.

### AccordKit Unit Tests (`tests/accordkit/unit/`)

Twelve test files, 134 tests:

- **test_snowflake.gd** (9 tests) -- Encode/decode roundtrip, epoch constant, nonce uniqueness, datetime conversion.
- **test_rest_result.gd** (8 tests) -- Success/failure construction, cursor/has_more, null data (204), array data.
- **test_intents.gd** (8 tests) -- Default/all/privileged/unprivileged intent sets, counts, union property.
- **test_cdn.gd** (12 tests) -- URL generation for avatars, space icons/banners, emojis, attachments, animated hash detection.
- **test_permissions.gd** (7 tests) -- All permissions count (39), has/has-not, administrator grants all, empty set, uniqueness.
- **test_multipart_form.gd** (8 tests) -- Content-type boundary, field/JSON/file parts, closing boundary, empty/multiple parts.
- **test_model_plugin_manifest.gd** (5 tests) -- `from_dict` full/minimal, `to_dict` roundtrip, canvas_size, enum values.
- **test_model_*.gd** (5 files, 77 tests) -- `from_dict` full/minimal, `to_dict` roundtrip, null field omission, field aliases, nested dicts.

### AccordKit Integration Tests (`tests/accordkit/integration/`)

Eight test files, 72 tests, all extending `AccordTestBase`:

- **test_users_api.gd** (6 tests) -- `get_me`, `get_user`, 404 for nonexistent, `list_spaces`, `update_me`.
- **test_spaces_api.gd** (5 tests) -- `get_space`, `create_space`, `update_space`, `list_channels`, `create_channel`.
- **test_channels_api.gd** (3 tests) -- `get_channel`, general channel, `update_channel` topic.
- **test_messages_api.gd** (6 tests) -- Create, list, get, edit, delete, typing indicator.
- **test_members_api.gd** (4 tests) -- List, get member, get bot member, update nickname.
- **test_permissions_api.gd** (23 tests) -- Server-enforced permissions: 403 for unauthorized, owner succeeds, escalation test (grant + use permission).
- **test_plugins_api.gd** (10 tests) -- Plugin REST: list, filter by type, manifest fields, sessions CRUD, state transitions, roles, actions.
- **test_dm_api.gd** (15 tests) -- DM REST: list DM channels, create DM, fetch messages, delete, update, recipient management.

### AccordKit Gateway Tests (`tests/accordkit/gateway/`)

- **test_gateway_connect.gd** (3 tests) -- Bot/user connect, poll for `ready_received`, disconnect signal + state verification.
- **test_gateway_events.gd** (1 test) -- Bot connects, user sends message, bot receives `message_create` event.

### AccordKit E2E Tests (`tests/accordkit/e2e/`)

- **test_full_lifecycle.gd** (1 test) -- 7-step flow: login, get_me, create space, list channels, send+fetch message, cross-client gateway event, logout.
- **test_add_server.gd** (1 test) -- 8-step invite flow: create space, create invite, gateway connect, accept invite, verify member_join, REST verify, send message, logout.
- **test_voice_auth_handshake.gd** (5 tests) -- Voice backend probe, channel creation, LiveKit credentials, mute/deaf flags, graceful leave-without-join.

### LiveKit Tests (`tests/livekit/unit/`)

Three test files, 29 tests, no server needed:

- **test_livekit_adapter.gd** (12 tests) -- State machine, mute/deafen, signal surface, disconnect, unpublish.
- **test_local_video_preview.gd** (10 tests) -- Frame update handling, RGBA8 texture creation, viewport sizing, empty frame handling.
- **test_screen_capture_lifecycle.gd** (7 tests) -- Screen capture start/stop lifecycle, unshare crash prevention, X11 display fallback.

### Integration Tests (`tests/integration/`)

- **test_sync_manager.gd** (5 tests) -- SyncManager push/pull integration against daccord-sync Docker container on port 3001.

### Client API Tests (`tests/client_api/`)

Three bash scripts testing the Client Test API HTTP endpoints:

- **test_state_endpoints.sh** -- State query endpoints (`get_state`, etc.).
- **test_navigation.sh** -- Navigation endpoints (select space/channel, DM mode).
- **test_lifecycle.sh** -- Lifecycle endpoints (connect, disconnect, quit).

### CI Pipeline (`.github/workflows/ci.yml`)

Six jobs on PR to `master` (also callable via `workflow_call`):

1. **lint** -- Python 3.12 + `gdtoolkit`, runs `gdlint scripts/ scenes/` (line 34). Code complexity analysis via `gdradon cc` emits warnings for grade C-F functions (lines 36-47).

2. **test** (Unit Tests) -- Installs audio libraries, godot-livekit addon, GUT, Sentry SDK. Runs project import + startup validation. Runs unit tests (`res://tests/unit`) with 5-minute timeout (lines 141-152). Runs LiveKit tests with `continue-on-error: true` (lines 154-166). Generates test result summary to `$GITHUB_STEP_SUMMARY` (lines 168-179).

3. **integration-test** -- Checks out accordserver, installs Rust with `sccache` caching, builds accordserver with fallback (lines 267-276), starts in test mode, polls until ready (lines 285-297). Runs AccordKit unit tests (lines 328-339), REST integration tests (lines 341-352), and Client API tests via Daccord `--test-api` (lines 354-401). Uploads server log as artifact (lines 424-430).

4. **godotlite-validation** -- Exports with GodotLite custom template for Linux, validates the binary starts via `--headless --quit` (lines 432-571).

5. **web-export** -- Exports Web build, serves via Python HTTP server with COOP/COEP headers, runs Chrome headless smoke test for SharedArrayBuffer/WASM errors (lines 573-787). Uploads web build artifact.

6. **windows-smoke-test** -- Exports Windows build via GodotLite template, validates binary starts under Wine64 (lines 789-947). Uploads Windows build artifact.

### Test Count Summary

| Suite | Files | Tests | Server needed |
|-------|-------|-------|---------------|
| Unit (`tests/unit/`) | 65 | 1339 | No |
| AccordKit unit (`tests/accordkit/unit/`) | 12 | 134 | No |
| AccordKit integration (`tests/accordkit/integration/`) | 8 | 72 | Yes |
| AccordKit gateway (`tests/accordkit/gateway/`) | 2 | 4 | Yes |
| AccordKit e2e (`tests/accordkit/e2e/`) | 3 | 7 | Yes |
| LiveKit (`tests/livekit/unit/`) | 3 | 29 | No |
| Integration (`tests/integration/`) | 1 | 5 | No (Docker) |
| Client API (`tests/client_api/`) | 3 bash | N/A | Yes |
| **Total** | **94 + 3 bash** | **1590** | |

## Implementation Status

- [x] Test runner with suite selection (`unit`, `integration`, `accordkit`, `gateway`, `livekit`, `sync`, `client`, `all`)
- [x] Remote server support via `ACCORD_TEST_URL` environment variable
- [x] Automatic server lifecycle (build, start, poll, cleanup)
- [x] Fresh database per test run (removes stale `accord_test.db*`)
- [x] Reuse of existing server instance if already running
- [x] Isolated Godot user directory per test run
- [x] AccordTestBase with `/test/seed` integration
- [x] GUT select filter for running individual tests (e.g., `./test.sh unit test_emoji_picker`)
- [x] CI lint job (`gdlint scripts/ scenes/` + code complexity analysis)
- [x] CI unit test job (Godot 4.5 headless)
- [x] CI integration test job (accordserver + AccordKit tests)
- [x] CI Client API test job (Daccord `--test-api` + bash scripts)
- [x] CI GodotLite export validation (Linux binary startup)
- [x] CI Web export + Chrome headless smoke test (COOP/COEP, SharedArrayBuffer, WASM)
- [x] CI Windows export + Wine smoke test
- [x] Release pipeline (cross-platform export + GitHub Release)
- [x] Unit tests for AppState (37 tests)
- [x] Unit tests for Config (24 tests)
- [x] Unit tests for Config profiles (28 tests)
- [x] Unit tests for markdown rendering (11 tests)
- [x] Unit tests for auth dialog (13 tests)
- [x] Unit tests for add-server dialog + URL parser (18 tests)
- [x] Security tests -- BBCode sanitization, URL scheme blocking, state integrity (28 tests)
- [x] Unit tests for ClientModels conversions (82 tests)
- [x] Unit tests for Client autoload -- data access, routing, permissions, unread (60 tests)
- [x] Unit tests for Client startup -- sub-modules, voice session wiring (6 tests)
- [x] Unit tests for ClientGateway -- event dispatch, cache mutation (36 tests)
- [x] Unit tests for ClientFetch -- primary + secondary (48 tests across 2 files)
- [x] Unit tests for ClientAdmin -- null-client guards, ban/unban, invite, emoji (35 tests)
- [x] Unit tests for ClientConnection -- connection status, disconnect (20 tests)
- [x] Unit tests for ClientMutations -- send/edit/delete, presence (14 tests)
- [x] Unit tests for ClientRelationships -- friends, block/unblock (22 tests)
- [x] Unit tests for ClientPermissions -- permission checks, overwrites (24 tests)
- [x] Unit tests for ClientVoice -- join voice, session state (7 tests)
- [x] Unit tests for ClientPlugins -- caching, gateway events, sessions, voice cleanup (51 tests)
- [x] Unit tests for ClientMcp -- JSON-RPC, tool groups, token validation (45 tests)
- [x] Unit tests for ClientTestApi -- request parsing, endpoint routing (29 tests)
- [x] Unit tests for message content rendering (10 tests)
- [x] Unit tests for cozy message layout (8 tests)
- [x] Unit tests for collapsed message layout (6 tests)
- [x] Unit tests for composer UI (8 tests)
- [x] Unit tests for typing indicator (6 tests)
- [x] Unit tests for reaction pill (7 tests)
- [x] Unit tests for reaction bar (5 tests)
- [x] Unit tests for message action bar (18 tests)
- [x] Unit tests for MessageViewScroll (8 tests)
- [x] Unit tests for MessageViewBanner (23 tests)
- [x] Unit tests for embed component (12 tests)
- [x] Unit tests for DM channel item (9 tests)
- [x] Unit tests for DM list (13 tests)
- [x] Unit tests for create group DM dialog (18 tests)
- [x] Unit tests for channel_item sidebar (21 tests)
- [x] Unit tests for category_item sidebar (10 tests)
- [x] Unit tests for guild_icon sidebar (11 tests)
- [x] Unit tests for guild_folder sidebar (24 tests)
- [x] Unit tests for user_bar (12 tests)
- [x] Unit tests for member_list (14 tests)
- [x] Unit tests for Updater semver + parse_release (34 tests)
- [x] Unit tests for ErrorReporting -- guard clauses, PII scrubbing (22 tests)
- [x] Unit tests for settings panels (16 tests)
- [x] Unit tests for emoji_picker (15 tests)
- [x] Unit tests for search_panel (25 tests)
- [x] Unit tests for SoundManager (16 tests)
- [x] Unit tests for voice_bar (12 tests)
- [x] Unit tests for voice_channel_item (11 tests)
- [x] Unit tests for voice_text_panel (17 tests)
- [x] Unit tests for WebVoiceSession (25 tests)
- [x] Unit tests for screen_picker_dialog (13 tests)
- [x] Unit tests for password_field (12 tests)
- [x] Unit tests for profile_password_dialog (13 tests)
- [x] Unit tests for create_profile_dialog (17 tests)
- [x] Unit tests for add_friend_dialog (9 tests)
- [x] Unit tests for friend_item (22 tests)
- [x] Unit tests for friends_list (15 tests)
- [x] Unit tests for UriHandler (38 tests)
- [x] Unit tests for SyncManager encryption (19 tests)
- [x] Unit tests for PluginCanvas (31 tests)
- [x] Unit tests for PluginContext (27 tests)
- [x] Unit tests for PluginDownloadManager (28 tests)
- [x] Unit tests for ScriptedRuntime (21 tests)
- [x] AccordKit model serialization tests (82 tests across 6 files)
- [x] AccordKit utility tests -- snowflake, REST result, intents, CDN, permissions, multipart (52 tests)
- [x] AccordKit REST integration tests -- users, spaces, channels, messages, members, DMs (39 tests)
- [x] AccordKit permission enforcement tests (23 tests)
- [x] AccordKit plugin REST integration tests (10 tests)
- [x] AccordKit gateway connect/event tests (4 tests)
- [x] AccordKit full lifecycle e2e test (1 test)
- [x] AccordKit invite flow e2e test (1 test)
- [x] AccordKit voice auth handshake e2e tests (5 tests)
- [x] LiveKit adapter unit tests -- state machine, mute/deafen, signals (12 tests)
- [x] LiveKit LocalVideoPreview tests (10 tests)
- [x] LiveKit screen capture lifecycle tests (7 tests)
- [x] SyncManager push/pull integration tests (5 tests)
- [x] Client API bash test scripts (3 scripts)

## Tasks

### TEST-1: No tests for `ClientFetch`
- **Status:** closed
- **Impact:** 4
- **Effort:** 1
- **Tags:** api, testing
- **Notes:** Split across `test_client_fetch.gd` (27 tests) and `test_client_fetch_secondary.gd` (21 tests) -- 48 tests covering all public methods.

### TEST-2: No tests for `ClientAdmin`
- **Status:** closed
- **Impact:** 3
- **Effort:** 1
- **Tags:** testing
- **Notes:** Resolved: `test_client_admin.gd` -- 35 tests.

### TEST-3: No tests for `ClientMutations`
- **Status:** closed
- **Impact:** 3
- **Effort:** 2
- **Tags:** messaging, testing
- **Notes:** Resolved: `test_client_mutations.gd` -- 14 tests covering send/edit/delete message and update presence.

### TEST-4: No tests for `ClientConnection`
- **Status:** closed
- **Impact:** 3
- **Effort:** 2
- **Tags:** connection, testing
- **Notes:** Resolved: `test_client_connection.gd` -- 20 tests covering connection status, disconnect, and lifecycle.

### TEST-5: No tests for message_view
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** messaging, testing, ui
- **Notes:** `scenes/messages/message_view.gd` (the scroll container / message list manager) is untested due to heavy `Client` dependency. `MessageViewScroll` has basic tests (8), `MessageViewBanner` has tests (23), and individual message components (cozy, collapsed, content, action_bar) are tested.

### TEST-6: No tests for sidebar containers
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** testing, ui
- **Notes:** Parent containers (`sidebar.gd`, `channel_list.gd`, `guild_bar.gd`) are untested due to heavy `Client` dependency. Leaf components (channel_item, category_item, guild_icon, guild_folder, dm_channel_item, dm_list, voice_channel_item, voice_bar) are tested.

### TEST-7: No tests for member_list
- **Status:** closed
- **Impact:** 2
- **Effort:** 1
- **Tags:** testing, ui
- **Notes:** Resolved: `test_member_list.gd` -- 14 tests covering display, sorting, filtering.

### TEST-8: No tests for admin dialogs
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** admin, testing, ui
- **Notes:** Admin dialog scenes (`space_settings_dialog`, `channel_management_dialog`, `role_management_dialog`, `ban_list_dialog`, `invite_management_dialog`, `emoji_management_dialog`, `channel_edit_dialog`, `category_edit_dialog`, `create_channel_dialog`, `channel_permissions_dialog`, `soundboard_management_dialog`, `plugin_management_dialog`, `audit_log_dialog`) have zero test coverage.

### TEST-9: No tests for emoji_picker
- **Status:** closed
- **Impact:** 2
- **Effort:** 2
- **Tags:** emoji, testing
- **Notes:** Resolved: `test_emoji_picker.gd` -- 15 tests covering categories, search, custom tab, insertion.

### TEST-10: No tests for search_panel
- **Status:** closed
- **Impact:** 2
- **Effort:** 1
- **Tags:** search, testing, ui
- **Notes:** Resolved: `test_search_panel.gd` -- 25 tests covering search input, results, filtering, pagination.

### TEST-11: No tests for `SoundManager` autoload
- **Status:** closed
- **Impact:** 2
- **Effort:** 2
- **Tags:** audio, testing
- **Notes:** Resolved: `test_sound_manager.gd` -- 16 tests covering playback, volume, status changes, mute.

### TEST-12: Gateway/e2e CI is non-blocking
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci, gateway, testing, voice
- **Notes:** Gateway and e2e tests are not run in CI at all (only AccordKit unit + REST integration + Client API are in the integration-test job). LiveKit tests use `continue-on-error: true` in the unit test job.

### TEST-13: `test_disconnect_clean_state` is a smoke test
- **Status:** closed
- **Impact:** 2
- **Effort:** 2
- **Tags:** gateway, testing
- **Notes:** Resolved: uses `watch_signals()` and `assert_signal_emitted()` to verify the `disconnected` signal fires and gateway state.

### TEST-14: No mock/stub/double usage
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** testing
- **Notes:** Tests use `StubRest` inner classes and direct object instantiation rather than GUT's mock/double/stub framework. This works well for Client sub-modules but makes testing complex UI components with deep dependencies impractical without a full scene tree.

### TEST-15: GDExtension binary staleness undetected
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci, voice
- **Notes:** CI installs the latest godot-livekit release binary, but LiveKit source changes are not automatically rebuilt. Stale binaries cause GDScript parse errors that cascade through dependent scripts.

### TEST-16: No tests for responsive layout behavior
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** testing, ui
- **Notes:** Layout mode breakpoints are tested in `test_app_state.gd`, but the actual UI response (sidebar drawer, hamburger button, panel visibility) in `main_window.gd` is untested.

### TEST-17: No tests for plugin UI scenes and runtimes
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** plugins, testing, ui
- **Notes:** Plugin runtime/canvas/context/download are now tested (`test_plugin_canvas.gd`, `test_plugin_context.gd`, `test_plugin_download_manager.gd`, `test_scripted_runtime.gd`). Remaining untested: `native_runtime.gd`, `activity_modal.gd`, `activity_lobby.gd`, `activity_panel.gd`, `plugin_trust_dialog.gd`.

### TEST-18: No tests for `ClientUnread` / `ClientEmoji`
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** testing
- **Notes:** `scripts/client/client_unread.gd` and `scripts/client/client_emoji.gd` sub-modules have no dedicated test files. Unread logic has partial coverage via `test_client.gd` and `test_client_gateway.gd`.

### TEST-19: Sync integration requires external Docker service
- **Status:** open
- **Impact:** 1
- **Effort:** 2
- **Tags:** ci, testing
- **Notes:** `./test.sh sync` requires daccord-sync running on port 3001 via Docker. Not run in CI; purely local.
