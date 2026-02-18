# Video Chat

## Overview

Video chat in daccord enables camera video, screen sharing, and window sharing within voice channels. The AccordStream GDExtension provides complete WebRTC infrastructure for enumerating capture devices, creating video tracks, and negotiating peer connections with SDP offer/answer exchange. The AccordVoiceState model tracks `self_video` and `self_stream` flags per user. Voice channels now have full join/leave/mute/deafen support via `client.gd`, with a dedicated `voice_channel_item` scene and `voice_bar` for controls. However, no UI exists for enabling video or screen sharing -- the video pipeline is backend-only with no user-facing camera/screen controls.

## User Steps

1. User clicks a voice channel in the sidebar (joins via `Client.join_voice_channel()`)
2. User sees participants listed below the voice channel item, with V/S indicators for video/screen share
3. User sees the voice bar with Mic/Deaf/Cam/Share/Disconnect buttons
4. User clicks "Cam" to toggle camera on/off (creates/stops camera track via `Client.toggle_video()`)
5. User clicks "Share" to open screen/window picker dialog, selects a source to start sharing
6. User would see other participants' video feeds (no rendering exists -- requires GDExtension changes)
7. User clicks "Sharing" to stop screen share, or "Cam On" to stop camera

## Signal Flow

```
  (No video UI layer exists -- this is the intended flow)

  User clicks "Enable Camera"        AccordStream                AccordVoiceSession
       |                                  |                              |
       |-- get_cameras() --------------->|                              |
       |<-- [{id, name}, ...] ------------|                              |
       |                                  |                              |
       |-- create_camera_track(id,w,h,fps)>                              |
       |<-- AccordMediaTrack (kind=video) |                              |
       |                                  |                              |
       |                          AccordPeerConnection                   |
       |-- add_track(video_track) ------>|                              |
       |-- create_offer() ------------->|                              |
       |                                |-- offer_created(sdp,type) -->|
       |                                |                              |
       |                                |   (SDP contains m=video)     |
       |                                |                              |
       |                        AccordVoiceSession              Gateway
       |                              |-- signal_outgoing ----------->|
       |                              |<-- handle_voice_signal -------|
       |                              |                               |
       |                        AccordPeerConnection                  |
       |                              |-- set_remote_description ---->|
       |                              |-- add_ice_candidate --------->|
       |                              |-- track_received(remote) ---->|
       |                              |                               |
       |   (Render remote video track in TextureRect or SubViewport) |
       |                                                              |
       |                        AccordVoiceState                      |
       |                              |   self_video = true           |
       |                              |   (gateway voice.state_update)|

  Screen share follows same flow but with:
       |-- get_screens() / get_windows() -->|
       |-- create_screen_track(id, fps) --->|
       |   self_stream = true               |
```

## Key Files

