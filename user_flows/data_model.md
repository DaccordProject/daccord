# Data Model

## Overview

daccord uses a dictionary-based data model as the contract between the network layer (AccordKit) and the UI. `ClientModels` converts AccordKit typed models (AccordUser, AccordSpace, AccordChannel, AccordMessage) into dictionary shapes that UI components consume via their `setup(data: Dictionary)` methods. `Client` maintains five in-memory caches (users, guilds, channels, DM channels, messages) populated from REST fetches and kept current via gateway events.

## Data Flow

```
AccordServer (REST/Gateway)
    -> AccordKit typed models (AccordUser, AccordSpace, AccordChannel, AccordMessage)
    -> ClientModels static conversion functions
    -> Dictionary shapes (the data contract)
    -> Client caches (in-memory dictionaries)
    -> UI components via setup(data: Dictionary)
```

## Signal Flow

1. **REST fetch** (e.g., `fetch_guilds()`) returns AccordKit typed models
2. `ClientModels` converts each model to a dictionary via `space_to_guild_dict()`, `channel_to_dict()`, `message_to_dict()`, etc.
3. Dictionaries are stored in the appropriate `Client` cache (`_guild_cache`, `_channel_cache`, `_message_cache`, etc.)
4. `Client` emits an `AppState` signal (`guilds_updated`, `channels_updated`, `messages_updated`, etc.)
5. UI components receive the signal, read from `Client`'s data access API, and call `setup(data)` with the dictionary
6. **Gateway events** (message_create, message_update, message_delete, channel_create, etc.) follow the same path: convert model -> update cache -> emit signal -> UI refreshes

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd` | Static conversion functions, enums (ChannelType, UserStatus), color palette |
| `scripts/autoload/client.gd` | Five caches, data access API, routing to correct server connection |
| `addons/accordkit/models/user.gd` | AccordUser typed model |
| `addons/accordkit/models/space.gd` | AccordSpace typed model |
| `addons/accordkit/models/channel.gd` | AccordChannel typed model |
| `addons/accordkit/models/message.gd` | AccordMessage typed model |
| `addons/accordkit/models/reaction.gd` | AccordReaction typed model |
| `addons/accordkit/models/embed.gd` | AccordEmbed typed model |
| `addons/accordkit/utils/cdn.gd` | CDN URL construction for avatars, icons, etc. |

## Implementation Details

### Enums (client_models.gd)

ChannelType (line 7): `{ TEXT, VOICE, ANNOUNCEMENT, FORUM, CATEGORY }`
UserStatus (line 10): `{ ONLINE, IDLE, DND, OFFLINE }`

### Color Palette (client_models.gd:12-23)

10 HSV colors at S=0.7, V=0.9 with hues: 0.0, 0.08, 0.16, 0.28, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95
- `_color_from_id(id: String)`: Deterministic color assignment via `id.hash() % palette_size`
- Used for user avatars, guild icons, and DM avatars when no image is available

### Dictionary Shapes

**User Dict** (client_models.gd:90-112, `user_to_dict()`):
```
{
    "id": String,
    "display_name": String,  # Falls back to username if null/empty
    "username": String,
    "color": Color,          # Deterministic from _color_from_id(id)
    "status": int,           # UserStatus enum value
    "avatar": String|null,   # CDN URL via AccordCDN.avatar() or null
}
```

**Guild Dict** (client_models.gd:114-122, `space_to_guild_dict()`):
```
{
    "id": String,
    "name": String,
    "icon_color": Color,     # Deterministic from _color_from_id(id)
    "folder": "",            # Always empty string (hardcoded)
    "unread": false,         # Always false (hardcoded)
    "mentions": 0,           # Always 0 (hardcoded)
}
```

**Channel Dict** (client_models.gd:124-148, `channel_to_dict()`):
```
{
    "id": String,
    "guild_id": String,      # From channel.space_id
    "name": String,
    "type": int,             # ChannelType enum value
    "parent_id": String,     # Category parent or ""
    "unread": false,         # Always false (hardcoded)
    "topic": String,         # Optional, only if non-empty
    "nsfw": true,            # Optional, only if channel.nsfw is true
}
```

**Message Dict** (client_models.gd:150-203, `message_to_dict()`):
```
{
    "id": String,
    "channel_id": String,
    "author": Dictionary,    # User dict (from cache or fallback "Unknown")
    "content": String,
    "timestamp": String,     # Formatted as "Today at H:MM AM/PM"
    "reactions": Array,      # [{emoji: String, count: int, active: bool}, ...]
    "reply_to": String,      # Message ID or ""
    "embed": Dictionary,     # {title, description, color, footer} or {}
    "system": bool,          # true if type != "default" and != "reply"
}
```

**DM Channel Dict** (client_models.gd:205-228, `dm_channel_to_dict()`):
```
{
    "id": String,
    "user": Dictionary,      # User dict for first recipient
    "last_message": "",      # Always empty string (hardcoded)
    "unread": false,         # Always false (hardcoded)
}
```

### Timestamp Formatting (client_models.gd:57-88)

- Parses ISO 8601 strings (e.g., "2025-05-10T14:30:00Z")
- Extracts time after "T", strips timezone suffix (Z/+/-), strips milliseconds
- Converts to 12-hour format: "Today at H:MM AM/PM"
- Always says "Today" regardless of actual date
- Returns raw string if unparseable

### Caching Architecture (client.gd)

Five caches:
- `_user_cache: Dictionary` -- keyed by user_id -> user dict
- `_guild_cache: Dictionary` -- keyed by guild_id -> guild dict
- `_channel_cache: Dictionary` -- keyed by channel_id -> channel dict
- `_dm_channel_cache: Dictionary` -- keyed by channel_id -> DM channel dict
- `_message_cache: Dictionary` -- keyed by channel_id -> Array of message dicts

Routing maps:
- `_guild_to_conn: Dictionary` -- guild_id -> connection index (for multi-server)
- `_channel_to_guild: Dictionary` -- channel_id -> guild_id

Cache population:
- On connect: `fetch_guilds()` populates _guild_cache from `GET /users/@me/spaces`
- On guild select: `fetch_channels(guild_id)` populates _channel_cache from `GET /spaces/{id}/channels`
- On DM mode: `fetch_dm_channels()` populates _dm_channel_cache from `GET /users/@me/channels`
- On channel select: `fetch_messages(channel_id)` populates _message_cache from `GET /channels/{id}/messages?limit=50`
- Users cached on-demand when encountered in messages or DM recipients

Cache updates via gateway:
- message_create: appends to _message_cache, enforces MESSAGE_CAP (50) via pop_front()
- message_update: finds and replaces in _message_cache array
- message_delete: finds and removes from _message_cache array
- channel_create/update/delete: updates _channel_cache or _dm_channel_cache based on type
- space_create/update/delete: updates _guild_cache
- presence_update: updates _user_cache[user_id].status

Data access API (client.gd):
- `guilds: Array` -> `_guild_cache.values()` (property)
- `channels: Array` -> `_channel_cache.values()` (property)
- `dm_channels: Array` -> `_dm_channel_cache.values()` (property)
- `get_channels_for_guild(guild_id)` -> filters _channel_cache by guild_id
- `get_messages_for_channel(channel_id)` -> returns from _message_cache or empty array
- `get_user_by_id(user_id)` -> returns from _user_cache or empty dict
- `get_guild_by_id(guild_id)` -> returns from _guild_cache or empty dict
- `get_message_by_id(message_id)` -> linear search across all channels' message arrays

Multi-server routing (client.gd):
- `_client_for_guild(guild_id)` -> looks up _guild_to_conn, returns AccordClient
- `_client_for_channel(channel_id)` -> channel -> guild -> connection
- `_cdn_for_guild(guild_id)` / `_cdn_for_channel(channel_id)` -> CDN URL for correct server

Constants (client.gd:8-15):
- `MESSAGE_CAP := 50` -- max messages cached per channel
- `GUILD_ICON_SIZE := 48`, `AVATAR_SIZE := 42`, `CHANNEL_ICON_SIZE := 32`
- `CHANNEL_PANEL_WIDTH := 240`, `GUILD_BAR_WIDTH := 68`
- `TOUCH_TARGET_MIN := 44`

## Implementation Status

- [x] ClientModels conversion layer (typed models -> dicts)
- [x] ChannelType and UserStatus enums
- [x] Deterministic color palette from IDs
- [x] Five in-memory caches
- [x] Gateway-driven cache updates (create/update/delete)
- [x] Multi-server routing via guild_to_conn and channel_to_guild maps
- [x] Message cap enforcement (50 per channel)
- [x] CDN URL generation for avatars
- [x] Timestamp formatting (ISO 8601 -> 12-hour)
- [x] Null-safe field conversion (AccordKit models -> strings)
- [x] User caching on-demand during message fetch
- [x] Embed extraction (first embed only)
- [x] Reaction data conversion

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `unread` always false | High | `channel_to_dict()` line 142, `space_to_guild_dict()` line 120, `dm_channel_to_dict()` line 227 all hardcode false. Server may provide unread state but it's ignored |
| `mentions` always 0 | High | `space_to_guild_dict()` line 121 hardcodes 0. No tracking of mention counts |
| `last_message` always empty | Medium | `dm_channel_to_dict()` line 226 hardcodes "". DM list previews are always blank |
| `folder` always empty | Medium | `space_to_guild_dict()` line 119 hardcodes "". Guilds are never assigned to folders from server data |
| Timestamp always says "Today" | Medium | `_format_timestamp()` line 88 hardcodes "Today at" prefix regardless of actual date |
| No cache eviction | Low | User, guild, and channel caches grow unbounded. Only message cache has a cap (MESSAGE_CAP = 50) |
| `get_message_by_id()` is O(n) | Low | Linear search across all channels' message arrays (client.gd:288-293) |
| Only first embed extracted | Low | `message_to_dict()` reads `msg.embeds[0]` only; additional embeds are discarded |
| No avatar image loading | Medium | `user_to_dict()` generates CDN URLs but no code fetches/caches the actual images. Avatars are colored squares |
| `voice_users` not in channel dict | Medium | `channel_to_dict()` doesn't include voice participant count even though `channel_item.gd` reads it |
