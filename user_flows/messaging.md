# Messaging

## Overview

The messaging flow covers sending, receiving, replying to, editing, and deleting messages. Messages appear in a scrollable view with two layout modes: cozy (full header with avatar, author, timestamp) and collapsed (compact, for consecutive same-author messages). The composer handles text input with Enter-to-send, Shift+Enter for newlines. Context menus provide Reply/Edit/Delete actions. Markdown is converted to BBCode for rendering. Embeds, reactions, and typing indicators are also supported.

## User Steps

### Send a Message

1. User types in composer TextEdit.
2. Typing indicator sent every 8 seconds (throttled).
3. Enter key sends message; Shift+Enter inserts newline.
4. `AppState.send_message(text)` emitted.
5. `message_view` calls `Client.send_message_to_channel(channel_id, content, reply_to)`.
6. Server creates message, gateway broadcasts `message.create` event.
7. `Client._on_message_create()` adds to `_message_cache`, emits `AppState.messages_updated`.
8. `message_view` re-renders message list.

### Reply to a Message

1. Right-click (or long-press) a message to open the context menu.
2. Select "Reply" to call `AppState.initiate_reply(message_id)`.
3. Reply bar appears above composer: "Replying to [author]".
4. User types and sends -- `reply_to` included in send call.
5. Reply reference rendered above message content (author name + truncated preview).

### Edit a Message

