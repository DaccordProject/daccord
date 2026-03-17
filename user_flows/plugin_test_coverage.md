# Plugin System Test Coverage

## Overview

Audit of test coverage for the server plugins system. The plugin system spans 13 source files (~2,400 lines) across AccordKit models, REST endpoints, autoload managers, runtimes, and UI components. Current tests cover the data model, REST API, ClientPlugins gateway/routing logic, PluginDownloadManager pure logic, PluginCanvas color parsing/limits/buffers, PluginContext identity helpers, and NativeRuntime file framing protocol. Remaining gaps are in the runtimes (Lua sandbox, scene loading), UI dialogs, and orchestration methods requiring network.

## Test Inventory

### Unit Tests: `test_client_plugins.gd` — 28 tests

| Test | What it covers |
|------|---------------|
| `test_get_plugins_empty_by_default` | Empty cache returns `[]` |
| `test_get_plugin_returns_empty_when_not_found` | Unknown plugin returns `{}` |
| `test_get_conn_index_for_plugin_not_found` | Unknown plugin returns `-1` |
| `test_on_plugin_installed_adds_to_cache` | Gateway install populates cache (line 56) |
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
| `test_livekit_data_strips_prefix_and_routes` | `_on_livekit_data_received` strips `plugin:<id>:` prefix and forwards to mock runtime (line 333) |
| `test_livekit_data_ignores_wrong_plugin_prefix` | Data with mismatched plugin prefix is dropped |
| `test_livekit_data_ignores_when_no_runtime` | No crash when `_active_runtime` is null |
| `test_livekit_data_ignores_non_plugin_topic` | Non-`plugin:` topics are ignored |
| `test_on_plugin_event_forwards_to_runtime` | `on_plugin_event` forwards event_type + data to runtime (line 456) |
| `test_on_plugin_event_noop_when_no_runtime` | No crash when no active runtime |
| `test_update_scripted_participants_updates_existing` | Role update for existing participant in scripted runtime (line 501) |
| `test_update_scripted_participants_adds_new` | New participant appended to scripted runtime list |
| `test_update_context_participants_updates_existing` | Role update for existing participant in PluginContext (line 511) |
| `test_update_context_participants_adds_new` | New participant appended to PluginContext list |
| `test_uninstall_active_plugin_clears_activity` | Uninstalling the active plugin clears session + AppState and emits `activity_ended` |

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

### Unit Tests: `test_plugin_context.gd` — 17 tests

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

### Unit Tests: `test_plugin_download_manager.gd` — 17 tests

| Test | What it covers |
|------|---------------|
| `test_sha256_hex_known_value` | SHA-256 of empty input matches known hash (line 140) |
| `test_sha256_hex_hello_world` | SHA-256 of "hello world" matches known hash |
| `test_sha256_hex_deterministic` | Same input always produces same hash |
| `test_sha256_hex_different_inputs_differ` | Different inputs produce different hashes |
| `test_cache_dir_simple_ids` | Simple IDs produce `user://plugins/<server>/<plugin>` path (line 122) |
| `test_cache_dir_special_characters_encoded` | Special chars in IDs are URI-encoded (line 124) |
| `test_cache_dir_spaces_encoded` | Spaces in IDs are URI-encoded |
| `test_verify_signature_returns_false_when_no_sig_file` | No `plugin.sig` → returns false (line 193) |
| `test_verify_signature_returns_true_when_sig_exists` | **Security gap**: empty `plugin.sig` passes stub verification (line 199) |
| `test_is_cached_empty_hash_returns_false` | Empty expected_hash returns false (line 20) |
| `test_is_cached_no_hash_file_returns_false` | Missing `.bundle_hash` file returns false (line 23) |
| `test_is_cached_matching_hash_returns_true` | Matching stored hash returns true (line 26) |
| `test_is_cached_mismatched_hash_returns_false` | Mismatched hash returns false |
| `test_write_hash_file_creates_file` | `_write_hash_file` creates `.bundle_hash` with correct content (line 202) |
| `test_max_bundle_size_is_50mb` | MAX_BUNDLE_SIZE constant is 50 MB (line 8) |
| `test_server_id_for_conn_uses_space_id` | Connection with space_id uses it as server ID (line 130) |
| `test_server_id_for_conn_empty_space_id_falls_back` | Empty space_id falls back to "unknown" (line 137) |

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

