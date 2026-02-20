# Video Chat

Last touched: 2026-02-20 (Discord-style UI redesign plan)

## Overview

Video chat in daccord enables camera video, screen sharing, and window sharing within voice channels. The AccordStream GDExtension provides complete WebRTC infrastructure for enumerating capture devices, creating video tracks, and negotiating peer connections with SDP offer/answer exchange. The AccordVoiceState model tracks `self_video` and `self_stream` flags per user. Voice channels have full join/leave/mute/deafen support via `client.gd`, with a dedicated `voice_channel_item` scene and `voice_bar` for controls. The full pipeline is implemented: voice bar has Cam/Share buttons, the video grid renders local camera and screen share tiles live, and the remote rendering pipeline (track cache, signal wiring, grid integration) is complete. Remote video tiles activate automatically when the AccordStream GDExtension exposes `track_received` on `AccordVoiceSession`; until then, remote peers show placeholder tiles with name/initials.

**Discord-style target design:** The video UI should replace the message content area with a full-area video view when the user is in a voice channel and wants to see video. Clicking the voice channel name in the voice bar (or the voice channel itself when already connected) opens this full-area view. Clicking any text channel returns to the normal message view while voice continues in the background. A screen share should appear as the dominant/spotlight view with other participants as small tiles. A mini picture-in-picture preview should appear when navigating away from the video view.

## User Steps

### Current behavior

1. User clicks a voice channel in the sidebar (joins via `Client.join_voice_channel()`)
2. User sees participants listed below the voice channel item, with V/S indicators for video/screen share
3. User sees the voice bar with Mic/Deaf/Cam/Share/SFX/Settings/Disconnect buttons
4. User clicks "Cam" to toggle camera on/off (creates/stops camera track via `Client.toggle_video()`)
5. User clicks "Share" to open screen/window picker dialog, selects a source to start sharing
6. Video grid appears as a fixed-height strip above the message content area, showing tiles for all video/screen share participants
7. User sees other participants' video feeds when GDExtension `track_received` is available (placeholder tiles with initials otherwise)
8. User clicks "Sharing" to stop screen share, or "Cam On" to stop camera

### Target behavior (Discord-style)

1. User clicks a voice channel in the sidebar (joins via `Client.join_voice_channel()`)
2. User sees participants listed below the voice channel item, with camera/screen share icons
3. User sees the voice bar at the bottom of the sidebar with mute/deafen/cam/share/disconnect controls
4. User clicks the voice channel name in the voice bar (or the voice channel again when connected) to open the **full-area video view** that replaces the message content area
5. The video view shows all participants in an adaptive grid: 1 person = full area, 2 = side by side, 3-4 = 2x2, 5+ = auto-grid with responsive columns
6. When someone screen shares, their stream appears as the **spotlight** (large main area) with other participants shown as a strip of small tiles along the side or bottom
7. User can click any text channel to return to the normal message view -- voice continues in the background, and a **mini PiP** (picture-in-picture) preview floats in the corner showing the active speaker or screen share
8. User clicks "Cam" / "Share" / "Sharing" / "Cam On" in the voice bar to toggle camera/screen share as before
9. Double-clicking a participant tile in the video view focuses them (spotlight mode)
10. User clicks Disconnect in the voice bar to leave voice -- PiP disappears and video view closes

## Signal Flow

```
  (GDScript pipeline fully wired -- activates when GDExtension exposes track_received)

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

### Discord-style view switching (target)

```
  User clicks voice channel (already connected)
       |
       v
  channel_list._on_channel_pressed()  --(voice channel, already in)-->
       |
       v
  AppState.voice_view_opened.emit(channel_id)
       |
       v
  main_window._on_voice_view_opened()
       |-- hide message_view, topic_bar, tab_bar
       |-- show video_grid as full-area (size_flags_vertical = EXPAND_FILL)
       |-- show voice controls toolbar above the grid
       |
  User clicks a text channel
       |
       v
  AppState.channel_selected.emit(channel_id)
       |
       v
  main_window._on_channel_selected()
       |-- hide full-area video_grid
       |-- show message_view, topic_bar, tab_bar
       |-- spawn mini PiP overlay in bottom-right corner
       |
  User clicks Disconnect
       |
       v
  Client.leave_voice_channel()
       |-- remove PiP overlay
       |-- hide video grid
       |-- AppState.leave_voice() -> voice_left signal