1. Right-click own message and select "Edit" (disabled for others' messages).
2. `AppState.start_editing(message_id)` triggers `message_content.enter_edit_mode()`.
3. TextEdit replaces RichTextLabel inline.
4. Enter saves: `AppState.edit_message(id, new_content)` calls `Client.update_message_content()`.
5. Escape cancels: edit TextEdit removed, original content restored.

### Delete a Message

1. Right-click own message and select "Delete" (disabled for others' messages).
2. `AppState.delete_message(message_id)` calls `Client.remove_message()`.
3. Server deletes message, gateway broadcasts `message.delete` event.
4. Message removed from `_message_cache`, view re-renders.

## Signal Flow

```
Sending:
  Composer._on_send()
    -> AppState.send_message(text) [message_sent signal]
    -> message_view._on_message_sent()
      -> Client.send_message_to_channel(channel_id, content, reply_to)
      -> AppState.cancel_reply() if replying
    -> Gateway: message.create event
    -> Client._on_message_create()
      -> _message_cache[channel_id].append(msg_dict)
      -> AppState.messages_updated.emit(channel_id)
    -> message_view._on_messages_updated() -> re-renders

Reply:
  Context menu "Reply"
    -> AppState.initiate_reply(message_id)
      -> replying_to_message_id set, editing_message_id cleared
      -> AppState.reply_initiated signal
    -> Composer shows reply bar
    -> On send: reply_to = AppState.replying_to_message_id

Edit:
  Context menu "Edit"
    -> AppState.start_editing(message_id)
      -> editing_message_id set, replying_to_message_id cleared
    -> message_content.enter_edit_mode(message_id, content)
    -> User presses Enter:
      -> AppState.edit_message(message_id, new_content)
        -> message_edited signal
      -> message_view._on_message_edited()
        -> Client.update_message_content(message_id, new_content)
    -> Gateway: message.update event -> re-render

Delete:
  Context menu "Delete"
    -> AppState.delete_message(message_id)
      -> message_deleted signal
    -> message_view._on_message_deleted()
      -> Client.remove_message(message_id)
    -> Gateway: message.delete event -> re-render
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/message_view.gd` | Scrollable message list, auto-scroll, message lifecycle |
| `scenes/messages/cozy_message.gd` | Full message: avatar, author, timestamp, reply ref, context menu |
| `scenes/messages/collapsed_message.gd` | Compact follow-up: no avatar/header, hover timestamp |
| `scenes/messages/message_content.gd` | Text rendering (markdown to BBCode), inline edit mode, embed, reactions |
| `scenes/messages/composer/composer.gd` | Text input, send, reply bar, typing throttle |
| `scenes/messages/embed.gd` | Rich embed display with colored left border |
| `scenes/messages/reaction_bar.gd` | Container for reaction pills |
| `scenes/messages/reaction_pill.gd` | Individual emoji reaction toggle button |
| `scenes/messages/typing_indicator.gd` | Animated "X is typing..." with three bouncing dots |
| `scripts/long_press_detector.gd` | Touch long-press for mobile context menu (0.5s, 10px drag threshold) |
| `scripts/autoload/client.gd` | `send_message_to_channel()`, `update_message_content()`, `remove_message()`, `send_typing()`, `markdown_to_bbcode()` |
| `scripts/autoload/app_state.gd` | message_sent, reply_initiated, reply_cancelled, message_edited, message_deleted signals |

## Implementation Details

### Cozy vs Collapsed Layout (message_view.gd)

- Determined per-message during render: `use_collapsed = (author_id == prev_author_id) and not has_reply and i > 0`.
- First message always cozy; messages with replies always cozy.
- Consecutive same-author messages without replies use collapsed layout.
- Full list re-rendered on every `messages_updated` signal (clears all children, recreates).

### Auto-scroll (message_view.gd)

- `auto_scroll: bool` tracks whether user is at bottom.
- `_on_scrollbar_changed()`: If auto_scroll, scrolls to max.
- `_on_scroll_value_changed()`: Sets auto_scroll = true if within 10px of bottom.
- New messages auto-scroll only if user was already at bottom.

### Context Menu (cozy_message.gd, collapsed_message.gd)

- PopupMenu with items: "Reply" (0), "Edit" (1), "Delete" (2).
- Edit/Delete disabled when message author != current user (`Client.current_user.get("id")`).
- Right-click triggers `_show_context_menu(pos)` at mouse position.
- Long-press (touch) also triggers context menu via LongPressDetector.

### Reply Reference (cozy_message.gd)

- If `data.reply_to` is non-empty, fetches original message via `Client.get_message_by_id(reply_to)`.
- Displays original author name (colored) and content preview (truncated to 50 chars).
- Font size 12px, gray color.

### Mention Highlighting (cozy_message.gd, collapsed_message.gd)

- Checks if message content contains `@` + current user's display_name.
- Highlights entire message row with tan tint: `modulate = Color(1.0, 0.95, 0.85)`.

### Markdown to BBCode (client.gd)

- Sequential regex replacements: code blocks, inline code, strikethrough, underline, bold, italic, spoilers, links, blockquotes.
- Spoilers rendered as same-color text on same-color background (hidden until hover not implemented).
- Underline processed before bold to avoid `__` vs `**` conflict.

### Inline Edit Mode (message_content.gd)

- Creates TextEdit dynamically, hides original RichTextLabel.
- Line wrapping enabled, auto-height via `scroll_fit_content_height`.
- Enter (no Shift): strips whitespace, calls `AppState.edit_message()`, removes TextEdit.
- Escape: removes TextEdit, restores original content.

### Composer (composer.gd)

- `_on_send()`: Validates non-empty, emits `AppState.send_message()`, clears input, cancels reply if active.
- Enter/Shift+Enter: `_unhandled_input` checks `Key.ENTER` + not Shift, calls `_on_send()` + accepts event.
- Reply bar: Shows "Replying to [author]" with cancel button, connected to `AppState.reply_initiated`.
- Typing throttle: 8000ms minimum between `Client.send_typing()` calls.

### Reactions (reaction_pill.gd)

- 5 hardcoded emoji textures in `Client.emoji_textures`: thumbs_up, heart, 100, rocket, eyes.
- Toggle button: pressed increments count, unpressed decrements (min 0).
- Active style: blue background (30% opacity), 1px border, 8px rounded corners.
- Reaction data from `ClientModels.message_to_dict()`: `{emoji, count, active}`.

### Typing Indicator (typing_indicator.gd)

- Three animated dots with sine-wave alpha oscillation.
- `show_typing(username)`: Sets text "[username] is typing...", starts animation.
- `hide_typing()`: Hides and stops animation.
- Connected to `AppState.typing_started` / `AppState.typing_stopped` signals.
- Animation: `phase = anim_time * 3.0 - float(i) * 0.8`, alpha clamped 0.3-1.0.

### Embed (embed.gd)

- Renders title, description (RichTextLabel), footer.
- Left border color set from embed data `color` field.
- Hidden when embed dict is empty.
- Only first embed per message is rendered (ClientModels extracts first only).

## Implementation Status

- [x] Message sending via composer
- [x] Enter to send, Shift+Enter for newline
- [x] Cozy vs collapsed message layout
- [x] Reply via context menu with reply bar
- [x] Reply reference display (author + preview)
- [x] Inline edit mode (Enter to save, Escape to cancel)
- [x] Delete via context menu
- [x] Context menu with ownership-based Edit/Delete disabling
- [x] Long-press context menu for touch devices
- [x] Markdown to BBCode conversion (bold, italic, code, strikethrough, underline, spoilers, links, blockquotes)
- [x] Embed rendering (title, description, footer, border color)
- [x] Reaction display with toggle
- [x] Typing indicator with animated dots
- [x] Typing throttle (8s between sends)
- [x] Auto-scroll (preserves position when user scrolls up)
- [x] Mention highlighting (@username tints row)
- [x] Message cap (50 per channel, oldest removed)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No delete confirmation dialog | Medium | Delete immediately calls `Client.remove_message()` with no "Are you sure?" prompt |
| Reactions don't call server API | High | `reaction_pill.gd` toggles count locally but never calls `Client` or `ReactionsApi`. AccordKit has full `ReactionsApi` (add, remove, list) but it's unused |
| Only 5 hardcoded emoji | Medium | `Client.emoji_textures` has thumbs_up, heart, 100, rocket, eyes. No emoji picker UI |
| No reaction picker | Medium | Users can only toggle existing reactions, not add new ones to a message |
| No typing indicator timeout | Medium | `show_typing()` is called on `typing_started` but there's no timer to auto-hide; relies on `typing_stopped` which may not fire |
| Full re-render on every update | Low | `_on_messages_updated()` clears and recreates all message nodes instead of diffing |
| Spoiler text not interactive | Low | Spoilers rendered as hidden text (same fg/bg color) but there's no click-to-reveal mechanism |
| Only first embed rendered | Low | `ClientModels.message_to_dict()` only extracts `msg.embeds[0]`; subsequent embeds ignored |
| No message pagination / history | Medium | No "load older messages" functionality; only the last 50 messages (MESSAGE_CAP) are shown |
| No file/image attachments | Medium | `AccordMessage` has `attachments[]` but they're not rendered in UI |
