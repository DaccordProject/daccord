# Message Reactions


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

### Removing all reactions (admin)
1. Right-click a message that has reactions.
2. Select "Remove All Reactions" (requires MANAGE_MESSAGES permission; disabled otherwise).
3. All reaction pills are removed from the message.
4. The server broadcasts a `reaction.clear` gateway event to other clients.

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
    └──▶  (other user)  AppState.reactions_updated.emit(channel_id, message_id)
         (own user)    Signal skipped — pill already shows optimistic state
                │
                ▼
            message_view._on_reactions_updated()
                │
                ▼
            Targeted reaction_bar.setup() on affected message only
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
| `scenes/messages/cozy_message.gd` | Context menu "Add Reaction" and "Remove All Reactions" (admin) entries |
| `scenes/messages/collapsed_message.gd` | Context menu "Add Reaction" and "Remove All Reactions" (admin) entries |
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

Reactions use an optimistic update with rollback:

1. **Pill-level** (`reaction_pill.gd`): When the user toggles a pill, the count and style update immediately in `_on_toggled()` before the API call fires. This provides instant visual feedback.

2. **Gateway deduplication**: When the gateway event for the user's own reaction arrives, `ClientGateway` updates the cache silently without emitting a signal, since the pill already shows the correct state.

3. **Rollback on failure**: If the REST call fails, `reaction_failed` is emitted and `reaction_pill._on_reaction_failed()` reverts the optimistic update (toggles the pressed state back and adjusts the count).

### Gateway Event Handling

`ClientGateway` handles four reaction event types, all emitting the targeted `reactions_updated(channel_id, message_id)` signal instead of the broader `messages_updated`:

- **`on_reaction_add`**: Parses `channel_id`, `message_id`, `user_id`, and `emoji` from the event data. Finds the message in cache, increments or creates the reaction entry. Sets `active = true` if `user_id` matches the current user. Skips emitting the signal for the current user's own reactions (the pill already shows the correct optimistic state).

- **`on_reaction_remove`**: Decrements the count, sets `active = false` if the current user removed their reaction, and removes the entry if count reaches 0. Also skips signaling for own reactions.

- **`on_reaction_clear`**: Sets the message's `reactions` array to `[]`. Always emits `reactions_updated`.

- **`on_reaction_clear_emoji`**: Removes all reactions for a specific emoji from the message.

The `_parse_emoji_name()` helper normalizes the emoji field, which may be a string or a `{"name": "..."}` dictionary from the server.

### Reaction Picker

`reaction_picker.gd` is a lightweight wrapper around the emoji picker. When opened via `open(channel_id, message_id, position)` (line 12), it instantiates the `EmojiPickerScene`, positions it on screen (clamped to viewport bounds), and connects the `emoji_picked` signal. When an emoji is selected, `_on_emoji_picked()` (line 26) calls `Client.add_reaction()` and emits `reaction_added`, then closes.

Custom emoji keys arrive from the picker in `"custom:name:id"` format. The reaction picker strips the `"custom:"` prefix (line 29-30) before passing the key to `Client.add_reaction()`.

### Reaction Pill Rendering

`reaction_bar.gd` is a `FlowContainer` that creates a `ReactionPill` for each entry in the reactions array (line 5). It injects `channel_id` and `message_id` into each reaction dictionary so pills can make API calls.

`reaction_pill.gd` extends `Button` with `toggle_mode`. In `setup()` (line 17), it sets the emoji texture from `EmojiData.TEXTURES`, the count label, and the pressed state from the `active` flag. The `_in_setup` guard (line 7) prevents `_on_toggled` from firing during setup.

Both active and inactive pill styles are explicitly set in `_update_active_style()`. Active pills use a blue `StyleBoxFlat`: `bg_color = Color(0.345, 0.396, 0.949, 0.3)` with a blue border. Inactive pills use a dark `StyleBoxFlat`: `bg_color = Color(0.184, 0.192, 0.212, 1)` with a subtle border. Both use 8px corner radius and 1px borders. The pill also shows a tooltip with the emoji name (e.g. `":thumbsup:"`).

### Context Menu Integration

Both `cozy_message.gd` (line 38) and `collapsed_message.gd` (line 31) add an "Add Reaction" entry (ID 3) to their context menus. Unlike "Edit" and "Delete", this entry is never disabled -- any user can add a reaction. When selected (line 108 / line 98), `_open_reaction_picker()` instantiates a `ReactionPickerScene` at the cursor position.

### Action Bar Integration

`message_action_bar.gd` (line 13) has a React button. When pressed (line 47), `_open_reaction_picker()` (line 59) instantiates the picker at the button's position. The picker is added to the scene tree root so it renders above all other UI. The bar keeps `_message_data` alive while the picker is open (line 38) so the callback can still read `channel_id` and `message_id` after the bar auto-hides.

### Targeted Reaction Bar Update

When `AppState.reactions_updated(channel_id, message_id)` fires, `message_view._on_reactions_updated()` finds only the affected message node and rebuilds its reaction bar from cache. This avoids destroying and recreating all message nodes for a single reaction change. The `messages_updated` signal is still used for message-level changes (create, update, delete).

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
- [x] Dedicated `reactions_updated` signal for targeted updates
- [x] Reaction tooltip showing emoji name
- [x] "Remove all reactions" UI (admin-only context menu, requires MANAGE_MESSAGES)
- [x] Rollback optimistic update on API failure
- [x] Prevent duplicate cache mutations (own reactions skip signal emission)
- [x] Explicit inactive pill style (dark background with border)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Reaction tooltip only shows emoji name | Low | The pill tooltip shows `":emoji_name:"` but does not list which users reacted. The `ReactionsApi.list_users()` endpoint exists and could be called on hover, but this is deferred to avoid per-hover network calls. |
