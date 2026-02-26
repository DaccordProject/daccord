# Godot-LiveKit

## Overview

Godot-LiveKit is a GDExtension addon that wraps the [LiveKit C++ SDK](https://github.com/livekit/client-sdk-cpp) for real-time voice, video, and data streaming within Godot 4.5. It is developed in a separate repository (`godot-livekit`) and its compiled binaries are vendored into daccord at `addons/godot-livekit/`. The extension exposes 15+ native classes to GDScript, and daccord wraps them via `LiveKitAdapter` (a GDScript adapter) to bridge room-based media into the signal surface that `Client` and `ClientVoice` expect.

## User Steps

From a developer's perspective (building and integrating):

1. Clone the `godot-livekit` repository
2. Run `./build.sh linux|macos|windows` to compile the GDExtension
3. Copy the resulting `addons/godot-livekit/` folder into the daccord project's `addons/` directory
4. Godot auto-detects the `.gdextension` file and registers all LiveKit classes at scene initialization
5. `LiveKitAdapter` (daccord's GDScript wrapper) creates `LiveKitRoom` instances and manages the connection lifecycle
6. `Client._ready()` creates a `LiveKitAdapter` child node and wires its signals to `ClientVoice` callbacks

From the user's perspective (voice/video in daccord):

1. User joins a voice channel; the server returns a LiveKit URL and token
2. `LiveKitAdapter.connect_to_room(url, token)` creates a `LiveKitRoom` and connects
3. On room connect, the adapter auto-publishes local microphone audio via `LiveKitAudioSource` + `LiveKitLocalAudioTrack`
4. Remote participants' audio/video tracks arrive via `track_subscribed` events and are rendered in the UI
5. User can publish camera (`publish_camera()`) or screen share (`publish_screen()`) tracks
6. On disconnect, all local/remote tracks are cleaned up and the room is closed

## Signal Flow

```
godot-livekit (C++ GDExtension)         LiveKitAdapter (GDScript)             ClientVoice / Client
         |                                       |                                    |
LiveKitRoom                                      |                                    |
  .connect_to_room(url, token) <------------- connect_to_room(url, token)             |
         |                                       |                                    |
         | (LiveKit C++ SDK handles              |                                    |
         |  WebRTC offer/answer/ICE)             |                                    |
         |                                       |                                    |
         | -- connected signal ----------------> _on_connected()                      |
         |                                       |-- state = CONNECTED                |
         |                                       |-- session_state_changed ---------> on_session_state_changed()
         |                                       |-- _publish_local_audio()           |
         |                                       |   LiveKitAudioSource.create()      |
         |                                       |   LiveKitLocalAudioTrack.create()  |
         |                                       |   LocalParticipant.publish_track() |
         |                                       |                                    |
         | -- participant_connected -----------> _on_participant_connected()           |
         |                                       |-- peer_joined ------------------>  on_peer_joined()
         |                                       |                                    |-- fetch_voice_states()
         |                                       |                                    |
         | -- track_subscribed ----------------> _on_track_subscribed()                |
         |      (audio)                          |-- _setup_remote_audio()            |
         |                                       |   LiveKitAudioStream.from_track()  |
         |                                       |   AudioStreamGenerator + Player    |
         |      (video)                          |-- LiveKitVideoStream.from_track()  |
         |                                       |-- track_received ----------------> on_track_received()
         |                                       |                                    |-- remote_track_received
         |                                       |                                    |
         | (per frame, in _process)              |                                    |
         |                                       | _room.poll_events()               |
         |                                       |   (drain C++ callbacks to main    |
         |                                       |    thread)                        |
         |                                       | poll remote video streams          |
         |                                       | poll remote audio into playback    |
         |                                       | compute audio levels               |
         |                                       |-- audio_level_changed -----------> on_audio_level_changed()
         |                                       |                                    |-- speaking_changed
         |                                       |                                    |
         | -- participant_disconnected --------> _on_participant_disconnected()        |
         |                                       |-- cleanup remote audio/video       |
         |                                       |-- peer_left --------------------->  on_peer_left()
         |                                       |                                    |
         | -- disconnected --------------------> _on_disconnected()                   |
         |                                       |-- state = DISCONNECTED             |
         |                                       |-- session_state_changed ---------> on_session_state_changed()
```

## Key Files

| File | Role |
|------|------|
| `addons/godot-livekit/godot-livekit.gdextension` | GDExtension manifest: entry symbol, platform library paths, native dependencies |
| `addons/godot-livekit/bin/` | Prebuilt platform binaries (Linux `.so`, Windows `.dll`, macOS `.dylib`) + LiveKit FFI shared libraries |
| `scripts/autoload/livekit_adapter.gd` | GDScript adapter wrapping `LiveKitRoom`: room lifecycle, local audio/video/screen publishing, remote audio playback, mic capture, audio level detection |
| `scripts/autoload/client_voice.gd` | `ClientVoice` helper: wires LiveKitAdapter signals to AppState, manages voice join/leave/mute/deafen |
| `scripts/autoload/client.gd` | Creates `LiveKitAdapter` in `_ready()` (line 156), connects session signals (lines 158-172), speaking debounce timer (lines 176-180) |
| `scenes/video/video_tile.gd` | Renders `LiveKitVideoStream` textures in video tiles, speaking border indicator |
| `scenes/video/video_grid.gd` | Grid layout for local/remote video tiles, rebuilds on track add/remove |
| `scripts/autoload/config_voice.gd` | Persists voice/video device preferences (input/output device, resolution, FPS) |
| `tests/livekit/unit/test_livekit_adapter.gd` | Unit tests for LiveKitAdapter (state machine, mute/deafen, signals, disconnect). No server needed. |
| `tests/accordkit/e2e/test_voice_auth_handshake.gd` | E2E tests for voice auth handshake: REST join/leave, LiveKit credential validation, mute/deaf flags. Requires server with `ACCORD_TEST_MODE=true`. |
| `tests/accordkit/helpers/test_base.gd` | `AccordTestBase`: test harness with seed data and `ACCORD_TEST_URL` env var override (line 26) |

### External Repository (godot-livekit)

| File | Role |
|------|------|
| `src/register_types.cpp` | Registers all 15+ classes with Godot ClassDB at scene init |
| `src/livekit_room.h/cpp` | `LiveKitRoom`: room connection, `GodotRoomDelegate` bridging C++ callbacks to Godot signals |
| `src/livekit_participant.h/cpp` | `LiveKitParticipant`, `LiveKitLocalParticipant` (publish/unpublish, RPC, data), `LiveKitRemoteParticipant` |
| `src/livekit_track.h/cpp` | `LiveKitTrack` base + `LiveKitLocalAudioTrack`, `LiveKitLocalVideoTrack`, `LiveKitRemoteAudioTrack`, `LiveKitRemoteVideoTrack` |
| `src/livekit_track_publication.h/cpp` | `LiveKitTrackPublication`, `LiveKitLocalTrackPublication`, `LiveKitRemoteTrackPublication` (subscription control) |
| `src/livekit_audio_source.h/cpp` | `LiveKitAudioSource`: capture audio frames into LiveKit (48kHz, mono/stereo, configurable queue) |
| `src/livekit_audio_stream.h/cpp` | `LiveKitAudioStream`: receives remote audio via background reader thread, polls into `AudioStreamGeneratorPlayback` |
| `src/livekit_video_source.h/cpp` | `LiveKitVideoSource`: capture video frames (Godot `Image`) into LiveKit |
| `src/livekit_video_stream.h/cpp` | `LiveKitVideoStream`: receives remote video via background reader thread, provides `ImageTexture` via `poll()` |
| `src/livekit_e2ee.h/cpp` | `LiveKitE2eeOptions`, `LiveKitKeyProvider`, `LiveKitFrameCryptor`, `LiveKitE2eeManager` (conditional compile) |
| `build.sh` | Build script: fetches LiveKit C++ SDK + godot-cpp prebuilts, compiles with SCons |
| `SConstruct` | SCons build configuration for the GDExtension |

## Implementation Details

### GDExtension Architecture

The addon is a native C++ GDExtension, compiled against `godot-cpp` (Godot's C++ binding layer). It wraps the [LiveKit C++ SDK](https://github.com/livekit/client-sdk-cpp) (version 0.3.2) which handles all WebRTC internals (SDP negotiation, ICE, DTLS, SRTP).

**Class registration** (`register_types.cpp`): On `MODULE_INITIALIZATION_LEVEL_SCENE`, the extension calls `livekit::initialize()` and registers all classes with `ClassDB`. On shutdown, it calls `livekit::shutdown()`.

**Registered classes** (16 core + 4 E2EE):
- Room: `LiveKitRoom`
- Participants: `LiveKitParticipant`, `LiveKitLocalParticipant`, `LiveKitRemoteParticipant`
- Tracks: `LiveKitTrack`, `LiveKitLocalAudioTrack`, `LiveKitLocalVideoTrack`, `LiveKitRemoteAudioTrack`, `LiveKitRemoteVideoTrack`
- Publications: `LiveKitTrackPublication`, `LiveKitLocalTrackPublication`, `LiveKitRemoteTrackPublication`
- Streams: `LiveKitVideoStream`, `LiveKitAudioStream`
- Sources: `LiveKitVideoSource`, `LiveKitAudioSource`
- Screen capture: `LiveKitScreenCapture`
- E2EE (conditional): `LiveKitE2eeOptions`, `LiveKitKeyProvider`, `LiveKitFrameCryptor`, `LiveKitE2eeManager`

### LiveKitRoom (livekit_room.h)

The central class. Wraps `livekit::Room` and uses a `GodotRoomDelegate` (inner class) to bridge 20+ C++ event callbacks into Godot signals.

**Connection states** (enum `ConnectionState`):
- `STATE_DISCONNECTED = 0`, `STATE_CONNECTED = 1`, `STATE_RECONNECTING = 2`

**Threading model**: `connect_to_room()` runs connection in a background `std::thread` (line 82-83, `connect_thread_`, `connecting_async_`), then finalizes on the main thread via `_finalize_connection()`. The adapter calls `poll_events()` every frame in `_process()` (line 172) to drain the thread-safe event queue, executing C++ callbacks (connection results, participant joins/leaves, track subscriptions) on the main thread.

**Connection options**: The adapter passes `{"auto_reconnect": false}` to `connect_to_room()` (line 72 of `livekit_adapter.gd`), disabling the SDK's built-in reconnection. Reconnection is handled at the application layer by `ClientVoice` / gateway events.

**Disconnect optimization**: `disconnect_voice()` (line 74) skips the blocking `unpublish_track()` SDK calls and instead drops all local track references before calling `disconnect_from_room()`, relying on the room teardown to handle track cleanup internally.

**Signals emitted** (from `GodotRoomDelegate` overrides):
- `connected`, `disconnected`, `reconnecting`, `reconnected`
- `participant_connected(participant)`, `participant_disconnected(participant)`
- `track_published`, `track_unpublished`, `track_subscribed(track, publication, participant)`, `track_unsubscribed(track, publication, participant)`
- `track_muted(participant, publication)`, `track_unmuted(participant, publication)`
- `local_track_published`, `local_track_unpublished`
- `data_received(data, participant, kind, topic)`
- `room_metadata_changed`, `connection_quality_changed`
- `participant_metadata_changed`, `participant_name_changed`, `participant_attributes_changed`
- E2EE: `e2ee_state_changed`, `participant_encryption_status_changed`

**Key methods**:
- `connect_to_room(url, token, options)` -- connects to a LiveKit server
- `disconnect_from_room()` -- disconnects and cleans up
- `get_local_participant()` -> `LiveKitLocalParticipant`
- `get_remote_participants()` -> Dictionary
- `poll_events()` -- drains the thread-safe event queue on the main thread (called per-frame by `LiveKitAdapter._process()`)
- `get_sid()`, `get_name()`, `get_metadata()`, `get_connection_state()`

### Track Hierarchy (livekit_track.h)

Base class `LiveKitTrack` wraps `livekit::Track` with enums:
- `TrackKind`: `KIND_UNKNOWN = 0`, `KIND_AUDIO = 1`, `KIND_VIDEO = 2`
- `TrackSource`: `SOURCE_UNKNOWN = 0`, `SOURCE_CAMERA = 1`, `SOURCE_MICROPHONE = 2`, `SOURCE_SCREENSHARE = 3`, `SOURCE_SCREENSHARE_AUDIO = 4`
- `StreamState`: `STATE_UNKNOWN = 0`, `STATE_ACTIVE = 1`, `STATE_PAUSED = 2`

Subclasses:
- `LiveKitLocalAudioTrack`: `create(name, source)` static factory, `mute()`, `unmute()`
- `LiveKitLocalVideoTrack`: `create(name, source)` static factory, `mute()`, `unmute()`
- `LiveKitRemoteAudioTrack`: read-only, tracks arrive via subscription
- `LiveKitRemoteVideoTrack`: read-only, tracks arrive via subscription

All tracks expose: `get_sid()`, `get_name()`, `get_kind()`, `get_source()`, `get_muted()`, `get_stream_state()`, `get_stats()`.

### Participants (livekit_participant.h)

Base `LiveKitParticipant`:
- `ParticipantKind`: `KIND_STANDARD = 0`, `KIND_INGRESS = 1`, `KIND_EGRESS = 2`, `KIND_SIP = 3`, `KIND_AGENT = 4`
- Methods: `get_sid()`, `get_name()`, `get_identity()`, `get_metadata()`, `get_attributes()`, `get_kind()`

`LiveKitLocalParticipant` (extends `LiveKitParticipant`):
- `publish_track(track, options)` -> `LiveKitLocalTrackPublication`
- `unpublish_track(track_sid)` -- removes a published track
- `publish_data(data, reliable, destination_identities, topic)` -- send data messages
- `set_metadata()`, `set_name()`, `set_attributes()`
- RPC: `perform_rpc()`, `register_rpc_method()`, `unregister_rpc_method()`, `respond_to_rpc()`, `respond_to_rpc_error()`

`LiveKitRemoteParticipant` (extends `LiveKitParticipant`):
- `get_track_publications()` -> Dictionary
- Subscription is managed via `LiveKitRemoteTrackPublication.set_subscribed()`

### Audio Pipeline

**Publishing (local mic -> LiveKit)**:
1. `LiveKitAudioSource.create(48000, 1, 200)` -- creates a source with 48kHz, mono, 200ms queue
2. `LiveKitLocalAudioTrack.create("microphone", source)` -- creates a track backed by the source
3. `LocalParticipant.publish_track(track, {"source": SOURCE_MICROPHONE})` -- publishes to the room
4. `LiveKitAdapter._setup_mic_capture()` creates an `AudioEffectCapture` on a muted "MicCapture" bus for local level detection (line 301)
5. The LiveKit C++ SDK reads from the audio source internally and sends via WebRTC

**Receiving (remote audio -> Godot playback)**:
1. `track_subscribed` fires with an audio track
2. `LiveKitAudioStream.from_track(track)` -- creates a stream with a background reader thread (`_reader_loop`, `livekit_audio_stream.h` line 34) that buffers incoming audio
3. `AudioStreamGenerator` + `AudioStreamPlayer` created per remote participant
4. Per-frame `LiveKitAudioStream.poll(playback)` pushes buffered audio into `AudioStreamGeneratorPlayback`
5. Deafen sets player `volume_db` to `-80.0` (line 108 of `livekit_adapter.gd`)

**Audio level detection** (`livekit_adapter.gd`, `_process`, lines 167-207):
- Remote: `_estimate_audio_level(player)` reads `AudioServer.get_bus_peak_volume_left_db()`, converts dB to linear (line 408)
- Local: reads `AudioEffectCapture.get_buffer()`, computes RMS, emits if > 0.001 (lines 194-207)

### Video Pipeline

**Publishing camera** (`LiveKitAdapter.publish_camera()`, line 119):
1. `LiveKitVideoSource.create(width, height)` -- creates a video source
2. `LiveKitLocalVideoTrack.create("camera", source)` -- creates a track
3. `LocalParticipant.publish_track(track, {"source": SOURCE_CAMERA})` -- publishes
4. Returns `LiveKitVideoStream.from_track()` for local preview

**Publishing screen** (`LiveKitAdapter.publish_screen()`, line 142):
1. `LiveKitVideoSource.create(1920, 1080)` -- hardcoded 1080p (line 147)
2. `LiveKitLocalVideoTrack.create("screen", source)` -- creates a track
3. `LocalParticipant.publish_track(track, {"source": SOURCE_SCREENSHARE})` -- publishes

### Screen Capture (LiveKitScreenCapture)

`LiveKitScreenCapture` captures screen or window content using the native **frametap** library, delivering frames as `ImageTexture`/`Image` objects for publishing via `LiveKitVideoSource`.

**Static query methods:**
- `get_monitors() -> Array` -- returns available monitors, each with properties: `id`, `name`, `x`, `y`, `width`, `height`, `scale`
- `get_windows() -> Array` -- returns available windows, each with properties: `id`, `name`, `x`, `y`, `width`, `height`
- `check_permissions() -> Dictionary` -- validates screen capture permissions; returns `status` (int), `summary` (String), `details` (Array)

**Factory methods:**
- `create() -> LiveKitScreenCapture` -- creates capture for the default monitor
- `create_for_monitor(monitor: Dictionary) -> LiveKitScreenCapture` -- targets a specific monitor from `get_monitors()`
- `create_for_window(window: Dictionary) -> LiveKitScreenCapture` -- targets a specific window from `get_windows()`

**Lifecycle:**
- `start()` -- initiates asynchronous capture
- `stop()` -- halts capture
- `pause()` -- suspends without terminating
- `resume()` -- resumes paused capture
- `is_paused() -> bool` -- checks pause status

**Frame access:**
- `poll() -> bool` -- retrieves new frames; call in `_process()`, returns `true` on new frame
- `get_texture() -> ImageTexture` -- latest captured frame as texture
- `get_image() -> Image` -- latest frame as `Image`
- `screenshot() -> Image` -- single immediate screenshot (no `start()` required)
- `close()` -- stops and releases resources

**Signal:**
- `frame_received` -- emitted after `poll()` detects a new frame

**Enum `PermissionLevel`:**
- `PERMISSION_OK = 0`, `PERMISSION_WARNING = 1`, `PERMISSION_ERROR = 2`

**Usage pattern:**
```gdscript
# Enumerate sources
var monitors = LiveKitScreenCapture.get_monitors()
var windows = LiveKitScreenCapture.get_windows()

# Create capture for a specific monitor or window
var capture = LiveKitScreenCapture.create_for_monitor(monitors[0])
# or: var capture = LiveKitScreenCapture.create_for_window(windows[0])

capture.start()

# In _process():
if capture.poll():
    var image = capture.get_image()
    video_source.capture_frame(image, timestamp, 0)
```

This class replaces the need for Godot's `DisplayServer.get_screen_count()` / `screen_get_size()` for screen enumeration, and provides actual frame capture that was previously missing. It also enables window-level sharing (not just full screens).

**Receiving video**:
1. `track_subscribed` fires with a video track
2. `LiveKitVideoStream.from_track(track)` -- creates a stream with a background reader thread (`_reader_loop`, `livekit_video_stream.h` line 33) that decodes frames into a pending `livekit::VideoFrame`
3. `poll()` converts the pending frame to a Godot `Image` -> `ImageTexture` (thread-safe via `frame_mutex_`)
4. `video_tile.gd` calls `_stream.poll()` per frame and assigns `_stream.get_texture()` to a `TextureRect` (lines 68-74)

### LiveKitAdapter State Machine (livekit_adapter.gd)

```
    connect_to_room()
         |
    DISCONNECTED ---------> CONNECTING ---------> CONNECTED
         ^                      |                    |
         |                      | (failure)          | (reconnecting event)
         |                      v                    v
         |                   FAILED             RECONNECTING
         |                                          |
         |                                          | (reconnected event)
         +------ disconnect_voice() <----- CONNECTED
```

State enum (lines 16-22): `DISCONNECTED = 0`, `CONNECTING = 1`, `CONNECTED = 2`, `RECONNECTING = 3`, `FAILED = 4`

**Track management** -- LiveKitAdapter holds 9 track-related variables (lines 31-39):
- Local audio: `_local_audio_source`, `_local_audio_track`, `_local_audio_pub`
- Local video (camera): `_local_video_source`, `_local_video_track`, `_local_video_pub`
- Local screen: `_local_screen_source`, `_local_screen_track`, `_local_screen_pub`

**Remote tracking**:
- `_remote_audio: Dictionary` (line 42): identity -> `{stream, player, playback, generator}`
- `_remote_video: Dictionary` (line 44): identity -> `LiveKitVideoStream`
- `_identity_to_user: Dictionary` (line 47): participant identity -> user_id mapping

### End-to-End Encryption (E2EE)

Conditionally compiled behind `LIVEKIT_E2EE_SUPPORTED` (livekit_e2ee.h). Provides:

- `LiveKitE2eeOptions`: encryption type (`ENCRYPTION_NONE`, `ENCRYPTION_GCM`, `ENCRYPTION_CUSTOM`), shared key, ratchet salt/window, failure tolerance
- `LiveKitKeyProvider`: per-participant or shared key management with key ratcheting
- `LiveKitFrameCryptor`: per-participant frame encryption control (enable/disable, key index)
- `LiveKitE2eeManager`: enable/disable E2EE, access key provider and frame cryptors

Accessible via `LiveKitRoom.get_e2ee_manager()`. Not currently used by daccord.

### Platform Binaries

The `.gdextension` file maps platform targets to library paths:

| Platform | Extension library | Dependencies |
|----------|-------------------|-------------|
| Linux x86_64 | `libgodot-livekit.linux.x86_64.so` | `liblivekit_ffi.so`, `liblivekit.so` |
| Windows x86_64 | `libgodot-livekit.windows.x86_64.dll` | `livekit_ffi.dll`, `livekit.dll` |
| macOS universal | `libgodot-livekit.macos.universal.dylib` | `liblivekit_ffi.dylib`, `liblivekit.dylib` |

Uses the same binary for both debug and release configurations.

**Linux RPATH fix**: The release binaries do not set an RPATH, so `dlopen` cannot find `liblivekit.so` in the same directory. After downloading, run `patchelf --set-rpath '$ORIGIN'` on the Linux `.so` to fix this:
```bash
patchelf --set-rpath '$ORIGIN' addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so
```

### Build Process (build.sh)

1. Validates platform argument (`linux`, `macos`, `windows`)
2. Checks and installs dependencies (SCons, g++/MSVC, curl, etc.)
3. Fetches LiveKit C++ SDK (version 0.3.2) from GitHub Releases if not cached
4. Fetches `godot-cpp` prebuilt binaries (Godot 4.5 stable) if not cached
5. Runs `scons platform=<platform> arch=<arch> target=template_release`
6. Copies LiveKit shared libraries to `addons/godot-livekit/bin/`

### Data Channels and RPC

The extension supports data messaging and RPC between participants, though daccord does not currently use these features:

- `LiveKitLocalParticipant.publish_data(data, reliable, destinations, topic)` -- send arbitrary `PackedByteArray` data
- `LiveKitRoom.data_received` signal -- receive data from other participants
- `perform_rpc()`, `register_rpc_method()`, `respond_to_rpc()` -- request/response pattern between participants

### Connection Statistics

`LiveKitTrack.get_stats()` returns an `Array` of WebRTC statistics including inbound/outbound RTP, codecs, transport, and candidate pair metrics. Not currently surfaced in the daccord UI.

### Tests

#### Unit Tests (test_livekit_adapter.gd)

10 tests covering the LiveKitAdapter GDScript wrapper (no server needed, run via `./test.sh livekit`):
- `test_initial_state_is_disconnected` -- verifies initial state (line 15)
- `test_is_muted_default_false` / `test_is_deafened_default_false` -- default flags (lines 23, 30)
- `test_set_muted_updates_state` / `test_set_deafened_updates_state` -- toggle behavior (lines 37, 50)
- `test_disconnect_voice_from_disconnected` -- idempotent disconnect (line 63)
- `test_has_required_signals` -- verifies all 5 signals exist (line 73)
- `test_disconnect_emits_state_signal` -- signal emission (line 96)
- `test_unpublish_camera_without_room` / `test_unpublish_screen_without_room` -- no-error on null room, asserts state stays DISCONNECTED (lines 108, 118)

#### E2E Voice Auth Handshake (test_voice_auth_handshake.gd)

5 tests covering the REST voice join/leave flow and LiveKit credential validation (requires accordserver with `ACCORD_TEST_MODE=true`, run via `./test.sh accordkit`):
- `test_voice_info_reports_backend` -- `GET /voice/info` returns a backend field (line 24)
- `test_create_voice_channel` -- creates a voice channel via `POST /spaces/{id}/channels` (line 33)
- `test_voice_join_returns_livekit_credentials` -- joins voice via REST, validates `AccordVoiceServerUpdate` contains `livekit_url` (ws:// or wss://), `token` (valid JWT), `voice_state` with correct user/channel IDs. **Skips when backend is "none"** (line 44)
- `test_voice_join_with_mute_and_deaf_flags` -- joins with `self_mute=true, self_deaf=true`, verifies flags propagate in `voice_state`. **Skips when backend is "none"** (line 143)
- `test_voice_leave_without_join_fails_gracefully` -- leave without prior join does not crash (line 183)

The credential validation test (line 44) checks exactly what `ClientVoice._connect_voice_backend()` would receive before calling `LiveKitAdapter.connect_to_room()`. This is the key diagnostic: if `livekit_url` is null/empty or `token` is not a valid JWT, the Godot client cannot connect.

**Running against a remote test server:**

```bash
ACCORD_TEST_URL=http://192.168.1.144:39099 ./test.sh accordkit
```

`AccordTestBase._resolve_server_url()` (line 25) reads `ACCORD_TEST_URL` and derives both `BASE_URL` and `GATEWAY_URL`. `SeedClient.seed()` uses the same base URL.

#### Known Test Failures

| Test file | Test | Failure | Severity |
|-----------|------|---------|----------|
| `test_livekit_adapter.gd` | All 10 tests | Fail if Linux RPATH not patched (see Platform Binaries section) | Fixed with `patchelf` |
| `test_voice_auth_handshake.gd` | `test_voice_join_returns_livekit_credentials` | Skipped (pass) when server backend is "none" (local test server has no LiveKit configured) | Expected |
| `test_voice_auth_handshake.gd` | `test_voice_join_with_mute_and_deaf_flags` | Same skip as above | Expected |
| `test_gateway_connect.gd` | `test_bot_connect_receives_ready` | Bot gateway connection times out after 15s | Pre-existing |
| `test_gateway_connect.gd` | `test_user_connect_receives_ready` | User gateway connection times out after 15s | Pre-existing |
| `test_gateway_connect.gd` | `test_disconnect_clean_state` | Depends on bot connecting first | Pre-existing |
| `test_gateway_events.gd` | `test_bot_receives_message_create` | Bot gateway ready timeout | Pre-existing |
| `test_full_lifecycle.gd` | `test_full_lifecycle` | Bot gateway ready timeout (step 1) | Pre-existing |
| `test_add_server.gd` | `test_add_server_via_invite` | Bot gateway ready timeout (step 3) | Pre-existing |

**Linux RPATH issue**: The v0.3.2 release binaries ship without an RPATH, so `dlopen` cannot resolve `liblivekit.so` even though it sits in the same `bin/` directory. This causes all LiveKit types to be undefined and every test that touches `LiveKitAdapter` fails with parse errors. Fix: `patchelf --set-rpath '$ORIGIN' addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so`.

The gateway timeout failures are pre-existing and unrelated to voice/LiveKit -- all 6 fail because the bot/user WebSocket `ready_received` signal never fires within the 10-15s timeout. The voice auth handshake tests (REST-only, no gateway) pass cleanly.

## Implementation Status

- [x] GDExtension wrapping LiveKit C++ SDK (version 0.3.2)
- [x] Cross-platform binaries (Linux x86_64, Windows x86_64, macOS universal)
- [x] LiveKitRoom with full signal surface (connected, disconnected, reconnecting, participant/track events)
- [x] Background thread connection (`connect_thread_`, `connecting_async_`)
- [x] Local audio track publishing via LiveKitAudioSource + LiveKitLocalAudioTrack
- [x] Local video track publishing via LiveKitVideoSource + LiveKitLocalVideoTrack
- [x] Screen share publishing via SOURCE_SCREENSHARE
- [x] LiveKitScreenCapture class for native screen/window capture via frametap
- [x] Remote audio reception via LiveKitAudioStream with background reader thread
- [x] Remote video reception via LiveKitVideoStream with background reader thread
- [x] Audio playback via Godot AudioStreamGenerator pipeline
- [x] Video rendering via poll() -> ImageTexture -> TextureRect
- [x] Track publication management (publish_track, unpublish_track)
- [x] Participant identity and metadata access
- [x] Data channels (publish_data, data_received signal)
- [x] RPC support (perform_rpc, register/unregister/respond)
- [x] Remote track subscription control (set_subscribed)
- [x] WebRTC statistics via get_stats()
- [x] E2EE classes (conditional compile behind LIVEKIT_E2EE_SUPPORTED)
- [x] LiveKitAdapter GDScript wrapper with state machine
- [x] Mic capture via AudioEffectCapture for local audio level detection
- [x] Deafen implementation (remote players set to -80dB)
- [x] Speaking level detection from AudioServer bus peak dB
- [x] Build script with dependency caching (LiveKit SDK + godot-cpp)
- [x] Unit tests for LiveKitAdapter (10 tests, no server required)
- [x] E2E voice auth handshake tests (5 tests, validates REST join/leave and LiveKit credentials)
- [x] `ACCORD_TEST_URL` env var for running tests against remote servers
- [x] Video tile rendering with speaking border indicator
- [x] Video grid with responsive column layout
- [x] Config persistence for video resolution and FPS
- [ ] E2EE integration in daccord (classes exist but not wired)
- [ ] Data channel usage in daccord (classes exist but not used)
- [ ] RPC usage in daccord (classes exist but not used)
- [ ] WebRTC stats surfaced in UI
- [ ] ARM64 / Linux ARM builds
- [ ] Web platform support (see web_export.md)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| E2EE not wired in daccord | Medium | `LiveKitE2eeManager`, `LiveKitKeyProvider`, `LiveKitFrameCryptor` are compiled and registered but daccord never enables encryption. Would need server-side key exchange and UI for shared key entry. |
| Data channels unused | Low | `publish_data()` and `data_received` signal are available but daccord uses the WebSocket gateway for all messaging. Could be useful for low-latency in-call features (e.g., cursor sharing, annotations). |
| RPC unused | Low | `perform_rpc()` / `register_rpc_method()` are available. Could enable peer-to-peer features without gateway round-trips. |
| No WebRTC stats UI | Low | `LiveKitTrack.get_stats()` returns detailed WebRTC metrics but they are not exposed in any settings or debug panel. |
| Screen share resolution hardcoded | Low | `publish_screen()` uses 1920x1080 (line 147 of `livekit_adapter.gd`). Should use `LiveKitScreenCapture.get_monitors()` to get the actual resolution and `LiveKitScreenCapture` for frame capture. |
| No ARM64 builds | Medium | Build script only supports x86_64 for Linux/Windows. macOS builds are universal (x86_64 + arm64) but Linux ARM is missing. |
| No web platform | High | GDExtension native libraries cannot load in Godot Web exports. See `web_export.md` for the planned Web API approach. |
| Input/output device selection not applied | Low | `Config.voice` persists device preferences but `LiveKitAdapter` always uses the default `AudioStreamMicrophone` and default audio bus. Need to route selected devices through to LiveKit audio source and playback. |
| No camera device selection | Low | `Config.voice.get_video_device()` is persisted but `publish_camera()` does not select a specific camera device -- it relies on LiveKit's default. |
| Gateway tests all timeout | Medium | All 6 gateway-dependent tests fail because bot/user `ready_received` never fires within 15s. This blocks the `test_gateway_receives_voice_state_on_join` test that was removed from the e2e. Root cause is in the test server WebSocket handling, not the LiveKit integration. |
| Linux RPATH missing in release binaries | Medium | The v0.3.2 release `.so` has no RPATH, so `liblivekit.so` in the same directory is not found by `dlopen`. Workaround: `patchelf --set-rpath '$ORIGIN'`. Should be fixed upstream in the build script's SCons config. |
| Voice credential tests skip on local test server | Low | `test_voice_join_returns_livekit_credentials` and `test_voice_join_with_mute_and_deaf_flags` skip (pass) when the test server reports `backend: "none"`. To exercise these tests, run against a server with LiveKit configured: `ACCORD_TEST_URL=http://host:39099 ./test.sh accordkit`. |
| No LiveKit room connection e2e test | Medium | The current e2e validates REST credentials but does not actually call `LiveKitAdapter.connect_to_room()` because GUT tests run headless and the GDExtension's `LiveKitRoom.connect_to_room()` requires a running LiveKit server. A future integration test could connect and verify `session_state_changed` fires `CONNECTED`. |
