# Forums

Priority: 48
Depends on: Message Threads, Channel Categories

## Overview

Forum channels present a threaded discussion view where each top-level message acts as a "post" with its own title and reply thread, similar to Discord's forum channels. A forum channel is a `FORUM`-type channel where the main view shows a post list (top-level messages with thread metadata) instead of a flat message feed, and clicking a post opens the thread panel to display its replies.

The forum system is fully implemented end-to-end: the client detects forum channel types and renders a dedicated post list view (`forum_view.gd`), the server supports `top_level=true` queries with sort options and enriches responses with `reply_count` and `last_reply_at`, and gateway events route thread replies and new posts to the correct caches.

## User Steps

### Browsing a Forum
1. User selects a space in the sidebar.
2. User clicks a forum channel (identified by the forum icon).
3. Instead of a flat message feed, the content area shows a **post list** — each row displays the post title, author, reply count, last activity timestamp, and a content preview.
4. User can scroll through posts; older posts load on demand.
5. A sort/filter bar at the top lets the user order posts by "Latest Activity", "Newest", or "Oldest".

### Reading a Post
1. User clicks a post row in the forum view.
2. The thread panel opens, showing the original post at the top and all replies below.
3. User scrolls through replies. Older replies load via the thread panel.
4. User can reply in the thread composer at the bottom of the panel.

### Creating a Post
1. User clicks the "New Post" button at the top of the forum view.
2. An inline post creation form appears with a title field and a body text area.
3. User fills in title and body, then clicks "Post".
4. The new post appears at the top of the post list.

### Deleting a Post
1. User right-clicks a post row.
2. Context menu shows "Open Thread" and "Delete Post" (delete only for own posts or users with `MANAGE_THREADS`).
3. Deleting removes the post and all its thread replies (server-side CASCADE).

### Replying in a Post
1. With a post's thread panel open, user types in the thread composer.
2. User presses Enter to send. The reply appears in the thread.
3. The post's reply count and last_reply_at update in the forum post list via gateway events.

## Signal Flow

```
User clicks forum channel in sidebar
    ├─> channel_list.gd: _on_channel_pressed(channel_id)
    │       emits channel_selected
    │
    ├─> AppState.select_channel(channel_id)
    │       emits channel_selected
    │
    └─> message_view.gd: _on_channel_selected(channel_id)
            detects ChannelType.FORUM (line 177)
            calls _enter_forum_mode(channel_id) (line 247)
            forum_view.load_forum(channel_id, channel_name)
                └─> Client.fetch.fetch_forum_posts(channel_id, sort)
                        GET /channels/{id}/messages?top_level=true&sort=latest_activity
                        └─> AppState.forum_posts_updated.emit(channel_id)
                                └─> forum_view._on_forum_posts_updated() → _render_posts()

User clicks a post row in forum view
    ├─> forum_post_row.gd: post_pressed.emit(message_id)
    │       └─> forum_view._on_post_pressed(message_id)
    │
    ├─> AppState.open_thread(message_id)
    │       sets current_thread_id, thread_panel_visible = true
    │       emits thread_opened
    │
    └─> thread_panel.gd: _on_thread_opened(parent_message_id)
            fetches parent message from cache
            calls Client.fetch.fetch_thread_messages(channel_id, parent_id)
                GET /channels/{id}/messages?thread_id={parent_id}
                └─> AppState.thread_messages_updated.emit(parent_id)

User clicks "New Post"
    ├─> forum_view.gd: _show_new_post_form()
    │       inline form with title LineEdit + body TextEdit
    │
    ├─> forum_view._on_create_post()
    │       Client.send_message_to_channel(channel_id, body, "", [], "", title)
    │       POST /channels/{id}/messages  { "content": "...", "title": "..." }
    │
    └─> Gateway: message.create (no thread_id, in forum channel)
            client_gateway.gd detects forum channel type
            inserts post into _forum_post_cache
            AppState.forum_posts_updated.emit(channel_id)

Thread reply arrives via gateway
    ├─> Gateway: message.create with thread_id
    │       client_gateway.gd appends to _thread_message_cache[thread_id]
    │       increments reply_count on parent in _forum_post_cache
    │       sets last_reply_at on parent in _forum_post_cache
    │       AppState.forum_posts_updated.emit(channel_id)
    │
    └─> Gateway: message.update on parent (server broadcasts)
            server sends updated parent with new reply_count
            client_gateway.gd updates _forum_post_cache entry
```