**Total: 108 plugin-specific tests** (28 client_plugins + 31 canvas + 17 context + 17 download_manager + 5 model + 10 integration)

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
                        └──────────────────┬──────────────────────────────┘
                                           │
                        ┌──────────────────▼──────────────────────────────┐
                        │    TESTED (unit — pure logic only)              │
                        │                                                 │
                        │ PluginCanvas._parse_color, push_command limits  │
                        │ PluginCanvas buffer create/write/data/cleanup   │
                        │ PluginContext.get_role, is_host, get_participants│
                        │ PluginContext↔NativeRuntime file framing        │
                        │ NativeRuntime._handle_file_data edge cases      │
                        │ NativeRuntime.on_data_received routing          │
                        │ PluginDownloadManager._sha256_hex               │
                        │ PluginDownloadManager.is_cached/_write_hash     │
                        │ PluginDownloadManager._verify_signature (stub)  │
                        │ PluginDownloadManager._cache_dir URI encoding   │
                        └──────────────────┬──────────────────────────────┘
                                           │
                        ┌──────────────────▼──────────────────────────────┐
                        │              NOT TESTED                         │
                        │                                                 │
                        │ ClientPlugins.launch_activity                   │
                        │ ClientPlugins.stop_activity                     │
                        │ ClientPlugins.start_session                     │
                        │ ClientPlugins.assign_role                       │
                        │ ClientPlugins.send_action                       │
                        │ ClientPlugins.forward_activity_input            │
                        │ ClientPlugins.get_activity_viewport_texture     │
                        │ ClientPlugins._download_and_prepare_*_runtime   │
                        │ ClientPlugins._extract_bundle                   │
                        │ ClientPlugins._show_trust_dialog                │
                        │ ClientPlugins._is_plugin_trusted                │
                        │ PluginDownloadManager.download_bundle           │
                        │ PluginDownloadManager._extract_zip              │
                        │ ScriptedRuntime (all)                           │
                        │ NativeRuntime.start/stop (scene loading)        │
                        └─────────────────────────────────────────────────┘
