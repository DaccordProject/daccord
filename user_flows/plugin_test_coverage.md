# Plugin System Test Coverage

## Overview

Audit of test coverage for the server plugins system. The plugin system spans 14 source files (~3,000 lines) across AccordKit models, REST endpoints, autoload managers, runtimes, and UI components. Current tests cover the data model, REST API, ClientPlugins gateway/routing/bundle extraction/trust/state management, PluginDownloadManager pure logic and ZIP extraction, PluginCanvas color parsing/limits/buffers, PluginContext identity helpers and communication, NativeRuntime file framing/lifecycle, and ScriptedRuntime pure logic (constants, error checking, cleanup, bulk bridge parsing, payload validation). Remaining gaps are in the Lua sandbox (requires lua-gdextension), network orchestration methods (including newer `join_activity`, `check_active_session`), and UI dialogs.

## Test Inventory

### Unit Tests: `test_client_plugins.gd` — 51 tests

| Test | What it covers |
|------|---------------|
| `test_get_plugins_empty_by_default` | Empty cache returns `[]` |
| `test_get_plugin_returns_empty_when_not_found` | Unknown plugin returns `{}` |
| `test_get_conn_index_for_plugin_not_found` | Unknown plugin returns `-1` |
| `test_on_plugin_installed_adds_to_cache` | Gateway install populates cache (line 583) |
| `test_on_plugin_installed_ignores_empty_id` | Manifest missing `id` is silently dropped |
| `test_on_plugin_installed_updates_existing` | Re-install same ID replaces cached entry |
| `test_on_plugin_uninstalled_removes_from_cache` | Uninstall removes the correct entry |
| `test_on_plugin_uninstalled_noop_for_unknown` | Uninstalling unknown ID doesn't error |
| `test_on_plugin_role_changed_updates_local_role` | Role change for current user updates AppState |
| `test_on_plugin_role_changed_ignores_other_users` | Role change for other user doesn't touch local role |
| `test_on_plugin_session_state_updates_state` | Session state gateway event updates AppState |
| `test_on_plugin_session_state_ended_clears_activity` | `ended` state clears all active activity state |
| `test_on_plugin_session_state_ignores_other_sessions` | Mismatched session_id is ignored |
| `test_voice_left_clears_active_activity` | Voice disconnect clears activity and emits `activity_ended` |
| `test_voice_left_noop_when_no_activity` | Voice disconnect without activity is a no-op |
| `test_get_conn_index_for_plugin_found` | Correct connection index returned |
| `test_plugins_isolated_per_connection` | Plugins from different connections don't cross-contaminate |
| `test_livekit_data_strips_prefix_and_routes` | `_on_livekit_data_received` strips `plugin:<id>:` prefix and forwards to mock runtime (line 341) |
| `test_livekit_data_ignores_wrong_plugin_prefix` | Data with mismatched plugin prefix is dropped |
| `test_livekit_data_ignores_when_no_runtime` | No crash when `_active_runtime` is null |
| `test_livekit_data_ignores_non_plugin_topic` | Non-`plugin:` topics are ignored |
| `test_on_plugin_event_forwards_to_runtime` | `on_plugin_event` forwards event_type + data to runtime (line 607) |
| `test_on_plugin_event_noop_when_no_runtime` | No crash when no active runtime |
| `test_update_scripted_participants_updates_existing` | Role update for existing participant in scripted runtime (line 685) |
| `test_update_scripted_participants_adds_new` | New participant appended to scripted runtime list |
| `test_update_context_participants_updates_existing` | Role update for existing participant in PluginContext (line 695) |
| `test_update_context_participants_adds_new` | New participant appended to PluginContext list |
| `test_uninstall_active_plugin_clears_activity` | Uninstalling the active plugin clears session + AppState and emits `activity_ended` |
| `test_extract_bundle_valid_zip` | ZIP with entry point → returns lua_source, modules, assets |
| `test_extract_bundle_default_entry_point` | Falls back to "src/main.lua" when entry_point missing (line 198) |
| `test_extract_bundle_missing_entry_returns_empty` | ZIP without entry file returns `{}` (line 208) |
| `test_extract_bundle_extracts_modules` | `.lua` files extracted as modules dict keyed by basename (line 217) |
| `test_extract_bundle_extracts_assets` | `assets/` paths extracted as binary PackedByteArray (line 221) |
| `test_extract_bundle_invalid_zip_returns_empty` | Non-ZIP bytes return `{}` |
| `test_is_plugin_trusted_default_false` | Unknown server/plugin returns false (line 334) |
| `test_is_plugin_trusted_trust_all` | `Config.is_plugin_trust_all` returns true → trusted (line 335) |
| `test_is_plugin_trusted_specific_plugin` | `Config.get_plugin_trust` per-plugin trust (line 337) |
| `test_clear_pending_activity_resets_state` | All `AppState.pending_activity_*` fields cleared (line 738) |
| `test_clear_active_activity_resets_state` | All active session/AppState fields reset (line 746) |
| `test_clear_active_activity_stops_runtime` | Active runtime stopped and freed |
| `test_get_activity_viewport_texture_null_when_no_runtime` | Returns null with no runtime (line 488) |
| `test_get_activity_viewport_texture_delegates_to_runtime` | Delegates to runtime.get_viewport_texture() |
| `test_forward_activity_input_noop_when_no_runtime` | No crash with null runtime (line 495) |
| `test_forward_activity_input_delegates_to_runtime` | Delegates to runtime.forward_input() |
| `test_is_activity_host_false_by_default` | Default false (line 501) |
| `test_is_activity_host_true_when_set` | Returns true when _is_host is set |
| `test_get_session_participants_returns_list` | Returns _session_participants (line 506) |
| `test_stop_activity_noop_when_no_session` | Early return when _active_session_id empty (line 416) |
| `test_start_session_noop_when_no_session` | Early return when _active_session_id empty (line 435) |
| `test_assign_role_noop_when_no_session` | Early return when _active_session_id empty (line 455) |
| `test_send_action_noop_when_no_session` | Early return when _active_session_id empty (line 472) |

### Unit Tests: `test_plugin_canvas.gd` — 31 tests

