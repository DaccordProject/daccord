# Message Threads

## Overview

Message threads allow users to branch off a conversation from a specific message in a channel, keeping focused discussions contained without cluttering the main message feed. Threads behave like Slack-style threads: clicking "Start Thread" or "Reply in Thread" on any message opens a side panel showing the parent message and its thread replies, with its own composer for sending threaded messages. Thread activity is summarized inline in the main channel as a compact reply count indicator.

This feature is **not yet implemented**. The current codebase has a lightweight inline reply system (`reply_to` on messages) and thread-related permission constants, but no thread data model, thread UI, or thread API endpoints.

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
4. User can scroll up to see older thread replies, or load more via a "Show older replies" button.

### Replying in a Thread
1. User opens a thread (via action bar, context menu, or reply count indicator).
2. User types in the thread composer at the bottom of the thread panel.
3. User presses Enter to send. The message appears in the thread.
4. Optionally, user checks "Also send to channel" to cross-post the reply to the main channel feed.

### Closing a Thread
1. User clicks the X button in the thread panel header.
2. The thread panel slides closed; the main message view expands to fill the space.

## Signal Flow

```
User clicks "Thread" on message
    ├─> message_view_actions.gd / message_action_bar.gd
    │       emits action_thread(msg_data)
    │
    ├─> AppState.thread_opened(parent_message_id)
    │       sets current_thread_id, thread_panel_visible = true
    │
    ├─> main_window.gd
    │       shows thread_panel alongside message_view in ContentBody
    │
    └─> thread_panel.gd
            calls Client.fetch_thread_messages(parent_message_id)
            renders parent message + thread replies
            shows thread composer

User sends message in thread composer
    ├─> AppState.message_sent(text)  [with thread context]
    │
    ├─> Client.send_thread_message(channel_id, parent_id, content)
    │       POST /channels/{id}/messages  with { thread_id: parent_id }
    │
    └─> Gateway: message_create (with thread metadata)
            ├─> thread_panel updates (appends new message)
            └─> parent message in main channel updates reply count

User clicks X on thread panel
    └─> AppState.thread_closed()
            sets current_thread_id = "", thread_panel_visible = false
            main_window hides thread panel
```

## Key Files

### Existing Files (to be modified)

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Add thread signals and state variables |
| `scripts/autoload/client.gd` | Add thread message fetch/send API routing |
| `scripts/autoload/client_mutations.gd` | Add `send_thread_message()` mutation |
| `scripts/autoload/client_gateway.gd` | Handle thread-related gateway events |
| `scripts/autoload/client_models.gd` | Add thread metadata to `message_to_dict()` |
| `addons/accordkit/models/message.gd` | Add `thread_id`, `reply_count`, `thread_metadata` fields |
| `addons/accordkit/models/permission.gd` | Already has `MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS` (lines 40-43) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | Add thread message list/create endpoints |
| `scenes/messages/message_view.gd` | Wire thread open/close to action bar and context menu |
| `scenes/messages/message_view.tscn` | No changes (thread panel lives in main_window layout) |
| `scenes/messages/message_view_actions.gd` | Add "Start Thread" context menu item (line 23) |
| `scenes/messages/message_action_bar.gd` | Add thread button, `action_thread` signal |
| `scenes/messages/cozy_message.gd` | Add thread reply count indicator below message content |
| `scenes/messages/cozy_message.tscn` | Add ThreadIndicator HBoxContainer |
| `scenes/main/main_window.gd` | Manage thread panel visibility in ContentBody |
| `scenes/main/main_window.tscn` | Add ThreadPanel node to ContentBody HBox |
| `scenes/admin/channel_permissions_dialog.gd` | Thread permissions already in `TEXT_ONLY_PERMS` (lines 22-23) |

### New Files (to be created)

| File | Role |
|------|------|
| `scenes/messages/thread_panel.gd` | Thread panel controller: loads parent message + thread replies, manages thread composer |
| `scenes/messages/thread_panel.tscn` | Thread panel scene: header (title + close), scroll container with message list, thread composer |

## Implementation Details

### Current Reply System (Foundation)

The existing reply system provides the infrastructure threads will build on:

- **AppState** tracks `replying_to_message_id` (line 134) with signals `reply_initiated` (line 7) and `reply_cancelled` (line 8).
- **AccordMessage** has a `reply_to` field (line 22) parsed from either `message.reply_to` or `message.message_reference.message_id` for Discord compatibility (lines 85-92).
- **ClientModels.message_to_dict()** converts `reply_to` to a string in the message dictionary (lines 386-388), which UI components read as `data.get("reply_to", "")`.
- **Composer** shows a reply bar when `reply_initiated` fires (line 69-76), sends the `reply_to` value alongside the message content (line 54), and the cancel button emits `AppState.cancel_reply()` (line 122).
- **CozyMessage** renders a reply reference header showing the original message author and a 50-character content preview (lines 52-65), fetching the original message via REST if not cached (lines 84-107).
- **MessageViewActions** context menu has "Reply" as item 0 (line 23), calling `AppState.initiate_reply()` (line 103).
- **MessageActionBar** has a reply button emitting `action_reply` (line 3, line 72-73).
- **Client.send_message_to_channel()** passes `reply_to` in the POST body (line 344-349 in client.gd, lines 62-97 in client_mutations.gd).