```

## Key Files

| File | Role | Tests |
|------|------|-------|
| `scripts/autoload/client_plugins.gd` | Plugin manager — caching, gateway, activity lifecycle | `tests/unit/test_client_plugins.gd` (28 tests; cache + gateway + routing + participants) |
| `scripts/autoload/plugin_download_manager.gd` | Bundle download, SHA-256 verification, ZIP extraction, cache | `tests/unit/test_plugin_download_manager.gd` (17 tests; hash, cache, signature stub, URI encoding) |
| `addons/accordkit/models/plugin_manifest.gd` | Typed manifest model (19 fields, 3 enums) | `tests/accordkit/unit/test_model_plugin_manifest.gd` (5 tests) |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST helpers (9 endpoints) | `tests/accordkit/integration/test_plugins_api.gd` (10 tests) |
| `scenes/plugins/scripted_runtime.gd` | Lua sandbox, SubViewport rendering, bridge API (30+ methods) | **None** |
| `scenes/plugins/native_runtime.gd` | Scene loader, teardown lifecycle, data channel routing | `tests/unit/test_plugin_context.gd` (6 tests; file framing, data routing, edge cases) |
| `scenes/plugins/plugin_canvas.gd` | Draw command queue, image/buffer management, color parsing | `tests/unit/test_plugin_canvas.gd` (31 tests; color parsing, limits, buffers, clamping) |
| `scenes/plugins/plugin_context.gd` | Native plugin bridge (data channels, file transfer, role queries) | `tests/unit/test_plugin_context.gd` (11 tests; get_role, is_host, file framing roundtrip) |
| `scenes/plugins/plugin_trust_dialog.gd` | Trust confirmation for unsigned native plugins | **None** |
| `scenes/plugins/activity_lobby.gd` | Lobby UI (player slots, spectators, start button) | **None** |
| `scenes/plugins/activity_modal.gd` | Activity picker dialog | **None** |
| `scenes/admin/plugin_management_dialog.gd` | Admin plugin list, upload, uninstall | **None** |

## Implementation Status

- [x] Plugin manifest model — fully tested (deserialization, roundtrip, enums, defaults)
- [x] REST API endpoints — fully tested (list, filter, session CRUD, roles, actions, state transitions)
- [x] ClientPlugins cache — fully tested (get, install, uninstall, multi-connection isolation)
- [x] ClientPlugins gateway handlers — fully tested (install, uninstall, session_state, role_changed, plugin_event)
- [x] ClientPlugins data channel routing — tested (`_on_livekit_data_received` prefix stripping, mock runtime)
- [x] ClientPlugins participant updates — tested (`_update_scripted_participants`, `_update_context_participants`)
- [x] ClientPlugins uninstall cleanup — tested (uninstalling active plugin clears session + AppState)
- [x] Voice disconnect cleanup — tested (clears activity, emits signal)
- [x] PluginCanvas color parsing — fully tested (named, hex, array RGB/RGBA, Color passthrough, fallbacks)
- [x] PluginCanvas command limits — tested (MAX_COMMANDS_PER_FRAME boundary, clear)
- [x] PluginCanvas buffer management — tested (create, limits, clamp, pixel write, data replace, cleanup)
- [x] PluginContext identity helpers — tested (get_role, is_host, get_participants copy safety)
- [x] PluginContext↔NativeRuntime file framing — tested (roundtrip, empty name, empty data, unicode, truncation)
- [x] NativeRuntime data routing — tested (file vs non-file topic dispatch, null context safety)
- [x] PluginDownloadManager SHA-256 — tested (known hashes, determinism, uniqueness)
- [x] PluginDownloadManager cache checking — tested (is_cached match/mismatch/empty, _write_hash_file)
- [x] PluginDownloadManager signature stub — tested (documents the security gap: empty .sig passes)
- [x] PluginDownloadManager URI encoding — tested (cache dir path encoding)
- [ ] ClientPlugins `launch_activity` — 0 tests
- [ ] ClientPlugins `stop_activity` — 0 tests
- [ ] ClientPlugins `start_session` / `assign_role` / `send_action` — 0 tests
- [ ] ClientPlugins `_extract_bundle` — 0 tests
- [ ] ClientPlugins trust checking (`_is_plugin_trusted`, `_show_trust_dialog`) — 0 tests
- [ ] PluginDownloadManager `download_bundle` — 0 tests (requires network)
- [ ] PluginDownloadManager `_extract_zip` — 0 tests (requires filesystem)
- [ ] ScriptedRuntime — 0 tests (Lua sandbox, bridge API, lifecycle, timers, audio, input forwarding)
- [ ] NativeRuntime `start`/`stop` — 0 tests (requires scene loading from bundle dir)
- [ ] PluginTrustDialog — 0 tests (trust_granted/denied signals, remember checkbox)
- [ ] ActivityLobby — 0 tests (slot rendering, participant updates, start button enable/disable)
- [ ] ActivityModal — 0 tests (activity listing, type filtering, launch signal)
- [ ] PluginManagementDialog — 0 tests (plugin list rendering, upload flow, uninstall confirmation)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| **PluginDownloadManager `_extract_zip` untested** | High | `_extract_zip` (line 148) writes ZIP entries to `dest_dir.path_join(file_path)` without checking for `../` sequences — ZIP path traversal vulnerability. The pure-logic helpers (`_sha256_hex`, `is_cached`, `_write_hash_file`, `_verify_signature`, `_cache_dir`) are now tested, but the actual extraction and download flow remain untested. |
| **ScriptedRuntime has no tests** | High | 565 lines, 0 tests. The Lua sandbox (`SAFE_LIBS` bitmask, line 13), bridge API injection (lines 260–467), lifecycle functions (`start`/`stop`), timer management, and audio handling are all untested. Requires lua-gdextension GDExtension to be present. |
| **ClientPlugins `_extract_bundle` untested** | Medium | Lines 174–219: ZIP reading, entry point resolution, module/asset extraction. Pure logic once you provide a PackedByteArray of a valid ZIP. Testable by constructing a small in-memory ZIP. |
| **ClientPlugins `launch_activity` untested** | Medium | Lines 71–113: the full orchestration (create session → set AppState → download → prepare runtime) has no test. Hard to unit-test due to network + scene tree requirements. |
| **Plugin trust flow untested** | Medium | `_is_plugin_trusted` (line 325) checks Config; `_show_trust_dialog` (line 284) awaits user response. Trust decisions are security-sensitive — a regression could auto-trust or always-deny. `_is_plugin_trusted` is testable by mocking Config. |
| **NativeRuntime `start`/`stop` untested** | Medium | Scene loading from bundle dir and teardown lifecycle require a mock scene on disk. |
| **Ed25519 signature verification is a stub** | Medium | `PluginDownloadManager._verify_signature` (line 191) only checks if `plugin.sig` exists, always returns `true`. Now documented by `test_verify_signature_returns_true_when_sig_exists` which asserts the gap. |
| **`get_source`/`get_bundle` REST endpoints untested** | Medium | `PluginsApi.get_source` (line 38) and `get_bundle` (line 45) return raw `PackedByteArray` — no integration test verifies binary download. `install_plugin` multipart upload (line 21) is also untested. |
| **PluginTrustDialog untested** | Low | 84 lines. Signals `trust_granted(remember)` and `trust_denied` should be verified. The `_remember_check` checkbox state should propagate correctly. |
| **ActivityLobby untested** | Low | 135 lines. `update_participants` (line 79) enables start button based on player count — testable by feeding mock participant arrays. |
| **ActivityModal untested** | Low | 162 lines. `_refresh_list` (line 54) filters to `type == "activity"` only — should verify bot/theme/command plugins are excluded. |
| **PluginManagementDialog untested** | Low | 316 lines. `_extract_manifest` (line 245) parses plugin.json from a ZIP — testable with fixture ZIPs. |

## Coverage Summary

| Layer | Files | Lines (approx) | Tests | Coverage |
|-------|-------|----------------|-------|----------|
| AccordKit model | 1 | 97 | 5 | Good — all fields, defaults, enums |
| AccordKit REST | 1 | 94 | 10 | Good — 6 of 9 endpoints tested; `get_source`, `get_bundle`, `install_plugin` missing |
| ClientPlugins (cache + gateway + routing) | 1 | ~250 of 554 | 28 | Good — cache, gateway, data channel routing, participant updates, uninstall cleanup |
| ClientPlugins (activity lifecycle) | 1 | ~300 of 554 | 0 | **None** — launch, stop, bundle extraction, trust flow |
| PluginDownloadManager (pure logic) | 1 | ~80 of 225 | 17 | Good — hash, cache check, signature stub, URI encoding, server ID |
| PluginDownloadManager (I/O) | 1 | ~145 of 225 | 0 | **None** — download_bundle, _extract_zip |
| PluginCanvas | 1 | 331 | 31 | Good — color parsing, command limits, buffer lifecycle, clamping |
| PluginContext | 1 | 93 | 11 | Good — identity helpers, file framing roundtrip |
| NativeRuntime | 1 | 119 | 6 | Partial — file protocol parsing + data routing tested; scene start/stop untested |
| ScriptedRuntime | 1 | 565 | 0 | **None** — Lua sandbox, bridge API, timers, audio |
| UI (4 files) | 4 | ~700 | 0 | **None** — trust, lobby, modal, admin dialogs |

**Overall: ~45% of plugin system lines now have test coverage (up from ~28%). The newly tested areas are PluginCanvas (color/limits/buffers), PluginDownloadManager (hash/cache/signature), PluginContext (identity/framing), NativeRuntime (file protocol/routing), and ClientPlugins (data channel routing/participants/event forwarding).**

## Security Audit

### Vulnerability Assessment

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| **ZIP path traversal — no sanitization** | **Critical** | `plugin_download_manager.gd:171-184` | `_extract_zip` iterates `reader.get_files()` and writes to `dest_dir.path_join(file_path)` without checking for `../` sequences. A malicious ZIP with entries like `../../.config/autostart/malware.desktop` would write outside the cache directory. Godot's `path_join()` does NOT strip `..` components. Same issue in `client_plugins.gd:208-214` (`_extract_bundle`) — file paths from the ZIP are used as-is for module names and asset keys, though those stay in-memory rather than touching disk. |
| **ZIP path traversal — scripted bundle** | **High** | `client_plugins.gd:190-192` | The `entry_point` field comes from the server-supplied manifest (line 190). A manifest with `entry_point: "../../some/path.lua"` would attempt to read that path from the ZIP (unlikely to succeed, but the intent is unvalidated). |
| **Ed25519 signature verification is a stub** | **Critical** | `plugin_download_manager.gd:191-199` | `_verify_signature` checks only whether `plugin.sig` exists, then returns `true`. **Now documented by test** `test_verify_signature_returns_true_when_sig_exists` which asserts this gap. Any attacker can include an empty `plugin.sig` in a bundle and it passes "verification." |
| **Trust-all grants permanent server-wide bypass** | **High** | `client_plugins.gd:297`, `config.gd:694-698` | When a user checks "Always trust plugins from this server," `Config.set_plugin_trust_all(server_id, true)` is set. All future native plugins from that server run without any prompt — even new, different plugins uploaded later by a compromised admin. There is no UI to review or revoke trust-all, and no expiry. |
| **No trust revocation UI** | **High** | `config.gd:681-698` | Trust settings are persisted in the encrypted config (`plugin_trust_<server_id>` section) but there is no settings page or dialog to view, revoke, or reset plugin trust. Users who granted trust cannot undo it without manually editing config files. |
| **No HTTPS enforcement for plugin downloads** | **High** | `accord_config.gd:5-7`, `accord_rest.gd:47` | `DEFAULT_BASE_URL` is `http://localhost:3000`. The REST client appends paths to whatever `base_url` is configured — if a user connects to an HTTP server, all plugin source/bundle downloads happen over plaintext. A network attacker (MITM) could replace the bundle with malicious code. The SHA-256 hash check (line 75-81 in `plugin_download_manager.gd`) mitigates this only if the manifest was delivered securely, but the manifest itself is fetched over the same potentially-insecure connection. |
| **No file size limit on plugin upload** | **Medium** | `plugin_management_dialog.gd:189-242` | `_on_file_selected` reads the entire file into memory (`file.get_buffer(file.get_length())`) with no size check. Downloads enforce `MAX_BUNDLE_SIZE = 50 MB` (line 8 in `plugin_download_manager.gd`), but uploads don't. A local admin could accidentally upload a multi-GB file, causing an OOM crash. |
| **Temp file race condition** | **Medium** | `client_plugins.gd:177`, `plugin_download_manager.gd:150` | Both ZIP extraction paths use fixed temp file names (`user://tmp_plugin_bundle.zip` and `dest_dir + ".tmp.zip"`). If two plugins launch concurrently, they overwrite each other's temp files. The scripted runtime path is worse — all scripted plugins share the same `user://tmp_plugin_bundle.zip`. |
| **BBCode injection in trust dialog** | **Medium** | `plugin_trust_dialog.gd:27-32` | The trust dialog uses `RichTextLabel` with `bbcode_enabled = true` and interpolates `plugin_name` and `server_name` directly: `"[b]%s[/b] is a native plugin from [b]%s[/b]."`. A server admin could set a plugin name containing BBCode tags (e.g., `[url=http://evil.com]Click here[/url]` or `[color=transparent]invisible text[/color]`) to mislead users about what they're trusting. |
| **Module name collision** | **Low** | `client_plugins.gd:210` | Module names are derived via `file_path.get_file().get_basename()` — just the filename without extension. Two Lua files at different paths (e.g., `src/utils.lua` and `lib/utils.lua`) would collide; the last one wins. This is a correctness bug that could be exploited if a plugin ships a malicious module that shadows a legitimate one. |
| **No manifest schema validation on upload** | **Medium** | `plugin_management_dialog.gd:245-276` | `_extract_manifest` only checks that `plugin.json` exists and parses as valid JSON. No validation of required fields (`id`, `name`, `runtime`, `type`), field types, or value ranges. A manifest with `runtime: "native"` and `signed: true` would be accepted and later bypass the trust dialog (since `_verify_signature` is a stub that returns `true` if plugin.sig exists). |
| **Lua `load()` available in sandbox** | **Low** | `scripted_runtime.gd:450` | The custom `require()` uses Lua's `load()` to compile module source. Since `LUA_BASE` is enabled, `load()` (and `loadstring()` in Lua 5.1) is available to plugin code, allowing runtime code generation from strings. This is standard for Lua sandboxes but worth noting — a plugin can construct and execute arbitrary Lua at runtime, making static analysis of plugin behavior impossible. |
| **No resource exhaustion limits for Lua** | **Medium** | `scripted_runtime.gd` | There is no CPU instruction count limit or execution timeout for Lua code. A malicious or buggy `_draw()` function runs every frame with no interrupt. An infinite loop in `_ready()` or `_on_event()` would freeze the main thread. Timer callbacks (`set_interval` at minimum 16ms) can accumulate. The `MAX_SOUNDS = 16` and canvas limits help, but CPU is unbounded. |
| **Native plugins get full Godot API access** | **By design** | `native_runtime.gd:48` | Native plugin scenes are instantiated with `scene.instantiate()` and added to the tree. They inherit full access to the scene tree, autoloads (Client, Config, AppState), filesystem, and network. This is documented and gated by the trust dialog, but a trusted native plugin could exfiltrate auth tokens from `Config`, send messages as the user via `Client`, or access local files. |
| **Data channel topic spoofing within a plugin** | **Low** | `plugin_context.gd:42`, `client_plugins.gd:341-344` | The data channel topic prefix is `plugin:<id>:`. `_on_livekit_data_received` (line 341) strips this prefix before forwarding. A malicious participant in the LiveKit room could send data with an arbitrary `plugin:<id>:` prefix targeting a different plugin's topic namespace. Cross-plugin isolation depends on LiveKit room membership, not cryptographic channel separation. |