| Test | What it covers |
|------|---------------|
| `test_parse_color_named_white` | Named color "white" resolves to `Color.WHITE` (line 315) |
| `test_parse_color_named_red` | Named color "red" resolves to `Color.RED` |
| `test_parse_color_named_transparent` | Named color "transparent" resolves to `Color.TRANSPARENT` |
| `test_parse_color_hex_6_digit` | 6-digit hex `#ff0000` resolves to red |
| `test_parse_color_hex_8_digit_with_alpha` | 8-digit hex with alpha channel |
| `test_parse_color_array_rgb` | 3-element array `[r, g, b]` → Color with alpha 1.0 (line 324) |
| `test_parse_color_array_rgba` | 4-element array `[r, g, b, a]` → Color with custom alpha |
| `test_parse_color_object_passthrough` | Color object passes through unchanged (line 316) |
| `test_parse_color_invalid_string_returns_white` | Unknown string falls back to `Color.WHITE` (line 323) |
| `test_parse_color_invalid_type_returns_white` | Non-string/array/Color falls back to white (line 330) |
| `test_parse_color_empty_array_returns_white` | Empty array falls back to white |
| `test_parse_color_two_element_array_returns_white` | 2-element array falls back to white |
| `test_push_command_within_limit` | Commands accepted within limit |
| `test_push_command_at_max_limit` | Exactly MAX_COMMANDS_PER_FRAME accepted (line 56) |
| `test_push_command_rejects_beyond_limit` | Commands beyond 4096 silently dropped |
| `test_clear_commands` | `clear_commands()` empties queue |
| `test_create_buffer_returns_handle` | Valid handle returned for new buffer |
| `test_create_buffer_respects_limit` | MAX_BUFFERS (4) enforced, returns -1 beyond limit (line 128) |
| `test_create_buffer_clamps_dimensions` | Oversized dimensions clamped to canvas bounds (line 133) |
| `test_set_buffer_pixel_within_bounds` | Pixel write at valid coords updates image |
| `test_set_buffer_pixel_out_of_bounds_ignored` | Out-of-bounds pixel writes silently ignored (line 158) |
| `test_set_buffer_pixel_invalid_handle_ignored` | Invalid handle doesn't crash |
| `test_set_buffer_data_correct_size` | Full buffer replacement with correct RGBA8 data (line 164) |
| `test_set_buffer_data_wrong_size_rejected` | Mismatched data size rejected (line 171) |
| `test_load_image_limit` | MAX_IMAGES constant is 64 |
| `test_free_resources_clears_all` | `free_resources()` resets all images, buffers, handles (line 194) |
| `test_clamp_x_within_bounds` | In-range x passes through |
| `test_clamp_x_negative_returns_zero` | Negative x clamped to 0 (line 206) |
| `test_clamp_x_beyond_width_returns_width` | Oversized x clamped to canvas_width |
| `test_clamp_y_beyond_height_returns_height` | Oversized y clamped to canvas_height |
| `test_setup_updates_dimensions` | `setup()` updates canvas_width/height |

### Unit Tests: `test_plugin_context.gd` — 27 tests

| Test | What it covers |
|------|---------------|
| `test_get_role_found` | `get_role()` returns correct role for known user (line 71) |
| `test_get_role_not_found` | `get_role()` returns empty string for unknown user |
| `test_get_role_empty_participants` | `get_role()` handles empty participant list |
| `test_is_host_true` | `is_host()` returns true when local_user_id == host_user_id (line 79) |
| `test_is_host_false` | `is_host()` returns false for non-host |
| `test_get_participants_returns_copy` | `get_participants()` returns a copy, not the original array (line 67) |
| `test_file_framing_roundtrip` | send_file encoding ↔ _handle_file_data decoding roundtrip matches (lines 51–62, 108–118) |
| `test_file_framing_empty_filename` | Empty filename encodes/decodes correctly |
| `test_file_framing_empty_data` | Zero-byte file data encodes/decodes correctly |
| `test_file_framing_unicode_filename` | UTF-8 filenames survive the roundtrip |
| `test_handle_file_data_too_short_ignored` | Payload under 4 bytes silently ignored (line 111) |
| `test_handle_file_data_truncated_name_ignored` | Name length exceeds payload — silently ignored (line 114) |
| `test_handle_file_data_valid_emits_signal` | Valid payload emits `file_received` with correct sender, name, data |
| `test_handle_file_data_null_context_ignored` | Null context doesn't crash (line 111) |
| `test_on_data_received_routes_non_file_to_context` | Non-"file:" topics route to `data_received` signal (line 92) |
| `test_on_data_received_routes_file_to_handler` | "file:" topics route to `_handle_file_data` (line 89) |
| `test_on_data_received_null_context_ignored` | Null context doesn't crash |
| `test_native_stop_noop_when_not_running` | NativeRuntime.stop() no-op when _running is false (line 61) |
| `test_native_stop_clears_state` | NativeRuntime.stop() sets _running=false, _context=null (line 62) |
| `test_native_on_plugin_event_noop_when_not_running` | on_plugin_event early return when not running (line 76) |
| `test_native_on_plugin_event_noop_when_no_scene` | on_plugin_event early return when no scene (line 76) |
| `test_native_get_viewport_texture_null_when_no_scene` | Returns null with no scene instance (line 97) |
| `test_native_forward_input_noop_when_no_scene` | No crash with null scene (line 104) |
| `test_native_runtime_initial_state` | Default state: _running=false, _scene_instance=null, _context=null |
| `test_context_send_action_noop_when_no_client_plugins` | send_action no-op with null _client_plugins (line 85) |
| `test_context_send_data_noop_when_no_adapter` | send_data no-op with null _livekit_adapter (line 40) |
| `test_context_session_state_defaults` | All PluginContext fields have correct defaults |

### Unit Tests: `test_plugin_download_manager.gd` — 28 tests

