# Message Reactions

*Last touched: 2026-02-18 20:21*

## Overview

Users can add emoji reactions to any message. Reactions appear as clickable pills below the message content, showing the emoji and a count. Clicking an existing reaction pill toggles the current user's reaction on/off. Users can also add new reactions via the emoji picker, accessible from the message action bar or right-click context menu. All reaction changes propagate in real-time to other clients via WebSocket gateway events.

## User Steps

### Adding a reaction via the action bar
1. Hover over a message to reveal the action bar (top-right of the message).
2. Click the React button (smiley face icon).
3. The emoji picker opens near the button.
4. Click an emoji to add it as a reaction.
5. The reaction pill appears below the message with count 1 and a blue highlight (active state).

### Adding a reaction via the context menu
1. Right-click a message (or long-press on touch) to open the context menu.
2. Select "Add Reaction".
3. The emoji picker opens at the cursor position.
4. Click an emoji to add it as a reaction.

### Toggling an existing reaction
1. Click a reaction pill below a message.
2. If the pill was inactive (grey), it becomes active (blue border) and the count increments.
3. If the pill was active (blue), it becomes inactive and the count decrements.
4. If the count reaches 0, the pill is removed on the next UI rebuild.

### Receiving a reaction from another user
1. Another user adds or removes a reaction on a message in the current channel.
2. The server broadcasts a gateway event (`reaction.add` / `reaction.remove`).
3. The reaction pill appears, updates its count, or is removed automatically.

## Signal Flow

```
User clicks React button / context menu "Add Reaction"
    │
    ▼
message_action_bar._on_react_pressed()  ─or─  cozy/collapsed_message._open_reaction_picker()
    │
    ▼
reaction_picker.open(channel_id, message_id, position)
    │
    ▼
emoji_picker  ──emoji_picked signal──▶  reaction_picker._on_emoji_picked()
    │
    ▼
Client.add_reaction(channel_id, message_id, emoji)
    │
    ├──▶  AccordClient.reactions.add()  ──REST PUT──▶  Server
    │
    └──▶  Optimistic cache update  ──▶  AppState.messages_updated.emit(channel_id)
                                            │
                                            ▼
                                        message_view._on_messages_updated()
                                            │
                                            ▼
                                        _load_messages() rebuilds all message nodes
                                            │
                                            ▼
                                        message_content.setup()  ──▶  reaction_bar.setup()
                                            │
                                            ▼
                                        ReactionPill for each reaction (emoji + count + active state)
```

### Gateway event flow (other users' reactions)

```
Server broadcasts gateway event
    │
    ▼
GatewaySocket._dispatch_event("reaction.add", data)
    │
    ▼
GatewaySocket.reaction_add signal
    │
    ▼
AccordClient.reaction_add signal  (re-emitted)
    │
    ▼
ClientGateway.on_reaction_add(data)
    │
    ├──▶  Updates Client._message_cache[channel_id]
    │
    └──▶  AppState.messages_updated.emit(channel_id)
                │
                ▼
            message_view._load_messages()  ──▶  Full UI rebuild
```

### Toggling an existing pill

```
User clicks ReactionPill (toggle button)
    │
    ▼
reaction_pill._on_toggled(toggled_on)
    │
    ├──▶  Optimistic local update: count +/- 1, style change (immediate)
    │
    └──▶  Client.add_reaction() or Client.remove_reaction()
              │
              ├──▶  REST call to server
              └──▶  Cache update + AppState.messages_updated  ──▶  Full UI rebuild
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/reaction_pill.gd` | Toggle button for a single reaction; optimistic update + API call |
| `scenes/messages/reaction_bar.gd` | FlowContainer that creates ReactionPill instances for a message |
| `scenes/messages/reaction_picker.gd` | Wrapper that opens the emoji picker and calls `Client.add_reaction()` |
| `scenes/messages/message_content.gd` | Passes reactions array to `reaction_bar.setup()` (line 56) |
| `scenes/messages/message_action_bar.gd` | Action bar with React button; opens reaction picker (line 47) |
| `scenes/messages/cozy_message.gd` | Context menu "Add Reaction" entry; opens reaction picker (line 108) |
| `scenes/messages/collapsed_message.gd` | Context menu "Add Reaction" entry; opens reaction picker (line 98) |
| `scenes/messages/message_view.gd` | Listens to `messages_updated`; rebuilds message list (line 251) |
| `scenes/messages/composer/emoji_picker.gd` | Grid of emoji with search; emits `emoji_picked` signal |
| `scripts/autoload/client.gd` | `add_reaction()` / `remove_reaction()` methods (lines 562-644) |
| `scripts/autoload/client_gateway.gd` | Handles gateway reaction events; updates cache (lines 395-475) |
| `scripts/autoload/app_state.gd` | Declares `messages_updated`, `reactions_updated`, `reaction_failed` signals |
| `scripts/autoload/client_models.gd` | Converts `AccordReaction` to dictionary shape (lines 244-252) |
| `addons/accordkit/.../gateway_socket.gd` | Dispatches `reaction.add/remove/clear/clear_emoji` events |
| `addons/accordkit/.../accord_client.gd` | Re-emits gateway reaction signals |
| `addons/accordkit/.../reactions_api.gd` | REST endpoints: `add`, `remove_own`, `remove_user`, `list_users`, `remove_all`, `remove_emoji` |
| `addons/accordkit/.../reaction.gd` | `AccordReaction` model: `emoji` (Dictionary), `count` (int), `includes_me` (bool) |

