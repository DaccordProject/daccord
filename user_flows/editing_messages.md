# Editing Messages

## Overview

Message editing lets users modify the content of their own messages inline. Right-clicking (or long-pressing on touch) a message opens a context menu; selecting "Edit" replaces the rendered text with an editable TextEdit. Enter saves, Escape cancels. The edit is sent to the server via REST API, and the gateway broadcasts a `message.update` event that updates the local cache and re-renders the message list. Edited messages display an "(edited)" indicator. Users can also press Up arrow in an empty composer to edit their most recent message.

## User Steps

1. User right-clicks (or long-presses) one of their own messages -- **or** presses Up arrow in an empty composer to edit their last sent message.
2. A context menu appears with "Reply", "Edit", "Delete", and "Add Reaction". "Edit" and "Delete" are disabled for other users' messages. (Skipped for Up arrow shortcut.)
3. User clicks "Edit" (or Up arrow triggers edit directly).
4. The rendered message text (RichTextLabel) is hidden and replaced by an inline TextEdit pre-filled with the raw message content.
5. User modifies the text.
6. **Enter** (without Shift): strips whitespace, saves the edit, and exits edit mode.
7. **Escape**: discards changes and exits edit mode, restoring the original text.
8. The server processes the edit; a gateway `message.update` event updates the cache and re-renders the message with an "(edited)" indicator.

## Signal Flow

```
--- Context Menu Path ---

User right-clicks message
  -> cozy_message._on_gui_input() / collapsed_message._on_gui_input()
    -> _show_context_menu(pos)
      -> Checks author.id == Client.current_user.id
      -> Disables Edit/Delete if not own message
      -> _context_menu.popup()

User selects "Edit" (id=1)
  -> _on_context_menu_id_pressed(1)
    -> AppState.start_editing(message_id)
      -> editing_message_id = message_id
      -> replying_to_message_id = "" (mutual exclusion)
    -> message_content.enter_edit_mode(message_id, content)
      -> Hides RichTextLabel (text_content.visible = false)
      -> Creates TextEdit, inserts at index 0
      -> Connects gui_input -> _on_edit_input
      -> Grabs focus

--- Up Arrow Shortcut Path ---

User presses Up arrow in empty composer
  -> composer._on_text_input(event)
    -> KEY_UP with empty text
    -> _edit_last_own_message()
      -> Scans messages in reverse for current user's last message
      -> AppState.start_editing(message_id)
      -> AppState.edit_requested.emit(message_id)
  -> message_view._on_edit_requested(message_id)
    -> Finds message node by _message_data.id match
    -> message_content.enter_edit_mode(message_id, content)

--- Save (Enter) ---

User presses Enter (no Shift)
  -> message_content._on_edit_input(event)
    -> KEY_ENTER without shift_pressed
    -> new_text = _edit_input.text.strip_edges()
    -> If not empty: AppState.edit_message(message_id, new_text)
      -> editing_message_id = ""
      -> message_edited.emit(message_id, new_content)
    -> _exit_edit_mode()
      -> _edit_input.queue_free()
      -> text_content.visible = true
    -> get_viewport().set_input_as_handled()

message_view._on_message_edited(message_id, new_content)
  -> Client.update_message_content(message_id, new_content)
    -> _find_channel_for_message(message_id) -- scans _message_cache
    -> _client_for_channel(channel_id)
    -> client.messages.edit(channel_id, message_id, {"content": new_content})
      -> PATCH /channels/{channel_id}/messages/{message_id}
    -> Server responds, gateway broadcasts message.update

--- Gateway Update ---

Gateway: message.update event
  -> client_gateway.on_message_update(message, conn_index)
    -> Finds message in _message_cache by id
    -> Replaces with ClientModels.message_to_dict(message, user_cache)
      -> Includes "edited": true (from msg.edited_at != null)
    -> AppState.messages_updated.emit(channel_id)
  -> message_view._on_messages_updated(channel_id)
    -> _load_messages(channel_id)
      -> Saves editing state (editing_id, editing_text) before clearing
      -> Re-renders all messages
      -> Restores editing state on matching message node
      -> "(edited)" indicator rendered in bbcode

--- Cancel (Escape) ---

User presses Escape
  -> message_content._on_edit_input(event)
    -> KEY_ESCAPE
    -> _exit_edit_mode()
      -> _edit_input.queue_free()
      -> text_content.visible = true
      -> _editing_message_id = ""
    -> get_viewport().set_input_as_handled()
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/cozy_message.gd` | Context menu setup, ownership check, calls `AppState.start_editing()` then `enter_edit_mode()` (lines 86-92) |
| `scenes/messages/collapsed_message.gd` | Same context menu and edit dispatch for collapsed messages (lines 81-87) |
| `scenes/messages/message_content.gd` | Inline edit mode: TextEdit creation, "(edited)" indicator, `is_editing()`/`get_edit_text()` helpers, Enter/Escape handling (lines 10-69) |
| `scripts/autoload/app_state.gd` | `start_editing()` (line 82), `edit_message()` (line 86), `message_edited` signal (line 9), `edit_requested` signal (line 11), `editing_message_id` state (line 50) |
| `scenes/messages/message_view.gd` | Connects `message_edited` and `edit_requested` signals, calls `Client.update_message_content()`, preserves edit state across re-renders (lines 22-25, 71-142, 148-149, 154-162) |
| `scenes/messages/composer/composer.gd` | Up arrow shortcut: `_edit_last_own_message()` scans messages in reverse for last own message (lines 45-47, 68-79) |
| `scripts/autoload/client.gd` | `update_message_content()` REST call via `client.messages.edit()` (lines 357-378), `_find_channel_for_message()` helper (lines 827-832) |
| `scripts/autoload/client_gateway.gd` | `on_message_update()` updates cache, emits `messages_updated` (lines 52-60) |
| `scripts/autoload/client_models.gd` | `message_to_dict()` converts AccordMessage to UI dict, includes `"edited"` flag (lines 172-226) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `edit()` method: PATCH to `/channels/{id}/messages/{id}` (lines 47-52) |
| `addons/accordkit/models/message.gd` | `AccordMessage` model with `edited_at` field (line 13) |

