# Voice Channels

Priority: 21
Depends on: Space & Channel Navigation, Godot-LiveKit

## Overview

Voice channels allow users to join real-time audio conversations within a server. The client displays voice channels with a dedicated scene (`voice_channel_item`), shows connected participants with mute/deaf indicators and speaking rings, and provides a voice control bar with mute, deafen, camera, screen share, soundboard, settings, and disconnect buttons. AccordKit provides the REST API (join, leave, status), VoiceManager for connection lifecycle, and gateway event handling. godot-livekit is a GDExtension addon providing LiveKit room connections and media track management. The `Client` autoload delegates voice operations to a `ClientVoice` helper class and manages a `LiveKitAdapter` (GDScript wrapper around `LiveKitRoom`) for the active voice connection.

The voice backend uses LiveKit for WebRTC media transport. When the client joins a voice channel, the server returns a LiveKit URL and token. The client connects to the LiveKit server via `LiveKitAdapter.connect_to_room(url, token)`. LiveKit handles all WebRTC signaling (offer/answer/ICE) internally -- the client does not need to exchange SDP or ICE candidates via the gateway.

## User Steps

1. User sees voice channels in the channel list (speaker icon, distinct from text channels)
2. User clicks a voice channel to join
3. `ClientVoice.join_voice_channel()` calls `VoiceApi.join()` on the server, receives backend connection info
4. Server returns `AccordVoiceServerUpdate` with `livekit_url` and `token`
5. Client validates backend info: requires non-empty `livekit_url` and `token`
6. If backend info is missing or invalid, the client emits `voice_error` and does not call `AppState.join_voice()` (no voice bar, no participant list)
7. If result data is not an `AccordVoiceServerUpdate`, the client emits `voice_error` and returns `false` (no fallthrough)
8. If backend info is valid, the client connects via `LiveKitAdapter.connect_to_room(url, token)`
9. LiveKit handles all WebRTC signaling internally -- no SDP offer/answer exchange through the gateway is needed
10. On room connect, `LiveKitAdapter` auto-publishes local microphone audio via `LiveKitAudioSource` + `LiveKitLocalAudioTrack`
11. Voice bar appears at the bottom of the channel panel showing "Connecting..." with a pulsing amber dot, then switches to the channel name with a green dot once the LiveKit session reaches CONNECTED state
12. The voice channel item shows connected participants with Avatar component, display name, mute (M) / deaf (D) indicators, video (V) / stream (S) indicators, and green speaking ring
13. When a second user joins the same channel, LiveKit handles adding them to the room and routing audio tracks to all participants automatically
14. User can click Mic to toggle mute, Deaf to toggle deafen, or Disconnect to leave
15. On disconnect, `ClientVoice.leave_voice_channel()` calls `VoiceApi.leave()`, disconnects the voice session via `LiveKitAdapter.disconnect_voice()`, and hides the voice bar

## Signal Flow

```
voice_channel_item.gd          AppState                    Client / ClientVoice
     |                              |                              |
     |-- channel_pressed(id) ------>|                              |
     |                              |                              |
     |            channel_list._on_channel_pressed(id)             |
     |                              |-- join_voice_channel(id) --->|
     |                              |                              |-- VoiceApi.join(id)
     |                              |                              |-- validate backend info
     |                              |                              |-- LiveKitAdapter.connect_to_room()
     |                              |<- join_voice(id, space_id) --|
     |                              |                              |-- fetch.fetch_voice_states(id)
     |                              |                              |
     |<-- voice_joined(id) --------|                              |
     |   (refresh participants)     |                              |
     |                              |                              |
voice_bar.gd                       |                              |
     |<-- voice_joined(id) --------|                              |
     |   (show bar, "Connecting..."|                              |
     |    pulse amber dot)          |                              |
     |                              |                              |
     |<-- voice_session_state_changed(CONNECTED) ---|              |
     |   (show channel name,        |                              |
     |    green dot, stop pulse)    |                              |
     |                              |                              |
     |-- mute_btn pressed -------->|                              |
     |                              |<- set_voice_muted(bool) ----|
     |<-- voice_mute_changed -------|   (session.set_muted())     |
     |   (update button visual)     |                              |
     |                              |                              |
     |-- disconnect_btn pressed -->|                              |
     |                              |-- leave_voice_channel() --->|
     |                              |                              |-- close camera/screen tracks
     |                              |                              |-- session.disconnect_voice()
     |                              |                              |-- VoiceApi.leave(id) (best-effort)
     |                              |<- leave_voice() ------------|
     |<-- voice_left(id) ----------|                              |
     |   (hide bar)                 |                              |
     |                              |                              |
     |   Gateway voice events:      |                              |
     |                              |   GatewaySocket emits:       |
     |                              |     voice_state_update        |
     |                              |     voice_server_update       |
     |                              |     voice_signal              |
     |                              |                              |
     |                              |   AccordClient re-emits ---->|
     |                              |                              |
     |                              |   ClientGatewayEvents:       |
     |                              |     on_voice_state_update     |
     |                              |       -> ensures user cached  |
     |                              |       -> ensures member cached|
     |                              |       -> updates cache        |
     |                              |       -> voice_state_updated  |
     |                              |     on_voice_server_update    |
     |                              |       -> stores info          |
     |                              |       -> connects backend if  |
     |                              |          in voice channel     |
     |                              |     on_voice_signal           |
     |                              |       -> no-op (LiveKit       |
     |                              |          handles signaling)   |
     |                              |                              |
     |<-- voice_state_updated ------|                              |
     |   (refresh participants)     |                              |
     |                              |                              |
     |   Speaking indicator flow:   |                              |
     |                              |   LiveKitAdapter._process()  |
     |                              |     -> audio_level_changed   |
     |                              |       -> ClientVoice          |
     |                              |         .on_audio_level_changed
     |                              |       -> speaking_changed     |
     |<-- speaking_changed ---------|                              |
     |   (green ring on avatar)     |                              |
```

### LiveKit Connection Flow

