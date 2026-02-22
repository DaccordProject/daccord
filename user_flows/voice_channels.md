# Voice Channels


## Overview

Voice channels allow users to join real-time audio conversations within a server. The client displays voice channels with a dedicated scene (`voice_channel_item`), shows connected participants with mute/deaf indicators, and provides a voice control bar with mute, deafen, and disconnect buttons. AccordKit provides the REST API (join, leave, status), VoiceManager for connection lifecycle, and gateway event handling. AccordStream is a GDExtension addon providing WebRTC peer connections and media track management. The `Client` autoload delegates voice operations to a `ClientVoice` helper class and manages an `AccordVoiceSession` for the active voice connection.

The server embeds a WebRTC SFU (Selective Forwarding Unit) directly in the main process using the Rust `webrtc` crate. Each client establishes a single PeerConnection to the SFU. The SFU receives audio from each participant and forwards it to all others via RTP packet forwarding. When `voice_backend == Custom`, the server returns `sfu_endpoint: "gateway"` and handles all WebRTC signaling (offer/answer/ICE) in-process rather than relaying signals peer-to-peer. When a new peer joins a room with existing peers, the SFU triggers renegotiation by sending new SDP offers to existing peers so they receive the new peer's audio track.

## User Steps

1. User sees voice channels in the channel list (speaker icon, distinct from text channels)
2. User clicks a voice channel to join
3. `ClientVoice.join_voice_channel()` calls `VoiceApi.join()` on the server, receives backend connection info
4. Server returns `AccordVoiceServerUpdate` with `backend: "custom"` and `sfu_endpoint: "gateway"` (embedded SFU) or `backend: "livekit"` with `livekit_url` and `token`
5. Client validates backend info: custom requires `sfu_endpoint`, livekit requires `livekit_url` and `token`
6. If backend info is missing or invalid, the client emits `voice_error` and does not call `AppState.join_voice()` (no voice bar, no participant list)
7. If result data is not an `AccordVoiceServerUpdate`, the client emits `voice_error` and returns `false` (no fallthrough)
8. If backend info is valid, the client connects via `AccordVoiceSession` (`connect_livekit()` or `connect_custom_sfu()`)
9. For custom SFU: AccordStream creates a PeerConnection, adds the microphone track, and generates an SDP offer. The offer is sent to the server via the gateway `VOICE_SIGNAL` opcode. The server's embedded SFU creates its own PeerConnection, sets the offer as remote description, creates an SDP answer (with ICE candidates gathered), and sends the answer back via a `voice.signal` gateway event. The client sets the answer as remote description, completing the WebRTC handshake.
10. Voice bar appears at the bottom of the channel panel showing the channel name, green status dot, and mute/deafen/disconnect buttons
11. The voice channel item shows connected participants with avatar, display name, and mute (M) / deaf (D) indicators
12. When a second user joins the same channel, the SFU creates a new PeerConnection for them and answers their offer. When their audio track arrives, the SFU creates a forwarded track and adds it to all existing peers' PeerConnections, triggering renegotiation: the SFU sends a new SDP offer to each existing peer, who responds with an answer. This enables all peers to receive the new participant's audio.
13. User can click Mic to toggle mute, Deaf to toggle deafen, or Disconnect to leave
14. On disconnect, `ClientVoice.leave_voice_channel()` calls `VoiceApi.leave()`, disconnects the voice session, and hides the voice bar. The server removes the SFU peer, closes its PeerConnection, sends `peer_left` signals to remaining peers, and renegotiates to remove the departed peer's forwarded track.

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
     |                              |   ClientGatewayEvents:       |
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

### WebRTC SFU Signal Flow (Custom Backend)

