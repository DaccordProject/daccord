# Group DMs


## Overview

Group DMs are direct message channels with more than one recipient. The client detects them by checking `recipients.size() > 1` on the AccordChannel model and sets an `is_group` flag in the dictionary shape. Group DMs display a comma-separated list of participant names instead of a single username, use a color-hash avatar derived from the channel ID, and share all the same navigation, messaging, and close mechanics as 1:1 DMs. Creating, managing membership of, and renaming group DMs is not yet supported in the client UI.

## User Steps

1. Another user (or the server) creates a group DM — the gateway delivers a `channel_create` event with `type = "group_dm"` and multiple `recipients`
2. Client caches the channel in `_dm_channel_cache` with `is_group: true`
3. User clicks DM button in guild bar to enter DM mode
4. Group DM appears in the DM list with comma-separated participant names (e.g., "Alice, Bob, Charlie")
5. User clicks the group DM item — messages load in message view, tab created
6. Sending, replying, editing, deleting messages works identically to 1:1 DMs
7. User can close (hide) the group DM via the X button on hover

## Signal Flow

```
Gateway delivers channel_create (type = "group_dm", 3 recipients)
    -> client_gateway.on_channel_create(channel, conn_index)
        -> Detects type == "group_dm"
        -> Caches each recipient in _user_cache
        -> ClientModels.dm_channel_to_dict(channel, _user_cache)
            -> recipients.size() > 1 → is_group = true
            -> Builds comma-separated display_name from all recipients
            -> user_dict.id = "", user_dict.color = _color_from_id(channel.id)
        -> Stores in _dm_channel_cache[channel.id]
        -> AppState.dm_channels_updated emitted

User enters DM mode (clicks DM button)
    -> guild_bar.dm_selected -> sidebar._on_dm_selected()
        -> AppState.enter_dm_mode() -> dm_mode_entered emitted

dm_channels_updated signal
    -> dm_list._on_dm_channels_updated() -> _populate_dms()
        -> For each dm in Client.dm_channels:
            -> DMChannelItemScene.instantiate()
            -> item.setup(dm)
                -> username_label.text = dm.user.display_name  (comma-separated names)
                -> avatar color from dm.user.color  (channel-ID-based hash)

User clicks group DM item
    -> dm_channel_item.dm_pressed(dm_id)
    -> dm_list: _set_active_dm(id), dm_selected.emit(id)
    -> sidebar._on_dm_selected_channel(dm_id)
        -> AppState.select_channel(dm_id) -> channel_selected emitted
    -> main_window._on_channel_selected(dm_id)
        -> Finds dm in Client.dm_channels
        -> Window title: "daccord - Alice, Bob, Charlie"
        -> Creates tab with comma-separated name
    -> message_view._on_channel_selected(dm_id)
        -> Fetches messages via Client.fetch.fetch_messages(dm_id)
        -> composer placeholder: "Message Alice, Bob, Charlie"
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` — detects group via `recipients.size() > 1`, builds comma-separated name |
| `scripts/autoload/client_gateway.gd` | Handles `channel_create/update/delete` for `type == "group_dm"` |
| `scripts/autoload/client_fetch.gd` | `fetch_dm_channels()` — fetches all DM channels (1:1 and group) from all servers |
| `scripts/autoload/client_mutations.gd` | `create_dm()` — creates 1:1 DM only (no group creation support) |
| `scripts/autoload/client.gd` | `_dm_channel_cache`, `_dm_to_conn` routing, `dm_channels` property |
| `scripts/autoload/app_state.gd` | `dm_mode_entered`, `dm_channels_updated` signals, `is_dm_mode` state |
| `scenes/sidebar/direct/dm_list.gd` | Populates DM list, search filtering, dm_selected signal |
| `scenes/sidebar/direct/dm_channel_item.gd` | Renders each DM item — avatar, name, last message, unread, close |
| `addons/accordkit/models/channel.gd` | `AccordChannel` model with `recipients`, `owner_id`, `type` fields |
| `addons/accordkit/rest/endpoints/users_api.gd` | `create_dm()` — POST /users/@me/channels |
| `scenes/main/main_window.gd` | Window title and tab name from `dm.user.display_name` |
| `scenes/messages/message_view.gd` | Composer placeholder from `dm.user.display_name` |
| `tests/unit/test_client_models.gd` | `test_dm_channel_group()` — verifies `is_group` flag and comma-separated names |