## Key Files

### Client — UI Components

| File | Role |
|------|------|
| `scenes/messages/forum_view.gd` | Forum post list controller: fetches posts via `Client.fetch.fetch_forum_posts()`, renders post rows, sort/filter, inline post creation form, context menu with delete |
| `scenes/messages/forum_view.tscn` | Forum view scene layout |
| `scenes/messages/forum_post_row.gd` | Individual post row: title, author, reply count, last activity, content preview; emits `post_pressed` and `context_menu_requested` signals |
| `scenes/messages/forum_post_row.tscn` | Post row scene layout |
| `scenes/messages/thread_panel.gd` | Thread panel: loads parent message + replies, thread composer, typing indicators, hides "Also send to channel" for forum threads (line 91-97), checks `SEND_IN_THREADS` permission |
| `scenes/messages/thread_panel.tscn` | Thread panel scene layout |
| `scenes/messages/message_view.gd:170-260` | Forum channel detection: checks `ChannelType.FORUM` (line 177), calls `_enter_forum_mode()` (line 247) to swap message list for forum view |

### Client — Data & API

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd:7` | `ChannelType.FORUM` enum value (index 3) |
| `scripts/autoload/client_models.gd:108-109` | `_channel_type_to_enum()` maps `"forum"` → `ChannelType.FORUM` |
| `scripts/autoload/client_models.gd:467-499` | `message_to_dict()` includes `thread_id`, `reply_count`, `last_reply_at`, `thread_participants`, `title` |
| `scripts/autoload/app_state.gd:127-137` | Thread/forum signals: `thread_opened`, `thread_closed`, `thread_messages_updated`, `thread_typing_started`, `thread_typing_stopped`, `forum_posts_updated` |
| `scripts/autoload/app_state.gd:229-231` | Thread state: `current_thread_id`, `thread_panel_visible` |
| `scripts/autoload/app_state.gd:398-406` | `open_thread()` and `close_thread()` methods |
| `scripts/autoload/client.gd:469-473` | `get_forum_posts(channel_id)` and `get_messages_for_thread(parent_id)` cache accessors |
| `scripts/autoload/client.gd:518-527` | `send_message_to_channel()` — 6th param `title` for forum posts |
| `scripts/autoload/client_fetch.gd:373-412` | `fetch_forum_posts(channel_id, sort)` — calls `list_posts()` with sort param, populates `_forum_post_cache` |
| `scripts/autoload/client_fetch.gd:334-371` | `fetch_thread_messages(channel_id, parent_message_id)` — calls `list_thread()`, reverses for oldest-first display |
| `scripts/autoload/client_gateway.gd:259-395` | `on_message_create()` — routes thread replies to `_thread_message_cache`, new forum posts to `_forum_post_cache`, updates parent `reply_count`/`last_reply_at` |
| `scripts/autoload/client_gateway.gd:396-431` | `on_message_update()` — updates thread cache and forum post cache |
| `scripts/autoload/client_gateway.gd:433-473` | `on_message_delete()` — removes from thread/forum caches, decrements parent reply_count |
| `scripts/autoload/client_gateway.gd:493-535` | `on_typing_start()` — thread-scoped typing indicators via `thread_typing_started` signal |
| `addons/accordkit/models/message.gd:27-31` | `thread_id`, `reply_count`, `last_reply_at`, `thread_participants`, `title` fields |
| `addons/accordkit/models/message.gd:117-131` | `from_dict()` parses all thread/forum fields |
| `addons/accordkit/rest/endpoints/messages_api.gd:104-106` | `list_thread()` — adds `thread_id` query param |
| `addons/accordkit/rest/endpoints/messages_api.gd:125-127` | `list_posts()` — adds `top_level=true` query param |
| `addons/accordkit/rest/endpoints/messages_api.gd:133-138` | `typing()` — supports optional `thread_id` for thread-scoped typing |
| `addons/accordkit/models/permission.gd:40-43` | `MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS` constants |

### Client — Admin & Sidebar

| File | Role |
|------|------|
| `scenes/sidebar/channels/channel_item.gd:8,50-51` | Preloads and displays `FORUM_ICON` for forum channels |
| `scenes/sidebar/channels/channel_list.gd:120-129` | Forum channels use `ChannelItemScene`; auto-select includes them |
| `scenes/admin/channel_management_dialog.gd:40,193` | "Forum" in create type dropdown, `type_map[3] = "forum"` |
| `scenes/admin/create_channel_dialog.gd:28,59` | "Forum" type option (id=3), `type_map[3] = "forum"` |
| `scenes/admin/channel_row.gd:56` | Displays `"F"` label for forum channels in admin list |
| `scenes/admin/channel_permissions_dialog.gd:273-276` | Forum grouped with TEXT/ANNOUNCEMENT for permission filtering |

### Server (accordserver)

| File | Role |
|------|------|
| `src/routes/messages.rs:17-24` | `ListMessagesQuery` struct: `top_level`, `sort`, `thread_id`, `after`, `limit` params |
| `src/routes/messages.rs:26-87` | `list_messages()` handler — branches on `top_level=true` for forum mode |
| `src/routes/messages.rs:121-259` | `create_message()` — validates `title` (non-empty, max 100 chars), stores `thread_id` |
| `src/routes/messages.rs:127-132` | Permission check: `send_messages` always, `send_in_threads` when `thread_id` present |
| `src/routes/messages.rs:182-211` | After thread reply creation, broadcasts `message.update` on parent with incremented `reply_count` |
| `src/routes/messages.rs:436-479` | `delete_message()` — author can delete own, otherwise requires `manage_messages` |
| `src/routes/messages.rs:697-706` | `list_active_threads()` — GET /channels/{id}/threads |
| `src/routes/messages.rs:683-695` | `get_thread_info()` — GET /channels/{id}/messages/{id}/threads |
| `src/routes/messages.rs:782-803` | `messages_to_json()` — includes `reply_count` for all messages |
| `src/routes/messages.rs:807-833` | `messages_to_forum_json()` — adds `last_reply_at` on top of regular fields |
| `src/db/messages.rs:104-146` | `list_forum_posts()` — `WHERE thread_id IS NULL`, sort by latest_activity/newest/oldest |
| `src/db/messages.rs:177-212` | `create_message()` — inserts `thread_id` and `title` columns |
| `src/db/messages.rs:412-423` | `get_thread_reply_count()` — `COUNT(*) WHERE thread_id = ?` |
| `src/db/messages.rs:150-175` | `get_last_reply_timestamps()` — `MAX(created_at) WHERE thread_id IN (...)` |
| `src/db/messages.rs:456-492` | `get_thread_metadata()` — reply_count, last_reply_at, participants |
| `src/models/message.rs:6-31` | `Message` struct: `thread_id`, `reply_count`, `title` fields |
| `src/models/permission.rs:47-50` | `create_threads`, `manage_threads`, `send_in_threads` in permission list |
| `migrations/009_threads.sql` | Adds `thread_id` column + index to messages table |
| `migrations/018_forum_title.sql` | Adds `title` column to messages table |

### Tests

| File | Role |
|------|------|
| `tests/unit/test_channel_item.gd:67-69` | Verifies forum icon assignment |
| `tests/unit/test_client_models.gd:89-90` | Verifies `"forum"` → `ChannelType.FORUM` mapping |

## Implementation Details

### Channel Type Recognition

The `FORUM` channel type is fully recognized end-to-end:

- **ClientModels** defines `ChannelType.FORUM` as enum value 3 (line 7) and maps `"forum"` strings to it (lines 108-109).
- **AccordChannel** stores `type` as a plain string (`"forum"`) from the server. The conversion to the typed enum happens in `ClientModels._channel_type_to_enum()`.
- **channel_item.gd** preloads `forum_channel.svg` (line 8) and displays it for `ChannelType.FORUM` (lines 50-51).
- **channel_list.gd** routes forum channels to `ChannelItemScene` (not `VoiceChannelItemScene`). Auto-select logic skips only `CATEGORY` and `VOICE`, so forum channels are selectable.
- **Server** stores channel type as a string (`"forum"`) with no special enum — the type distinction is purely at the query level (`top_level=true`).

### Forum View

When a forum channel is selected, `message_view.gd` detects `ChannelType.FORUM` (line 177) and calls `_enter_forum_mode()` (line 247), which hides the scroll container, typing indicator, and composer, then lazily instantiates and shows the forum view.

**forum_view.gd** manages the post list:
- `load_forum()` (line 178) triggers `Client.fetch.fetch_forum_posts(channel_id, sort)` which sends `GET /channels/{id}/messages?top_level=true&sort={sort}&limit={cap}`.
- `_render_posts()` (line 195) instantiates `ForumPostRow` scenes from cached data.
- `_sort_posts()` (line 221) applies client-side sorting as a secondary pass after the server sort.
- Sort dropdown maps indices to: `"latest_activity"` (0), `"newest"` (1), `"oldest"` (2).

**forum_post_row.gd** displays each post:
- `setup(data)` (line 111) extracts `title` (fallback to first line of content), `reply_count`, `last_reply_at` (fallback to `timestamp`), and content preview (truncated ~100 chars).
- Left-click emits `post_pressed`, right-click emits `context_menu_requested`.

### Post Creation

The inline form in `forum_view.gd` collects a title (LineEdit) and body (TextEdit). On submit (line 273):
```gdscript
Client.send_message_to_channel(_channel_id, body, "", [], "", post_title)
```
This sends `POST /channels/{id}/messages` with `{ "content": "...", "title": "..." }`.

**Server validation** (messages.rs lines 140-148): title must be non-empty and at most 100 characters.

### Thread Panel Integration

**thread_panel.gd** opens when a post is clicked:
- `_on_thread_opened()` (line 55) fetches the parent message, displays reply count, and fetches thread messages via `Client.fetch.fetch_thread_messages()`.
- For forum threads, hides the "Also send to channel" checkbox (lines 91-97) since forum posts are thread-only.
- Checks `SEND_IN_THREADS` permission (lines 101-109) before enabling the composer.
- Thread-scoped typing indicators: `Client.send_typing(channel_id, parent_message_id)` → server broadcasts with `thread_id` → client routes to `thread_typing_started` signal.

### Gateway Event Handling

**client_gateway.gd** handles all forum/thread events in `on_message_create()` (lines 259-395):

1. **Thread reply** (`thread_id` present): appends to `_thread_message_cache`, increments parent `reply_count` in both `_message_cache` and `_forum_post_cache`, updates `last_reply_at`, emits `forum_posts_updated` and `thread_messages_updated`.
2. **New forum post** (no `thread_id`, channel type is FORUM): inserts at position 0 in `_forum_post_cache`, emits `forum_posts_updated`.
3. **Server also broadcasts** a `message.update` event on the parent message with the new `reply_count` (messages.rs lines 182-211), providing a second confirmation path.

**on_message_update()** (lines 396-431) and **on_message_delete()** (lines 433-473) update thread/forum caches symmetrically.

### Client–Server API Contract

| Operation | Client Request | Server Handler | Response Fields |
|-----------|---------------|----------------|-----------------|
| List forum posts | `GET /channels/{id}/messages?top_level=true&sort=latest_activity&limit=50` | `list_messages()` → `list_forum_posts()` → `messages_to_forum_json()` | `reply_count`, `last_reply_at`, `title`, `thread_id: null` |
| List thread replies | `GET /channels/{id}/messages?thread_id={parent_id}` | `list_messages()` with `thread_id` filter | `thread_id`, `reply_count` |
| Create forum post | `POST /channels/{id}/messages` `{ "content": "...", "title": "..." }` | `create_message()` validates title (1-100 chars) | Created message + gateway broadcast |
| Create thread reply | `POST /channels/{id}/messages` `{ "content": "...", "thread_id": "..." }` | `create_message()` checks `send_in_threads` perm | Created reply + parent `message.update` broadcast |
| Delete post/reply | `DELETE /channels/{id}/messages/{msg_id}` | `delete_message()` checks author or `manage_messages` | Gateway `message.delete` broadcast |
| Thread metadata | `GET /channels/{id}/messages/{msg_id}/threads` | `get_thread_info()` → `get_thread_metadata()` | `reply_count`, `last_reply_at`, `participants` |
| Active threads | `GET /channels/{id}/threads` | `list_active_threads()` | Array of parent messages with replies |
| Thread typing | `POST /channels/{id}/typing` `{ "thread_id": "..." }` | Broadcasts typing with `thread_id` | Gateway typing event |

### Permission Model

| Permission | Client Constant | Server Constant | Where Enforced |
|-----------|----------------|-----------------|----------------|
| `MANAGE_THREADS` | `AccordPermission.MANAGE_THREADS` (line 40) | `manage_threads` (permission.rs line 47) | Client-side only: forum_view delete context menu (line 284) |
| `CREATE_THREADS` | `AccordPermission.CREATE_THREADS` (line 41) | `create_threads` (permission.rs line 48) | **Not enforced** on either side |
| `SEND_IN_THREADS` | `AccordPermission.SEND_IN_THREADS` (line 43) | `send_in_threads` (permission.rs line 50) | Server: checked on `create_message()` when `thread_id` present. Client: thread_panel composer gating (line 101) |

### Responsive Layout

| Layout Mode | Behavior |
|-------------|----------|
| FULL (>=768px) | Forum post list + thread panel side by side in ContentBody |
| MEDIUM (<768px) | Thread panel replaces member list when a post is open |
| COMPACT (<500px) | Thread panel is full-screen overlay with back button; forum_view adapts header (compact "+" button, smaller title), forum_post_row hides avatar/activity |

## Implementation Status

- [x] `FORUM` value in `ChannelType` enum (`client_models.gd:7`)
- [x] String-to-enum conversion for `"forum"` (`client_models.gd:108-109`)
- [x] Forum icon SVG (`theme/icons/forum_channel.svg`)
- [x] Forum icon displayed in sidebar channel items (`channel_item.gd:8,50-51`)
- [x] Forum as selectable type in Create Channel dialogs (`create_channel_dialog.gd:28`, `channel_management_dialog.gd:40`)
- [x] Forum type in API payload type maps (`create_channel_dialog.gd:59`, `channel_management_dialog.gd:193`)
- [x] Forum label "F" in admin channel row (`channel_row.gd:56`)
- [x] Forum grouped with text for permission filtering (`channel_permissions_dialog.gd:273-276`)
- [x] Thread permission constants (`MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS`)
- [x] Unit tests for forum icon and enum mapping
- [x] Forum post list view (`forum_view.tscn` + `forum_view.gd`)
- [x] Forum post row component (`forum_post_row.tscn` + `forum_post_row.gd`)
- [x] Post creation form (title + body) — inline in forum_view
- [x] Channel type detection in message_view to switch to forum layout (`message_view.gd:170-260`)
- [x] Thread panel with forum-specific behavior (`thread_panel.gd`)
- [x] Thread signals and state in AppState (`thread_opened`, `thread_closed`, `forum_posts_updated`)
- [x] `thread_id`, `reply_count`, `last_reply_at`, `thread_participants`, `title` fields on AccordMessage (`message.gd:27-31`)
- [x] Thread message fetch/send API endpoints (`list_posts()`, `list_thread()`, `get_thread_info()`, `list_active_threads()`)
- [x] Gateway handling for thread-aware message events — create, update, delete, typing (`client_gateway.gd`)
- [x] Forum post sort/filter controls — Latest Activity, Newest, Oldest (`forum_view.gd:221-242`)
- [x] Forum empty state ("No posts yet" with New Post button)
- [x] Forum-specific context menu items (Open Thread, Delete Post)
- [x] Permission checks for `MANAGE_THREADS` on delete (client-side)
- [x] `SEND_IN_THREADS` enforcement (server + client thread_panel)
- [x] Responsive layout for forum view + thread panel (FULL/MEDIUM/COMPACT)
- [x] Server-side forum/thread support: `top_level=true` query, `list_forum_posts()` with sort, `messages_to_forum_json()` with `last_reply_at`, reply_count broadcasts, `send_in_threads` enforcement, thread-scoped typing
- [x] Database schema: `thread_id` column + index (migration 009), `title` column (migration 018), PostgreSQL equivalents
- [x] Client forum post cache (`_forum_post_cache`) and thread message cache (`_thread_message_cache`)
- [x] Reply count live updates via gateway (both client-side increment and server `message.update` broadcast)
- [ ] Post editing UI (title + body inline edit)
- [ ] Post pinning/archiving UI (`archived`, `auto_archive_after` fields exist but unused)
- [ ] `CREATE_THREADS` permission enforcement (defined but not checked)
- [ ] `MANAGE_THREADS` server-side enforcement (client checks but server uses `manage_messages`)
- [ ] Forum post pagination (cursor-based `after` param supported by server but no "Load More" button in client)

## Interoperability Analysis

### Verified Compatible

| Area | Client | Server | Status |
|------|--------|--------|--------|
| Forum post listing | `list_posts()` sends `top_level=true` | `list_forum_posts()` filters `WHERE thread_id IS NULL` | Compatible |
| Sort parameter | Client sends `sort=latest_activity\|newest\|oldest` | Server accepts all three, defaults to `latest_activity` | Compatible |
| Post creation with title | Sends `{ "title": "...", "content": "..." }` | Validates title 1-100 chars, stores in `title` column | Compatible |
| Thread reply creation | Sends `{ "thread_id": "...", "content": "..." }` | Checks `send_in_threads` perm, stores `thread_id` FK | Compatible |
| Message model fields | Parses `thread_id`, `reply_count`, `last_reply_at`, `title` | Returns all four fields in JSON responses | Compatible |
| Gateway thread reply routing | Routes by `thread_id` presence to thread cache | Broadcasts `message.create` with `thread_id` intact | Compatible |
| Gateway forum post routing | Routes by channel type FORUM + no `thread_id` | New top-level forum post has `thread_id: null` | Compatible |
| Reply count live update | Gateway increments parent `reply_count` in cache | Broadcasts `message.update` on parent with new count | Compatible (dual path) |
| `last_reply_at` enrichment | Reads from forum post response | Only included in `messages_to_forum_json()` (forum mode) | Compatible |
| Thread-scoped typing | Sends `POST /typing` with `{ "thread_id": "..." }` | Broadcasts typing event with `thread_id` field | Compatible |
| Post deletion cascade | Removes from `_forum_post_cache` on `message.delete` | `ON DELETE CASCADE` on `thread_id` FK deletes all replies | Compatible |
| Thread metadata endpoint | `get_thread_info()` → `GET /messages/{id}/threads` | Returns `{ reply_count, last_reply_at, participants }` | Compatible |

### Permission Mismatch

| Permission | Client Behavior | Server Behavior | Issue |
|-----------|----------------|-----------------|-------|
| `MANAGE_THREADS` | Used to gate "Delete Post" in context menu | **Not checked** — server uses `manage_messages` for non-author deletes | Mismatch: client gates on wrong permission; user with `manage_messages` but not `manage_threads` can delete via API but not via UI |
| `CREATE_THREADS` | Defined but not checked anywhere | Defined but not checked anywhere | Both sides ignore it |

### Pagination Gap

The server supports cursor-based pagination (`after` param, `has_more` in response) for forum posts, but the client's `forum_view.gd` does not implement a "Load More" button. All posts are fetched in a single request limited by `MESSAGE_CAP`. For forums with many posts, this means only the most recent page is visible.

### Sort Double-Processing

The client passes `sort` to the server AND applies client-side sorting in `_sort_posts()` (forum_view.gd line 221). The server already returns posts in the requested order, so the client-side sort is redundant but harmless.

## Tasks

### FORUM-1: Compact layout forum UX
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** forum_view adapts header (compact "+" button, smaller title), forum_post_row hides avatar/activity in compact, thread_panel shows "← Back" button and drops min-width.

### FORUM-2: No post pinning or archiving
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** `AccordChannel` has `archived` and `auto_archive_after` fields (channel.gd lines 21-22) but no UI uses them. Server has no archiving endpoints.

### FORUM-3: Server-side forum support
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** general
- **Notes:** accordserver supports `title` field on messages, `top_level=true` query param with sort options, `list_forum_posts()` with cursor pagination, `messages_to_forum_json()` with `last_reply_at`, thread reply count broadcasts, `send_in_threads` permission enforcement, and thread-scoped typing indicators.

### FORUM-4: Edit post UI
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** No inline edit for forum post title+body. Server supports `PATCH /messages/{id}` with `title` field. Users can edit content via the thread panel but cannot change the title.

### FORUM-5: Permission alignment
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** general
- **Notes:** Client gates post deletion on `MANAGE_THREADS` but server checks `manage_messages`. Either the client should check `manage_messages` or the server should add a `manage_threads` check for forum post operations. `CREATE_THREADS` is unused on both sides.

### FORUM-6: Forum post pagination
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** Server supports cursor pagination (`after`/`has_more`) but client fetches only one page. Forums with many posts need a "Load More" button in forum_view.