```
Client A              Server (Embedded SFU)              Client B
   |                         |                              |
   | VoiceApi.join()         |                              |
   |------------------------>|                              |
   |                    join_voice_channel()                 |
   |                         |                              |
   | voice.server_update     |                              |
   | (sfu_endpoint=gateway)  |                              |
   |<------------------------|                              |
   |                         | voice.state_update           |
   |                         |----------------------------->|
   |                         |                              |
   | VOICE_SIGNAL (offer)    |                              |
   |------------------------>|                              |
   |               EmbeddedSfu.handle_offer()               |
   |                  create PeerConnection                 |
   |                  set remote desc (offer)               |
   |                  create answer + gather ICE            |
   |                         |                              |
   | voice.signal (answer)   |                              |
   |<------------------------|                              |
   |  set remote desc        |                              |
   |  WebRTC connected       |                              |
   |                         |                              |
   |========= audio flows via RTP =========                 |
   |                         |                              |
   |                         | VoiceApi.join()              |
   |                         |<-----------------------------|
   |                         |                              |
   |                         | voice.server_update          |
   |                         | (sfu_endpoint=gateway)       |
   |                         |----------------------------->|
   |                         |                              |
   |                         | VOICE_SIGNAL (offer)         |
   |                         |<-----------------------------|
   |                EmbeddedSfu.handle_offer()              |
   |                  create PC for B                       |
   |                  add A's forwarded track               |
   |                  answer B's offer                      |
   |                         |                              |
   |                         | voice.signal (answer)        |
   |                         |----------------------------->|
   |                         |  B connected                 |
   |                         |                              |
   |         B's audio track arrives at SFU                 |
   |              create forwarded track                    |
   |              add to A's PeerConnection                 |
   |                         |                              |
   | voice.signal (offer)    |                              |
   | (renegotiation)         |                              |
   |<------------------------|                              |
   |  set remote desc        |                              |
   |  create answer          |                              |
   | VOICE_SIGNAL (answer)   |                              |
   |------------------------>|                              |
   |          set A's remote desc                           |
   |          renegotiation complete                        |
   |                         |                              |
   |==== A now receives B's audio ====                      |
```