```
Client A              Server (LiveKit)              Client B
   |                         |                              |
   | VoiceApi.join()         |                              |
   |------------------------>|                              |
   |                    join_voice_channel()                 |
   |                         |                              |
   | voice.server_update     |                              |
   | (livekit_url, token)    |                              |
   |<------------------------|                              |
   |                         | voice.state_update           |
   |                         |----------------------------->|
   |                         |                              |
   | LiveKitAdapter          |                              |
   | .connect_to_room()      |                              |
   |------------------------>|                              |
   |  (LiveKit handles all   |                              |
   |   WebRTC signaling      |                              |
   |   internally)           |                              |
   |                         |                              |
   | _on_connected()         |                              |
   | _publish_local_audio()  |                              |
   |  (auto mic publish)     |                              |
   |                         |                              |
   |========= audio flows via LiveKit =========             |
   |                         |                              |
   |                         | VoiceApi.join()              |
   |                         |<-----------------------------|
   |                         |                              |
   |                         | voice.server_update          |
   |                         | (livekit_url, token)         |
   |                         |----------------------------->|
   |                         |                              |
   |                         | LiveKitAdapter               |
   |                         | .connect_to_room()           |
   |                         |<-----------------------------|
   |                         |                              |
   |  LiveKit adds B to room and routes audio automatically |
   |                         |                              |
   |==== A now receives B's audio ====                      |
```

Error path: if `VoiceApi.join()` returns a backend without credentials, `ClientVoice.join_voice_channel()` emits `AppState.voice_error` and returns without emitting `AppState.join_voice` or showing the voice bar. If the server returns data that is not an `AccordVoiceServerUpdate`, the client also emits `voice_error` and returns `false` (no fallthrough to `AppState.join_voice()`).

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/voice_channel_item.gd` (423 lines) | Dedicated voice channel scene: participant list with Avatar components, mute/deaf/video/stream indicators, speaking rings, user count, green tint when connected, chat button for voice text chat |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene (VBoxContainer with ChannelButton + ParticipantContainer) |
| `scenes/sidebar/voice_bar.gd` (301 lines) | Voice control bar: mute/deafen/cam/share/activity/sfx/settings/disconnect buttons, channel name, connection status visual with pulse animation |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene (PanelContainer with StatusRow + ButtonRow) |
| `scenes/sidebar/channels/channel_list.gd` | Instantiates `VoiceChannelItemScene` for VOICE channels, `ChannelItemScene` for others |
| `scenes/sidebar/channels/category_item.gd` | Also instantiates `VoiceChannelItemScene` for voice channels within categories |
| `scenes/sidebar/channels/channel_item.gd` | Generic channel item; still handles VOICE type icon and voice_users count |
| `scenes/sidebar/user_bar.gd` | Voice connection indicator (microphone emoji label) shown/hidden via `voice_joined`/`voice_left` |
| `scenes/sidebar/user_bar.tscn` | VoiceIndicator Label node in HBox |
| `scripts/autoload/app_state.gd` (459 lines) | Voice signals: `voice_state_updated` (line 54), `voice_joined` (line 56), `voice_left` (line 58), `voice_error` (line 60), `voice_session_state_changed` (line 62), `voice_mute_changed` (line 64), `voice_deafen_changed` (line 66), `video_enabled_changed` (line 68), `screen_share_changed` (line 70), `remote_track_received` (line 72), `remote_track_removed` (line 74), `speaking_changed` (line 76), `voice_view_opened` (line 78), `voice_view_closed` (line 80), `voice_text_opened` (line 82), `voice_text_closed` (line 84), `spotlight_changed` (line 86); state vars (lines 226-237) |
| `scripts/autoload/client.gd` (794 lines) | Delegates voice to `ClientVoice`; creates `LiveKitAdapter` or `WebVoiceSession` in `_ready()` (lines 196-206); wires all session signals (lines 207-224); speaking debounce timer (lines 229-234); config_changed wired to voice (line 238) |
| `scripts/autoload/client_voice.gd` (531 lines) | `ClientVoice` helper class: `join_voice_channel()` (line 28), `leave_voice_channel()` (line 141), `set_voice_muted()` (line 204), `set_voice_deafened()` (line 208), `toggle_video()` (line 214), `start_screen_share()` (line 250), `stop_screen_share()` (line 270); session callbacks (lines 300-393); auto-reconnect with fresh token (line 395); config change handler (line 462) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` fetches connected users for a channel via `VoiceApi.get_status()` (line 538) |
| `scripts/autoload/client_gateway.gd` | Voice gateway signal connections (lines 109-114) |
| `scripts/autoload/client_gateway_events.gd` (330 lines) | Gateway voice event handlers: `on_voice_state_update` (line 181), `on_voice_server_update` (line 264), `on_voice_signal` (line 282, no-op stub) |
| `scripts/autoload/client_models.gd` | `ChannelType.VOICE` enum; `voice_state_to_dict()` conversion |
| `scripts/autoload/config_voice.gd` (151 lines) | Voice/video device configuration: input/output/video device get/set, sensitivity, volume, resolution, fps, speaking threshold, debug logging |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_info()`, `list_regions()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking, signals |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState` model (user_id, channel_id, mute, deaf, self_video, self_stream flags) |
| `addons/accordkit/models/voice_server_update.gd` | `AccordVoiceServerUpdate` model (backend type, LiveKit URL, token, SFU endpoint) |
| `addons/accordkit/gateway/gateway_socket.gd` | `voice_state_update`, `voice_server_update`, `voice_signal` signals; dispatch; `update_voice_state()` with video/stream params |
| `addons/accordkit/core/accord_client.gd` | Exposes `voice: VoiceApi`, `voice_manager: VoiceManager`; `update_voice_state()` with `self_video`/`self_stream` params |
| `addons/godot-livekit/` | godot-livekit GDExtension: LiveKitRoom, LiveKitVideoStream, LiveKitAudioStream, LiveKitAudioSource, LiveKitLocalAudioTrack, LiveKitLocalVideoTrack, LiveKitVideoSource, LiveKitScreenCapture for WebRTC media |
| `scripts/autoload/livekit_adapter.gd` (720 lines) | LiveKitAdapter GDScript wrapper: room management, local audio/video/screen publishing, remote audio playback via AudioStreamGenerator, remote video via LiveKitVideoStream, mic capture via AudioEffectCapture, audio level detection, noise gate, camera hot-swap, screen capture with local preview, plugin data channels, connection timeout |
| `scripts/autoload/web_voice_session.gd` (411 lines) | Web platform voice session: delegates to godot-livekit-web.js via JavaScriptBridge, stub camera/screen (no device selection on web) |
| `tests/livekit/unit/test_livekit_adapter.gd` | LiveKitAdapter unit tests (state machine, mute/deafen, signals, disconnect) |
| `tests/unit/test_client_voice.gd` (310 lines) | ClientVoice unit tests: null session check (DAC-79), valid session join, token validation, REST failure handling |

### godot-livekit GDExtension Files

| File | Role |
|------|------|
| `addons/godot-livekit/bin/` | Platform-specific native binaries (Linux, Windows, macOS) + LiveKit FFI shared libraries |
| `addons/godot-livekit/godot-livekit.gdextension` | GDExtension configuration: entry symbol, platform library paths, native dependencies |

## Implementation Details

### Voice Channel Item (voice_channel_item.gd, 423 lines)

Dedicated scene for voice channels (distinct from `channel_item.gd`). Used by both `channel_list.gd` and `category_item.gd` when the channel type is `ChannelType.VOICE`.

- `channel_pressed` signal emitted when the channel button is clicked (line 3)
- Listens to `AppState.voice_state_updated`, `voice_joined`, `voice_left`, `speaking_changed`, `channels_updated`, `voice_text_opened` (lines 45-50)
- `setup(data)` initializes from channel dict, sets voice icon, creates chat button for voice text, creates gear button if `MANAGE_CHANNELS` permission, calls `_refresh_participants()` (line 78)
- `set_active(active)` sets active background and pill visibility (line 129)
- `_refresh_participants()` (line 147):
  - Reads `Client.get_voice_users(channel_id)` for current voice state dicts
  - Shows user count label when count > 0
  - Green tint via `ThemeManager.get_color("success")` on icon when the local user is connected to this channel (line 164)
  - Builds per-participant rows with: 28px indent spacer, 18x18 Avatar component (with letter and color), 6px gap, display name label (12px, role-colored or body text), red "M" or "D" indicator for self_mute/self_deaf, green "V" for self_video, blue "S" for self_stream (lines 170-254)
  - Tracks participant Avatar nodes in `_participant_avatars` dictionary for speaking state updates (line 194)
  - Applies current speaking state on rebuild via `Client.is_user_speaking()` -> `av.set_ring_opacity(1.0)` (lines 195-196)
- `_on_speaking_changed(user_id, is_speaking)` (line 269): updates Avatar speaking animation for the affected participant
- Chat button for voice text chat (line 291): emits `AppState.toggle_voice_text(channel_id)`
- Gear button + context menu for channel edit/delete/mute (requires `MANAGE_CHANNELS` permission) (lines 112-125)
- Drag-and-drop reordering within the same space (lines 356-416)

### Voice Bar (voice_bar.gd, 301 lines)

Bottom panel in the channel sidebar that appears when connected to voice. Instanced in `sidebar.tscn` as a child of `ChannelPanel` (node name `VoiceBar`).

- Hidden by default (`visible = false`, line 37)
- Connects to `AppState.voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed`, `video_enabled_changed`, `screen_share_changed`, `voice_error`, `voice_session_state_changed`, `reduce_motion_changed` (lines 48-56)
- `_on_voice_joined()` (line 77): shows bar, looks up channel name, shows "Connecting..." with amber pulsing status dot, checks `USE_SOUNDBOARD` permission for SFX button visibility
- `_on_session_state_changed()` (line 127): updates visual state based on LiveKit session state:
  - CONNECTING (line 131): amber "Connecting..." with pulse
  - CONNECTED (line 139): green channel name, stop pulse
  - RECONNECTING (line 147): amber "Reconnecting..." with pulse
- `_on_voice_error()` (line 109): shows error text with red dot for 4 seconds, then clears
- `_on_voice_left()` (line 104): hides bar, closes soundboard panel
- Button handlers:
  - Mute (line 168): `Client.set_voice_muted(not AppState.is_voice_muted)`
  - Deafen (line 171): `Client.set_voice_deafened(not AppState.is_voice_deafened)`
  - Video (line 174): `Client.toggle_video()`
  - Share (line 177): opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`
  - Activity (line 188): opens activity modal for plugin launch
  - SFX (line 197): opens/closes soundboard panel, gated on `USE_SOUNDBOARD` permission
  - Settings (line 219): opens User Settings on page 1 (Voice & Video)
  - Disconnect (line 224): `Client.leave_voice_channel()`
