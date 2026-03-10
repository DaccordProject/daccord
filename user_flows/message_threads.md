# Message Threads

Priority: 47
Depends on: Messaging

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

### Browsing Active Threads
1. User clicks the "Threads" button (thread icon) in the message view topic bar.
2. A modal dialog opens listing all active threads for the current channel.
3. Each item shows the parent message author, content preview, and reply count.
4. User clicks a thread item to open it in the thread panel.

### Replying in a Thread
1. User opens a thread (via action bar, context menu, or reply count indicator).
2. User types in the thread composer at the bottom of the thread panel.
3. User presses Enter to send. The message appears in the thread.
4. Optionally, user checks "Also send to channel" to cross-post the reply to the main channel feed.

### Thread Notification Settings
1. User clicks the bell icon in the thread panel header.
2. A popup menu appears with options: Default, All Messages, Mentions Only, Nothing.
3. User selects a notification level. The choice persists across sessions.

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
    ├─> AppState.open_thread(parent_message_id) (line 341)
    │       sets current_thread_id, thread_panel_visible = true
    │       emits thread_opened (line 123)
    │
    ├─> main_window.gd._on_thread_opened() (line 455)
    │       hides member list (FULL/MEDIUM) or message view (COMPACT)
    │
    └─> thread_panel.gd._on_thread_opened() (line 45)
            fetches thread messages via Client.fetch.fetch_thread_messages()
            clears unread + mention counts
            checks SEND_IN_THREADS permission
            renders parent message + thread replies
            focuses thread composer (if permitted)

User sends message in thread composer
    ├─> thread_panel._on_send() (line 186)
    │
    ├─> Client.send_message_to_channel(channel_id, text, "", [], thread_id) (line 494)
    │       → ClientMutations.send_message_to_channel() (line 65)
    │           POST /channels/{id}/messages with { thread_id: parent_id }
    │
    └─> Gateway: message_create (with thread_id in payload)
            ├─> client_gateway.on_message_create() detects thread_id (line 266)
            │       routes to _thread_message_cache
            │       increments parent message reply_count
            │       tracks thread mentions (line 296)
            │       marks _thread_unread if panel not open (line 301)
            ├─> AppState.thread_messages_updated(parent_id) (line 304)
            └─> AppState.messages_updated(parent_channel) (line 285)

Typing in thread
    ├─> Gateway: typing_start (with thread_id in payload)
    │       client_gateway.on_typing_start() detects thread_id (line 481)
    │       emits AppState.thread_typing_started (line 483)
    │       creates timer to emit thread_typing_stopped (line 491)
    │
    └─> thread_panel._on_thread_typing_started() (line 224)
            shows ThreadTypingIndicator if thread_id matches

