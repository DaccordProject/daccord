# Messaging

*Last touched: 2026-02-18 20:21*

## Overview

The messaging flow covers sending, receiving, replying to, editing, and deleting messages. Messages appear in a scrollable view with two layout modes: cozy (full header with avatar, author, timestamp) and collapsed (compact, for consecutive same-author messages). The composer handles text input with Enter-to-send, Shift+Enter for newlines, and Up arrow to edit last own message. A floating action bar appears on message hover with React, Reply, Edit, and Delete buttons (Edit/Delete only for own messages). Right-click context menus and long-press (touch) also provide these actions. Markdown is converted to BBCode for rendering. Embeds, reactions (with server API integration and reaction picker), typing indicators, connection state banners, and error handling are also supported.

## User Steps

### Send a Message

1. User types in composer TextEdit.
2. Typing indicator sent every 8 seconds (throttled via `_last_typing_time`).
3. Enter key sends message; Shift+Enter inserts newline.
4. `AppState.send_message(text)` emitted.
5. `message_view` calls `Client.send_message_to_channel(channel_id, content, reply_to)`.
6. Server creates message, gateway broadcasts `message.create` event.
7. `Client._on_message_create()` adds to `_message_cache`, emits `AppState.messages_updated`.
8. `message_view` re-renders message list.
9. On failure: `Client` emits `AppState.message_send_failed`; composer shows error label and restores the failed text.

### Reply to a Message

1. Hover over a message and click the Reply button in the floating action bar, or right-click (or long-press) and select "Reply".
2. `AppState.initiate_reply(message_id)` called.
3. Reply bar appears above composer: "Replying to [author]".
4. User types and sends -- `reply_to` included in send call.
5. Reply reference rendered above message content (author name + truncated preview).

### Edit a Message

