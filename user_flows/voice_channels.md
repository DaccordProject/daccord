# Voice Channels

## Overview

Voice channel support in daccord is partially implemented. Voice channels appear in the channel list with a speaker icon, and AccordKit provides a complete voice API (join, leave, status, regions) with a VoiceManager class. AccordStream is a GDExtension addon providing WebRTC peer connections and media track management (camera, microphone, screen, window capture). However, the UI layer has no join/leave controls, no participant list, and no mute/deafen buttons -- voice is display-only in the current client.

## User Steps

Current state:

1. User sees voice channels in the channel list (speaker icon)
2. Voice channels can show a participant count if `voice_users > 0` (but this field is never populated)
3. Clicking a voice channel selects it like a text channel (loads empty message view)
4. No actual voice connection is established

## Signal Flow

```
channel_item.gd                 AppState                    Client / AccordKit
     |                              |                              |
     |-- channel_pressed(id) ------>|                              |
     |                              |-- channel_selected(id) ----->|
     |                              |                              |-- fetch_messages(id)
     |                              |                              |   (treats voice channel
     |                              |                              |    like a text channel)
     |                              |                              |
     |   (NO voice join/leave signal flow exists)                  |
     |                              |                              |
     |   Gateway voice events fire but nothing handles them:       |
     |                              |                              |
     |                              |   gateway_socket.gd emits:   |
     |                              |     voice_state_update        |
     |                              |     voice_server_update       |
     |                              |     voice_signal              |
     |                              |                              |
     |                              |   AccordClient re-emits them |
     |                              |   VoiceManager listens to them|
     |                              |                              |
     |                              |   client.gd does NOT connect |
     |                              |   to voice_state_update,      |
     |                              |   voice_server_update, or     |
     |                              |   voice_signal from           |
     |                              |   AccordClient                |
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/channel_item.gd` | Voice channel display with VOICE_ICON, voice_users count (lines 42-51) |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_info()`, `list_regions()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking, signals |
| `addons/accordkit/voice/voice_signaling.gd` | WebRTC signaling helpers |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState model (user_id, channel_id, mute, deaf, etc.) |
| `addons/accordkit/models/voice_server_update.gd` | AccordVoiceServerUpdate (backend type, LiveKit URL, token, SFU endpoint) |
| `addons/accordkit/gateway/gateway_socket.gd` | voice_state_update, voice_server_update, voice_signal gateway events |
| `addons/accordkit/core/accord_client.gd` | Exposes `voice` (VoiceApi) and `voice_manager` (VoiceManager), re-emits gateway voice signals |
| `addons/accordstream/` | GDExtension binary for WebRTC peer connections and media tracks |
| `scripts/autoload/client_models.gd` | `ChannelType.VOICE` enum value |
| `scripts/autoload/client.gd` | Multi-server client -- connects gateway signals but skips all voice events |

## Implementation Details

### Channel Item Voice Display (channel_item.gd:42-51)

- `voice_users: int = data.get("voice_users", 0)` reads participant count
- If voice channel and voice_users > 0: creates a Label with count, font size 11, gray color
- But `channel_to_dict()` in `client_models.gd` never sets `voice_users` -- the field is absent from the dict

### AccordKit Voice API (voice_api.gd, 55 lines)

- `get_info() -> RestResult`: Returns voice backend configuration
- `join(channel_id, self_mute, self_deaf) -> RestResult`: Joins voice channel, returns AccordVoiceServerUpdate with connection details (LiveKit URL + token, or custom SFU endpoint)
- `leave(channel_id) -> RestResult`: Leaves voice channel
- `list_regions(space_id) -> RestResult`: Lists available voice regions
- `get_status(channel_id) -> RestResult`: Gets current voice status (connected users and their states)

### VoiceManager (voice_manager.gd, 77 lines)

- Signals: voice_connected, voice_disconnected, voice_state_changed, voice_server_updated, voice_error
- `join(channel_id, self_mute, self_deaf)`: Calls VoiceApi.join(), stores state, emits voice_connected
- `leave()`: Calls VoiceApi.leave(), clears state, emits voice_disconnected
- `is_connected_to_voice() -> bool`: Checks if currently in a voice channel
- `get_current_channel() -> String`: Returns current voice channel ID
- Listens to gateway voice_state_update and voice_server_update events
- Detects forced disconnection when user's channel_id becomes null in a voice_state_update

### VoiceSignaling (voice_signaling.gd, 22 lines)

- Signals: sdp_offer_received, sdp_answer_received, ice_candidate_received
- Listens to gateway voice_signal events and dispatches by type ("offer", "answer", "ice")

### AccordVoiceServerUpdate (voice_server_update.gd, 59 lines)