Error path: if `VoiceApi.join()` returns a backend without credentials, `ClientVoice.join_voice_channel()` emits `AppState.voice_error` and returns without emitting `AppState.join_voice` or showing the voice bar. If the server returns data that is not an `AccordVoiceServerUpdate`, the client also emits `voice_error` and returns `false` (no fallthrough to `AppState.join_voice()`).

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/voice_channel_item.gd` | Dedicated voice channel scene: participant list with mute/deaf indicators, user count, green tint when connected |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene (VBoxContainer with ChannelButton + ParticipantContainer) |
| `scenes/sidebar/voice_bar.gd` | Voice control bar: mute/deafen/disconnect buttons, channel name, green status dot |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene (PanelContainer with StatusRow + ButtonRow) |
| `scenes/sidebar/channels/channel_list.gd` | Instantiates `VoiceChannelItemScene` for VOICE channels, `ChannelItemScene` for others |
| `scenes/sidebar/channels/category_item.gd` | Also instantiates `VoiceChannelItemScene` for voice channels within categories |
| `scenes/sidebar/channels/channel_item.gd` | Generic channel item; still handles VOICE type icon and voice_users count |
| `scripts/autoload/app_state.gd` | Voice signals and state: `voice_joined`, `voice_left`, `voice_state_updated`, `voice_error`, `voice_mute_changed`, `voice_deafen_changed`; state vars; methods |
| `scripts/autoload/client.gd` | Delegates voice operations to `ClientVoice`; instantiates `AccordVoiceSession` (line 165); wires voice session signals (lines 169-188); voice data access via `voice` helper (lines 441-444); voice API delegation (lines 528-561) |
| `scripts/autoload/client_voice.gd` | `ClientVoice` helper class: `join_voice_channel()` (line 26), `leave_voice_channel()` (line 153), `set_voice_muted()` (line 206), `set_voice_deafened()` (line 211); voice session callbacks (lines 302-405); backend validation (line 479) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` fetches connected users for a channel via `VoiceApi.get_status()` (line 476) |
| `scripts/autoload/client_gateway_events.gd` | Gateway voice event handlers: `on_voice_state_update` (line 89), `on_voice_server_update` (line 140), `on_voice_signal` (line 163) |
| `scripts/autoload/client_models.gd` | `ChannelType.VOICE` enum; `voice_state_to_dict()` conversion; `voice_users: 0` field in `channel_to_dict()` |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_info()`, `list_regions()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking, signals |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState` model (user_id, channel_id, mute, deaf flags) |
| `addons/accordkit/models/voice_server_update.gd` | `AccordVoiceServerUpdate` model (backend type, LiveKit URL, token, SFU endpoint) |
| `addons/accordkit/gateway/gateway_socket.gd` | `voice_state_update`, `voice_server_update`, `voice_signal` signals; dispatch; `send_voice_signal()` sends `VOICE_SIGNAL` opcode with `"type"` key |
| `addons/accordkit/core/accord_client.gd` | Exposes `voice: VoiceApi`, `voice_manager: VoiceManager`; re-emits gateway voice signals; `update_voice_state()` gateway opcode; `send_voice_signal()` |
| `addons/accordstream/` | GDExtension binary for WebRTC peer connections and media tracks |
| `tests/accordstream/integration/test_voice_session.gd` | AccordVoiceSession unit tests (state, mute/deafen, signals, connect/disconnect) |

### Server-Side Files (accordserver)

| File | Role |
|------|------|
| `src/voice/embedded_sfu.rs` | Embedded WebRTC SFU: `EmbeddedSfu`, `SfuRoom`, `SfuPeer` structs; `handle_signal()` dispatches offer/answer/ICE; `on_track()` creates forwarded tracks and triggers renegotiation; `remove_peer()` cleans up on leave |
| `src/voice/signaling.rs` | Signal relay (fallback when no embedded SFU); uses `"type"` key in voice.signal events |
| `src/voice/state.rs` | Voice state management: `join_voice_channel()`, `leave_voice_channel()`, `get_channel_voice_states()`, `get_user_voice_state()` |
| `src/gateway/mod.rs` | Gateway WebSocket handler; routes `VOICE_SIGNAL` to embedded SFU; returns `"gateway"` endpoint for Custom backend; cleans up SFU peer on disconnect |
| `src/gateway/events.rs` | `VoiceSignalData` struct with `#[serde(rename = "type")]` on `signal_type` field |
| `src/routes/voice.rs` | REST voice endpoints; `join_voice()` returns `sfu_endpoint: "gateway"` for Custom backend; `leave_voice()` calls `embedded_sfu.remove_peer()` |
| `src/state.rs` | `AppState` with `embedded_sfu: Option<Arc<EmbeddedSfu>>` field |

### AccordStream C++ Files

| File | Role |
|------|------|
| `src/internal/custom_sfu_backend.cpp` | `CustomSFUBackend`: handles incoming signals (answer, offer for renegotiation, ICE candidate, peer_joined, peer_left); `on_offer_created()` uses `type` parameter for signal type (not hardcoded "offer") |
| `src/internal/custom_sfu_backend.h` | Header: `VoiceBackend` interface implementation, peer tracking, track management |
| `src/internal/voice_backend.h` | `VoiceBackendCallbacks` struct (on_state_changed, on_peer_joined, on_peer_left, on_audio_level, on_signal_outgoing) |
| `src/accord_voice_session.cpp` | Signal forwarders: `_on_offer_created` and `_on_answer_created` both forward to `on_offer_created()` (type parameter disambiguates); `wire_peer_connection_signals()` connects PC signals |

## Implementation Details

### Voice Channel Item (voice_channel_item.gd)

Dedicated scene for voice channels (distinct from `channel_item.gd`). Used by both `channel_list.gd` and `category_item.gd` when the channel type is `ChannelType.VOICE`.

