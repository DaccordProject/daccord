# Profiles

Last touched: 2026-02-19

## Overview

Profiles allow multiple people (or the same person with different server setups) to share a single daccord installation. Each profile is an independent config file containing its own server connections, preferences, UI state, and emoji cache. Profiles are optionally password-protected. The app ships with a "Default" profile that is automatically active, so single-user installations work exactly as before with zero friction.

The user-facing term for what was previously called "config" is now **profile**. Export/import operations are framed as "Export Profile" / "Import Profile" so users understand they are portable, self-contained bundles of their settings.

## Concepts

| Term | Meaning |
|------|---------|
| **Profile** | A named collection of all user data: server connections, preferences, UI state, emoji cache. Stored as a directory under `user://profiles/<slug>/`. |
| **Active profile** | The profile currently loaded into the `Config` autoload. Only one profile is active at a time. |
| **Default profile** | The profile created on first launch (name: "Default", slug: `default`). Cannot be deleted, only renamed. |
| **Profile registry** | A small unencrypted `ConfigFile` at `user://profile_registry.cfg` that tracks all profile names, the active profile slug, and optional password hashes. |
| **Profile password** | An optional password that must be entered before switching to a protected profile. Stored as a SHA-256 hash in the registry. |

## User Steps

### First launch (no profiles exist)

1. User opens daccord for the first time.
2. `Config._ready()` detects no `user://profile_registry.cfg`.
3. A "Default" profile is created: `user://profiles/default/` directory, empty `config.cfg` inside.
4. Registry is written with `active = "default"` and one profile entry.
5. App proceeds normally -- the user never sees any profile UI unless they look for it.

### Upgrade from pre-profile version

1. User launches an updated daccord that has profile support.
2. `Config._ready()` detects no `user://profile_registry.cfg` but finds an existing `user://config.cfg`.
3. Migration runs:
   a. Creates `user://profiles/default/` directory.
   b. Moves `user://config.cfg` to `user://profiles/default/config.cfg`.
   c. Moves `user://emoji_cache/` to `user://profiles/default/emoji_cache/` (if it exists).
   d. Writes `user://profile_registry.cfg` with `active = "default"`.
4. App loads normally from the new location. The user's existing data is preserved.

### Viewing profiles

1. User opens Settings (gear icon in user bar or user bar menu).
2. A "Profiles" section is visible at the top of settings.
3. The current profile name is displayed with a dropdown or list showing all profiles.
4. Each profile entry shows: name, whether it's password-protected (lock icon), and a badge if it's the active one.

### Creating a new profile

1. User clicks "New Profile" button in the Profiles section.
2. A dialog appears with:
   - **Name** text field (required, max 32 characters, alphanumeric + spaces + hyphens).
   - **Password** field (optional). If left blank, the profile has no password.
   - **Confirm Password** field (shown only if password is non-empty).
   - "Start from scratch" / "Copy current profile" radio buttons.
3. User fills in the name, optionally sets a password, picks a starting point, and clicks "Create".
4. The profile directory is created: `user://profiles/<slug>/config.cfg`.
   - If "Copy current profile" was selected, the active profile's `config.cfg` and `emoji_cache/` are copied.
   - If "Start from scratch", an empty `config.cfg` is created.
5. The registry is updated with the new profile entry (and password hash if set).
6. The user is **not** automatically switched to the new profile -- they stay on the current one.

### Switching profiles

1. User clicks a different profile in the Profiles list.
2. **If the target profile has a password:** a password dialog appears. User enters the password and clicks "Unlock".
   - On wrong password: error message, stays on current profile.
   - On correct password: proceeds.
3. **If no password:** proceeds immediately.
4. The app performs a profile switch:
   a. All active server connections are disconnected (`Client.disconnect_all()`).
   b. `Config` reloads from the target profile's `config.cfg`.
   c. The registry's `active` field is updated.
   d. `Client._ready()`-equivalent logic runs: auto-connect saved servers, restore session.
