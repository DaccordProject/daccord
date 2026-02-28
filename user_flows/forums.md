# Forums

## Overview

Forum channels present a threaded discussion view where each top-level message acts as a "post" with its own title and reply thread, similar to Discord's forum channels. Forums piggyback on the message threads feature (see [Message Threads](message_threads.md)) — a forum channel is a `FORUM`-type channel where the main view shows a post list (top-level messages with thread metadata) instead of a flat message feed, and clicking a post opens the thread panel to display its replies.

Currently, the `FORUM` channel type is recognized throughout the codebase (enum, icon, sidebar, admin dialogs) but selecting a forum channel renders it identically to a text channel — a flat message list with no post-style layout, no thread panel, and no "create post" flow.

## User Steps

### Browsing a Forum
1. User selects a space in the sidebar.
2. User clicks a forum channel (identified by the forum icon).
3. Instead of a flat message feed, the content area shows a **post list** — each row displays the post title, author, reply count, last activity timestamp, and a content preview.
4. User can scroll through posts; older posts load on demand.
5. A sort/filter bar at the top lets the user order posts by "Latest Activity", "Newest", or "Oldest".

### Reading a Post
1. User clicks a post row in the forum view.
2. The thread panel opens (reusing the thread panel from Message Threads), showing the original post at the top and all replies below.
3. User scrolls through replies. Older replies load via a "Show older replies" button.
4. User can reply in the thread composer at the bottom of the panel.

### Creating a Post
1. User clicks the "New Post" button at the top of the forum view.
2. A post creation form appears with a title field and a rich text body field.
3. User fills in title and body, then clicks "Post".
4. The new post appears at the top of the post list (or sorted by the current filter).
5. Optionally, the thread panel opens automatically for the new post.

### Editing / Deleting a Post
1. User right-clicks their own post row (or hovers for the action bar).
2. Context menu shows "Edit Post" and "Delete Post" (only for own posts or users with `MANAGE_THREADS`).
3. Editing opens an inline title + body editor. Deleting prompts a confirmation dialog.

### Replying in a Post
1. With a post's thread panel open, user types in the thread composer.
2. User presses Enter to send. The reply appears in the thread.
3. The post's reply count updates in the forum post list.

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
            [CURRENT] renders flat message list (no forum distinction)
            [PLANNED] detects FORUM type → switches to forum post list view

User clicks a post row in forum view (planned)
    ├─> forum_view.gd: emits post_selected(parent_message_id)
    │
    ├─> AppState.open_thread(parent_message_id)
    │       sets current_thread_id, thread_panel_visible = true
    │       emits thread_opened
    │
    └─> thread_panel.gd: loads parent message + thread replies

User clicks "New Post" (planned)
    ├─> forum_view.gd: shows post creation form
    │
    ├─> Client.send_message_to_channel(channel_id, content, ...)
    │       POST /channels/{id}/messages  with { title: "..." }
    │
    └─> Gateway: message_create
            forum_view appends new post to list
```

## Key Files

### Existing Files (already reference FORUM)

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd:7` | `ChannelType.FORUM` enum value (index 3) |
| `scripts/autoload/client_models.gd:108-109` | `_channel_type_to_enum()` maps `"forum"` string to `ChannelType.FORUM` |
| `scripts/autoload/app_state.gd` | Signal bus — needs thread signals for forum post open/close |
| `scripts/autoload/client.gd` | Data access and API routing — needs forum-aware message fetching |
| `scripts/autoload/client_gateway.gd` | Gateway event handler — needs thread metadata on `message_create` |
| `addons/accordkit/models/channel.gd:21-22` | `archived` and `auto_archive_after` fields (thread/forum concepts) |
| `addons/accordkit/models/message.gd` | Message model — needs `thread_id`, `reply_count`, title fields for posts |
| `addons/accordkit/models/permission.gd:40-43` | `MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS` constants |
| `addons/accordkit/rest/endpoints/messages_api.gd:16-24` | `list()` — thread-filtered listing needs `thread_id` query param |
| `scenes/sidebar/channels/channel_item.gd:8,50-51` | Preloads and displays `FORUM_ICON` for forum channels |
| `scenes/sidebar/channels/channel_list.gd:120-129` | Forum channels use `ChannelItemScene` (same as text); auto-select includes them (line 162) |
| `scenes/messages/message_view.gd:131-149` | `_on_channel_selected()` — currently calls `fetch_messages()` with no forum distinction |
| `scenes/messages/message_view_actions.gd:21-29` | Context menu — needs "Start Thread" / "View Thread" items for forum posts |
| `scenes/messages/message_action_bar.gd` | Action bar — needs thread button |
| `scenes/messages/cozy_message.gd:35-67` | Message row — needs thread reply count indicator for forum post display |
| `scenes/admin/channel_management_dialog.gd:40,193` | "Forum" in create type dropdown, `type_map[3] = "forum"` |
| `scenes/admin/create_channel_dialog.gd:28,59` | "Forum" type option (id=3), `type_map[3] = "forum"` |
| `scenes/admin/channel_row.gd:56` | Displays `"F"` label for forum channels in admin list |
| `scenes/admin/channel_permissions_dialog.gd:273-276` | Forum channels grouped with TEXT/ANNOUNCEMENT for permission filtering (hides voice-only perms) |
| `scenes/main/main_window.gd:40-42` | `content_body` HBoxContainer — thread panel will be added here |
| `tests/unit/test_channel_item.gd:67-69` | Test verifies forum icon assignment |
| `tests/unit/test_client_models.gd:89-90` | Test verifies `"forum"` → `ChannelType.FORUM` mapping |