- `channel_pressed` signal emitted when the channel button is clicked
- Listens to `AppState.voice_state_updated`, `voice_joined`, `voice_left`
- `setup(data)` initializes from channel dict, sets voice icon, calls `_refresh_participants()`
- `set_active()` is a no-op -- voice channels don't have persistent active state, but the method exists for polymorphism with `channel_item`
- `_refresh_participants()`:
  - Reads `Client.get_voice_users(channel_id)` for current voice state dicts
  - Shows user count label when count > 0
  - Green tint on icon and white text when the local user is connected to this channel
  - Builds per-participant rows with: 28px indent spacer, 18x18 ColorRect avatar (using user's color), display name label (12px, gray), and red "M" or "D" indicator for self_mute/self_deaf

### Voice Bar (voice_bar.gd)

Bottom panel in the channel sidebar that appears when connected to voice. Instanced in `sidebar.tscn` as a child of `ChannelPanel` (node name `VoiceBar`).

- Hidden by default (`visible = false`)
- Connects to `AppState.voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed`
- `_on_voice_joined()`: shows bar, looks up channel name from `Client.get_channels_for_guild()`, sets green status dot color `(0.231, 0.647, 0.365)`
- `_on_voice_left()`: hides bar
- Button handlers delegate to `Client`: `set_voice_muted()`, `set_voice_deafened()`, `leave_voice_channel()`
- `_update_button_visuals()`: toggles button text ("Mic" / "Mic Off", "Deaf") and applies red-tinted `StyleBoxFlat` background when active

### ClientVoice Voice Mutation API (client_voice.gd, 513 lines)

Extracted helper class (`ClientVoice extends RefCounted`). Instantiated by `Client._init()` with a reference to the Client autoload node.

- `join_voice_channel(channel_id)` (line 26):
  - Returns early if already in this channel
  - Leaves current voice channel if in one (awaits `leave_voice_channel()`)
  - Calls `VoiceApi.join()` with current mute/deaf state
  - Validates `AccordVoiceServerUpdate`:
    - Backend `custom` requires `sfu_endpoint`
    - Backend `livekit` requires `livekit_url` and `token`
    - Missing backend credentials emits `voice_error`, calls leave on server, cleans up state, and returns `false`
  - If result data is not `AccordVoiceServerUpdate`, emits `voice_error` and returns `false` (no fallthrough)
  - Valid backend connects to LiveKit or custom SFU via `AccordVoiceSession`
  - Custom SFU uses configured or first available microphone from `AccordStream.get_microphones()`
  - Calls `AppState.join_voice()` and `fetch.fetch_voice_states()`
- `leave_voice_channel()` (line 153):
  - Stops camera/screen tracks, stops remote tracks
  - Disconnects `AccordVoiceSession`, calls `VoiceApi.leave()`
  - Removes self from `_voice_state_cache`, clears `_voice_server_info`
  - Clears speaking states, calls `AppState.leave_voice()` and emits `voice_state_updated`
- `set_voice_muted(muted)` (line 206): delegates to session and AppState
- `set_voice_deafened(deafened)` (line 211): delegates to session and AppState

### ClientVoice Session Callbacks (client_voice.gd, lines 302-405)

- `on_session_state_changed(state)` (line 302): emits `voice_error` on FAILED state
- `on_peer_joined(user_id)` (line 312): re-fetches voice states from server
- `on_peer_left(user_id)` (line 319): removes user from local cache, updates `voice_users` count, cleans up speaking state and remote tracks, emits `voice_state_updated`
- `on_signal_outgoing(signal_type, payload_json)` (line 392): sends voice signal via gateway `VOICE_SIGNAL` opcode using `AccordClient.send_voice_signal()`

### Client Voice Data Access (client.gd)

- `_voice_state_cache: Dictionary` (line 90): maps `channel_id -> Array` of voice state dicts
- `_voice_server_info: Dictionary` (line 91): stores latest voice server connection details
- `get_voice_users(channel_id) -> Array` (line 441): delegates to `voice.get_voice_users()`
- `get_voice_user_count(channel_id) -> int` (line 444): delegates to `voice.get_voice_user_count()`

### AppState Voice Signals and State (app_state.gd)

Signals:
- `voice_state_updated(channel_id)` -- fired when voice participant list changes
- `voice_joined(channel_id)` -- fired when local user joins voice
- `voice_left(channel_id)` -- fired when local user leaves voice
- `voice_error(error)` -- fired on voice connection errors
- `voice_mute_changed(is_muted)` -- fired when mute state toggles
- `voice_deafen_changed(is_deafened)` -- fired when deafen state toggles

State variables:
- `voice_channel_id: String` -- currently connected voice channel ID (empty if not in voice)
- `voice_guild_id: String` -- guild of the connected voice channel
- `is_voice_muted: bool` -- whether local user is muted
- `is_voice_deafened: bool` -- whether local user is deafened

Methods:
- `join_voice(channel_id, guild_id)` -- sets state vars, emits `voice_joined`
- `leave_voice()` -- clears state vars, resets mute/deaf, emits `voice_left`
- `set_voice_muted(muted)` / `set_voice_deafened(deafened)` -- update flags, emit change signals

### ClientGatewayEvents Voice Event Handlers (client_gateway_events.gd)

- `on_voice_state_update(state, conn_index)` (line 89):
  - Converts `AccordVoiceState` to dict via `ClientModels.voice_state_to_dict()`
  - Ignores self updates when not in voice and no backend credentials (prevents phantom join)
  - Removes user from any previous channel in `_voice_state_cache` (dedup)
  - Adds user to new channel, updates `voice_users` count in channel cache
  - Plays peer join/leave sound via `SoundManager`
  - Emits `AppState.voice_state_updated` for affected channels
  - Detects force-disconnect: if own user's `channel_id` becomes empty, calls `AppState.leave_voice()`
- `on_voice_server_update(info, conn_index)` (line 140): stores `info.to_dict()` in `_voice_server_info`; if already in voice with a disconnected session, connects backend immediately
- `on_voice_signal(data, conn_index)` (line 163): forwards to `AccordVoiceSession.handle_voice_signal()` with user_id, signal_type (from `data["type"]`), and payload

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

- `backend: String` -- "livekit" or "custom"
- `livekit_url: String` -- LiveKit server URL
- `token: String` -- authentication token for voice backend
- `sfu_endpoint: String` -- SFU endpoint (now `"gateway"` for embedded SFU)
- `voice_state: AccordVoiceState` -- present in REST join response, absent in gateway event

### AccordVoiceState (voice_state.gd)

- Properties: `user_id`, `space_id`, `channel_id`, `session_id`
- Mute/deaf flags: `deaf`, `mute`, `self_deaf`, `self_mute`, `self_stream`, `self_video`, `suppress`
- `from_dict()` / `to_dict()`

### Voice State Dictionary Shape (ClientModels.voice_state_to_dict)

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
- Instantiated in `Client._ready()` (line 165), stored as child node and meta `_voice_session`

### AccordStream GDExtension

- Native binary addon for WebRTC media
- Registered as engine singleton `AccordStream`
- Device enumeration: `get_cameras()`, `get_microphones()`, `get_screens()`, `get_windows()`
- Track creation: `create_camera_track(device_id, w, h, fps)`, `create_microphone_track(device_id)`, `create_screen_track(screen_id, fps)`, `create_window_track(window_id, fps)`
- AccordMediaTrack class: `get_id()`, `get_kind()`, `get_state()`, `is_enabled()`, `set_enabled()`, `stop()`
- Track states: `TRACK_STATE_LIVE`, `TRACK_STATE_ENDED`
- AccordPeerConnection class for WebRTC peer connections
- Tests: `tests/accordstream/integration/` -- peer connection, media tracks, voice session, device enumeration

### CustomSFUBackend (custom_sfu_backend.cpp)

C++ implementation of the `VoiceBackend` interface for the custom SFU.

- `connect_session()`: creates microphone track, creates PeerConnection, adds mic track, generates SDP offer
- `handle_incoming_signal()`: dispatches by signal type:
  - `"answer"`: sets remote SDP description (initial connection or renegotiation response)
  - `"offer"`: handles SFU renegotiation (sets remote description, creates answer which triggers `answer_created` signal -> `_on_answer_created` -> `on_offer_created(sdp, type="answer")` -> `signal_outgoing("answer", ...)`)
  - `"ice_candidate"`: adds ICE candidate to PeerConnection
  - `"peer_joined"` / `"peer_left"`: tracks peers in set, fires callbacks
- `on_offer_created(sdp, type)`: sends outgoing signal with the `type` parameter (not hardcoded `"offer"`) so answers are sent as `signal_outgoing("answer", ...)` and offers as `signal_outgoing("offer", ...)`
- Signal wiring is done by `AccordVoiceSession::wire_peer_connection_signals()` since this class is not a Godot Object

### Embedded SFU (embedded_sfu.rs -- server-side)

Rust WebRTC SFU embedded in the main server process using the `webrtc` crate.

- `EmbeddedSfu`: top-level manager. Owns a `DashMap<String, Arc<Mutex<SfuRoom>>>` for concurrent room access. Initialized with a shared WebRTC API instance (MediaEngine with default codecs, interceptor registry).
- `SfuRoom`: per-channel room. Tracks `HashMap<String, SfuPeer>` for connected peers and `HashMap<String, Arc<TrackLocalStaticRTP>>` for forwarded audio tracks.
- `SfuPeer`: per-user. Owns an `Arc<RTCPeerConnection>`, session_id, and space_id.
- `handle_signal()`: entry point from gateway. Dispatches to `handle_offer`, `handle_answer`, or `handle_ice_candidate`.
- `handle_offer()`: creates PeerConnection with STUN server, adds audio transceiver, sets client's offer as remote description, adds existing forwarded tracks, creates SDP answer with gathered ICE candidates, stores peer in room, sends peer_joined signals to existing peers, sends answer back to client.
- `handle_answer()`: sets remote description on user's PeerConnection (used during renegotiation when SFU sends a new offer after adding a forwarded track).
- `handle_ice_candidate()`: adds ICE candidate to user's PeerConnection.
- `on_track()`: called when audio arrives from a client. Creates `TrackLocalStaticRTP` for forwarding, spawns async RTP forwarding task (`loop { read_rtp -> write_rtp }`), adds the forwarded track to all other peers' PeerConnections, triggers renegotiation by creating and sending new SDP offers.
- `remove_peer()`: closes PeerConnection, removes forwarded tracks, sends `peer_left` signals, renegotiates with remaining peers to remove departed tracks, destroys empty rooms.
- `send_signal_to_user()`: sends `voice.signal` event to a specific user via gateway broadcast with `target_user_ids` filtering.

### Gateway Voice Signal Routing (gateway/mod.rs)

- `VOICE_SIGNAL` handler: for Custom backend, routes to `embedded_sfu.handle_signal()` by looking up the user's voice state to find channel_id and space_id. Falls back to `relay_signal()` if no embedded SFU is configured.
- `VOICE_STATE_UPDATE` Custom backend: returns `"endpoint": "gateway"` in the `voice.server_update` event (no external SFU node allocation).
- Disconnect cleanup: calls `embedded_sfu.remove_peer()` when a user disconnects from the gateway (in addition to voice state cleanup and broadcast).
- Explicit leave: calls `embedded_sfu.remove_peer()` when a user sends a leave voice state update.

### Signal Serialization

- Client sends `VOICE_SIGNAL` with `"type"` key in data (e.g., `"type": "offer"`).
- Server `VoiceSignalData` struct uses `#[serde(rename = "type")]` on `signal_type` field to match.
- Server sends `voice.signal` events with `"type"` key in data (e.g., `"type": "answer"`).
- Client reads `data.get("type", "")` to determine signal type.

### Gateway Voice Event Dispatch (gateway_socket.gd)

- `"voice.state_update"` -> `voice_state_update.emit(AccordVoiceState.from_dict(data))`
- `"voice.server_update"` -> `voice_server_update.emit(AccordVoiceServerUpdate.from_dict(data))`
- `"voice.signal"` -> `voice_signal.emit(data)`

### Server Disconnect Voice Cleanup (client.gd)

- `disconnect_server()` checks if user is in voice on the disconnecting server (`AppState.voice_guild_id == guild_id`) and calls `AppState.leave_voice()`
- Erases voice state cache entries for all channels belonging to the disconnected server

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
- [x] Speaker (output device) enumeration via `AccordStream.get_speakers()`
- [x] Output device selection via `AccordStream.set_output_device()` / `get_output_device()`
- [x] Playout device selection in WebRTCContext (routes to ADM `SetPlayoutDevice()`)
- [x] Deafen silences incoming audio (disables received audio tracks in CustomSFUBackend)
- [x] Received audio tracks tracked and cleaned up on disconnect
- [x] Output device persistence in Config (`voice.output_device`)
- [x] Voice settings dialog speaker dropdown
- [x] Output device applied on voice connect in ClientVoice
- [x] Speaker enumeration and output device integration tests
- [x] Speaking indicator: `audio_level_changed` signal wired from `AccordVoiceSession` to `ClientVoice`
- [x] Speaking indicator: green ring on participant avatars via shader (`ring_opacity` uniform)
- [x] Speaking indicator: 300ms debounce timer prevents flickering during speech pauses
- [x] Speaking indicator: green border on video tiles when user is speaking
- [x] Speaking indicator: state cleared on voice leave and peer disconnect
- [x] Voice join blocked when backend credentials are missing (emits `voice_error`, no `AppState.join_voice()`)
- [x] Embedded WebRTC SFU in server (webrtc crate, per-channel rooms, RTP forwarding)
- [x] Server returns `sfu_endpoint: "gateway"` for custom backend (no external SFU nodes needed)
- [x] Gateway routes `VOICE_SIGNAL` to embedded SFU instead of peer-to-peer relay
- [x] SFU handles offer/answer/ICE signaling, creates PeerConnections per client
- [x] SFU forwards audio via `TrackLocalStaticRTP` and async RTP forwarding tasks
- [x] SFU renegotiation: sends new offers to existing peers when a new peer's audio track arrives
- [x] Client handles incoming SFU renegotiation offers (`"offer"` signal type in CustomSFUBackend)
- [x] `on_offer_created()` uses `type` parameter (not hardcoded `"offer"`) so answers send correct signal type
- [x] `VoiceSignalData` serde rename: `#[serde(rename = "type")]` matches client JSON key
- [x] Server voice.signal events use `"type"` key (not `"signal_type"`) matching client expectations
- [x] SFU peer cleanup on explicit leave, REST leave, and gateway disconnect
- [x] SFU sends `peer_joined` / `peer_left` signals to connected peers
- [x] Empty SFU rooms destroyed automatically
- [x] Voice join fallthrough bug fixed: non-`AccordVoiceServerUpdate` response emits error and returns false
- [x] Voice mutation API extracted to `ClientVoice` helper class

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No TURN server configuration | Medium | The embedded SFU uses only STUN (`stun:stun.l.google.com:19302`). Clients behind symmetric NATs may fail to connect. Add configurable TURN server support to the SFU's `RTCConfiguration`. |
| LiveKit backend not implemented in AccordStream | Medium | `connect_livekit()` prints a "Phase 2" warning and does nothing. Only custom SFU backend works end-to-end. |
| No server-side validation/tests for voice join payloads | Low | Add server tests that assert `voice/join` returns credentials for configured backends. |
