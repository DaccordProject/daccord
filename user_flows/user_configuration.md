# User Configuration

Last touched: 2026-02-20

## Overview

All user preferences and connection data are persisted locally in a single encrypted `ConfigFile` at `user://config.cfg`. The `Config` autoload (`scripts/autoload/config.gd`) is the sole gateway to this file, providing typed getter/setter pairs for each preference domain. Every setter immediately writes the full config back to disk via `save_encrypted_pass()`. There is no in-memory batching or deferred write.

## User Steps

### Changing voice/video device settings
1. User clicks gear icon in the voice bar (or accesses voice settings).
2. Voice Settings dialog appears with dropdowns for microphone, speaker, camera, resolution, and FPS.
3. User selects devices and clicks "Apply".
4. Settings are saved to the `[voice]` config section.

### Changing sound settings
1. User clicks their avatar in the user bar, selects "Sound Settings".
2. Sound Settings dialog appears with volume slider and per-event checkboxes.
3. User adjusts volume and toggles sound events, clicks "Apply".
4. Settings are saved to the `[sounds]` config section.

### Setting user status
1. User clicks their avatar in the user bar.
2. A menu appears with Online, Idle, Do Not Disturb, Invisible options.
3. User selects a status; it is saved locally and broadcast to all connected servers.

### Setting custom status
1. User clicks their avatar, selects "Set Custom Status".
2. A dialog with a text input and "Clear Status" button appears.
3. User types a status message and clicks "Save".
4. Text is saved to Config and sent as a presence activity to all servers.

### Toggling error reporting
1. On first launch, a consent dialog asks to enable anonymous error reporting.
2. User can also toggle via user bar menu > "Send Error Reports" checkbox.
3. Preference is saved to the `[error_reporting]` config section.

### Managing guild folders
1. User right-clicks a guild icon, selects "Move to Folder".
2. A dialog shows existing folder names and a text input for a new name.
3. User picks or types a folder name and clicks "Move".
4. Guild-to-folder mapping is saved in the `[folders]` config section.

## Signal Flow

```
User changes setting in dialog
    |
    v
Dialog._on_confirmed()
    |
    v
Config.set_*()  -->  _config.set_value(section, key, val)
    |
    v
Config.save()  -->  _config.save_encrypted_pass(CONFIG_PATH, key)
    |
    v
user://config.cfg (AES-256-CBC encrypted on disk)
```

```
App startup (Config._ready)
    |
    v
_config.load_encrypted_pass(CONFIG_PATH, key)
    |
    +--> OK: config loaded
    |
    +--> ERR: try _config.load(CONFIG_PATH) plaintext
              |
              +--> OK: re-save encrypted (migration)
              |
              +--> ERR: _config stays empty (data lost)
```

```
App startup (Client._ready, line 98)
    |
    v
Config.has_servers()? --yes--> connect_server(i) for each
    |                              |
    no                             v
    |                          Config.get_servers()[i]  --> read base_url, token, guild_name
    v                              |
Mode stays CONNECTING              v
(empty UI)                     Auth + guild lookup + gateway connect
                                   |
                                   v
                               Mode = LIVE, guilds_updated emitted
                                   |
                                   v
                               Sidebar._on_guilds_updated() (line 22)
                                   |
                                   v
                               Config.get_last_selection() --> restore guild + channel
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/config.gd` | Central config store -- all local persistence goes through here |
| `scripts/autoload/client.gd` | Reads server configs on startup (line 98), restores saved status (line 293) |
| `scripts/autoload/client_mutations.gd` | Saves user status to Config on presence change (line 283) |
| `scenes/sidebar/user_bar.gd` | User menu: status, custom status, sound settings, error reporting |
| `scenes/sidebar/voice_settings_dialog.gd` | Voice/video device and resolution preferences |
| `scenes/sidebar/sound_settings_dialog.gd` | SFX volume and per-event sound toggles |
| `scenes/sidebar/sidebar.gd` | Reads/writes last guild+channel selection (lines 29, 53, 70) |
| `scenes/sidebar/channels/category_item.gd` | Reads/writes category collapsed state (lines 91, 97) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Reads/writes guild folder assignment (lines 197, 250) |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | Adds server entries to Config (line 169) |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Provides username+password for credential storage |
| `scenes/messages/composer/emoji_picker.gd` | Reads/writes recently used emoji (lines 28, 198) |
| `scenes/main/main_window.gd` | Error reporting consent dialog on first launch (line 338) |