| File | Role |
|------|------|
| `addons/accordstream/` | GDExtension binary: AccordStream singleton, AccordPeerConnection, AccordMediaTrack, AccordVoiceSession |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState model with `self_video` (line 15) and `self_stream` (line 14) flags |
| `addons/accordkit/models/voice_server_update.gd` | AccordVoiceServerUpdate: backend type, LiveKit URL, token, SFU endpoint |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()` (line 23), `leave()` (line 32), `get_status()` (line 46) |
| `addons/accordkit/voice/voice_manager.gd` | Voice lifecycle: join/leave, voice_connected/voice_disconnected signals |
| `addons/accordkit/voice/voice_manager.gd` | Voice connection lifecycle: join, leave, state tracking |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway voice events: `voice_state_update` (line 52), `voice_server_update` (line 53), `voice_signal` (line 54) |
| `addons/accordkit/core/accord_client.gd` | Re-emits voice signals (lines 212-214), exposes `voice` API (line 105) and `voice_manager` (line 106) |
| `scripts/autoload/app_state.gd` | Voice signals: `voice_state_updated`, `voice_joined`, `voice_left`, `voice_error`, `voice_mute_changed`, `voice_deafen_changed`, `video_enabled_changed`, `screen_share_changed`; state vars including `is_video_enabled`, `is_screen_sharing` |
| `scripts/autoload/client.gd` | Voice session, join/leave/mute/deafen API, video track management (`toggle_video()`, `start_screen_share()`, `stop_screen_share()`), gateway signal connections, voice state cache and data access, session callbacks |
| `scripts/autoload/client_gateway.gd` | Voice gateway handlers: `on_voice_state_update` (line 387), `on_voice_server_update` (line 421), `on_voice_signal` (line 426) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` (line 323): REST voice status -> cache -> signal |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` includes `self_video`/`self_stream`, `channel_to_dict()` includes `voice_users` |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel UI: expandable participant list, green icon when connected, mute/deaf/video/stream indicators |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene: VBoxContainer with button + participant container |
| `scenes/sidebar/voice_bar.gd` | Voice connection bar: mute/deafen/cam/share/disconnect, self-manages visibility via AppState signals |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: PanelContainer with status row + button row (Mic, Deaf, Cam, Share, Disconnect) |
| `scenes/sidebar/screen_picker_dialog.gd` | Screen/window picker overlay: tabs for screens/windows, enumerates via AccordStream, emits `source_selected` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: ColorRect overlay with centered panel, TabBar, ScrollContainer with source buttons |
| `scenes/sidebar/channels/channel_list.gd` | Conditional voice channel instantiation (lines 107-117), voice join/leave on click (lines 159-170), auto-select skips voice (lines 148-154) |
| `scenes/sidebar/channels/category_item.gd` | Conditional voice channel instantiation in categories (lines 56-63) |
| `scenes/sidebar/sidebar.tscn` | VoiceBar between DMList and UserBar (line 32) |
| `tests/accordstream/integration/test_end_to_end.gd` | Video publish flow tests (lines 75-108), screen share tests (lines 172-202), audio+video tests (lines 115-165) |
| `tests/accordstream/integration/test_media_tracks.gd` | Camera track tests (lines 27-134), screen track tests (lines 209-252), window track tests (lines 255-283) |
| `tests/accordstream/integration/test_peer_connection.gd` | Peer connection tests: video media in SDP (lines 394-414), track management, ICE, state enums |
| `tests/accordstream/integration/test_device_enumeration.gd` | Device enumeration tests: cameras (lines 18-70), screens (lines 114-144), windows (lines 149-180) |
| `tests/accordstream/integration/test_voice_session.gd` | Voice session tests: state machine, mute/deafen, peer tracking, custom SFU connection |

## Implementation Details

### Voice Data Layer (Phase 1 -- Implemented)

Voice gateway events are now fully wired through the data layer:

**AppState signals** (lines 46-56):
- `voice_state_updated(channel_id)` -- emitted when voice participants change
- `voice_joined(channel_id)` -- emitted when local user joins voice
- `voice_left(channel_id)` -- emitted when local user leaves voice
- `voice_error(error)` -- emitted on voice connection failure
- `voice_mute_changed(is_muted)` -- emitted when mute state changes
- `voice_deafen_changed(is_deafened)` -- emitted when deafen state changes

**AppState state vars** (lines 96-99):
- `voice_channel_id: String` -- current voice channel (empty if not connected)
- `voice_guild_id: String` -- guild of current voice channel
- `is_voice_muted: bool` -- local mute state
- `is_voice_deafened: bool` -- local deafen state

**AppState helpers** (lines 174-196):
- `join_voice(channel_id, guild_id)` -- sets state, emits `voice_joined`
- `leave_voice()` -- clears state, resets mute/deafen, emits `voice_left`
- `set_voice_muted(muted)` -- updates state, emits `voice_mute_changed`
- `set_voice_deafened(deafened)` -- updates state, emits `voice_deafen_changed`

**ClientModels.voice_state_to_dict()**:
Converts `AccordVoiceState` to dict with keys: `user_id`, `channel_id`, `session_id`, `self_mute`, `self_deaf`, `self_video`, `self_stream`, `mute`, `deaf`, `user` (user dict from cache).

**Client voice state cache** (`client.gd` line 42):
- `_voice_state_cache: Dictionary = {}` -- keyed by channel_id, values are Arrays of voice state dicts
- `_voice_server_info: Dictionary = {}` -- stored AccordVoiceServerUpdate for active connection
- `get_voice_users(channel_id) -> Array` (line 473) -- returns voice state dicts for a channel
- `get_voice_user_count(channel_id) -> int` (line 476) -- returns participant count

**Client voice mutation API** (lines 724-808):
- `join_voice_channel(channel_id) -> bool` (line 726) -- leaves current voice if any, calls `VoiceApi.join()`, connects AccordVoiceSession based on backend type (LiveKit or custom SFU), emits `AppState.join_voice()`, fetches voice states
- `leave_voice_channel() -> bool` (line 773) -- disconnects voice session, calls `VoiceApi.leave()`, removes self from cache, emits `AppState.leave_voice()`
- `set_voice_muted(muted)` (line 802) -- forwards to `_voice_session.set_muted()` and `AppState.set_voice_muted()`
- `set_voice_deafened(deafened)` (line 806) -- forwards to `_voice_session.set_deafened()` and `AppState.set_voice_deafened()`

**Client gateway signal connections** (lines 348-353):
- `client.voice_state_update` -> `_gw.on_voice_state_update`
- `client.voice_server_update` -> `_gw.on_voice_server_update`
- `client.voice_signal` -> `_gw.on_voice_signal`

**ClientGateway voice handlers** (`client_gateway.gd`):
- `on_voice_state_update(state, conn_index)` (line 387) -- converts to dict via `voice_state_to_dict()`, removes user from previous channel, adds to new channel, updates `voice_users` count in channel cache, emits `voice_state_updated`, detects force-disconnect
- `on_voice_server_update(info, conn_index)` (line 421) -- stores info in `_voice_server_info`
- `on_voice_signal(data, conn_index)` (line 426) -- forwards to `AccordVoiceSession.handle_voice_signal()` via meta reference

**ClientFetch.fetch_voice_states()** (`client_fetch.gd` line 323):
Calls `VoiceApi.get_status(channel_id)`, converts each `AccordVoiceState` via `voice_state_to_dict()`, populates `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`.

**Server disconnect cleanup** (`client.gd` line 957-959):
If user is in voice on the disconnecting server, calls `AppState.leave_voice()`. Voice state cache entries are erased with channel cleanup (line 976).

### Voice Channel UI (Phase 2 -- Implemented)

**voice_channel_item.gd** -- Dedicated VBoxContainer scene for voice channels:
- Exposes `channel_pressed` signal, `setup(data)`, `set_active(bool)` for polymorphism with `channel_item`
- Top row: Button with voice icon, channel name, user count label (line 14)
- Below: `ParticipantContainer` VBoxContainer populated by `_refresh_participants()` (line 51)
- Listens to `voice_state_updated`, `voice_joined`, `voice_left` signals (lines 19-21)
- Green icon tint (`Color(0.231, 0.647, 0.365)`) when user is connected to this channel (line 66)
- Each participant row: 28px indent + 18x18 avatar ColorRect + display name + mute/deaf indicator labels + green "V" for video + blue "S" for screen share

**channel_list.gd** voice integration:
- `VoiceChannelItemScene` preloaded (line 7)
- Uncategorized loop (lines 107-117): checks `ch.get("type", 0) == ClientModels.ChannelType.VOICE`, instantiates `VoiceChannelItemScene` for voice, `ChannelItemScene` for others
- `_on_channel_pressed()` (lines 159-170): voice channels toggle `Client.join_voice_channel()` / `Client.leave_voice_channel()` instead of emitting `channel_selected`. Text channel message view stays in place
- Auto-select (lines 148-154): skips both `CATEGORY` and `VOICE` channel types

**category_item.gd** voice integration:
- `VoiceChannelItemScene` preloaded (line 9)
- `setup()` child loop (lines 56-63): same conditional instantiation as channel_list

### Voice Connection Bar (Phase 3 -- Implemented)

**voice_bar.gd** -- Self-managing PanelContainer in sidebar:
- Hidden by default, shows on `voice_joined`, hides on `voice_left`
- Status row: green `ColorRect` dot + channel name label (looked up from `Client.get_channels_for_guild()`)
- Button row: Mic, Deaf, Cam, Share, Disconnect
- Mute button: toggles via `Client.set_voice_muted()`, red tint `StyleBoxFlat` when active
- Deafen button: toggles via `Client.set_voice_deafened()`, red tint when active
- Cam button: toggles via `Client.toggle_video()`, green tint when active ("Cam On"), creates/stops camera track
- Share button: opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`, green tint when active ("Sharing")
- Disconnect button: calls `Client.leave_voice_channel()`
- Listens to `video_enabled_changed` and `screen_share_changed` signals to update button visuals