### What's Properly Protected

| Control | Status | Location | Tested? |
|---------|--------|----------|---------|
| Lua sandbox — dangerous libs blocked | OK | `scripted_runtime.gd:13` — io, os, package, debug, ffi excluded via bitmask | No |
| Lua `require()` restricted to bundle | OK | `scripted_runtime.gd:441-458` — only loads from `_modules` dict, no filesystem | No |
| Canvas coordinate clamping | OK | `plugin_canvas.gd:205-209` — all coords clamped to canvas bounds | **Yes** |
| Canvas resource limits | OK | `plugin_canvas.gd:7-9` — MAX_IMAGES=64, MAX_BUFFERS=4, MAX_COMMANDS=4096 | **Yes** |
| Canvas size bounds | OK | `scripted_runtime.gd:66-73` — width 64-1920, height 64-1080 | No |
| Sound limit | OK | `scripted_runtime.gd:9` — MAX_SOUNDS=16 | No |
| Bundle size limit (download) | OK | `plugin_download_manager.gd:8` — 50 MB max | **Yes** (constant check) |
| SHA-256 hash verification | OK | `plugin_download_manager.gd:75-81` — rejects hash mismatch | **Yes** |
| Cache directory URI encoding | OK | `plugin_download_manager.gd:123-125` — server_id and plugin_id URI-encoded | **Yes** |
| Data channel namespacing | OK | `plugin_context.gd:42` — `plugin:<id>:` prefix isolates topics | **Yes** |
| Data channel prefix stripping | OK | `client_plugins.gd:341-344` — strips prefix, routes to runtime | **Yes** |
| Plugin isolation per connection | OK | `client_plugins.gd:10` — `_plugin_cache[conn_index]` separates servers | **Yes** |
| Trust gating before native execution | OK | `client_plugins.gd:236-248` — unsigned natives require explicit user consent | No |
| Voice disconnect cleanup | OK | `client_plugins.gd:524-530` — leaving voice clears activity state | **Yes** |
| LiveKit data channel disconnect | OK | `client_plugins.gd:538-542` — `_clear_active_activity` disconnects handler | **Yes** |
| File framing protocol consistency | OK | `plugin_context.gd:51-62` ↔ `native_runtime.gd:108-118` — roundtrip tested | **Yes** |

