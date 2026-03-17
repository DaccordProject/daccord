# Message Threads

Priority: 47
Depends on: Messaging
Status: Complete

Slack-style message threads with thread panel UI, thread data model, reply count indicators, thread composer with "Also send to channel", permission gating, notification settings, typing indicators, active threads browser, and responsive layout.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Thread signals (lines 123-131), typing signals (lines 129-131), state vars (lines 195-196), `open_thread()`/`close_thread()` methods (lines 341-349) |
| `scripts/autoload/client.gd` | Thread message cache `_thread_message_cache`, unread tracking `_thread_unread`, mention tracking `_thread_mention_count`, `get_messages_for_thread()`, `send_message_to_channel()` with `thread_id` param |
| `scripts/autoload/client_fetch.gd` | `fetch_thread_messages()`, `fetch_active_threads()` |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` accepts `thread_id` param, includes in POST data |
| `scripts/autoload/client_gateway.gd` | Thread reply routing in `on_message_create()`, thread mention tracking, thread typing in `on_typing_start()`, thread-aware `on_message_update()` and `on_message_delete()` |
| `scripts/autoload/client_models.gd` | Thread fields in `message_to_dict()` return dictionary |
| `scripts/autoload/config.gd` | Thread notification settings `get_thread_notifications()`/`set_thread_notifications()` |
| `addons/accordkit/models/message.gd` | `thread_id`, `reply_count`, `last_reply_at`, `thread_participants` fields |
| `addons/accordkit/models/permission.gd` | `MANAGE_THREADS`, `CREATE_THREADS`, `SEND_IN_THREADS` |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `list_thread()`, `get_thread_info()`, `list_active_threads()` |
| `scenes/messages/thread_panel.gd` | Thread panel controller: loads parent message, renders thread replies, manages composer, notification settings, typing indicator, permission checks |
| `scenes/messages/thread_panel.tscn` | Thread panel scene: header with bell + close buttons, parent message container, scroll area, typing indicator, composer with "Also send to channel" checkbox |
| `scenes/messages/active_threads_dialog.gd` | Active threads modal dialog: lists threads for a channel, click-to-open |
| `scenes/messages/cozy_message.gd` | Thread indicator setup, mention badge, click handler `_on_thread_indicator_input()` |
| `scenes/messages/message_view_actions.gd` | "Start Thread" context menu item, `CREATE_THREADS` permission check |
| `scenes/messages/message_action_bar.gd` | `action_thread` signal, ThreadButton, `CREATE_THREADS` permission check |
| `scenes/messages/message_view.gd` | Wires `action_thread`, topic bar with threads button, active threads dialog |
| `scenes/main/main_window.gd` | `_on_thread_opened()`, `_on_thread_closed()`, responsive layout handling |
| `migrations/009_threads.sql` | Adds `thread_id` column and index to messages table |
| `src/db/messages.rs` | Thread-aware queries: list, reply counts, thread metadata, active threads |
| `src/routes/messages.rs` | Thread REST endpoints |