## Implementation Details

### Group Detection (client_models.gd)

`dm_channel_to_dict()` (lines 337–393) determines whether a DM is a group:

- Checks `channel.recipients != null and channel.recipients is Array and channel.recipients.size() > 0` (line 342–344)
- Sets `is_group = channel.recipients.size() > 1` (line 345)
- For group DMs, iterates all recipients and builds a comma-separated `display_name` (lines 356–367):
  ```
  names = [recipient1.display_name, recipient2.display_name, ...]
  user_dict["display_name"] = ", ".join(names)
  ```
- The synthetic `user_dict` for group DMs has `id = ""`, `username = ""`, and `avatar = null` (lines 360–367)
- Color is generated from the channel ID via `_color_from_id(channel.id)` (line 364), not from any recipient
- For 1:1 DMs, uses the first (and only) recipient's full user dict instead (line 369)

**Returned dictionary shape:**
```gdscript
{
    "id": channel.id,
    "user": {                      # Synthetic for groups
        "id": "",
        "display_name": "Alice, Bob, Charlie",
        "username": "",
        "color": Color(...),       # From channel ID hash
        "status": OFFLINE,
        "avatar": null,
    },
    "recipients": [user_dict_1, user_dict_2, ...],
    "is_group": true,
    "last_message": "",
    "last_message_id": "...",
    "unread": false,
}
```

### Gateway Events (client_gateway.gd)

All three channel event handlers detect group DMs:

- `on_channel_create()` (line 242): `if channel.type == "dm" or channel.type == "group_dm"` — caches recipients, converts to dict, emits `dm_channels_updated`
- `on_channel_update()` (line 263): Same detection — updates cache with new data
- `on_channel_delete()` (line 284): Same detection — erases from `_dm_channel_cache`
- `on_message_create()` (lines 107–113): Updates `last_message` preview on DM channels (truncated to 80 chars)

The `on_gateway_ready()` handler (line 28) calls `fetch_dm_channels()` which fetches both 1:1 and group DMs.

### DM List UI (dm_list.gd)

The DM list treats group DMs identically to 1:1 DMs:

- `_populate_dms()` (lines 21–37): Iterates `Client.dm_channels` and instantiates `DMChannelItemScene` for each, regardless of `is_group`
- Search filtering (lines 49–61): Matches against `user.display_name` (which is comma-separated for groups) and `user.username` (which is `""` for groups, so effectively only display_name matches)
- No visual distinction between group and 1:1 items (no group icon, no member count badge)

### DM Channel Item UI (dm_channel_item.gd)

- `setup()` (lines 23–30): Sets `username_label.text` from `data.user.display_name` — for groups this is the comma-separated list
- Avatar: Uses `set_avatar_color()` with the color from `data.user.color` — for groups this is derived from the channel ID, not a stacked/composite avatar
- Unread dot and close button work identically for both types
- `set_active()` (lines 35–47): Highlight styling is the same

### AccordChannel Model (channel.gd)

The `AccordChannel` model (lines 1–120) has fields relevant to group DMs:

- `recipients` (line 17): Array of `AccordUser` objects, parsed from JSON (lines 46–52)
- `owner_id` (line 18): The user who created the group DM, parsed from `owner_id` field (lines 54–57). **Not used anywhere in client UI.**
- `type` (line 7): String, either `"dm"` or `"group_dm"` — used by gateway to route to DM cache

### Create DM API (client_mutations.gd / users_api.gd)