- `_update_button_visuals()` (line 239): toggles button icons (Mic/Mic Off, Headphones/Headphones Off, Camera/Camera Off, Screen Share/Screen Share Off) and applies red/green-tinted `StyleBoxFlat` background when active
- `_has_camera()` (line 288): checks `/sys/class/video4linux` on Linux for camera availability, disables video button if none found
- `_on_reduce_motion_changed()` (line 298): stops pulse animation when reduce motion enabled

### ClientVoice Voice Mutation API (client_voice.gd, 531 lines)

Extracted helper class (`ClientVoice extends RefCounted`). Instantiated by `Client._ready()` with a reference to the Client autoload node.

- `join_voice_channel(channel_id)` (line 28):
  - Returns early if already in this channel
  - Leaves current voice channel if in one (awaits `leave_voice_channel()`)
  - Calls `VoiceApi.join()` with current mute/deaf state
  - Validates `AccordVoiceServerUpdate` via `_apply_voice_server_update()` (line 72):
    - Checks `_validate_backend_info()` (line 445): requires non-empty `livekit_url` and `token`
    - Missing credentials emits `voice_error`, calls leave on server, cleans up state via `_cleanup_failed_join_state()`, and returns `false`
  - If result data is not `AccordVoiceServerUpdate`, emits `voice_error` and returns `false` (no fallthrough)
  - Valid backend connects via `_connect_voice_backend(info)` -> `_voice_session.connect_to_room(url, token)` (line 121)
  - Calls `AppState.join_voice()` and `fetch.fetch_voice_states()`
- `leave_voice_channel()` (line 141):
  - Closes camera/screen tracks via `.close()`, closes all remote tracks
  - Disconnects `LiveKitAdapter` via `disconnect_voice()`, calls `VoiceApi.leave()` (best-effort, skipped if connection is down)
  - Removes self from `_voice_state_cache`, clears `_voice_server_info`
  - Clears all speaking states via `AppState.speaking_changed.emit(uid, false)`
  - Calls `AppState.leave_voice()` and emits `voice_state_updated`
