# Voice Channels


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
11. Voice bar appears at the bottom of the channel panel showing the channel name, green status dot, and mute/deafen/cam/share/sfx/settings/disconnect buttons
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
     |                              |<- join_voice(id, guild_id) --|
     |                              |                              |-- fetch.fetch_voice_states(id)
     |                              |                              |
     |<-- voice_joined(id) --------|                              |
     |   (refresh participants)     |                              |
     |                              |                              |
voice_bar.gd                       |                              |
     |<-- voice_joined(id) --------|                              |
     |   (show bar, channel name)   |                              |
     |                              |                              |
     |-- mute_btn pressed -------->|                              |
     |                              |<- set_voice_muted(bool) ----|
     |<-- voice_mute_changed -------|   (session.set_muted())     |
     |   (update button visual)     |                              |
     |                              |                              |
     |-- disconnect_btn pressed -->|                              |
     |                              |-- leave_voice_channel() --->|
     |                              |                              |-- VoiceApi.leave(id)
     |                              |                              |-- session.disconnect_voice()
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
     |                              |       -> updates cache        |
     |                              |       -> voice_state_updated  |
     |                              |     on_voice_server_update    |
     |                              |       -> stores info          |
     |                              |       -> connects backend if  |
     |                              |          session disconnected |
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
| `scenes/sidebar/channels/voice_channel_item.gd` | Dedicated voice channel scene: participant list with Avatar components, mute/deaf/video/stream indicators, speaking rings, user count, green tint when connected |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene (VBoxContainer with ChannelButton + ParticipantContainer) |
| `scenes/sidebar/voice_bar.gd` | Voice control bar: mute/deafen/cam/share/sfx/settings/disconnect buttons, channel name, green status dot |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene (PanelContainer with StatusRow + ButtonRow) |
| `scenes/sidebar/channels/channel_list.gd` | Instantiates `VoiceChannelItemScene` for VOICE channels, `ChannelItemScene` for others |
| `scenes/sidebar/channels/category_item.gd` | Also instantiates `VoiceChannelItemScene` for voice channels within categories |
| `scenes/sidebar/channels/channel_item.gd` | Generic channel item; still handles VOICE type icon and voice_users count |
| `scenes/sidebar/user_bar.gd` | Voice connection indicator (microphone emoji label, line 13) shown/hidden via `voice_joined`/`voice_left` (lines 112-116) |
| `scenes/sidebar/user_bar.tscn` | VoiceIndicator Label node in HBox (line 52) |
| `scripts/autoload/app_state.gd` | Voice signals: `voice_joined` (line 54), `voice_left` (line 56), `voice_state_updated` (line 52), `voice_error` (line 58), `voice_mute_changed` (line 60), `voice_deafen_changed` (line 62), `speaking_changed` (line 72); state vars (lines 160-165); methods (lines 260-290) |
| `scripts/autoload/client.gd` | Delegates voice to `ClientVoice`; creates `LiveKitAdapter` in `_ready()` (line 156); wires all session signals (lines 158-172); speaking debounce timer (lines 176-180); data access delegation (lines 408-416) |
| `scripts/autoload/client_voice.gd` | `ClientVoice` helper class: `join_voice_channel()` (line 26), `leave_voice_channel()` (line 127), `set_voice_muted()` (line 179), `set_voice_deafened()` (line 183); session callbacks (lines 263-344); backend validation (line 361) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` fetches connected users for a channel via `VoiceApi.get_status()` (line 476) |
| `scripts/autoload/client_gateway.gd` | Voice gateway signal connections (lines 89-94) |
| `scripts/autoload/client_gateway_events.gd` | Gateway voice event handlers: `on_voice_state_update` (line 89), `on_voice_server_update` (line 140), `on_voice_signal` (line 159, no-op stub) |
| `scripts/autoload/client_models.gd` | `ChannelType.VOICE` enum (line 7); `voice_state_to_dict()` conversion (line 535) |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_info()`, `list_regions()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking, signals |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState` model (user_id, channel_id, mute, deaf, self_video, self_stream flags) |
| `addons/accordkit/models/voice_server_update.gd` | `AccordVoiceServerUpdate` model (backend type, LiveKit URL, token, SFU endpoint) |
| `addons/accordkit/gateway/gateway_socket.gd` | `voice_state_update`, `voice_server_update`, `voice_signal` signals; dispatch; `update_voice_state()` with video/stream params |
| `addons/accordkit/core/accord_client.gd` | Exposes `voice: VoiceApi` (line 107), `voice_manager: VoiceManager` (line 109); `update_voice_state()` (line 165) with `self_video`/`self_stream` params |
| `addons/godot-livekit/` | godot-livekit GDExtension: LiveKitRoom, LiveKitVideoStream, LiveKitAudioStream, LiveKitAudioSource, LiveKitLocalAudioTrack, LiveKitLocalVideoTrack, LiveKitVideoSource for WebRTC media |
| `scripts/autoload/livekit_adapter.gd` | LiveKitAdapter GDScript wrapper: room management, local audio/video/screen publishing, remote audio playback via AudioStreamGenerator, remote video via LiveKitVideoStream, mic capture via AudioEffectCapture, audio level detection |
| `tests/livekit/unit/test_livekit_adapter.gd` | LiveKitAdapter unit tests (state machine, mute/deafen, signals, disconnect) |