**screen_picker_dialog.gd** -- Full-screen semi-transparent overlay:
- Two tabs: Screens and Windows (via TabBar)
- Populates source buttons from `AccordStream.get_screens()` / `AccordStream.get_windows()`
- Each button shows source title and resolution
- Emits `source_selected(source_type, source_id)` on pick
- Self-destructs on close/backdrop click/Escape

**sidebar.tscn**: VoiceBar placed between DMList and UserBar in `ChannelPanel` VBox. Self-manages via AppState signals -- no changes to `sidebar.gd` required.

### AccordVoiceSession Integration (Phase 4 -- Implemented)

**Client owns AccordVoiceSession** (`client.gd` lines 63-82):
- `_voice_session: AccordVoiceSession` instantiated in `_ready()`, added as child node
- Stored as meta `"_voice_session"` for gateway access
- Connected signals: `session_state_changed`, `peer_joined`, `peer_left`, `signal_outgoing`

**Join flow** (`client.gd` lines 750-768):
After REST `VoiceApi.join()` succeeds, the response `AccordVoiceServerUpdate` determines backend:
- LiveKit: `_voice_session.connect_livekit(url, token)` (line 757)
- Custom SFU: `_voice_session.connect_custom_sfu(endpoint, ice_config, mic_id)` (line 766) -- picks first microphone from `AccordStream.get_microphones()` (lines 762-764)

