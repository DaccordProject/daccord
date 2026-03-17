# Data Model

Priority: 2
Depends on: Server Connection

## Overview

daccord uses a dictionary-based data model as the contract between the network layer (AccordKit) and the UI. `ClientModels` converts AccordKit typed models into dictionary shapes that UI components consume via their `setup(data: Dictionary)` methods. Less-frequently-modified converters (role, invite, emoji, sound) are extracted into `ClientModelsSecondary` to reduce file size. `Client` maintains ten in-memory caches (users, spaces, channels, DM channels, messages, members, roles, voice states, thread messages, forum posts) plus a relationship cache, populated from REST fetches and kept current via gateway events. Unread and mention state is tracked separately and merged into cached dicts at runtime. A secondary `_message_id_index` provides O(1) message lookups. User cache is evicted when it exceeds `USER_CACHE_CAP` (500).

## Data Flow

```
AccordServer (REST/Gateway)
    -> AccordKit typed models (AccordUser, AccordSpace, AccordChannel, AccordMessage, AccordMember, AccordRole, AccordInvite, AccordEmoji, AccordSound, AccordVoiceState, AccordRelationship)
    -> ClientModels / ClientModelsSecondary static conversion functions
    -> Dictionary shapes (the data contract)
    -> Client caches (in-memory dictionaries)
    -> UI components via setup(data: Dictionary)
```

## Signal Flow