| Test | What it covers |
|------|---------------|
| `test_sha256_hex_known_value` | SHA-256 of empty input matches known hash (line 140) |
| `test_sha256_hex_hello_world` | SHA-256 of "hello world" matches known hash |
| `test_sha256_hex_deterministic` | Same input always produces same hash |
| `test_sha256_hex_different_inputs_differ` | Different inputs produce different hashes |
| `test_cache_dir_simple_ids` | Simple IDs produce `user://plugins/<server>/<plugin>` path (line 122) |
| `test_cache_dir_special_characters_encoded` | Special chars in IDs are URI-encoded (line 124) |
| `test_cache_dir_spaces_encoded` | Spaces in IDs are URI-encoded |
| `test_verify_signature_returns_false_when_no_sig_file` | No `plugin.sig` → returns false (line 192) |
| `test_verify_signature_returns_true_when_sig_exists` | **Security gap**: empty `plugin.sig` passes stub verification (line 200) |
| `test_is_cached_empty_hash_returns_false` | Empty expected_hash returns false (line 19) |
| `test_is_cached_no_hash_file_returns_false` | Missing `.bundle_hash` file returns false (line 23) |
| `test_is_cached_matching_hash_returns_true` | Matching stored hash returns true (line 26) |
| `test_is_cached_mismatched_hash_returns_false` | Mismatched hash returns false |
| `test_write_hash_file_creates_file` | `_write_hash_file` creates `.bundle_hash` with correct content (line 203) |
| `test_max_bundle_size_is_50mb` | MAX_BUNDLE_SIZE constant is 50 MB (line 8) |
| `test_server_id_for_conn_uses_space_id` | Connection with space_id uses it as server ID (line 130) |
| `test_server_id_for_conn_empty_space_id_falls_back` | Empty space_id falls back to "unknown" (line 137) |
| `test_extract_zip_creates_files` | Valid ZIP extracts files to dest dir (line 149) |
| `test_extract_zip_handles_subdirectories` | Nested directory entries created correctly (line 175) |
| `test_extract_zip_invalid_data_returns_false` | Non-ZIP data returns false (line 162) |
| `test_extract_zip_cleans_up_temp_file` | Temp `.tmp.zip` removed after extraction (line 188) |
| `test_extract_zip_overwrites_old_cache` | Old cache dir removed before extraction (line 168) |
| `test_extract_zip_path_traversal_not_sanitized` | **Security**: documents that `path_join("../")` is not sanitized (line 178) |
| `test_remove_dir_recursive_cleans_nested_dirs` | Recursively removes dirs and files (line 211) |
| `test_remove_dir_recursive_noop_for_nonexistent` | No crash on non-existent path |
| `test_clear_cache_removes_cached_dir` | `clear_cache` removes plugin cache directory (line 114) |
| `test_clear_cache_noop_for_uncached` | No crash for non-existent cache |
| `test_get_cache_dir_delegates_to_cache_dir` | Public accessor delegates to internal `_cache_dir` (line 30) |

### Unit Tests: `test_scripted_runtime.gd` — 42 tests

| Test | What it covers |
|------|---------------|
| `test_safe_libs_bitmask` | SAFE_LIBS excludes io, os, package, debug (line 15) |
| `test_max_sounds_constant` | MAX_SOUNDS is 16 (line 9) |
| `test_is_lua_error_null_returns_false` | `_is_lua_error(null)` returns false (line 295) |
| `test_is_lua_error_string_returns_false` | String is not a LuaError |
| `test_is_lua_error_int_returns_false` | Int is not a LuaError |
| `test_is_lua_error_dict_returns_false` | Dictionary is not a LuaError |
| `test_is_lua_error_node_returns_false` | Node is not a LuaError |
| `test_not_running_by_default` | `_running` is false on init |
| `test_process_disabled_by_default` | `_ready()` disables process (line 56) |
| `test_get_viewport_texture_null_when_no_viewport` | Returns null when _viewport is null (line 162) |
| `test_on_plugin_event_noop_when_not_running` | Early return when not running (line 155) |
| `test_forward_input_noop_when_not_running` | Early return when not running (line 177) |
| `test_lua_call_safe_null_fn_returns_null` | Null function returns null (line 257) |
| `test_lua_call_safe_null_fn_with_args_returns_null` | Null function with args returns null |
| `test_stop_noop_when_not_running` | stop() early return (line 133) |
| `test_cleanup_nulls_references` | `_cleanup()` nulls all cached Lua functions (line 655) |
| `test_session_context_defaults` | Default session_id, participants, local_user_id, local_role |
| `test_bridge_send_action_noop_when_no_client_plugins` | No crash with null _client_plugins (line 567) |
| `test_bridge_clear_timer_noop_for_unknown` | Unknown timer ID is a no-op (line 616) |
| `test_bridge_play_sound_noop_for_unknown` | Unknown sound handle is a no-op (line 641) |
| `test_bridge_stop_sound_noop_for_unknown` | Unknown sound handle is a no-op (line 647) |
| `test_max_action_payload_bytes_constant` | MAX_ACTION_PAYLOAD_BYTES is 8192 (line 10) |
| `test_max_collection_elements_constant` | MAX_COLLECTION_ELEMENTS is 200 (line 11) |
| `test_parse_flat_array_integers` | Integer values decoded correctly via `parse_flat_array` (line 216) |
| `test_parse_flat_array_floats` | Float values decoded with correct type |
| `test_parse_flat_array_booleans` | Boolean values `btrue`/`bfalse` decoded |
| `test_parse_flat_array_strings` | String values with `s` prefix decoded |
| `test_parse_flat_array_mixed_types` | Mixed int/float/bool/string in one array |
| `test_parse_flat_array_single_element` | Single-element array works |
| `test_parse_flat_array_string_that_looks_like_int` | Snowflake IDs stay as strings, not coerced to int |
| `test_parse_flat_array_board_serialization` | 100-cell board (10x10) serialization roundtrip |
| `test_parse_flat_dict_simple` | Key-value pairs with mixed types via `parse_flat_dict` (line 226) |
| `test_parse_flat_dict_with_booleans` | Boolean values in dict |
| `test_parse_flat_dict_empty_string` | Empty string returns empty dict |
| `test_parse_flat_dict_single_pair` | Single key-value pair |
| `test_parse_flat_dict_preserves_string_user_id` | String user IDs not coerced to int |
| `test_parse_typed_value_negative_int` | Negative integer via `_parse_typed_value` (line 239) |
| `test_parse_typed_value_zero` | Zero decoded as TYPE_INT |
| `test_parse_typed_value_negative_float` | Negative float decoded as TYPE_FLOAT |
| `test_parse_typed_value_plain_string` | String prefix `s` decoded correctly |
| `test_parse_typed_value_numeric_string_stays_string` | `s12345` stays string, not coerced |
| `test_bridge_send_action_rejects_oversized_payload` | Payloads exceeding 8KB emit `runtime_error` (line 567) |

### Unit Tests: `test_model_plugin_manifest.gd` — 5 tests

