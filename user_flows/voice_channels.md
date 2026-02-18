# Voice Channels

## Overview

Voice channels allow users to join real-time audio conversations within a server. The client displays voice channels with a dedicated scene (`voice_channel_item`), shows connected participants with mute/deaf indicators, and provides a voice control bar with mute, deafen, and disconnect buttons. AccordKit provides the REST API (join, leave, status), VoiceManager for connection lifecycle, and gateway event handling. AccordStream is a GDExtension addon providing WebRTC peer connections and media track management. The `Client` autoload routes voice state through `AppState` signals and manages an `AccordVoiceSession` for the active voice connection.

## User Steps

1. User sees voice channels in the channel list (speaker icon, distinct from text channels)
2. User clicks a voice channel to join
3. `Client.join_voice_channel()` calls `VoiceApi.join()` on the server, receives backend connection info
4. If backend is LiveKit: connects via `AccordVoiceSession.connect_livekit()`; if custom SFU: connects via `AccordVoiceSession.connect_custom_sfu()`
5. Voice bar appears at the bottom of the channel panel showing the channel name, green status dot, and mute/deafen/disconnect buttons
6. The voice channel item shows connected participants with avatar, display name, and mute (M) / deaf (D) indicators
7. User can click Mic to toggle mute, Deaf to toggle deafen, or Disconnect to leave
8. On disconnect, `Client.leave_voice_channel()` calls `VoiceApi.leave()`, disconnects the voice session, and hides the voice bar

## Signal Flow

```
voice_channel_item.gd          AppState                    Client / AccordKit
     |                              |                              |
     |-- channel_pressed(id) ------>|                              |
     |                              |                              |
     |            channel_list._on_channel_pressed(id)             |
     |                              |-- join_voice_channel(id) --->|
     |                              |                              |-- VoiceApi.join(id)
     |                              |                              |-- AccordVoiceSession.connect_*()
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
     |                              |   ClientGateway handles:     |
     |                              |     on_voice_state_update     |
     |                              |       -> updates cache        |
     |                              |       -> voice_state_updated  |
     |                              |     on_voice_server_update    |
     |                              |       -> stores info          |
     |                              |     on_voice_signal           |
     |                              |       -> forwards to session  |
     |                              |                              |
     |<-- voice_state_updated ------|                              |
     |   (refresh participants)     |                              |
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/voice_channel_item.gd` | Dedicated voice channel scene: participant list with mute/deaf indicators, user count, green tint when connected |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene (VBoxContainer with ChannelButton + ParticipantContainer) |
| `scenes/sidebar/voice_bar.gd` | Voice control bar: mute/deafen/disconnect buttons, channel name, green status dot |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene (PanelContainer with StatusRow + ButtonRow) |
| `scenes/sidebar/channels/channel_list.gd` | Instantiates `VoiceChannelItemScene` for VOICE channels, `ChannelItemScene` for others (lines 108-113) |
| `scenes/sidebar/channels/category_item.gd` | Also instantiates `VoiceChannelItemScene` for voice channels within categories (lines 58-61) |
| `scenes/sidebar/channels/channel_item.gd` | Generic channel item; still handles VOICE type icon and voice_users count (lines 42-69) |
| `scripts/autoload/app_state.gd` | Voice signals and state: `voice_joined`, `voice_left`, `voice_state_updated`, `voice_error`, `voice_mute_changed`, `voice_deafen_changed` (lines 46-56); state vars (lines 96-99); methods (lines 183-203) |
| `scripts/autoload/client.gd` | Voice mutation API: `join_voice_channel()`, `leave_voice_channel()`, `set_voice_muted()`, `set_voice_deafened()` (lines 726-808); voice data access (lines 473-477); voice session callbacks (lines 1079-1127); caches (lines 41-42) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` fetches connected users for a channel via `VoiceApi.get_status()` (lines 323-355) |
| `scripts/autoload/client_gateway.gd` | Gateway voice event handlers: `on_voice_state_update`, `on_voice_server_update`, `on_voice_signal` (lines 387-433) |
| `scripts/autoload/client_models.gd` | `ChannelType.VOICE` enum (line 7); `voice_state_to_dict()` conversion (lines 465-492); `voice_users: 0` field in `channel_to_dict()` (line 208) |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_info()`, `list_regions()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking, signals |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState` model (user_id, channel_id, mute, deaf flags) |
| `addons/accordkit/models/voice_server_update.gd` | `AccordVoiceServerUpdate` model (backend type, LiveKit URL, token, SFU endpoint) |
| `addons/accordkit/gateway/gateway_socket.gd` | `voice_state_update`, `voice_server_update`, `voice_signal` signals (lines 52-54); dispatch (lines 329-334) |
| `addons/accordkit/core/accord_client.gd` | Exposes `voice: VoiceApi` (line 105), `voice_manager: VoiceManager` (line 106); re-emits gateway voice signals (lines 212-214); `update_voice_state()` gateway opcode (lines 161-164) |
| `addons/accordstream/` | GDExtension binary for WebRTC peer connections and media tracks |
| `tests/accordstream/integration/test_voice_session.gd` | AccordVoiceSession unit tests (state, mute/deafen, signals, connect/disconnect) |