1. **REST fetch** (e.g., `Client.fetch.fetch_spaces()`) returns AccordKit typed models
2. `ClientModels` converts each model to a dictionary via `space_to_dict()`, `channel_to_dict()`, `message_to_dict()`, `member_to_dict()`, `role_to_dict()`, etc.
3. Dictionaries are stored in the appropriate `Client` cache (`_space_cache`, `_channel_cache`, `_message_cache`, `_member_cache`, `_role_cache`, etc.)
4. `Client` emits an `AppState` signal (`spaces_updated`, `channels_updated`, `messages_updated`, `members_updated`, `roles_updated`, etc.)
5. UI components receive the signal, read from `Client`'s data access API, and call `setup(data)` with the dictionary
6. **Gateway events** (message_create, message_update, message_delete, channel_create, member_join, role_create, reaction_add, etc.) follow the same path: convert model -> update cache -> emit signal -> UI refreshes

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd` | Primary conversion functions (user, space, channel, message, member, DM channel, voice state, relationship), enums (ChannelType, UserStatus, VoiceSessionState), color palette |
| `scripts/autoload/client_models_secondary.gd` | Secondary conversion functions (role, invite, emoji, sound), user flag constants, mention detection |
| `scripts/autoload/client.gd` | Ten caches + relationship cache, unread/mention tracking, message ID index, data access API, routing to correct server connection |
| `scripts/autoload/client_fetch.gd` | `ClientFetch` -- extracted fetch operations (spaces, channels, DMs, messages, members, roles, voice states, threads, forum posts); builds message ID index on fetch; DM preview pre-population |
| `scripts/autoload/client_admin.gd` | `ClientAdmin` -- admin API wrappers (space/channel/role/member/ban/invite/emoji/sound CRUD, reordering, permission overwrites) |
| `scripts/autoload/client_gateway.gd` | `ClientGateway` -- gateway event handlers (messages, typing, presence, members, roles, bans, invites, emojis, soundboard, reactions, voice states, connection lifecycle); tracks unread/mentions on message_create; updates DM last_message previews; maintains message ID index |
| `scripts/autoload/client_markdown.gd` | `ClientMarkdown` -- markdown-to-BBCode conversion (extracted from ClientModels) |
| `scripts/autoload/app_state.gd` | Central signal bus and UI state tracking |
| `scripts/autoload/config.gd` | Encrypted server config persistence, UI state (last selection, category collapsed) |
| `scenes/common/avatar.gd` | Avatar rendering with HTTP image loading from CDN URLs, static in-memory image cache, circle shader clipping |
| `addons/accordkit/models/user.gd` | AccordUser typed model |
| `addons/accordkit/models/space.gd` | AccordSpace typed model (includes `icon` hash field) |
| `addons/accordkit/models/channel.gd` | AccordChannel typed model (includes `last_message_id` field) |
| `addons/accordkit/models/message.gd` | AccordMessage typed model (includes `attachments`, `mentions`, `mention_everyone`) |
| `addons/accordkit/models/member.gd` | AccordMember typed model |
| `addons/accordkit/models/role.gd` | AccordRole typed model |
| `addons/accordkit/models/invite.gd` | AccordInvite typed model |
| `addons/accordkit/models/emoji.gd` | AccordEmoji typed model |
| `addons/accordkit/models/sound.gd` | AccordSound typed model |
| `addons/accordkit/models/reaction.gd` | AccordReaction typed model |
| `addons/accordkit/models/embed.gd` | AccordEmbed typed model (includes `image`, `thumbnail`, `fields`) |
| `addons/accordkit/models/attachment.gd` | AccordAttachment typed model |
| `addons/accordkit/models/presence.gd` | AccordPresence typed model |
| `addons/accordkit/models/permission.gd` | AccordPermission constants and helpers |
| `addons/accordkit/models/permission_overwrite.gd` | AccordPermissionOverwrite typed model |
| `addons/accordkit/models/voice_state.gd` | AccordVoiceState typed model |
| `addons/accordkit/utils/cdn.gd` | CDN URL construction for avatars, space icons, emojis, sounds, attachments |

## Implementation Details

### Enums (client_models.gd)

ChannelType (line 7): `{ TEXT, VOICE, ANNOUNCEMENT, FORUM, CATEGORY }`
UserStatus (line 10): `{ ONLINE, IDLE, DND, OFFLINE }`
VoiceSessionState (line 13): `{ DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, FAILED }`

### Enum Helpers (client_models.gd)

- `_status_string_to_enum(status: String) -> int` (line 64): Converts "online"/"idle"/"dnd" strings to UserStatus enum values; defaults to OFFLINE.
- `_status_enum_to_string(status: int) -> String` (line 75): Reverse of above; defaults to "offline".
- `_channel_type_to_enum(type_str: String) -> int` (line 108): Converts "text"/"voice"/"category"/"announcement"/"forum" to ChannelType; defaults to TEXT.

### Color Palette (client_models.gd:26-37)

10 HSV colors at S=0.7, V=0.9 with hues: 0.0, 0.08, 0.16, 0.28, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95
- `_color_from_id(id: String)`: Deterministic color assignment via `id.hash() % palette_size`
- Used for user avatars, space icons, and DM avatars when no image is available

### Dictionary Shapes

**User Dict** (client_models.gd:189-226, `user_to_dict()`):
```
{
    "id": String,
    "display_name": String,  # Falls back to username if null/empty
    "username": String,
    "color": Color,          # Deterministic from _color_from_id(id)
    "status": int,           # UserStatus enum value
    "avatar": String|null,   # CDN URL via _resolve_media_url() or null
    "is_admin": bool,        # From AccordUser.is_admin
    "bio": String,           # User bio, "" if null
    "banner": String|null,   # CDN URL for banner image or null
    "accent_color": int,     # Profile accent color integer, 0 if null
    "flags": int,            # User flag bitmask
    "public_flags": int,     # Public user flag bitmask
    "created_at": String,    # Account creation timestamp
    "bot": bool,             # Whether user is a bot
    "mfa_enabled": bool,     # Whether 2FA is enabled
    "client_status": Dictionary, # Per-platform status (initialized {})
    "activities": Array,     # User activities (initialized [])
}
```

**Space Dict** (client_models.gd:283-311, `space_to_dict()`):
```
{
    "id": String,
    "name": String,
    "slug": String,                  # Space slug for URL-friendly names
    "icon_color": Color,             # Deterministic from _color_from_id(id)
    "icon": String|null,             # CDN URL via _resolve_media_url() or null
    "folder": "",                    # Initialized empty; populated from Config persistence by ClientFetch
    "unread": bool,                  # Initialized false; updated by Client.mark_channel_unread()/_update_space_unread()
    "mentions": int,                 # Initialized 0; updated by Client._update_space_unread() from _channel_mention_counts
    "owner_id": String,              # Space owner user ID
    "description": String,           # From space.description, "" if null
    "verification_level": String,    # From space.verification_level
    "default_notifications": String, # From space.default_notifications
    "preferred_locale": String,      # From space.preferred_locale
    "public": bool,                  # true if space.public or "PUBLIC"/"public" in space.features
    "nsfw_level": variant,           # From space.nsfw_level
    "explicit_content_filter": variant, # From space.explicit_content_filter
    "rules_channel_id": String,      # System rules channel ID, "" if null
}
```

**Channel Dict** (client_models.gd:313-351, `channel_to_dict()`):
```
{
    "id": String,
    "space_id": String,      # From channel.space_id
    "name": String,
    "type": int,             # ChannelType enum value
    "parent_id": String,     # Category parent or ""
    "unread": bool,          # Initialized false; updated by Client.mark_channel_unread() on message_create
    "voice_users": int,      # Initialized 0; updated by voice state tracking in ClientGateway
    "position": int,         # Optional, only if channel.position != null
    "topic": String,         # Optional, only if non-empty
    "nsfw": true,            # Optional, only if channel.nsfw is true
    "allow_anonymous_read": true, # Optional, only if channel.allow_anonymous_read is true
    "permission_overwrites": Array, # Optional, only if overwrites exist; Array of {id, type, allow, deny} dicts
}
```

**Message Dict** (client_models.gd:353-490, `message_to_dict()`):
```
{
    "id": String,
    "channel_id": String,
    "author": Dictionary,    # User dict (from cache or fallback "Unknown")
    "content": String,
    "timestamp": String,     # "Today at H:MM AM/PM", "Yesterday at H:MM AM/PM", or "MM/DD/YYYY H:MM AM/PM"
    "edited": bool,          # true if msg.edited_at != null
    "reactions": Array,      # [{emoji: String, count: int, active: bool}, ...]
    "reply_to": String,      # Message ID or ""
    "embed": Dictionary,     # First embed: {title, description, color, footer, image, thumbnail, author, fields, url, type} or {}
    "embeds": Array,         # All embeds: [{...same keys...}, ...]
    "attachments": Array,    # [{id, filename, size, url, content_type?, width?, height?}, ...]
    "system": bool,          # true if type != "default" and != "reply"
    "mentions": Array,       # Array of mentioned user IDs
    "mention_everyone": bool, # Whether @everyone was used
    "mention_roles": Array,  # Array of mentioned role IDs
    "thread_id": String,     # Thread/parent message ID or ""
    "reply_count": int,      # Number of thread replies
    "last_reply_at": String, # Timestamp of last thread reply or ""
    "thread_participants": Array, # User IDs of thread participants
    "title": String,         # Forum post title or ""
}
```

**Member Dict** (client_models.gd:497-535, `member_to_dict()`):
```
{
    "id": String,            # user_id
    "display_name": String,  # Nickname overrides user display_name
    "username": String,
    "color": Color,
    "status": int,           # UserStatus enum value
    "avatar": String|null,   # Per-server member avatar overrides user avatar
    "nickname": String,      # Raw nickname string ("" if none)
    "roles": Array,          # Array of role ID strings (copied from member.roles)
    "joined_at": String,     # Join timestamp
    "mute": bool,            # Server-side mute state
    "deaf": bool,            # Server-side deafen state
    "timed_out_until": String, # Timeout expiry timestamp or ""
}
```
Note: member_to_dict() duplicates the user dict from cache, then overlays the member's nickname as display_name and adds member-specific fields. Per-server member avatar (if set) overrides the user's global avatar via CDN URL resolution.

**DM Channel Dict** (client_models.gd:537-598, `dm_channel_to_dict()`):
```
{
    "id": String,
    "user": Dictionary,      # User dict for first recipient (1:1) or combined entry (group)
    "recipients": Array,     # Array of user dicts for all recipients
    "is_group": bool,        # true if more than one recipient
    "owner_id": String,      # Group DM owner ID, "" if null
    "name": String,          # Channel name (for group DMs), "" if null
    "last_message": String,  # Initialized ""; pre-populated from REST via _fetch_dm_previews(); updated by gateway
    "last_message_id": String, # Last message snowflake ID for REST preview fetch, "" if null
    "unread": bool,          # Initialized false; updated by Client.mark_channel_unread() on message_create
}
```

**Role Dict** (client_models_secondary.gd:21-31, `role_to_dict()`):
```
{
    "id": String,
    "name": String,
    "color": int,            # Role color integer
    "hoist": bool,           # Display separately in member list
    "position": int,         # Sort position
    "permissions": Array,    # Array of permission strings (e.g., ["SEND_MESSAGES", "VIEW_CHANNEL"])
    "managed": bool,         # Bot-managed role
    "mentionable": bool,
}
```

**Invite Dict** (client_models_secondary.gd:33-57, `invite_to_dict()`):
```
{
    "code": String,
    "space_id": String,
    "channel_id": String,
    "inviter_id": String,    # "" if null
    "max_uses": int,         # 0 if null
    "uses": int,
    "max_age": int,          # 0 if null (seconds)
    "temporary": bool,
    "created_at": String,
    "expires_at": String,    # "" if null
}
```

**Emoji Dict** (client_models_secondary.gd:59-72, `emoji_to_dict()`):
```
{
    "id": String,            # "" if null (unicode emoji)
    "name": String,
    "animated": bool,
    "role_ids": Array,       # Array of role ID strings
    "creator_id": String,    # "" if null
}
```

**Sound Dict** (client_models_secondary.gd:74-89, `sound_to_dict()`):
```
{
    "id": String,            # "" if null
    "name": String,
    "audio_url": String,     # CDN path or URL
    "volume": float,         # 0.0-1.0 multiplier
    "creator_id": String,    # "" if null
    "created_at": String,
    "updated_at": String,
}
```

**Voice State Dict** (client_models.gd:612-641, `voice_state_to_dict()`):
```
{
    "user_id": String,
    "channel_id": String,    # Voice channel ID, "" if null
    "session_id": String,
    "self_mute": bool,
    "self_deaf": bool,
    "self_video": bool,
    "self_stream": bool,
    "mute": bool,            # Server-side mute
    "deaf": bool,            # Server-side deafen
    "user": Dictionary,      # User dict from cache
}
```

**Relationship Dict** (client_models.gd:228-249, `relationship_to_dict()`):
```
{
    "id": String,
    "user": Dictionary,      # User dict with status and activities
    "type": int,             # Relationship type (friend, blocked, pending, etc.)
    "since": String,         # Relationship creation timestamp
    "server_url": String,    # Server URL for cross-server friends
    "space_name": String,    # Space name where relationship originated
    "available": bool,       # true if from live server, false if from friend book
}
```

### Markdown to BBCode (client_markdown.gd)

`markdown_to_bbcode(text: String) -> String` converts Discord-style markdown to Godot BBCode for RichTextLabel rendering. Supported conversions:

| Markdown | BBCode |
|----------|--------|
| ` ```code``` ` | `[code]code[/code]` |
| `` `inline` `` | `[code]inline[/code]` |
| `~~text~~` | `[s]text[/s]` |
| `__text__` | `[u]text[/u]` |
| `**text**` | `[b]text[/b]` |
| `*text*` | `[i]text[/i]` |
| `\|\|text\|\|` | `[bgcolor][color]text[/color][/bgcolor]` (spoiler, hidden text) |
| `[text](url)` | `[url=url]text[/url]` |
| `> text` | `[indent][color]text[/color][/indent]` (blockquote) |
| `:emoji_name:` | `[img=20x20]res://assets/theme/emoji/{codepoint}.svg[/img]` (if found in EmojiData) |

