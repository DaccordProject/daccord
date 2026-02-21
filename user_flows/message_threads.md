# Message Threads

## Overview

Message threads allow users to branch off a conversation from a specific message in a channel, keeping focused discussions contained without cluttering the main message feed. Threads behave like Slack-style threads: clicking "Start Thread" or "Reply in Thread" on any message opens a side panel showing the parent message and its thread replies, with its own composer for sending threaded messages. Thread activity is summarized inline in the main channel as a compact reply count indicator.

The implementation uses a simple `thread_id` column on the messages table. A message with `thread_id = NULL` is a normal channel message. A message with `thread_id` set to a parent message ID is a thread reply. The main channel feed excludes thread replies (`AND thread_id IS NULL`), keeping the conversation uncluttered.

## User Steps

### Starting a Thread
1. User hovers over a message in the channel — the action bar appears.
2. User clicks the "Thread" button (or right-clicks and selects "Start Thread" from the context menu).
3. A thread panel slides open to the right of the message view, showing the parent message at the top.
4. User types a reply in the thread composer and presses Enter to send.
5. The parent message in the main channel updates to show "1 reply" with the latest reply preview.

### Viewing an Existing Thread
1. User sees a "N replies" indicator beneath a message in the main channel.
2. User clicks the reply count indicator.
3. The thread panel opens, showing the parent message and all thread replies in chronological order.
4. User can scroll up to see older thread replies.

### Replying in a Thread
1. User opens a thread (via action bar, context menu, or reply count indicator).
2. User types in the thread composer at the bottom of the thread panel.
3. User presses Enter to send. The message appears in the thread.
4. Optionally, user checks "Also send to channel" to cross-post the reply to the main channel feed.

### Closing a Thread
1. User clicks the X button in the thread panel header (or presses Escape).
2. The thread panel closes; the main message view expands to fill the space.

## Signal Flow

```
User clicks "Thread" on message
    ├─> message_view_actions.gd (line 28, context menu id=5)
    │   or message_action_bar.gd (line 6, action_thread signal)
    │       → message_view_actions.on_bar_thread(msg_data) (line 53)
    │
    ├─> AppState.open_thread(parent_message_id) (line 284)
    │       sets current_thread_id, thread_panel_visible = true
    │       emits thread_opened (line 110)
    │
    ├─> main_window.gd._on_thread_opened() (line 353)
    │       hides member list (FULL/MEDIUM) or message view (COMPACT)
    │
    └─> thread_panel.gd._on_thread_opened() (line 28)
            fetches thread messages via Client.fetch.fetch_thread_messages()
            renders parent message + thread replies
            focuses thread composer

User sends message in thread composer
    ├─> thread_panel._on_send() (line 118)
    │
    ├─> Client.send_message_to_channel(channel_id, text, "", [], thread_id) (line 361)
    │       → ClientMutations.send_message_to_channel() (line 64)
    │           POST /channels/{id}/messages with { thread_id: parent_id }
    │
    └─> Gateway: message_create (with thread_id in payload)
            ├─> client_gateway.on_message_create() detects thread_id (line 188)
            │       routes to _thread_message_cache
            │       increments parent message reply_count
            │       marks _thread_unread if panel not open
            ├─> AppState.thread_messages_updated(parent_id) (line 213)
            └─> AppState.messages_updated(parent_channel) (line 207)

User clicks X on thread panel (or presses Escape)
    └─> AppState.close_thread() (line 289)
            sets current_thread_id = "", thread_panel_visible = false
            emits thread_closed (line 112)
            → main_window._on_thread_closed() restores layout
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Thread signals (lines 110-114), state vars (lines 159-160), `open_thread()`/`close_thread()` methods (lines 284-293) |
| `scripts/autoload/client.gd` | Thread message cache `_thread_message_cache` (line 88), unread tracking `_thread_unread` (line 89), `get_messages_for_thread()` (line 326), `send_message_to_channel()` with `thread_id` param (line 361) |
| `scripts/autoload/client_fetch.gd` | `fetch_thread_messages()` (line 268), `fetch_active_threads()` (line 305) |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` accepts `thread_id` param (line 64), includes in POST data |
| `scripts/autoload/client_gateway.gd` | Thread reply routing in `on_message_create()` (lines 187-214), thread-aware `on_message_update()` (lines 273-295), thread-aware `on_message_delete()` (lines 297-325) |
| `scripts/autoload/client_models.gd` | Thread fields in `message_to_dict()` return dictionary (lines 399-426) |
| `scripts/autoload/config.gd` | Thread notification settings `get_thread_notifications()`/`set_thread_notifications()` (lines 405-413) |
| `addons/accordkit/models/message.gd` | `thread_id` (line 27), `reply_count` (line 28), `last_reply_at` (line 29), `thread_participants` (line 30), `from_dict()` parsing (lines 116-128) |
| `addons/accordkit/models/permission.gd` | `MANAGE_THREADS` (line 40), `CREATE_THREADS` (line 41), `SEND_IN_THREADS` (line 43) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `list_thread()` (line 136), `get_thread_info()` (line 143), `list_active_threads()` (line 149) |
| `scenes/messages/thread_panel.gd` | Thread panel controller: loads parent message, renders thread replies, manages composer |
| `scenes/messages/thread_panel.tscn` | Thread panel scene: header, parent message container, scroll area, composer with "Also send to channel" checkbox |
| `scenes/messages/cozy_message.gd` | Thread indicator setup in `setup()` (lines 71-85), click handler `_on_thread_indicator_input()` (line 159) |
| `scenes/messages/cozy_message.tscn` | ThreadIndicator HBoxContainer with ThreadIcon and ThreadCountLabel |
| `scenes/messages/message_view_actions.gd` | "Start Thread" context menu item (line 28), `on_bar_thread()` handler (line 53) |
| `scenes/messages/message_action_bar.gd` | `action_thread` signal (line 6), `thread_btn` reference (line 17) |
| `scenes/messages/message_action_bar.tscn` | ThreadButton between ReplyButton and EditButton |
| `scenes/messages/message_view.gd` | Wires `action_thread` to `_actions.on_bar_thread` (line 103) |
| `scenes/main/main_window.gd` | `thread_panel` onready (line 42), signal connections (line 70), `_on_thread_opened()` (line 353), `_on_thread_closed()` (line 364), responsive layout handling |
| `scenes/main/main_window.tscn` | ThreadPanel instance in ContentBody between MessageView and MemberList |
| `theme/icons/thread.svg` | Thread icon (chat bubble with horizontal line) |
| `scenes/admin/channel_permissions_dialog.gd` | Thread permissions in `TEXT_ONLY_PERMS` (lines 22-23) |