**Leave flow** (`client.gd` line 777):
`_voice_session.disconnect_voice()` called before REST `VoiceApi.leave()`.

**Mute/deafen** (`client.gd`):
Both forward to `_voice_session.set_muted()` / `set_deafened()` and `AppState`.

### Video Track Management (Phase 5 -- Implemented)

**AppState video state** (`app_state.gd`):
- `is_video_enabled: bool` -- camera is active
- `is_screen_sharing: bool` -- screen/window share is active
- `video_enabled_changed(is_enabled)` -- emitted when camera state changes
- `screen_share_changed(is_sharing)` -- emitted when screen share state changes
- `set_video_enabled(bool)` / `set_screen_sharing(bool)` -- helpers that update state and emit signals
- Both reset to `false` in `leave_voice()` alongside mute/deafen

**Client video API** (`client.gd`):
- `_camera_track: AccordMediaTrack` -- active camera track (null when off)
- `_screen_track: AccordMediaTrack` -- active screen/window track (null when off)
- `toggle_video()` -- creates camera track via `AccordStream.create_camera_track(first_camera, 640, 480, 30)` or stops existing one. Emits `voice_error` if no camera found
- `start_screen_share(source_type, source_id)` -- creates screen or window track via `AccordStream.create_screen_track(id, 15)` / `create_window_track(id, 15)`. Stops any existing screen track first
- `stop_screen_share()` -- stops and nulls screen track
- `_send_voice_state_update()` -- sends gateway voice state update with all flags (mute, deaf, video, stream)
- Track cleanup in `leave_voice_channel()` -- stops both camera and screen tracks before disconnecting

**AccordKit gateway** (`gateway_socket.gd`, `accord_client.gd`):
`update_voice_state()` now accepts `self_video: bool = false, self_stream: bool = false` as additional default parameters. The payload includes both flags. Backward compatible -- existing callers don't need changes.

### Video UI Controls (Phase 5 -- Implemented)

**Voice bar Cam/Share buttons** (`voice_bar.gd`, `voice_bar.tscn`):
- VideoBtn ("Cam") and ShareBtn ("Share") added between DeafenBtn and DisconnectBtn
- Cam: toggles `Client.toggle_video()`. Green tint `StyleBoxFlat` when active, text changes to "Cam On"
- Share: if sharing, calls `Client.stop_screen_share()`. If not, opens `ScreenPickerDialog`. Green tint when active, text changes to "Sharing"
- Listens to `video_enabled_changed` and `screen_share_changed` to update visuals

