# Application Sound Effects

*Last touched: 2026-02-18 21:14*

## Overview

Application sound effects provide audible feedback for key events: incoming messages, mentions, users joining/leaving voice, call ringing, and UI interactions. Unlike the [Soundboard](soundboard.md) (which plays user-uploaded clips into voice channels), these are built-in client-side sounds that play through the user's local speakers. Currently **none of this is implemented** -- the client is entirely silent.

## User Steps

1. User receives a new message in a channel they are not viewing -- a notification sound plays.
2. User receives a mention (`@username`) -- a distinct mention sound plays.
3. User joins or leaves a voice channel -- a join/leave chime plays.
4. User sends a message -- an optional send sound plays.
5. User opens Settings > Sound Effects and adjusts which sounds are enabled and their volume.
6. User sets their status to Do Not Disturb -- all notification sounds are suppressed.

## Signal Flow

```
Gateway event (e.g. MESSAGE_CREATE)
  │
  ├─► Client._on_message_create()
  │     └─► AppState.messages_updated
  │           └─► MessageView loads messages (visual)
  │
  └─► (NOT YET IMPLEMENTED)
        SoundManager.play("message_received")
          └─► AudioStreamPlayer.play()

User changes sound settings
  └─► (NOT YET IMPLEMENTED)
        Config persists sound preferences
          └─► SoundManager reloads volume/mute state
```

## Key Files

| File | Role |
|------|------|
| *(none yet)* | No sound effect files, scenes, or scripts exist |
| `scripts/autoload/app_state.gd` | Central signal bus -- would emit signals that trigger sounds |
| `scripts/autoload/client.gd` | Receives gateway events that should produce sounds |
| `scripts/autoload/client_gateway.gd` | Handles gateway dispatch -- message create, typing, presence |
| `scripts/autoload/config.gd` | Would persist sound preferences (volume, mute, per-event toggles) |
| `user_flows/in_app_notifications.md` | Related flow -- visual notifications, currently no sound |
| `user_flows/soundboard.md` | Distinct feature -- user clips played into voice channels |

## Implementation Details

### Current State

There are zero application sound effects in the codebase:

- No audio asset files (`.wav`, `.ogg`, `.mp3`) exist anywhere in the project.
- No `AudioStreamPlayer` nodes exist in any scene.
- No `AudioServer` or `AudioBus` configuration is used.
- No sound-related settings exist in `Config` (`scripts/autoload/config.gd`).
- No sound-related signals exist in `AppState` beyond `soundboard_updated` and `soundboard_played` (line 40, 42 of `app_state.gd`), which are for the voice channel soundboard feature.

The `in_app_notifications.md` user flow explicitly notes this gap: "No calls to OS notification APIs, no system tray integration, no notification sounds."

### Proposed Architecture

#### SoundManager Autoload

A new autoload singleton (`scripts/autoload/sound_manager.gd`) would:

- Preload audio assets for each sound event.
- Expose a `play(sound_name: String)` method.
- Respect per-event mute toggles and a master SFX volume from `Config`.
- Suppress all sounds when the user's status is Do Not Disturb.
- Use a pool of `AudioStreamPlayer` nodes to handle overlapping sounds.

#### Sound Events

| Event | Trigger | Condition |
|-------|---------|-----------|
| `message_received` | `AppState.messages_updated` | Channel is not currently viewed; window may or may not be focused |
| `mention_received` | `AppState.messages_updated` | Message contains `@current_user` |
| `message_sent` | `AppState.message_sent` | User sends a message (optional, off by default) |
| `voice_join` | User or other user joins voice | Voice channel feature connected |
| `voice_leave` | User or other user leaves voice | Voice channel feature connected |
| `call_ringing` | Incoming DM call | DM call feature (not yet implemented) |
| `deafen` / `undeafen` | User toggles deafen | Voice connected |
| `mute` / `unmute` | User toggles mute | Voice connected |

#### Audio Assets

Sound files should be placed in `assets/sounds/` as `.ogg` (OGG Vorbis) files. OGG is preferred in Godot for short sound effects due to small file size and no licensing issues. Each file should be imported with `loop = false`.

#### Config Persistence

`Config` (`scripts/autoload/config.gd`) would store:

```
[sounds]
master_volume=1.0
message_received=true
mention_received=true
message_sent=false
voice_join=true
voice_leave=true
call_ringing=true
```

#### AudioBus Layout

A dedicated `SFX` audio bus in Godot's audio bus layout would allow the SFX volume to be adjusted independently of any future music or voice audio buses.

## Implementation Status

- [ ] Audio asset files (`.ogg`) for each sound event
- [ ] `SoundManager` autoload singleton
- [ ] `AudioStreamPlayer` pool for overlapping playback
- [ ] `SFX` audio bus in Godot's bus layout
- [ ] Config persistence for sound preferences (volume, per-event toggles)
- [ ] Settings UI for sound preferences
- [ ] Message received sound (non-focused channel)
- [ ] Mention received sound
- [ ] Message sent sound (optional)
- [ ] Voice join/leave chimes
- [ ] Call ringing sound
- [ ] Mute/deafen toggle sounds
- [ ] Do Not Disturb suppression
- [ ] Respect OS-level mute / volume

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No audio assets exist | High | Need to source or create `.ogg` sound effect files for each event. Could use freely-licensed sound packs. |
| No SoundManager autoload | High | Core infrastructure for playing sounds does not exist. Must be created as a new autoload. |
| No AudioStreamPlayer in any scene | High | No audio playback nodes exist anywhere in the client. |
| No sound preferences in Config | Medium | `config.gd` has no sound-related keys. Users cannot enable/disable or adjust volume of individual sounds. |
| No Settings UI for sounds | Medium | No settings panel exists for sound configuration. |
| Do Not Disturb is cosmetic only | Medium | `AppState` tracks DND status visually (`app_state.gd`), but it has no effect on notifications or sounds. |
| Voice join/leave not implemented | Low | Voice channel connection itself is not yet implemented (see `voice_channels.md`), so voice sounds are blocked on that. |
| DM call ringing not implemented | Low | DM calling does not exist yet, so call ringing sound is blocked on that feature. |