```

## Key Files

| File | Role |
|------|------|
| `addons/accordstream/` | GDExtension binary: AccordStream singleton, AccordPeerConnection, AccordMediaTrack, AccordVoiceSession |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState model with `self_video` (line 15) and `self_stream` (line 14) flags |
| `addons/accordkit/models/voice_server_update.gd` | AccordVoiceServerUpdate: backend type, LiveKit URL, token, SFU endpoint |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()` (line 23), `leave()` (line 32), `get_status()` (line 46) |
| `addons/accordkit/voice/voice_manager.gd` | Voice lifecycle: join/leave, voice_connected/voice_disconnected signals |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway voice events: `voice_state_update` (line 52), `voice_server_update` (line 53), `voice_signal` (line 54) |
| `addons/accordkit/core/accord_client.gd` | Re-emits voice signals (lines 227-229), exposes `voice` API (line 107) and `voice_manager` (line 109) |
| `scripts/autoload/app_state.gd` | Voice signals: `voice_state_updated` (line 52), `voice_joined` (line 54), `voice_left` (line 56), `voice_error` (line 58), `voice_mute_changed` (line 60), `voice_deafen_changed` (line 62), `video_enabled_changed` (line 64), `screen_share_changed` (line 66), `remote_track_received` (line 68), `remote_track_removed` (line 70); state vars: `voice_channel_id` (line 144), `voice_guild_id` (line 145), `is_voice_muted` (line 146), `is_voice_deafened` (line 147), `is_video_enabled` (line 148), `is_screen_sharing` (line 149) |
| `scripts/autoload/client.gd` | Voice session setup (lines 135-155), voice state cache `_voice_state_cache` (line 85), `_camera_track` (line 115), `_screen_track` (line 116), `_remote_tracks` (line 117), `_accord_stream` singleton reference (line 118) |
| `scripts/autoload/client_voice.gd` | Voice mutation API: `join_voice_channel()` (line 23), `leave_voice_channel()` (line 89), `toggle_video()` (line 150), `start_screen_share()` (line 186), `stop_screen_share()` (line 209), remote track handler `on_track_received()` (line 275), session callbacks (lines 234-304) |
| `scripts/autoload/client_gateway.gd` | Voice gateway signal connections (lines 87-92) |
| `scripts/autoload/client_gateway_events.gd` | Voice event handlers: `on_voice_state_update` (line 89), `on_voice_server_update` (line 129), `on_voice_signal` (line 134) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` (line 363): REST voice status -> cache -> signal |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` includes `self_video`/`self_stream`, `channel_to_dict()` includes `voice_users` |
| `scripts/autoload/config_voice.gd` | Voice/video settings helper: input/output device (lines 11-34), video device (line 37), resolution preset (line 50), fps (line 63) |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel UI: expandable participant list, green icon when connected, mute/deaf/video/stream indicators (lines 86-184) |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene: VBoxContainer with button + participant container |
| `scenes/sidebar/voice_bar.gd` | Voice connection bar: mute/deafen/cam/share/sfx/settings/disconnect buttons, self-manages visibility via AppState signals |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: PanelContainer with status row + button row |
| `scenes/sidebar/screen_picker_dialog.gd` | Screen/window picker overlay: tabs for screens/windows, enumerates via AccordStream, emits `source_selected` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: ColorRect overlay with centered panel, TabBar, ScrollContainer with source buttons |
| `scenes/sidebar/channels/channel_list.gd` | Conditional voice channel instantiation (lines 119-129), voice join/leave on click (lines 171-184), auto-select skips voice (lines 155-166) |
| `scenes/sidebar/channels/category_item.gd` | Conditional voice channel instantiation in categories |
| `scenes/sidebar/sidebar.tscn` | VoiceBar between DMList and UserBar in ChannelPanel VBox |
| `scenes/main/main_window.gd` | Content area layout: sidebar + content_area VBox (ContentHeader/TopicBar/VideoGrid/ContentBody) |
| `scenes/main/main_window.tscn` | VideoGrid placed between TopicBar and ContentBody (line 88) |
| `scenes/video/video_tile.gd` | Video frame rendering component: local live feed via AccordMediaTrack polling, or placeholder with initials |
| `scenes/video/video_tile.tscn` | Video tile scene: PanelContainer with TextureRect (160x120 min), InitialsLabel, NameBar |
| `scenes/video/video_grid.gd` | Self-managing video grid: rebuilds tiles from AppState signals, responsive column layout, renders remote tracks live when available via `Client.get_remote_track()` |
| `scenes/video/video_grid.tscn` | Video grid scene: PanelContainer (140px min height) > ScrollContainer > GridContainer |
| `tests/accordstream/integration/test_end_to_end.gd` | Video publish flow tests, screen share tests, audio+video tests |
| `tests/accordstream/integration/test_media_tracks.gd` | Camera/screen/window track creation tests |
| `tests/accordstream/integration/test_peer_connection.gd` | Peer connection tests: video media in SDP, track management, ICE, state enums |
| `tests/accordstream/integration/test_device_enumeration.gd` | Device enumeration tests: cameras, screens, windows |
| `tests/accordstream/integration/test_voice_session.gd` | Voice session tests: state machine, mute/deafen, peer tracking, custom SFU connection |

