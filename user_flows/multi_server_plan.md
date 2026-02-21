# Multi-Server Support Plan

## Current State

- `AccordClient` is already per-instance: each instance has its own `base_url`, `gateway_url`, and `token`. Creating multiple `AccordClient` instances for multiple servers is already possible.
- `AccordCDN` is **static** — `base_url` is a class-level variable. All CDN URL builders (`avatar()`, `space_icon()`, etc.) use this single shared base. This breaks with multiple servers since each server has its own CDN endpoint.
- daccord's `Client` singleton manages a single `AccordClient` instance, a single token, and a single set of caches.
- daccord's `Config` singleton stores a single server's credentials.

## Target State

Users configure multiple server connections via the "Add a Server" dialog. Each entry is: `host:port` + `guild name` (lowercase, URL-safe) + `token`. The app connects to all configured servers at startup. The guild bar aggregates guilds from all connected servers.

---

## AccordKit Changes

### 1. Make `AccordCDN` instance-aware

**File:** `addons/accordkit/utils/cdn.gd`

The static `base_url` pattern cannot support multiple servers. Two options:

**Option A — Add `base_url` parameter to every static method (minimal change):**

```gdscript
# Before
static func avatar(user_id: String, hash: String, format: String = "png") -> String:
    return base_url + "/avatars/" + user_id + "/" + hash + "." + format

# After — base_url param with fallback to static default
static func avatar(user_id: String, hash: String, format: String = "png", cdn_url: String = "") -> String:
    var url := cdn_url if not cdn_url.is_empty() else base_url
    return url + "/avatars/" + user_id + "/" + hash + "." + format
```

Apply to: `avatar()`, `default_avatar()`, `space_icon()`, `space_banner()`, `emoji()`, `attachment()`.

**Option B — Add a `cdn_url` property to `AccordClient` (cleaner):**

Add `cdn_url: String` to `AccordClient` and `AccordConfig`, derived from `base_url + "/cdn"` by default. Then callers pass it explicitly when building URLs. The static `AccordCDN` methods get the extra parameter as in Option A.

**Recommendation:** Option A is simpler and backward-compatible. The static default still works for single-server use.

### 2. Add `cdn_url` property to `AccordConfig` and `AccordClient`

**File:** `addons/accordkit/core/accord_config.gd`

```gdscript
# Add to AccordConfig
var cdn_url: String = DEFAULT_CDN_URL
```

**File:** `addons/accordkit/core/accord_client.gd`

```gdscript
# Add export
@export var cdn_url: String = AccordConfig.DEFAULT_CDN_URL

# In _ready(), pass to config:
config.cdn_url = cdn_url
```

This way each `AccordClient` instance knows its own CDN URL, and callers can pass `client.cdn_url` to `AccordCDN` methods.

### 3. No other AccordKit changes needed

`AccordClient` already supports per-instance `base_url`, `gateway_url`, and `token`. Multiple instances already work independently. Gateway, REST, models — all instance-scoped.

---

## daccord Changes

### 4. Redesign `Config` (`scripts/autoload/config.gd`)

Replace single-credential storage with a list of server entries.

**Config file format (`user://config.cfg`):**

```ini
[servers]
count=2

[server_0]
base_url=http://example.com:3000
token=abc123
guild_name=my-guild

[server_1]
base_url=http://other.com:3000
token=xyz789
guild_name=cool-guild
```

**API:**

```gdscript
# Each server entry is a Dictionary:
# { "base_url": String, "token": String, "guild_name": String }

func get_servers() -> Array[Dictionary]
func add_server(base_url: String, token: String, guild_name: String) -> void
func remove_server(index: int) -> void
func save() -> void
func has_servers() -> bool
```

### 5. Redesign `Client` (`scripts/autoload/client.gd`)

Manage multiple `AccordClient` instances, one per configured server.

**New structure:**

```gdscript
# Per-server connection state
var _connections: Array = []
# Each entry: {
#   "config": Dictionary,         # { base_url, token, guild_name }
#   "client": AccordClient,       # the AccordClient instance
#   "guild_id": String,           # resolved guild ID (from guild_name)
#   "cdn_url": String,            # base_url + "/cdn"
#   "status": String,             # "connecting", "connected", "error"
# }
```

**Startup flow:**

```
_ready():
  for each server in Config.get_servers():
    _connect_server(server)

_connect_server(server_config):
  1. Create AccordClient with server_config.base_url, token
  2. Add as child
  3. Call get_me() to authenticate
  4. Call list_spaces() to find the guild matching guild_name
  5. If found, store the guild_id
  6. Connect gateway signals (scoped to this server's client)
  7. Call client.login()
  8. On gateway ready, fetch channels + messages for just that guild
```

**Data access changes:**

The `guilds` property now returns aggregated guilds across all connections. Each guild dict gets a `"_server_index"` (or `"_connection"`) field so the rest of the app knows which `AccordClient` to use for API calls against that guild.