**Screen picker dialog** (`screen_picker_dialog.gd`, `screen_picker_dialog.tscn`):
- Full-screen `ColorRect` overlay (50% black backdrop) with centered `PanelContainer`
- TabBar with "Screens" and "Windows" tabs
- Enumerates sources from `AccordStream.get_screens()` / `AccordStream.get_windows()`
- Each source shown as a button with title and resolution
- Emits `source_selected(source_type: String, source_id: int)` on pick
- Self-destructs on close button, backdrop click, or Escape key

**Participant video/stream indicators** (`voice_channel_item.gd`):
- After mute/deaf indicator block, adds green "V" label for `self_video` and blue "S" label for `self_stream`
- Both can appear simultaneously (user can have camera on while screen sharing)
- Follows same `Label.new()` pattern as existing mute/deaf indicators

**Session callbacks** (`client.gd` lines 1077-1114):
- `_on_voice_session_state_changed(state)` (line 1079) -- emits `voice_error` on `FAILED` state
- `_on_voice_peer_joined(user_id)` (line 1087) -- refreshes voice states via `fetch.fetch_voice_states()`
- `_on_voice_peer_left(user_id)` (line 1095) -- removes from local cache, updates `voice_users` count, emits `voice_state_updated`
- `_on_voice_signal_outgoing(signal_type, payload_json)` (line 1110) -- logs outgoing signal; gateway `_send` is private so outgoing WebRTC signaling is logged but not yet forwarded

### AccordStream Device Enumeration

The AccordStream engine singleton provides four device enumeration methods:

- `get_cameras() -> Array` -- Returns `[{id: String, name: String}, ...]` for connected webcams
- `get_microphones() -> Array` -- Returns `[{id: String, name: String}, ...]` for audio input devices
- `get_screens() -> Array` -- Returns `[{id: int, title: String, width: int, height: int}, ...]` for displays
- `get_windows() -> Array` -- Returns `[{id: int, title: String, width: int, height: int}, ...]` for application windows

All calls are idempotent and safe to call repeatedly (verified by `test_device_enumeration.gd` lines 22-26, 79-83, 118-122).

### AccordStream Media Track Creation

Video tracks are created via AccordStream factory methods:

- `create_camera_track(device_id: String, width: int, height: int, fps: int) -> AccordMediaTrack` -- Webcam capture. Tested at 320x240@15fps and 640x480@30fps (`test_media_tracks.gd` lines 127-128)
- `create_screen_track(screen_id: int, fps: int) -> AccordMediaTrack` -- Full screen capture (`test_media_tracks.gd` line 225)
- `create_window_track(window_id: int, fps: int) -> AccordMediaTrack` -- Single window capture (`test_media_tracks.gd` line 270)

All video tracks have `get_kind() == "video"` (verified at `test_media_tracks.gd` lines 42, 227, 272).

**AccordMediaTrack API:**
- `get_id() -> String` -- Unique track ID
- `get_kind() -> String` -- `"audio"` or `"video"`
- `get_state() -> int` -- `TRACK_STATE_LIVE` (0) or `TRACK_STATE_ENDED` (1)
- `is_enabled() -> bool` / `set_enabled(bool)` -- Enable/disable track without destroying it
- `stop()` -- Ends the track, emits `state_changed(TRACK_STATE_ENDED)` signal

Invalid device IDs return `null` (`test_media_tracks.gd` lines 28-33). Multiple tracks from the same device are supported (`test_media_tracks.gd` lines 120-134). `stop()` is idempotent (`test_media_tracks.gd` lines 290-300).

### AccordPeerConnection for Video

`AccordStream.create_peer_connection(config: Dictionary) -> AccordPeerConnection` creates a WebRTC peer connection.

**Config format:**
```gdscript
{"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
```

Supports STUN, TURN with credentials, and multiple ICE servers (`test_peer_connection.gd` lines 39-54).

