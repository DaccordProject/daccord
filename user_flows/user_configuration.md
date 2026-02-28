# User Configuration

Last touched: 2026-02-25

## Overview

All user preferences and connection data are persisted locally in encrypted `ConfigFile` instances, one per profile. The `Config` autoload (`scripts/autoload/config.gd`) is the sole gateway to the active profile's config, providing typed getter/setter pairs for each preference domain. Every setter immediately writes the full config back to disk via `save_encrypted_pass()`. There is no in-memory batching or deferred write.

**Profiles** allow multiple people (or the same person with different server setups) to share a single daccord installation. Each profile is an independent directory under `user://profiles/<slug>/` containing its own `config.cfg` and `emoji_cache/`. The app ships with a "Default" profile that is automatically active, so single-user installations work exactly as before with zero friction. See [Profiles](profiles.md) for the full profile lifecycle (creating, switching, passwords, deletion).

A lightweight **profile registry** at `user://profile_registry.cfg` (unencrypted) tracks all profile names, the active profile slug, display order, and optional password hashes. The actual config data lives inside each profile's encrypted `config.cfg`.

The user-facing term for what was previously called "config" is now **profile**. Export/import operations are framed as "Export Profile" / "Import Profile" so users understand they are portable, self-contained bundles of their settings.

## User Steps

### Changing voice/video device settings
1. User opens Settings (gear icon in user bar or user bar menu).
2. User navigates to "Voice & Video" page.
3. Dropdowns for microphone, speaker, resolution, and FPS appear, pre-selected to current values.
4. User selects devices; changes are saved immediately to the `[voice]` config section.

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
2. User can also toggle via Settings > Notifications > "Send anonymous crash and error reports" checkbox.
3. Preference is saved to the `[error_reporting]` config section.

### Managing space folders
1. User right-clicks a space icon, selects "Move to Folder".
2. A dialog shows existing folder names and a text input for a new name.
3. User picks or types a folder name and clicks "Move".
4. Space-to-folder mapping is saved in the `[folders]` config section.

### Exporting a profile
1. User clicks their avatar in the user bar, selects "Export Profile".
2. A native file-save dialog opens, defaulting to `.daccord-profile` extension.
3. The active profile's config is saved as a sanitized plaintext `ConfigFile` to the chosen path. **Tokens and passwords are stripped** — the export contains only preferences, server URLs, space names, and usernames.
4. Emoji cache is **not** included (it can be re-downloaded).

### Importing a profile
1. User clicks their avatar in the user bar, selects "Import Profile".
2. A native file-open dialog opens, filtering for `.daccord-profile` files.
3. A dialog asks for a profile name (pre-filled from the file name) and optional password.
4. A new profile is created with the imported config data. Any password keys are stripped, and the config is saved encrypted (not plain text).
5. The user can then switch to the imported profile from the Profiles section in Settings.

## Signal Flow

```
User changes setting in dialog
    |
    v
Dialog._on_confirmed() / immediate signal callback
    |
    v
Config.set_*()  -->  _config.set_value(section, key, val)
    |
    v
Config._save()  -->  _config.save_encrypted_pass(_profile_config_path(), key)
    |
    v
user://profiles/<active-slug>/config.cfg (AES-256-CBC encrypted on disk)
```

```
=== APP STARTUP (Config._ready) ===

Config._ready()
    |
    v
FileAccess.file_exists(REGISTRY_PATH)?
    |
    yes: load registry, read active slug, set config path
    |
    no: first-time profile setup
        |
        +-> FileAccess.file_exists("user://config.cfg")?
            |
            yes: MIGRATION FROM PRE-PROFILE
            |   DirAccess.make_dir_recursive("user://profiles/default/")
            |   DirAccess.rename("user://config.cfg",
            |       "user://profiles/default/config.cfg")
            |   DirAccess.rename("user://emoji_cache/",
            |       "user://profiles/default/emoji_cache/")
            |   write registry with active = "default"
            |
            no: FRESH INSTALL
                DirAccess.make_dir_recursive("user://profiles/default/")
                write empty config.cfg
                write registry with active = "default"
    |
    v
Load config from user://profiles/<active>/config.cfg
    |
    +--> load_encrypted_pass(path, key)
    |       |
    |       OK: _load_ok = true
    |       |
    |       ERR: try plaintext load(path)
    |               |
    |               OK: re-save encrypted (migration), _load_ok = true
    |               |
    |               ERR: backup corrupted file, start fresh, _load_ok = true
    |
    v
(rest of _ready() proceeds -- Client reads servers, etc.)
```