### New Files (to be created)

| File | Role |
|------|------|
| `scenes/messages/forum_view.gd` | Forum post list controller: fetches top-level messages, renders post rows, handles sort/filter, emits `post_selected` |
| `scenes/messages/forum_view.tscn` | Forum view scene: sort bar, ScrollContainer with post list VBox, "New Post" button |
| `scenes/messages/forum_post_row.gd` | Individual post row: title, author, reply count, last activity, content preview |
| `scenes/messages/forum_post_row.tscn` | Post row scene layout |
| `scenes/messages/thread_panel.gd` | Thread panel controller (shared with Message Threads): loads parent message + thread replies |
| `scenes/messages/thread_panel.tscn` | Thread panel scene (shared with Message Threads) |

## Implementation Details

### Channel Type Recognition (Already Implemented)

The `FORUM` channel type is fully recognized:

- **ClientModels** defines `ChannelType.FORUM` as enum value 3 (line 7) and maps `"forum"` strings to it (lines 108-109).
- **AccordChannel** stores `type` as a plain string (`"forum"`) from the server (channel.gd line 7). The conversion to the typed enum happens in `ClientModels._channel_type_to_enum()`.
- **channel_item.gd** preloads `forum_channel.svg` (line 8) and displays it for `ChannelType.FORUM` (lines 50-51). Forum channels are otherwise treated identically to text channels.
- **channel_list.gd** routes forum channels to `ChannelItemScene` (not `VoiceChannelItemScene`) at line 125. Auto-select logic (lines 160-166) skips only `CATEGORY` and `VOICE`, so forum channels are selectable.

### Admin Channel Creation (Already Implemented)

Forum channels can be created via admin dialogs:

- **channel_management_dialog.gd** adds "Forum" as type option id=3 (line 40) and maps index 3 to `"forum"` in the API payload (line 193).
- **create_channel_dialog.gd** adds "Forum" as type option id=3 (line 28) with `type_map[3] = "forum"` (line 59).
- **channel_row.gd** displays `"F"` for forum type in the admin channel list (line 56).

### Permission Foundation (Already Implemented)

Thread/forum permissions exist but are not enforced client-side:

- **AccordPermission** defines `MANAGE_THREADS` (line 40), `CREATE_THREADS` (line 41), and `SEND_IN_THREADS` (line 43). These are included in `all()` (lines 83-86).
- **channel_permissions_dialog.gd** groups FORUM with TEXT and ANNOUNCEMENT for permission filtering (lines 273-276), hiding voice-only permissions.
- **accordserver** recognizes `manage_threads`, `create_threads`, and `send_in_threads` in its permission model (permission.rs lines 47-50).

### Message View — Current Behavior (Forum Gap)

When a forum channel is selected, `message_view.gd` handles it identically to a text channel:

1. `_on_channel_selected()` (line 131) calls `Client.fetch.fetch_messages(channel_id)` (line 149) — no channel type check.
2. `_load_messages()` (line 189) renders all messages as cozy/collapsed rows — no post-list layout.
3. The composer (line 37) shows a standard text input — no "New Post" button or title field.

The planned change: `message_view.gd` should check the channel type and, for FORUM channels, delegate to a `forum_view` that displays a post list instead of the flat message list.

### Forum View (Planned)

The forum view replaces the flat message list when a FORUM channel is selected:

```
ForumView (PanelContainer)
└── VBox
    ├── Header (HBoxContainer)
    │   ├── Title (Label) — "# forum-name"
    │   ├── SortDropdown (OptionButton) — "Latest Activity" / "Newest" / "Oldest"
    │   └── NewPostButton (Button) — "New Post"
    ├── ScrollContainer
    │   └── PostList (VBoxContainer)
    │       ├── ForumPostRow (post 1)
    │       ├── ForumPostRow (post 2)
    │       └── ...
    └── LoadMoreButton (Button) — pagination
```

Each `ForumPostRow` displays:
- Post title (from a new `title` field on the message, or the first line of content as fallback)
- Author avatar + name
- Reply count (from `reply_count` thread metadata)
- Last activity timestamp (from `last_reply_at`)
- Content preview (first ~100 characters of the post body)