### Timestamp Formatting (client_models.gd:123-187)

- Parses ISO 8601 strings (e.g., "2025-05-10T14:30:00Z")
- Extracts date and time portions, strips timezone suffix (Z/+/-) and milliseconds
- Converts to 12-hour format
- Compares parsed date against UTC system time:
  - Same day: "Today at H:MM AM/PM"
  - Previous day: "Yesterday at H:MM AM/PM"
  - Older: "MM/DD/YYYY H:MM AM/PM"
- Returns raw string if unparseable

### Caching Architecture (client.gd)

Ten caches plus relationship cache:
- `_user_cache: Dictionary` -- keyed by user_id -> user dict. Evicted via `trim_user_cache()` when exceeding `USER_CACHE_CAP` (500); preserves current user, current space members, and current channel message authors.
- `_space_cache: Dictionary` -- keyed by space_id -> space dict
- `_channel_cache: Dictionary` -- keyed by channel_id -> channel dict
- `_dm_channel_cache: Dictionary` -- keyed by channel_id -> DM channel dict
- `_message_cache: Dictionary` -- keyed by channel_id -> Array of message dicts
- `_member_cache: Dictionary` -- keyed by space_id -> Array of member dicts
- `_role_cache: Dictionary` -- keyed by space_id -> Array of role dicts
- `_voice_state_cache: Dictionary` -- keyed by channel_id -> Array of voice state dicts
- `_thread_message_cache: Dictionary` -- keyed by parent_message_id -> Array of message dicts
- `_forum_post_cache: Dictionary` -- keyed by channel_id -> Array of post dicts
- `_relationship_cache: Dictionary` -- keyed by "{conn_index}:{user_id}" -> relationship dict