## Implementation Details

### Ownership Check (cozy_message.gd, collapsed_message.gd)

Both message layouts perform the same ownership check when showing the context menu (cozy: line 80, collapsed: line 75):

```gdscript
var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
_context_menu.set_item_disabled(1, not is_own)  # Edit
_context_menu.set_item_disabled(2, not is_own)  # Delete
```

The context menu items are added in `_ready()` with fixed IDs: Reply=0, Edit=1, Delete=2, Add Reaction=3.

### Edit Dispatch (cozy_message.gd:91-92, collapsed_message.gd:86-87)

When the user selects "Edit" from the context menu, both layouts first call `AppState.start_editing()` to set editing state (which also clears any pending reply via mutual exclusion), then call `message_content.enter_edit_mode()`:

```gdscript
AppState.start_editing(_message_data.get("id", ""))
message_content.enter_edit_mode(_message_data.get("id", ""), _message_data.get("content", ""))
```

### Up Arrow Keyboard Shortcut (composer.gd)

When the user presses Up arrow in an empty composer (line 45), `_edit_last_own_message()` (line 68) scans the current channel's messages in reverse to find the last message authored by the current user. It then calls `AppState.start_editing()` and emits `AppState.edit_requested` to route the request to `message_view`:

```gdscript
AppState.start_editing(msg.get("id", ""))
AppState.edit_requested.emit(msg.get("id", ""))
```

`message_view._on_edit_requested()` (line 154) iterates message nodes to find the one with a matching `_message_data.id` and calls `enter_edit_mode()` on its `message_content` child.

### Inline Edit Mode (message_content.gd)

`enter_edit_mode()` (line 30) creates the edit UI:
- Stores `_editing_message_id` for the save call.
- Hides `text_content` (RichTextLabel) by setting `visible = false`.
- Creates a new `TextEdit` with `custom_minimum_size = Vector2(0, 36)`, `SIZE_EXPAND_FILL`, `LINE_WRAPPING_BOUNDARY`, and `scroll_fit_content_height = true`.
- Connects `gui_input` to `_on_edit_input`.
- Inserts the TextEdit as the first child (`move_child(_edit_input, 0)`) so it appears at the top of the content column, above the embed and reaction bar.
- Calls `grab_focus()` to immediately place the cursor in the editor.

### "(edited)" Indicator (message_content.gd, client_models.gd)

`ClientModels.message_to_dict()` (line 221) now includes `"edited": msg.edited_at != null` in the output dictionary. In `message_content.setup()` (line 18), when `data.get("edited", false)` is true, a styled "(edited)" label is appended to the BBCode:

```gdscript
if data.get("edited", false):
    bbcode += " [font_size=11][color=#8a8e94](edited)[/color][/font_size]"
```