### Thread Permissions (Already Present)

AccordPermission defines three thread-related constants (permission.gd lines 40-43):
- `MANAGE_THREADS` — manage and delete other users' threads
- `CREATE_THREADS` — start new threads on messages
- `SEND_IN_THREADS` — post messages in existing threads

These are already included in `AccordPermission.all()` (lines 83-86) and classified as text-only permissions in the channel permissions dialog (channel_permissions_dialog.gd lines 22-23). No client-side permission checks currently use them.

### AccordMessage Model Changes

The `AccordMessage` model (message.gd) needs new fields:

```gdscript
var thread_id = null         # String — parent message ID if this is a thread reply
var reply_count: int = 0     # Number of replies in thread (on parent messages)
var last_reply_at = null     # ISO timestamp of latest thread reply
var thread_participants: Array = []  # User IDs who have replied in thread
```

`from_dict()` should parse these from the server response, and `to_dict()` should include them when non-null. The `message_to_dict()` in ClientModels should expose them in the UI dictionary shape:

```gdscript
# Added to the return dictionary in message_to_dict()
"thread_id": thread_id_str,        # "" if not a thread reply
"reply_count": msg.reply_count,    # 0 if no thread
"last_reply_at": last_reply_str,   # "" if no thread
"thread_participants": msg.thread_participants,
```

### AppState Changes

New signals and state for thread management:

```gdscript
signal thread_opened(parent_message_id: String)
signal thread_closed()
signal thread_messages_updated(parent_message_id: String)

var current_thread_id: String = ""
var thread_panel_visible: bool = false
```

Methods:

```gdscript
func open_thread(parent_message_id: String) -> void:
    current_thread_id = parent_message_id
    thread_panel_visible = true
    thread_opened.emit(parent_message_id)

func close_thread() -> void:
    current_thread_id = ""
    thread_panel_visible = false
    thread_closed.emit()
```

### Thread Panel UI

The thread panel is a new scene placed in `main_window.tscn`'s `ContentBody` HBoxContainer, positioned after `MessageView` and before `MemberList`:

```
ContentBody (HBoxContainer)
├── MessageView (size_flags_horizontal = 3)
├── ThreadPanel (custom_minimum_size.x = 340, visible = false)
└── MemberList
```

The panel structure:

```
ThreadPanel (PanelContainer)
└── VBox (VBoxContainer)
    ├── Header (HBoxContainer)
    │   ├── ThreadIcon (TextureRect)
    │   ├── Title (Label) — "Thread"
    │   ├── Spacer (Control, h_expand)
    │   └── CloseButton (Button)
    ├── ParentMessage (HBoxContainer) — CozyMessage instance for the root message
    ├── Separator (HSeparator)
    ├── ReplyCount (Label) — "N replies"
    ├── ScrollContainer
    │   └── ThreadMessageList (VBoxContainer) — thread reply messages
    ├── TypingIndicator (HBoxContainer)
    └── ThreadComposer (PanelContainer) — stripped-down composer (text input + send)
```

The thread panel controller:

```gdscript
# thread_panel.gd
extends PanelContainer

var _parent_message_id: String = ""
var _thread_messages: Array = []

func _ready() -> void:
    AppState.thread_opened.connect(_on_thread_opened)
    AppState.thread_closed.connect(_on_thread_closed)
    AppState.thread_messages_updated.connect(_on_thread_messages_updated)

func _on_thread_opened(parent_message_id: String) -> void:
    _parent_message_id = parent_message_id
    visible = true
    _load_parent_message()
    Client.fetch_thread_messages(parent_message_id)

func _on_thread_closed() -> void:
    _parent_message_id = ""
    visible = false
    _clear_messages()
```

### Message View Integration

**Context menu** — Add "Start Thread" as a new item in `message_view_actions.gd`:

```gdscript
# In setup_context_menu() (currently line 22)
_context_menu.add_item("Start Thread", 5)
```

**Action bar** — Add a thread button in `message_action_bar.gd`:

```gdscript
signal action_thread(msg_data: Dictionary)
# Add thread_btn in _ready()
```

**Cozy message** — Add a thread reply count indicator:

