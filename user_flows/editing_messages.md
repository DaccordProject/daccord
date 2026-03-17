# Editing Messages

Priority: 10
Depends on: Messaging
Status: Complete

Inline message editing with ownership checks, Enter/Escape handling, REST PATCH, gateway update, editing state preservation across re-renders, Up arrow shortcut, and "(edited)" indicator.

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