## Implementation Details

### Voice Data Layer -- Implemented

Voice gateway events are fully wired through the data layer:

**AppState signals** (`app_state.gd`):
- `voice_state_updated(channel_id)` (line 52) -- emitted when voice participants change
- `voice_joined(channel_id)` (line 54) -- emitted when local user joins voice
- `voice_left(channel_id)` (line 56) -- emitted when local user leaves voice
- `voice_error(error)` (line 58) -- emitted on voice connection failure
- `voice_mute_changed(is_muted)` (line 60) -- emitted when mute state changes
- `voice_deafen_changed(is_deafened)` (line 62) -- emitted when deafen state changes
- `video_enabled_changed(is_enabled)` (line 64) -- emitted when camera state changes
- `screen_share_changed(is_sharing)` (line 66) -- emitted when screen share state changes
- `remote_track_received(user_id, track)` (line 68) -- emitted when a remote peer's video track arrives
- `remote_track_removed(user_id)` (line 70) -- emitted when a remote peer's track is cleaned up

**AppState state vars** (`app_state.gd`):
- `voice_channel_id: String` (line 144) -- current voice channel (empty if not connected)
- `voice_guild_id: String` (line 145) -- guild of current voice channel
- `is_voice_muted: bool` (line 146) -- local mute state
- `is_voice_deafened: bool` (line 147) -- local deafen state
- `is_video_enabled: bool` (line 148) -- camera is active
- `is_screen_sharing: bool` (line 149) -- screen/window share is active

**AppState helpers** (`app_state.gd`):
- `join_voice(channel_id, guild_id)` (line 242) -- sets state, emits `voice_joined`
- `leave_voice()` (line 247) -- clears state, resets mute/deafen/video/screen, emits `voice_left`
- `set_voice_muted(muted)` (line 258) -- updates state, emits `voice_mute_changed`
- `set_voice_deafened(deafened)` (line 262) -- updates state, emits `voice_deafen_changed`
- `set_video_enabled(enabled)` (line 266) -- updates state, emits `video_enabled_changed`
- `set_screen_sharing(sharing)` (line 270) -- updates state, emits `screen_share_changed`

**ClientModels.voice_state_to_dict()**:
Converts `AccordVoiceState` to dict with keys: `user_id`, `channel_id`, `session_id`, `self_mute`, `self_deaf`, `self_video`, `self_stream`, `mute`, `deaf`, `user` (user dict from cache).

**Client voice state cache** (`client.gd`):
- `_voice_state_cache: Dictionary = {}` (line 85) -- keyed by channel_id, values are Arrays of voice state dicts
- `_voice_server_info: Dictionary = {}` (line 86) -- stored AccordVoiceServerUpdate for active connection

**Client voice mutation API** (`client_voice.gd`):
- `join_voice_channel(channel_id) -> bool` (line 23) -- leaves current voice if any, calls `VoiceApi.join()`, connects AccordVoiceSession based on backend type (LiveKit or custom SFU), emits `AppState.join_voice()`, fetches voice states
- `leave_voice_channel() -> bool` (line 89) -- cleans up camera/screen/remote tracks, disconnects voice session, calls `VoiceApi.leave()`, removes self from cache, emits `AppState.leave_voice()`
- `set_voice_muted(muted)` (line 138) -- forwards to `_voice_session.set_muted()` and `AppState.set_voice_muted()`
- `set_voice_deafened(deafened)` (line 143) -- forwards to `_voice_session.set_deafened()` and `AppState.set_voice_deafened()`

