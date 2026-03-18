# Video Chat

Last touched: 2026-03-18 (closed all open tasks: resize handle idle dots, bandwidth adaptation, camera device routing, camera hot-swap all confirmed implemented)
Priority: 23
Depends on: Voice Channels, Server Plugins

## Overview

Video chat in daccord enables camera video and screen/window sharing within voice channels. The godot-livekit GDExtension (`addons/godot-livekit/`) provides WebRTC infrastructure via `LiveKitRoom`, and the `LiveKitAdapter` GDScript wrapper manages publishing/unpublishing video tracks through `LiveKitLocalVideoTrack` and `LiveKitVideoSource`. The AccordVoiceState model tracks `self_video` and `self_stream` flags per user. Voice channels have full join/leave/mute/deafen support via `client.gd`, with a dedicated `voice_channel_item` scene and `voice_bar` for controls. The full pipeline is implemented: voice bar has Cam/Share buttons, the video grid renders local camera and screen share tiles live via `LiveKitVideoStream.poll()` + `.get_texture()`, and the remote rendering pipeline uses `track_received` signal on `LiveKitAdapter` to create live video tiles for remote peers. Screen capture uses `LiveKitScreenCapture` for native monitor and window frame capture with dynamic downscaling.

**Discord-style target design:** The video UI replaces the message content area with a full-area video view when the user is in a voice channel and wants to see video. Clicking the voice channel name in the voice bar (or the voice channel itself when already connected) opens this full-area view. Clicking any text channel returns to the normal message view while voice continues in the background. A screen share appears as the dominant/spotlight view with other participants as small tiles. A mini picture-in-picture preview appears when navigating away from the video view.

**Activity integration:** Server plugins can launch activities (games, collaborative tools) that render inside the spotlight area of the video grid. The activity lifecycle (lobby → running → ended) is managed through AppState signals, with the activity viewport rendered via `SubViewport` texture forwarding and input coordinate remapping. A vertical resize handle between the spotlight/activity area and the participant grid allows users to adjust the split, though the handle is currently invisible until hovered (see Gaps).

## User Steps

1. User clicks a voice channel in the sidebar (joins via `Client.join_voice_channel()`)
2. User sees participants listed below the voice channel item, with V/S indicators for video/screen share
3. User sees the voice bar with Mic/Deaf/Cam/Share/SFX/Settings/Disconnect buttons; status shows "Connecting..." with pulsing yellow dot
4. LiveKit session connects; voice bar shows channel name with solid green dot
5. User clicks "Cam" to toggle camera on/off (creates/stops camera track via `Client.toggle_video()`)
6. User clicks "Share" to open screen picker dialog (enumerates monitors and windows via `LiveKitScreenCapture`), selects a source to start sharing
7. Video grid appears as a fixed-height strip above the message content area, showing tiles for all video/screen share participants
8. User clicks the voice channel name in the voice bar (or the voice channel again when connected) to open the **full-area video view** that replaces the message content area
9. The video view shows all participants in an adaptive grid: 1 person = full area, 2 = side by side, 3-4 = 2x2, 5+ = auto-grid with responsive columns
10. When someone screen shares, their stream appears as the **spotlight** (large main area) with other participants shown as a strip of small tiles
11. User double-clicks a participant tile to manually spotlight them
12. User clicks any text channel to return to the normal message view -- voice continues in the background, and a **mini PiP** (picture-in-picture) preview floats in the corner
13. User clicks "Sharing" to stop screen share, or "Cam On" to stop camera
14. User clicks the chat button on a voice channel to open **voice text chat** (linked text channel)
15. User clicks Disconnect in the voice bar to leave voice -- PiP disappears and video view closes

## Signal Flow

```
  User clicks "Enable Camera"        LiveKitAdapter
       |                                  |
       |-- publish_camera(res, fps) ----->|
       |   (creates LiveKitVideoSource,  |
       |    LiveKitLocalVideoTrack,       |
       |    publishes via                 |
       |    LiveKitLocalParticipant)      |
       |                                  |
       |   Returns LiveKitVideoStream    |
       |   for local preview             |
       |                                  |
       |   Remote peers receive track    |
       |   via LiveKit internally        |
       |                                  |
       |   track_subscribed signal ------>|
       |   -> _on_track_subscribed()      |
       |   -> LiveKitVideoStream          |
       |      .from_track()               |
       |   -> track_received signal       |
       |                                  |
       |                        AccordVoiceState
       |                              |   self_video = true
       |                              |   (gateway voice.state_update)

  Screen share follows same flow but with:
       |-- publish_screen(source) ----->|
       |   (creates LiveKitScreenCapture |
       |    from monitor/window dict,    |
       |    downscales to capped size,   |
       |    publishes with               |
       |    SOURCE_SCREENSHARE)          |
       |   self_stream = true            |
```

### View switching

```
  User clicks voice channel (already connected)
       |
       v
  channel_list._on_channel_pressed()  --(voice channel, already in)-->
       |
       v
  AppState.open_voice_view()
       |-- sets is_voice_view_open = true
       |-- voice_view_opened.emit(channel_id)
       |
       v
  main_window._on_voice_view_opened()
       |-- hide message_view, topic_bar, tab_bar
       |-- show video_grid as full-area (size_flags_vertical = EXPAND_FILL)
       |
  User clicks a text channel
       |
       v
  AppState.channel_selected.emit(channel_id)
       |
       v
  main_window._on_channel_selected()
       |-- close_voice_view() -> hide full-area video_grid
       |-- show message_view, topic_bar, tab_bar
       |-- spawn mini PiP overlay in bottom-right corner
       |
  User clicks Disconnect
       |
       v
  Client.leave_voice_channel()
       |-- close camera/screen/remote tracks
       |-- disconnect_voice()
       |-- REST VoiceApi.leave()
       |-- AppState.leave_voice() clears all state, closes voice view, clears spotlight
       |-- remove PiP overlay via voice_left signal
```

## Key Files