### Backend Files (accordserver)

| File | Role |
|------|------|
| `migrations/009_threads.sql` | Adds `thread_id` column and index to messages table |
| `src/models/message.rs` | `thread_id: Option<String>` and `reply_count: Option<i64>` on Message, `thread_id` on MessageRow and CreateMessage |
| `src/db/messages.rs` | Thread-aware queries: `list_messages()` filters by thread_id, `get_thread_reply_count()`, `get_thread_reply_counts()` (batch), `get_thread_metadata()`, `list_active_threads()` |
| `src/routes/messages.rs` | `thread_id` in ListMessagesQuery, `get_thread_info()` handler, `list_active_threads()` handler, reply_count in JSON serialization |
| `src/routes/mod.rs` | Thread info and active threads routes |

## Implementation Details

### Reply System (Foundation)

The existing reply system provides the infrastructure threads build on:

- **AppState** tracks `replying_to_message_id` (line 144) with signals `reply_initiated` (line 7) and `reply_cancelled` (line 8).
- **AccordMessage** has a `reply_to` field (line 22) parsed from either `message.reply_to` or `message.message_reference.message_id` for Discord compatibility.
- **CozyMessage** renders a reply reference header showing the original message author and a 50-character content preview (lines 52-65), fetching the original message via REST if not cached (lines 102-125).
- **MessageActionBar** has a reply button emitting `action_reply` (line 3).

### Thread Data Model

**AccordMessage** (message.gd) has four thread-related fields:
- `thread_id` (line 27) — parent message ID if this is a thread reply, `null` otherwise
- `reply_count` (line 28) — number of replies in thread (populated on parent messages)
- `last_reply_at` (line 29) — ISO timestamp of latest thread reply
- `thread_participants` (line 30) — array of user IDs who have replied

`from_dict()` parses these from the server response (lines 116-128). `to_dict()` includes them when non-null.

**ClientModels.message_to_dict()** (lines 399-426) converts these to the UI dictionary shape:
- `thread_id`: String (empty string if null)
- `reply_count`: int
- `last_reply_at`: String (empty string if null)
- `thread_participants`: Array

### Thread Permissions

AccordPermission defines three thread-related constants (permission.gd lines 40-43):
- `MANAGE_THREADS` — manage and delete other users' threads
- `CREATE_THREADS` — start new threads on messages
- `SEND_IN_THREADS` — post messages in existing threads

These are classified as text-only permissions in the channel permissions dialog (channel_permissions_dialog.gd lines 22-23). Client-side permission checks are not yet enforced.

### AppState Thread Management

Signals (lines 110-114):
- `thread_opened(parent_message_id: String)` — emitted when user opens a thread
- `thread_closed()` — emitted when user closes the thread panel
- `thread_messages_updated(parent_message_id: String)` — emitted when thread messages change

State variables (lines 159-160):
- `current_thread_id: String` — ID of the currently open thread's parent message
- `thread_panel_visible: bool` — whether the thread panel is showing