Auxiliary indexes:
- `_message_id_index: Dictionary` -- message_id -> channel_id, maintained on message_create/delete and fetch_messages; enables O(1) lookups in `get_message_by_id()` and `_find_channel_for_message()`
- `_unread_channels: Dictionary` -- channel_id -> true, set on message_create when channel != current, cleared on channel_selected
- `_channel_mention_counts: Dictionary` -- channel_id -> int, incremented on message_create when current user is mentioned, cleared on channel_selected
- `_thread_unread: Dictionary` -- parent_message_id -> true, tracks unread thread messages
- `_thread_mention_count: Dictionary` -- parent_message_id -> int, tracks mention counts per thread
- `_muted_channels: Dictionary` -- channel_id -> true, server-side per-user channel mute state
- `_voice_server_info: Dictionary` -- stored voice server connection info

Routing maps:
- `_space_to_conn: Dictionary` -- space_id -> connection index (for multi-server)
- `_channel_to_space: Dictionary` -- channel_id -> space_id

Cache population (via ClientFetch):
- On connect: space fetched via `spaces.fetch()` during `connect_server()`, populates `_space_cache` with CDN icon URL
- On gateway ready: `fetch_channels()`, `fetch_members()`, `fetch_roles()` called for the space; `fetch_dm_channels()` also called
- On space select: `fetch_channels(space_id)` populates `_channel_cache` from `GET /spaces/{id}/channels`
- On DM mode: `fetch_dm_channels()` populates `_dm_channel_cache` from `GET /users/@me/channels`
- On channel select: `fetch_messages(channel_id)` populates `_message_cache` from `GET /channels/{id}/messages?limit=50`; builds `_message_id_index`; triggers `trim_user_cache()`
- On member list shown: `fetch_members(space_id)` populates `_member_cache` from `GET /spaces/{id}/members?limit=1000`
- On role management: `fetch_roles(space_id)` populates `_role_cache` from `GET /spaces/{id}/roles`
- Users cached on-demand when encountered in messages, DM recipients, or member fetches

Cache updates via gateway (ClientGateway):
- message_create: appends to `_message_cache`, adds to `_message_id_index`, enforces MESSAGE_CAP (50) via `pop_front()` (evicted messages removed from index); marks channel unread if not current; checks `message.mentions` and `mention_everyone` to track mention counts; updates DM channel `last_message` preview with truncated content
- message_update: finds and replaces in `_message_cache` array (with CDN URL for attachments)
- message_delete: finds and removes from `_message_cache` array and `_message_id_index`
- channel_create/update: updates `_channel_cache` or `_dm_channel_cache` based on type (dm/group_dm vs space)
- channel_delete: erases from `_channel_cache` or `_dm_channel_cache`
- space_create: updates `_space_cache` if matching connected space (with CDN URL for icon)
- space_update: updates `_space_cache` (with CDN URL for icon)
- space_delete: erases from `_space_cache` and `_space_to_conn`
- member_join: fetches user if missing, appends to `_member_cache`
- member_leave: removes from `_member_cache`
- member_update: finds and replaces or appends in `_member_cache`
- role_create: appends to `_role_cache`
- role_update: finds and replaces in `_role_cache`
- role_delete: removes from `_role_cache`
- presence_update: updates status in `_user_cache` and matching `_member_cache` entry
- ban_create/ban_delete: emits `bans_updated` (no local cache; bans fetched on-demand)
- invite_create/invite_delete: emits `invites_updated` (no local cache; invites fetched on-demand)
- emoji_update: emits `emojis_updated` (no local cache; emojis fetched on-demand)
- soundboard_create/update/delete: emits `soundboard_updated` (no local cache; sounds fetched on-demand)
- soundboard_play: emits `soundboard_played` with space_id, sound_id, user_id
- reaction_add: increments count or adds new entry in message's reactions array; sets `active` if current user
- reaction_remove: decrements count, removes entry if count reaches 0; clears `active` if current user
- reaction_clear: empties entire reactions array for a message
- reaction_clear_emoji: removes specific emoji entry from reactions array