```
=== SERVER RECONNECT ON STARTUP ===

App startup (Client._ready)
    |
    v
Config.has_servers()? --yes--> connect_server(i) for each
    |                              |
    no                             v
    |                          Config.get_servers()[i]  --> read base_url, token, space_name
    v                              |
Mode stays CONNECTING              v
(empty UI)                     Auth + space lookup + gateway connect
                                   |
                                   v
                               Mode = LIVE, spaces_updated emitted
                                   |
                                   v
                               Sidebar._on_spaces_updated()
                                   |
                                   v
                               Config.get_last_selection() --> restore space + channel
```

```
=== PROFILE SWITCH ===

User clicks target profile in Settings > Profiles
    |
    v
[Has password?] --yes--> PasswordDialog shown
    |                         |
    no                        v
    |                     User enters password
    |                         |
    |                     SHA-256(salt + slug + input) == stored hash?
    |                         |
    |                     no: show error, abort
    |                     yes: proceed
    |                         |
    +<------------------------+
    |
    v
Client.disconnect_all()
    |  (for each connection: close WebSocket, clear caches)
    |
    v
Config.switch_profile(slug)
    |
    +-> registry.set_value("state", "active", slug)
    |   registry.save(REGISTRY_PATH)
    |
    +-> _config = ConfigFile.new()
    |   _config.load_encrypted_pass(_profile_config_path(), key)
    |   _load_ok = true
    |
    +-> AppState.profile_switched.emit()
    |
    v
Client._on_profile_switched()
    |
    +-> clear all in-memory state (spaces, channels, users, messages)
    +-> Config.has_servers()? --yes--> connect_server(i) for each
    |                            |
    |                            v
    |                        normal startup flow (auth, space match, gateway)
    |                            |
    |                            v
    |                        AppState.spaces_updated.emit()
    |
    +-> no servers: stay in CONNECTING mode (empty UI)
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/config.gd` | Central config store -- all local persistence goes through here. Profile-aware: manages registry, profile paths, `switch_profile()`, `create_profile()`, `delete_profile()` |
| `scripts/autoload/app_state.gd` | Signal bus. Includes `profile_switched` signal for profile change broadcasts |
| `scripts/autoload/client.gd` | Reads server configs on startup, restores saved status. `disconnect_all()` and `_on_profile_switched()` for profile switches |
| `scripts/autoload/client_mutations.gd` | Saves user status to Config on presence change |
| `scenes/sidebar/user_bar.gd` | User menu: status, custom status, sound settings, error reporting, export/import profile |
| `scenes/user/user_settings.gd` | User Settings panel -- Voice & Video (page 2), Sound (page 3), and Notifications (page 4) preferences |
| `scenes/sidebar/sidebar.gd` | Reads/writes last space+channel selection |
| `scenes/sidebar/channels/category_item.gd` | Reads/writes category collapsed state |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Reads/writes space folder assignment |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | Adds server entries to Config |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Authentication dialog; accepts optional username pre-fill for re-auth flows |
| `scenes/messages/composer/emoji_picker.gd` | Reads/writes recently used emoji |
| `scenes/main/main_window.gd` | Error reporting consent dialog on first launch |
| `scenes/user/user_settings.gd` | Full settings panel with Profiles section |
| `scenes/user/profile_dialog.gd` | Create / edit profile dialog (name, password, copy vs fresh) |
| `scenes/user/profile_password_dialog.gd` | Password entry dialog for switching to protected profiles |