## Implementation Details

### Config file structure

The config is a Godot `ConfigFile` stored at `user://config.cfg` (resolves to `~/.local/share/godot/app_userdata/daccord/config.cfg` on Linux). It is encrypted with AES-256-CBC using the key `"daccord-config-v1" + OS.get_user_data_dir()` (line 19).

Sections and keys:

| Section | Key(s) | Type | Default | Written by |
|---------|--------|------|---------|------------|
| `servers` | `count` | int | `0` | `add_server()`, `remove_server()` |
| `server_0` .. `server_N` | `base_url`, `token`, `guild_name`, `username`, `password` | String | `""` | `add_server()`, `update_server_url()`, `update_server_token()` |
| `state` | `last_guild_id`, `last_channel_id` | String | `""` | `sidebar.gd` on guild/channel selection |
| `state` | `user_status` | int | `0` (ONLINE) | `client_mutations.gd` on presence change |
| `state` | `custom_status` | String | `""` | `user_bar.gd` custom status dialog |
| `voice` | `input_device`, `output_device`, `video_device` | String | `""` | `voice_settings_dialog.gd` |
| `voice` | `video_resolution` | int | `0` (480p) | `voice_settings_dialog.gd` |
| `voice` | `video_fps` | int | `30` | `voice_settings_dialog.gd` |
| `sounds` | `volume` | float | `1.0` | `sound_settings_dialog.gd` |
| `sounds` | `<event_name>` | bool | `true` (except `message_sent` = `false`) | `sound_settings_dialog.gd` |
| `notifications` | `suppress_everyone` | bool | `false` | (no UI wired yet) |
| `muted_servers` | `<guild_id>` | bool | `false` | (no UI wired yet) |
| `error_reporting` | `enabled` | bool | `false` | `user_bar.gd`, `main_window.gd` consent dialog |
| `error_reporting` | `consent_shown` | bool | (absent) | `main_window.gd` (line 341) |
| `folders` | `<guild_id>` | String | `""` | `guild_icon.gd` folder dialog |
| `folder_colors` | `<guild_id>` | Color | `Color(0.212, 0.224, 0.247)` | `guild_icon.gd` |
| `collapsed_<guild_id>` | `<category_id>` | bool | `false` | `category_item.gd` (line 91) |
| `emoji` | `recent` | Array | `[]` | `emoji_picker.gd` |

### Encryption and loading (config.gd lines 8-16)

On `_ready()`, Config attempts `load_encrypted_pass()` with a derived key. If that fails, it falls back to a plaintext `load()` -- this supports first-run (no file) and migration from unencrypted configs. If the plaintext load succeeds, the file is immediately re-saved encrypted. If both fail, `_config` remains an empty `ConfigFile` and all getters return their defaults.

The encryption key is derived from a static salt concatenated with `OS.get_user_data_dir()` (line 19). This means the key is stable across sessions **as long as the Godot version and project name stay the same**. If the user upgrades Godot and the engine changes its `ConfigFile` encryption internals, old encrypted files become unreadable.

### Server credential storage (config.gd lines 35-47)

When a server is added, the base URL, auth token, guild name, and optionally username + password are stored in sections `server_0`, `server_1`, etc. The `servers` section tracks the count. Credentials are only stored when the user authenticates via the auth dialog (sign-in or register flow) -- when a raw `?token=...` URL is used, `username` and `password` are stored as empty strings, which prevents automatic re-authentication if the token expires.

### Server removal and index shifting (config.gd lines 49-67)

`remove_server()` shifts all subsequent server sections down to fill the gap and erases the last section. This renumbers all connections, so `Client.disconnect_server()` (client.gd line 612) also rebuilds `_guild_to_conn` after removing the config entry.

### Session restore (sidebar.gd lines 22-46, client.gd lines 292-296)

On startup, after the first `guilds_updated` signal fires, `sidebar._on_guilds_updated()` reads `Config.get_last_selection()` and attempts to restore the previously-viewed guild and channel. If the saved guild no longer exists, it falls back to the first guild.

Separately, `Client.connect_server()` restores the saved user status (line 293-296): if the user's last status was not ONLINE, it calls `update_presence()` to broadcast the saved status to all servers.