- `set_voice_muted(muted)` (line 204): delegates to session and AppState
- `set_voice_deafened(deafened)` (line 208): delegates to session and AppState
- `toggle_video()` (line 214): publishes/unpublishes camera via LiveKitAdapter, reads resolution/fps/device from Config.voice
- `start_screen_share(source)` (line 250): publishes screen via LiveKitAdapter from source dict (monitor or window)
- `stop_screen_share()` (line 270): unpublishes screen, clears track
- `_send_voice_state_update()` (line 282): sends voice state update via gateway with current mute/deaf/video/screen flags

### ClientVoice Session Callbacks (client_voice.gd, lines 300-393)

- `on_session_state_changed(state)` (line 300): emits `voice_session_state_changed`, then dispatches:
  - CONNECTED: resets `_auto_reconnect_attempted` flag
  - FAILED: emits `voice_error`
  - DISCONNECTED: calls `_try_auto_reconnect()`
- `on_peer_joined(user_id)` (line 320): re-fetches voice states from server
- `on_peer_left(user_id)` (line 327): removes user from local cache, updates `voice_users` count, cleans up speaking state and remote tracks, emits `voice_state_updated`
- `on_track_removed(user_id)` (line 352): erases remote track, emits `remote_track_removed`
- `on_track_received(user_id, stream)` (line 357): stops any previous track for the same peer via `.close()`, stores in `_remote_tracks`, emits `remote_track_received`
- `on_audio_level_changed(user_id, level)` (line 370): skips if deafened; maps `@local`/`local`/`self`/empty to current user ID; uses `Config.voice.get_speaking_threshold()` for activation; triggers `speaking_changed` signal with 300ms debounce
- `_try_auto_reconnect()` (line 395): requests fresh token via `VoiceApi.join()` instead of replaying stale stored credentials; limited to one attempt via `_auto_reconnect_attempted` flag

### ClientVoice Config Change Handler (client_voice.gd, lines 462-501)

- `on_voice_config_changed(section, key)` (line 462): reacts to `config_changed` signal
  - `video_resolution`, `video_fps`, `video_device` -> `_republish_camera()` for seamless hot-swap
  - `debug_logging` -> updates `Client.debug_voice_logs` flag
- `_republish_camera()` (line 473): uses `swap_camera()` for seamless hot-swap without full disconnect

### Client Voice Data Access (client.gd)

- `_voice_state_cache: Dictionary` (line 106): maps `channel_id -> Array` of voice state dicts
- `_voice_server_info: Dictionary` (line 107): stores latest voice server connection details
- `_voice_session` (line 149): `LiveKitAdapter` on desktop/mobile, `WebVoiceSession` on web
- `_camera_track` (line 153): `LiveKitVideoStream` local camera preview
- `_screen_track` (line 154): `LiveKitVideoStream` local screen preview
- `_remote_tracks: Dictionary` (line 155): maps `user_id -> LiveKitVideoStream`
- `_speaking_users: Dictionary` (line 156): maps `user_id -> last_active timestamp` for speaking debounce
- `_speaking_timer: Timer` (line 157): 200ms interval timer that checks for 300ms silence timeouts
- Voice session created in `_ready()` (lines 196-206): `WebVoiceSession` on Web, `LiveKitAdapter` otherwise
- Session signals wired (lines 207-224): `session_state_changed`, `peer_joined`, `peer_left`, `track_received`, `track_removed`, `audio_level_changed`
- `config_changed` signal wired to `voice.on_voice_config_changed` (line 238)

### AppState Voice Signals and State (app_state.gd)

Signals:
- `voice_state_updated(channel_id)` (line 54) -- fired when voice participant list changes
- `voice_joined(channel_id)` (line 56) -- fired when local user joins voice
- `voice_left(channel_id)` (line 58) -- fired when local user leaves voice
- `voice_error(error)` (line 60) -- fired on voice connection errors
- `voice_session_state_changed(state)` (line 62) -- fired on LiveKit session state transitions
- `voice_mute_changed(is_muted)` (line 64) -- fired when mute state toggles
- `voice_deafen_changed(is_deafened)` (line 66) -- fired when deafen state toggles
- `video_enabled_changed(is_enabled)` (line 68) -- fired when camera state changes
- `screen_share_changed(is_sharing)` (line 70) -- fired when screen share state changes
- `remote_track_received(user_id, track)` (line 72) -- fired when a remote peer's video track arrives
- `remote_track_removed(user_id)` (line 74) -- fired when a remote peer's track is cleaned up
- `speaking_changed(user_id, is_speaking)` (line 76) -- fired when speaking state changes (300ms debounce)
- `voice_view_opened(channel_id)` (line 78) -- fired when voice view panel opens
- `voice_view_closed()` (line 80) -- fired when voice view panel closes
- `voice_text_opened(channel_id)` (line 82) -- fired when voice text chat opens
- `voice_text_closed()` (line 84) -- fired when voice text chat closes
- `spotlight_changed(user_id)` (line 86) -- fired when spotlight user changes

State variables:
- `voice_channel_id: String` (line 226) -- currently connected voice channel ID (empty if not in voice)
- `voice_space_id: String` (line 227) -- space of the connected voice channel
- `is_voice_muted: bool` (line 228) -- whether local user is muted
- `is_voice_deafened: bool` (line 229) -- whether local user is deafened
- `is_video_enabled: bool` (line 230) -- whether camera is active
- `is_screen_sharing: bool` (line 231) -- whether screen share is active
- `is_voice_view_open: bool` (line 232) -- whether voice view panel is visible
- `spotlight_user_id: String` (line 233) -- user being spotlighted in voice view
- `voice_text_channel_id: String` (line 237) -- channel ID for voice text chat

### ClientGatewayEvents Voice Event Handlers (client_gateway_events.gd, 330 lines)