Methods:
- `open_thread(parent_message_id)` (line 284) — sets state and emits `thread_opened`
- `close_thread()` (line 289) — clears state and emits `thread_closed`

### Thread Panel UI

The thread panel (`thread_panel.tscn`) is a PanelContainer with `custom_minimum_size.x = 340`, initially hidden. Located in `main_window.tscn`'s ContentBody between MessageView and MemberList.

Panel structure:
```
ThreadPanel (PanelContainer, visible = false)
└── VBox (VBoxContainer)
    ├── Header (HBoxContainer, min_height 40)
    │   ├── ThreadTitle (Label) — "Thread"
    │   └── CloseButton (Button, flat) — "X"
    ├── HSeparator
    ├── ParentMessageContainer (MarginContainer) — instantiates CozyMessage for parent
    ├── HSeparator
    ├── ReplyCountLabel (Label) — "N replies" (blue, font_size 12)
    ├── ScrollContainer (v_expand)
    │   └── ThreadMessageList (VBoxContainer) — thread reply messages
    └── ComposerBox (VBoxContainer)
        ├── HBox: ThreadInput (TextEdit) + SendButton (Button)
        └── AlsoSendCheck (CheckBox) — "Also send to channel"
```

The controller (`thread_panel.gd`):
- Connects to `AppState.thread_opened`, `thread_closed`, `thread_messages_updated` in `_ready()` (lines 24-26)
- `_on_thread_opened()` (line 28): Shows panel, loads parent message as CozyMessage instance, fetches thread replies via `Client.fetch.fetch_thread_messages()`, clears unread marker, focuses input
- `_render_thread_messages()` (line 80): Renders thread replies using CozyMessage/CollapsedMessage scenes (collapsed when consecutive same-author messages), scrolls to bottom
- `_on_send()` (line 118): Sends via `Client.send_message_to_channel()` with `thread_id` param; optionally sends a copy without `thread_id` if "Also send to channel" is checked
- `_on_input_key()` (line 135): Enter to send, Escape to close panel

### Client Thread Caching

**Client** (client.gd):
- `_thread_message_cache: Dictionary` (line 88) — maps `{ parent_message_id -> Array[message_dict] }`
- `_thread_unread: Dictionary` (line 89) — maps `{ parent_message_id -> true }` for threads with unread messages
- `get_messages_for_thread(parent_id)` (line 326) — returns cached thread messages

**ClientFetch** (client_fetch.gd):
- `fetch_thread_messages(channel_id, parent_message_id)` (line 268) — calls `client.messages.list_thread()`, caches result in `_thread_message_cache`, emits `AppState.thread_messages_updated`
- `fetch_active_threads(channel_id)` (line 305) — calls `client.messages.list_active_threads()`, returns array of parent message dicts with thread metadata

**ClientMutations** (client_mutations.gd):
- `send_message_to_channel()` accepts optional `thread_id: String = ""` param (line 64), includes in POST data when non-empty

### Gateway Event Handling

**on_message_create** (client_gateway.gd, lines 187-214):
1. Checks if message has `thread_id` (line 188)
2. If thread reply: adds to `_thread_message_cache[tid]` (line 199), increments parent message's `reply_count` (line 205), marks `_thread_unread[tid]` if panel not open (line 210), emits `thread_messages_updated` (line 213), then returns without adding to main channel cache
3. Normal messages proceed through existing flow

**on_message_update** (lines 273-295): Checks for `thread_id` — if present, updates in `_thread_message_cache` and emits `thread_messages_updated`; otherwise updates in main cache

**on_message_delete** (lines 297-325): Iterates `_thread_message_cache` to find deleted message — if found, removes it, decrements parent's `reply_count`, and emits `thread_messages_updated`; otherwise removes from main cache

### REST API Endpoints

**MessagesApi** (messages_api.gd):
- `list_thread(channel_id, parent_message_id, query)` (line 136) — `GET /channels/{cid}/messages?thread_id={parent_id}`
- `get_thread_info(channel_id, message_id)` (line 143) — `GET /channels/{cid}/messages/{mid}/threads`
- `list_active_threads(channel_id)` (line 149) — `GET /channels/{cid}/threads`

**Server endpoints** (accordserver):
- `GET /channels/{cid}/messages` — accepts optional `thread_id` query param; excludes thread replies from main feed when not specified
- `POST /channels/{cid}/messages` — accepts `thread_id` in body to create thread replies
- `GET /channels/{cid}/messages/{mid}/threads` — returns `{ reply_count, last_reply_at, participants }`
- `GET /channels/{cid}/threads` — returns all parent messages with active threads

### Message View Integration

**Context menu** — `message_view_actions.gd` adds "Start Thread" as item id=5 (line 28). Handler calls `AppState.open_thread(msg_id)`.