| Test | What it covers |
|------|---------------|
| `test_from_dict_full` | All 19 manifest fields deserialize correctly |
| `test_from_dict_minimal` | Empty dict produces sane defaults |
| `test_to_dict_roundtrip` | `from_dict → to_dict` preserves key fields |
| `test_canvas_size_from_separate_fields` | `canvas_width`/`canvas_height` fallback works |
| `test_enums_defined` | PluginRuntime, SessionState, ParticipantRole enums accessible |

### Integration Tests: `test_plugins_api.gd` — 10 tests

| Test | What it covers |
|------|---------------|
| `test_list_plugins` | GET `/spaces/:id/plugins` returns an array |
| `test_list_plugins_with_type_filter` | `?type=activity` filters correctly |
| `test_list_plugins_empty_type_filter` | `?type=bot` returns empty for activity-only seed |
| `test_seeded_plugin_manifest_fields` | Seeded plugin has correct name/runtime/type/version/max_participants/lobby |
| `test_create_and_delete_session` | POST/DELETE session lifecycle, verifies session fields |
| `test_session_state_transitions` | `lobby → running → ended` via PATCH |
| `test_assign_role` | Role assignment (player ↔ spectator) via POST `/roles` |
| `test_send_action` | Action dispatch in running state succeeds |
| `test_send_action_requires_running_state` | Action in lobby state fails |
| `test_invalid_state_transition` | `lobby → lobby` returns error |

**Total: 194 plugin-specific tests** (51 client_plugins + 31 canvas + 27 context + 28 download_manager + 42 scripted_runtime + 5 model + 10 integration)

## Signal Flow

```
                        ┌─────────────────────────────────────────────────┐
                        │              TESTED (unit)                      │
                        │                                                 │
  Gateway event ──────► │ ClientPlugins.on_plugin_installed/uninstalled   │
                        │ ClientPlugins.on_plugin_session_state           │
                        │ ClientPlugins.on_plugin_role_changed            │
                        │ ClientPlugins.on_plugin_event                   │
                        │ ClientPlugins._on_voice_left                    │
                        │ ClientPlugins._on_livekit_data_received         │
                        │ ClientPlugins._update_*_participants            │
                        │ ClientPlugins._extract_bundle                   │
                        │ ClientPlugins._is_plugin_trusted                │
                        │ ClientPlugins._clear_pending/active_activity    │
                        │ ClientPlugins.get_activity_viewport_texture     │
                        │ ClientPlugins.forward_activity_input            │
                        │ ClientPlugins.is_activity_host                  │
                        │ ClientPlugins.stop/start/assign/send guards     │
                        └──────────────────┬──────────────────────────────┘
                                           │
                        ┌──────────────────▼──────────────────────────────┐
                        │    TESTED (unit — pure logic only)              │
                        │                                                 │
                        │ PluginCanvas._parse_color, push_command limits  │
                        │ PluginCanvas buffer create/write/data/cleanup   │
                        │ PluginContext.get_role, is_host, get_participants│
                        │ PluginContext.send_action, send_data guards     │
                        │ PluginContext↔NativeRuntime file framing        │
                        │ NativeRuntime._handle_file_data edge cases      │
                        │ NativeRuntime.on_data_received routing          │
                        │ NativeRuntime.stop lifecycle, initial state     │
                        │ NativeRuntime.on_plugin_event/forward_input     │
                        │ ScriptedRuntime._is_lua_error, _lua_call_safe  │
                        │ ScriptedRuntime.stop/cleanup, constants         │
                        │ ScriptedRuntime.bridge no-op guards             │
                        │ ScriptedRuntime.parse_flat_array/dict (bulk)    │
                        │ ScriptedRuntime._parse_typed_value              │
                        │ ScriptedRuntime.payload size validation         │
                        │ PluginDownloadManager._sha256_hex               │
                        │ PluginDownloadManager.is_cached/_write_hash     │
                        │ PluginDownloadManager._verify_signature (stub)  │
                        │ PluginDownloadManager._cache_dir URI encoding   │
                        │ PluginDownloadManager._extract_zip              │
                        │ PluginDownloadManager.clear_cache               │
                        │ PluginDownloadManager._remove_dir_recursive     │
                        └──────────────────┬──────────────────────────────┘
                                           │
                        ┌──────────────────▼──────────────────────────────┐
                        │              NOT TESTED                         │
                        │                                                 │
                        │ ClientPlugins.launch_activity (network)         │
                        │ ClientPlugins.join_activity (network)           │
                        │ ClientPlugins.check_active_session (network)    │
                        │ ClientPlugins._on_voice_joined (network)        │
                        │ ClientPlugins._download_and_prepare_*_runtime   │
                        │ ClientPlugins._broadcast_activity_presence      │
                        │ ClientPlugins._show_trust_dialog (UI modal)     │
                        │ ClientPlugins._await_trust_signal (UI modal)    │
                        │ PluginDownloadManager.download_bundle (network) │
                        │ ScriptedRuntime.start (requires lua-gdextension)│
                        │ ScriptedRuntime._inject_bridge_api (requires    │
                        │   lua-gdextension)                              │
                        │ NativeRuntime.start (requires scene on disk)    │
                        └─────────────────────────────────────────────────┘
```

## Key Files