| File | Role |
|------|------|
| `addons/godot-livekit/` | godot-livekit GDExtension: LiveKitRoom, LiveKitVideoStream, LiveKitAudioStream, LiveKitVideoSource, LiveKitLocalVideoTrack, LiveKitScreenCapture |
| `scripts/autoload/livekit_adapter.gd` | LiveKitAdapter GDScript wrapper: connect_to_room(), publish_camera(), publish_screen(), unpublish_camera(), unpublish_screen(), track_received signal, screen capture frame loop, audio level detection |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState model with `self_video` (line 15) and `self_stream` (line 14) flags |
| `addons/accordkit/models/voice_server_update.gd` | AccordVoiceServerUpdate: backend type, LiveKit URL, token, SFU endpoint |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice lifecycle: join/leave, voice_connected/voice_disconnected signals |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway voice events: `voice_state_update`, `voice_server_update`, `voice_signal`; `update_voice_state()` with video/stream params |
| `addons/accordkit/core/accord_client.gd` | `update_voice_state()` (line 167) with `self_video`/`self_stream` params; re-emits voice signals; exposes `voice` API (line 107) |
| `scripts/autoload/app_state.gd` | Voice signals (lines 52-84): `voice_state_updated`, `voice_joined`, `voice_left`, `voice_error`, `voice_session_state_changed`, `voice_mute_changed`, `voice_deafen_changed`, `video_enabled_changed`, `screen_share_changed`, `remote_track_received`, `remote_track_removed`, `speaking_changed`, `voice_view_opened`, `voice_view_closed`, `voice_text_opened`, `voice_text_closed`, `spotlight_changed`. State vars (lines 192-203): `voice_channel_id`, `voice_space_id`, `is_voice_muted`, `is_voice_deafened`, `is_video_enabled`, `is_screen_sharing`, `is_voice_view_open`, `spotlight_user_id`, `voice_text_channel_id` |
| `scripts/autoload/client.gd` | Voice session setup (creates LiveKitAdapter in `_ready()`, line 169), voice state cache `_voice_state_cache` (line 96), `_remote_tracks` (line 135), `_camera_track`/`_screen_track` (lines 133-134), `_speaking_users` (line 136), speaking debounce timer (lines 192-196) |
| `scripts/autoload/client_voice.gd` | Voice mutation API: `join_voice_channel()` (line 26), `leave_voice_channel()` (line 132), `toggle_video()` (line 205), `start_screen_share()` (line 240), `stop_screen_share()` (line 260), `on_track_received()` (line 347), `on_track_removed()` (line 342), `on_audio_level_changed()` (line 360), session callbacks (lines 290-358) |
| `scripts/autoload/client_gateway.gd` | Voice gateway signal connections (lines 89-94) |
| `scripts/autoload/client_gateway_events.gd` | Voice event handlers: `on_voice_state_update` (line 89), `on_voice_server_update` (line 173), `on_voice_signal` (line 193, no-op stub) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` (line 483): REST voice status -> cache -> signal |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` (line 578) includes `self_video`/`self_stream` |
| `scripts/autoload/config_voice.gd` | Voice/video settings helper: input/output device (lines 11-36), video device (line 39), resolution preset (line 52), fps (line 66), input sensitivity (line 76), input/output volume (lines 89-112), debug logging (line 115), speaking threshold (line 129) |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel UI: expandable participant list, green icon when connected, mute/deaf/video/stream indicators (lines 221-237), speaking rings (line 247), voice text chat button (line 253), drag-and-drop reordering (lines 313-350+) |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene: VBoxContainer with button + participant container |
| `scenes/sidebar/voice_bar.gd` | Voice connection bar: mute/deafen/cam/share/sfx/settings/disconnect buttons (lines 15-21), session state machine (lines 99-127), camera detection (lines 262-270), self-manages visibility via AppState signals |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: PanelContainer with status row + button row |
| `scenes/sidebar/screen_picker_dialog.gd` | Screen picker overlay: enumerates monitors via `LiveKitScreenCapture.get_monitors()` and windows via `LiveKitScreenCapture.get_windows()`, permission check, emits `source_selected(source: Dictionary)` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: ModalBase with centered panel, ScrollContainer with source buttons |
| `scenes/sidebar/channels/channel_list.gd` | Conditional voice channel instantiation, voice join/leave on click, voice view open on re-click, auto-select skips voice |
| `scenes/sidebar/channels/category_item.gd` | Conditional voice channel instantiation in categories |
| `scenes/sidebar/sidebar.tscn` | VoiceBar between DMList and UserBar in ChannelPanel VBox |
| `scenes/main/main_window.gd` | Content area layout: sidebar + content_area VBox (ContentHeader/TopicBar/VideoGrid/ContentBody); VideoPipScene preloaded (line 21); voice view opened/closed/left connections (lines 98-106) |
| `scenes/main/main_window.tscn` | VideoGrid placed between TopicBar and ContentBody |
| `scenes/video/video_tile.gd` | Video frame rendering component: live feed via `_process()` poll + `get_texture()`, or `frame_received` signal; placeholder with initials; speaking border (line 54); double-click spotlight (line 68); `detach_stream()` cleanup (line 77) |
| `scenes/video/video_tile.tscn` | Video tile scene: PanelContainer with TextureRect (160x120 min), InitialsLabel, NameBar |
| `scenes/video/video_grid.gd` | Self-managing video grid: rebuilds tiles from AppState signals, responsive column layout, INLINE (140px strip) and FULL_AREA modes with spotlight layout for screen shares and activities, deferred rebuild batching, activity viewport rendering |
| `scenes/video/video_grid.tscn` | Video grid scene: PanelContainer > VBoxContainer with SpotlightArea (PanelContainer) + ParticipantGrid (GridContainer) |
| `scenes/video/vertical_resize_handle.gd` | Draggable vertical resize bar between spotlight/activity area and participant grid: 6px hit area, hover/drag line, double-click reset, themed |
| `scenes/plugins/activity_lobby.gd` | Activity lobby UI: player slot grid, spectator list, start button (host only), participant count, role filtering |
| `scenes/main/main_window_voice_view.gd` | Voice view lifecycle: reparents VideoGrid + voice text panel into VoiceViewBody on open, restores on close, PiP spawn/removal |
| `scenes/video/video_pip.gd` | Picture-in-picture overlay: small floating video tile showing screen share or camera or first remote track, click to return to full video view, Escape to dismiss |
| `scenes/video/video_pip.tscn` | PiP scene: PanelContainer anchored bottom-right with Margin > TileSlot |
| `tests/livekit/unit/test_livekit_adapter.gd` | LiveKitAdapter tests: state machine, mute/deafen, signals, disconnect, unpublish |