```gdscript
var guilds: Array:
    get:
        if _connections.is_empty():
            return MockData.guilds
        var result: Array = []
        for conn in _connections:
            if conn.status == "connected":
                result.append(_guild_cache[conn.guild_id])
        return result
```

API calls (`send_message`, `fetch_channels`, etc.) need to route to the correct `AccordClient` based on which server owns the channel/guild:

```gdscript
func _client_for_guild(guild_id: String) -> AccordClient:
    for conn in _connections:
        if conn.guild_id == guild_id:
            return conn.client
    return null

func _client_for_channel(channel_id: String) -> AccordClient:
    var ch := _channel_cache.get(channel_id, {})
    return _client_for_guild(ch.get("guild_id", ""))
```

**CDN URL routing:**

`ClientModels` functions need to receive the CDN URL for the relevant server. Add a `cdn_url` parameter to conversion functions, or store it alongside the cached data.

### 6. Update `ClientModels` (`scripts/autoload/client_models.gd`)

Add `cdn_url` parameter to functions that build CDN URLs:

```gdscript
# Before
static func user_to_dict(user: AccordUser, status: int = ...) -> Dictionary:
    ...
    avatar_url = AccordCDN.avatar(user.id, str(user.avatar))

# After
static func user_to_dict(user: AccordUser, status: int = ..., cdn_url: String = "") -> Dictionary:
    ...
    avatar_url = AccordCDN.avatar(user.id, str(user.avatar), "png", cdn_url)
```

### 7. Update `add_server_dialog` (`scenes/sidebar/guild_bar/add_server_dialog.gd`)

Replace current Join/Create dual-mode with a single "Add Server" form:

**Fields:**
- Server URL (LineEdit, placeholder: `http://host:port`)
- Guild Name (LineEdit, placeholder: `guild-name`, lowercase/URL-safe)
- Token (LineEdit, placeholder: `Token`, secret=true)

**Flow:**
1. User fills in all three fields
2. "Add" button validates inputs (non-empty, guild name is URL-safe)
3. Saves to Config
4. Calls `Client.connect_server(...)` to connect immediately
5. On success: closes dialog, guild appears in sidebar
6. On error (bad token, guild not found): shows error in dialog

Remove the "Create" mode — creating servers is a server-admin operation, not an in-app feature in this model.

### 8. Remove the settings dialog

The settings dialog (`scenes/settings/settings_dialog.gd` + `.tscn`) created earlier should be removed. Server management is handled entirely through Add Server. To disconnect/remove a server, add a right-click context menu or option on guild icons in the guild bar.

### 9. Update `guild_bar` (`scenes/sidebar/guild_bar/guild_bar.gd`)

- Guild icons now represent individual server connections (one guild per server entry)
- Right-click on a guild icon could offer "Remove Server" (removes from Config, disconnects)
- No folder grouping changes needed — folders can still group guilds from different servers

### 10. Update `project.godot`

Config autoload order: `MockData → AppState → Config → Client` (already correct from previous work).

### 11. Mock mode

If `Config.get_servers()` is empty, fall back to mock mode using `MockData` (same as current behavior). As soon as at least one server is added, switch to live mode for that server while mock data can be cleared or kept for unconnected slots.

---

## Gateway URL Convention

The gateway URL can be derived from the base URL: if the user provides `http://host:port`, the gateway URL is `ws://host:port/gateway` (or `wss://` for `https://`). This avoids making the user specify it separately.

```gdscript
func _derive_gateway_url(base_url: String) -> String:
    var gw := base_url.replace("https://", "wss://").replace("http://", "ws://")
    return gw + "/gateway"
```

---

## CDN URL Convention

Similarly derived: `base_url + "/cdn"`.

---

## File Summary

| File | Action |
|------|--------|
| `accordkit: utils/cdn.gd` | Add optional `cdn_url` param to all static methods |
| `accordkit: core/accord_config.gd` | Add `cdn_url` property |
| `accordkit: core/accord_client.gd` | Add `cdn_url` export, pass to config |
| `daccord: scripts/autoload/config.gd` | Rewrite for multi-server storage |
| `daccord: scripts/autoload/client.gd` | Rewrite for multi-connection management |
| `daccord: scripts/autoload/client_models.gd` | Add `cdn_url` parameter to model converters |
| `daccord: scenes/sidebar/guild_bar/add_server_dialog.gd` | Replace with Add Server form |
| `daccord: scenes/sidebar/guild_bar/guild_bar.gd` | Minor: handle server removal context menu |
| `daccord: scenes/sidebar/user_bar.gd` | Remove Settings menu item (added earlier) |
| `daccord: scenes/settings/` | Delete (no longer needed) |
| `daccord: project.godot` | Remove Config autoload if not needed, or keep for multi-server config |

## Order of Implementation

1. AccordKit CDN changes (backward-compatible, can land first)
2. AccordKit client `cdn_url` property
3. daccord `Config` rewrite
4. daccord `Client` rewrite (biggest change)
5. daccord `ClientModels` cdn_url threading
6. daccord `add_server_dialog` redesign
7. daccord cleanup (remove settings dialog, update user_bar)