**Track management:**
- `add_track(track: AccordMediaTrack) -> int` -- Adds a media track to the connection. Returns `OK` on success
- `remove_track(track: AccordMediaTrack) -> int` -- Removes a track
- `get_senders() -> Array` -- Returns `[{track_id: String, track_kind: String}, ...]`
- `get_receivers() -> Array` -- Returns `[{track_kind: String, audio_level: float}, ...]`

**SDP negotiation:**
- `create_offer()` -- Async, emits `offer_created(sdp: String, type: String)`. When video tracks are added, the SDP contains `m=video` media sections (`test_peer_connection.gd` lines 394-414)
- `create_answer()` -- Emits `answer_created(sdp: String, type: String)`
- `set_local_description(type, sdp) -> int` / `set_remote_description(type, sdp) -> int`
- `add_ice_candidate(mid, index, sdp) -> int`

**Signals:**
- `offer_created(sdp, type)` / `answer_created(sdp, type)`
- `ice_candidate_generated(mid, index, sdp)`
- `track_received(track: Dictionary)` -- Remote track from peer

**Connection state enums** (`test_peer_connection.gd` lines 525-548):
- Connection: NEW(0), CONNECTING(1), CONNECTED(2), DISCONNECTED(3), FAILED(4), CLOSED(5)
- Signaling: STABLE(0), HAVE_LOCAL_OFFER(1), HAVE_LOCAL_PRANSWER(2), HAVE_REMOTE_OFFER(3), HAVE_REMOTE_PRANSWER(4), CLOSED(5)
- ICE: NEW(0), CHECKING(1), CONNECTED(2), COMPLETED(3), FAILED(4), DISCONNECTED(5), CLOSED(6)

### AccordVoiceState Video Flags (voice_state.gd)

The `AccordVoiceState` model includes two video-related boolean flags:

- `self_video: bool = false` (line 15) -- User is transmitting camera video
- `self_stream: bool = false` (line 14) -- User is screen sharing

These are serialized via `from_dict()` (lines 35-36) and `to_dict()` (lines 49-50), and are sent/received through the gateway `voice.state_update` event. The `voice_state_to_dict()` conversion in `client_models.gd` includes both `self_video` and `self_stream` in its output dict.

### End-to-End Video Workflows (test_end_to_end.gd)

Four video-related E2E tests validate the full pipeline:

1. **`test_publish_video_flow()`** (line 75) -- Camera enumeration -> `create_camera_track(640, 480, 30)` -> add to PC -> `create_offer()` -> verify SDP contains `m=video` -> `set_local_description()`
2. **`test_publish_audio_and_video_flow()`** (line 115) -- Both mic and camera tracks simultaneously -> verify SDP contains both `m=audio` and `m=video`
3. **`test_publish_screen_share_flow()`** (line 172) -- Screen enumeration -> `create_screen_track(id, 15)` -> add to PC -> verify SDP contains `m=video`
4. **`test_kitchen_sink()`** (line 330) -- All device types (camera, mic, screen, window) -> all tracks added to single PC -> SDP generation

Two-peer handshake is tested in `test_two_peer_connections_offer_answer()` (line 209): offerer creates offer -> sets local description -> answerer sets remote description -> creates answer -> both sides complete negotiation.

## Implementation Status

