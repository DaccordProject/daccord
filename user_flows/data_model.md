# Data Model


## Overview

daccord uses a dictionary-based data model as the contract between the network layer (AccordKit) and the UI. `ClientModels` converts AccordKit typed models into dictionary shapes that UI components consume via their `setup(data: Dictionary)` methods. `Client` maintains seven in-memory caches (users, spaces, channels, DM channels, messages, members, roles) populated from REST fetches and kept current via gateway events. Unread and mention state is tracked separately and merged into cached dicts at runtime. A secondary `_message_id_index` provides O(1) message lookups. User cache is evicted when it exceeds `USER_CACHE_CAP` (500).

## Data Flow

```
AccordServer (REST/Gateway)
    -> AccordKit typed models (AccordUser, AccordSpace, AccordChannel, AccordMessage, AccordMember, AccordRole, AccordInvite, AccordEmoji, AccordSound)
    -> ClientModels static conversion functions
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
| `scripts/autoload/client_models.gd` | Static conversion functions, enums (ChannelType, UserStatus), color palette, markdown_to_bbcode |
| `scripts/autoload/client.gd` | Seven caches, unread/mention tracking, message ID index, data access API, mutation API, search API, permission helpers, cache eviction, routing to correct server connection |
| `scripts/autoload/client_fetch.gd` | `ClientFetch` -- extracted fetch operations (spaces, channels, DMs, messages, members, roles); builds message ID index on fetch |
| `scripts/autoload/client_admin.gd` | `ClientAdmin` -- admin API wrappers (space/channel/role/member/ban/invite/emoji/sound CRUD, reordering, permission overwrites) |
| `scripts/autoload/client_gateway.gd` | `ClientGateway` -- gateway event handlers (messages, typing, presence, members, roles, bans, invites, emojis, soundboard, reactions, connection lifecycle); tracks unread/mentions on message_create; updates DM last_message previews; maintains message ID index |
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

### Enum Helpers (client_models.gd)

- `_status_string_to_enum(status: String) -> int` (line 31): Converts "online"/"idle"/"dnd" strings to UserStatus enum values; defaults to OFFLINE.
- `_status_enum_to_string(status: int) -> String` (line 42): Reverse of above; defaults to "offline".
- `_channel_type_to_enum(type_str: String) -> int` (line 53): Converts "text"/"voice"/"category"/"announcement"/"forum" to ChannelType; defaults to TEXT.

### Color Palette (client_models.gd:12-23)

10 HSV colors at S=0.7, V=0.9 with hues: 0.0, 0.08, 0.16, 0.28, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95
- `_color_from_id(id: String)`: Deterministic color assignment via `id.hash() % palette_size`
- Used for user avatars, space icons, and DM avatars when no image is available

### Dictionary Shapes

**User Dict** (client_models.gd:134-157, `user_to_dict()`):
```
{
    "id": String,
    "display_name": String,  # Falls back to username if null/empty
    "username": String,
    "color": Color,          # Deterministic from _color_from_id(id)
    "status": int,           # UserStatus enum value
    "avatar": String|null,   # CDN URL via AccordCDN.avatar() or null
    "is_admin": bool,        # From AccordUser.is_admin
}
```

**Space Dict** (client_models.gd:159-187, `space_to_dict()`):
```
{
    "id": String,
    "name": String,
    "icon_color": Color,             # Deterministic from _color_from_id(id)
    "icon": String|null,             # CDN URL via AccordCDN.space_icon() or null
    "folder": "",                    # Always empty string (client-side feature, not server data)
    "unread": bool,                  # Initialized false; updated by Client.mark_channel_unread()/_update_space_unread()
    "mentions": int,                 # Initialized 0; updated by Client._update_space_unread() from _channel_mention_counts
    "owner_id": String,              # Space owner user ID
    "description": String,           # From space.description, "" if null
    "verification_level": String,    # From space.verification_level
    "default_notifications": String, # From space.default_notifications
    "preferred_locale": String,      # From space.preferred_locale
    "public": bool,                  # true if "PUBLIC" or "public" in space.features
}
```

**Channel Dict** (client_models.gd:189-225, `channel_to_dict()`):
```
{
    "id": String,
    "space_id": String,      # From channel.space_id
    "name": String,
    "type": int,             # ChannelType enum value
    "parent_id": String,     # Category parent or ""
    "unread": bool,          # Initialized false; updated by Client.mark_channel_unread() on message_create
    "voice_users": int,      # Initialized 0; placeholder for voice state tracking
    "position": int,         # Optional, only if channel.position != null
    "topic": String,         # Optional, only if non-empty
    "nsfw": true,            # Optional, only if channel.nsfw is true
    "permission_overwrites": Array, # Optional, only if overwrites exist; Array of {id, type, allow, deny} dicts
}
```

**Message Dict** (client_models.gd:227-316, `message_to_dict()`):
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
    "embed": Dictionary,     # First embed: {title, description, color, footer, image, thumbnail} or {}
    "embeds": Array,         # All embeds: [{title, description, color, footer, image, thumbnail}, ...]
    "attachments": Array,    # [{id, filename, size, url, content_type?, width?, height?}, ...]
    "system": bool,          # true if type != "default" and != "reply"
}
```