### godot-livekit GDExtension Files

| File | Role |
|------|------|
| `addons/godot-livekit/bin/` | Platform-specific native binaries (Linux, Windows, macOS) + LiveKit FFI shared libraries |
| `addons/godot-livekit/godot-livekit.gdextension` | GDExtension configuration: entry symbol, platform library paths, native dependencies |

## Implementation Details

### Voice Channel Item (voice_channel_item.gd)

Dedicated scene for voice channels (distinct from `channel_item.gd`). Used by both `channel_list.gd` and `category_item.gd` when the channel type is `ChannelType.VOICE`.

- `channel_pressed` signal emitted when the channel button is clicked (line 3)
- Listens to `AppState.voice_state_updated`, `voice_joined`, `voice_left`, `speaking_changed` (lines 33-36)
- `setup(data)` initializes from channel dict, sets voice icon, creates gear button if `MANAGE_CHANNELS` permission, calls `_refresh_participants()` (line 54)
- `set_active()` is a no-op -- voice channels don't have persistent active state, but the method exists for polymorphism with `channel_item` (line 79)
- `_refresh_participants()` (line 96):
  - Reads `Client.get_voice_users(channel_id)` for current voice state dicts
  - Shows user count label when count > 0
  - Green tint `(0.231, 0.647, 0.365)` on icon and white text when the local user is connected to this channel (line 113)
  - Builds per-participant rows with: 28px indent spacer, 18x18 Avatar component (with letter and color), 6px gap, display name label (12px, gray), red "M" or "D" indicator for self_mute/self_deaf, green "V" for self_video, blue "S" for self_stream (lines 121-202)
  - Tracks participant Avatar nodes in `_participant_avatars` dictionary for speaking state updates (line 149)
  - Applies current speaking state on rebuild via `Client.is_user_speaking()` -> `av.set_ring_opacity(1.0)` (lines 150-151)
- `_on_speaking_changed(user_id, is_speaking)` (line 204): updates Avatar speaking ring animation for the affected participant
- Gear button + context menu for channel edit/delete (requires `MANAGE_CHANNELS` permission) (lines 62-75)
- Drag-and-drop reordering within the same guild (lines 257-314)

### Voice Bar (voice_bar.gd)

Bottom panel in the channel sidebar that appears when connected to voice. Instanced in `sidebar.tscn` as a child of `ChannelPanel` (node name `VoiceBar`).