- `backend: String` -- "livekit" or "custom"
- `livekit_url: String` -- LiveKit server URL for WebRTC
- `token: String` -- Authentication token for voice backend
- `sfu_endpoint: String` -- Custom SFU endpoint URL
- `voice_state: AccordVoiceState` -- Current voice state (present in REST join response, absent in gateway event)

### AccordVoiceState (voice_state.gd, 58 lines)

- Properties: user_id, space_id, channel_id, session_id
- Mute/deaf flags: deaf, mute, self_deaf, self_mute, self_stream, self_video, suppress

### Gateway Voice Events (gateway_socket.gd)

- `voice_state_update(state: AccordVoiceState)` -- line 51
- `voice_server_update(info: AccordVoiceServerUpdate)` -- line 52
- `voice_signal(data: Dictionary)` -- line 53
- Dispatched from `_dispatch_event()` on events `voice.state_update`, `voice.server_update`, `voice.signal`

### AccordClient Voice Integration (accord_client.gd)

- Exposes `voice: VoiceApi` (line 97) and `voice_manager: VoiceManager` (line 98)
- `_connect_gateway_signals()` re-emits voice_state_update, voice_server_update, voice_signal (lines 202-204)
- `update_voice_state()` sends VOICE_STATE_UPDATE opcode via gateway (lines 152-156)
- VoiceManager is instantiated with VoiceApi and GatewaySocket references (line 137)

### Client.gd Voice Handling (client.gd)

- `connect_server()` connects gateway signals for messages, channels, presence, spaces -- but NOT voice (lines 202-214)
- No `_on_voice_state_update`, `_on_voice_server_update`, or `_on_voice_signal` handler methods exist
- AccordClient instances expose voice signals, but Client never subscribes to them

### AccordStream GDExtension

- Native binary addon for WebRTC media
- Registered as engine singleton `AccordStream`
- Device enumeration: `get_cameras()`, `get_microphones()`, `get_screens()`, `get_windows()`
- Track creation: `create_camera_track(device_id, w, h, fps)`, `create_microphone_track(device_id)`, `create_screen_track(screen_id, fps)`, `create_window_track(window_id, fps)`
- AccordMediaTrack class: `get_id()`, `get_kind()`, `get_state()`, `is_enabled()`, `set_enabled()`, `stop()`
- Track states: TRACK_STATE_LIVE, TRACK_STATE_ENDED
- Signal: `state_changed(new_state)` on AccordMediaTrack
- AccordPeerConnection class for WebRTC peer connections
- Tests exist: `tests/accordstream/integration/` -- peer connection, media tracks, voice session, device enumeration, end-to-end

## Implementation Status

- [x] Voice channels displayed in channel list with speaker icon
- [x] Voice channel type recognized by ClientModels (ChannelType.VOICE)
- [x] AccordKit VoiceApi (join, leave, get_info, list_regions, get_status)
- [x] AccordKit VoiceManager (connection lifecycle, signals)
- [x] AccordKit VoiceSignaling (SDP offer/answer, ICE candidate dispatch)
- [x] AccordKit voice models (AccordVoiceState, AccordVoiceServerUpdate)
- [x] AccordKit gateway voice events (voice_state_update, voice_server_update, voice_signal)
- [x] AccordClient re-emits gateway voice signals and exposes VoiceManager
- [x] AccordClient update_voice_state() gateway opcode
- [x] AccordStream device enumeration (cameras, microphones, screens, windows)
- [x] AccordStream media track creation (camera, microphone, screen, window)
- [x] AccordStream WebRTC peer connections
- [x] AccordStream integration tests
- [x] Voice user count display code in channel_item (conditional, if data provides it)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No voice join/leave UI | Critical | No button or interaction to join or leave a voice channel. All voice API and streaming code exists but nothing connects it to the UI |
| No mute/deafen buttons | Critical | No UI controls for self_mute or self_deaf despite AccordVoiceState supporting these flags |
| No voice participant list | High | No display of who is in a voice channel. `VoiceApi.get_status()` returns connected users but nothing renders them |
| voice_users never populated | High | `channel_to_dict()` in client_models.gd does not include `voice_users` field, so the participant count in channel_item is always 0 |
| Client doesn't handle voice gateway events | High | `client.gd` has no `_on_voice_state_update`, `_on_voice_server_update`, or `_on_voice_signal` handlers -- it never connects to AccordClient's voice signals |
| No audio output/playback | High | AccordStream creates media tracks but there is no code to play received audio from other participants |
| No voice connection indicator | Medium | No visual indicator showing the user is connected to a voice channel (e.g., bottom bar, channel highlight) |
| No voice settings (input/output device selection) | Medium | AccordStream can enumerate devices but no settings UI exists for selecting microphone or speaker |
| No screen/window sharing UI | Low | AccordStream supports screen/window capture but no UI to start/stop sharing |
| VoiceSignaling not used by any UI code | Low | VoiceSignaling dispatches SDP/ICE events but nothing consumes them to establish peer connections |