**Client gateway signal connections** (`client_gateway.gd` lines 87-92):
- `client.voice_state_update` -> `_events.on_voice_state_update`
- `client.voice_server_update` -> `_events.on_voice_server_update`
- `client.voice_signal` -> `_events.on_voice_signal`

**ClientGatewayEvents voice handlers** (`client_gateway_events.gd`):
- `on_voice_state_update(state, conn_index)` (line 89) -- converts to dict via `voice_state_to_dict()`, removes user from previous channel, adds to new channel, updates `voice_users` count in channel cache, emits `voice_state_updated`, plays peer join/leave sound, detects force-disconnect
- `on_voice_server_update(info, conn_index)` (line 129) -- stores info in `_voice_server_info`
- `on_voice_signal(data, conn_index)` (line 134) -- forwards to `AccordVoiceSession.handle_voice_signal()` via meta reference

**ClientFetch.fetch_voice_states()** (`client_fetch.gd` line 363):
Calls `VoiceApi.get_status(channel_id)`, converts each `AccordVoiceState` via `voice_state_to_dict()`, populates `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`.

### Voice Channel UI -- Implemented

**voice_channel_item.gd** -- Dedicated VBoxContainer scene for voice channels:
- Exposes `channel_pressed` signal, `setup(data)`, `set_active(bool)` for polymorphism with `channel_item`
- Top row: Button with voice icon, channel name, user count label
- Below: `ParticipantContainer` VBoxContainer populated by `_refresh_participants()` (line 86)
- Listens to `voice_state_updated`, `voice_joined`, `voice_left` signals (lines 32-34)
- Green icon tint (`Color(0.231, 0.647, 0.365)`) when user is connected to this channel (line 103)
- Each participant row: 28px indent + 18x18 avatar + display name + mute/deaf indicators + green "V" for video + blue "S" for screen share (lines 110-184)
- Gear button + context menu for channel edit/delete (requires MANAGE_CHANNELS permission)
- Drag-and-drop reordering within the same guild (lines 233-305)

**channel_list.gd** voice integration:
- `VoiceChannelItemScene` preloaded (line 7)
- Uncategorized loop (lines 119-129): checks `ch.get("type", 0) == ClientModels.ChannelType.VOICE`, instantiates `VoiceChannelItemScene` for voice, `ChannelItemScene` for others
- `_on_channel_pressed()` (lines 171-184): voice channels toggle `Client.join_voice_channel()` / `Client.leave_voice_channel()` instead of emitting `channel_selected`. Text channel message view stays in place
- Auto-select (lines 155-166): skips both `CATEGORY` and `VOICE` channel types

### Voice Connection Bar -- Implemented