- [x] AccordStream GDExtension with WebRTC peer connections
- [x] Camera enumeration (`get_cameras()`) with id/name dict shape
- [x] Screen enumeration (`get_screens()`) with id/title/width/height dict shape
- [x] Window enumeration (`get_windows()`) with id/title/width/height dict shape
- [x] Camera video track creation with configurable resolution and frame rate
- [x] Screen capture track creation
- [x] Window capture track creation
- [x] AccordMediaTrack enable/disable toggle (mute video without destroying track)
- [x] SDP offer/answer negotiation with m=video media sections
- [x] ICE candidate exchange for NAT traversal
- [x] AccordVoiceSession with custom SFU and LiveKit backend support
- [x] AccordVoiceState `self_video` and `self_stream` flags
- [x] Gateway `voice.state_update` event carries video flags
- [x] Voice signals routed via AccordVoiceSession and VOICE_SIGNAL gateway opcode
- [x] VoiceManager connection lifecycle (join/leave/forced disconnect)
- [x] VoiceApi REST endpoints (join, leave, get_status)
- [x] AccordClient re-emits all gateway voice signals
- [x] 146 integration tests covering device enumeration, media tracks, peer connections, voice sessions, and E2E video flows
- [x] Client.gd voice gateway event handlers (`on_voice_state_update`, `on_voice_server_update`, `on_voice_signal`)
- [x] AppState voice signals (`voice_state_updated`, `voice_joined`, `voice_left`, `voice_error`, `voice_mute_changed`, `voice_deafen_changed`)
- [x] AppState voice state tracking (`voice_channel_id`, `voice_guild_id`, `is_voice_muted`, `is_voice_deafened`)
- [x] Client voice mutation API (`join_voice_channel`, `leave_voice_channel`, `set_voice_muted`, `set_voice_deafened`)
- [x] Voice state cache (`_voice_state_cache`) with data access API (`get_voice_users`, `get_voice_user_count`)
- [x] ClientModels `voice_state_to_dict()` conversion
- [x] ClientFetch `fetch_voice_states()` for REST-based voice state population
- [x] Dedicated `voice_channel_item` scene with expandable participant list
- [x] Voice channel click toggles join/leave (does not emit `channel_selected`)
- [x] Auto-select skips voice channels
- [x] Voice bar with mute/deafen/disconnect buttons
- [x] Voice bar self-manages visibility via AppState signals
- [x] AccordVoiceSession wired into Client (join connects SFU/LiveKit, leave disconnects, mute/deafen forwarded)
- [x] Gateway voice signals forwarded to AccordVoiceSession
- [x] Force-disconnect detection (gateway voice_state_update with null channel_id)
- [x] Voice state cleanup on server disconnect
- [x] `voice_state_to_dict` includes `self_video` / `self_stream` flags
- [x] AppState video state tracking (`is_video_enabled`, `is_screen_sharing`, signals, helpers)
- [x] AccordKit `update_voice_state` supports `self_video` / `self_stream` params
- [x] Client video track management (`toggle_video()`, `start_screen_share()`, `stop_screen_share()`)
- [x] Video enable/disable UI (Cam button in voice bar)
- [x] Screen sharing UI (Share button + screen/window picker dialog)
- [x] Video/stream indicators in voice channel participant rows (green V, blue S)
- [x] Track cleanup on voice disconnect
- [ ] Video preview (local camera feed display -- requires AccordMediaTrack frame access)
- [ ] Remote video rendering (TextureRect or SubViewport for peer video -- requires AccordMediaTrack frame access)
- [ ] Video participant grid/layout
- [ ] Camera/screen device selection settings UI
- [ ] Video quality settings (resolution, frame rate)
- [ ] Bandwidth adaptation for video streams

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No remote video rendering | Critical | `track_received` signal on AccordPeerConnection delivers remote video tracks, but nothing renders them. Requires AccordMediaTrack `get_frame()`/`to_texture()` GDExtension changes to bridge to Godot's rendering system |
| No video preview | Critical | Local camera feed should be shown to the user. AccordMediaTrack exists but has no bridge to Godot's rendering system (Texture2D / ImageTexture). Blocked on GDExtension changes |
| LiveKit backend is a stub | High | `AccordVoiceSession.connect_livekit()` does not actually connect -- remains in DISCONNECTED state. Only custom SFU works |
| Outgoing voice signals not forwarded | Medium | `_on_voice_signal_outgoing` in `client.gd` logs but does not send signals via gateway. The SFU handles its own signaling for custom backends, but LiveKit backend would need this |
| No video participant layout | Medium | No grid/gallery view for multiple video feeds. Needs dynamic layout that adapts to participant count. Blocked on video rendering |
| No camera/screen device picker | Medium | Uses first camera automatically. A settings UI could let the user choose which camera to use |
| No video quality controls | Medium | Camera track creation uses fixed 640x480@30fps. Nothing lets the user configure resolution or frame rate |
| No bandwidth adaptation | Low | Fixed video parameters with no dynamic quality adjustment based on network conditions |
| No video track hot-swap | Low | Switching cameras requires stopping the old track and creating a new one. No seamless hot-swap mechanism |