- Hidden by default (`visible = false`, line 20)
- Connects to `AppState.voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed`, `video_enabled_changed`, `screen_share_changed` (lines 28-33)
- `_on_voice_joined()` (line 35): shows bar, looks up channel name from `Client.get_channels_for_guild()`, sets green status dot color `(0.231, 0.647, 0.365)`, checks `USE_SOUNDBOARD` permission for SFX button visibility
- `_on_voice_left()` (line 52): hides bar, closes soundboard panel
- Button handlers:
  - Mute (line 56): `Client.set_voice_muted(not AppState.is_voice_muted)`
  - Deafen (line 59): `Client.set_voice_deafened(not AppState.is_voice_deafened)`
  - Video (line 62): `Client.toggle_video()`
  - Share (line 65): opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`
  - SFX (line 78): opens/closes soundboard panel, gated on `USE_SOUNDBOARD` permission
  - Settings (line 100): opens User Settings on page 2 (Voice & Video)
  - Disconnect (line 105): `Client.leave_voice_channel()`
- `_update_button_visuals()` (line 120): toggles button text ("Mic" / "Mic Off", "Cam" / "Cam On", "Share" / "Sharing") and applies red/green-tinted `StyleBoxFlat` background when active

### ClientVoice Voice Mutation API (client_voice.gd, 387 lines)

Extracted helper class (`ClientVoice extends RefCounted`). Instantiated by `Client._ready()` with a reference to the Client autoload node.

- `join_voice_channel(channel_id)` (line 26):
  - Returns early if already in this channel
  - Leaves current voice channel if in one (awaits `leave_voice_channel()`)
  - Calls `VoiceApi.join()` with current mute/deaf state
  - Validates `AccordVoiceServerUpdate` via `_validate_backend_info()`:
    - Requires non-empty `livekit_url` and `token` (line 370)
    - Missing credentials emits `voice_error`, calls leave on server, cleans up state via `_cleanup_failed_join_state()`, and returns `false`
  - If result data is not `AccordVoiceServerUpdate`, emits `voice_error` and returns `false` (no fallthrough)
  - Valid backend connects via `_connect_voice_backend(info)` -> `_voice_session.connect_to_room(url, token)` (line 123)
  - Calls `AppState.join_voice()` and `fetch.fetch_voice_states()`
- `leave_voice_channel()` (line 127):
  - Closes camera/screen tracks via `.close()`, closes all remote tracks
  - Disconnects `LiveKitAdapter` via `disconnect_voice()`, calls `VoiceApi.leave()`
  - Removes self from `_voice_state_cache`, clears `_voice_server_info`
  - Clears all speaking states via `AppState.speaking_changed.emit(uid, false)`
  - Calls `AppState.leave_voice()` and emits `voice_state_updated`
- `set_voice_muted(muted)` (line 179): delegates to session and AppState
- `set_voice_deafened(deafened)` (line 183): delegates to session and AppState

### ClientVoice Session Callbacks (client_voice.gd, lines 263-344)

- `on_session_state_changed(state)` (line 263): emits `voice_error` on FAILED state
- `on_peer_joined(user_id)` (line 273): re-fetches voice states from server
- `on_peer_left(user_id)` (line 280): removes user from local cache, updates `voice_users` count, cleans up speaking state and remote tracks via `.close()`, emits `voice_state_updated`
- `on_track_received(user_id, stream)` (line 308): stops any previous track for the same peer via `.close()`, stores in `_remote_tracks`, emits `remote_track_received`
- `on_audio_level_changed(user_id, level)` (line 321): skips if deafened; maps `@local`/`local`/`self`/empty to current user ID; triggers `speaking_changed` signal with 300ms debounce
- (No `on_signal_outgoing` -- LiveKit handles signaling internally)

### Client Voice Data Access (client.gd)

- `_voice_state_cache: Dictionary` (line 90): maps `channel_id -> Array` of voice state dicts
- `_voice_server_info: Dictionary` (line 91): stores latest voice server connection details
- `_voice_session: LiveKitAdapter` (line 122): the active voice connection adapter
- `_speaking_users: Dictionary` (line 129): maps `user_id -> last_active timestamp` for speaking debounce
- `_speaking_timer: Timer` (line 130): 200ms interval timer that checks for 300ms silence timeouts
- `get_voice_users(channel_id) -> Array` (line 408): delegates to `voice.get_voice_users()`
- `get_voice_user_count(channel_id) -> int` (line 411): delegates to `voice.get_voice_user_count()`
- `is_user_speaking(user_id) -> bool` (line 414): checks `_speaking_users` dictionary
- `_check_speaking_timeouts()` (line 417): iterates `_speaking_users`, emits `speaking_changed(uid, false)` for any user silent > 300ms

### AppState Voice Signals and State (app_state.gd)

Signals:
- `voice_state_updated(channel_id)` (line 52) -- fired when voice participant list changes
- `voice_joined(channel_id)` (line 54) -- fired when local user joins voice
- `voice_left(channel_id)` (line 56) -- fired when local user leaves voice
- `voice_error(error)` (line 58) -- fired on voice connection errors
- `voice_mute_changed(is_muted)` (line 60) -- fired when mute state toggles
- `voice_deafen_changed(is_deafened)` (line 62) -- fired when deafen state toggles
- `video_enabled_changed(is_enabled)` (line 64) -- fired when camera state changes
- `screen_share_changed(is_sharing)` (line 66) -- fired when screen share state changes
- `remote_track_received(user_id, track)` (line 68) -- fired when a remote peer's video track arrives
- `remote_track_removed(user_id)` (line 70) -- fired when a remote peer's track is cleaned up
- `speaking_changed(user_id, is_speaking)` (line 72) -- fired when speaking state changes (300ms debounce)

State variables:
- `voice_channel_id: String` (line 160) -- currently connected voice channel ID (empty if not in voice)
- `voice_guild_id: String` (line 161) -- guild of the connected voice channel
- `is_voice_muted: bool` (line 162) -- whether local user is muted
- `is_voice_deafened: bool` (line 163) -- whether local user is deafened
- `is_video_enabled: bool` (line 164) -- whether camera is active
- `is_screen_sharing: bool` (line 165) -- whether screen share is active

Methods:
- `join_voice(channel_id, guild_id)` (line 260) -- sets state vars, emits `voice_joined`
- `leave_voice()` (line 265) -- clears state vars, resets mute/deaf/video/screen, emits `voice_left`
- `set_voice_muted(muted)` (line 276) / `set_voice_deafened(deafened)` (line 280) -- update flags, emit change signals
- `set_video_enabled(enabled)` (line 284) / `set_screen_sharing(sharing)` (line 288) -- update flags, emit change signals

### ClientGatewayEvents Voice Event Handlers (client_gateway_events.gd)

- `on_voice_state_update(state, conn_index)` (line 89):
  - Converts `AccordVoiceState` to dict via `ClientModels.voice_state_to_dict()`
  - Ignores self updates when not in voice and no backend credentials (prevents phantom join, lines 99-106)
  - Removes user from any previous channel in `_voice_state_cache` (dedup, lines 108-121)
  - Adds user to new channel, updates `voice_users` count in channel cache (lines 124-130)
  - Plays peer join/leave sound via `SoundManager` (lines 133-134)
  - Emits `AppState.voice_state_updated` for affected channels
  - Detects force-disconnect: if own user's `channel_id` becomes empty, calls `AppState.leave_voice()` (line 137)
- `on_voice_server_update(info, conn_index)` (line 140): stores `info.to_dict()` in `_voice_server_info`; if already in voice with a disconnected session, connects backend immediately via `_connect_voice_backend()` (lines 152-157)
- `on_voice_signal(data, conn_index)` (line 159): no-op stub -- LiveKit handles all signaling internally

### ClientFetch Voice States (client_fetch.gd, line 476)

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

### LiveKitAdapter (livekit_adapter.gd, 409 lines)

Full GDScript wrapper around the godot-livekit GDExtension. Created unconditionally in `client.gd _ready()` (line 156) and added as a child node.

**Signals** (lines 9-13):
- `session_state_changed(state: int)` -- room connection state changes
- `peer_joined(user_id: String)` -- remote participant connected
- `peer_left(user_id: String)` -- remote participant disconnected
- `track_received(user_id: String, stream: RefCounted)` -- remote video track subscribed (LiveKitVideoStream)
- `audio_level_changed(user_id: String, level: float)` -- speaking level for a participant

**State enum** (lines 16-22): `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `RECONNECTING`, `FAILED`