**Action bar** — `message_action_bar.gd` has `action_thread` signal (line 6) and ThreadButton (line 17) between Reply and Edit. Connected in `message_view.gd` (line 103) via `_actions.on_bar_thread()` (message_view_actions.gd line 53).

**Thread indicator** — `cozy_message.gd` checks `data.get("reply_count", 0)` in `setup()` (lines 71-85). When > 0, shows ThreadIndicator HBoxContainer with blue reply count text and a pointing-hand cursor. Click handler `_on_thread_indicator_input()` (line 159) calls `AppState.open_thread()`. Unread threads show a brighter blue color (line 80).

### Main Window Layout

`main_window.gd` connects to `AppState.thread_opened` and `AppState.thread_closed` (line 70):

**`_on_thread_opened()`** (line 353): Hides member list in FULL/MEDIUM mode; hides message view in COMPACT mode (thread panel takes over).

**`_on_thread_closed()`** (line 364): Restores member list visibility via `_update_member_list_visibility()` in FULL/MEDIUM; restores message view visibility in COMPACT.

**`_update_member_list_visibility()`** checks `AppState.thread_panel_visible` — when the thread panel is open, member list is hidden regardless of `AppState.member_list_visible`.

**`_on_layout_mode_changed()`**: In COMPACT mode, if thread is open, hides message view and shows thread panel.

### Responsive Behavior

| Layout Mode | Behavior |
|-------------|----------|
| FULL (>=768px) | Thread panel shown alongside message view; member list hidden when thread is open |
| MEDIUM (<768px) | Thread panel replaces member list area; member list hidden when thread is open |
| COMPACT (<500px) | Thread panel replaces message view entirely (message_view.visible = false) |

### Thread Notification Settings

Config (config.gd) provides per-thread notification preferences:
- `get_thread_notifications(thread_id)` (line 405) — returns mode: "default", "all", "mentions", or "none"
- `set_thread_notifications(thread_id, mode)` (line 408) — persists the notification mode

Default behavior ("default") follows the channel's notification settings.

### Thread Unread Tracking

- `Client._thread_unread` (line 89) tracks which threads have unread messages
- Gateway marks a thread as unread when a reply arrives and the panel is not open for that thread (client_gateway.gd line 210)
- Thread panel clears unread marker when opened (thread_panel.gd line 58)
- Cozy message thread indicator shows brighter blue color for unread threads (cozy_message.gd line 80)

## Implementation Status

- [x] Inline reply system (`reply_to` field, reply bar in composer, reply reference in cozy messages)
- [x] Thread permission constants (`MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS`)
- [x] Thread permissions in channel permission management UI (text-only permissions)
- [x] Thread data model fields on `AccordMessage` (`thread_id`, `reply_count`, `last_reply_at`, `thread_participants`)
- [x] Thread dictionary shape in `ClientModels.message_to_dict()`
- [x] AppState thread signals and state (`thread_opened`, `thread_closed`, `current_thread_id`)
- [x] Thread panel UI scene (`thread_panel.tscn` + `thread_panel.gd`)
- [x] Thread composer (send in thread context)
- [x] Thread reply count indicator on parent messages in main channel
- [x] "Start Thread" in context menu and action bar
- [x] REST API thread message endpoints (server-side: migration, model, queries, routes)
- [x] Gateway thread event handling (create, update, delete)
- [x] Thread unread indicators (blue highlight on cozy message thread indicator)
- [x] "Also send to channel" cross-post toggle
- [x] Thread notification settings (per-thread config persistence)
- [x] Thread message caching and cache management
- [x] Responsive layout (FULL/MEDIUM/COMPACT thread panel behavior)
- [ ] Thread list view UI (active threads panel — backend endpoint exists, client fetch method exists, no UI)
- [ ] Thread notification settings UI (bell icon in thread panel header)
- [ ] Client-side permission checks for `CREATE_THREADS` / `SEND_IN_THREADS`
- [ ] Thread mention tracking (separate from channel mention counts)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No thread list view UI | Medium | Backend `GET /channels/{cid}/threads` and client `fetch_active_threads()` exist, but no UI panel to browse active threads. Need a "Threads" button in channel header opening a list view. |
| Thread permissions unused | Medium | `CREATE_THREADS` and `SEND_IN_THREADS` exist in permission.gd (lines 40-43) but no client code checks them before allowing thread creation or replies. |
| No thread notification UI | Low | `Config.get_thread_notifications()` / `set_thread_notifications()` persist settings, but no bell icon or popup in the thread panel header exposes this to users. |
| No thread mention tracking | Low | Thread replies that mention the current user are not tracked separately from channel mentions. The thread indicator could show a mention badge. |
| No thread typing indicator | Low | Thread panel has no typing indicator for users typing in the thread. |
