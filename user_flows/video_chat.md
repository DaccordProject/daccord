# Video Chat

Last touched: 2026-02-24 (LiveKitAdapter rewrite, addon migration)

## Overview

Video chat in daccord enables camera video and screen sharing within voice channels. The godot-livekit GDExtension (`addons/godot-livekit/`) provides WebRTC infrastructure via `LiveKitRoom`, and the `LiveKitAdapter` GDScript wrapper manages publishing/unpublishing video tracks through `LiveKitLocalVideoTrack` and `LiveKitVideoSource`. The AccordVoiceState model tracks `self_video` and `self_stream` flags per user. Voice channels have full join/leave/mute/deafen support via `client.gd`, with a dedicated `voice_channel_item` scene and `voice_bar` for controls. The full pipeline is implemented: voice bar has Cam/Share buttons, the video grid renders local camera and screen share tiles live via `LiveKitVideoStream.poll()` + `.get_texture()`, and the remote rendering pipeline uses `track_received` signal on `LiveKitAdapter` to create live video tiles for remote peers.

**Discord-style target design:** The video UI should replace the message content area with a full-area video view when the user is in a voice channel and wants to see video. Clicking the voice channel name in the voice bar (or the voice channel itself when already connected) opens this full-area view. Clicking any text channel returns to the normal message view while voice continues in the background. A screen share should appear as the dominant/spotlight view with other participants as small tiles. A mini picture-in-picture preview should appear when navigating away from the video view.

## User Steps

### Current behavior