## Implementation Details

### Voice Data Layer -- Implemented

Voice gateway events are fully wired through the data layer:

**AppState signals** (`app_state.gd` lines 52-84):
- `voice_state_updated(channel_id)` (line 52) -- emitted when voice participants change
- `voice_joined(channel_id)` (line 54) -- emitted when local user joins voice
- `voice_left(channel_id)` (line 56) -- emitted when local user leaves voice
- `voice_error(error)` (line 58) -- emitted on voice connection failure
- `voice_session_state_changed(state)` (line 60) -- emitted on LiveKit session state change
- `voice_mute_changed(is_muted)` (line 62) -- emitted when mute state changes
- `voice_deafen_changed(is_deafened)` (line 64) -- emitted when deafen state changes
- `video_enabled_changed(is_enabled)` (line 66) -- emitted when camera state changes
- `screen_share_changed(is_sharing)` (line 68) -- emitted when screen share state changes
- `remote_track_received(user_id, track)` (line 70) -- emitted when a remote peer's video track arrives
- `remote_track_removed(user_id)` (line 72) -- emitted when a remote peer's track is cleaned up
- `speaking_changed(user_id, is_speaking)` (line 74) -- emitted when speaking state changes
- `voice_view_opened(channel_id)` (line 76) -- emitted when full-area video view is opened
- `voice_view_closed()` (line 78) -- emitted when full-area video view is closed
- `voice_text_opened(channel_id)` (line 80) -- emitted when voice text chat panel opens
- `voice_text_closed()` (line 82) -- emitted when voice text chat panel closes
- `spotlight_changed(user_id)` (line 84) -- emitted when spotlight target changes (empty string = cleared)

**AppState state vars** (`app_state.gd` lines 192-203):
- `voice_channel_id: String` (line 192) -- current voice channel (empty if not connected)
- `voice_space_id: String` (line 193) -- space of current voice channel
- `is_voice_muted: bool` (line 194) -- local mute state
- `is_voice_deafened: bool` (line 195) -- local deafen state
- `is_video_enabled: bool` (line 196) -- camera is active
- `is_screen_sharing: bool` (line 197) -- screen share is active
- `is_voice_view_open: bool` (line 198) -- full-area video view is displayed
- `spotlight_user_id: String` (line 199) -- user ID of manually spotlighted tile (empty = auto)
- `voice_text_channel_id: String` (line 203) -- linked text channel for voice chat

**AppState helpers** (`app_state.gd` lines 289-373):
- `join_voice(channel_id, space_id)` (line 289) -- sets state, emits `voice_joined`
- `leave_voice()` (line 294) -- clears state, resets mute/deafen/video/screen, closes voice view, clears spotlight, emits `voice_left`
- `set_voice_muted(muted)` (line 311) -- updates state, emits `voice_mute_changed`
- `set_voice_deafened(deafened)` (line 315) -- updates state, emits `voice_deafen_changed`
- `set_video_enabled(enabled)` (line 319) -- updates state, emits `video_enabled_changed`
- `set_screen_sharing(sharing)` (line 323) -- updates state, emits `screen_share_changed`
- `open_voice_view()` (line 327) -- opens full-area video view, emits `voice_view_opened`
- `close_voice_view()` (line 333) -- closes full-area video view, emits `voice_view_closed`
- `set_spotlight(user_id)` (line 339) -- sets spotlight target, emits `spotlight_changed`
- `clear_spotlight()` (line 343) -- clears spotlight, emits `spotlight_changed("")`
- `toggle_voice_text(channel_id)` (line 359) -- toggles voice text chat panel
- `open_voice_text(channel_id)` (line 365) -- opens voice text panel
- `close_voice_text()` (line 369) -- closes voice text panel

**ClientModels.voice_state_to_dict()** (`client_models.gd` line 578):
Converts `AccordVoiceState` to dict with keys: `user_id`, `channel_id`, `session_id`, `self_mute`, `self_deaf`, `self_video`, `self_stream`, `mute`, `deaf`, `user` (user dict from cache).

**Client voice state cache** (`client.gd`):
- `_voice_state_cache: Dictionary = {}` (line 96) -- keyed by channel_id, values are Arrays of voice state dicts
- `_voice_server_info: Dictionary = {}` (line 97) -- stored AccordVoiceServerUpdate for active connection
- `_speaking_users: Dictionary = {}` (line 136) -- user_id -> last_active timestamp for speaking debounce

**Client voice mutation API** (`client_voice.gd`):
- `join_voice_channel(channel_id) -> bool` (line 26) -- leaves current voice if any, calls `VoiceApi.join()`, connects via `LiveKitAdapter.connect_to_room()`, emits `AppState.join_voice()`, fetches voice states
- `leave_voice_channel() -> bool` (line 132) -- cleans up camera/screen/remote tracks via `.close()`, disconnects voice session, calls `VoiceApi.leave()` (best-effort, skips if connection down), removes self from cache, clears speaking states, emits `AppState.leave_voice()`
- `set_voice_muted(muted)` (line 195) -- forwards to `_voice_session.set_muted()` and `AppState.set_voice_muted()`
- `set_voice_deafened(deafened)` (line 199) -- forwards to `_voice_session.set_deafened()` and `AppState.set_voice_deafened()`

**Client gateway signal connections** (`client_gateway.gd` lines 89-94):
- `client.voice_state_update` -> `_events.on_voice_state_update`
- `client.voice_server_update` -> `_events.on_voice_server_update`
- `client.voice_signal` -> `_events.on_voice_signal` (no-op stub)

**ClientGatewayEvents voice handlers** (`client_gateway_events.gd`):
- `on_voice_state_update(state, conn_index)` (line 89) -- ensures user cached, converts to dict via `voice_state_to_dict()`, removes user from previous channel, adds to new channel, updates `voice_users` count in channel cache, emits `voice_state_updated`, plays peer join/leave sound via SoundManager, detects force-disconnect
- `on_voice_server_update(info, conn_index)` (line 173) -- stores info in `_voice_server_info`; (re)connects backend if already in voice (handles both connected and disconnected session states)
- `on_voice_signal(data, conn_index)` (line 193) -- no-op stub (LiveKit handles signaling internally)