| File | Role | Tests |
|------|------|-------|
| `scripts/client/client_plugins.gd` | Plugin manager — caching, gateway, activity lifecycle, join/discover sessions, bundle extraction, trust | `tests/unit/test_client_plugins.gd` (51 tests; cache + gateway + routing + participants + bundle + trust + state + guards) |
| `scripts/helpers/plugin_download_manager.gd` | Bundle download, SHA-256 verification, ZIP extraction, cache | `tests/unit/test_plugin_download_manager.gd` (28 tests; hash, cache, signature stub, URI encoding, ZIP extraction, dir cleanup, path traversal) |
| `addons/accordkit/models/plugin_manifest.gd` | Typed manifest model (21 fields, 3 enums) | `tests/accordkit/unit/test_model_plugin_manifest.gd` (5 tests) |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST helpers (12 endpoints) | `tests/accordkit/integration/test_plugins_api.gd` (10 tests) |
| `scripts/plugins/scripted_runtime.gd` | Lua sandbox, SubViewport rendering, bridge API (30+ methods), bulk bridge parsing | `tests/unit/test_scripted_runtime.gd` (42 tests; constants, error checking, cleanup, guards, defaults, bulk bridge parsing, payload validation) |
| `scripts/plugins/native_runtime.gd` | Scene loader, teardown lifecycle, data channel routing | `tests/unit/test_plugin_context.gd` (16 tests; file framing, data routing, stop lifecycle, event/input guards) |
| `scripts/plugins/plugin_canvas.gd` | Draw command queue, image/buffer management, color parsing | `tests/unit/test_plugin_canvas.gd` (31 tests; color parsing, limits, buffers, clamping) |
| `scripts/plugins/plugin_context.gd` | Native plugin bridge (data channels, file transfer, role queries) | `tests/unit/test_plugin_context.gd` (11 tests; get_role, is_host, file framing roundtrip, send_action/send_data guards, defaults) |
| `scenes/plugins/plugin_trust_dialog.gd` | Trust confirmation for unsigned native plugins | **None** (61 lines, UI-only) |
| `scenes/plugins/activity_lobby.gd` | Lobby UI (player slots, spectators, start button, display name resolution) | **None** (109 lines, UI-only) |
| `scenes/plugins/activity_modal.gd` | Activity picker dialog | **None** (84 lines, UI-only) |
| `scenes/admin/plugin_management_dialog.gd` | Admin plugin list, upload, uninstall | **None** (291 lines, UI-only) |
| `addons/accordkit/gateway/gateway_intents.gd` | Gateway intent constants (includes `PLUGINS`) | `tests/accordkit/unit/test_intents.gd` |

## Implementation Status