## Implementation Details

### Profile registry

A plain (unencrypted) `ConfigFile` at `user://profile_registry.cfg` tracks all profiles:

| Section | Key(s) | Type | Description |
|---------|--------|------|-------------|
| `state` | `active` | String | Slug of the currently active profile (e.g. `"default"`) |
| `profiles` | `<slug>` | String | Display name for each profile (e.g. `"default"` -> `"Default"`) |
| `passwords` | `<slug>` | String | SHA-256 hex digest of the profile's password (absent if no password) |
| `order` | `list` | Array | Ordered array of slugs for display ordering |

The registry is unencrypted because it contains no sensitive data (password hashes are one-way, profile names aren't secret). The actual credentials live inside each profile's encrypted `config.cfg`.

### Config file structure

Each profile has its own Godot `ConfigFile` stored at `user://profiles/<slug>/config.cfg`. It is encrypted with AES-256-CBC using the key `"daccord-config-v1" + OS.get_user_data_dir()`.

The `CONFIG_PATH` constant is replaced by the dynamic method `_profile_config_path()`:

```gdscript
func _profile_config_path() -> String:
    return "user://profiles/%s/config.cfg" % _profile_slug

func _profile_emoji_cache_dir() -> String:
    return "user://profiles/%s/emoji_cache" % _profile_slug
```

Sections and keys within each profile's `config.cfg`:

| Section | Key(s) | Type | Default | Written by |
|---------|--------|------|---------|------------|
| `servers` | `count` | int | `0` | `add_server()`, `remove_server()` |
| `server_0` .. `server_N` | `base_url`, `token`, `space_name`, `username`, `display_name` | String | `""` | `add_server()`, `update_server_url()`, `update_server_token()`, `update_server_username()` |
| `state` | `last_space_id`, `last_channel_id` | String | `""` | `sidebar.gd` on space/channel selection |
| `state` | `user_status` | int | `0` (ONLINE) | `client_mutations.gd` on presence change |
| `state` | `custom_status` | String | `""` | `user_bar.gd` custom status dialog |
| `voice` | `input_device`, `output_device`, `video_device` | String | `""` | `user_settings.gd` (Voice & Video page) |
| `voice` | `video_resolution` | int | `0` (480p) | `user_settings.gd` (Voice & Video page) |
| `voice` | `video_fps` | int | `30` | `user_settings.gd` (Voice & Video page) |
| `sounds` | `volume` | float | `1.0` | `user_settings.gd` (Sound page) |
| `sounds` | `<event_name>` | bool | `true` (except `message_sent` = `false`) | `user_settings.gd` (Sound page) |
| `notifications` | `suppress_everyone` | bool | `false` | Settings > Notifications |
| `muted_servers` | `<space_id>` | bool | `false` | Settings > Notifications |
| `error_reporting` | `enabled` | bool | `false` | `user_bar.gd`, `main_window.gd` consent dialog |
| `error_reporting` | `consent_shown` | bool | (absent) | `main_window.gd` |
| `folders` | `<space_id>` | String | `""` | `guild_icon.gd` space folder dialog |
| `folder_colors` | `<space_id>` | Color | `Color(0.212, 0.224, 0.247)` | `guild_icon.gd` |
| `collapsed_<space_id>` | `<category_id>` | bool | `false` | `category_item.gd` |
| `emoji` | `recent` | Array | `[]` | `emoji_picker.gd` |
| `updates` | `auto_check` | bool | `true` | Settings |
| `updates` | `skipped_version` | String | `""` | Update dialog |
| `updates` | `last_check_timestamp` | int | `0` | Auto-update check |
| `idle` | `timeout` | int | `300` | Settings > Notifications |

### Encryption and loading

On startup, Config resolves the active profile's path from the registry, then attempts `load_encrypted_pass()` with a derived key. If that fails, it falls back to a plaintext `load()` -- this supports first-run (no file) and migration from unencrypted configs. If the plaintext load succeeds, the file is immediately re-saved encrypted. If both fail, the corrupted file is backed up and `_config` starts fresh.

The encryption key is derived from a static salt concatenated with `OS.get_user_data_dir()`. This means the key is stable across sessions **as long as the Godot version and project name stay the same**.

### Profile path resolution

`Config` gains a `_profile_slug` variable set during `_ready()` or `switch_profile()`. All file operations use the resolved path via `_profile_config_path()` and `_profile_emoji_cache_dir()`. All existing callers that reference emoji cache paths are updated to go through `Config` instead of hardcoding a path.

### Migration from pre-profile installations

On startup, if `user://profile_registry.cfg` does not exist:

1. Check for `user://config.cfg` (legacy location).
2. If found: create `user://profiles/default/`, move `config.cfg` and `emoji_cache/` into it, write the registry.
3. If not found: create `user://profiles/default/` with an empty config, write the registry.

The migration is atomic in intent -- if the move fails partway, the next launch retries (checks both old and new locations). The legacy `config.cfg.bak` is left in place (not moved) as a safety net.

### Server credential storage

When a server is added, the base URL, auth token, space name, and optionally username are stored in sections `server_0`, `server_1`, etc. The `servers` section tracks the count. **Passwords are never stored.** When a token expires, the re-authentication dialog is shown with the username pre-filled so the user can re-enter their password. A migration (`_migrate_clear_passwords()`) runs on config load to erase any password keys left by older versions.

### Server removal and index shifting

`remove_server()` shifts all subsequent server sections down to fill the gap and erases the last section. This renumbers all connections, so `Client.disconnect_server()` also rebuilds `_space_to_conn` after removing the config entry.

### Session restore

On startup, after the first `spaces_updated` signal fires, `sidebar._on_spaces_updated()` reads `Config.get_last_selection()` and attempts to restore the previously-viewed space and channel. If the saved space no longer exists, it falls back to the first space.

Separately, `Client.connect_server()` restores the saved user status: if the user's last status was not ONLINE, it calls `update_presence()` to broadcast the saved status to all servers.

### Profile switch sequence

Switching profiles is a disruptive operation -- the app effectively "restarts" without quitting:

1. **Disconnect**: `Client.disconnect_all()` closes all WebSocket connections, clears `_connections`, `_space_to_conn`, and all cached data (spaces, channels, users, messages, emoji textures).
2. **Reload config**: `Config.switch_profile(slug)` updates the registry, loads the new profile's `config.cfg`, and emits `AppState.profile_switched`.
3. **Reconnect**: `Client._on_profile_switched()` runs the same logic as `_ready()` -- checks `has_servers()`, calls `connect_server()` for each, etc.
4. **UI reset**: Components listening to `profile_switched` clear their state. `spaces_updated` then fires as servers reconnect, triggering the normal startup selection flow.

### Default profile protection

The "Default" profile (slug `"default"`) has special rules:
- Cannot be deleted (UI hides/disables the delete option).
- Can be renamed (the slug stays `"default"`, only the display name changes).
- Can have a password set like any other profile.

### Voice/video settings

The Voice & Video settings page enumerates available devices via Godot's `AudioServer.get_input_device_list()` and `AudioServer.get_output_device_list()`. Each dropdown pre-selects the device stored in Config. Changes save immediately.

Video resolution offers three hardcoded presets: 480p (index 0), 720p (index 1), 1080p (index 2). FPS choices are 15, 30, and 60.

### Sound settings (user_settings.gd -- Sound page)

The Sound page (page 3) in User Settings lists sound events with per-event checkboxes. Volume is a slider with percentage display. All values are read from Config on page load and written back on change.

### Recently used emoji

`add_recent_emoji()` maintains a most-recently-used list capped at 16 entries. Duplicates are moved to the front. The emoji picker reads this on open to show a "Recent" category.

### Custom emoji cache

Custom space emoji are downloaded and cached as PNG files in `user://profiles/<slug>/emoji_cache/<emoji_id>.png` (per-profile). This is a write-once disk cache -- emoji are checked on disk before downloading. Each profile has its own emoji cache directory so switching profiles and connecting to different servers won't have stale emoji from other profiles' servers.

### Notification preferences

`suppress_everyone` and per-server mute (`muted_servers`) preferences are stored in Config with UI in the Settings > Notifications page and the user bar menu's "Suppress @everyone" toggle.

### Category collapse state

Each category tracks its collapsed state in a per-space Config section `collapsed_<space_id>`. On toggle, the state is saved. On channel list load, `restore_collapse_state()` reads the saved state.

### Export / import as profile operations

The existing `export_config()` and `import_config()` methods are preserved but reframed in the UI:

- **Export Profile**: Calls `Config.export_config(path)` on the active profile. The file extension is `.daccord-profile` (a plaintext `ConfigFile`). **Secrets (tokens and passwords) are stripped** from server sections before writing — the export only contains preferences, server URLs, space names, and usernames.
- **Import Profile**: Creates a new profile, strips any leftover password keys from the imported data, then saves the config encrypted with `save_encrypted_pass()`. The user is prompted for a profile name before import.

### Password hashing

Profile passwords are hashed with SHA-256 using a salt derived from the profile slug + a static salt (`"daccord-profile-v1"`). The hash is stored as a hex string in the registry.

```
hash = SHA256("daccord-profile-v1" + slug + password).hex_encode()
```

GDScript provides `HashingContext` with `HASH_SHA256` for this.

### Slug generation

Profile slugs are derived from the display name: lowercased, spaces replaced with hyphens, non-alphanumeric characters stripped, truncated to 32 characters. If a slug collision occurs, a numeric suffix is appended (`-2`, `-3`, etc.). The slug is immutable after creation -- renaming a profile only changes the display name in the registry.

### Command-line profile selection

For power users and automation, daccord accepts a `--profile <slug>` command-line argument that overrides the registry's `active` field for that session. The registry is not updated (so the next normal launch still uses the previously active profile). This is useful for launching multiple instances with different profiles.

## Local Data Summary

All user data resides under `user://` (typically `~/.local/share/godot/app_userdata/daccord/`):

| Path | Contents | Managed by |
|------|----------|------------|
| `profile_registry.cfg` | Profile names, active profile slug, password hashes, display order (unencrypted) | `Config` autoload |
| `profiles/default/config.cfg` | Default profile: preferences, server credentials, UI state (encrypted) | `Config` autoload |
| `profiles/default/emoji_cache/<id>.png` | Default profile: downloaded custom emoji images | `Client.register_custom_emoji()` |
| `profiles/<slug>/config.cfg` | Additional profile: preferences, server credentials, UI state (encrypted) | `Config` autoload |
| `profiles/<slug>/emoji_cache/<id>.png` | Additional profile: downloaded custom emoji images | `Client.register_custom_emoji()` |
| `logs/godot.log` | Godot engine log (created by engine) | Engine |

Legacy paths (pre-profile migration):

| Path | Contents | Notes |
|------|----------|-------|
| `config.cfg` | All preferences (old location) | Moved to `profiles/default/config.cfg` on first launch after upgrade |
| `config.cfg.bak` | Backup of old config | Left in place as safety net during migration |
| `emoji_cache/<id>.png` | Emoji images (old location) | Moved to `profiles/default/emoji_cache/` on first launch after upgrade |

## Implementation Status

- [x] Encrypted config file with plaintext migration fallback
- [x] Server connection storage (URL, token, space name, username)
- [x] Server removal with index shifting
- [x] Session restore (last space + channel selection)
- [x] User status persistence across sessions
- [x] Custom status text persistence
- [x] Voice device preferences (mic, speaker, camera)
- [x] Video resolution and FPS preferences
- [x] SFX volume and per-event sound toggles
- [x] Error reporting opt-in with first-launch consent
- [x] Space folder assignments and colors
- [x] Category collapse state per space
- [x] Recently used emoji (16 max)
- [x] Custom emoji disk cache
- [x] Notification preference storage (suppress @everyone, server mute)
- [x] UI for notification preferences (suppress @everyone, server mute)
- [x] Config load-failure guard (prevent save from overwriting unreadable file)
- [x] Config export/import
- [x] Config backup before overwrite
- [x] Emit `server_connection_failed` on initial auth failure
- [x] Token-only re-auth signal (`reauth_needed`) with auth dialog and username pre-fill
- [x] Password removal from config storage with migration for existing configs
- [x] Sanitized exports (no tokens or passwords in exported files)
- [x] Encrypted import saving (imported profiles saved with `save_encrypted_pass`)
- [x] Profile registry file (`user://profile_registry.cfg`)
- [x] Migration from legacy `user://config.cfg` to `user://profiles/default/`
- [x] Default profile auto-creation on fresh install
- [x] `Config._profile_config_path()` dynamic path resolution
- [x] Per-profile emoji cache directory
- [x] `Config.create_profile(name, password, copy_current)`
- [x] `Config.delete_profile(slug)`
- [x] `Config.switch_profile(slug)`
- [x] `Config.rename_profile(slug, new_name)`
- [x] `Config.set_profile_password(slug, old_password, new_password)`
- [x] `Config.verify_profile_password(slug, password) -> bool`
- [x] `Config.get_profiles() -> Array`
- [x] `Config.get_active_profile_slug() -> String`
- [x] `AppState.profile_switched` signal
- [x] `Client.disconnect_all()` method
- [x] `Client._on_profile_switched()` reset and reconnect handler
- [x] Profiles section in user settings UI
- [x] Create Profile dialog (name, password, copy/fresh)
- [x] Profile password entry dialog
- [x] Profile context menu (Rename, Delete, Set Password, Export)
- [x] Import Profile flow (file picker + name dialog)
- [x] Export Profile with `.daccord-profile` extension
- [x] UI rename of "config" to "profile" in export/import labels
- [ ] `--profile <slug>` command-line argument
- [ ] Profile list ordering (drag-to-reorder or manual up/down)

## Tasks

### USRCFG-1: Encryption key tied to `OS.get_user_data_dir()`
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, security
- **Notes:** The key derivation depends on Godot's user data directory path. If the project name changes in `project.godot` or the user data dir convention changes between Godot versions, old config files become unreadable.

### USRCFG-2: No emoji cache eviction
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** emoji, performance
- **Notes:** Per-profile `emoji_cache/` directories grow unboundedly as custom emoji are encountered. No max-size or LRU eviction is implemented.

### USRCFG-3: Emoji cache duplication across profiles
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** emoji, performance
- **Notes:** Profiles connecting to the same server will each download and store the same custom emoji. A shared cache with refcounting would save disk space but adds complexity. Not worth it unless storage becomes a concern.

### USRCFG-4: Video resolution presets are hardcoded
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** video, voice
- **Notes:** Resolution options (480p, 720p, 1080p) and FPS options (15, 30, 60) are defined as literals rather than being data-driven or coming from LiveKit capabilities.

### USRCFG-5: `save()` called on every individual setter
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** api, audio, ci, config, security
- **Notes:** Each `Config.set_*()` calls `save_encrypted_pass()` immediately. Rapid successive changes (e.g., applying all sound settings) trigger multiple disk writes. A deferred/batched save would be more efficient.

### USRCFG-6: SHA-256 is fast to brute-force
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** security
- **Notes:** Profile passwords are a convenience lock, not a security boundary. All data is on the local filesystem and accessible to anyone with disk access. SHA-256 with a salt is adequate for this threat model.

### USRCFG-7: No profile lock-on-idle
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** security
- **Notes:** Once a password-protected profile is unlocked, it stays unlocked for the session. No idle timeout that re-locks the profile.

### USRCFG-8: No multi-instance guard
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** config, gateway
- **Notes:** Two daccord instances could run with the same profile simultaneously, causing config write conflicts. A lockfile would prevent this but isn't planned for v1.