**ClientFetch.fetch_voice_states()** (`client_fetch.gd` line 483):
Calls `VoiceApi.get_status(channel_id)`, converts each `AccordVoiceState` via `voice_state_to_dict()`, populates `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`.

### Voice Channel UI -- Implemented

**voice_channel_item.gd** -- Dedicated VBoxContainer scene for voice channels:
- Exposes `channel_pressed` signal, `setup(data)`, `set_active(bool)` for polymorphism with `channel_item`
- Top row: Button with voice icon, channel name, user count label
- Below: `ParticipantContainer` VBoxContainer populated by `_refresh_participants()` (line 129)
- Listens to `voice_state_updated`, `voice_joined`, `voice_left`, `speaking_changed` signals
- Green icon tint via `ThemeManager.get_color("success")` when user is connected to this channel (line 147)
- Each participant row (lines 152-239): 28px indent + 18x18 Avatar component (with letter, color, optional avatar URL) + 6px gap + display name label (12px, role-colored or body) + mute/deaf indicators (red "M"/"D") + green "V" for `self_video` + blue "S" for `self_stream`
- Speaking state: tracks Avatar nodes in `_participant_avatars` dict (line 21), applies speaking ring via `Client.is_user_speaking()` on rebuild (line 182), animates via `_on_speaking_changed()` -> `av.set_speaking()` (line 247)
- Chat button: toggles voice text chat via `AppState.toggle_voice_text()` (line 253)
- Gear button + context menu for channel edit/delete (requires MANAGE_CHANNELS permission)
- Drag-and-drop reordering within the same space (lines 313+)

**channel_list.gd** voice integration:
- `VoiceChannelItemScene` preloaded
- Uncategorized loop: checks `ch.get("type", 0) == ClientModels.ChannelType.VOICE`, instantiates `VoiceChannelItemScene` for voice, `ChannelItemScene` for others
- `_on_channel_pressed()`: voice channels join via `Client.join_voice_channel()`, or re-click opens video view via `AppState.open_voice_view()`. Users disconnect via voice bar button. Text channel message view stays in place
- Auto-select: skips both `CATEGORY` and `VOICE` channel types

### Voice Connection Bar -- Implemented