### Thread Integration (Builds on Message Threads)

Forums reuse the thread panel from the Message Threads feature:

1. Clicking a post row calls `AppState.open_thread(post_message_id)`.
2. The thread panel (shared scene) opens alongside the forum view in `main_window`'s `ContentBody`.
3. Thread replies are fetched via `GET /channels/{id}/messages?thread_id={parent_id}`.
4. Sending a reply in the thread composer posts with `{ "thread_id": parent_id }`.

This means the thread panel, thread signals, and thread API work described in [Message Threads](message_threads.md) is a **prerequisite** for forums.

### AccordMessage Model Changes (Shared with Threads)

The message model needs fields for both threads and forums:

```gdscript
var thread_id = null         # parent message ID if this is a thread reply
var reply_count: int = 0     # number of thread replies (on parent/post messages)
var last_reply_at = null     # ISO timestamp of latest reply
var title = null             # post title (forum channels only)
```

`from_dict()` should parse these from the server response. `ClientModels.message_to_dict()` should expose them in the UI dictionary:

```gdscript
"thread_id": str(msg.thread_id) if msg.thread_id else "",
"reply_count": msg.reply_count,
"last_reply_at": str(msg.last_reply_at) if msg.last_reply_at else "",
"title": str(msg.title) if msg.title else "",
```

### REST API Changes

Forum posts use the existing messages endpoint with forum-aware parameters:

```gdscript
# List top-level posts in a forum channel (no thread_id = top-level only)
# GET /channels/{forum_channel_id}/messages?top_level=true&sort=latest_activity
func list_posts(channel_id: String, query: Dictionary = {}) -> RestResult:
    query["top_level"] = "true"
    return await list(channel_id, query)

# Create a forum post (message with a title)
# POST /channels/{forum_channel_id}/messages  { "title": "...", "content": "..." }
```

### Gateway Event Handling

Gateway events for forum channels need special handling in `client_gateway.gd`:

- **message_create** with a `thread_id` field: update the parent post's `reply_count` in the cache; if the thread panel is open for that post, append the reply.
- **message_create** without `thread_id` in a forum channel: add a new post row to the forum view.
- **message_update**: update post title/content if the message is a top-level forum post.
- **message_delete**: remove post from forum view or reply from thread panel.

### Responsive Layout

| Layout Mode | Behavior |
|-------------|----------|
| FULL (>=768px) | Forum post list + thread panel side by side in ContentBody |
| MEDIUM (<768px) | Thread panel replaces member list when a post is open |
| COMPACT (<500px) | Thread panel is full-screen overlay with back button; forum post list fills content area |

### Forum-Specific UI Details

**Post list empty state**: When a forum channel has no posts, show "No posts yet. Start the conversation!" with a prominent "New Post" button.

**Post creation form**: A modal dialog or inline form at the top of the forum view with:
- Title field (required, max ~100 characters)
- Body text area (same markdown support as the composer)
- "Post" button and "Cancel" button

**Sort/filter options**:
- Latest Activity (default) — sorted by `last_reply_at` descending
- Newest — sorted by post creation `timestamp` descending
- Oldest — sorted by post creation `timestamp` ascending

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
- [x] Channel type detection in message_view to switch to forum layout
- [x] Thread panel (prerequisite — see Message Threads)
- [x] Thread signals and state in AppState (prerequisite — see Message Threads)
- [x] `thread_id`, `reply_count`, `title` fields on AccordMessage
- [x] Thread message fetch/send API endpoints (`list_posts()`, `list_thread()`)
- [x] Gateway handling for thread-aware message events (forum post create/update/delete)
- [x] Forum post sort/filter controls (Latest Activity, Newest, Oldest)
- [x] Forum empty state ("No posts yet" with New Post button)
- [x] Forum-specific context menu items (Open Thread, Delete Post)
- [x] Permission checks for `MANAGE_THREADS` on delete
- [x] Responsive layout for forum view + thread panel
- [ ] Server-side forum/thread support in accordserver

## Tasks

### FORUM-1: Compact layout forum UX
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** : forum_view adapts header (compact "+" button, smaller title), forum_post_row hides avatar/activity in compact, thread_panel shows "\u2190 Back" button and drops min-width.

### FORUM-2: No post pinning or archiving
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** `AccordChannel` has `archived` and `auto_archive_after` fields (channel.gd lines 21-22) but no UI uses them.

### FORUM-3: Server-side forum support missing
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** general
- **Notes:** accordserver needs to support `title` field on messages and the `top_level=true` query param for listing forum posts. Until then, `list_posts()` falls back to listing all messages in the channel.

### FORUM-4: Edit post UI
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** No inline edit for forum post title+body. Users can edit content via the thread panel.