```gdscript
# In cozy_message.gd setup()
var reply_count: int = data.get("reply_count", 0)
if reply_count > 0:
    thread_indicator.visible = true
    thread_count_label.text = "%d %s" % [reply_count, "reply" if reply_count == 1 else "replies"]
```

Clicking the thread indicator calls `AppState.open_thread(message_id)`.

### REST API Endpoints

Thread messages are fetched from and posted to the same channel messages endpoint, with a `thread_id` query/body parameter:

```gdscript
# Fetch thread messages
# GET /channels/{channel_id}/messages?thread_id={parent_message_id}
func list_thread(channel_id: String, parent_message_id: String, query: Dictionary = {}) -> RestResult:
    query["thread_id"] = parent_message_id
    return await list(channel_id, query)

# Send thread message
# POST /channels/{channel_id}/messages  { "content": "...", "thread_id": "parent_id" }
# Uses existing create() with thread_id in data
```

### Gateway Event Handling

When a `message_create` event arrives with a `thread_id` field:
1. If the thread panel is open for that parent message, append the new message to the thread list.
2. Update the parent message's `reply_count` in the channel message cache.
3. Emit `AppState.thread_messages_updated(parent_message_id)`.

### Main Window Layout

`main_window.gd` handles thread panel visibility:

```gdscript
func _ready() -> void:
    # ... existing code ...
    AppState.thread_opened.connect(_on_thread_opened)
    AppState.thread_closed.connect(_on_thread_closed)

func _on_thread_opened(_parent_id: String) -> void:
    thread_panel.visible = true

func _on_thread_closed() -> void:
    thread_panel.visible = false
```

In compact layout mode, the thread panel replaces the message view (similar to how the sidebar becomes a drawer). In medium mode, the member list hides when the thread panel is open.

### Responsive Behavior

| Layout Mode | Behavior |
|-------------|----------|
| FULL (>=768px) | Thread panel shown alongside message view; member list may hide if space is tight |
| MEDIUM (<768px) | Thread panel replaces member list area |
| COMPACT (<500px) | Thread panel overlays the message view as a full-screen panel with back button |

## Implementation Status

- [x] Inline reply system (`reply_to` field, reply bar in composer, reply reference in cozy messages)
- [x] Thread permission constants (`MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS`)
- [x] Thread permissions in channel permission management UI (text-only permissions)
- [ ] Thread data model fields on `AccordMessage` (`thread_id`, `reply_count`, `last_reply_at`)
- [ ] Thread dictionary shape in `ClientModels.message_to_dict()`
- [ ] AppState thread signals and state (`thread_opened`, `thread_closed`, `current_thread_id`)
- [ ] Thread panel UI scene (`thread_panel.tscn` + `thread_panel.gd`)
- [ ] Thread composer (send in thread context)
- [ ] Thread reply count indicator on parent messages in main channel
- [ ] "Start Thread" in context menu and action bar
- [ ] REST API thread message endpoints (server-side)
- [ ] Gateway thread event handling
- [ ] Thread unread/mention indicators
- [ ] "Also send to channel" cross-post toggle
- [ ] Thread notification settings
- [ ] Thread list view (all active threads in a channel)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No thread data model | High | `AccordMessage` (message.gd) has no `thread_id`, `reply_count`, or `thread_metadata` fields. Server must support these first. |
| No thread API endpoints | High | `MessagesApi` (messages_api.gd) has no thread-specific list or create methods. Requires accordserver backend support. |
| No thread panel UI | High | No `thread_panel.tscn` or `thread_panel.gd` exists. Must be created as a new scene. |
| No AppState thread state | High | `app_state.gd` has no `current_thread_id`, `thread_panel_visible`, or thread signals. |
| No "Start Thread" action | High | Context menu (message_view_actions.gd line 23) and action bar (message_action_bar.gd) lack thread buttons. |
| No thread indicator on messages | Medium | `cozy_message.gd` and `cozy_message.tscn` have no reply count indicator beneath messages. |
| No gateway thread events | Medium | `client_gateway.gd` does not differentiate thread messages from channel messages in `on_message_create` (line 161). |
| No thread message caching | Medium | `Client` caches messages per channel but has no separate cache for thread messages. |
| Thread permissions unused | Medium | `MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS` exist in permission.gd (lines 40-43) but no client code checks them. |
| No "Also send to channel" toggle | Low | Slack allows cross-posting thread replies to the main channel; no UI or API support exists. |
| No thread list view | Low | No way to browse all active threads in a channel or guild. |
| No thread notification settings | Low | Cannot configure per-thread mute or follow/unfollow. |
| No thread unread tracking | Low | No unread badge or indicator for threads with new messages. |
| Compact layout thread UX | Low | No design for how threads appear on narrow viewports (<500px). |