User clicks X on thread panel (or presses Escape)
    └─> AppState.close_thread() (line 346)
            sets current_thread_id = "", thread_panel_visible = false
            emits thread_closed (line 125)
            → main_window._on_thread_closed() restores layout
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Thread signals (lines 123-131), typing signals (lines 129-131), state vars (lines 195-196), `open_thread()`/`close_thread()` methods (lines 341-349) |
| `scripts/autoload/client.gd` | Thread message cache `_thread_message_cache` (line 98), unread tracking `_thread_unread` (line 99), mention tracking `_thread_mention_count` (line 100), `get_messages_for_thread()` (line 409), `send_message_to_channel()` with `thread_id` param (line 494) |
| `scripts/autoload/client_fetch.gd` | `fetch_thread_messages()` (line 279), `fetch_active_threads()` (line 363) |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` accepts `thread_id` param (line 65), includes in POST data (line 95) |
| `scripts/autoload/client_gateway.gd` | Thread reply routing in `on_message_create()` (lines 266-305), thread mention tracking (line 298), thread typing in `on_typing_start()` (lines 476-498), thread-aware `on_message_update()` (lines 375-395), thread-aware `on_message_delete()` (lines 412-432) |
| `scripts/autoload/client_models.gd` | Thread fields in `message_to_dict()` return dictionary (lines 402-433) |
| `scripts/autoload/config.gd` | Thread notification settings `get_thread_notifications()`/`set_thread_notifications()` (lines 503-511) |
| `addons/accordkit/models/message.gd` | `thread_id` (line 27), `reply_count` (line 28), `last_reply_at` (line 29), `thread_participants` (line 30), `from_dict()` parsing (lines 117-129) |
| `addons/accordkit/models/permission.gd` | `MANAGE_THREADS` (line 40), `CREATE_THREADS` (line 41), `SEND_IN_THREADS` (line 43) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `list_thread()` (line 136), `get_thread_info()` (line 143), `list_active_threads()` (line 149) |
| `scenes/messages/thread_panel.gd` | Thread panel controller: loads parent message, renders thread replies, manages composer, notification settings, typing indicator, permission checks |
| `scenes/messages/thread_panel.tscn` | Thread panel scene: header with bell + close buttons, parent message container, scroll area, typing indicator, composer with "Also send to channel" checkbox |
| `scenes/messages/active_threads_dialog.gd` | Active threads modal dialog (extends ModalBase): lists threads for a channel, click-to-open |
| `scenes/messages/cozy_message.gd` | Thread indicator setup in `setup()` (lines 72-91), mention badge (lines 83-86), click handler `_on_thread_indicator_input()` (line 179) |
| `scenes/messages/cozy_message.tscn` | ThreadIndicator HBoxContainer with ThreadIcon and ThreadCountLabel |
| `scenes/messages/message_view_actions.gd` | "Start Thread" context menu item (line 28), `on_bar_thread()` handler (line 53), `CREATE_THREADS` permission check (lines 101-104) |
| `scenes/messages/message_action_bar.gd` | `action_thread` signal (line 6), `thread_btn` reference (line 17), `CREATE_THREADS` permission check (lines 38-41) |
| `scenes/messages/message_action_bar.tscn` | ThreadButton between ReplyButton and EditButton |
| `scenes/messages/message_view.gd` | Wires `action_thread` to `_actions.on_bar_thread` (line 113), topic bar with threads button (lines 33-35, 93), active threads dialog (lines 663-667) |
| `scenes/messages/message_view.tscn` | TopicBar with ChannelNameLabel + ThreadsButton |
| `scenes/main/main_window.gd` | `thread_panel` onready (line 56), signal connections (lines 92-93), `_on_thread_opened()` (line 455), `_on_thread_closed()` (line 460), responsive layout handling |
| `scenes/main/main_window.tscn` | ThreadPanel instance in ContentBody between MessageView and MemberList |
| `assets/theme/icons/thread.svg` | Thread icon (chat bubble with horizontal line) |
| `assets/theme/icons/bell.svg` | Bell icon for thread notification settings |
| `scenes/admin/channel_permissions_dialog.gd` | Thread permissions in `TEXT_ONLY_PERMS` (lines 23-24) |

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

- **AppState** tracks `replying_to_message_id` (line 179) with signals `reply_initiated` (line 7) and `reply_cancelled` (line 8).
- **AccordMessage** has a `reply_to` field (line 22) parsed from either `message.reply_to` or `message.message_reference.message_id` for Discord compatibility.
- **CozyMessage** renders a reply reference header showing the original message author and a 50-character content preview (lines 52-65), fetching the original message via REST if not cached (lines 102-125).
- **MessageActionBar** has a reply button emitting `action_reply` (line 3).

### Thread Data Model

**AccordMessage** (message.gd) has four thread-related fields:
- `thread_id` (line 27) — parent message ID if this is a thread reply, `null` otherwise
- `reply_count` (line 28) — number of replies in thread (populated on parent messages)
- `last_reply_at` (line 29) — ISO timestamp of latest thread reply
- `thread_participants` (line 30) — array of user IDs who have replied

`from_dict()` parses these from the server response (lines 117-129). `to_dict()` includes them when non-null (lines 182-189).

**ClientModels.message_to_dict()** (line 298) converts these to the UI dictionary shape:
- `thread_id`: String (empty string if null)
- `reply_count`: int
- `last_reply_at`: String (empty string if null)
- `thread_participants`: Array

### Thread Permissions

AccordPermission defines three thread-related constants (permission.gd lines 40-43):
- `MANAGE_THREADS` — manage and delete other users' threads
- `CREATE_THREADS` — start new threads on messages
- `SEND_IN_THREADS` — post messages in existing threads

These are classified as text-only permissions in the channel permissions dialog (channel_permissions_dialog.gd lines 23-24).

Client-side enforcement:
- **Action bar**: `message_action_bar.gd` checks `CREATE_THREADS` (line 38) and hides `thread_btn` when the user lacks permission.
- **Context menu**: `message_view_actions.gd` checks `CREATE_THREADS` (line 101) and disables "Start Thread" (item id=5) when the user lacks permission.
- **Thread composer**: `thread_panel.gd` checks `SEND_IN_THREADS` (line 92) and disables `thread_input.editable` + `send_button.disabled` when the user lacks permission.

### AppState Thread Management

Signals (lines 123-131):
- `thread_opened(parent_message_id: String)` — emitted when user opens a thread
- `thread_closed()` — emitted when user closes the thread panel
- `thread_messages_updated(parent_message_id: String)` — emitted when thread messages change
- `thread_typing_started(thread_id: String, username: String)` — emitted when someone types in a thread
- `thread_typing_stopped(thread_id: String)` — emitted when thread typing times out

State variables (lines 195-196):
- `current_thread_id: String` — ID of the currently open thread's parent message
- `thread_panel_visible: bool` — whether the thread panel is showing

Methods:
- `open_thread(parent_message_id)` (line 341) — sets state and emits `thread_opened`
- `close_thread()` (line 346) — clears state and emits `thread_closed`

### Thread Panel UI

The thread panel (`thread_panel.tscn`) is a PanelContainer with `custom_minimum_size.x = 340`, initially hidden. Located in `main_window.tscn`'s ContentBody between MessageView and MemberList.

Panel structure:
```
ThreadPanel (PanelContainer, visible = false)
└── VBox (VBoxContainer)
    ├── Header (HBoxContainer, min_height 40)
    │   ├── ThreadTitle (Label) — "Thread"
    │   ├── NotifyButton (Button, flat, bell icon) — notification settings
    │   └── CloseButton (Button, flat) — "X"
    ├── HSeparator
    ├── ParentMessageContainer (MarginContainer) — instantiates CozyMessage for parent
    ├── HSeparator
    ├── ReplyCountLabel (Label) — "N replies" (blue, font_size 12)
    ├── ScrollContainer (v_expand)
    │   └── ThreadMessageList (VBoxContainer) — thread reply messages
    ├── ThreadTypingIndicator (TypingIndicator instance) — "X is typing..."
    └── ComposerBox (VBoxContainer)
        ├── HBox: ThreadInput (TextEdit) + SendButton (Button)
        └── AlsoSendCheck (CheckBox) — "Also send to channel"