**voice_bar.gd** -- Self-managing PanelContainer in sidebar:
- Hidden by default, shows on `voice_joined`, hides on `voice_left` (lines 34-35, 49, 76)
- Status row (line 12): green `ColorRect` dot + channel name label; clickable to open voice view (line 72-74)
- Button row (lines 15-21): Mic, Deaf, Cam, Share, SFX, Settings, Disconnect
- Mute button (line 140): toggles via `Client.set_voice_muted()`, red tint `StyleBoxFlat` when active ("Mic Off")
- Deafen button (line 143): toggles via `Client.set_voice_deafened()`, red tint when active
- Cam button (line 146): toggles via `Client.toggle_video()`, green tint when active ("Cam On"); disabled if no camera detected (line 232-234)
- Share button (line 149): opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`, green tint when active ("Sharing")
- SFX button (line 160): opens/closes soundboard panel, visibility gated on `USE_SOUNDBOARD` permission
- Settings button (line 182): opens User Settings on page 1 (Voice & Video)
- Disconnect button (line 187): calls `Client.leave_voice_channel()`
- Session state machine (lines 99-127): CONNECTING → "Connecting..." (yellow, pulsing), CONNECTED → channel name (green, solid), RECONNECTING → "Reconnecting..." (orange, pulsing)
- Voice error display (lines 81-97): shows error in red, auto-clears after 4s tween
- Camera detection (lines 262-270): Linux checks `/sys/class/video4linux` directory; other platforms assume camera exists
- Listens to `video_enabled_changed`, `screen_share_changed`, `voice_error`, `voice_session_state_changed`, `reduce_motion_changed` signals

**screen_picker_dialog.gd** -- ModalBase overlay:
- Checks screen capture permissions via `LiveKitScreenCapture.check_permissions()` (line 11)
- Enumerates monitors via `LiveKitScreenCapture.get_monitors()` (line 20)
- Enumerates windows via `LiveKitScreenCapture.get_windows()` (line 32)
- Groups into "Screens" and "Windows" sections with resolution labels
- Each button emits `source_selected(source: Dictionary)` on pick (line 3); source dict includes `_type` ("monitor" or "window"), `name`, `width`, `height`, plus native fields
- Self-destructs on close/backdrop click

**sidebar.tscn**: VoiceBar placed between DMList and UserBar in `ChannelPanel` VBox. Self-manages via AppState signals -- no changes to `sidebar.gd` required.

### LiveKitAdapter Integration -- Implemented

**Client owns LiveKitAdapter** (`client.gd`):
- `_voice_session: LiveKitAdapter` (line 129), created unconditionally in `_ready()` (line 169), added as child node
- Connected signals (lines 171-188): `session_state_changed`, `peer_joined`, `peer_left`, `track_received`, `track_removed`, `audio_level_changed`
- Speaking debounce timer (lines 192-196): 200ms poll, checks `_speaking_users` for 300ms silence timeout
- Android permission request at startup (lines 165-168)

**Join flow** (`client_voice.gd`):
After REST `VoiceApi.join()` succeeds, the response `AccordVoiceServerUpdate` provides LiveKit credentials:
- `_connect_voice_backend(info)` (line 112) -> `_voice_session.connect_to_room(url, token)` -- connects to LiveKit server directly
- On connect, `LiveKitAdapter._on_connected()` (line 290) auto-publishes local microphone audio; re-publishes screen share if capture survived reconnection

**Leave flow** (`client_voice.gd` lines 132-193):
Closes camera track, screen track, all remote tracks via `.close()`, sets `_intentional_disconnect = true`, then `_voice_session.disconnect_voice()`, best-effort REST `VoiceApi.leave()` (skips if connection down), removes self from voice state cache, clears `_voice_server_info`, clears speaking states, calls `AppState.leave_voice()`.

**Mute/deafen** (`client_voice.gd` lines 195-201):
Both forward to `_voice_session.set_muted()` / `set_deafened()` and `AppState`.

**Auto-reconnect** (`client_voice.gd`):
On `DISCONNECTED` state (non-intentional), attempts `_try_auto_reconnect()` using stored `_voice_server_info` credentials. Guarded by `_auto_reconnect_attempted` flag to prevent infinite loops. Reset on successful `CONNECTED`.

### Video Track Management -- Implemented

**Client video API** (`client_voice.gd`):
- `toggle_video()` (line 205) -- calls `_voice_session.publish_camera(Vector2i(w, h), fps)` using `Config.voice` settings for resolution and fps, or closes stream + calls `_voice_session.unpublish_camera()` to stop. Closes stream BEFORE unpublishing to avoid segfault from freed native track. Emits `voice_error` if publish returns null. Resolution presets: 0=480p (640x480), 1=720p (1280x720), 2=1080p (1920x1080)
- `start_screen_share(source: Dictionary)` (line 240) -- calls `_voice_session.publish_screen(source)` with the source dict from screen picker (monitor or window). Stops any existing screen track first
- `stop_screen_share()` (line 260) -- closes preview stream, nulls track, calls `unpublish_screen()`
- `_send_voice_state_update()` (line 272) -- sends gateway voice state update with all flags (mute, deaf, video, stream)
- Track cleanup in `leave_voice_channel()` (lines 138-150) -- closes camera, screen, and all remote tracks via `.close()` before disconnecting
- Config change listener: republishes camera on `video_resolution` or `video_fps` config change

**LiveKitAdapter video publishing** (`livekit_adapter.gd`):
- `publish_camera(res: Vector2i, fps: int) -> RefCounted` (line 146): creates `LiveKitVideoSource.create(w, h)`, `LiveKitLocalVideoTrack.create("camera", source)`, publishes via `LiveKitLocalParticipant.publish_track()` with `SOURCE_CAMERA`, returns `LiveKitVideoStream.from_track()` for local preview
- `publish_screen(source: Dictionary) -> RefCounted` (line 169): creates `LiveKitScreenCapture` from monitor or window dict (`create_for_monitor()` or `create_for_window()` based on `_type` field), downscales to capped size, creates video source/track, publishes with `SOURCE_SCREENSHARE`, returns `LocalVideoPreview` wrapper for local preview
- `unpublish_camera()` (line 166) / `unpublish_screen()` (line 221): cleanup via dedicated methods
- `_republish_screen()` (line 197): re-creates room-dependent objects (source, track, publication) for existing screen capture after room reconnection; stashes capture across disconnect/connect cycles
- `_capped_size()`: dynamic downscaling to fit `Config.get_max_screen_capture_size()` (capped at 4K)

**Screen capture frame loop** (`livekit_adapter.gd` lines 226-237):
Per-frame `_process()` calls `_screen_capture.screenshot()` synchronously (async callback doesn't fire on X11), resizes to `_screen_capture_size` if needed, pushes to `_local_screen_source.capture_frame(image)`, updates `_screen_preview`.

**LocalVideoPreview** inner class (`livekit_adapter.gd`):
Wraps frame updates for local screen share preview. `update_frame(image)` creates `ImageTexture` from image, with X11 alpha channel fix (RGB8 conversion round-trip). Exposes `get_texture()` and `close()`.

**AccordKit gateway** (`accord_client.gd`):
`update_voice_state()` (line 167) accepts `self_video: bool = false, self_stream: bool = false` as additional default parameters. The payload includes both flags. Backward compatible -- existing callers don't need changes.

### Video Settings Persistence (Config)

**ConfigVoice** (`config_voice.gd`) stores voice/video preferences in the `[voice]` section:
- `get_input_device()` / `set_input_device(device_id)` -- microphone device (line 11); applies immediately via `AudioServer.input_device`
- `get_output_device()` / `set_output_device(device_id)` -- speaker device (line 25); applies immediately via `AudioServer.output_device`
- `get_video_device()` / `set_video_device(device_id)` -- camera device (line 39)
- `get_video_resolution()` / `set_video_resolution(preset)` -- resolution presets: 0=480p (640x480), 1=720p (1280x720), 2=1080p (1920x1080) (line 52); emits `config_changed` to trigger camera republish
- `get_video_fps()` / `set_video_fps(fps)` -- frame rate, default 30 (line 66); emits `config_changed` to trigger camera republish
- `get_input_sensitivity()` / `set_input_sensitivity(value)` -- speaking sensitivity 0-100 (line 76)
- `get_input_volume()` / `set_input_volume(value)` -- mic volume 0-200 (line 89)
- `get_output_volume()` / `set_output_volume(value)` -- speaker volume 0-200 (line 102)
- `get_debug_logging()` / `set_debug_logging(enabled)` -- voice debug log toggle (line 115); emits `config_changed`
- `get_speaking_threshold()` (line 129) -- logarithmic mapping: `pow(10, -1 - 3 * sensitivity / 100)` (0% → 0.1, 50% → ~0.003, 100% → 0.0001)
- `apply_devices()` (line 135) -- applies input/output devices at startup

### Video Tile -- Implemented (video_tile.gd / video_tile.tscn)

`PanelContainer` (160x120 min size) with dark background, `TextureRect` for video frames, initials label for placeholders, and a name bar with mute indicator.

Two setup modes:
- `setup_local(stream, user)` (line 16) -- stores the stream, sets `_is_live = true`, hides initials, shows video rect. Connects to `frame_received` signal if available (line 27-28). Per-frame `_process()` calls `_stream.get_texture()` to update `video_rect.texture` (lines 84-89)
- `setup_placeholder(user, voice_state)` (line 30) -- shows user initials (max 2 chars) and name, mute indicator, no live video

Speaking indicator (line 54): listens to `AppState.speaking_changed`, applies green `StyleBoxFlat` border `(0.231, 0.647, 0.365)` with 2px width and 4px corner radius on the PanelContainer when the user is speaking.

Double-click spotlight (line 68): toggles `AppState.set_spotlight(user_id)` / `clear_spotlight()`.

Cleanup: `detach_stream()` (line 77) disconnects `frame_received` signal and nulls stream. Called from `_exit_tree()` (line 98).

### Video Grid -- Implemented (video_grid.gd / video_grid.tscn)

**Layout:** Self-managing `PanelContainer` > `VBoxContainer` (MainLayout) with `SpotlightArea` (PanelContainer, hidden by default) + `ParticipantGrid` (GridContainer). Placed in `main_window.tscn` between `TopicBar` and `ContentBody`.

**Two modes** via `GridMode` enum (line 3):
- `INLINE` (default) -- 140px min height strip above messages, columns based on layout mode (1 COMPACT, 2 MEDIUM/FULL)
- `FULL_AREA` -- fills the content area (`size_flags_vertical = EXPAND_FILL`), adaptive columns based on tile count (1→1col, 2-4→2col, 5-9→3col, 10-16→4col, 17+→5col), spotlight layout for screen shares or manual spotlight

**Spotlight layout:** When `FULL_AREA` and a screen share exists (or `AppState.spotlight_user_id` is set), the spotlighted tile goes into `SpotlightArea` (large main view) and remaining tiles go into `ParticipantGrid` as a horizontal strip (columns=99). Spotlight priority (lines 288-301): manual spotlight first, then auto-spotlight first screen share.

**Mode switching:** `set_full_area(full: bool)` (line 42) called by `main_window.gd` when voice view opens/closes.

**Tile collection** (`_collect_tiles()`, line 171):
- **FULL_AREA**: all participants as cards (camera only) + separate tiles for local/remote screen shares
- **INLINE**: only users with `self_video` or `self_stream`, plus local camera/screen tracks

**Signal connections** (lines 17-39): `video_enabled_changed`, `screen_share_changed`, `voice_state_updated`, `voice_joined`, `voice_left`, `remote_track_received`, `remote_track_removed`, `layout_mode_changed`, `spotlight_changed`

**Deferred rebuild** (lines 263-272): `_schedule_rebuild()` batches multiple signal-triggered updates into a single `call_deferred("_do_rebuild")` per frame.

Self-hides in INLINE mode when no tiles exist (line 278), always visible in FULL_AREA mode.

**Public track accessors** on `Client` (`client.gd`):
- `get_camera_track()` (line 562)
- `get_screen_track()` (line 565)
- `get_remote_track(user_id)` (line 568)

### Remote Video Rendering Pipeline -- Implemented

The full GDScript pipeline for rendering remote video tracks is functional. `LiveKitAdapter` emits `track_received(user_id, stream)` when a remote peer's video track is subscribed via the LiveKit room.

**LiveKitAdapter track subscription** (`livekit_adapter.gd`):
- `_on_track_subscribed(track, publication, participant)`: checks `track.get_kind() == LiveKitTrack.KIND_VIDEO`, creates `LiveKitVideoStream.from_track(track)`, stores in `_remote_video[identity]`, emits `track_received(uid, stream)`
- `_on_track_unsubscribed(track, publication, participant)`: cleans up remote video/audio for the identity, emits `track_removed(uid)`

**Client remote track cache** (`client.gd`):
- `_remote_tracks: Dictionary = {}` (line 135) -- keyed by user_id, values are `LiveKitVideoStream` instances
- `track_received` signal connected to `voice.on_track_received` (line 180)
- `track_removed` signal connected to `voice.on_track_removed` (line 183)

**ClientVoice track handling** (`client_voice.gd`):
- `on_track_received(user_id, stream)` (line 347) -- closes any previous track for the same peer via `.close()`, stores in `_remote_tracks`, emits `remote_track_received`
- `on_track_removed(user_id)` (line 342) -- erases remote track, emits `remote_track_removed`
- `on_peer_left(user_id)` (line 317) -- removes from voice state cache, clears speaking state, erases remote track, emits `remote_track_removed` and `voice_state_updated`
- `leave_voice_channel()` (lines 144-150) -- closes all remote tracks and clears `_remote_tracks` before disconnecting the session

**Data flow:**
```
LiveKitAdapter._on_track_subscribed(track, pub, participant)
    |-- KIND_VIDEO check
    |-- LiveKitVideoStream.from_track(track)
    |-- track_received.emit(uid, stream)
         |
         v