### Voice/video settings (voice_settings_dialog.gd)

The dialog enumerates available devices via `AccordStream.get_microphones()`, `AccordStream.get_speakers()`, and `AccordStream.get_cameras()` (lines 21, 40, 59). Each dropdown pre-selects the device ID stored in Config. On "Apply" (line 96), all selected device IDs and presets are saved.

Video resolution offers three hardcoded presets: 480p (index 0), 720p (index 1), 360p (index 2) (lines 78-83). FPS choices are 15 and 30 (lines 89-90).

### Sound settings (sound_settings_dialog.gd)

The dialog lists 11 sound events with per-event checkboxes (lines 3-15). Volume is a slider from 0.0 to 1.0 with 0.05 step (lines 27-29). All values are read from Config on dialog open and written back on "Apply" (lines 51-56).

### Recently used emoji (config.gd lines 241-258)

`add_recent_emoji()` maintains a most-recently-used list capped at 16 entries. Duplicates are moved to the front. The emoji picker reads this on open to show a "Recent" category (emoji_picker.gd line 28).

### Custom emoji cache (client.gd lines 739-777)

Custom guild emoji are downloaded and cached as PNG files in `user://emoji_cache/<emoji_id>.png`. This is a write-once disk cache -- emoji are checked on disk before downloading. The in-memory mappings are tracked in `ClientModels.custom_emoji_paths` and `ClientModels.custom_emoji_textures`.

### Notification preferences (config.gd lines 219-237)

`suppress_everyone` and per-server mute (`muted_servers`) preferences are stored in Config but have no UI to control them yet.

### Category collapse state (category_item.gd lines 83-103)

Each category tracks its collapsed state in a per-guild Config section `collapsed_<guild_id>`. On toggle (line 91), the state is saved. On channel list load, `restore_collapse_state()` (line 93) reads the saved state.

## Local Data Summary

All user data resides under `user://` (typically `~/.local/share/godot/app_userdata/daccord/`):

| Path | Contents | Managed by |
|------|----------|------------|
| `config.cfg` | All preferences, server credentials, UI state (encrypted) | `Config` autoload |
| `emoji_cache/<id>.png` | Downloaded custom emoji images | `Client.register_custom_emoji()` |
| `logs/godot.log` | Godot engine log (created by engine) | Engine |

## Implementation Status

- [x] Encrypted config file with plaintext migration fallback
- [x] Server connection storage (URL, token, guild name, credentials)
- [x] Server removal with index shifting
- [x] Session restore (last guild + channel selection)
- [x] User status persistence across sessions
- [x] Custom status text persistence
- [x] Voice device preferences (mic, speaker, camera)
- [x] Video resolution and FPS preferences
- [x] SFX volume and per-event sound toggles
- [x] Error reporting opt-in with first-launch consent
- [x] Guild folder assignments and colors
- [x] Category collapse state per guild
- [x] Recently used emoji (16 max)
- [x] Custom emoji disk cache
- [x] Notification preference storage (suppress @everyone, server mute)
- [x] UI for notification preferences (suppress @everyone, server mute)
- [x] Config load-failure guard (prevent save from overwriting unreadable file)
- [x] Config export/import
- [x] Config backup before overwrite
- [x] Emit `server_connection_failed` on initial auth failure
- [x] Token-only re-auth signal (`reauth_needed`) with auth dialog

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Encryption key tied to `OS.get_user_data_dir()` | Low | The key derivation (config.gd line 19) depends on Godot's user data directory path. If the project name changes in `project.godot` or the user data dir convention changes between Godot versions, old config files become unreadable. |
| No emoji cache eviction | Low | `user://emoji_cache/` grows unboundedly as custom emoji are encountered. No max-size or LRU eviction is implemented. |
| Video resolution presets are hardcoded | Low | Resolution options (480p, 720p, 360p) and FPS options (15, 30) are defined as literals in `voice_settings_dialog.gd` lines 78-93 rather than being data-driven or coming from AccordStream capabilities. |
| `save()` called on every individual setter | Low | Each `Config.set_*()` calls `save_encrypted_pass()` immediately. Rapid successive changes (e.g., applying all sound settings) trigger multiple disk writes. A deferred/batched save would be more efficient. |