## Implementation Details

### Reaction Data Shape

Reactions are stored in the message cache as an array of dictionaries:

```gdscript
# Client._message_cache[channel_id][i]["reactions"]
[
    {"emoji": "thumbsup", "count": 3, "active": true},
    {"emoji": "heart", "count": 1, "active": false},
]
```

- `emoji` -- The emoji name string (e.g. `"thumbsup"`, `"tada"`).
- `count` -- Total number of users who reacted with this emoji.
- `active` -- `true` if the current user has this reaction.

### AccordReaction Model

`AccordReaction` (`addons/accordkit/.../reaction.gd`) has three fields:
- `emoji: Dictionary` -- Contains `"id"` (nullable) and `"name"` (string). Custom emoji have both; built-in emoji only have `"name"`.
- `count: int` -- Number of users who reacted.
- `includes_me: bool` -- Whether the authenticated user reacted.

`ClientModels.message_to_dict()` (line 244) converts this to the UI dictionary shape, mapping `reaction.emoji.get("name", "")` to the `"emoji"` key and `reaction.includes_me` to `"active"`.

### Adding a Reaction (Client)

`Client.add_reaction()` (line 562) routes to the correct `AccordClient` via `_client_for_channel()`, calls `client.reactions.add(cid, mid, emoji)`, and on success performs an optimistic cache update: it finds the message in `_message_cache[cid]`, increments the count on a matching emoji entry (or appends a new one with `count: 1`), and emits `AppState.messages_updated`.

`Client.remove_reaction()` (line 605) follows the same pattern but calls `client.reactions.remove_own()`, decrements the count, sets `active = false`, and removes the entry if count reaches 0.

### Optimistic Updates

Reactions use a two-layer optimistic update:

1. **Pill-level** (`reaction_pill.gd`, line 32): When the user toggles a pill, the count and style update immediately in `_on_toggled()` before the API call fires. This provides instant visual feedback.

2. **Client-level** (`client.gd`, lines 583-603): After the REST call succeeds, the message cache is updated and `messages_updated` is emitted, triggering a full UI rebuild.

### Gateway Event Handling

`ClientGateway` handles four reaction event types:

- **`on_reaction_add`** (line 395): Parses `channel_id`, `message_id`, `user_id`, and `emoji` from the event data. Finds the message in cache, increments or creates the reaction entry. Sets `active = true` if `user_id` matches the current user. Emits `messages_updated`.

- **`on_reaction_remove`** (line 424): Decrements the count, sets `active = false` if the current user removed their reaction, and removes the entry if count reaches 0.

- **`on_reaction_clear`** (line 447): Sets the message's `reactions` array to `[]`.

- **`on_reaction_clear_emoji`** (line 459): Removes all reactions for a specific emoji from the message.

The `_parse_emoji_name()` helper (line 387) normalizes the emoji field, which may be a string or a `{"name": "..."}` dictionary from the server.

### Reaction Picker

`reaction_picker.gd` is a lightweight wrapper around the emoji picker. When opened via `open(channel_id, message_id, position)` (line 12), it instantiates the `EmojiPickerScene`, positions it on screen (clamped to viewport bounds), and connects the `emoji_picked` signal. When an emoji is selected, `_on_emoji_picked()` (line 26) calls `Client.add_reaction()` and emits `reaction_added`, then closes.

Custom emoji keys arrive from the picker in `"custom:name:id"` format. The reaction picker strips the `"custom:"` prefix (line 29-30) before passing the key to `Client.add_reaction()`.

### Reaction Pill Rendering