1. User clicks a voice channel in the sidebar (joins via `Client.join_voice_channel()`)
2. User sees participants listed below the voice channel item, with V/S indicators for video/screen share
3. User sees the voice bar with Mic/Deaf/Cam/Share/SFX/Settings/Disconnect buttons
4. User clicks "Cam" to toggle camera on/off (creates/stops camera track via `Client.toggle_video()`)
5. User clicks "Share" to open screen picker dialog, selects a screen to start sharing
6. Video grid appears as a fixed-height strip above the message content area, showing tiles for all video/screen share participants
7. User sees other participants' video feeds live when remote tracks are received via `LiveKitAdapter.track_received`; placeholder tiles with initials shown otherwise
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
       |-- publish_screen() ------------>|
       |   (creates 1920x1080 source,    |
       |    publishes with               |
       |    SOURCE_SCREENSHARE)          |
       |   self_stream = true            |
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
| `addons/godot-livekit/` | godot-livekit GDExtension: LiveKitRoom, LiveKitVideoStream, LiveKitAudioStream, LiveKitVideoSource, LiveKitLocalVideoTrack |
| `scripts/autoload/livekit_adapter.gd` | LiveKitAdapter GDScript wrapper: connect_to_room(), publish_camera(), publish_screen(), unpublish_camera(), unpublish_screen(), track_received signal |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState model with `self_video` (line 15) and `self_stream` (line 14) flags |
| `addons/accordkit/models/voice_server_update.gd` | AccordVoiceServerUpdate: backend type, LiveKit URL, token, SFU endpoint |
| `addons/accordkit/rest/endpoints/voice_api.gd` | REST API: `join()`, `leave()`, `get_status()` |
| `addons/accordkit/voice/voice_manager.gd` | Voice lifecycle: join/leave, voice_connected/voice_disconnected signals |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway voice events: `voice_state_update`, `voice_server_update`, `voice_signal`; `update_voice_state()` with video/stream params |
| `addons/accordkit/core/accord_client.gd` | `update_voice_state()` (line 165) with `self_video`/`self_stream` params; re-emits voice signals; exposes `voice` API (line 107) |
| `scripts/autoload/app_state.gd` | Voice signals: `voice_state_updated` (line 52), `voice_joined` (line 54), `voice_left` (line 56), `voice_error` (line 58), `voice_mute_changed` (line 60), `voice_deafen_changed` (line 62), `video_enabled_changed` (line 64), `screen_share_changed` (line 66), `remote_track_received` (line 68), `remote_track_removed` (line 70), `speaking_changed` (line 72); state vars: `voice_channel_id` (line 160), `voice_space_id` (line 161), `is_voice_muted` (line 162), `is_voice_deafened` (line 163), `is_video_enabled` (line 164), `is_screen_sharing` (line 165) |
| `scripts/autoload/client.gd` | Voice session setup (creates LiveKitAdapter in `_ready()`, line 156), voice state cache `_voice_state_cache` (line 90), `_remote_tracks` (line 128), `_camera_track`/`_screen_track` (lines 126-127) |
| `scripts/autoload/client_voice.gd` | Voice mutation API: `join_voice_channel()` (line 26), `leave_voice_channel()` (line 127), `toggle_video()` (line 189), `start_screen_share()` (line 219), `stop_screen_share()` (line 237), `on_track_received()` (line 308), session callbacks (lines 263-344) |
| `scripts/autoload/client_gateway.gd` | Voice gateway signal connections (lines 89-94) |
| `scripts/autoload/client_gateway_events.gd` | Voice event handlers: `on_voice_state_update` (line 89), `on_voice_server_update` (line 140), `on_voice_signal` (line 159, no-op stub) |
| `scripts/autoload/client_fetch.gd` | `fetch_voice_states()` (line 476): REST voice status -> cache -> signal |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` (line 535) includes `self_video`/`self_stream`, `channel_to_dict()` includes `voice_users` |
| `scripts/autoload/config_voice.gd` | Voice/video settings helper: input/output device (lines 11-34), video device (line 37), resolution preset (line 50), fps (line 63) |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel UI: expandable participant list, green icon when connected, mute/deaf/video/stream indicators (lines 121-202), speaking rings (line 204) |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene: VBoxContainer with button + participant container |
| `scenes/sidebar/voice_bar.gd` | Voice connection bar: mute/deafen/cam/share/sfx/settings/disconnect buttons (lines 9-17), self-manages visibility via AppState signals |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: PanelContainer with status row + button row |
| `scenes/sidebar/screen_picker_dialog.gd` | Screen picker overlay: enumerates screens via `DisplayServer.get_screen_count()`, emits `source_selected` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: ColorRect overlay with centered panel, ScrollContainer with source buttons |
| `scenes/sidebar/channels/channel_list.gd` | Conditional voice channel instantiation, voice join/leave on click, auto-select skips voice |
| `scenes/sidebar/channels/category_item.gd` | Conditional voice channel instantiation in categories |
| `scenes/sidebar/sidebar.tscn` | VoiceBar between DMList and UserBar in ChannelPanel VBox |
| `scenes/main/main_window.gd` | Content area layout: sidebar + content_area VBox (ContentHeader/TopicBar/VideoGrid/ContentBody) |
| `scenes/main/main_window.tscn` | VideoGrid placed between TopicBar and ContentBody |
| `scenes/video/video_tile.gd` | Video frame rendering component: live feed via LiveKitVideoStream.poll() + get_texture(), or placeholder with initials, speaking border |
| `scenes/video/video_tile.tscn` | Video tile scene: PanelContainer with TextureRect (160x120 min), InitialsLabel, NameBar |
| `scenes/video/video_grid.gd` | Self-managing video grid: rebuilds tiles from AppState signals, responsive column layout, renders remote tracks live via `Client.get_remote_track()` |
| `scenes/video/video_grid.tscn` | Video grid scene: PanelContainer (140px min height) > ScrollContainer > GridContainer |
| `tests/livekit/unit/test_livekit_adapter.gd` | LiveKitAdapter tests: state machine, mute/deafen, signals, disconnect, unpublish |

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
- `speaking_changed(user_id, is_speaking)` (line 72) -- emitted when speaking state changes

**AppState state vars** (`app_state.gd`):
- `voice_channel_id: String` (line 160) -- current voice channel (empty if not connected)
- `voice_space_id: String` (line 161) -- space of current voice channel
- `is_voice_muted: bool` (line 162) -- local mute state
- `is_voice_deafened: bool` (line 163) -- local deafen state
- `is_video_enabled: bool` (line 164) -- camera is active
- `is_screen_sharing: bool` (line 165) -- screen share is active

**AppState helpers** (`app_state.gd`):
- `join_voice(channel_id, space_id)` (line 260) -- sets state, emits `voice_joined`
- `leave_voice()` (line 265) -- clears state, resets mute/deafen/video/screen, emits `voice_left`
- `set_voice_muted(muted)` (line 276) -- updates state, emits `voice_mute_changed`
- `set_voice_deafened(deafened)` (line 280) -- updates state, emits `voice_deafen_changed`
- `set_video_enabled(enabled)` (line 284) -- updates state, emits `video_enabled_changed`
- `set_screen_sharing(sharing)` (line 288) -- updates state, emits `screen_share_changed`

**ClientModels.voice_state_to_dict()** (line 535):
Converts `AccordVoiceState` to dict with keys: `user_id`, `channel_id`, `session_id`, `self_mute`, `self_deaf`, `self_video`, `self_stream`, `mute`, `deaf`, `user` (user dict from cache).

**Client voice state cache** (`client.gd`):
- `_voice_state_cache: Dictionary = {}` (line 90) -- keyed by channel_id, values are Arrays of voice state dicts
- `_voice_server_info: Dictionary = {}` (line 91) -- stored AccordVoiceServerUpdate for active connection

**Client voice mutation API** (`client_voice.gd`):
- `join_voice_channel(channel_id) -> bool` (line 26) -- leaves current voice if any, calls `VoiceApi.join()`, connects via `LiveKitAdapter.connect_to_room()`, emits `AppState.join_voice()`, fetches voice states
- `leave_voice_channel() -> bool` (line 127) -- cleans up camera/screen/remote tracks via `.close()`, disconnects voice session, calls `VoiceApi.leave()`, removes self from cache, emits `AppState.leave_voice()`
- `set_voice_muted(muted)` (line 179) -- forwards to `_voice_session.set_muted()` and `AppState.set_voice_muted()`
- `set_voice_deafened(deafened)` (line 183) -- forwards to `_voice_session.set_deafened()` and `AppState.set_voice_deafened()`

**Client gateway signal connections** (`client_gateway.gd` lines 89-94):
- `client.voice_state_update` -> `_events.on_voice_state_update`
- `client.voice_server_update` -> `_events.on_voice_server_update`
- `client.voice_signal` -> `_events.on_voice_signal` (no-op stub)

**ClientGatewayEvents voice handlers** (`client_gateway_events.gd`):
- `on_voice_state_update(state, conn_index)` (line 89) -- converts to dict via `voice_state_to_dict()`, removes user from previous channel, adds to new channel, updates `voice_users` count in channel cache, emits `voice_state_updated`, plays peer join/leave sound, detects force-disconnect
- `on_voice_server_update(info, conn_index)` (line 140) -- stores info in `_voice_server_info`; connects backend if already in voice with a disconnected session
- `on_voice_signal(data, conn_index)` (line 159) -- no-op stub (LiveKit handles signaling internally)

**ClientFetch.fetch_voice_states()** (`client_fetch.gd` line 476):
Calls `VoiceApi.get_status(channel_id)`, converts each `AccordVoiceState` via `voice_state_to_dict()`, populates `_voice_state_cache`, updates `voice_users` count, emits `voice_state_updated`.

### Voice Channel UI -- Implemented

**voice_channel_item.gd** -- Dedicated VBoxContainer scene for voice channels:
- Exposes `channel_pressed` signal, `setup(data)`, `set_active(bool)` for polymorphism with `channel_item`
- Top row: Button with voice icon, channel name, user count label
- Below: `ParticipantContainer` VBoxContainer populated by `_refresh_participants()` (line 96)
- Listens to `voice_state_updated`, `voice_joined`, `voice_left`, `speaking_changed` signals (lines 33-36)
- Green icon tint (`Color(0.231, 0.647, 0.365)`) when user is connected to this channel (line 113)
- Each participant row (lines 121-202): 28px indent + 18x18 Avatar component (with letter, color, optional avatar URL) + 6px gap + display name label (12px, gray) + mute/deaf indicators (red "M"/"D") + green "V" for `self_video` + blue "S" for `self_stream`
- Speaking state: tracks Avatar nodes in `_participant_avatars` dict (line 149), applies green ring via `Client.is_user_speaking()` on rebuild (line 150), animates via `_on_speaking_changed()` -> `av.set_speaking()` (line 208)
- Gear button + context menu for channel edit/delete (requires MANAGE_CHANNELS permission)
- Drag-and-drop reordering within the same space (lines 257-314)

**channel_list.gd** voice integration:
- `VoiceChannelItemScene` preloaded
- Uncategorized loop: checks `ch.get("type", 0) == ClientModels.ChannelType.VOICE`, instantiates `VoiceChannelItemScene` for voice, `ChannelItemScene` for others
- `_on_channel_pressed()`: voice channels toggle `Client.join_voice_channel()` / `Client.leave_voice_channel()` instead of emitting `channel_selected`. Text channel message view stays in place
- Auto-select: skips both `CATEGORY` and `VOICE` channel types

### Voice Connection Bar -- Implemented

**voice_bar.gd** -- Self-managing PanelContainer in sidebar:
- Hidden by default, shows on `voice_joined`, hides on `voice_left` (lines 20, 35, 52)
- Status row: green `ColorRect` dot + channel name label (looked up from `Client.get_channels_for_space()`)
- Button row (lines 9-17): Mic, Deaf, Cam, Share, SFX, Settings, Disconnect
- Mute button (line 56): toggles via `Client.set_voice_muted()`, red tint `StyleBoxFlat` when active
- Deafen button (line 59): toggles via `Client.set_voice_deafened()`, red tint when active
- Cam button (line 62): toggles via `Client.toggle_video()`, green tint when active ("Cam On")
- Share button (line 65): opens `ScreenPickerDialog` or calls `Client.stop_screen_share()`, green tint when active ("Sharing")
- SFX button (line 78): opens/closes soundboard panel, visibility gated on `USE_SOUNDBOARD` permission
- Settings button (line 100): opens User Settings on page 2 (Voice & Video)
- Disconnect button (line 105): calls `Client.leave_voice_channel()`
- Listens to `video_enabled_changed` and `screen_share_changed` signals to update button visuals (lines 32-33)

**screen_picker_dialog.gd** -- Full-screen semi-transparent overlay:
- Enumerates screens via `DisplayServer.get_screen_count()` and `DisplayServer.screen_get_size()` (lines 21-32)
- Each button shows screen title ("Screen 1", "Screen 2", etc.) and resolution (e.g., "1920x1080")
- Emits `source_selected(source_type: String, source_id: int)` on pick (line 3)
- Self-destructs on close/backdrop click/Escape (lines 13-19, 62)

**sidebar.tscn**: VoiceBar placed between DMList and UserBar in `ChannelPanel` VBox. Self-manages via AppState signals -- no changes to `sidebar.gd` required.

### LiveKitAdapter Integration -- Implemented

**Client owns LiveKitAdapter** (`client.gd`):
- `_voice_session: LiveKitAdapter` (line 122), created unconditionally in `_ready()` (line 156), added as child node
- Connected signals (lines 158-172): `session_state_changed`, `peer_joined`, `peer_left`, `track_received`, `audio_level_changed`
- No `signal_outgoing` signal -- LiveKit handles signaling internally

**Join flow** (`client_voice.gd`):
After REST `VoiceApi.join()` succeeds, the response `AccordVoiceServerUpdate` provides LiveKit credentials:
- `_connect_voice_backend(info)` (line 112) -> `_voice_session.connect_to_room(url, token)` -- connects to LiveKit server directly
- On connect, `LiveKitAdapter._on_connected()` (line 200) auto-publishes local microphone audio

**Leave flow** (`client_voice.gd` lines 127-177):
Closes camera track, screen track, all remote tracks via `.close()`, then `_voice_session.disconnect_voice()`, REST `VoiceApi.leave()`, removes self from voice state cache, clears `_voice_server_info`, clears speaking states, calls `AppState.leave_voice()`.

**Mute/deafen** (`client_voice.gd` lines 179-185):
Both forward to `_voice_session.set_muted()` / `set_deafened()` and `AppState`.

### Video Track Management -- Implemented

**Client video API** (`client_voice.gd`):
- `toggle_video()` (line 189) -- calls `_voice_session.publish_camera(Vector2i(w, h), fps)` using `Config.voice` settings for resolution and fps, or calls `_camera_track.close()` + `_voice_session.unpublish_camera()` to stop. Emits `voice_error` if publish returns null. Resolution presets: 0=480p (640x480), 1=720p (1280x720), 2=1080p (1920x1080)
- `start_screen_share(source_type, source_id)` (line 219) -- calls `_voice_session.publish_screen()` (source_type and source_id are currently unused -- LiveKitAdapter publishes at a default 1920x1080 resolution). Stops any existing screen track first
- `stop_screen_share()` (line 237) -- closes and nulls screen track, calls `unpublish_screen()`
- `_send_voice_state_update()` (line 245) -- sends gateway voice state update with all flags (mute, deaf, video, stream)
- Track cleanup in `leave_voice_channel()` (lines 131-143) -- closes camera, screen, and all remote tracks via `.close()` before disconnecting

**LiveKitAdapter video publishing** (`livekit_adapter.gd`):
- `publish_camera(res: Vector2i, fps: int) -> RefCounted` (line 111): creates `LiveKitVideoSource.create(w, h)`, `LiveKitLocalVideoTrack.create("camera", source)`, publishes via `LiveKitLocalParticipant.publish_track()` with `SOURCE_CAMERA`, returns `LiveKitVideoStream.from_track()` for local preview
- `publish_screen() -> RefCounted` (line 134): creates screen source at 1920x1080, `LiveKitLocalVideoTrack.create("screen", source)`, publishes with `SOURCE_SCREENSHARE`, returns `LiveKitVideoStream.from_track()` for local preview. **Note:** does not yet use `LiveKitScreenCapture` for actual frame capture -- the `LiveKitScreenCapture` API (monitor/window enumeration, native frame capture) is now available in the addon but not integrated
- `unpublish_camera()` / `unpublish_screen()` (lines 131, 154): unpublishes track via `LiveKitLocalParticipant.unpublish_track()`, clears local refs

**AccordKit gateway** (`accord_client.gd`):
`update_voice_state()` (line 165) accepts `self_video: bool = false, self_stream: bool = false` as additional default parameters. The payload includes both flags. Backward compatible -- existing callers don't need changes.

### Video Settings Persistence (Config)

**ConfigVoice** (`config_voice.gd`) stores voice/video preferences in the `[voice]` section:
- `get_input_device()` / `set_input_device(device_id)` -- microphone device (line 11)
- `get_output_device()` / `set_output_device(device_id)` -- speaker device (line 24)
- `get_video_device()` / `set_video_device(device_id)` -- camera device (line 37)
- `get_video_resolution()` / `set_video_resolution(preset)` -- resolution presets: 0=480p (640x480), 1=720p (1280x720), 2=1080p (1920x1080) (line 50)
- `get_video_fps()` / `set_video_fps(fps)` -- frame rate, default 30 (line 63)

### Video Tile -- Implemented (video_tile.gd / video_tile.tscn)

`PanelContainer` (160x120 min size) with dark background, `TextureRect` for video frames, initials label for placeholders, and a name bar with mute indicator.

Two setup modes:
- `setup_local(stream, user)` (line 16) -- stores the `LiveKitVideoStream`, sets `_is_live = true`, hides initials, shows video rect. Per-frame `_process()` calls `_stream.poll()` then `_stream.get_texture()` to update `video_rect.texture` (lines 68-74)
- `setup_placeholder(user, voice_state)` (line 29) -- shows user initials (max 2 chars) and name, mute indicator, no live video

Speaking indicator (line 54): listens to `AppState.speaking_changed`, applies green `StyleBoxFlat` border `(0.231, 0.647, 0.365)` with 2px width and 4px corner radius on the PanelContainer when the user is speaking.

Cleanup (`_exit_tree()`, line 76): calls `_stream.close()` if available.

### Video Grid -- Implemented (video_grid.gd / video_grid.tscn)

**Current layout:** Self-managing `PanelContainer` > `ScrollContainer` > `GridContainer` placed in `main_window.tscn` between `TopicBar` and `ContentBody`. Fixed 140px minimum height. This behaves as an **inline strip** above the message area -- not Discord-style.

- Listens to `video_enabled_changed`, `screen_share_changed`, `voice_state_updated`, `voice_left`, `remote_track_received`, `remote_track_removed`, `layout_mode_changed` (lines 11-29)
- Rebuilds tiles on any change: local camera tile, local screen share tile, remote peer tiles (lines 73-137)
- Grid columns adapt to layout mode: 1 for COMPACT, 2 for MEDIUM/FULL (lines 60-67)
- Self-hides when no tiles exist, self-shows when tiles are added (line 137)
- Remote peers with `self_video` or `self_stream` flags get live tiles when a remote track is available via `Client.get_remote_track()`, otherwise placeholder tiles (lines 116-134)

**Public track accessors** on `Client`:
- `get_camera_track()` (line 518)
- `get_screen_track()` (line 521)
- `get_remote_track(user_id)` (line 524)

### Remote Video Rendering Pipeline -- Implemented

The full GDScript pipeline for rendering remote video tracks is functional. `LiveKitAdapter` emits `track_received(user_id, stream)` when a remote peer's video track is subscribed via the LiveKit room.

**LiveKitAdapter track subscription** (`livekit_adapter.gd`):
- `_on_track_subscribed(track, publication, participant)` (line 232): checks `track.get_kind() == LiveKitTrack.KIND_VIDEO`, creates `LiveKitVideoStream.from_track(track)`, stores in `_remote_video[identity]`, emits `track_received(uid, stream)`
- `_on_track_unsubscribed(track, publication, participant)` (line 247): cleans up remote video/audio for the identity

**Client remote track cache** (`client.gd`):
- `_remote_tracks: Dictionary = {}` (line 128) -- keyed by user_id, values are `LiveKitVideoStream` instances
- `track_received` signal connected directly to `voice.on_track_received` (line 167)

**ClientVoice track handling** (`client_voice.gd`):
- `on_track_received(user_id, stream)` (line 308) -- closes any previous track for the same peer via `.close()`, stores in `_remote_tracks`, emits `remote_track_received`
- `on_peer_left()` (line 280) -- closes and erases remote track for the departing peer, emits `remote_track_removed`
- `leave_voice_channel()` (lines 138-143) -- closes all remote tracks and clears `_remote_tracks` before disconnecting the session

**VideoGrid integration** (`video_grid.gd`):
- Connects to `remote_track_received` and `remote_track_removed` signals to trigger rebuild (lines 21-26)
- During `_rebuild()`, for each remote peer with `self_video` or `self_stream`, calls `Client.get_remote_track(uid)` (line 127)
- If a remote track exists, creates a live tile via `tile.setup_local(remote_track, user)` (same rendering path as local camera/screen tiles, line 130)
- Falls back to `tile.setup_placeholder(user, state)` when no track is available (line 134)

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
    VideoGrid._on_remote_track_received() -> _rebuild()
         |-- Client.get_remote_track(uid) -> LiveKitVideoStream
         |-- tile.setup_local(stream, user)
              |-- _process() calls stream.poll()
              |-- stream.get_texture() -> ImageTexture
              |-- renders into TextureRect
```