### Edit State Helpers (message_content.gd)

Two helper methods support edit state preservation:
- `is_editing()` (line 44): Returns `true` if `_edit_input` exists (edit mode is active).
- `get_edit_text()` (line 47): Returns the current text in the edit TextEdit, or empty string if not editing.

### Save and Cancel (message_content.gd)

`_on_edit_input()` (line 59) handles keyboard events:
- **Enter** (without Shift, line 61): Strips whitespace with `strip_edges()`. If the result is non-empty, calls `AppState.edit_message()` which emits `message_edited`. Then calls `_exit_edit_mode()` and consumes the event.
- **Escape** (line 67): Calls `_exit_edit_mode()` and consumes the event. No save occurs.

`_exit_edit_mode()` (line 52):
- Calls `queue_free()` on the TextEdit.
- Restores `text_content.visible = true`.
- Clears `_editing_message_id`.

### Edit Mode Preservation (message_view.gd)

When `_load_messages()` runs (line 71), it saves the current editing state before clearing message nodes:
- Reads `AppState.editing_message_id` (line 73).
- If editing, iterates children to find the active `message_content` and saves the in-progress text via `mc.get_edit_text()` (lines 75-82).
- After re-rendering all messages, restores edit mode on the matching message node by calling `mc.enter_edit_mode(editing_id, editing_text)` (lines 128-137).

This prevents losing in-progress edits when a `messages_updated` event fires (e.g., a new message arrives or a reaction is added).

### Server-side Update (client.gd)

`update_message_content()` (line 357):
- Uses `_find_channel_for_message()` (line 827) to scan `_message_cache` for the channel containing the message.
- Routes to the correct `AccordClient` via `_client_for_channel()`.
- Calls `client.messages.edit(channel_id, message_id, {"content": new_content})`, which sends a `PATCH` request.
- Errors are logged via `push_error()` but not surfaced to the UI.

### Gateway Update (client_gateway.gd)

`on_message_update()` (line 52):
- Finds the message in `_message_cache[channel_id]` by ID.
- Replaces the cached dict with a fresh `ClientModels.message_to_dict()` conversion (which now includes the `"edited"` flag).
- Emits `AppState.messages_updated` which triggers a full re-render of the message list.

### AppState Editing State (app_state.gd)

Three methods and two signals manage editing state:
- `start_editing(message_id)` (line 82): Sets `editing_message_id`, clears `replying_to_message_id` (mutual exclusion with reply). Does **not** emit a signal.
- `edit_message(message_id, new_content)` (line 86): Clears `editing_message_id`, emits `message_edited` signal.
- `edit_requested` signal (line 11): Emitted by the composer's Up arrow shortcut to request editing a message from outside the message node tree. Connected in `message_view._ready()`.

The `editing_message_id` and `replying_to_message_id` are mutually exclusive -- starting an edit cancels any pending reply, and initiating a reply clears any editing state.

## Implementation Status

- [x] Context menu with "Edit" option on messages
- [x] Ownership check disables "Edit" for other users' messages
- [x] Inline TextEdit replaces rendered content
- [x] Enter saves, Escape cancels
- [x] Empty edits (whitespace-only) are silently discarded (no API call)
- [x] REST API call via PATCH to update message content
- [x] Gateway `message.update` event updates cache and re-renders
- [x] Edit/Reply mutual exclusion in AppState
- [x] Long-press support for touch context menu
- [x] "(edited)" indicator on edited messages
- [x] `AppState.start_editing()` called during edit flow (from context menu and Up arrow)
- [x] Keyboard shortcut to edit last message (Up arrow in empty composer)
- [x] Edit mode preserved across re-renders
- [ ] Visual feedback during save (loading/pending state)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No error feedback to user | Medium | `Client.update_message_content()` logs errors via `push_error()` (line 375) but never surfaces failures to the UI. If the edit fails (network error, permissions), the user sees the message revert on re-render with no explanation |
| No save-in-progress indicator | Low | After pressing Enter, the edit exits immediately and the old text shows until the gateway event arrives with the updated content. There's a brief flash of the old content |
| Empty edit silently discarded | Low | If the user clears the content and presses Enter, the edit is skipped (line 63 in message_content.gd). No feedback is given. Could offer to delete the message instead |
| Shift+Enter doesn't insert newline in edit | Low | The `_on_edit_input` handler (line 61) only checks for Enter without Shift to save. Shift+Enter falls through to default TextEdit behavior, which does work, but there's no visual hint that multiline editing is supported |