`reaction_bar.gd` is a `FlowContainer` that creates a `ReactionPill` for each entry in the reactions array (line 5). It injects `channel_id` and `message_id` into each reaction dictionary so pills can make API calls.

`reaction_pill.gd` extends `Button` with `toggle_mode`. In `setup()` (line 17), it sets the emoji texture from `EmojiData.TEXTURES`, the count label, and the pressed state from the `active` flag. The `_in_setup` guard (line 7) prevents `_on_toggled` from firing during setup.

Active pills are styled with a blue `StyleBoxFlat` (line 49): `bg_color = Color(0.345, 0.396, 0.949, 0.3)` with a 1px border in `Color(0.345, 0.396, 0.949)` and 8px corner radius.

### Context Menu Integration

Both `cozy_message.gd` (line 38) and `collapsed_message.gd` (line 31) add an "Add Reaction" entry (ID 3) to their context menus. Unlike "Edit" and "Delete", this entry is never disabled -- any user can add a reaction. When selected (line 108 / line 98), `_open_reaction_picker()` instantiates a `ReactionPickerScene` at the cursor position.

### Action Bar Integration

`message_action_bar.gd` (line 13) has a React button. When pressed (line 47), `_open_reaction_picker()` (line 59) instantiates the picker at the button's position. The picker is added to the scene tree root so it renders above all other UI. The bar keeps `_message_data` alive while the picker is open (line 38) so the callback can still read `channel_id` and `message_id` after the bar auto-hides.

### Full Message List Rebuild

When `AppState.messages_updated` fires, `message_view._on_messages_updated()` (line 251) calls `_load_messages()` which destroys all message nodes and recreates them from cache. This means every reaction change rebuilds the entire visible message list, not just the affected message.

## Implementation Status

- [x] Add reaction via action bar React button
- [x] Add reaction via context menu "Add Reaction"
- [x] Toggle existing reaction by clicking pill
- [x] Optimistic UI update on pill toggle (instant feedback)
- [x] REST API calls for add/remove reactions
- [x] Gateway event handling for `reaction.add`
- [x] Gateway event handling for `reaction.remove`
- [x] Gateway event handling for `reaction.clear`
- [x] Gateway event handling for `reaction.clear_emoji`
- [x] Active state tracking (blue highlight for current user's reactions)
- [x] Custom emoji support in reaction picker
- [x] Error signal (`reaction_failed`) on API failure
- [ ] Dedicated `reactions_updated` signal (declared but unused)
- [ ] Reaction tooltip showing who reacted
- [ ] "Remove all reactions" UI (admin-only; API exists)
- [ ] Rollback optimistic update on API failure
- [ ] Prevent duplicate API calls (gateway event + optimistic update both mutate cache)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Double cache mutation on own reactions | Medium | When the current user adds a reaction, both `reaction_pill._on_toggled()` (optimistic, line 36) and `Client.add_reaction()` (post-REST, line 583) update the cache and emit `messages_updated`. Then the gateway event in `ClientGateway.on_reaction_add()` (line 395) does it a third time. The message list rebuilds 2-3 times for a single click. |
| `reactions_updated` signal declared but unused | Low | `AppState` declares `reactions_updated(channel_id, message_id)` (line 44) but no code emits or connects to it. All reaction updates go through the broader `messages_updated` signal, which triggers a full message list rebuild. |
| No rollback on API failure | Medium | If `Client.add_reaction()` fails (line 575), `reaction_failed` is emitted but the optimistic update from `reaction_pill._on_toggled()` (line 36) is not reverted. The pill shows the wrong count until the next `messages_updated` rebuild. |
| No reaction tooltip | Low | Hovering a reaction pill does not show which users reacted. The `ReactionsApi.list_users()` endpoint exists but is not called anywhere in the client. |
| Inactive pill style not explicitly set | Low | `_update_active_style()` (line 49) only sets the style when `button_pressed` is `true`. When inactive, it relies on the default Button style from the theme, which works but means inactive pills don't have an explicit dark background style. |
| Full message list rebuild per reaction | Medium | Every reaction change (own or remote) triggers `_load_messages()` which destroys and recreates all message nodes. Using the dedicated `reactions_updated` signal to surgically update just the affected message's reaction bar would be more efficient. |
| Custom emoji not rendered on pills | Medium | `reaction_pill.setup()` (line 25) only checks `EmojiData.TEXTURES` for built-in emoji. Custom emoji (which are loaded from CDN in the emoji picker) won't have entries in `EmojiData.TEXTURES`, so custom reaction pills show no icon -- only the count. |