### Security Test Gaps (Priority Order)

| # | Test Needed | Why |
|---|-------------|-----|
| 1 | **ZIP path traversal in `_extract_zip`** | Craft a ZIP with `../../../etc/passwd` entry, verify it is rejected or sanitized. Currently it writes outside the cache dir. |
| 2 | **ZIP path traversal in `_extract_bundle`** | Same attack via scripted plugin bundle entry_point containing `../`. |
| 3 | **Trust-all persists across new plugins** | Install plugin A, grant trust-all, install plugin B — verify B runs without prompt. Then verify there's no way to revoke. |
| 4 | ~~**Signature stub accepts any plugin.sig**~~ | **Done** — `test_verify_signature_returns_true_when_sig_exists` documents this gap. |
| 5 | **BBCode injection in trust dialog** | Set plugin name to `[url]http://evil[/url]`, verify it renders literally (not as a link). |
| 6 | **Concurrent temp file race** | Launch two scripted plugins simultaneously, verify they don't corrupt each other's `user://tmp_plugin_bundle.zip`. |
| 7 | **Lua CPU exhaustion** | Run `while true do end` in `_ready()`, verify it doesn't permanently freeze the client (currently it will). |
| 8 | **Manifest field injection on upload** | Upload a manifest with `signed: true` + fake `plugin.sig`, verify the server or client rejects it. |
| 9 | **HTTP downgrade for plugin download** | Connect to HTTP server, download plugin, verify hash check catches MITM replacement (it should — but test it). |
| 10 | **Module name collision** | Bundle two `.lua` files with the same basename at different paths, verify correct one loads. |

## Recommended Next Test Priorities

1. **ZIP path traversal** (Critical) — craft malicious ZIPs with `../` entries, verify rejection in both `_extract_zip` and `_extract_bundle`
2. **ClientPlugins._extract_bundle** — construct a small ZIP in-memory, verify entry/module/asset extraction
3. **BBCode escaping in trust dialog** — verify plugin names can't inject formatting
4. **NativeRuntime.start/stop** — mock scene on disk, verify lifecycle calls
5. **ActivityLobby.update_participants** — feed participant arrays, verify start button enable state
6. **ScriptedRuntime bridge API** — requires lua-gdextension; test bridge callback closures in isolation