**Member Dict** (client_models.gd:318-335, `member_to_dict()`):
```
{
    "id": String,            # user_id
    "display_name": String,  # Nickname overrides user display_name
    "username": String,
    "color": Color,
    "status": int,           # UserStatus enum value
    "avatar": String|null,
    "roles": Array,          # Array of role ID strings (copied from member.roles)
    "joined_at": String,     # Join timestamp
}
```
Note: member_to_dict() duplicates the user dict from cache, then overlays the member's nickname as display_name and adds `roles` and `joined_at` fields.

**DM Channel Dict** (client_models.gd:337-360, `dm_channel_to_dict()`):
```
{
    "id": String,
    "user": Dictionary,      # User dict for first recipient
    "last_message": String,  # Initialized ""; updated by ClientGateway.on_message_create() with content preview (truncated to 80 chars)
    "unread": bool,          # Initialized false; updated by Client.mark_channel_unread() on message_create
}
```

**Role Dict** (client_models.gd:362-372, `role_to_dict()`):
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

**Invite Dict** (client_models.gd:374-398, `invite_to_dict()`):
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

**Emoji Dict** (client_models.gd:400-413, `emoji_to_dict()`):
```
{
    "id": String,            # "" if null (unicode emoji)
    "name": String,
    "animated": bool,
    "role_ids": Array,       # Array of role ID strings
    "creator_id": String,    # "" if null
}
```

**Sound Dict** (client_models.gd:415-430, `sound_to_dict()`):
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

### Markdown to BBCode (client_models.gd:432-490)

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

### Timestamp Formatting (client_models.gd:68-132)

- Parses ISO 8601 strings (e.g., "2025-05-10T14:30:00Z")
- Extracts date and time portions, strips timezone suffix (Z/+/-) and milliseconds
- Converts to 12-hour format
- Compares parsed date against UTC system time:
  - Same day: "Today at H:MM AM/PM"
  - Previous day: "Yesterday at H:MM AM/PM"
  - Older: "MM/DD/YYYY H:MM AM/PM"
- Returns raw string if unparseable

### Caching Architecture (client.gd)

Seven caches:
- `_user_cache: Dictionary` -- keyed by user_id -> user dict. Evicted via `trim_user_cache()` when exceeding `USER_CACHE_CAP` (500); preserves current user, current space members, and current channel message authors.
- `_space_cache: Dictionary` -- keyed by space_id -> space dict
- `_channel_cache: Dictionary` -- keyed by channel_id -> channel dict
- `_dm_channel_cache: Dictionary` -- keyed by channel_id -> DM channel dict
- `_message_cache: Dictionary` -- keyed by channel_id -> Array of message dicts
- `_member_cache: Dictionary` -- keyed by space_id -> Array of member dicts
- `_role_cache: Dictionary` -- keyed by space_id -> Array of role dicts

Auxiliary indexes:
- `_message_id_index: Dictionary` -- message_id -> channel_id, maintained on message_create/delete and fetch_messages; enables O(1) lookups in `get_message_by_id()` and `_find_channel_for_message()`
- `_unread_channels: Dictionary` -- channel_id -> true, set on message_create when channel != current, cleared on channel_selected
- `_channel_mention_counts: Dictionary` -- channel_id -> int, incremented on message_create when current user is mentioned, cleared on channel_selected

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

Constants (client.gd:6-12):
- `MESSAGE_CAP := 50` -- max messages cached per channel
- `SPACE_ICON_SIZE := 48`, `AVATAR_SIZE := 42`, `CHANNEL_ICON_SIZE := 32`
- `CHANNEL_PANEL_WIDTH := 240`, `SPACE_BAR_WIDTH := 68`
- `TOUCH_TARGET_MIN := 44`
- `USER_CACHE_CAP := 500` -- max user cache entries before eviction (line 53)

## Implementation Status

- [x] ClientModels conversion layer (typed models -> dicts) for all 9 model types
- [x] ChannelType and UserStatus enums with bidirectional string conversion
- [x] Deterministic color palette from IDs
- [x] Seven in-memory caches (users, spaces, channels, DMs, messages, members, roles)
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
- [x] Attachment rendering in message_content.gd (filename link + file size)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `voice_users` always 0 | Medium | `channel_to_dict()` (line 208) includes a `voice_users: 0` placeholder but no voice state tracking is connected. AccordVoiceState model exists but gateway events for voice state aren't wired. `channel_item.gd` reads this field (line 61) |
| `folder` always empty | Low | `space_to_dict()` (line 178) hardcodes `folder: ""`. This is a client-side organizational feature (grouping servers into folders); the server has no folder concept. `guild_folder.gd` exists in the UI but folder assignment is not implemented |
| DM `last_message` only from gateway | Low | `dm_channel_to_dict()` (line 358) initializes `last_message: ""`. Only updated when a message_create gateway event arrives. On initial load, DM previews are blank until a new message is sent/received. Could pre-populate from `AccordChannel.last_message_id` by fetching the message |
| No image display for attachments | Low | `message_content.gd` renders attachments as clickable filename links with file sizes. Image attachments (content_type starts with "image/") could be rendered inline as actual images |
| Timestamps in UTC | Low | `_format_timestamp()` parses and displays UTC time directly. Users in non-UTC timezones see UTC times. Could convert to local time |
| Member cache limit | Low | `fetch_members()` requests limit=1000; large spaces may not fetch all members. No pagination implemented |
| Avatar image cache unbounded | Low | `avatar.gd` static `_image_cache` grows without limit. Could add an LRU eviction policy |
