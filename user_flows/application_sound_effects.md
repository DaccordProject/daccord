# Application Sound Effects


## Overview

Application sound effects provide audible feedback for key events: incoming messages, mentions, users joining/leaving voice, and UI interactions like mute/deafen toggles. Unlike the [Soundboard](soundboard.md) (which plays user-uploaded clips into voice channels), these are built-in client-side sounds that play through the user's local speakers via the `SFX` audio bus.

## User Steps

1. User receives a new message in a channel they are not viewing -- a notification sound plays (only when the window is unfocused; mentions always play).
2. User receives a mention (`@username`) -- a distinct mention sound plays regardless of window focus.
3. User joins or leaves a voice channel -- a join/leave chime plays.
4. Another user joins or leaves the same voice channel the user is in -- a peer join/leave chime plays.
5. User sends a message -- an optional send sound plays (off by default).
6. User toggles mute or deafen -- a toggle sound plays.
7. User sets their status to Do Not Disturb -- all notification sounds are suppressed.
8. User opens Sound Settings from the user bar menu -- adjusts volume and toggles individual sounds.

## Signal Flow

```
Gateway event (MESSAGE_CREATE)
  │
  ├─► ClientGateway.on_message_create()
  │     ├─► AppState.messages_updated          (visual)
  │     └─► SoundManager.play_for_message()    (audio)
  │           ├─ Skips if author is self
  │           ├─ Skips if channel is currently viewed
  │           ├─ Plays "mention_received" if @mention (always)
  │           └─ Plays "message_received" only if window is unfocused
  │
  └─► SoundManager.play()
        ├─ Checks Config.is_sound_enabled()
        ├─ Checks DND status (suppresses all)
        └─ AudioStreamPlayer.play() on SFX bus

User sends message
  └─► AppState.message_sent
        └─► SoundManager._on_message_sent()
              └─► play("message_sent")

User joins/leaves voice
  └─► AppState.voice_joined / voice_left
        └─► SoundManager._on_voice_joined/left()
              └─► play("voice_join" / "voice_leave")

Peer joins/leaves same voice channel
  └─► ClientGateway.on_voice_state_update()
        └─► SoundManager.play_for_voice_state(user_id, joined, left)
              ├─ Skips if user is self
              ├─ Skips if not in a voice channel
              ├─ Plays "peer_join" if peer joined our channel
              └─ Plays "peer_leave" if peer left our channel

User toggles mute/deafen
  └─► AppState.voice_mute_changed / voice_deafen_changed
        └─► SoundManager._on_voice_mute/deafen_changed()
              └─► play("mute"/"unmute" / "deafen"/"undeafen")

User opens Sound Settings
  └─► user_bar menu → "Sound Settings"
        └─► SoundSettingsDialog
              ├─ Volume slider (HSlider) bound to Config.get/set_sfx_volume()
              └─ Per-event CheckBoxes bound to Config.is/set_sound_enabled()

User changes sound settings
  └─► Config persists sound preferences
        └─► SoundManager reads on next play()
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/sound_manager.gd` | SoundManager autoload -- preloads audio, connects to AppState signals, plays sounds through SFX bus. Tracks window focus to suppress non-mention sounds when focused. |
| `scripts/autoload/config.gd` | Persists sound preferences: `get_sfx_volume()`, `set_sfx_volume()`, `is_sound_enabled()`, `set_sound_enabled()` |
| `scripts/autoload/client_gateway.gd` | Calls `SoundManager.play_for_message()` in `on_message_create()` and `SoundManager.play_for_voice_state()` in `on_voice_state_update()` |
| `scripts/autoload/app_state.gd` | Emits signals that trigger sounds: `message_sent`, `voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed` |
| `scenes/sidebar/sound_settings_dialog.gd` | Sound Settings dialog -- volume slider + per-event toggle checkboxes |
| `scenes/sidebar/sound_settings_dialog.tscn` | Sound Settings dialog scene |
| `scenes/sidebar/user_bar.gd` | Opens Sound Settings dialog from menu (id 12) |
| `assets/sfx/` | WAV audio files for each sound event |
| `default_bus_layout.tres` | Audio bus layout with `Master` and `SFX` buses |
| `project.godot` | Registers `SoundManager` autoload |

## Implementation Details

### Audio Assets

WAV files in `assets/sfx/`, each mapped to a sound event:

| File | Event | Trigger |
|------|-------|---------|
| `message_received.wav` | `message_received` | New message in unfocused channel |
| `mention_received.wav` | `mention_received` | Message contains `@current_user` |
| `message_sent.wav` | `message_sent` | User sends a message (off by default) |
| `voice_join.wav` | `voice_join` | User joins a voice channel |
| `voice_leave.wav` | `voice_leave` | User leaves a voice channel |
| `mute.wav` | `mute` | User mutes microphone |
| `unmute.wav` | `unmute` | User unmutes microphone |
| `deafen.wav` | `deafen` | User deafens audio |
| `undeafen.wav` | `undeafen` | User undeafens audio |
| `voice_join.wav` | `peer_join` | Another user joins the same voice channel (reuses `voice_join.wav`) |
| `voice_leave.wav` | `peer_leave` | Another user leaves the same voice channel (reuses `voice_leave.wav`) |

### SoundManager Autoload

`SoundManager` (`scripts/autoload/sound_manager.gd`):

- Preloads all WAV assets as constants via `preload()`.
- `play(sound_name)` -- checks `Config.is_sound_enabled()`, checks DND status, then plays through an `AudioStreamPlayer` pool.
- `play_for_message(channel_id, author_id, mentions, mention_everyone)` -- called by `ClientGateway.on_message_create()`. Skips if author is self or channel is currently viewed. Plays `mention_received` for @mentions (always), `message_received` only when window is unfocused.
- `play_for_voice_state(user_id, joined_channel, left_channel)` -- called by `ClientGateway.on_voice_state_update()`. Skips if user is self or local user is not in voice. Plays `peer_join`/`peer_leave` when a peer joins or leaves the same voice channel.
- Tracks window focus via `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` to suppress `message_received` when the window is focused.
- Uses a pool of 4 `AudioStreamPlayer` nodes on the `SFX` bus for overlapping playback.
- Connects to `AppState` signals in `_ready()`: `message_sent`, `voice_joined`, `voice_left`, `voice_mute_changed`, `voice_deafen_changed`.

### Config Persistence

`Config` stores sound preferences in the `[sounds]` section:

```
[sounds]
volume=1.0
message_received=true
mention_received=true
message_sent=false
voice_join=true
voice_leave=true
peer_join=true
peer_leave=true
mute=true
unmute=true
deafen=true
undeafen=true
```

Methods: `get_sfx_volume()`, `set_sfx_volume(vol)`, `is_sound_enabled(name)`, `set_sound_enabled(name, enabled)`.

### AudioBus Layout

`default_bus_layout.tres` defines two buses:
- `Master` -- default Godot bus
- `SFX` -- routes to Master; all `SoundManager` players output here

### DND Suppression

When the current user's status is `ClientModels.UserStatus.DND`, `SoundManager.play()` suppresses all sounds.

### Sound Settings UI

The Sound Settings dialog (`scenes/sidebar/sound_settings_dialog.gd`) is accessible from the user bar menu (id 12). It contains:

- **Volume slider** (`HSlider`, 0-100%) bound to `Config.get/set_sfx_volume()`
- **Per-event checkboxes** for each sound event, bound to `Config.is/set_sound_enabled()`
- Changes are applied on "Apply" (confirmed signal)

### Window Focus Detection

`SoundManager` tracks window focus via `NOTIFICATION_APPLICATION_FOCUS_IN/OUT`. When the window is focused, `play_for_message()` suppresses `message_received` (generic new-message sound) but still plays `mention_received` (mentions always sound regardless of focus).

## Implementation Status

- [x] Audio asset files (`.wav`) for each sound event
- [x] `SoundManager` autoload singleton
- [x] `AudioStreamPlayer` pool for overlapping playback
- [x] `SFX` audio bus in Godot's bus layout
- [x] Config persistence for sound preferences (volume, per-event toggles)
- [x] Settings UI for sound preferences (Sound Settings dialog in user bar menu)
- [x] Message received sound (unfocused window only)
- [x] Mention received sound (plays regardless of window focus)
- [x] Message sent sound (optional, off by default)
- [x] Voice join/leave chimes
- [x] Mute/deafen toggle sounds
- [x] Do Not Disturb suppression
- [x] Peer join/leave sounds (when others join/leave the same voice channel)
- [x] Window focus detection (suppresses `message_received` when focused)
- [ ] Call ringing sound (blocked on DM call feature)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Call ringing sound | Low | DM calling does not exist yet, so call ringing is blocked on that feature. |

Last touched: 2026-02-19