**Public API**:
- `connect_to_room(url, token)` (line 56): creates `LiveKitRoom`, connects all room signals (connected, disconnected, reconnecting, reconnected, participant_connected/disconnected, track_subscribed/unsubscribed, track_muted/unmuted), calls `_room.connect_to_room()`
- `disconnect_voice()` (line 74): cleans up all local tracks (audio/video/screen), all remote tracks (audio/video), mic capture bus, disconnects room
- `set_muted(muted)` (line 86): mutes/unmutes the local audio track
- `set_deafened(deafened)` (line 94): sets all remote audio players to -80dB (deafened) or 0dB (normal)
- `publish_camera(res: Vector2i, fps: int) -> RefCounted` (line 111): creates `LiveKitVideoSource` + `LiveKitLocalVideoTrack`, publishes via `LiveKitLocalParticipant.publish_track()` with `SOURCE_CAMERA`, returns `LiveKitVideoStream` for local preview
- `unpublish_camera()` (line 131): cleans up local video track
- `publish_screen() -> RefCounted` (line 134): creates screen source at 1920x1080, publishes with `SOURCE_SCREENSHARE`, returns `LiveKitVideoStream`
- `unpublish_screen()` (line 154): cleans up local screen track

**Room signal handlers** (lines 200-269):
- `_on_connected()` (line 200): sets CONNECTED state, auto-publishes local microphone audio via `_publish_local_audio()`
- `_on_participant_connected(participant)` (line 218): maps identity to user_id, emits `peer_joined`
- `_on_participant_disconnected(participant)` (line 224): cleans up remote audio/video, emits `peer_left`
- `_on_track_subscribed(track, publication, participant)` (line 232): video tracks -> `LiveKitVideoStream.from_track()` + `track_received` signal; audio tracks -> `_setup_remote_audio()`