- `on_voice_state_update(state, conn_index)` (line 181):
  - Fetches missing user from REST if not cached (lines 187-196)
  - Ensures user is in the member cache for this space, creating a stub if missing (lines 198-216)
  - Converts `AccordVoiceState` to dict via `ClientModels.voice_state_to_dict()`
  - Ignores self updates when not in voice and no backend credentials (prevents phantom join, lines 224-230)
  - Removes user from any previous channel in `_voice_state_cache` (dedup, lines 232-245)
  - Adds user to new channel, updates `voice_users` count in channel cache (lines 248-254)
  - Plays peer join/leave sound via `SoundManager` (lines 257-258)
  - Emits `AppState.voice_state_updated` for affected channels
  - Detects force-disconnect: if own user's `channel_id` becomes empty, calls `AppState.leave_voice()` (line 261)
- `on_voice_server_update(info, conn_index)` (line 264): stores `info.to_dict()` in `_voice_server_info`; if already in voice, connects backend immediately via `_connect_voice_backend()` (lines 278-280)
- `on_voice_signal(data, conn_index)` (line 282): no-op stub -- LiveKit handles all signaling internally

### ClientFetch Voice States (client_fetch.gd, line 538)

- `fetch_voice_states(channel_id)`: calls `VoiceApi.get_status()`, converts each `AccordVoiceState` via `ClientModels.voice_state_to_dict()`, stores in `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`

### AccordKit Voice API (voice_api.gd)

- `get_info() -> RestResult`: voice backend configuration
- `join(channel_id, self_mute, self_deaf) -> RestResult`: joins voice, returns `AccordVoiceServerUpdate`
- `leave(channel_id) -> RestResult`: leaves voice channel
- `list_regions(space_id) -> RestResult`: available voice regions
- `get_status(channel_id) -> RestResult`: connected users as `Array[AccordVoiceState]`

### VoiceManager (voice_manager.gd)

- Signals: `voice_connected`, `voice_disconnected`, `voice_state_changed`, `voice_server_updated`, `voice_error`
- `join(channel_id, self_mute, self_deaf)`: calls VoiceApi, stores state, emits `voice_connected`
- `leave()`: calls VoiceApi, clears state, emits `voice_disconnected`
- `is_connected_to_voice() -> bool` / `get_current_channel() -> String`
- Gateway handlers: `_on_voice_state_update()` detects forced disconnection; `_on_voice_server_update()` re-emits

### AccordVoiceServerUpdate (voice_server_update.gd)

- `backend: String` (line 11) -- "livekit" or "custom"
- `livekit_url` (line 12) -- LiveKit server URL (nullable)
- `token` (line 13) -- authentication token for voice backend (nullable)
- `sfu_endpoint` (line 14) -- SFU endpoint (nullable, legacy)
- `voice_state` (line 15) -- `AccordVoiceState`, present in REST join response, absent in gateway event

### AccordVoiceState (voice_state.gd)

- Properties: `user_id`, `space_id`, `channel_id`, `session_id`
- Mute/deaf flags: `deaf`, `mute`, `self_deaf`, `self_mute`, `self_stream` (line 14), `self_video` (line 15), `suppress`
- `from_dict()` / `to_dict()`

### Voice State Dictionary Shape (ClientModels.voice_state_to_dict)

```gdscript
{
    "user_id": String,
    "channel_id": String,
    "session_id": String,
    "self_mute": bool,
    "self_deaf": bool,
    "self_video": bool,
    "self_stream": bool,
    "mute": bool,
    "deaf": bool,
    "user": {  # from user cache, or fallback with color_from_id
        "id": String,
        "display_name": String,
        "username": String,
        "color": Color,
        "status": int,
        "avatar": Variant,
    },
}
```

### LiveKitAdapter (livekit_adapter.gd, 720 lines)

Full GDScript wrapper around the godot-livekit GDExtension. Created conditionally in `client.gd _ready()` (line 202) for non-Web platforms and added as a child node.

**Signals** (lines 8-14):
- `session_state_changed(state: int)` -- room connection state changes
- `peer_joined(user_id: String)` -- remote participant connected
- `peer_left(user_id: String)` -- remote participant disconnected
- `track_received(user_id: String, stream: RefCounted)` -- remote video track subscribed (LiveKitVideoStream)
- `track_removed(user_id: String)` -- remote video/audio track unsubscribed
- `audio_level_changed(user_id: String, level: float)` -- speaking level for a participant
- `plugin_data_received(sender_id, topic, payload)` -- data channel message from plugin