5. The UI resets as if the app was freshly launched -- sidebar rebuilds, messages clear, then repopulate from the new profile's servers.

### Renaming a profile

1. User right-clicks (or clicks a menu icon on) a profile entry and selects "Rename".
2. A text input appears with the current name pre-filled.
3. User types a new name and presses Enter or clicks "Save".
4. The registry updates the display name. The on-disk slug does **not** change (avoids file moves and race conditions).

### Deleting a profile

1. User right-clicks a profile and selects "Delete".
2. **The Default profile cannot be deleted.** The option is grayed out / hidden for it.
3. A confirmation dialog appears: "Delete profile '[name]'? This will permanently remove all its server connections and settings. This cannot be undone."
4. **If the profile being deleted is the active one:** the app switches to Default first (following the switch flow above), then deletes.
5. The profile's directory (`user://profiles/<slug>/`) is recursively deleted.
6. The registry entry is removed.

### Setting or changing a profile password

1. User right-clicks a profile and selects "Set Password" (or "Change Password" if one exists).
2. **If a password already exists:** user must enter the current password first.
3. A dialog with "New Password" and "Confirm Password" fields appears.
4. User enters a password and clicks "Save". The SHA-256 hash is stored in the registry.
5. To **remove** a password: the dialog has a "Remove Password" button (requires entering the current password).

### Exporting a profile

1. User right-clicks a profile and selects "Export Profile" (or uses the existing export menu item).
2. A native file-save dialog opens, defaulting to `<profile-name>.daccord-profile`.
3. The profile's `config.cfg` is saved as a plaintext `ConfigFile` to the chosen path (same as current `export_config()`).
4. Emoji cache is **not** included in the export (it can be re-downloaded). This keeps exports small.

### Importing a profile

1. User clicks "Import Profile" in the Profiles section.
2. A native file-open dialog opens, filtering for `.daccord-profile` files.
3. A dialog asks for a profile name (pre-filled from the file name) and optional password.
4. A new profile is created with the imported config data.
5. The user can then switch to the imported profile.

## Signal Flow

```
=== PROFILE SWITCH ===

User clicks target profile in Profiles UI
    |
    v
[Has password?] --yes--> PasswordDialog shown
    |                         |
    no                        v
    |                     User enters password
    |                         |
    |                     SHA-256(input) == stored hash?
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
    |   _config.load_encrypted_pass(new_profile_path, key)
    |   _load_ok = true
    |
    +-> AppState.profile_switched.emit()
    |
    v
Client._on_profile_switched()
    |
    +-> clear all in-memory state (guilds, channels, users, messages)
    +-> Config.has_servers()? --yes--> connect_server(i) for each
    |                            |
    |                            v
    |                        normal startup flow (auth, guild match, gateway)
    |                            |
    |                            v
    |                        AppState.guilds_updated.emit()
    |
    +-> no servers: stay in CONNECTING mode (empty UI)


=== MIGRATION FROM PRE-PROFILE ===

Config._ready()
    |
    +-> FileAccess.file_exists(REGISTRY_PATH)?
    |       |
    |       yes: load registry, read active slug, set config path
    |       |
    |       no: first-time profile setup
    |           |
    |           +-> FileAccess.file_exists("user://config.cfg")?
    |               |
    |               yes: MIGRATION
    |               |   DirAccess.make_dir_recursive("user://profiles/default/")
    |               |   DirAccess.rename("user://config.cfg",
    |               |       "user://profiles/default/config.cfg")
    |               |   DirAccess.rename("user://emoji_cache/",
    |               |       "user://profiles/default/emoji_cache/")
    |               |   write registry with active = "default"
    |               |
    |               no: FRESH INSTALL
    |                   DirAccess.make_dir_recursive("user://profiles/default/")
    |                   write registry with active = "default"
    |
    v
Load config from user://profiles/<active>/config.cfg
(rest of _ready() proceeds as before)


=== PROFILE CREATE ===

User clicks "New Profile", fills dialog, clicks "Create"
    |
    v
_slugify(name) -> slug  (lowercase, spaces to hyphens, strip special chars)
    |
    v
DirAccess.make_dir_recursive("user://profiles/<slug>/")
    |
    +-> [Copy current?] --yes--> DirAccess.copy(current config.cfg -> new config.cfg)
    |                            DirAccess.copy(current emoji_cache/ -> new emoji_cache/)
    |
    +-> [Start fresh?] --> write empty config.cfg
    |
    v
registry.set_value("profiles", slug, name)
[has password?] -> registry.set_value("passwords", slug, sha256_hash)
registry.save(REGISTRY_PATH)
    |
    v
Profiles UI refreshes to show new entry
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/config.gd` | Extended with profile awareness: registry management, `switch_profile()`, `create_profile()`, `delete_profile()`, migration logic |
| `scripts/autoload/app_state.gd` | New signal: `profile_switched` |
| `scripts/autoload/client.gd` | `disconnect_all()` method, `_on_profile_switched()` handler to reset state and reconnect |
| `scenes/user/user_settings.gd` | Profiles section in settings UI |
| `scenes/user/profile_dialog.gd` | Create / edit profile dialog (name, password, copy vs fresh) |
| `scenes/user/profile_password_dialog.gd` | Password entry dialog for switching to protected profiles |