Data access API (client.gd):
- `spaces: Array` -> `_space_cache.values()` (property)
- `channels: Array` -> `_channel_cache.values()` (property)
- `dm_channels: Array` -> `_dm_channel_cache.values()` (property)
- `get_channels_for_space(space_id)` -> filters `_channel_cache` by space_id
- `get_messages_for_channel(channel_id)` -> returns from `_message_cache` or empty array
- `get_user_by_id(user_id)` -> returns from `_user_cache` or empty dict
- `get_space_by_id(space_id)` -> returns from `_space_cache` or empty dict
- `get_members_for_space(space_id)` -> returns from `_member_cache` or empty array
- `get_roles_for_space(space_id)` -> returns from `_role_cache` or empty array
- `get_message_by_id(message_id)` -> O(1) via `_message_id_index` with linear fallback (line 412)

### Unread / Mention Tracking (client.gd)

- `_on_channel_selected_clear_unread(cid)` (line 703): Connected to `AppState.channel_selected`. Erases unread flag and mention count for the channel, updates cached channel dict, recomputes space aggregates, emits `channels_updated`/`dm_channels_updated`.
- `mark_channel_unread(cid, is_mention)` (line 718): Sets `_unread_channels[cid] = true`, increments `_channel_mention_counts[cid]` if `is_mention`, updates the cached channel dict's `unread` field, recomputes space aggregates, emits `channels_updated`/`dm_channels_updated` and `spaces_updated`.
- `_update_space_unread(gid)` (line 736): Iterates channels in `_channel_cache` for the space, computes `unread = any channel unread` and `mentions = sum of channel mention counts`, writes results to `_space_cache[gid]`.
- **Gateway trigger** (client_gateway.gd): `on_message_create()` calls `mark_channel_unread(channel_id, is_mention)` when `message.channel_id != AppState.current_channel_id` and `message.author_id != current_user.id`. Mention detection checks `my_id in message.mentions or message.mention_everyone`.

### Avatar Image Loading (avatar.gd)

- `set_avatar_url(url)`: Checks a static `_image_cache: Dictionary` (shared across all avatar instances). On cache hit, applies the texture immediately. On miss, creates an `HTTPRequest` child and fetches the image.
- `_on_image_loaded()`: Tries PNG, JPG, and WebP decoding in order. On success, stores the `ImageTexture` in `_image_cache` and calls `_apply_texture()`.
- `_apply_texture(tex)`: Creates a `TextureRect` child with `PRESET_FULL_RECT` anchoring, applies the same circle shader (`avatar_circle.gdshader`), hides the letter label.
- `set_radius()` syncs the radius parameter to both the ColorRect shader and the TextureRect shader, so hover animations (circle -> rounded square) work on loaded images.
- **Callers**: `cozy_message.gd` calls `avatar.set_avatar_url(avatar_url)` in `setup()` when the user dict has a non-empty `avatar` URL. `guild_icon.gd` calls `avatar_rect.set_avatar_url(icon_url)` in `setup()` when the space dict has a non-empty `icon` URL.

### Mutation API (client.gd)

- `send_message_to_channel(cid, content, reply_to)` -> creates message via REST; emits `message_send_failed` on error
- `update_message_content(mid, new_content)` -> edits message via REST; emits `message_edit_failed` on error
- `remove_message(mid)` -> deletes message via REST; emits `message_delete_failed` on error
- `add_reaction(cid, mid, emoji)` -> adds reaction via REST + optimistic cache update
- `remove_reaction(cid, mid, emoji)` -> removes reaction via REST + optimistic cache update
- `update_presence(status)` -> updates own status in caches and sends to all connected servers
- `send_typing(cid)` -> sends typing indicator to channel

### Search API (client.gd)

- `search_messages(space_id, query_str, filters)` -> searches via `messages.search()` REST endpoint; fetches missing authors on-demand; passes CDN URL for attachment URLs; returns `{results: Array, has_more: bool}`

### Permission Helpers (client.gd)

- `has_permission(gid, perm)` -> checks if current user has a permission. Returns true if: user `is_admin`, user is space `owner_id`, or perm is found in the union of all role permissions (base role + assigned roles). Uses `AccordPermission.has()` which also grants ADMINISTRATOR full access.
- `is_space_owner(gid)` -> checks if current user is the space owner

### Admin API (ClientAdmin)

Thin delegation layer that routes calls to the correct AccordClient and refreshes caches on success:

| Method | REST call | Cache refresh |
|--------|-----------|---------------|
| `update_space(space_id, data)` | `spaces.update()` | `fetch_spaces()` |
| `delete_space(space_id)` | `spaces.delete()` | none |
| `create_channel(space_id, data)` | `spaces.create_channel()` | `fetch_channels()` |
| `update_channel(channel_id, data)` | `channels.update()` | `fetch_channels()` |
| `delete_channel(channel_id)` | `channels.delete()` | `fetch_channels()` |
| `create_role(space_id, data)` | `roles.create()` | `fetch_roles()` |
| `update_role(space_id, role_id, data)` | `roles.update()` | `fetch_roles()` |
| `delete_role(space_id, role_id)` | `roles.delete()` | `fetch_roles()` |
| `kick_member(space_id, user_id)` | `members.kick()` | `fetch_members()` |
| `ban_member(space_id, user_id, data)` | `bans.create()` | `fetch_members()` + `bans_updated` |
| `unban_member(space_id, user_id)` | `bans.remove()` | `bans_updated` |
| `add_member_role(space_id, user_id, role_id)` | `members.add_role()` | `fetch_members()` |
| `remove_member_role(space_id, user_id, role_id)` | `members.remove_role()` | `fetch_members()` |
| `get_bans(space_id)` | `bans.list()` | none (on-demand) |
| `get_invites(space_id)` | `invites.list_space()` | none (on-demand) |
| `create_invite(space_id, data)` | `invites.create_space()` | `invites_updated` |
| `delete_invite(code, space_id)` | `invites.delete()` | `invites_updated` |
| `get_emojis(space_id)` | `emojis.list()` | none (on-demand) |
| `create_emoji(space_id, data)` | `emojis.create()` | `emojis_updated` |
| `update_emoji(space_id, emoji_id, data)` | `emojis.update()` | `emojis_updated` |
| `delete_emoji(space_id, emoji_id)` | `emojis.delete()` | `emojis_updated` |
| `get_sounds(space_id)` | `soundboard.list()` | none (on-demand) |
| `create_sound(space_id, data)` | `soundboard.create()` | `soundboard_updated` |
| `update_sound(space_id, sound_id, data)` | `soundboard.update()` | `soundboard_updated` |
| `delete_sound(space_id, sound_id)` | `soundboard.delete()` | `soundboard_updated` |
| `play_sound(space_id, sound_id)` | `soundboard.play()` | none |
| `get_emoji_url(space_id, emoji_id, animated)` | `AccordCDN.emoji()` | none |
| `get_sound_url(space_id, audio_url)` | `AccordCDN.sound()` | none |
| `reorder_channels(space_id, data)` | `spaces.reorder_channels()` | `fetch_channels()` |
| `reorder_roles(space_id, data)` | `roles.reorder()` | `fetch_roles()` |
| `update_channel_overwrites(channel_id, overwrites)` | `channels.update()` | `fetch_channels()` |

### Server Management (client.gd)

- `disconnect_server(space_id)` -> logs out, clears all caches for that space (space, roles, members, channels, messages, unread/mentions, message index, routing), removes config, re-indexes connections, emits `spaces_updated`
- `reconnect_server(index)` -> logs out old client, resets status to "connecting", calls `connect_server()` again
- `is_server_connected(index)` -> checks if connection at index is "connected"
- `is_space_connected(gid)` -> checks connection for space
- `get_space_connection_status(gid)` -> returns status string ("connected", "connecting", "disconnected", "reconnecting", "error", "none")
- `get_conn_index_for_space(gid)` -> returns connection index

### Reconnection Architecture (client.gd + client_gateway.gd)

- `_auto_reconnect_attempted: Dictionary` -- tracks per-connection whether auto-reconnect has been tried
- On gateway disconnect with fatal codes (4003, 4004, 4012, 4013, 4014): escalates to full reconnect with re-auth via `_handle_gateway_reconnect_failed()`
- On gateway reconnect exhausted (max attempts reached): same escalation
- `_handle_gateway_reconnect_failed()` calls `reconnect_server()` once; if already attempted, sets status to "error" and emits `server_connection_failed`
- `_try_reauth()` re-authenticates with stored username/password credentials; updates token in config on success

### AppState Signals (app_state.gd)

