# Voice Text Chat

## Overview

Discord-style text chat within voice channels. Each voice channel item in the sidebar has a small chat icon button (visible on hover). Clicking this button opens the voice channel's text chat as a separate column to the right of the current content area -- the same way Discord shows voice channel text. The chat button stops click propagation so it does **not** also trigger the voice channel click (join/leave/open voice view).

## User Steps

1. User sees a voice channel in the sidebar; hovering reveals a chat icon button
2. User clicks the chat icon button on the voice channel item
3. The click is consumed by the button -- it does **not** propagate to the voice channel click handler (no join/leave/voice view toggle)
4. A text chat column appears to the right of the current content area, showing message history for that voice channel
5. User types a message in the voice text composer and presses Enter to send
6. Messages appear in the chat column for all participants in the voice channel
7. Typing indicators show which participants are typing
8. User can close the voice text column via the close button on the column header
9. The voice text column is independent of the voice view -- it can be open whether or not the user is in the voice channel or has the voice view open
10. Clicking the chat button again when the column is already open closes it (toggle behavior)

## Signal Flow

```
voice_channel_item.gd                       AppState                    main_window.gd
     |                                           |                           |
     | (user clicks chat icon button)            |                           |
     | (_chat_just_pressed flag prevents         |                           |
     |  channel_pressed from firing)             |                           |
     |-- AppState.toggle_voice_text(cid) ------->|                           |
     |                                           |-- voice_text_opened(cid)->|
     |                                           |                           |-- _sync_handle_visibility()
     |                                           |                           |
     |                                    voice_text_panel.gd                |
     |                                           |                           |
     |                                           |-- _on_voice_text_opened() |
     |                                           |-- Client.fetch.fetch_messages(cid)
     |                                           |<- messages_updated(cid)   |
     |                                           |-- _render_messages()      |
     |                                           |                           |
     | (user sends message)                      |                           |
     |                                           |-- Client.send_message_to_channel(cid, text)
     |                                           |                           |
     | (user clicks chat button again or close)  |                           |
     |                                           |-- voice_text_closed() --->|
     |                                           |                           |-- _sync_handle_visibility()
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel sidebar item -- chat icon button with `_chat_just_pressed` propagation suppression |
| `scenes/sidebar/channels/voice_channel_item.tscn` | Voice channel item scene -- chat button added programmatically in `setup()` |
| `scenes/sidebar/channels/channel_list.gd` | Routes voice channel clicks to join (unchanged) -- chat button bypasses this |
| `scenes/messages/voice_text_panel.gd` | Voice text chat panel -- message list, composer, typing indicator targeting a voice channel ID |
| `scenes/messages/voice_text_panel.tscn` | Voice text panel scene -- PanelContainer with header, message list, typing indicator, composer |
| `scenes/main/main_window.gd` | Manages content layout -- shows/hides voice text panel, resize handle, voice view coexistence |
| `scenes/main/main_window.tscn` | Scene layout -- VoiceTextPanel is a child of `ContentBody` |
| `scripts/autoload/app_state.gd` | `voice_text_opened(channel_id)` / `voice_text_closed` signals, `voice_text_channel_id` state |
| `scripts/autoload/client.gd` | `get_messages_for_channel()`, `send_message_to_channel()`, `send_typing()` -- all channel-type agnostic |
| `addons/accordkit/rest/endpoints/messages_api.gd` | REST message CRUD -- channel-type agnostic |

## Implementation Details

### Chat Icon Button on Voice Channel Item

`voice_channel_item.gd` creates a chat icon button programmatically in `setup()` (line 79). The button uses `assets/theme/icons/chat.svg` (line 6), is hidden by default and shown on hover (lines 258-268), and uses the same propagation-suppression pattern as the gear button:

- `_chat_just_pressed` flag (line 18) is set in `_on_chat_pressed()` (line 253)
- `channel_button.pressed` callback checks the flag and early-returns (lines 36-38)
- `_on_chat_pressed()` calls `AppState.toggle_voice_text(channel_id)` (line 255)

### AppState Voice Text Signals

`app_state.gd` declares two signals (lines 80, 82):
- `voice_text_opened(channel_id: String)` -- emitted when voice text panel should open
- `voice_text_closed()` -- emitted when voice text panel should close

State variable `voice_text_channel_id` (line 203) tracks the currently-open voice text channel.

Helper methods (lines 359-373):
- `toggle_voice_text(channel_id)` -- closes if same channel, opens otherwise
- `open_voice_text(channel_id)` -- sets state and emits `voice_text_opened`
- `close_voice_text()` -- clears state and emits `voice_text_closed`

### Voice Text Panel

`voice_text_panel.gd` is a self-contained panel that manages its own message list and composer, independent of `AppState.current_channel_id`. Key behaviors:

- **Opening:** `_on_voice_text_opened()` (line 30) looks up the channel name, clears old messages, calls `Client.fetch.fetch_messages(channel_id)`, and focuses the text input
- **Message rendering:** `_render_messages()` (line 56) uses cozy/collapsed message layout (same `CozyMessageScene`/`CollapsedMessageScene` as the main message view)
- **Sending:** `_on_send()` (line 88) calls `Client.send_message_to_channel(_channel_id, text)` directly -- bypasses `AppState.send_message()` since that targets the main channel
- **Typing:** `_on_text_changed()` (line 99) sends typing indicators via `Client.send_typing(_channel_id)` with a 5-second cooldown
- **Typing display:** Connects to `AppState.typing_started` / `typing_stopped` (lines 107-112) and filters by `_channel_id`
- **Keyboard:** Enter sends, Shift+Enter for newline, Escape closes (lines 93-98)
- **Closing:** `_on_close()` calls `AppState.close_voice_text()`, which hides the panel and clears message nodes

### Voice Text Panel in Content Layout

`main_window.gd` places the voice text panel inside `ContentBody` (the HBox alongside `MessageView`, `ThreadPanel`, `MemberList`, `SearchPanel`) at path `LayoutHBox/ContentArea/ContentBody/VoiceTextPanel` (line 54).

A `PanelResizeHandle` is created for the panel (lines 164-169) with min width 240px and default 300px, following the same pattern as thread/member/search panels.

Panel visibility is synced via `_sync_handle_visibility()` (line 402) and included in `_clamp_panel_widths()` budget calculations (lines 419, 435-436).

### Voice View Coexistence

When the voice view opens, `_on_voice_view_opened()` (line 638) checks if the voice text panel is visible. If so, instead of hiding `content_body` entirely, it hides all children of `content_body` *except* the voice text panel (lines 639-641). This allows voice text chat to remain visible alongside the video grid. When voice view closes, `_on_voice_view_closed()` restores `content_body` and its children (lines 645-650).

### Voice Channel Click Behavior (Unchanged)

`channel_list.gd:_on_channel_pressed()` (line 185) checks if the channel type is `VOICE` (line 192). If so, it joins voice via `Client.join_voice_channel()` and returns early without emitting `channel_selected`. The chat button bypasses this entirely.

### Unread Indicators on Voice Channel Items

`voice_channel_item.gd` mirrors the unread dot pattern from `channel_item.gd`:

- `_has_unread` flag and `UnreadDot` ColorRect (8x8, white) in the scene (same as text channels)
- `setup()` reads `data.get("unread", false)` and sets dot visibility
- Connects to `AppState.channels_updated` to refresh unread state when gateway marks the channel unread
- Connects to `AppState.voice_text_opened` to clear unread via `Client.clear_channel_unread()` when the panel opens
- `_apply_text_color()` uses white text when `_has_unread` is true (same as `_is_active` or connected)

### Notification Suppression for Voice Text Panel

`client_gateway.gd` on_message_create checks whether the channel is currently viewed before marking unread. The check includes both `AppState.current_channel_id` (main message view) and `AppState.voice_text_channel_id` (voice text panel). Messages arriving while the voice text panel is open for that channel are not marked unread.

### Pagination in Voice Text Panel

`voice_text_panel.gd` includes a "Show older messages" button at the top of the message list:

- Created in `_ready()` and persisted across re-renders (skipped in `queue_free()` loops)
- Shown when `messages.size() >= Client.MESSAGE_CAP` (same heuristic as main message view)
- `_on_older_messages_pressed()` follows the same pattern as `message_view_scroll.gd`: saves scroll position, calls `Client.fetch.fetch_older_messages()`, awaits `messages_updated`, then restores scroll offset
- `_is_loading_older` flag prevents scroll-to-bottom during older message loads

### Messages API Compatibility

The REST messages API (`messages_api.gd`) is **channel-type agnostic** -- `list()`, `create()`, `edit()`, `typing()`, and `delete()` all operate on a `channel_id` without checking the channel type. Whether the **server** (accordserver) accepts message operations on voice channels depends on its implementation, but the client-side API layer has no restrictions.

### Space Change Cleanup

When the user selects a different space, `main_window.gd:_on_space_selected()` (line 490) calls `AppState.close_voice_text()` to close any open voice text panel, since the voice channel belongs to the previous space.

## Implementation Status

- [x] Voice channels exist as a distinct `ChannelType.VOICE` in `ClientModels` (line 7)
- [x] Voice channel sidebar items show participants, speaking indicators, mute/deaf/video/stream badges
- [x] Voice view opens full-area video grid when user clicks voice bar or re-clicks voice channel
- [x] REST messages API is channel-type agnostic (works for any channel ID)
- [x] Message cache (`get_messages_for_channel`) works for any channel ID
- [x] Chat icon button on voice channel sidebar item with propagation suppression (`_chat_just_pressed`)
- [x] `voice_text_opened` / `voice_text_closed` signals and `voice_text_channel_id` state in AppState
- [x] `toggle_voice_text()` / `open_voice_text()` / `close_voice_text()` helper methods in AppState
- [x] Voice text panel (`voice_text_panel.gd/.tscn`) with message list, composer, typing indicator
- [x] Panel added to `ContentBody` in `main_window.tscn` with resize handle
- [x] Message fetching triggered by opening voice text chat
- [x] Dedicated composer for voice text (targets voice channel ID via `_channel_id`, not `current_channel_id`)
- [x] Typing indicators in voice text chat (sends and receives)
- [x] Voice view coexistence -- voice text panel survives `_on_voice_view_opened` hiding other content
- [x] Space change cleanup -- voice text panel closes on space switch
- [x] Unread indicators for voice channel text messages (UnreadDot on voice_channel_item, cleared on panel open)
- [x] Notification support -- gateway suppresses unread when voice text panel is viewing the channel
- [x] Pagination / scroll-back in voice text history ("Show older messages" button)
- [ ] No voice text chat in PiP mode

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Server-side voice channel message support unknown | Medium | `messages_api.gd` is type-agnostic but accordserver may reject message operations on voice channels. Needs server-side verification |
| No voice text chat in PiP mode | Low | `video_pip.gd` is a minimal floating preview with no text chat capability |
| No compact layout handling | Low | Voice text panel has no special handling for `LayoutMode.COMPACT` -- could replace message view like thread panel does |