**voice_bar.gd** -- Self-managing PanelContainer in sidebar:
- Hidden by default, shows on `voice_joined`, hides on `voice_left` (lines 35-54)
- Status row: green `ColorRect` dot + channel name label (looked up from `Client.get_channels_for_guild()`)
- Button row: Mic, Deaf, Cam, Share, SFX, Settings, Disconnect (lines 9-17)
- Mute button: toggles via `Client.set_voice_muted()`, red tint `StyleBoxFlat` when active (line 56)
- Deafen button: toggles via `Client.set_voice_deafened()`, red tint when active (line 59)
- Cam button: toggles via `Client.toggle_video()`, green tint when active ("Cam On") (line 62)
- Share button: opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`, green tint when active ("Sharing") (line 65)
- SFX button: opens/closes soundboard panel, visibility gated on `USE_SOUNDBOARD` permission (line 78)
- Settings button: opens User Settings on page 2 (Voice & Video) (line 100)
- Disconnect button: calls `Client.leave_voice_channel()` (line 105)
- Listens to `video_enabled_changed` and `screen_share_changed` signals to update button visuals (lines 32-33)

**screen_picker_dialog.gd** -- Full-screen semi-transparent overlay:
- Two tabs: Screens and Windows (via TabBar)
- Populates source buttons from `AccordStream.get_screens()` / `AccordStream.get_windows()`
- Each button shows source title and resolution
- Emits `source_selected(source_type: String, source_id: int)` on pick
- Self-destructs on close/backdrop click/Escape

**sidebar.tscn**: VoiceBar placed between DMList and UserBar in `ChannelPanel` VBox. Self-manages via AppState signals -- no changes to `sidebar.gd` required.

### AccordVoiceSession Integration -- Implemented

**Client owns AccordVoiceSession** (`client.gd` lines 135-155):
- `_voice_session` instantiated from `AccordVoiceSession` ClassDB if available (line 136), added as child node (line 138)
- Stored as meta `"_voice_session"` for gateway access (line 139)
- Connected signals: `session_state_changed` (line 140), `peer_joined` (line 143), `peer_left` (line 146), `signal_outgoing` (line 149)
- Runtime `track_received` signal check: `if _voice_session.has_signal("track_received")` connects to `voice.on_track_received` (lines 152-155)

**Join flow** (`client_voice.gd` lines 23-60):
After REST `VoiceApi.join()` succeeds, the response `AccordVoiceServerUpdate` determines backend:
- LiveKit: `_voice_session.connect_livekit(url, token)` (line 72)
- Custom SFU: `_voice_session.connect_custom_sfu(endpoint, ice_config, mic_id)` (line 85) -- picks microphone from `Config.voice.get_input_device()`, falls back to first from `AccordStream.get_microphones()` (lines 76-80). Also sets output device if configured (lines 81-83)

**Leave flow** (`client_voice.gd` lines 89-136):
Cleans up camera track, screen track, all remote tracks, then `_voice_session.disconnect_voice()`, REST `VoiceApi.leave()`, removes self from voice state cache, clears `_voice_server_info`, calls `AppState.leave_voice()`.

**Mute/deafen** (`client_voice.gd` lines 138-146):
Both forward to `_voice_session.set_muted()` / `set_deafened()` and `AppState`.

### Video Track Management -- Implemented

**Client video API** (`client_voice.gd`):
- `toggle_video()` (line 150) -- creates camera track via `AccordStream.create_camera_track()` using `Config.voice` settings for device, resolution, and fps, or stops existing one. Emits `voice_error` if no camera found. Falls back to first camera if saved device is gone
- `start_screen_share(source_type, source_id)` (line 186) -- creates screen or window track via `AccordStream.create_screen_track(id, 15)` / `create_window_track(id, 15)`. Stops any existing screen track first
- `stop_screen_share()` (line 209) -- stops and nulls screen track
- `_send_voice_state_update()` (line 216) -- sends gateway voice state update with all flags (mute, deaf, video, stream)
- Track cleanup in `leave_voice_channel()` (lines 93-105) -- stops camera, screen, and all remote tracks before disconnecting

**AccordKit gateway** (`gateway_socket.gd`, `accord_client.gd`):
`update_voice_state()` (line 165 in `accord_client.gd`) accepts `self_video: bool = false, self_stream: bool = false` as additional default parameters. The payload includes both flags. Backward compatible -- existing callers don't need changes.

### Video Settings Persistence (Config)

**ConfigVoice** (`config_voice.gd`) stores voice/video preferences in the `[voice]` section:
- `get_input_device()` / `set_input_device(device_id)` -- microphone device (line 11)
- `get_output_device()` / `set_output_device(device_id)` -- speaker device (line 24)
- `get_video_device()` / `set_video_device(device_id)` -- camera device (line 37)
- `get_video_resolution()` / `set_video_resolution(preset)` -- resolution presets: 0=480p (640x480), 1=720p (1280x720), 2=360p (640x360) (line 50)
- `get_video_fps()` / `set_video_fps(fps)` -- frame rate, default 30 (line 63)

### Video Tile -- Implemented (video_tile.gd / video_tile.tscn)

`PanelContainer` (160x120 min size) with dark background, `TextureRect` for video frames, initials label for placeholders, and a name bar with mute indicator.

Two setup modes:
- `setup_local(track, user)` (line 12) -- attaches video sink, polls `has_video_frame()` / `get_video_frame()` each `_process()` frame, renders into `ImageTexture`
- `setup_placeholder(user, voice_state)` (line 27) -- shows user initials (max 2 chars) and name, mute indicator, no live video

Calls `attach_video_sink()` / `detach_video_sink()` if available on the track (lines 24, 66-69).

### Video Grid -- Implemented (video_grid.gd / video_grid.tscn)

**Current layout:** Self-managing `PanelContainer` > `ScrollContainer` > `GridContainer` placed in `main_window.tscn` between `TopicBar` and `ContentBody` (line 88). Fixed 140px minimum height. This behaves as an **inline strip** above the message area -- not Discord-style.

- Listens to `video_enabled_changed`, `screen_share_changed`, `voice_state_updated`, `voice_left`, `remote_track_received`, `remote_track_removed`, `layout_mode_changed` (lines 11-29)
- Rebuilds tiles on any change: local camera tile, local screen share tile, remote peer placeholder tiles (lines 73-137)
- Grid columns adapt to layout mode: 1 for COMPACT, 2 for MEDIUM/FULL (lines 60-67)
- Self-hides when no tiles exist, self-shows when tiles are added (line 137)
- Remote peers with `self_video` or `self_stream` flags get placeholder tiles unless a live remote track is available via `Client.get_remote_track()` (lines 116-134)

**Public track accessors** on `Client`:
- `get_camera_track() -> AccordMediaTrack`
- `get_screen_track() -> AccordMediaTrack`

### Remote Video Rendering Pipeline -- Implemented

The full GDScript pipeline for rendering remote video tracks is in place. It activates automatically when the AccordStream GDExtension exposes a `track_received(user_id: String, track: AccordMediaTrack)` signal on `AccordVoiceSession`.

**Client remote track cache** (`client.gd`):
- `_remote_tracks: Dictionary = {}` (line 117) -- keyed by user_id, values are `AccordMediaTrack` instances
- Runtime signal check in `_ready()`: `if _voice_session.has_signal("track_received")` connects to `voice.on_track_received` (lines 152-155)

**ClientVoice track handling** (`client_voice.gd`):
- `on_track_received(user_id, track)` (line 275) -- filters to video tracks only (`get_kind() == "video"`), stops any previous track for the same peer, stores in `_remote_tracks`, emits `remote_track_received`
- `on_peer_left()` (line 251) -- stops and erases remote track for the departing peer, emits `remote_track_removed`
- `leave_voice_channel()` (lines 100-105) -- stops all remote tracks and clears `_remote_tracks` before disconnecting the session

**VideoGrid integration** (`video_grid.gd`):
- Connects to `remote_track_received` and `remote_track_removed` signals to trigger rebuild (lines 21-26)
- During `_rebuild()`, for each remote peer with `self_video` or `self_stream`, calls `Client.get_remote_track(uid)` (line 127)
- If a remote track exists, creates a live tile via `tile.setup_local(remote_track, user)` (same rendering path as local camera/screen tiles)
- Falls back to `tile.setup_placeholder(user, state)` when no track is available (line 134)

**Data flow:**
```
AccordVoiceSession.track_received(user_id, track)
    |
    v