- `create_dm()` in `client_mutations.gd` (lines 299–335): Sends `{"recipient_id": user_id}` — only creates 1:1 DMs
- `UsersApi.create_dm()` (line 65): POST to `/users/@me/channels` with a data dictionary. The API likely supports `{"recipients": [id1, id2, ...]}` for group DM creation, but the client only sends `recipient_id` (singular)
- No client-side UI or method exists to create a group DM with multiple recipients

### Close/Leave (client_mutations.gd)

- `close_dm()` (lines 337–361): Calls `ChannelsApi.delete(channel_id)` which closes the DM (does not permanently delete)
- Works identically for both 1:1 and group DMs
- For group DMs, "close" semantically means "leave" — the server should handle removal from the recipients list

### Multi-Server Routing (client_fetch.gd / client.gd)

- `fetch_dm_channels()` (lines 63–137): Iterates all connected servers, fetches DM channels from each, and populates `_dm_to_conn` routing map
- `_client_for_channel()` and `_cdn_for_channel()` in `client.gd` use `_dm_to_conn` to route API calls to the correct server for both 1:1 and group DMs

### Tests (test_client_models.gd)

- `test_dm_channel_group()` (lines 441–453): Creates a channel with 2 recipients, asserts `is_group == true`, checks that `display_name` contains both "Bob" and "Charlie"
- `test_dm_channel_single_recipient()` (lines 429–438): Verifies 1:1 DM has `is_group == false`
- `test_dm_channel_no_recipients()` (lines 456–463): Verifies fallback to channel name
- `test_dm_channel_last_message_id()` (lines 466–473): Verifies last_message_id extraction

## Implementation Status

- [x] Group DM detection via `recipients.size() > 1`
- [x] `is_group` flag in dictionary shape
- [x] Comma-separated display name for group DMs
- [x] Channel-ID-based avatar color for groups
- [x] Gateway handling for `"group_dm"` channel type (create/update/delete)
- [x] Group DMs appear in DM list alongside 1:1 DMs
- [x] Group DM selection loads messages in message view
- [x] Tab creation with comma-separated name
- [x] Window title shows comma-separated participant names
- [x] Composer placeholder uses comma-separated names
- [x] Search filtering works on comma-separated display_name
- [x] Last message preview fetching works for group DMs
- [x] Unread state tracking works for group DMs
- [x] Close/leave group DM via X button
- [x] Multi-server routing for group DM channels
- [x] Unit tests for group DM dictionary conversion
- [ ] Create group DM (select multiple recipients)
- [ ] Add member to existing group DM
- [ ] Remove member from existing group DM
- [ ] Rename group DM
- [ ] Group DM avatar (stacked/composite avatars)
- [ ] Group DM member list / participant sidebar
- [ ] Owner indicator (AccordChannel.owner_id is parsed but unused)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No UI to create a group DM | High | `create_dm()` only sends `recipient_id` (singular) — needs a multi-select user picker and `recipients` array payload. `users_api.gd:65` already posts to the right endpoint. |
| No add/remove member for group DMs | High | No API wrapper or UI. Server likely supports PUT/DELETE `/channels/{id}/recipients/{user_id}` but `channels_api.gd` has no such methods. |
| No group DM rename | Medium | `AccordChannel.name` field exists (line 9) and `channels_api.update()` could PATCH it, but no UI exposes this for DM channels. |
| Single avatar for groups | Medium | Group DMs show a single color circle derived from channel ID (`_color_from_id` in `client_models.gd:364`). Should show stacked/overlapping recipient avatars or a group icon. |
| No participant list | Medium | Group DMs have `recipients` array in the dict but no UI to view participants. Member list is hidden in DM mode (`main_window.gd:213-214`). |
| `owner_id` unused | Low | `AccordChannel.owner_id` is parsed (`channel.gd:18`, `channel.gd:54-57`) but never displayed or used in any group DM UI. Could show who created the group. |
| Search only matches display_name | Low | For group DMs, `user.username` is `""` (`client_models.gd:363`), so search in `dm_list.gd:60` only matches the comma-separated display_name, not individual recipient usernames. |
| No typing indicator differentiation | Low | Typing indicators in group DMs don't show which participant is typing — same as 1:1 DMs. |