- [x] Plugin manifest model — fully tested (deserialization, roundtrip, enums, defaults)
- [x] REST API endpoints — partially tested (list, filter, session CRUD, roles, actions, state transitions; `get_channel_sessions`, `leave_session`, `get_source`, `get_bundle`, `install_plugin` untested)
- [x] ClientPlugins cache — fully tested (get, install, uninstall, multi-connection isolation)
- [x] ClientPlugins gateway handlers — fully tested (install, uninstall, session_state, role_changed, plugin_event)
- [x] ClientPlugins data channel routing — tested (`_on_livekit_data_received` prefix stripping, mock runtime)
- [x] ClientPlugins participant updates — tested (`_update_scripted_participants`, `_update_context_participants`)
- [x] ClientPlugins uninstall cleanup — tested (uninstalling active plugin clears session + AppState)
- [x] Voice disconnect cleanup — tested (clears activity, emits signal)
- [x] ClientPlugins `_extract_bundle` — tested (valid ZIP, missing entry, modules, assets, invalid ZIP, default entry point)
- [x] ClientPlugins `_is_plugin_trusted` — tested (default false, trust-all, per-plugin trust via Config)
- [x] ClientPlugins state management — tested (`_clear_pending_activity`, `_clear_active_activity` reset all fields)
- [x] ClientPlugins delegation — tested (`get_activity_viewport_texture`, `forward_activity_input`, `is_activity_host`, `get_session_participants`)
- [x] ClientPlugins no-session guards — tested (`stop_activity`, `start_session`, `assign_role`, `send_action` early return)
- [x] PluginCanvas color parsing — fully tested (named, hex, array RGB/RGBA, Color passthrough, fallbacks)
- [x] PluginCanvas command limits — tested (MAX_COMMANDS_PER_FRAME boundary, clear)
- [x] PluginCanvas buffer management — tested (create, limits, clamp, pixel write, data replace, cleanup)
- [x] PluginContext identity helpers — tested (get_role, is_host, get_participants copy safety)
- [x] PluginContext communication guards — tested (send_action null client, send_data null adapter)
- [x] PluginContext↔NativeRuntime file framing — tested (roundtrip, empty name, empty data, unicode, truncation)
- [x] NativeRuntime data routing — tested (file vs non-file topic dispatch, null context safety)
- [x] NativeRuntime lifecycle — tested (stop clears state, event/input/viewport guards, initial state)
- [x] ScriptedRuntime pure logic — tested (constants, _is_lua_error, _lua_call_safe null, cleanup, stop, bridge guards)
- [x] ScriptedRuntime bulk bridge — tested (parse_flat_array, parse_flat_dict, _parse_typed_value — integers, floats, booleans, strings, mixed types, snowflake IDs, board serialization, negative values, empty input)
- [x] ScriptedRuntime payload validation — tested (send_action rejects payloads exceeding MAX_ACTION_PAYLOAD_BYTES, emits runtime_error)
- [x] PluginDownloadManager SHA-256 — tested (known hashes, determinism, uniqueness)
- [x] PluginDownloadManager cache checking — tested (is_cached match/mismatch/empty, _write_hash_file)
- [x] PluginDownloadManager signature stub — tested (documents the security gap: empty .sig passes)
- [x] PluginDownloadManager URI encoding — tested (cache dir path encoding)
- [x] PluginDownloadManager `_extract_zip` — tested (file creation, subdirectories, invalid data, temp cleanup, cache overwrite)
- [x] PluginDownloadManager `_remove_dir_recursive` — tested (nested cleanup, nonexistent no-op)
- [x] PluginDownloadManager `clear_cache` — tested (removes dir, nonexistent no-op)
- [x] ZIP path traversal — documented (test verifies path_join doesn't strip `../`)
- [ ] ClientPlugins `launch_activity` — 0 tests (requires network + scene tree)
- [ ] ClientPlugins `join_activity` — 0 tests (line 359; joins existing session as non-host, requires network)
- [ ] ClientPlugins `check_active_session` — 0 tests (line 515; discovers active sessions on voice join/reconnect via `get_channel_sessions`, requires network)
- [ ] ClientPlugins `_on_voice_joined` — 0 tests (line 714; triggers `check_active_session` on voice join)
- [ ] ClientPlugins `_broadcast_activity_presence` — 0 tests (line 747; sends presence updates across all connections, requires network)
- [ ] ClientPlugins `_download_and_prepare_*_runtime` — 0 tests (requires network)
- [ ] ClientPlugins `_show_trust_dialog` / `_await_trust_signal` — 0 tests (requires UI modal)
- [ ] PluginDownloadManager `download_bundle` — 0 tests (requires network)
- [ ] ScriptedRuntime `start` / `_inject_bridge_api` — 0 tests (requires lua-gdextension)
- [ ] NativeRuntime `start` — 0 tests (requires scene loading from bundle dir)
- [ ] PluginTrustDialog — 0 tests (62 lines, UI-only: trust_granted/denied signals, remember checkbox)
- [ ] ActivityLobby — 0 tests (109 lines, UI-only: slot rendering, participant updates, start button, display name resolution)
- [ ] ActivityModal — 0 tests (85 lines, UI-only: activity listing, type filtering, launch signal)
- [ ] PluginManagementDialog — 0 tests (292 lines, UI-only: plugin list, upload flow, uninstall)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| **ZIP path traversal — no sanitization** | Critical | `_extract_zip` (line 178) writes ZIP entries to `dest_dir.path_join(file_path)` without checking for `../` sequences. Now documented by `test_extract_zip_path_traversal_not_sanitized` which verifies `path_join` preserves `..` components. Same issue in `_extract_bundle` (line 217). |
| **ScriptedRuntime `start` / `_inject_bridge_api` untested** | High | Requires lua-gdextension. The Lua sandbox setup, bridge API injection (30+ bridge methods), and full lifecycle need the GDExtension present. Pure-logic methods (constants, error checking, guards, cleanup, bulk bridge parsing, payload validation) are now tested (42 tests). |
| **ClientPlugins `launch_activity` untested** | Medium | Lines 75–121: full orchestration (create session → set AppState → download → prepare runtime). Requires network + scene tree. |
| **ClientPlugins `join_activity` untested** | Medium | Lines 358–413: joins existing session as non-host player via `assign_role`, sets AppState, downloads runtime. Requires network. |
| **ClientPlugins `check_active_session` untested** | Medium | Lines 512–577: discovers active sessions in a voice channel on join/reconnect via `get_channel_sessions`. Auto-rejoins if already a participant, otherwise shows as pending. Requires network. |
| **ClientPlugins `_show_trust_dialog` / `_await_trust_signal` untested** | Medium | Lines 292–329: UI modal with trust_granted/denied signals and signal-waiting loop. Requires scene tree. `_is_plugin_trusted` is now tested separately. |
| **NativeRuntime `start` untested** | Medium | Scene loading from bundle dir requires a `.tscn` on disk. `stop()` lifecycle, event/input guards, and initial state are now tested. |
| **Ed25519 signature verification is a stub** | Medium | `PluginDownloadManager._verify_signature` (line 192) only checks if `plugin.sig` exists, always returns `true`. Documented by `test_verify_signature_returns_true_when_sig_exists`. |
| **5 REST endpoints untested** | Medium | `PluginsApi.get_source` (line 38), `get_bundle` (line 45), `install_plugin` (line 21), `get_channel_sessions` (line 51), and `leave_session` (line 87) have no integration tests. The latter two are new endpoints used by `check_active_session` and `stop_activity`/`_on_voice_left`. |
| **PluginDownloadManager `download_bundle` untested** | Medium | Lines 37–110: full download orchestration with hash validation. Requires network. |
| **PluginTrustDialog untested** | Low | 62 lines, UI-only. Signals `trust_granted(remember)` and `trust_denied` should be verified. |
| **ActivityLobby untested** | Low | 109 lines, UI-only. `update_participants` (line 44) enables start button based on player count. `_resolve_display_name` (line 99) resolves user names via Client cache. |
| **ActivityModal untested** | Low | 85 lines, UI-only. `_refresh_list` (line 56) filters to `type == "activity"` only. |
| **PluginManagementDialog untested** | Low | 292 lines, UI-only. `_extract_manifest` (line 220) parses plugin.json from a ZIP. |

## Coverage Summary

| Layer | Files | Lines (approx) | Tests | Coverage |
|-------|-------|----------------|-------|----------|
| AccordKit model | 1 | 97 | 5 | Good — all 21 fields, defaults, enums |
| AccordKit REST | 1 | 110 | 10 | Partial — 7 of 12 endpoints tested; `get_source`, `get_bundle`, `install_plugin`, `get_channel_sessions`, `leave_session` missing |
| ClientPlugins (cache + gateway + routing) | 1 | ~350 of 790 | 51 | Good — cache, gateway, data channel routing, participants, bundle extraction, trust, state mgmt, delegation, guards |
| ClientPlugins (network orchestration) | 1 | ~440 of 790 | 0 | **None** — launch_activity, join_activity, check_active_session, _on_voice_joined, _download_and_prepare_*_runtime, _show_trust_dialog, _broadcast_activity_presence (require network/UI) |
| PluginDownloadManager (pure logic + I/O) | 1 | ~180 of 225 | 28 | Good — hash, cache, signature stub, URI encoding, ZIP extraction, dir cleanup, path traversal doc |
| PluginDownloadManager (network) | 1 | ~45 of 225 | 0 | **None** — download_bundle (requires network) |
| PluginCanvas | 1 | 330 | 31 | Good — color parsing, command limits, buffer lifecycle, clamping |
| PluginContext | 1 | 92 | 11 | Good — identity helpers, file framing roundtrip, communication guards, defaults |
| NativeRuntime | 1 | 118 | 16 | Good — file protocol, data routing, stop lifecycle, event/input/viewport guards, initial state |
| ScriptedRuntime | 1 | 667 | 42 | Good — constants, error checking, cleanup, stop, guards, bulk bridge parsing (parse_flat_array/dict, _parse_typed_value), payload size validation tested; start/bridge API require lua-gdextension |
| UI (4 files) | 4 | ~545 | 0 | **None** — trust dialog, lobby, modal, admin dialogs (UI-only, would need scene tree) |

**Overall: ~65% of plugin system lines have test coverage. The tested surface covers ClientPlugins cache/gateway/routing/bundle/trust/state/delegation/guards (51 tests), PluginDownloadManager pure logic/ZIP extraction (28 tests), ScriptedRuntime pure logic + bulk bridge parsing + payload validation (42 tests), NativeRuntime lifecycle/guards (16 tests), PluginContext identity/framing/guards (11 tests). Since last audit, ScriptedRuntime gained bulk bridge protocol (parse_flat_array, parse_flat_dict, _parse_typed_value — all tested), payload size limits (MAX_ACTION_PAYLOAD_BYTES=8KB, MAX_COLLECTION_ELEMENTS=200 — tested), and runtime_error signal. ClientPlugins gained `_broadcast_activity_presence` (line 747) for updating activity status across all connections. ActivityLobby gained `_resolve_display_name` (line 99) for resolving user display names via Client cache. GatewayIntents added `PLUGINS` intent (line 14). Remaining untested code is network orchestration (launch/join/check_active_session/broadcast_presence), session discovery, and UI dialogs.**

## Security Audit

### Vulnerability Assessment

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| **ZIP path traversal — no sanitization** | **Critical** | `plugin_download_manager.gd:171-184` | `_extract_zip` iterates `reader.get_files()` and writes to `dest_dir.path_join(file_path)` without checking for `../` sequences. A malicious ZIP with entries like `../../.config/autostart/malware.desktop` would write outside the cache directory. Godot's `path_join()` does NOT strip `..` components. Same issue in `client_plugins.gd:207-213` (`_extract_bundle`) — file paths from the ZIP are used as-is for module names and asset keys, though those stay in-memory rather than touching disk. |
| **ZIP path traversal — scripted bundle** | **High** | `client_plugins.gd:189-191` | The `entry_point` field comes from the server-supplied manifest (line 189). A manifest with `entry_point: "../../some/path.lua"` would attempt to read that path from the ZIP (unlikely to succeed, but the intent is unvalidated). |
| **Ed25519 signature verification is a stub** | **Critical** | `plugin_download_manager.gd:191-199` | `_verify_signature` checks only whether `plugin.sig` exists, then returns `true`. **Now documented by test** `test_verify_signature_returns_true_when_sig_exists` which asserts this gap. Any attacker can include an empty `plugin.sig` in a bundle and it passes "verification." |
| **Trust-all grants permanent server-wide bypass** | **High** | `client_plugins.gd:305`, `config.gd:694-698` | When a user checks "Always trust plugins from this server," `Config.set_plugin_trust_all(server_id, true)` is set. All future native plugins from that server run without any prompt — even new, different plugins uploaded later by a compromised admin. There is no UI to review or revoke trust-all, and no expiry. |
| **No trust revocation UI** | **High** | `config.gd:681-698` | Trust settings are persisted in the encrypted config (`plugin_trust_<server_id>` section) but there is no settings page or dialog to view, revoke, or reset plugin trust. Users who granted trust cannot undo it without manually editing config files. |
| **No HTTPS enforcement for plugin downloads** | **High** | `accord_config.gd:5-7`, `accord_rest.gd:47` | `DEFAULT_BASE_URL` is `http://localhost:3000`. The REST client appends paths to whatever `base_url` is configured — if a user connects to an HTTP server, all plugin source/bundle downloads happen over plaintext. A network attacker (MITM) could replace the bundle with malicious code. The SHA-256 hash check (line 75-81 in `plugin_download_manager.gd`) mitigates this only if the manifest was delivered securely, but the manifest itself is fetched over the same potentially-insecure connection. |
| **No file size limit on plugin upload** | **Medium** | `plugin_management_dialog.gd:189-242` | `_on_file_selected` reads the entire file into memory (`file.get_buffer(file.get_length())`) with no size check. Downloads enforce `MAX_BUNDLE_SIZE = 50 MB` (line 8 in `plugin_download_manager.gd`), but uploads don't. A local admin could accidentally upload a multi-GB file, causing an OOM crash. |
| **Temp file race condition** | **Medium** | `client_plugins.gd:176`, `plugin_download_manager.gd:150` | Both ZIP extraction paths use fixed temp file names (`user://tmp_plugin_bundle.zip` and `dest_dir + ".tmp.zip"`). If two plugins launch concurrently, they overwrite each other's temp files. The scripted runtime path is worse — all scripted plugins share the same `user://tmp_plugin_bundle.zip`. |
| **BBCode injection in trust dialog** | **Medium** | `plugin_trust_dialog.gd:27-32` | The trust dialog uses `RichTextLabel` with `bbcode_enabled = true` and interpolates `plugin_name` and `server_name` directly: `"[b]%s[/b] is a native plugin from [b]%s[/b]."`. A server admin could set a plugin name containing BBCode tags (e.g., `[url=http://evil.com]Click here[/url]` or `[color=transparent]invisible text[/color]`) to mislead users about what they're trusting. |
| **Module name collision** | **Low** | `client_plugins.gd:209` | Module names are derived via `file_path.get_file().get_basename()` — just the filename without extension. Two Lua files at different paths (e.g., `src/utils.lua` and `lib/utils.lua`) would collide; the last one wins. This is a correctness bug that could be exploited if a plugin ships a malicious module that shadows a legitimate one. |
| **No manifest schema validation on upload** | **Medium** | `plugin_management_dialog.gd:245-276` | `_extract_manifest` only checks that `plugin.json` exists and parses as valid JSON. No validation of required fields (`id`, `name`, `runtime`, `type`), field types, or value ranges. A manifest with `runtime: "native"` and `signed: true` would be accepted and later bypass the trust dialog (since `_verify_signature` is a stub that returns `true` if plugin.sig exists). |
| **Lua `load()` available in sandbox** | **Low** | `scripted_runtime.gd:450` | The custom `require()` uses Lua's `load()` to compile module source. Since `LUA_BASE` is enabled, `load()` (and `loadstring()` in Lua 5.1) is available to plugin code, allowing runtime code generation from strings. This is standard for Lua sandboxes but worth noting — a plugin can construct and execute arbitrary Lua at runtime, making static analysis of plugin behavior impossible. |
| **No CPU exhaustion limits for Lua** | **Medium** | `scripted_runtime.gd` | There is no CPU instruction count limit or execution timeout for Lua code. A malicious or buggy `_draw()` function runs every frame with no interrupt. An infinite loop in `_ready()` or `_on_event()` would freeze the main thread. Timer callbacks (`set_interval` at minimum 16ms) can accumulate. `MAX_SOUNDS = 16`, canvas limits, `MAX_ACTION_PAYLOAD_BYTES = 8192`, and `MAX_COLLECTION_ELEMENTS = 200` help bound memory/network, but CPU is unbounded. |
| **Native plugins get full Godot API access** | **By design** | `native_runtime.gd:48` | Native plugin scenes are instantiated with `scene.instantiate()` and added to the tree. They inherit full access to the scene tree, autoloads (Client, Config, AppState), filesystem, and network. This is documented and gated by the trust dialog, but a trusted native plugin could exfiltrate auth tokens from `Config`, send messages as the user via `Client`, or access local files. |
| **Data channel topic spoofing within a plugin** | **Low** | `plugin_context.gd:42`, `client_plugins.gd:341-344` | The data channel topic prefix is `plugin:<id>:`. `_on_livekit_data_received` (line 341) strips this prefix before forwarding. A malicious participant in the LiveKit room could send data with an arbitrary `plugin:<id>:` prefix targeting a different plugin's topic namespace. Cross-plugin isolation depends on LiveKit room membership, not cryptographic channel separation. |

### What's Properly Protected

| Control | Status | Location | Tested? |
|---------|--------|----------|---------|
| Lua sandbox — dangerous libs blocked | OK | `scripted_runtime.gd:13` — io, os, package, debug, ffi excluded via bitmask | **Yes** (bitmask verified) |
| Lua `require()` restricted to bundle | OK | `scripted_runtime.gd:441-458` — only loads from `_modules` dict, no filesystem | No |
| Canvas coordinate clamping | OK | `plugin_canvas.gd:205-209` — all coords clamped to canvas bounds | **Yes** |
| Canvas resource limits | OK | `plugin_canvas.gd:7-9` — MAX_IMAGES=64, MAX_BUFFERS=4, MAX_COMMANDS=4096 | **Yes** |
| Canvas size bounds | OK | `scripted_runtime.gd:66-73` — width 64-1920, height 64-1080 | No |
| Sound limit | OK | `scripted_runtime.gd:9` — MAX_SOUNDS=16 | **Yes** (constant check) |
| Action payload size limit | OK | `scripted_runtime.gd:10` — MAX_ACTION_PAYLOAD_BYTES=8192 | **Yes** (oversized payload rejected, runtime_error emitted) |
| Collection element limit | OK | `scripted_runtime.gd:11` — MAX_COLLECTION_ELEMENTS=200, enforced in Lua Dictionary()/Array() | **Yes** (constant check) |
| Bundle size limit (download) | OK | `plugin_download_manager.gd:8` — 50 MB max | **Yes** (constant check) |
| SHA-256 hash verification | OK | `plugin_download_manager.gd:75-81` — rejects hash mismatch | **Yes** |
| Cache directory URI encoding | OK | `plugin_download_manager.gd:123-125` — server_id and plugin_id URI-encoded | **Yes** |
| Data channel namespacing | OK | `plugin_context.gd:42` — `plugin:<id>:` prefix isolates topics | **Yes** |
| Data channel prefix stripping | OK | `client_plugins.gd:341-344` — strips prefix, routes to runtime | **Yes** |
| Plugin isolation per connection | OK | `client_plugins.gd:10` — `_plugin_cache[conn_index]` separates servers | **Yes** |
| Trust gating before native execution | OK | `client_plugins.gd:243-256` — unsigned natives require explicit user consent via `_show_trust_dialog` / `_await_trust_signal` | **Yes** (`_is_plugin_trusted` tested; dialog flow untested) |
| Voice disconnect cleanup | OK | `client_plugins.gd:718-733` — leaving voice clears activity state and notifies server via `leave_session` | **Yes** (local cleanup tested; `leave_session` call untested) |
| LiveKit data channel disconnect | OK | `client_plugins.gd:752-756` — `_clear_active_activity` disconnects handler | **Yes** |
| File framing protocol consistency | OK | `plugin_context.gd:51-62` ↔ `native_runtime.gd:108-118` — roundtrip tested | **Yes** |

### Security Test Gaps (Priority Order)

| # | Test Needed | Why |
|---|-------------|-----|
| 1 | ~~**ZIP path traversal in `_extract_zip`**~~ | **Documented** — `test_extract_zip_path_traversal_not_sanitized` verifies that `path_join` preserves `..` components. Fix needed: sanitize paths before writing. |
| 2 | **ZIP path traversal in `_extract_bundle`** | Same attack via scripted plugin bundle entry_point containing `../`. Entry point comes from server manifest (line 189). |
| 3 | ~~**Trust-all persists across new plugins**~~ | **Tested** — `test_is_plugin_trusted_trust_all` verifies that trust-all returns true for any plugin ID. The gap (no revocation UI) is architectural, not a test gap. |
| 4 | ~~**Signature stub accepts any plugin.sig**~~ | **Done** — `test_verify_signature_returns_true_when_sig_exists` documents this gap. |
| 5 | **BBCode injection in trust dialog** | Set plugin name to `[url]http://evil[/url]`, verify it renders literally (not as a link). Requires scene tree. |
| 6 | **Concurrent temp file race** | Launch two scripted plugins simultaneously, verify they don't corrupt each other's `user://tmp_plugin_bundle.zip`. |
| 7 | **Lua CPU exhaustion** | Run `while true do end` in `_ready()`, verify it doesn't permanently freeze the client (currently it will). Requires lua-gdextension. |
| 8 | **Manifest field injection on upload** | Upload a manifest with `signed: true` + fake `plugin.sig`, verify the server or client rejects it. |
| 9 | **HTTP downgrade for plugin download** | Connect to HTTP server, download plugin, verify hash check catches MITM replacement (it should — but test it). |
| 10 | **Module name collision** | Bundle two `.lua` files with the same basename at different paths, verify correct one loads. `_extract_bundle` uses `get_file().get_basename()` (line 217) — last one wins. |

## Recommended Next Test Priorities

1. **Fix ZIP path traversal** (Critical) — add `../` sanitization in `_extract_zip` and `_extract_bundle`, then update `test_extract_zip_path_traversal_not_sanitized` to assert rejection
2. **BBCode escaping in trust dialog** — verify plugin names can't inject formatting (requires scene tree)
3. **`join_activity` / `check_active_session` guards** — test early-return paths (empty IDs, bad conn_index, already-active session) without network; the pure guard logic at the top of each method can be unit tested
4. **REST endpoint coverage** — add integration tests for `get_channel_sessions`, `leave_session`, `get_source`, `get_bundle`, `install_plugin`
5. **NativeRuntime.start** — create a mock `.tscn` scene on disk, verify scene loading and `setup(context)` call
6. **ScriptedRuntime bridge API** — requires lua-gdextension; test bridge callback closures in isolation (bulk bridge parsing is now fully tested without lua-gdextension)
7. **PluginDownloadManager.download_bundle** — integration test with mock REST responses
8. **Module name collision** — `_extract_bundle` test with two `.lua` files sharing the same basename
9. **`_broadcast_activity_presence` guards** — test early-return for empty connections list, null clients