ClientVoice.on_track_received()
    |-- filters to kind=="video"
    |-- stores in Client._remote_tracks[user_id]
    |-- emits AppState.remote_track_received
         |
         v
    VideoGrid._on_remote_track_received() -> _rebuild()
         |-- Client.get_remote_track(uid) -> AccordMediaTrack
         |-- tile.setup_local(track, user)
              |-- attach_video_sink()
              |-- _process() polls has_video_frame() / get_video_frame()
              |-- renders into ImageTexture -> TextureRect
```

### AccordStream Device Enumeration

The AccordStream engine singleton provides four device enumeration methods:

- `get_cameras() -> Array` -- Returns `[{id: String, name: String}, ...]` for connected webcams
- `get_microphones() -> Array` -- Returns `[{id: String, name: String}, ...]` for audio input devices
- `get_screens() -> Array` -- Returns `[{id: int, title: String, width: int, height: int}, ...]` for displays
- `get_windows() -> Array` -- Returns `[{id: int, title: String, width: int, height: int}, ...]` for application windows

### AccordStream Media Track Creation

Video tracks are created via AccordStream factory methods:

- `create_camera_track(device_id: String, width: int, height: int, fps: int) -> AccordMediaTrack` -- Webcam capture
- `create_screen_track(screen_id: int, fps: int) -> AccordMediaTrack` -- Full screen capture
- `create_window_track(window_id: int, fps: int) -> AccordMediaTrack` -- Single window capture

**AccordMediaTrack API:**
- `get_id() -> String` -- Unique track ID
- `get_kind() -> String` -- `"audio"` or `"video"`
- `get_state() -> int` -- `TRACK_STATE_LIVE` (0) or `TRACK_STATE_ENDED` (1)
- `is_enabled() -> bool` / `set_enabled(bool)` -- Enable/disable track without destroying it
- `stop()` -- Ends the track, emits `state_changed(TRACK_STATE_ENDED)` signal

### AccordPeerConnection for Video

`AccordStream.create_peer_connection(config: Dictionary) -> AccordPeerConnection` creates a WebRTC peer connection.

**Config format:**
```gdscript
{"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
```

**Track management:**
- `add_track(track: AccordMediaTrack) -> int` -- Adds a media track to the connection. Returns `OK` on success
- `remove_track(track: AccordMediaTrack) -> int` -- Removes a track
- `get_senders() -> Array` -- Returns `[{track_id: String, track_kind: String}, ...]`
- `get_receivers() -> Array` -- Returns `[{track_kind: String, audio_level: float}, ...]`

**SDP negotiation:**
- `create_offer()` -- Async, emits `offer_created(sdp: String, type: String)`. When video tracks are added, the SDP contains `m=video` media sections
- `create_answer()` -- Emits `answer_created(sdp: String, type: String)`
- `set_local_description(type, sdp) -> int` / `set_remote_description(type, sdp) -> int`
- `add_ice_candidate(mid, index, sdp) -> int`

**Signals:**
- `offer_created(sdp, type)` / `answer_created(sdp, type)`
- `ice_candidate_generated(mid, index, sdp)`
- `track_received(track: Dictionary)` -- Remote track from peer

**Connection state enums:**
- Connection: NEW(0), CONNECTING(1), CONNECTED(2), DISCONNECTED(3), FAILED(4), CLOSED(5)
- Signaling: STABLE(0), HAVE_LOCAL_OFFER(1), HAVE_LOCAL_PRANSWER(2), HAVE_REMOTE_OFFER(3), HAVE_REMOTE_PRANSWER(4), CLOSED(5)
- ICE: NEW(0), CHECKING(1), CONNECTED(2), COMPLETED(3), FAILED(4), DISCONNECTED(5), CLOSED(6)

### AccordVoiceState Video Flags (voice_state.gd)

The `AccordVoiceState` model includes two video-related boolean flags:

- `self_video: bool = false` (line 15) -- User is transmitting camera video
- `self_stream: bool = false` (line 14) -- User is screen sharing

These are serialized via `from_dict()` (lines 35-36) and `to_dict()` (lines 49-50), and are sent/received through the gateway `voice.state_update` event. The `voice_state_to_dict()` conversion in `client_models.gd` includes both `self_video` and `self_stream` in its output dict.

## Implementation Status

- [x] AccordStream GDExtension with WebRTC peer connections
- [x] Camera/screen/window enumeration and video track creation
- [x] AccordMediaTrack enable/disable toggle
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
- [x] Client voice gateway event handlers with sound effects for peer join/leave
- [x] AppState voice/video signals and state tracking
- [x] Client voice mutation API with track cleanup
- [x] Voice state cache with data access API
- [x] ClientModels `voice_state_to_dict()` conversion
- [x] ClientFetch `fetch_voice_states()` for REST-based voice state population
- [x] Dedicated `voice_channel_item` scene with expandable participant list, drag-and-drop reorder, edit/delete context menu
- [x] Voice channel click toggles join/leave (does not emit `channel_selected`)
- [x] Auto-select skips voice channels
- [x] Voice bar with mute/deafen/cam/share/sfx/settings/disconnect buttons
- [x] Voice bar self-manages visibility via AppState signals
- [x] AccordVoiceSession wired into Client (join connects SFU/LiveKit, leave disconnects, mute/deafen forwarded)
- [x] Gateway voice signals forwarded to AccordVoiceSession
- [x] Force-disconnect detection (gateway voice_state_update with null channel_id)
- [x] Video enable/disable UI (Cam button in voice bar)
- [x] Screen sharing UI (Share button + screen/window picker dialog)
- [x] Video/stream indicators in voice channel participant rows (green V, blue S)
- [x] Track cleanup on voice disconnect (camera, screen, all remote tracks)
- [x] Local video preview via `VideoTile` polling `AccordMediaTrack.has_video_frame()` / `get_video_frame()`
- [x] Video participant grid layout with responsive column count
- [x] Camera device selection in voice settings
- [x] Video quality settings (resolution presets + frame rate) persisted via `ConfigVoice`
- [x] Input/output device selection and persistence
- [x] Public track accessors (`Client.get_camera_track()`, `Client.get_screen_track()`)
- [x] Remote video rendering pipeline (track cache, signal wiring, grid integration -- activates when GDExtension exposes `track_received`)
- [ ] **Full-area video view** (Discord-style: replaces message content when viewing voice channel)
- [ ] **Screen share spotlight layout** (large main view + small participant strip)
- [ ] **Mini PiP overlay** (floating preview when navigating away from voice channel)
- [ ] **Adaptive grid sizing** (auto-layout based on participant count: 1=full, 2=halves, 3-4=2x2, etc.)
- [ ] **Voice bar click to open video view** (clicking channel name in voice bar opens full-area view)
- [ ] **Active speaker detection** (green border or focus on speaking user)
- [ ] **Double-click to spotlight** (focusing a specific participant)
- [ ] Bandwidth adaptation for video streams

## Gaps / TODO

### Discord-Style UI Redesign (High Priority)

| Gap | Severity | Notes |
|-----|----------|-------|
| Video grid is an inline strip, not full-area | High | Currently `VideoGrid` sits between `TopicBar` and `ContentBody` in `main_window.tscn` (line 88) with a fixed 140px min height. Discord shows video as a **full content area** that replaces the message view. Need to: (1) add `voice_view_opened` / `voice_view_closed` signals to `AppState`, (2) toggle visibility of `message_view` vs `video_grid` in `main_window.gd`, (3) make `video_grid` fill the full `ContentBody` area (`size_flags_vertical = SIZE_EXPAND_FILL`) |
| No screen share spotlight layout | High | Discord shows the shared screen as the dominant large view with participants as a small strip alongside. Current grid treats all tiles equally (uniform `GridContainer`). Need: (1) an `HBoxContainer` or `VBoxContainer` layout with a large `FocusedTile` and a scrollable `ParticipantStrip`, (2) logic in `_rebuild()` to detect screen share tiles and assign them the spotlight role, (3) double-click on any tile to manually spotlight it |
| No mini PiP (picture-in-picture) | Medium | When user navigates to a text channel while in voice, Discord shows a small floating video preview in the bottom-right corner. Need: (1) a `PiPOverlay` scene (small `PanelContainer` with a single `VideoTile`), (2) spawn it in `main_window.gd` when switching from voice view to text view while `voice_channel_id` is non-empty, (3) show active speaker or screen share in the PiP, (4) click PiP to return to full video view, (5) remove PiP on `voice_left` |
| Voice bar doesn't open video view on click | Medium | Discord lets you click the voice channel name in the voice bar to jump to the video view. Currently `voice_bar.gd` only has controls (mute/cam/etc), the status row is not clickable. Need to make `channel_label` or `StatusRow` a `Button` that emits `voice_view_opened` |
| No active speaker detection | Medium | Discord highlights the currently speaking user with a green border around their tile. Would need audio level data from `AccordVoiceSession` (peer audio levels) and a `speaking_changed(user_id, is_speaking)` signal to drive a green `StyleBoxFlat` border on the active tile |
| Adaptive grid doesn't match Discord sizing | Low | Current grid is 1 column on COMPACT, 2 on MEDIUM/FULL. Discord dynamically sizes: 1 person fills the area, 2 split side-by-side, 3-4 are 2x2, 5-9 are 3x3, etc. Should calculate columns from participant count in `_update_grid_columns()` |
| No tile interaction (double-click to focus) | Low | Discord allows clicking/double-clicking a participant tile to spotlight them (switch to focused layout). No input handling on `video_tile.gd` currently |

### Existing Gaps

| Gap | Severity | Notes |
|-----|----------|-------|
| Remote video rendering blocked on GDExtension | High | GDScript pipeline is complete (`_remote_tracks` cache, `track_received` signal wiring, `VideoGrid` live tile rendering). Activates automatically when AccordStream GDExtension exposes `track_received(user_id, track)` on `AccordVoiceSession`. Until then, remote peers with `self_video`/`self_stream` get placeholder tiles with name/initials |
| LiveKit backend is a stub | High | `AccordVoiceSession.connect_livekit()` does not actually connect -- remains in DISCONNECTED state. Only custom SFU works |
| No bandwidth adaptation | Low | Fixed video parameters with no dynamic quality adjustment based on network conditions |
| No video track hot-swap | Low | Switching cameras requires stopping the old track and creating a new one. No seamless hot-swap mechanism |