**State enum** (via `ClientModels.VoiceSessionState`): `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `RECONNECTING`, `FAILED`

**Public API**:
- `connect_to_room(url, token)` (line 57): stashes screen capture resources for reconnection, creates `LiveKitRoom`, connects all room signals (connected, disconnected, reconnecting, reconnected, participant_connected/disconnected, track_subscribed/unsubscribed, track_muted/unmuted, data_received), starts 15-second connection timeout, calls `_room.connect_to_room()` with `auto_reconnect: false`
- `disconnect_voice()` (line 91): drops all local track references (skips blocking unpublish_track() calls), closes screen capture/preview, cleans up all remote audio/video, cleans up mic capture, disconnects room
- `set_muted(muted)` (line 117): mutes/unmutes the local audio track
- `set_deafened(deafened)` (line 125): sets all remote audio players to -80dB (deafened) or 0dB (normal)
- `publish_camera(res, fps, device_id)` (line 142): creates `LiveKitVideoSource` + `LiveKitLocalVideoTrack`, sets device if available, publishes via `LiveKitLocalParticipant.publish_track()` with `SOURCE_CAMERA` and resolution-based max bitrate, returns `LiveKitVideoStream` for local preview
- `swap_camera(res, fps, device_id)` (line 185): hot-swaps camera source without tearing down the publication; falls back to full `publish_camera()` if `set_source()` is unavailable
- `unpublish_camera()` (line 212): cleans up local video track
- `publish_screen(source)` (line 215): creates `LiveKitScreenCapture` from source dict (monitor or window), publishes with `SOURCE_SCREENSHARE` and 2x bitrate for text clarity, returns `LocalVideoPreview` for local display
- `unpublish_screen()` (line 282): cleans up local screen track and capture
- `publish_plugin_data(data, reliable, topic, destination_ids)` (line 292): sends arbitrary data via LiveKit data channels for plugin communication

**Room signal handlers** (lines 376-469):
- `_on_connected()` (line 376): stops connect timer, sets CONNECTED state, auto-publishes local microphone audio via `_publish_local_audio()`, re-publishes screen share if capture survived reconnection
- `_on_connection_failed(error)` (line 386): stops timer, sets FAILED state
- `_on_participant_connected(participant)` (line 404): maps identity to user_id, emits `peer_joined`
- `_on_participant_disconnected(participant)` (line 410): cleans up remote audio/video, emits `peer_left`
- `_on_track_subscribed(track, publication, participant)` (line 418): video tracks -> `LiveKitVideoStream.from_track()` + `track_received` signal; audio tracks -> `_setup_remote_audio()`
- `_on_track_unsubscribed(track, publication, participant)` (line 433): cleans up remote video/audio, emits `track_removed` for video
- `_on_data_received(data, participant, kind, topic)` (line 459): routes `plugin:*` topics to `plugin_data_received` signal

**Local audio publishing** (lines 473-510):
- `_publish_local_audio()`: creates `LiveKitAudioSource` (at mix rate, mono, 200ms buffer), `LiveKitLocalAudioTrack`, publishes with `SOURCE_MICROPHONE`, sets up mic capture
- `_setup_mic_capture()` (line 491): cleans up stale MicCapture bus, creates AudioServer bus "MicCapture" (muted to prevent local playback), adds `AudioEffectCapture`, creates `AudioStreamPlayer` with `AudioStreamMicrophone` for local audio level detection

**Remote audio playback** (lines 531-562):
- `_setup_remote_audio(identity, track)`: creates `LiveKitAudioStream.from_track()`, `AudioStreamGenerator` at stream sample rate, `AudioStreamPlayer`, connects playback; deafen state applied immediately

**Per-frame processing** (`_process()`, line 312):
- Screen capture: synchronous `screenshot()` each frame, resize if needed, push to `_local_screen_source.capture_frame()` and update local preview
- Room event polling: `_room.poll_events()` drains thread-safe event queue on main thread
- Remote video: polls each `LiveKitVideoStream`
- Remote audio: polls `LiveKitAudioStream` into `AudioStreamGeneratorPlayback`, computes audio level from bus peak dB, emits `audio_level_changed` if above speaking threshold
- Local mic: captures frames via `AudioEffectCapture`, converts stereo to mono with input volume gain (`Config.voice.get_input_volume() / 100.0`), applies noise gate using speaking threshold, pushes to LiveKit via `capture_frame()`, emits `audio_level_changed` for local speaking detection

**Audio level estimation** (line 650): reads `AudioServer.get_bus_peak_volume_left_db()`, converts dB to linear (0..1 range, clamped)

**Connection timeout** (lines 661-681): 15-second timer; if still CONNECTING when it fires, sets FAILED state and emits `session_state_changed`

**LocalVideoPreview** inner class (lines 692-720): lightweight preview stream for local tracks; updated directly from the capture loop; RGB8↔RGBA8 round-trip to fix alpha channel issues on X11 32-bit displays; exposes `get_texture()` and `frame_received` signal for VideoTile consumption

### Voice Device Configuration (config_voice.gd, 151 lines)

Voice and video device configuration helper accessed via `Config.voice`.

- `get_input_device()` / `set_input_device()` (lines 11-22): persist mic device ID; `set_input_device()` calls `_apply_input_device()` which sets `AudioServer.input_device`
- `get_output_device()` / `set_output_device()` (lines 25-36): persist speaker device ID; `set_output_device()` calls `_apply_output_device()` which sets `AudioServer.output_device`
- `get_video_device()` / `set_video_device()` (lines 39-50): persist camera device; emits `config_changed` to trigger camera hot-swap
- `get_video_resolution()` / `set_video_resolution()` (lines 53-64): 0=480p, 1=720p, 2=1080p; emits `config_changed`
- `get_video_fps()` / `set_video_fps()` (lines 67-74): default 30; emits `config_changed`
- `get_input_sensitivity()` / `set_input_sensitivity()` (lines 77-87): 0-100 range, clamped
- `get_input_volume()` / `set_input_volume()` (lines 90-100): 0-200%, default 100
- `get_output_volume()` / `set_output_volume()` (lines 103-113): 0-200%, default 100
- `get_debug_logging()` / `set_debug_logging()` (lines 116-127): emits `config_changed`
- `get_speaking_threshold()` (line 130): logarithmic mapping from sensitivity (0%→0.1, 50%→~0.003, 100%→0.0001)
- `apply_devices()` (line 136): applies both input and output device to AudioServer

### godot-livekit GDExtension

Native binary addon wrapping the LiveKit C++ SDK for room-based voice/video. Located at `addons/godot-livekit/`.

- `godot-livekit.gdextension`: entry symbol `livekit_library_init`, minimum compatibility Godot 4.5
- Platform support: Linux x86_64, Windows x86_64, macOS universal
- Native dependencies: `liblivekit_ffi` + `liblivekit` shared libraries per platform
- Provides classes: `LiveKitRoom`, `LiveKitVideoStream`, `LiveKitAudioStream`, `LiveKitAudioSource`, `LiveKitLocalAudioTrack`, `LiveKitLocalVideoTrack`, `LiveKitVideoSource`, `LiveKitScreenCapture`, `LiveKitRemoteParticipant`, `LiveKitLocalParticipant`, `LiveKitTrack`, `LiveKitTrackPublication`, `LiveKitRemoteTrackPublication`, `LiveKitLocalTrackPublication`, `LiveKitParticipant`
- `LiveKitTrack` constants: `KIND_VIDEO`, `KIND_AUDIO`, `SOURCE_CAMERA`, `SOURCE_MICROPHONE`, `SOURCE_SCREENSHARE`

### Gateway Voice Event Dispatch (gateway_socket.gd)

- `"voice.state_update"` -> `voice_state_update.emit(AccordVoiceState.from_dict(data))`
- `"voice.server_update"` -> `voice_server_update.emit(AccordVoiceServerUpdate.from_dict(data))`
- `"voice.signal"` -> `voice_signal.emit(data)`

### Server Disconnect Voice Cleanup (client.gd)

- `disconnect_server()` checks if user is in voice on the disconnecting server (`AppState.voice_space_id == space_id`) and calls `AppState.leave_voice()`
- Erases voice state cache entries for all channels belonging to the disconnected server

### Voice Connection Indicator (user_bar.gd)

- `VoiceIndicator` Label with microphone emoji, green color, hidden by default
- `_on_voice_joined()`: sets `voice_indicator.visible = true`
- `_on_voice_left()`: sets `voice_indicator.visible = false`

## Implementation Status

- [x] Voice channels displayed in channel list with speaker icon
- [x] Dedicated voice channel scene (`voice_channel_item`) with participant list
- [x] Voice channel type recognized by ClientModels (`ChannelType.VOICE`)
- [x] Join/leave voice via REST API (`VoiceApi.join()`, `VoiceApi.leave()`)
- [x] Voice control bar with mute, deafen, cam, share, activity, sfx, settings, and disconnect buttons
- [x] Voice participant list with Avatar component, display name, and mute/deaf/video/stream indicators
- [x] Voice user count displayed on voice channel items
- [x] Green tint on voice channel icon when connected
- [x] Voice state cache in `Client` (`_voice_state_cache`)
- [x] Gateway voice event handling (`on_voice_state_update`, `on_voice_server_update`, `on_voice_signal` is a no-op stub)
- [x] Force-disconnect detection (gateway `voice_state_update` with empty `channel_id`)
- [x] Voice session management via `LiveKitAdapter` (wraps godot-livekit `LiveKitRoom`)
- [x] Mute/deafen state synced with `LiveKitAdapter` and `AppState`
- [x] Voice state fetched on join via `fetch.fetch_voice_states()`
- [x] Voice peer join/leave callbacks refresh participant state
- [x] Server disconnect cleans up voice state
- [x] AccordKit VoiceManager (connection lifecycle, signals)
- [x] Voice signaling handled internally by LiveKit (no gateway VOICE_SIGNAL needed)
- [x] Voice settings dialog for microphone device selection
- [x] Voice connection indicator on user bar (microphone emoji)
- [x] Voice participant avatars use Avatar component (circular, with initials and speaking ring)
- [x] AccordKit voice models (`AccordVoiceState`, `AccordVoiceServerUpdate`)
- [x] AccordClient `update_voice_state()` gateway opcode with `self_video`/`self_stream` params
- [x] godot-livekit GDExtension for WebRTC media (Linux, Windows, macOS)
- [x] LiveKitAdapter unit tests (state machine, mute/deafen, signals, disconnect)
- [x] Deafen silences incoming audio (remote players set to -80dB)
- [x] Received audio tracks tracked via AudioStreamGenerator playback pipeline
- [x] Output device persistence in Config (`voice.output_device`)
- [x] Speaking indicator: `audio_level_changed` signal wired from `LiveKitAdapter` to `ClientVoice`
- [x] Speaking indicator: green ring on participant avatars via `set_speaking()` / `set_ring_opacity()`
- [x] Speaking indicator: 300ms debounce timer prevents flickering during speech pauses
- [x] Speaking indicator: green border on video tiles when user is speaking
- [x] Speaking indicator: state cleared on voice leave and peer disconnect
- [x] Voice join blocked when backend credentials are missing (emits `voice_error`, no `AppState.join_voice()`)
- [x] LiveKit backend for voice (full room-based connection with audio publishing)
- [x] Voice join fallthrough bug fixed: non-`AccordVoiceServerUpdate` response emits error and returns false
- [x] Voice mutation API extracted to `ClientVoice` helper class
- [x] Local microphone auto-published on room connect via `LiveKitAudioSource`
- [x] Mic capture via AudioEffectCapture for local speaking level detection
- [x] Remote audio playback via LiveKitAudioStream -> AudioStreamGenerator -> AudioStreamPlayer
- [x] Audio level estimation from AudioServer bus peak dB
- [x] Room reconnection handling (RECONNECTING -> CONNECTED state transitions)
- [x] Async voice server update handling (connects backend if session disconnected when gateway event arrives)
- [x] Debug voice logging to `user://voice_debug.log`
- [x] Participant identity-to-user_id mapping in LiveKitAdapter
- [x] Camera and screen share publishing via LiveKitAdapter
- [x] Remote video track reception via `track_subscribed` -> `LiveKitVideoStream.from_track()`
- [x] Soundboard button in voice bar (gated on `USE_SOUNDBOARD` permission)
- [x] Settings button in voice bar (opens Voice & Video settings page)
- [x] Voice channel drag-and-drop reordering
- [x] Voice channel edit/delete context menu (gated on `MANAGE_CHANNELS`)
- [x] Auto-reconnect requests fresh token via `VoiceApi.join()` instead of replaying stale credentials
- [x] Voice session state visual feedback (Connecting/Connected/Reconnecting with pulse animation)
- [x] Voice error display in voice bar (4-second red status, then clears)
- [x] Input device applied to AudioServer via `config_voice.gd _apply_input_device()`
- [x] Output device applied to AudioServer via `config_voice.gd _apply_output_device()`
- [x] Input volume gain applied during mic capture (0-200%)
- [x] Noise gate on mic capture using speaking threshold
- [x] Camera hot-swap via `swap_camera()` without full disconnect
- [x] Screen share persistence across room reconnections (stashed capture/preview)
- [x] Connection timeout (15 seconds) for stuck CONNECTING state
- [x] Plugin data channels via `publish_plugin_data()`
- [x] Voice text chat button on voice channel items
- [x] Activity button in voice bar for plugin launch
- [x] Camera detection on Linux via `/sys/class/video4linux`
- [x] Reduce-motion support (stops pulse animation)
- [x] ClientVoice unit tests (null session, valid session, token validation, REST failure)
- [x] Voice config helper class (`config_voice.gd`) with device/volume/sensitivity/resolution/fps persistence
- [x] Speaking threshold: logarithmic mapping from sensitivity slider (0-100%)
- [x] Screen capture size capping to configurable max dimension
- [x] Bitrate hints for camera/screen publications
- [x] Web platform voice via `WebVoiceSession` (JavaScriptBridge)
- [x] Track unsubscribed handling (`track_removed` signal)
- [x] Best-effort VoiceApi.leave() on disconnect (skipped if connection is down)
- [ ] Input device routing to `AudioStreamMicrophone` at mic capture time
- [ ] Output device routing to per-peer `AudioStreamPlayer` instances
- [ ] Output volume applied to remote audio players