**Local audio publishing** (lines 273-314):
- `_publish_local_audio()`: creates `LiveKitAudioSource` (48kHz, mono), `LiveKitLocalAudioTrack`, publishes with `SOURCE_MICROPHONE`, sets up mic capture
- `_setup_mic_capture()`: creates AudioServer bus "MicCapture" (muted to prevent local playback), adds `AudioEffectCapture`, creates `AudioStreamPlayer` with `AudioStreamMicrophone` for local audio level detection

**Remote audio playback** (lines 318-349):
- `_setup_remote_audio(identity, track)`: creates `LiveKitAudioStream.from_track()`, `AudioStreamGenerator` at stream sample rate, `AudioStreamPlayer`, connects playback; deafen state applied immediately
- Per-frame `_process()` (line 159): polls remote video streams, polls remote audio into `AudioStreamGeneratorPlayback`, computes audio levels from bus peak dB, computes local mic level via `AudioEffectCapture`

**Audio level estimation** (line 397): reads `AudioServer.get_bus_peak_volume_left_db()`, converts dB to linear (0..1 range, clamped)

### godot-livekit GDExtension

Native binary addon wrapping the LiveKit C++ SDK for room-based voice/video. Located at `addons/godot-livekit/`.

- `godot-livekit.gdextension`: entry symbol `livekit_library_init`, minimum compatibility Godot 4.5
- Platform support: Linux x86_64, Windows x86_64, macOS universal
- Native dependencies: `liblivekit_ffi` + `liblivekit` shared libraries per platform
- Provides classes: `LiveKitRoom`, `LiveKitVideoStream`, `LiveKitAudioStream`, `LiveKitAudioSource`, `LiveKitLocalAudioTrack`, `LiveKitLocalVideoTrack`, `LiveKitVideoSource`, `LiveKitRemoteParticipant`, `LiveKitLocalParticipant`, `LiveKitTrack`, `LiveKitTrackPublication`, `LiveKitRemoteTrackPublication`, `LiveKitLocalTrackPublication`, `LiveKitParticipant`
- `LiveKitTrack` constants: `KIND_VIDEO`, `KIND_AUDIO`, `SOURCE_CAMERA`, `SOURCE_MICROPHONE`, `SOURCE_SCREENSHARE`

### Gateway Voice Event Dispatch (gateway_socket.gd)

- `"voice.state_update"` -> `voice_state_update.emit(AccordVoiceState.from_dict(data))`
- `"voice.server_update"` -> `voice_server_update.emit(AccordVoiceServerUpdate.from_dict(data))`
- `"voice.signal"` -> `voice_signal.emit(data)`

### Server Disconnect Voice Cleanup (client.gd)

- `disconnect_server()` checks if user is in voice on the disconnecting server (`AppState.voice_guild_id == guild_id`) and calls `AppState.leave_voice()`
- Erases voice state cache entries for all channels belonging to the disconnected server

### Voice Connection Indicator (user_bar.gd)

- `VoiceIndicator` Label with microphone emoji, green color, hidden by default (line 22)
- `_on_voice_joined()` (line 112): sets `voice_indicator.visible = true`
- `_on_voice_left()` (line 115): sets `voice_indicator.visible = false`

## Implementation Status

- [x] Voice channels displayed in channel list with speaker icon
- [x] Dedicated voice channel scene (`voice_channel_item`) with participant list
- [x] Voice channel type recognized by ClientModels (`ChannelType.VOICE`)
- [x] Join/leave voice via REST API (`VoiceApi.join()`, `VoiceApi.leave()`)
- [x] Voice control bar with mute, deafen, cam, share, sfx, settings, and disconnect buttons
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

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side validation/tests for voice join payloads | Low | Add server tests that assert `voice/join` returns credentials for configured backends. |
| No input device selection applied at connect time | Low | `Config.voice.get_input_device()` is persisted but LiveKitAdapter always creates a default `AudioStreamMicrophone`. Need to route selected device to LiveKit audio source. |
| No output device selection applied at connect time | Low | `Config.voice.get_output_device()` is persisted but remote audio players use the default bus. Need to route to the selected output device. |