ClientVoice.on_track_received()
    |-- closes previous track for same peer
    |-- stores in Client._remote_tracks[user_id]
    |-- emits AppState.remote_track_received
         |
         v
    VideoGrid._on_remote_track_received() -> _schedule_rebuild()
         |-- Client.get_remote_track(uid) -> LiveKitVideoStream
         |-- tile.setup_local(stream, user)
              |-- _process() calls stream.get_texture()
              |-- frame_received signal -> _on_frame_received()
              |-- renders into TextureRect
```

### Picture-in-Picture -- Implemented (video_pip.gd / video_pip.tscn)

**PiP overlay** floats in the bottom-right corner (anchored via tscn). Shows a single `VideoTile` in a `TileSlot`.

**Priority order** (`_rebuild_pip()`, lines 40-75):
1. Local screen share track
2. Local camera track
3. First remote peer with `self_video` or `self_stream`

**Interactions:**
- Click → emits `pip_clicked` signal (line 25); main_window navigates back to voice view
- Escape key → `queue_free()` (line 29)

**Lifecycle:** Rebuilds on `video_enabled_changed`, `screen_share_changed`, `remote_track_received`, `remote_track_removed`. Self-destructs on `voice_left` signal (line 37-38). Hides when no tracks available.

### Audio Level Detection -- Implemented

**Remote audio** (`livekit_adapter.gd` lines 248-262):
Per-frame `_process()` computes RMS level from `AudioStreamPlayer` via `_estimate_audio_level()`. Emits `audio_level_changed(uid, level)` when above speaking threshold.

**Local microphone** (`livekit_adapter.gd` lines 263-286):
Captures frames via `AudioEffectCapture`, converts stereo to mono, applies input volume gain (0-200%), pushes to `LiveKitAudioSource.capture_frame()`. Noise gate: fills with silence when RMS below speaking threshold. Emits `audio_level_changed("@local", rms)`.

**ClientVoice speaking detection** (`client_voice.gd` line 360):
- Maps `@local`/`local`/`self`/empty to current user's ID
- Tracks speaking state with timestamp in `_speaking_users`
- Emits `AppState.speaking_changed(uid, true)` on first detection
- Skips if deafened

**Speaking timer** (`client.gd` lines 192-196):
200ms poll timer calls `_check_speaking_timeouts()` which clears speaking state after 300ms silence.

### AccordVoiceState Video Flags (voice_state.gd)

The `AccordVoiceState` model includes two video-related boolean flags:

- `self_stream: bool = false` (line 14) -- User is screen sharing
- `self_video: bool = false` (line 15) -- User is transmitting camera video

These are serialized via `from_dict()` (lines 35-36) and `to_dict()` (lines 49-50), and are sent/received through the gateway `voice.state_update` event. The `voice_state_to_dict()` conversion in `client_models.gd` (line 578) includes both `self_video` and `self_stream` in its output dict.

### Vertical Resize Handle -- Implemented (vertical_resize_handle.gd)

Draggable `Control` placed between the spotlight/activity area and the participant grid in `video_grid.gd` (lines 72-79). Allows the user to resize the spotlight area height.

**Parameters:** `_init(target, min_h, default_h, max_ratio)` — target is the `spotlight_area` PanelContainer, min height 100px, default 200px, max 70% of parent.

**Interaction:**
- Drag: tracks mouse delta, clamps target `custom_minimum_size.y` between `_min_height` and `_max_ratio * parent.size.y` (lines 87-98)
- Double-click: resets to `_default_height` (lines 68-71, 113-117)
- Hover: sets `CURSOR_VSIZE` cursor shape (line 32)

**Rendering** (lines 42-57): Three visual states:
- **Idle**: three small semi-transparent dots (α=0.35, radius 1.5px) at center ± 8px, providing a subtle resting indicator (lines 50-57)
- **Hovered or dragging**: full-width horizontal line at center in `icon_default` theme color (lines 44-49)

**Visibility:** Shown only when spotlight or activity is active (`_rebuild_spotlight` line 609, `_rebuild_activity` line 418), hidden otherwise (`_clear` line 274, `_rebuild_grid_only` line 627).

**Theming:** Added to `"themed"` group (line 35), `_apply_theme()` calls `queue_redraw()` to pick up color changes.

### Activity Integration -- Implemented (video_grid.gd lines 133-601)

Server plugins can launch activities that render inside the video grid's spotlight area. Activity state is tracked via AppState signals:
- `activity_started(plugin_id, channel_id)` (app_state.gd line 195)
- `activity_ended(plugin_id)` (line 197)
- `activity_download_progress(plugin_id, progress)` (line 199)
- `activity_session_state_changed(plugin_id, state)` (line 201)
- `activity_role_changed(plugin_id, user_id, role)` (line 203)

**State vars** (app_state.gd lines 233-237): `active_activity_plugin_id`, `active_activity_channel_id`, `active_activity_session_id`, `active_activity_session_state` ("lobby"/"running"/"ended"), `active_activity_role` ("player"/"spectator").

**`_rebuild_activity(tiles)`** (video_grid.gd line 416):
Activity takes priority over standard spotlight layout in FULL_AREA mode. Builds a VBoxContainer inside `spotlight_area` containing:
1. **Header** (line 486): activity name, runtime label, Start button (host only, accent styled), Leave button (error styled)
2. **Content** (line 433): state-dependent view:
   - `"lobby"` → `ActivityLobbyScript` with player slots and spectator list
   - `"running"` → `TextureRect` bound to `Client.plugins.get_activity_viewport_texture()` with input coordinate remapping via `_on_activity_viewport_input()` (line 578)
   - `"ended"` → simple "Activity ended." label
3. **Download progress bar** (line 469): hidden by default, shown during plugin download
4. **Footer** (line 545): role label ("Role: Player"/"Role: Spectator")

All video tiles go into the `ParticipantGrid` strip below the activity area.

**Input forwarding** (`_on_activity_viewport_input`, line 578): Remaps mouse coordinates from `TextureRect` display space to SubViewport canvas space, accounting for aspect-ratio letterboxing. Forwards via `Client.plugins.forward_activity_input()`.

**Activity lobby** (`activity_lobby.gd`):
VBoxContainer with title, status label, player slot grid (2-column GridContainer), spectator list, and host Start button. `setup(manifest, is_host)` reads `max_participants` from manifest. `update_participants(participants)` rebuilds slots, enables Start when at least 1 player exists.

### Voice View Reparenting -- Implemented (main_window_voice_view.gd)

Extracted as `RefCounted` helper owned by `main_window.gd` (line 68). Manages the lifecycle of the full-area voice view and PiP overlay.

**`on_voice_view_opened()`** (line 19): Hides content_header, topic_bar, content_body. Reparents `VideoGrid` and voice text panel/handle from their original parents into `VoiceViewBody` (HBoxContainer in ContentArea). Saves original parent references and child indices for later restoration. Calls `video_grid.set_full_area(true)`. Auto-opens voice text chat in non-COMPACT mode.

**`on_voice_view_closed()`** (line 66): Reparents VideoGrid and voice text panel/handle back to their saved positions. Restores content_header, content_body, message_view visibility. Calls `set_full_area(false)`. Closes voice text. Spawns PiP if any video content exists.

**PiP management:** `maybe_spawn_pip()` (line 120) checks for local camera/screen track or any remote peer with `self_video`/`self_stream`. `remove_pip()` (line 149) cleans up. PiP click navigates back to voice view via `AppState.open_voice_view()`.

## Implementation Status

- [x] godot-livekit GDExtension with LiveKitRoom-based connections (Linux, Windows, macOS)
- [x] Camera publishing via LiveKitVideoSource + LiveKitLocalVideoTrack + LiveKitLocalParticipant
- [x] Screen share publishing via LiveKitScreenCapture (monitor and window) + dynamic downscaling
- [x] Window sharing via `LiveKitScreenCapture.get_windows()` + `create_for_window()`
- [x] Native screen/window frame capture via `LiveKitScreenCapture.screenshot()` piped to `LiveKitVideoSource.capture_frame()`
- [x] AccordVoiceState `self_video` and `self_stream` flags
- [x] Gateway `voice.state_update` event carries video flags
- [x] Voice signaling handled internally by LiveKit (no gateway VOICE_SIGNAL needed)
- [x] VoiceManager connection lifecycle (join/leave/forced disconnect)
- [x] VoiceApi REST endpoints (join, leave, get_status)
- [x] AccordClient re-emits all gateway voice signals
- [x] Client voice gateway event handlers with sound effects for peer join/leave
- [x] AppState voice/video signals and state tracking (17 signals, 9 state vars)
- [x] Client voice mutation API with track cleanup
- [x] Voice state cache with data access API
- [x] ClientModels `voice_state_to_dict()` conversion
- [x] ClientFetch `fetch_voice_states()` for REST-based voice state population
- [x] Dedicated `voice_channel_item` scene with expandable participant list, drag-and-drop reorder, edit/delete context menu
- [x] Voice channel click joins or opens video view (does not emit `channel_selected`)
- [x] Auto-select skips voice channels
- [x] Voice bar with mute/deafen/cam/share/sfx/settings/disconnect buttons
- [x] Voice bar self-manages visibility via AppState signals
- [x] Voice bar session state machine (connecting/connected/reconnecting indicators with pulse animation)
- [x] Voice bar error display with 4s auto-dismiss
- [x] Camera detection (Linux `/sys/class/video4linux` check; disables Cam button if absent)
- [x] LiveKitAdapter wired into Client (join connects room, leave disconnects, mute/deafen forwarded)
- [x] Force-disconnect detection (gateway voice_state_update with null channel_id)
- [x] Auto-reconnect with stored credentials (guarded against infinite loops)
- [x] Video enable/disable UI (Cam button in voice bar)
- [x] Screen sharing UI (Share button + screen picker dialog with monitor AND window tabs via LiveKitScreenCapture)
- [x] Screen capture permission checking
- [x] Video/stream indicators in voice channel participant rows (green V, blue S)
- [x] Track cleanup on voice disconnect (camera, screen, all remote tracks via `.close()`)
- [x] Local video preview via `VideoTile` with `_process()` poll + `get_texture()` and `frame_received` signal
- [x] Video participant grid layout with responsive column count
- [x] Video quality settings (resolution presets + frame rate) persisted via `ConfigVoice`
- [x] Config change triggers camera republish (resolution/fps changes applied live)
- [x] Input/output device selection and persistence (applied via AudioServer)
- [x] Input sensitivity with logarithmic speaking threshold
- [x] Input/output volume control (0-200%)
- [x] Debug logging toggle
- [x] Public track accessors (`Client.get_camera_track()`, `Client.get_screen_track()`, `Client.get_remote_track()`)
- [x] Remote video rendering pipeline (LiveKitAdapter `track_received` -> ClientVoice cache -> VideoGrid live tiles)
- [x] Speaking indicator on video tiles (green border when user is speaking)
- [x] Speaking debounce (300ms silence timeout via timer)
- [x] LiveKitAdapter unit tests (state machine, mute/deafen, signals, disconnect, unpublish)
- [x] **Full-area video view** (Discord-style: replaces message content when viewing voice channel)
- [x] **Screen share spotlight layout** (large main view + small participant strip)
- [x] **Mini PiP overlay** (floating preview when navigating away from voice channel; click returns, Escape dismisses)
- [x] **Adaptive grid sizing** (auto-layout based on participant count: 1=full, 2-4=2x2, 5-9=3x3, etc.)
- [x] **Voice bar click to open video view** (clicking status row opens full-area view)
- [x] **Active speaker detection** (audio level-based, green border on video tiles and speaking ring on voice channel avatars)
- [x] **Double-click to spotlight** (focusing a specific participant)
- [x] **Voice text chat** (toggle linked text channel via chat button on voice channel item)
- [x] **Screen share reconnection** (stashes capture across disconnect/connect, re-publishes on reconnect)
- [x] **Dynamic screen downscaling** (caps at max screen capture size, capped at 4K)
- [x] **Noise gate** (silences mic input below speaking threshold)
- [x] **Android permission request** (camera/mic permissions requested at startup)
- [x] **Vertical resize handle** (draggable bar between spotlight/activity area and participant grid, double-click to reset)
- [x] **Activity rendering in spotlight area** (lobby/running/ended states, viewport texture, input forwarding)
- [x] **Activity lobby UI** (player slot grid, spectator list, host start button)
- [x] **Activity download progress** (progress bar during plugin download)
- [x] **Voice view reparenting** (VideoGrid + voice text reparented into VoiceViewBody on open, restored on close)
- [x] **Resize handle resting indicator** (three semi-transparent dots at α=0.35 when idle, full line when hovered/dragging)
- [x] **Bandwidth adaptation** (`_bitrate_for_resolution()` caps at 800 kbps/2.5 Mbps/4 Mbps per resolution tier; passed as `max_bitrate` publish option to LiveKit SFU)
- [x] **Camera device routing** (`Config.voice.get_video_device()` passed through `toggle_video()` → `publish_camera()` → `LiveKitVideoSource.set_device()`)
- [x] **Camera hot-swap** (`swap_camera()` replaces source on existing publication via `set_source()`; falls back to full republish if GDExtension lacks the method)

## Tasks

### VIDEO-1: Camera device not routed to publish
- **Status:** closed
- **Impact:** 3
- **Effort:** 1
- **Tags:** config, video, voice
- **Notes:** Implemented — `toggle_video()` reads `Config.voice.get_video_device()` (client_voice.gd line 239) and passes it to `publish_camera()` (line 241). Adapter applies it via `LiveKitVideoSource.set_device()` if the method exists (livekit_adapter.gd lines 149-151).

### VIDEO-2: No bandwidth adaptation
- **Status:** closed
- **Impact:** 2
- **Effort:** 1
- **Tags:** video
- **Notes:** Implemented — `_bitrate_for_resolution()` (livekit_adapter.gd lines 175-183) returns 800 kbps/2.5 Mbps/4 Mbps based on pixel count. The value is passed as `max_bitrate` in publish options (lines 162-164). LiveKit SFU adapts dynamically below this cap.

### VIDEO-3: No video track hot-swap
- **Status:** closed
- **Impact:** 2
- **Effort:** 3
- **Tags:** video
- **Notes:** Implemented — `swap_camera()` (livekit_adapter.gd lines 185-210) mutes the existing track, replaces the source via `set_source()`, then unmutes. Falls back to full republish if the GDExtension lacks `set_source`. Triggered by `on_voice_config_changed()` in ClientVoice when video device/resolution changes.

### VIDEO-4: Resize handle invisible until hovered
- **Status:** closed
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, video, activity
- **Notes:** Implemented — `_draw()` in vertical_resize_handle.gd (lines 50-57) draws three small semi-transparent dots (α=0.35) when idle, giving users a discoverable resting indicator.