## Known Issues & Edge Cases

### Room Assignment (Why Users Should Always Be in the Same Room)

The LiveKit room name is **always** `"channel_{channel_id}"`, derived deterministically from the channel ID on the server (`voice/livekit.rs:34`). The room name is baked into the JWT token via `VideoGrants.room` at generation time (`livekit.rs:44-50`). Both the REST join endpoint (`routes/voice.rs:99`) and the gateway voice join handler (`gateway/mod.rs:401`) call the same `generate_token()` function with the same channel ID. The `AccordVoiceServerUpdate` model handles the REST/gateway field name difference (`livekit_url` vs `url`) via fallback at `voice_server_update.gd:25`. All users joining the same voice channel receive tokens for the same LiveKit room, and the LiveKit server enforces room membership from the token grant.

### ISSUE: `_intentional_disconnect` Flag Timing Around Async `connect_to_room()`

**Location:** `client_voice.gd:131-138`, `livekit_adapter.gd:57-89`

```
_intentional_disconnect = true          # line 134
_c._voice_session.connect_to_room(...)  # line 135 (async native call)
_intentional_disconnect = false          # line 138
```

Inside `connect_to_room()`, the old room is torn down via `disconnect_voice()` (livekit_adapter.gd:68), which synchronously emits `session_state_changed(DISCONNECTED)` (livekit_adapter.gd:114-115). Because `_intentional_disconnect` is still `true` at this point, `_try_auto_reconnect()` correctly returns early.