### AccordVoiceState Video Flags (voice_state.gd)

The `AccordVoiceState` model includes two video-related boolean flags:

- `self_stream: bool = false` (line 14) -- User is screen sharing
- `self_video: bool = false` (line 15) -- User is transmitting camera video

These are serialized via `from_dict()` (lines 35-36) and `to_dict()` (lines 49-50), and are sent/received through the gateway `voice.state_update` event. The `voice_state_to_dict()` conversion in `client_models.gd` (line 535) includes both `self_video` and `self_stream` in its output dict.

## Implementation Status

- [x] godot-livekit GDExtension with LiveKitRoom-based connections (Linux, Windows, macOS)
- [x] Camera publishing via LiveKitVideoSource + LiveKitLocalVideoTrack + LiveKitLocalParticipant
- [x] Screen share publishing via LiveKitVideoSource (1920x1080) + SOURCE_SCREENSHARE
- [x] AccordVoiceState `self_video` and `self_stream` flags
- [x] Gateway `voice.state_update` event carries video flags
- [x] Voice signaling handled internally by LiveKit (no gateway VOICE_SIGNAL needed)
- [x] VoiceManager connection lifecycle (join/leave/forced disconnect)
- [x] VoiceApi REST endpoints (join, leave, get_status)
- [x] AccordClient re-emits all gateway voice signals
- [x] Client voice gateway event handlers with sound effects for peer join/leave
- [x] AppState voice/video signals and state tracking (11 signals, 6 state vars)
- [x] Client voice mutation API with track cleanup
- [x] Voice state cache with data access API
- [x] ClientModels `voice_state_to_dict()` conversion
- [x] ClientFetch `fetch_voice_states()` for REST-based voice state population
- [x] Dedicated `voice_channel_item` scene with expandable participant list, drag-and-drop reorder, edit/delete context menu
- [x] Voice channel click toggles join/leave (does not emit `channel_selected`)
- [x] Auto-select skips voice channels
- [x] Voice bar with mute/deafen/cam/share/sfx/settings/disconnect buttons
- [x] Voice bar self-manages visibility via AppState signals
- [x] LiveKitAdapter wired into Client (join connects room, leave disconnects, mute/deafen forwarded)
- [x] Force-disconnect detection (gateway voice_state_update with null channel_id)
- [x] Video enable/disable UI (Cam button in voice bar)
- [x] Screen sharing UI (Share button + screen picker dialog using DisplayServer)
- [x] Video/stream indicators in voice channel participant rows (green V, blue S)
- [x] Track cleanup on voice disconnect (camera, screen, all remote tracks via `.close()`)
- [x] Local video preview via `VideoTile` polling `LiveKitVideoStream.poll()` + `.get_texture()`
- [x] Video participant grid layout with responsive column count
- [x] Video quality settings (resolution presets + frame rate) persisted via `ConfigVoice`
- [x] Input/output device selection and persistence
- [x] Public track accessors (`Client.get_camera_track()`, `Client.get_screen_track()`, `Client.get_remote_track()`)
- [x] Remote video rendering pipeline (LiveKitAdapter `track_received` -> ClientVoice cache -> VideoGrid live tiles)
- [x] Speaking indicator on video tiles (green border when user is speaking)
- [x] LiveKitAdapter unit tests (state machine, mute/deafen, signals, disconnect, unpublish)
- [ ] **Full-area video view** (Discord-style: replaces message content when viewing voice channel)
- [ ] **Screen share spotlight layout** (large main view + small participant strip)
- [ ] **Mini PiP overlay** (floating preview when navigating away from voice channel)
- [ ] **Adaptive grid sizing** (auto-layout based on participant count: 1=full, 2=halves, 3-4=2x2, etc.)
- [ ] **Voice bar click to open video view** (clicking channel name in voice bar opens full-area view)
- [ ] **Active speaker detection in video view** (green border or focus on speaking user's tile)
- [ ] **Double-click to spotlight** (focusing a specific participant)
- [ ] Bandwidth adaptation for video streams
- [ ] Window sharing via `LiveKitScreenCapture.get_windows()` + `create_for_window()` (API now available in godot-livekit)
- [ ] Actual screen/window frame capture via `LiveKitScreenCapture` piped to `LiveKitVideoSource` (API now available)
- [ ] Camera device selection applied at publish time (Config value persisted but not routed to LiveKit source)

## Gaps / TODO

### Discord-Style UI Redesign (High Priority)

| Gap | Severity | Notes |
|-----|----------|-------|
| Video grid is an inline strip, not full-area | High | Currently `VideoGrid` sits between `TopicBar` and `ContentBody` in `main_window.tscn` with a fixed 140px min height. Discord shows video as a **full content area** that replaces the message view. Need to: (1) add `voice_view_opened` / `voice_view_closed` signals to `AppState`, (2) toggle visibility of `message_view` vs `video_grid` in `main_window.gd`, (3) make `video_grid` fill the full `ContentBody` area (`size_flags_vertical = SIZE_EXPAND_FILL`) |
| No screen share spotlight layout | High | Discord shows the shared screen as the dominant large view with participants as a small strip alongside. Current grid treats all tiles equally (uniform `GridContainer`). Need: (1) an `HBoxContainer` or `VBoxContainer` layout with a large `FocusedTile` and a scrollable `ParticipantStrip`, (2) logic in `_rebuild()` to detect screen share tiles and assign them the spotlight role, (3) double-click on any tile to manually spotlight it |
| No mini PiP (picture-in-picture) | Medium | When user navigates to a text channel while in voice, Discord shows a small floating video preview in the bottom-right corner. Need: (1) a `PiPOverlay` scene (small `PanelContainer` with a single `VideoTile`), (2) spawn it in `main_window.gd` when switching from voice view to text view while `voice_channel_id` is non-empty, (3) show active speaker or screen share in the PiP, (4) click PiP to return to full video view, (5) remove PiP on `voice_left` |
| Voice bar doesn't open video view on click | Medium | Discord lets you click the voice channel name in the voice bar to jump to the video view. Currently `voice_bar.gd` only has controls (mute/cam/etc), the status row is not clickable. Need to make `channel_label` or `StatusRow` a `Button` that emits `voice_view_opened` |
| Adaptive grid doesn't match Discord sizing | Low | Current grid is 1 column on COMPACT, 2 on MEDIUM/FULL. Discord dynamically sizes: 1 person fills the area, 2 split side-by-side, 3-4 are 2x2, 5-9 are 3x3, etc. Should calculate columns from participant count in `_update_grid_columns()` |
| No tile interaction (double-click to focus) | Low | Discord allows clicking/double-clicking a participant tile to spotlight them (switch to focused layout). No input handling on `video_tile.gd` currently |

### Existing Gaps

| Gap | Severity | Notes |
|-----|----------|-------|
| No window sharing | Medium | Screen picker (`screen_picker_dialog.gd`) only enumerates screens via `DisplayServer.get_screen_count()`. No window tab or window enumeration. `start_screen_share()` source_type and source_id params are currently unused -- `publish_screen()` always publishes at default 1920x1080. **Now unblocked:** `LiveKitScreenCapture.get_windows()` and `create_for_window()` enable window-level capture |
| Camera device not routed to publish | Medium | `Config.voice.get_video_device()` is persisted but `toggle_video()` doesn't pass the device ID to `LiveKitAdapter.publish_camera()`. The adapter creates a `LiveKitVideoSource` with no device selection |
| No bandwidth adaptation | Low | Fixed video parameters with no dynamic quality adjustment based on network conditions |
| No video track hot-swap | Low | Switching cameras requires stopping the old track and creating a new one. No seamless hot-swap mechanism |