1. Hover over own message and click the Edit button in the floating action bar, or right-click and select "Edit" (disabled for others' messages). Alternatively, press Up arrow in the composer when the text input is empty to edit your last sent message.
2. `AppState.start_editing(message_id)` sets state; the caller directly invokes `message_content.enter_edit_mode()`. For Up-arrow editing, `AppState.edit_requested` signal is emitted and handled by `message_view._on_edit_requested()`.
3. TextEdit replaces RichTextLabel inline.
4. Enter saves: `AppState.edit_message(id, new_content)` calls `Client.update_message_content()`.
5. Escape cancels: edit TextEdit removed, original content restored.
6. Editing state is preserved across message list re-renders (saved/restored in `_load_messages()`).

### Delete a Message

1. Hover over own message and click the Delete button in the floating action bar, or right-click and select "Delete" (disabled for others' messages).
2. A confirmation dialog appears: "Are you sure you want to delete this message?"
3. On confirm: `AppState.delete_message(message_id)` calls `Client.remove_message()`.
4. Server deletes message, gateway broadcasts `message.delete` event.
5. Message removed from `_message_cache`, view re-renders.

### Add a Reaction

1. **Via action bar**: Hover over a message, click the React (smile) button to open the reaction picker.
2. **Via context menu**: Right-click (or long-press) a message, select "Add Reaction" to open the reaction picker.
3. **Via existing pill**: Click an existing reaction pill to toggle your reaction on/off.
4. The reaction picker wraps the emoji picker (`ReactionPickerScene`); selecting an emoji calls `Client.add_reaction(channel_id, msg_id, emoji)`. Toggling a pill off calls `Client.remove_reaction()`.
5. Picker closes automatically after selection.

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
  On failure:
    -> Client emits AppState.message_send_failed(channel_id, content, error)
    -> Composer._on_message_send_failed() shows error, restores text

Reply:
  Action bar Reply button / Context menu "Reply"
    -> AppState.initiate_reply(message_id)
      -> replying_to_message_id set, editing_message_id cleared
      -> AppState.reply_initiated signal
    -> Composer shows reply bar
    -> On send: reply_to = AppState.replying_to_message_id

Edit (action bar / context menu):
  Action bar Edit button / Context menu "Edit"
    -> AppState.start_editing(message_id)
      -> editing_message_id set, replying_to_message_id cleared
    -> message_content.enter_edit_mode(message_id, content)
    -> User presses Enter:
      -> AppState.edit_message(message_id, new_content)
        -> message_edited signal
      -> message_view._on_message_edited()
        -> Client.update_message_content(message_id, new_content)
    -> Gateway: message.update event -> re-render

Edit (Up arrow in composer):
  Composer._on_text_input() detects KEY_UP with empty input
    -> _edit_last_own_message() finds last own msg in cache
    -> AppState.start_editing(message_id)
    -> AppState.edit_requested.emit(message_id)
    -> message_view._on_edit_requested()
      -> message_content.enter_edit_mode(message_id, content)

Delete:
  Action bar Delete button / Context menu "Delete"
    -> ConfirmationDialog shown: "Are you sure you want to delete this message?"
    -> On confirmed: AppState.delete_message(message_id)
      -> message_deleted signal
    -> message_view._on_message_deleted()
      -> Client.remove_message(message_id)
    -> Gateway: message.delete event -> re-render

Reaction (picker):
  Action bar React / Context menu "Add Reaction"
    -> _open_reaction_picker() creates ReactionPickerScene
    -> ReactionPickerScene wraps EmojiPickerScene
    -> _on_emoji_picked(emoji_name)
      -> Client.add_reaction(channel_id, message_id, emoji)
    -> Picker auto-closes

Reaction (pill toggle):
  reaction_pill._on_toggled(toggled_on)
    -> Optimistic local count update
    -> Client.add_reaction() or Client.remove_reaction()
    -> On success: Client updates _message_cache, emits messages_updated
    -> On failure: Client emits AppState.reaction_failed
      -> reaction_pill._on_reaction_failed() reverts toggle and count

Connection state:
  AppState.server_disconnected -> message_view shows warning banner
  AppState.server_reconnecting -> banner shows attempt N/M
  AppState.server_reconnected -> banner shows success, auto-hides after 3s
  AppState.server_connection_failed -> banner shows error + retry button
  Disconnected state -> composer disables input/buttons
```

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
| `scripts/autoload/client_fetch.gd` | `fetch_messages()`, `fetch_older_messages()` -- fetches messages from server, populates `_message_cache`, emits `messages_updated` or `message_fetch_failed` |
| `scripts/autoload/client_models.gd` | `markdown_to_bbcode()`, `message_to_dict()` -- converts AccordKit models to UI dictionaries |
| `scripts/autoload/app_state.gd` | `message_sent`, `reply_initiated`, `reply_cancelled`, `message_edited`, `edit_requested`, `message_deleted`, `message_send_failed`, `message_edit_failed`, `message_delete_failed`, `message_fetch_failed`, `reactions_updated`, `reaction_failed`, `server_disconnected`, `server_reconnecting`, `server_reconnected`, `server_connection_failed` signals |

## Implementation Details

### Loading, Timeout, and Error States (message_view.gd)

- **Loading state**: When a channel is selected (line 109), `_is_loading` is set to `true` and a centered "Loading messages..." label is shown while `Client.fetch.fetch_messages()` runs. A 15-second timeout timer starts (line 119). Once `messages_updated` fires and `_load_messages()` runs, the loading label is hidden.
- **Loading timeout**: If the 15-second timer fires while still loading (line 439), the label changes to "Loading timed out. Click to retry" in red. The label becomes clickable (`MOUSE_FILTER_STOP`).
- **Fetch failure**: On `message_fetch_failed` (line 429), the loading label shows the error message in red with "Click to retry". Clicking retries `Client.fetch.fetch_messages()` (line 455).
- **Empty state**: When a channel has 0 messages, a centered `EmptyState` VBoxContainer is shown. For guild channels: "Welcome to #channel-name" / "This is the beginning of this channel. Send a message to get the conversation started!". For DM channels: "No messages yet" / "Send a message to start the conversation." (lines 137-155).
- All states are persistent child nodes of `MessageList` (alongside `OlderMessagesBtn`), toggled via visibility. The message clearing loop and message cap logic skip these persistent nodes.

### Connection Banner (message_view.gd)

- A `ConnectionBanner` PanelContainer sits above the scroll container with a status label and retry button.
- Three styled states: warning (amber, for disconnect/reconnecting), error (red, for connection failed), success (green, for reconnected).
- On `server_disconnected` (line 379): shows "Connection lost. Reconnecting..." in warning style.
- On `server_reconnecting` (line 388): shows "Reconnecting... (attempt N/M)".
- On `server_reconnected` (line 397): shows "Reconnected!" in success style, auto-hides after 3 seconds.
- On `server_connection_failed` (line 406): shows "Connection failed: [reason]" in error style with a visible Retry button.
- Retry (line 415): clears the auto-reconnect guard and calls `Client.reconnect_server()`.
- Banner only reacts to events for the guild that owns the currently viewed channel (line 376).

### Cozy vs Collapsed Layout (message_view.gd)

- Determined per-message during render (line 194): `use_collapsed = (author_id == prev_author_id) and not has_reply and i > 0`.
- First message always cozy; messages with replies always cozy.
- Consecutive same-author messages without replies use collapsed layout.
- Full list re-rendered on every `messages_updated` signal (clears all children, recreates).
- Editing state is saved before clearing and restored after re-rendering (lines 162-229).

### Auto-scroll (message_view.gd)

- `auto_scroll: bool` tracks whether user is at bottom (line 7).
- `_on_scrollbar_changed()` (line 462): If auto_scroll, scrolls to max.
- `_on_scroll_value_changed()` (line 466): Sets auto_scroll = true if within 10px of bottom.
- New messages auto-scroll only if user was already at bottom.

### Floating Action Bar (message_action_bar.gd, message_view.gd)

- A single shared `MessageActionBar` instance is owned by `message_view`, added as a `top_level` child so it renders in global coordinates (avoids ScrollContainer clipping).
- On message hover (line 271): message gets a subtle background highlight (`_draw()` with `Color(0.24, 0.25, 0.27, 0.3)`), and the bar appears at the top-right corner.
- Edit/Delete buttons only visible for the current user's own messages (message_action_bar.gd line 29).
- React button opens a `ReactionPickerScene` (message_action_bar.gd line 59), which wraps the emoji picker and calls `Client.add_reaction()`.
- **Hover state machine**: 100ms debounce timer prevents flickering when moving between messages or between a message and the bar. Mouse on bar keeps it visible. On timer timeout, bar hides if neither message nor bar is hovered (lines 297-312).
- Bar hidden and disabled in compact layout mode (`LayoutMode.COMPACT`). Hidden on channel switch and message reload.
- Suppressed when the hovered message is in inline edit mode (line 276).
- Bar positions itself relative to the scroll container bounds, hiding when the message scrolls out of view (lines 323-344).

### Context Menu (cozy_message.gd, collapsed_message.gd)

- PopupMenu with items: "Reply" (0), "Edit" (1), "Delete" (2), "Add Reaction" (3).
- Edit/Delete disabled when message author != current user (`Client.current_user.get("id")`).
- Right-click triggers `_show_context_menu(pos)` at mouse position.
- Long-press (touch) also triggers context menu via LongPressDetector.
- "Add Reaction" (id 3) opens a `ReactionPickerScene` positioned at the mouse location (cozy_message.gd line 106).
- Context menu remains fully functional alongside the floating action bar.

### Reply Reference (cozy_message.gd)

- If `data.reply_to` is non-empty, fetches original message via `Client.get_message_by_id(reply_to)` (line 61).
- Displays original author name (colored) and content preview (truncated to 50 chars) (line 67).
- Font size 12px, gray color.

### Mention Highlighting (cozy_message.gd, collapsed_message.gd)

- Checks if message content contains `@` + current user's display_name.
- Highlights entire message row with tan tint: `modulate = Color(1.0, 0.95, 0.85)` (cozy_message.gd line 79, collapsed_message.gd line 55).

### System Messages and Edit Indicator (message_content.gd)

- **System messages**: If `data.system` is true, content is rendered in italic gray instead of processing markdown (line 21).
- **(edited) indicator**: If `data.edited` is true, a small gray "(edited)" suffix is appended after the BBCode content (line 25).

### Markdown to BBCode (client_models.gd)

- `ClientModels.markdown_to_bbcode()` (line 353) performs sequential regex replacements: code blocks, inline code, strikethrough, underline, bold, italic, spoilers, links, blockquotes.
- **Emoji shortcodes**: `:name:` patterns are replaced with inline `[img]` tags pointing to `res://theme/emoji/<codepoint>.svg` (lines 399-410).
- Spoilers rendered as same-color text on same-color background, wrapped in `[url=spoiler]` for click-to-reveal. Clicking a spoiler re-renders the BBCode with visible text colors.
- Underline processed before bold to avoid `__` vs `**` conflict (line 367).

### Inline Edit Mode (message_content.gd)

- Creates TextEdit dynamically (line 39), hides original RichTextLabel (line 38).
- Line wrapping enabled, auto-height via `scroll_fit_content_height` (line 44).
- Enter (no Shift): strips whitespace, calls `AppState.edit_message()`, removes TextEdit (lines 68-71).
- Escape: removes TextEdit, restores original content (lines 73-75).
- `is_editing()` and `get_edit_text()` helpers support state preservation during re-renders.

### Composer (composer.gd)

- `_on_send()` (line 37): Validates non-empty, emits `AppState.send_message()`, clears input, cancels reply if active.
- Enter/Shift+Enter: `text_input.gui_input` connected to `_on_text_input()` (line 46); checks `KEY_ENTER` + not Shift, calls `_on_send()` + accepts event.
- **Up arrow to edit**: When Up is pressed with empty input (line 51), `_edit_last_own_message()` scans messages in reverse for the last own message, then calls `AppState.start_editing()` and emits `AppState.edit_requested` (lines 74-85).
- Reply bar: Shows "Replying to [author]" with cancel button, connected to `AppState.reply_initiated` (lines 55-62).
- Typing throttle: 8000ms minimum between `Client.send_typing()` calls (line 70).
- **Emoji picker**: Emoji button toggles an `EmojiPickerScene` positioned above the button (lines 90-136). Selected emoji inserted at cursor position as `:name:` shortcode.
- **Send failure handling** (line 138): On `message_send_failed`, restores the failed text to the input and shows an error label.
- **Disabled state** (line 147): When disconnected, `text_input.editable` is false, buttons are disabled, and placeholder changes to "Cannot send messages -- disconnected". Re-enables on reconnect.

### Reactions (reaction_pill.gd, reaction_picker.gd)

- 160 emoji textures from `EmojiData.TEXTURES` (shared with emoji picker). See [Emoji Picker](emoji_picker.md) for full catalog details.
- **Pill toggle**: Optimistic local count update, then calls `Client.add_reaction()` or `Client.remove_reaction()` (reaction_pill.gd lines 42-47). Skips API call during `setup()` via `_in_setup` guard (line 33).
- `Client.add_reaction()` and `Client.remove_reaction()` call the server. On success, they update `_message_cache` optimistically and emit `messages_updated`. On failure, they emit `AppState.reaction_failed` which causes the pill to revert its toggle state and count.
- Active style: blue background (30% opacity), 1px border, 8px rounded corners (lines 50-67).
- `reaction_bar.setup(reactions, channel_id, message_id)` passes IDs through to each pill (reaction_bar.gd line 5).
- **Reaction picker** (reaction_picker.gd): A wrapper Control that instantiates the emoji picker, positioned near the trigger point. On emoji pick, calls `Client.add_reaction()` and auto-closes.
- Reaction data from `ClientModels.message_to_dict()`: `{emoji, count, active}`.

### Typing Indicator (typing_indicator.gd)

- Three animated dots with sine-wave alpha oscillation (line 22).
- `show_typing(username)` (line 27): Sets text "[username] is typing...", starts animation, starts/restarts 10s timeout timer.
- `hide_typing()` (line 33): Hides, stops animation, stops timeout timer.
- 10s one-shot timeout timer auto-hides the indicator if `typing_stopped` never fires (e.g., if the other client disconnects).
- Connected to `AppState.typing_started` / `AppState.typing_stopped` signals (message_view.gd lines 261-267).
- Animation: `phase = anim_time * 3.0 - float(i) * 0.8`, alpha clamped 0.3-1.0 (lines 22-25).

### Embed (embed.gd)

- Renders title, description (RichTextLabel), footer (lines 19-21).
- Left border color set from embed data `color` field (lines 27-30).
- Hidden when embed dict is empty (lines 14-16).
- Multiple embeds supported: first embed uses the static scene node, additional embeds are instantiated dynamically from `EmbedScene`.

### Collapsed Message Timestamp (collapsed_message.gd)

- Timestamp is hidden by default and shown on mouse hover (lines 57-63).
- In compact layout mode (`LayoutMode.COMPACT`), timestamps are always visible (lines 68-72).

## Implementation Status

- [x] Message sending via composer
- [x] Enter to send, Shift+Enter for newline
- [x] Up arrow to edit last own message
- [x] Cozy vs collapsed message layout
- [x] Reply via action bar / context menu with reply bar
- [x] Reply reference display (author + preview)
- [x] Inline edit mode (Enter to save, Escape to cancel)
- [x] Editing state preserved across re-renders
- [x] Delete via action bar / context menu with confirmation dialog
- [x] Floating action bar on message hover (React, Reply, Edit, Delete)
- [x] Action bar hidden in compact mode, suppressed during inline edit
- [x] Message hover highlight
- [x] Context menu with ownership-based Edit/Delete disabling
- [x] Long-press context menu for touch devices
- [x] Markdown to BBCode conversion (bold, italic, code, strikethrough, underline, spoilers with click-to-reveal, links, blockquotes)
- [x] Emoji shortcode rendering (`:name:` to inline images)
- [x] Embed rendering (title, description, footer, border color) with multiple embed support
- [x] Reaction display with toggle and server API (add/remove, with error rollback)
- [x] Reaction picker (via action bar and context menu)
- [x] Typing indicator with animated dots and 10s auto-hide timeout
- [x] Typing throttle (8s between sends)
- [x] Auto-scroll (preserves position when user scrolls up)
- [x] Mention highlighting (@username tints row)
- [x] Message pagination (load older messages via "Show older messages" button)
- [x] File/image attachment rendering (images displayed inline, files as download links)
- [x] Empty channel state (welcome message with channel name)
- [x] Loading indicator with 15s timeout and click-to-retry
- [x] Message fetch failure display with click-to-retry
- [x] Message send failure display with text restoration
- [x] Connection banner (disconnect, reconnecting, reconnected, failed + retry)
- [x] Composer disabled state when disconnected
- [x] System message rendering (italic gray)
- [x] (edited) indicator on modified messages
- [x] Emoji picker in composer (insert shortcodes at cursor)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Full re-render on every update | Low | `_on_messages_updated()` clears and recreates all message nodes instead of diffing |