| Signal | Parameters | Emitted by |
|--------|------------|------------|
| `space_selected` | space_id | AppState.select_space() |
| `channel_selected` | channel_id | AppState.select_channel(); also triggers Client._on_channel_selected_clear_unread() |
| `dm_mode_entered` | -- | AppState.enter_dm_mode() |
| `message_sent` | text | AppState.send_message() |
| `reply_initiated` | message_id | AppState.initiate_reply() |
| `reply_cancelled` | -- | AppState.cancel_reply() |
| `message_edited` | message_id, new_content | AppState.edit_message() |
| `edit_requested` | message_id | UI components |
| `message_deleted` | message_id | AppState.delete_message() |
| `layout_mode_changed` | mode | AppState.update_layout_mode() |
| `sidebar_drawer_toggled` | is_open | AppState.toggle/close_sidebar_drawer() |
| `spaces_updated` | -- | Client/ClientFetch/ClientGateway; also emitted by mark_channel_unread() when space indicators change |
| `channels_updated` | space_id | ClientFetch/ClientGateway; also emitted by _on_channel_selected_clear_unread() and mark_channel_unread() |
| `dm_channels_updated` | -- | ClientFetch/ClientGateway; also emitted by on_message_create() for DM last_message updates and mark_channel_unread() |
| `messages_updated` | channel_id | ClientFetch/ClientGateway/Client (reactions) |
| `user_updated` | user_id | ClientGateway (presence), Client (own presence) |
| `typing_started` | channel_id, username | ClientGateway |
| `typing_stopped` | channel_id | UI components (timer-based) |
| `members_updated` | space_id | ClientFetch/ClientGateway/Client/ClientAdmin |
| `roles_updated` | space_id | ClientFetch/ClientGateway/ClientAdmin |
| `bans_updated` | space_id | ClientGateway/ClientAdmin |
| `invites_updated` | space_id | ClientGateway/ClientAdmin |
| `emojis_updated` | space_id | ClientGateway/ClientAdmin |
| `soundboard_updated` | space_id | ClientGateway/ClientAdmin |
| `soundboard_played` | space_id, sound_id, user_id | ClientGateway |
| `reactions_updated` | channel_id, message_id | UI components |
| `member_list_toggled` | is_visible | AppState.toggle_member_list() |
| `channel_panel_toggled` | is_visible | AppState.toggle_channel_panel() |
| `search_toggled` | is_open | AppState.toggle/close_search() |
| `server_disconnected` | space_id, code, reason | ClientGateway |
| `server_reconnecting` | space_id, attempt, max_attempts | ClientGateway |
| `server_reconnected` | space_id | ClientGateway |
| `server_connection_failed` | space_id, reason | Client |
| `message_send_failed` | channel_id, content, error | Client |
| `message_edit_failed` | message_id, error | Client |
| `message_delete_failed` | message_id, error | Client |
| `message_fetch_failed` | channel_id, error | ClientFetch |

### AppState UI State (app_state.gd)

| Variable | Type | Default |
|----------|------|---------|
| `current_space_id` | String | "" |
| `current_channel_id` | String | "" |
| `is_dm_mode` | bool | false |
| `replying_to_message_id` | String | "" |
| `editing_message_id` | String | "" |
| `current_layout_mode` | LayoutMode | FULL |
| `sidebar_drawer_open` | bool | false |
| `member_list_visible` | bool | true |
| `channel_panel_visible` | bool | true |
| `search_open` | bool | false |

### Config Persistence (config.gd)

Encrypted storage at `user://config.cfg` (salt: "daccord-config-v1").

Server config shape (per server):
```
{
    "base_url": String,
    "token": String,
    "space_name": String,
    "username": String,   # For re-auth on token expiry
    "password": String,   # For re-auth on token expiry
}
```

Methods:
- `get_servers() -> Array` -- returns array of server config dicts
- `add_server(base_url, token, space_name, username, password)` -- adds and saves
- `remove_server(index)` -- removes by index and re-indexes remaining
- `update_server_url(index, new_url)` -- updates base URL
- `update_server_token(index, new_token)` -- updates token (e.g., after re-auth)
- `has_servers() -> bool` -- checks if any servers configured
- `set_last_selection(space_id, channel_id)` -- persists last selected space/channel
- `get_last_selection() -> Dictionary` -- returns `{space_id, channel_id}`
- `set_category_collapsed(space_id, category_id, collapsed)` -- persists category UI state
- `is_category_collapsed(space_id, category_id) -> bool` -- retrieves category state
- `clear()` -- wipes all server configs

Multi-server routing (client.gd):
- `_client_for_space(space_id)` -> looks up `_space_to_conn`, returns AccordClient
- `_client_for_channel(channel_id)` -> channel -> space -> connection
- `_cdn_for_space(space_id)` / `_cdn_for_channel(channel_id)` -> CDN URL for correct server

Constants (client.gd:6-15):
- `MESSAGE_CAP := 50` -- max messages cached per channel
- `MAX_CHANNEL_MESSAGES := 200` -- upper message limit
- `MESSAGE_QUEUE_CAP := 20` -- message queue cap
- `SPACE_ICON_SIZE := 48`, `AVATAR_SIZE := 42`, `CHANNEL_ICON_SIZE := 32`
- `CHANNEL_PANEL_WIDTH := 240`, `SPACE_BAR_WIDTH := 68`
- `TOUCH_TARGET_MIN := 44`
- `USER_CACHE_CAP := 500` -- max user cache entries before eviction

## Implementation Status

