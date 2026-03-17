# Messaging

Priority: 5
Depends on: Space & Channel Navigation, Gateway Events
Status: Complete

Send/receive messages with cozy vs collapsed layout, reply/edit/delete, floating action bar, context menus, markdown-to-BBCode rendering, embeds, reactions with picker, typing indicators, connection state banners, and diff-based updates.

## Key Files

| File | Role |
|------|------|
| `scenes/messages/message_view.gd` | Scrollable message list, auto-scroll, message lifecycle, action bar management, connection banner, loading/error states |
| `scenes/messages/message_action_bar.gd` | Floating toolbar: React, Reply, Edit, Delete buttons; hover state machine; opens reaction picker |
| `scenes/messages/cozy_message.gd` | Full message: avatar, author, timestamp, reply ref, context menu, reaction picker |
| `scenes/messages/collapsed_message.gd` | Compact follow-up: no avatar/header, hover timestamp (always visible in compact mode), context menu |
| `scenes/messages/message_content.gd` | Text rendering (markdown to BBCode), system messages, (edited) indicator, inline edit mode, embed, reactions |
| `scenes/messages/reaction_picker.gd` | Wraps emoji picker for adding reactions to messages; calls `Client.add_reaction()` |
| `scenes/messages/composer/composer.gd` | Text input, send, reply bar, typing throttle, Up-to-edit, send failure handling, disabled state |
| `scenes/messages/composer/message_input.gd` | Custom TextEdit with styled content margins |
| `scenes/messages/embed.gd` | Rich embed display with colored left border |
| `scenes/messages/reaction_bar.gd` | Container for reaction pills; passes `channel_id`/`message_id` through to each pill |
| `scenes/messages/reaction_pill.gd` | Individual emoji reaction toggle button with server API calls |
| `scenes/messages/typing_indicator.gd` | Animated "X is typing..." with three bouncing dots |
| `scripts/long_press_detector.gd` | Touch long-press for mobile context menu (0.5s, 10px drag threshold) |
| `scripts/autoload/client.gd` | `send_message_to_channel()`, `update_message_content()`, `remove_message()`, `add_reaction()`, `remove_reaction()`, `send_typing()` |
| `scripts/autoload/client_fetch.gd` | `fetch_messages()`, `fetch_older_messages()` — fetches messages from server, populates `_message_cache`, emits `messages_updated` or `message_fetch_failed` |
| `scripts/autoload/client_models.gd` | `markdown_to_bbcode()`, `message_to_dict()` — converts AccordKit models to UI dictionaries |
| `scripts/autoload/app_state.gd` | `message_sent`, `reply_initiated`, `reply_cancelled`, `message_edited`, `edit_requested`, `message_deleted`, `message_send_failed`, `message_edit_failed`, `message_delete_failed`, `message_fetch_failed`, `reactions_updated`, `reaction_failed`, `server_disconnected`, `server_reconnecting`, `server_reconnected`, `server_connection_failed` signals |