```

The controller (`thread_panel.gd`):
- Connects to `AppState.thread_opened`, `thread_closed`, `thread_messages_updated`, `thread_typing_started`, `thread_typing_stopped` in `_ready()` (lines 36-42)
- Sets up notification popup menu with 4 options in `_ready()` (lines 29-35)
- `_on_thread_opened()` (line 45): Shows panel, loads parent message as CozyMessage instance, fetches thread replies via `Client.fetch.fetch_thread_messages()`, clears unread + mention counts (lines 75-76), checks `SEND_IN_THREADS` permission (lines 89-99), focuses input if permitted
- `_render_thread_messages()` (line 128): Renders thread replies using CozyMessage/CollapsedMessage scenes (collapsed when consecutive same-author messages), scrolls to bottom
- `_on_notify_pressed()` (line 163): Shows notification settings popup with current mode check-marked
- `_on_notify_option_selected()` (line 178): Persists notification mode via `Config.set_thread_notifications()`
- `_on_send()` (line 186): Sends via `Client.send_message_to_channel()` with `thread_id` param; optionally sends a copy without `thread_id` if "Also send to channel" is checked
- `_on_input_key()` (line 203): Enter to send, Escape to close panel
- `_on_thread_typing_started()` (line 224): Shows typing indicator when thread_id matches
- `_on_thread_typing_stopped()` (line 228): Hides typing indicator when thread_id matches

### Active Threads Dialog

`active_threads_dialog.gd` extends `ModalBase` (code-built modal, 480x400). Opened from the "Threads" button in `message_view.gd`'s topic bar (line 663).

- `open(channel_id)` fetches active threads via `Client.fetch.fetch_active_threads()`
- Each thread item is a PanelContainer card showing author name, timestamp, content preview (truncated to 100 chars), and reply count
- Clicking an item calls `AppState.open_thread(msg_id)` and closes the dialog
- Shows loading/empty states while fetching
- Hidden for DMs and forum channels (`message_view.gd` line 154)

### Client Thread Caching

**Client** (client.gd):
- `_thread_message_cache: Dictionary` (line 98) — maps `{ parent_message_id -> Array[message_dict] }`
- `_thread_unread: Dictionary` (line 99) — maps `{ parent_message_id -> true }` for threads with unread messages
- `_thread_mention_count: Dictionary` (line 100) — maps `{ parent_message_id -> int }` for per-thread mention counts
- `get_messages_for_thread(parent_id)` (line 409) — returns cached thread messages

**ClientFetch** (client_fetch.gd):
- `fetch_thread_messages(channel_id, parent_message_id)` (line 279) — calls `client.messages.list_thread()`, caches result in `_thread_message_cache`, emits `AppState.thread_messages_updated`
- `fetch_active_threads(channel_id)` (line 363) — calls `client.messages.list_active_threads()`, returns array of parent message dicts with thread metadata

**ClientMutations** (client_mutations.gd):
- `send_message_to_channel()` accepts optional `thread_id: String = ""` param (line 67), includes in POST data when non-empty (line 95)

### Gateway Event Handling

**on_message_create** (client_gateway.gd, lines 266-305):
1. Checks if message has `thread_id` (line 266)
2. If thread reply: adds to `_thread_message_cache[tid]` (line 277), increments parent message's `reply_count` (line 283), checks if current user is mentioned and increments `_thread_mention_count` (line 298), marks `_thread_unread[tid]` if panel not open (line 301), emits `thread_messages_updated` (line 304), then returns without adding to main channel cache
3. Normal messages proceed through existing flow

**on_message_update** (lines 375-395): Checks for `thread_id` — if present, updates in `_thread_message_cache` and emits `thread_messages_updated`; otherwise updates in main cache

**on_message_delete** (lines 412-432): Iterates `_thread_message_cache` to find deleted message — if found, removes it, decrements parent's `reply_count`, and emits `thread_messages_updated`; otherwise removes from main cache

**on_typing_start** (lines 472-498): Checks for `thread_id` in typing data (line 481). If present, emits `AppState.thread_typing_started` and creates a 10-second timer with key `"thread_" + thread_id` to emit `thread_typing_stopped`. Otherwise emits channel-level `typing_started`/`typing_stopped` as before.

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

**Topic bar** — `message_view.tscn` has a TopicBar HBoxContainer between ImposterBanner and ScrollContainer, containing a ChannelNameLabel and ThreadsButton (thread icon). Hidden for DMs and forum channels (message_view.gd line 154). Button click opens the active threads dialog (line 663).

**Context menu** — `message_view_actions.gd` adds "Start Thread" as item id=5 (line 28). Disabled when user lacks `CREATE_THREADS` (line 104). Handler calls `AppState.open_thread(msg_id)` (line 154).

**Action bar** — `message_action_bar.gd` has `action_thread` signal (line 6) and ThreadButton (line 17) between Reply and Edit. Hidden when user lacks `CREATE_THREADS` (line 41). Connected in `message_view.gd` (line 113) via `_actions.on_bar_thread()` (message_view_actions.gd line 53).

**Thread indicator** — `cozy_message.gd` checks `data.get("reply_count", 0)` in `setup()` (lines 72-91). When > 0, shows ThreadIndicator HBoxContainer with blue reply count text and a pointing-hand cursor. Unread threads show a brighter accent_hover color (line 81). Mention badge appends " · @N" when `_thread_mention_count` > 0 (lines 83-86). Click handler `_on_thread_indicator_input()` (line 179) calls `AppState.open_thread()`.

### Main Window Layout

`main_window.gd` connects to `AppState.thread_opened` and `AppState.thread_closed` (lines 92-93):

**`_on_thread_opened()`** (line 455): Hides member list in FULL/MEDIUM mode; hides message view in COMPACT mode (thread panel takes over).

**`_on_thread_closed()`** (line 460): Restores member list visibility via `_update_member_list_visibility()` in FULL/MEDIUM; restores message view visibility in COMPACT.

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
- `get_thread_notifications(thread_id)` (line 503) — returns mode: "default", "all", "mentions", or "nothing"
- `set_thread_notifications(thread_id, mode)` (line 506) — persists the notification mode; "default" erases the key

The thread panel header has a bell icon button (NotifyButton) that opens a PopupMenu with 4 options: Default, All Messages, Mentions Only, Nothing. The current mode is check-marked. Selection persists via Config under the `[thread_notifications]` section.

Default behavior ("default") follows the channel's notification settings.

### Thread Unread & Mention Tracking

- `Client._thread_unread` (line 99) tracks which threads have unread messages
- `Client._thread_mention_count` (line 100) tracks per-thread mention counts
- Gateway marks a thread as unread when a reply arrives and the panel is not open for that thread (client_gateway.gd line 301)
- Gateway increments mention count when a thread reply mentions the current user (client_gateway.gd line 298)
- Thread panel clears both unread and mention markers when opened (thread_panel.gd lines 75-76)
- Cozy message thread indicator shows brighter accent_hover color for unread threads (cozy_message.gd line 81)
- Cozy message thread indicator appends " · @N" mention badge when mention count > 0 (cozy_message.gd lines 83-86)

## Implementation Status

- [x] Inline reply system (`reply_to` field, reply bar in composer, reply reference in cozy messages)
- [x] Thread permission constants (`MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS`)
- [x] Thread permissions in channel permission management UI (text-only permissions)
- [x] Client-side permission checks for `CREATE_THREADS` / `SEND_IN_THREADS`
- [x] Thread data model fields on `AccordMessage` (`thread_id`, `reply_count`, `last_reply_at`, `thread_participants`)
- [x] Thread dictionary shape in `ClientModels.message_to_dict()`
- [x] AppState thread signals and state (`thread_opened`, `thread_closed`, `thread_typing_started`, `thread_typing_stopped`, `current_thread_id`)
- [x] Thread panel UI scene (`thread_panel.tscn` + `thread_panel.gd`)
- [x] Thread composer (send in thread context, permission-gated)
- [x] Thread reply count indicator on parent messages in main channel
- [x] Thread mention tracking (separate from channel mention counts, "@N" badge on indicator)
- [x] "Start Thread" in context menu and action bar (permission-gated)
- [x] REST API thread message endpoints (server-side: migration, model, queries, routes)
- [x] Gateway thread event handling (create, update, delete, typing)
- [x] Thread unread indicators (accent_hover color on cozy message thread indicator)
- [x] "Also send to channel" cross-post toggle
- [x] Thread notification settings (per-thread config persistence + bell icon UI)
- [x] Thread message caching and cache management
- [x] Responsive layout (FULL/MEDIUM/COMPACT thread panel behavior)
- [x] Thread typing indicator (reuses typing_indicator.tscn in thread panel)
- [x] Active threads list view (Threads button in topic bar, modal dialog)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Thread notification settings not enforced | Medium | `Config.get_thread_notifications()` persists the mode but nothing in the gateway or notification system reads it to suppress/filter notifications. The bell UI works but the setting has no effect on actual notifications. |
| No thread-scoped `send_typing` | Low | The thread composer doesn't call `Client.send_typing()` with a `thread_id`, so other users won't see typing indicators in threads unless the server infers it. |
| Thread participant avatars not shown | Low | `thread_participants` is parsed from the server but the thread indicator only shows reply count and mention badge — no participant avatar row. |