- [x] ClientModels conversion layer (typed models -> dicts) for all 11 model types (split across ClientModels + ClientModelsSecondary)
- [x] ChannelType, UserStatus, and VoiceSessionState enums with bidirectional string conversion
- [x] Deterministic color palette from IDs
- [x] Ten in-memory caches (users, spaces, channels, DMs, messages, members, roles, voice states, thread messages, forum posts) + relationship cache
- [x] Gateway-driven cache updates for all event types (messages, channels, spaces, members, roles, reactions, presence)
- [x] Gateway signal-only notifications for bans, invites, emojis, soundboard (on-demand fetching, no local cache)
- [x] Multi-server routing via space_to_conn and channel_to_space maps
- [x] Message cap enforcement (50 per channel)
- [x] CDN URL generation for avatars, space icons, emojis, sounds, attachments
- [x] Timestamp formatting (ISO 8601 -> 12-hour with Today/Yesterday/date)
- [x] Null-safe field conversion (AccordKit models -> strings)
- [x] User caching on-demand during message/member/DM fetch
- [x] All embeds extracted (full array + backward-compat first-embed field)
- [x] Attachment data surfaced in message dict with CDN URL resolution
- [x] Reaction data conversion + optimistic cache updates + full gateway reaction events
- [x] Mutation API (send/edit/delete messages, add/remove reactions, update presence, send typing)
- [x] Search API for messages (with CDN URL for attachments)
- [x] Permission checking (has_permission, is_space_owner) with role union + ADMINISTRATOR + owner bypass
- [x] Admin API wrappers (ClientAdmin) for all admin operations
- [x] ClientFetch extraction for data fetching operations
- [x] ClientGateway extraction for gateway event handling
- [x] Server disconnect/reconnect/re-auth lifecycle
- [x] Encrypted config persistence with credential storage
- [x] Markdown to BBCode conversion (code, bold, italic, underline, strike, spoiler, links, blockquotes, emoji shortcodes)
- [x] Error signals for failed mutations (send, edit, delete, fetch)
- [x] Unread channel tracking (set on message_create, cleared on channel_selected, aggregated to space)
- [x] Mention count tracking (incremented on message_create when user is mentioned, aggregated to space)
- [x] DM last_message preview (updated on message_create with truncated content)
- [x] Space icon URLs from AccordSpace.icon via AccordCDN.space_icon()
- [x] Avatar image loading via HTTP with static in-memory cache and circle shader clipping
- [x] O(1) message lookup via _message_id_index (with linear fallback)
- [x] User cache eviction (trim_user_cache() at USER_CACHE_CAP=500)
- [x] Attachment rendering in message_content.gd (inline images + filename link + file size)
- [x] Voice state tracking via `_voice_state_cache` with gateway voice_state_update events updating `voice_users` count in channel cache
- [x] Space folder assignment with Config persistence (`get_space_folder`, `set_space_folder`, `get_folder_color`, `set_folder_color`)
- [x] DM last_message pre-population from REST via `_fetch_dm_previews()` using `last_message_id`
- [x] Inline image rendering for attachments (PNG/JPG/WebP/BMP with max 400×300px, LRU cache with 100-entry cap)
- [x] Member fetch pagination (cursor-based, fetches all members regardless of space size)
- [x] Avatar image cache LRU eviction (`AVATAR_CACHE_CAP := 200`, `_cache_access_order` tracking)
- [x] Thread message cache (`_thread_message_cache`, `fetch_thread_messages()`, `get_messages_for_thread()`)
- [x] Forum post cache (`_forum_post_cache`, `fetch_forum_posts()`, `get_forum_posts()`)
- [x] Relationship cache for cross-server friends
- [x] Voice API helpers (`get_voice_users()`, `get_voice_user_count()`, `join_voice_channel()`, `leave_voice_channel()`)
- [x] Per-server member avatars (override user avatar in member_to_dict)
- [x] User profile fields (bio, banner, accent_color, flags, public_flags, created_at, bot, mfa_enabled, client_status, activities)
- [x] Activity formatting (`format_activity()` for Playing/Streaming/Listening/Watching/Competing/Custom)
- [x] Channel mute tracking (`_muted_channels`)
- [x] Thread unread/mention tracking (`_thread_unread`, `_thread_mention_count`)

## Tasks

### DATA-1: `voice_users` always 0
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** gateway, voice
- **Notes:** Fixed. `_voice_state_cache` (client.gd line 106) tracks per-channel voice states. Gateway `on_voice_state_update()` (client_gateway_events.gd lines 144-217) updates `voice_users` count in channel cache. `fetch_voice_states()` and `resync_voice_states()` in client_fetch.gd handle REST population.

### DATA-2: `folder` always empty
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** Fixed. Config persistence via `get_space_folder()`/`set_space_folder()` (config.gd lines 385-417). ClientFetch preserves folder from old cache on re-fetch. Full folder UI in `guild_folder.gd`.

### DATA-3: DM `last_message` only from gateway
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, dm, gateway
- **Notes:** Fixed. `_fetch_dm_previews()` (client_fetch.gd lines 605-631) pre-populates last_message from REST using `last_message_id`. Called automatically after `fetch_dm_channels()`.

### DATA-4: No image display for attachments
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** general
- **Notes:** Fixed. `message_content.gd` (lines 91-102) detects `content_type.begins_with("image/")` and renders inline with TextureRect (max 400×300px). LRU cache with 100-entry cap prevents unbounded growth. Video and audio attachments also handled.

### DATA-5: Timestamps in UTC
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** `_format_timestamp()` (client_models.gd line 170) uses `Time.get_datetime_dict_from_system(true)` which forces UTC comparison. Users in non-UTC timezones see UTC times. Fix: change `true` to `false` for local system time.

### DATA-6: Member cache limit
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** api, performance
- **Notes:** Fixed. `fetch_members()` (client_fetch.gd lines 443-490) now uses cursor-based pagination loop with `after` parameter. Fetches all members regardless of space size. User deduplication on each page.

### DATA-7: Avatar image cache unbounded
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** performance
- **Notes:** Fixed. `avatar.gd` now has `AVATAR_CACHE_CAP := 200` with LRU eviction via `_cache_access_order` array and `_evict_cache()` method.