## Implementation Details

### Voice Channel Item (voice_channel_item.gd, 122 lines)

Dedicated scene for voice channels (distinct from `channel_item.gd`). Used by both `channel_list.gd` (line 111) and `category_item.gd` (line 61) when the channel type is `ChannelType.VOICE`.

- `channel_pressed` signal (line 3) emitted when the channel button is clicked
- Listens to `AppState.voice_state_updated`, `voice_joined`, `voice_left` (lines 19-21)
- `setup(data)` (line 23) initializes from channel dict, sets voice icon, calls `_refresh_participants()`
- `set_active()` (line 32) is a no-op -- voice channels don't have persistent active state, but the method exists for polymorphism with `channel_item`
- `_refresh_participants()` (lines 49-121):
  - Reads `Client.get_voice_users(channel_id)` for current voice state dicts
  - Shows user count label when count > 0 (lines 58-62)
  - Green tint on icon and white text when the local user is connected to this channel (lines 64-70)
  - Builds per-participant rows with: 28px indent spacer, 18x18 ColorRect avatar (using user's color), display name label (12px, gray), and red "M" or "D" indicator for self_mute/self_deaf (lines 72-121)

### Voice Bar (voice_bar.gd, 78 lines)

Bottom panel in the channel sidebar that appears when connected to voice. Instanced in `sidebar.tscn` as a child of `ChannelPanel` (node name `VoiceBar`).

- Hidden by default (`visible = false`, line 10)
- Connects to `AppState.voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed` (lines 14-17)
- `_on_voice_joined()` (lines 19-30): shows bar, looks up channel name from `Client.get_channels_for_guild()`, sets green status dot color `(0.231, 0.647, 0.365)`
- `_on_voice_left()` (line 32-33): hides bar
- Button handlers delegate to `Client`: `set_voice_muted()` (line 36), `set_voice_deafened()` (line 39), `leave_voice_channel()` (line 42)
- `_update_button_visuals()` (lines 50-77): toggles button text ("Mic" / "Mic Off", "Deaf") and applies red-tinted `StyleBoxFlat` background when active

### Client Voice Mutation API (client.gd, lines 726-808)

- `join_voice_channel(channel_id)` (lines 726-771):
  - Returns early if already in this channel
  - Leaves current voice channel if in one (awaits `leave_voice_channel()`)
  - Calls `VoiceApi.join()` with current mute/deaf state
  - Parses `AccordVoiceServerUpdate` response: connects to LiveKit or custom SFU via `AccordVoiceSession`
  - For custom SFU: picks the first available microphone from `AccordStream.get_microphones()`
  - Calls `AppState.join_voice()` and `fetch.fetch_voice_states()`
- `leave_voice_channel()` (lines 773-800):
  - Disconnects `AccordVoiceSession`, calls `VoiceApi.leave()`
  - Removes self from `_voice_state_cache`, clears `_voice_server_info`
  - Calls `AppState.leave_voice()` and emits `voice_state_updated`
- `set_voice_muted(muted)` (lines 802-804): delegates to session and AppState
- `set_voice_deafened(deafened)` (lines 806-808): delegates to session and AppState

### Client Voice Session Callbacks (client.gd, lines 1079-1127)

- `_on_voice_session_state_changed()` (lines 1079-1085): emits `voice_error` on FAILED state
- `_on_voice_peer_joined()` (lines 1087-1093): re-fetches voice states from server
- `_on_voice_peer_left()` (lines 1095-1109): removes user from local cache, updates `voice_users` count, emits `voice_state_updated`
- `_on_voice_signal_outgoing()` (lines 1111-1127): logs outgoing voice signals (gateway raw_send not yet connected)

### Client Voice Data Access (client.gd, lines 471-477)

- `_voice_state_cache: Dictionary` (line 41): maps `channel_id -> Array` of voice state dicts
- `_voice_server_info: Dictionary` (line 42): stores latest voice server connection details
- `get_voice_users(channel_id) -> Array` (lines 473-474)
- `get_voice_user_count(channel_id) -> int` (lines 476-477)

### AppState Voice Signals and State (app_state.gd)

Signals (lines 46-56):
- `voice_state_updated(channel_id)` -- fired when voice participant list changes
- `voice_joined(channel_id)` -- fired when local user joins voice
- `voice_left(channel_id)` -- fired when local user leaves voice
- `voice_error(error)` -- fired on voice connection errors
- `voice_mute_changed(is_muted)` -- fired when mute state toggles
- `voice_deafen_changed(is_deafened)` -- fired when deafen state toggles

State variables (lines 96-99):
- `voice_channel_id: String` -- currently connected voice channel ID (empty if not in voice)
- `voice_guild_id: String` -- guild of the connected voice channel
- `is_voice_muted: bool` -- whether local user is muted
- `is_voice_deafened: bool` -- whether local user is deafened

Methods (lines 183-203):
- `join_voice(channel_id, guild_id)` -- sets state vars, emits `voice_joined`
- `leave_voice()` -- clears state vars, resets mute/deaf, emits `voice_left`
- `set_voice_muted(muted)` / `set_voice_deafened(deafened)` -- update flags, emit change signals

### ClientGateway Voice Event Handlers (client_gateway.gd, lines 387-433)

- `on_voice_state_update(state, conn_index)` (lines 387-419):
  - Converts `AccordVoiceState` to dict via `ClientModels.voice_state_to_dict()`
  - Removes user from any previous channel in `_voice_state_cache` (dedup)
  - Adds user to new channel, updates `voice_users` count in channel cache
  - Emits `AppState.voice_state_updated` for affected channels
  - Detects force-disconnect: if own user's `channel_id` becomes empty, calls `AppState.leave_voice()`
- `on_voice_server_update(info, conn_index)` (lines 421-424): stores `info.to_dict()` in `_voice_server_info`
- `on_voice_signal(data, conn_index)` (lines 426-433): forwards to `AccordVoiceSession.handle_voice_signal()` with user_id, signal_type, and payload

### ClientFetch Voice States (client_fetch.gd, lines 323-355)

- `fetch_voice_states(channel_id)`: calls `VoiceApi.get_status()`, converts each `AccordVoiceState` via `ClientModels.voice_state_to_dict()`, stores in `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`

### AccordKit Voice API (voice_api.gd, 55 lines)

- `get_info() -> RestResult` (line 16): voice backend configuration
- `join(channel_id, self_mute, self_deaf) -> RestResult` (line 23): joins voice, returns `AccordVoiceServerUpdate`
- `leave(channel_id) -> RestResult` (line 32): leaves voice channel
- `list_regions(space_id) -> RestResult` (line 39): available voice regions
- `get_status(channel_id) -> RestResult` (line 46): connected users as `Array[AccordVoiceState]`

### VoiceManager (voice_manager.gd, 77 lines)

- Signals: `voice_connected`, `voice_disconnected`, `voice_state_changed`, `voice_server_updated`, `voice_error` (lines 3-7)
- `join(channel_id, self_mute, self_deaf)` (lines 22-36): calls VoiceApi, stores state, emits `voice_connected`
- `leave()` (lines 39-48): calls VoiceApi, clears state, emits `voice_disconnected`
- `is_connected_to_voice() -> bool` (line 51) / `get_current_channel() -> String` (line 55)
- Gateway handlers: `_on_voice_state_update()` (lines 63-72) detects forced disconnection; `_on_voice_server_update()` (lines 75-76) re-emits

### AccordVoiceServerUpdate (voice_server_update.gd, 59 lines)

- `backend: String` (line 11) -- "livekit" or "custom"
- `livekit_url: String` (line 12) -- LiveKit server URL
- `token: String` (line 13) -- authentication token for voice backend
- `sfu_endpoint: String` (line 14) -- custom SFU endpoint URL
- `voice_state: AccordVoiceState` (line 15) -- present in REST join response, absent in gateway event

### AccordVoiceState (voice_state.gd, 58 lines)

- Properties: `user_id`, `space_id`, `channel_id`, `session_id`
- Mute/deaf flags: `deaf`, `mute`, `self_deaf`, `self_mute`, `self_stream`, `self_video`, `suppress`
- `from_dict()` (lines 19-38) / `to_dict()` (lines 41-57)

### Voice State Dictionary Shape (ClientModels.voice_state_to_dict, lines 465-492)

```gdscript
{
    "user_id": String,
    "channel_id": String,
    "session_id": String,
    "self_mute": bool,
    "self_deaf": bool,
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

### AccordVoiceSession (GDExtension native class)

- Registered as a Node subclass (no GDScript source -- compiled in AccordStream GDExtension)
- Signals: `session_state_changed`, `peer_joined`, `peer_left`, `audio_level_changed`, `signal_outgoing`
- State enum: `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `FAILED`
- Methods: `connect_livekit(url, token)`, `connect_custom_sfu(endpoint, ice_config, mic_id)`, `disconnect_voice()`, `set_muted(bool)`, `set_deafened(bool)`, `handle_voice_signal(user_id, type, payload)`
- Properties: `muted`, `deafened`, `peers`, `peer_details`, `channel_id`, `poll_interval`
- Instantiated in `Client._ready()` (line 69), stored as child node and meta `_voice_session`

### AccordStream GDExtension

- Native binary addon for WebRTC media
- Registered as engine singleton `AccordStream`
- Device enumeration: `get_cameras()`, `get_microphones()`, `get_screens()`, `get_windows()`
- Track creation: `create_camera_track(device_id, w, h, fps)`, `create_microphone_track(device_id)`, `create_screen_track(screen_id, fps)`, `create_window_track(window_id, fps)`
- AccordMediaTrack class: `get_id()`, `get_kind()`, `get_state()`, `is_enabled()`, `set_enabled()`, `stop()`
- Track states: `TRACK_STATE_LIVE`, `TRACK_STATE_ENDED`
- AccordPeerConnection class for WebRTC peer connections
- Tests: `tests/accordstream/integration/` -- peer connection, media tracks, voice session, device enumeration

### Gateway Voice Event Dispatch (gateway_socket.gd, lines 329-334)

- `"voice.state_update"` -> `voice_state_update.emit(AccordVoiceState.from_dict(data))`
- `"voice.server_update"` -> `voice_server_update.emit(AccordVoiceServerUpdate.from_dict(data))`
- `"voice.signal"` -> `voice_signal.emit(data)`

### Server Disconnect Voice Cleanup (client.gd, lines 953-976)

- `disconnect_server()` checks if user is in voice on the disconnecting server (`AppState.voice_guild_id == guild_id`) and calls `AppState.leave_voice()` (line 958-959)
- Erases voice state cache entries for all channels belonging to the disconnected server (line 976)

## Implementation Status

- [x] Voice channels displayed in channel list with speaker icon
- [x] Dedicated voice channel scene (`voice_channel_item`) with participant list
- [x] Voice channel type recognized by ClientModels (`ChannelType.VOICE`)
- [x] Join/leave voice via REST API (`VoiceApi.join()`, `VoiceApi.leave()`)
- [x] Voice control bar with mute, deafen, and disconnect buttons
- [x] Voice participant list with avatar, display name, and mute/deaf indicators
- [x] Voice user count displayed on voice channel items
- [x] Green tint on voice channel icon when connected
- [x] Voice state cache in `Client` (`_voice_state_cache`)
- [x] Gateway voice event handling (`on_voice_state_update`, `on_voice_server_update`, `on_voice_signal`)
- [x] Force-disconnect detection (gateway `voice_state_update` with empty `channel_id`)
- [x] Voice session management via `AccordVoiceSession` (LiveKit and custom SFU backends)
- [x] Mute/deafen state synced with `AccordVoiceSession` and `AppState`
- [x] Voice state fetched on join via `fetch.fetch_voice_states()`
- [x] Voice peer join/leave callbacks refresh participant state
- [x] Server disconnect cleans up voice state
- [x] AccordKit VoiceManager (connection lifecycle, signals)
- [x] Voice signal outgoing sent via gateway (VOICE_SIGNAL opcode)
- [x] Voice settings dialog for microphone device selection
- [x] Voice connection indicator on user bar
- [x] Voice participant avatars use Avatar component (circular, with initials)
- [x] AccordKit voice models (`AccordVoiceState`, `AccordVoiceServerUpdate`)
- [x] AccordClient `update_voice_state()` gateway opcode
- [x] AccordStream device enumeration and media track creation
- [x] AccordStream WebRTC peer connections
- [x] AccordStream voice session integration tests

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No audio output/playback | High | `AccordVoiceSession` manages connections but there is no code to render received audio from other participants to speakers (requires GDExtension C++ changes) |