## Implementation Details

### File layout on disk

```
user://
  profile_registry.cfg          # unencrypted, tracks profiles + active + password hashes
  profiles/
    default/
      config.cfg                # encrypted (same format as before)
      emoji_cache/
        <id>.png
    work/
      config.cfg
      emoji_cache/
    family/
      config.cfg
      emoji_cache/
```

### Profile registry format

The registry is a plain (unencrypted) `ConfigFile` at `user://profile_registry.cfg`:

| Section | Key(s) | Type | Description |
|---------|--------|------|-------------|
| `state` | `active` | String | Slug of the currently active profile (e.g. `"default"`) |
| `profiles` | `<slug>` | String | Display name for each profile (e.g. `"default"` -> `"Default"`) |
| `passwords` | `<slug>` | String | SHA-256 hex digest of the profile's password (absent if no password) |
| `order` | `list` | Array | Ordered array of slugs for display ordering |

The registry is unencrypted because it contains no sensitive data (password hashes are one-way, profile names aren't secret). The actual credentials live inside each profile's encrypted `config.cfg`.

### Slug generation

Profile slugs are derived from the display name: lowercased, spaces replaced with hyphens, non-alphanumeric characters stripped, truncated to 32 characters. If a slug collision occurs, a numeric suffix is appended (`-2`, `-3`, etc.). The slug is immutable after creation -- renaming a profile only changes the display name in the registry.

### Password hashing

Passwords are hashed with SHA-256 using a salt derived from the profile slug + a static salt (`"daccord-profile-v1"`). The hash is stored as a hex string in the registry. On verification, the same salt+hash is computed and compared.

```
hash = SHA256("daccord-profile-v1" + slug + password).hex_encode()
```

GDScript provides `HashingContext` with `HASH_SHA256` for this.

### Config path resolution

`Config` gains a `_profile_slug` variable set during `_ready()` or `switch_profile()`. All file operations use the resolved path:

```gdscript
func _profile_config_path() -> String:
    return "user://profiles/%s/config.cfg" % _profile_slug

func _profile_emoji_cache_dir() -> String:
    return "user://profiles/%s/emoji_cache" % _profile_slug
```

The `CONFIG_PATH` constant is replaced by these dynamic methods. All existing callers that reference emoji cache paths are updated to go through `Config` instead of hardcoding `user://emoji_cache/`.

### Profile switch sequence

Switching profiles is a disruptive operation -- the app effectively "restarts" without quitting:

1. **Disconnect**: `Client.disconnect_all()` closes all WebSocket connections, clears `_connections`, `_guild_to_conn`, and all cached data (guilds, channels, users, messages, emoji textures).
2. **Reload config**: `Config.switch_profile(slug)` updates the registry, loads the new profile's `config.cfg`, and emits `AppState.profile_switched`.
3. **Reconnect**: `Client._on_profile_switched()` runs the same logic as `_ready()` -- checks `has_servers()`, calls `connect_server()` for each, etc.
4. **UI reset**: Components listening to `profile_switched` clear their state. `guilds_updated` then fires as servers reconnect, triggering the normal startup selection flow.

### Default profile protection

The "Default" profile (slug `"default"`) has special rules:
- Cannot be deleted (UI hides/disables the delete option).
- Can be renamed (the slug stays `"default"`, only the display name changes).
- Can have a password set like any other profile.

### Migration from pre-profile installations

On startup, if `user://profile_registry.cfg` does not exist:

1. Check for `user://config.cfg` (legacy location).
2. If found: create `user://profiles/default/`, move `config.cfg` and `emoji_cache/` into it, write the registry.
3. If not found: create `user://profiles/default/` with an empty config, write the registry.

The migration is atomic in intent -- if the move fails partway, the next launch retries (checks both old and new locations). The legacy `config.cfg.bak` is left in place (not moved) as a safety net.

### Export / import as profile operations

The existing `export_config()` and `import_config()` methods are preserved but reframed in the UI:

- **Export Profile**: Calls `Config.export_config(path)` on the active profile. The file extension is `.daccord-profile` (a plaintext `ConfigFile`). Credentials are included in the export since the user explicitly chose to export.
- **Import Profile**: Creates a new profile, then calls `Config.import_config(path)` to load the data into it. The user is prompted for a profile name before import.

### Emoji cache per profile

Each profile has its own `emoji_cache/` directory. This means switching profiles and connecting to different servers won't have stale emoji from other profiles' servers. The tradeoff is duplicate storage if two profiles connect to the same server, but emoji files are small (typically <50KB each) and this keeps profiles fully isolated.

### Command-line profile selection

For power users and automation, daccord accepts a `--profile <slug>` command-line argument that overrides the registry's `active` field for that session. The registry is not updated (so the next normal launch still uses the previously active profile). This is useful for launching multiple instances with different profiles.

## Implementation Status

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
- [x] `Config.get_profiles() -> Array` (returns list of {slug, name, has_password})
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
- [x] `--profile <slug>` command-line argument
- [x] Profile list ordering (drag-to-reorder or manual up/down)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| SHA-256 is fast to brute-force | Low | Profile passwords are a convenience lock, not a security boundary. All data is on the local filesystem and accessible to anyone with disk access. SHA-256 with a salt is adequate for this threat model. If stronger protection is wanted later, switch to a KDF like scrypt or Argon2 (no GDScript built-in, would need GDExtension). |
| No profile lock-on-idle | Low | Once a password-protected profile is unlocked, it stays unlocked for the session. There's no idle timeout that re-locks the profile. Could be added later with a timer that emits a lock signal. |
| Export includes credentials in plaintext | Medium | `export_config()` saves the `ConfigFile` in plaintext, including server tokens and passwords. The user is exporting intentionally, but a warning dialog before export ("This file will contain your server credentials") would be prudent. |
| No multi-instance guard | Low | Two daccord instances could run with the same profile simultaneously, causing config write conflicts. A lockfile (`user://profiles/<slug>/.lock`) would prevent this but isn't planned for v1. |
| Emoji cache duplication across profiles | Low | Profiles connecting to the same server will each download and store the same custom emoji. A shared cache with refcounting would save disk space but adds complexity. Not worth it unless storage becomes a concern. |
| No profile icon/avatar | Low | Profiles are identified only by name. A small color dot or user-chosen icon would make switching faster visually. |