**However**, once `_intentional_disconnect` is set back to `false` (line 138), any subsequent DISCONNECTED signal from the **new** room's native connection attempt would trigger `_try_auto_reconnect()`. This window exists because `connect_to_room()` fires off `_room.connect_to_room()` asynchronously (livekit_adapter.gd:89) — the native LiveKit SDK connects in a background thread, and a failure callback could arrive on a later frame after the flag is already false.

**Practical risk:** Low — the DISCONNECTED callback from the new room would only fire if the connection attempt succeeds and then immediately drops. A connection failure fires `connection_failed` → FAILED state, which does NOT trigger auto-reconnect (client_voice.gd:310-314). The auto-reconnect now uses fresh tokens, mitigating the stale credential concern.

### ISSUE: Double `_connect_voice_backend()` on Gateway `voice.server_update`

**Location:** `client_voice.gd:114` and `client_gateway_events.gd:278-280`

The REST join path calls `_connect_voice_backend()` directly from `_apply_voice_server_update()` (line 114). The gateway `on_voice_server_update` handler also calls `_connect_voice_backend()` whenever `voice_channel_id` is non-empty (lines 278-280).

**In normal operation, this does NOT double-fire.** The REST `join_voice` endpoint (`routes/voice.rs`) does not send a `voice.server_update` via the gateway — it only broadcasts `voice.state_update` and returns the token in the REST response. The gateway only sends `voice.server_update` when a join is initiated via gateway opcode 9 (VOICE_STATE_UPDATE), which the client only uses for flag-only updates (video/screen state) via `_send_voice_state_update()`. Since those are same-channel updates, the server's `is_same_channel` check (`gateway/mod.rs:322`) skips the `voice.server_update`.

**When double-fire could occur:**
- If a server-side mechanism (admin move, load balancer migration) sends a `voice.server_update` while the user is already connected. This is actually correct behavior — the gateway handler tears down and reconnects with fresh credentials.
- If a gateway reconnect replays a queued `voice.server_update` after the REST join already connected. This would cause a brief disconnect/reconnect cycle but end in the correct room.

### Join Flow: REST-Only Token Path

For clarity, the normal voice join uses **only** the REST response for the LiveKit token:

```
Client                          Server                      LiveKit
  |                                |                            |
  | POST /channels/{id}/voice/join |                            |
  |------------------------------->|                            |
  |                                | join_voice_channel()       |
  |                                | ensure_room()              |
  |                                |--------------------------->|
  |                                | generate_token()           |
  |                                |  room = "channel_{id}"     |
  |                                |                            |
  |    REST response               |                            |
  |    {livekit_url, token}        |                            |
  |<-------------------------------|                            |
  |                                |                            |
  | _connect_voice_backend()       |                            |
  | LiveKitAdapter.connect_to_room(url, token)                  |
  |------------------------------------------------------------>|
  |                                |                            |
  |                                | broadcast voice.state_update
  |                                | (NO voice.server_update)   |
  |    gateway: voice.state_update |                            |
  |<-------------------------------|                            |
  |    (updates cache only,        |                            |
  |     does NOT reconnect)        |                            |
```

The gateway `voice.server_update` event is reserved for:
1. Server-initiated reconnection (e.g., LiveKit server migration)
2. Joins initiated via gateway opcode 9 (currently unused for initial joins)

## Tasks

### VOICE-1: No server-side validation/tests for voice join payloads
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** config, testing, voice
- **Notes:** Add server tests that assert `voice/join` returns credentials for configured backends.

### VOICE-2: Input device not routed to AudioStreamMicrophone at capture time
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** audio, config, voice
- **Notes:** `Config.voice.set_input_device()` correctly sets `AudioServer.input_device` (config_voice.gd:144), which affects the global default input. However, `_setup_mic_capture()` (livekit_adapter.gd:507) creates `AudioStreamMicrophone.new()` without explicitly verifying that the selected device is active. The AudioServer property approach works when only one audio subsystem is consuming the mic, but if a future change adds a second consumer, per-stream device routing would be needed.

### VOICE-3: Output device not routed to per-peer AudioStreamPlayers
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** audio, config, voice
- **Notes:** `Config.voice.set_output_device()` sets `AudioServer.output_device` (config_voice.gd:150) which affects the global output. However, remote audio `AudioStreamPlayer` instances (livekit_adapter.gd:537-542) play on the default bus without applying `Config.voice.get_output_volume()`. The output volume (0-200%) is persisted but never applied to remote player `volume_db`.

### VOICE-5: `_intentional_disconnect` flag does not cover async connection failures
- **Status:** open
- **Impact:** 1
- **Effort:** 1
- **Tags:** voice, reliability
- **Notes:** The flag is set/unset synchronously around an async `connect_to_room()` call (client_voice.gd:134-138). A native DISCONNECTED callback from the new room arriving after the flag is cleared could trigger auto-reconnect. Low practical risk since connection failures fire FAILED (not DISCONNECTED). See "ISSUE: `_intentional_disconnect` Flag Timing" above.
