# Group DMs


## Overview

Group DMs are direct message channels with more than one recipient. The client detects them by checking `recipients.size() > 1` on the AccordChannel model and sets an `is_group` flag in the dictionary shape. Group DMs display a comma-separated list of participant names (or a custom name if set), use a "G" avatar letter with a color derived from the channel ID, and share all the same navigation, messaging, and close mechanics as 1:1 DMs. Users can create group DMs via a multi-select user picker, rename them (owner only), add/remove members, and view participants in the member list sidebar.

## User Steps

1. User clicks "+" button next to "DIRECT MESSAGES" header in the DM list
2. Create Group DM dialog opens with a searchable list of known users
3. User selects 2+ recipients via checkboxes, clicks "Create Group DM"
4. Client sends `POST /users/@me/channels` with `{"recipients": [id1, id2, ...]}` to the server
5. Server creates the group DM channel and broadcasts `channel_create` via gateway
6. Group DM appears in the DM list with a stacked 2x2 mini-avatar grid and comma-separated names (or custom name)
7. User clicks the group DM item — messages load in message view, tab created
8. Sending, replying, editing, deleting messages works identically to 1:1 DMs
9. Member list sidebar shows "PARTICIPANTS" header with all members and "(Owner)" indicator
10. Group DM items show a participant count badge (e.g., "3") next to the name
11. Right-click on group DM item shows context menu: "Add Member" (owner only), "Rename Group" (owner only), "Leave Group"
12. User can close (hide) the group DM via the X button on hover
13. Member list sidebar auto-refreshes when participants are added/removed via gateway events

## Signal Flow

```
User clicks "+" button in DM list header
    -> dm_list._on_new_group_pressed()
        -> Instantiates CreateGroupDMDialog on root

User selects 2+ users and clicks "Create Group DM"
    -> create_group_dm_dialog._on_create_pressed()
        -> Client.create_group_dm(selected_ids)
            -> client_mutations.create_group_dm(user_ids)
                -> POST /users/@me/channels {"recipients": user_ids}
                -> Caches channel in _dm_channel_cache
                -> AppState.dm_channels_updated emitted
                -> AppState.enter_dm_mode()
                -> AppState.select_channel(channel.id)

Gateway delivers channel_create (type = "group_dm", 3 recipients)
    -> client_gateway.on_channel_create(channel, conn_index)
        -> Detects type == "group_dm"
        -> Caches each recipient in _user_cache
        -> ClientModels.dm_channel_to_dict(channel, _user_cache)
            -> recipients.size() > 1 → is_group = true
            -> Builds comma-separated display_name from all recipients
            -> Includes owner_id and name fields
            -> user_dict.id = "", user_dict.color = _color_from_id(channel.id)
        -> Stores in _dm_channel_cache[channel.id]
        -> AppState.dm_channels_updated emitted

User enters DM mode (clicks DM button)
    -> space_bar.dm_selected -> sidebar._on_dm_selected()
        -> AppState.enter_dm_mode() -> dm_mode_entered emitted

dm_channels_updated signal
    -> dm_list._on_dm_channels_updated() -> _populate_dms()
        -> For each dm in Client.dm_channels:
            -> DMChannelItemScene.instantiate()
            -> item.setup(dm)
                -> If is_group and custom name set: show custom name
                -> Else: show dm.user.display_name (comma-separated)
                -> Group avatar: 2x2 mini-avatar grid via GroupAvatar
                -> 1:1 avatar: first letter of display_name or avatar URL

User clicks group DM item
    -> dm_channel_item.dm_pressed(dm_id)
    -> dm_list: _set_active_dm(id), dm_selected.emit(id)
    -> sidebar._on_dm_selected_channel(dm_id)
        -> AppState.select_channel(dm_id) -> channel_selected emitted
    -> main_window._on_channel_selected(dm_id)
        -> Finds dm in Client.dm_channels
        -> Window title: "daccord - Alice, Bob, Charlie"
        -> Creates tab with comma-separated name
    -> main_window._update_member_list_visibility()
        -> Detects is_group → shows member_toggle and member_list
    -> member_list._on_channel_selected(dm_id)
        -> Detects is_group → calls _build_dm_participants(dm)
        -> Builds participant list with PARTICIPANTS header and owner flag
    -> message_view._on_channel_selected(dm_id)
        -> Fetches messages via Client.fetch.fetch_messages(dm_id)
        -> Composer placeholder: "Message Alice, Bob, Charlie"

User right-clicks group DM item
    -> dm_channel_item._on_gui_input(event)
        -> Detects right-click on group DM
        -> _show_group_context_menu(pos)
            -> Shows "Add Member" (owner only) + "Rename Group" (owner only) + "Leave Group"
    -> "Add Member" -> _add_member()
        -> Instantiates AddMemberDialog on root
        -> dialog.setup(dm_id, recipients) — filters out existing members, self, bots
        -> User selects a user, clicks "Add Member"
        -> Client.add_dm_member(channel_id, selected_id)
    -> "Rename Group" -> _rename_group()
        -> AcceptDialog with LineEdit
        -> Client.rename_group_dm(dm_id, new_name)
    -> "Leave Group" -> _leave_group()
        -> Client.remove_dm_member(dm_id, my_id)

dm_channels_updated signal (gateway: recipient added/removed)
    -> member_list._on_dm_channels_updated()
        -> If currently viewing a group DM, calls _build_dm_participants(dm)
        -> Participant list refreshes with updated recipients

Typing in group DM
    -> Gateway delivers typing_start with user_id
    -> client_gateway.on_typing_start()
        -> Looks up user by ID, gets display_name
        -> AppState.typing_started.emit(channel_id, username)
    -> typing_indicator.show_typing(username)
        -> Shows "Alice is typing..."
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` — detects group via `recipients.size() > 1`, builds comma-separated name, includes `owner_id` and `name` |
| `scripts/autoload/client_gateway.gd` | Handles `channel_create/update/delete` for `type == "group_dm"` |
| `scripts/autoload/client_fetch.gd` | `fetch_dm_channels()` — fetches all DM channels (1:1 and group) from all servers |
| `scripts/autoload/client_mutations.gd` | `create_dm()`, `create_group_dm()`, `add_dm_member()`, `remove_dm_member()`, `rename_group_dm()` |
| `scripts/autoload/client.gd` | `_dm_channel_cache`, `_dm_to_conn` routing, `dm_channels` property, delegate methods for group DM mutations |
| `scripts/autoload/app_state.gd` | `dm_mode_entered`, `dm_channels_updated` signals, `is_dm_mode` state |
| `scenes/sidebar/direct/dm_list.gd` | Populates DM list, "+" button for new group DM, improved search filtering, dm_selected signal |
| `scenes/sidebar/direct/dm_list.tscn` | DM list scene with HeaderRow containing HeaderLabel and NewGroupBtn |
| `scenes/sidebar/direct/dm_channel_item.gd` | Renders each DM item — stacked group avatar, custom name, member count badge, context menu (add member/rename/leave) |
| `scenes/sidebar/direct/create_group_dm_dialog.gd` | Multi-select user picker dialog for creating group DMs |
| `scenes/sidebar/direct/create_group_dm_dialog.tscn` | Dialog scene — ColorRect overlay, centered Panel, search, checklist, create button |
| `scenes/sidebar/direct/add_member_dialog.gd` | Single-select user picker dialog for adding a member to an existing group DM |
| `scenes/sidebar/direct/add_member_dialog.tscn` | Add member dialog scene — ColorRect overlay, centered Panel, search, user list, add button |
| `scenes/common/group_avatar.gd` | 2x2 grid of mini-avatars for group DM items, `setup_recipients(recipients)` |
| `scenes/common/group_avatar.tscn` | GroupAvatar scene — ColorRect with GridContainer and circle shader clipping |
| `scenes/main/main_window.gd` | Window title and tab name from dm.user.display_name; member list visibility for group DMs |
| `scenes/members/member_list.gd` | `_build_dm_participants()` — shows group DM participants with owner indicator |
| `scenes/members/member_item.gd` | Displays "(Owner)" suffix for group DM owner |
| `scenes/messages/message_view.gd` | Composer placeholder, typing indicator with username |
| `scenes/messages/typing_indicator.gd` | `show_typing(username)` — shows "username is typing..." |
| `addons/accordkit/models/channel.gd` | `AccordChannel` model with `recipients`, `owner_id`, `type` fields |
| `addons/accordkit/rest/endpoints/channels_api.gd` | `add_recipient()`, `remove_recipient()` for managing group DM members |
| `addons/accordkit/rest/endpoints/users_api.gd` | `create_dm()` — POST /users/@me/channels |
| `tests/unit/test_client_models.gd` | `test_dm_channel_group()` — verifies `is_group` flag and comma-separated names |

## Implementation Details

### Group Detection (client_models.gd)

`dm_channel_to_dict()` (lines 462–525) determines whether a DM is a group:

- Checks `channel.recipients != null and channel.recipients is Array and channel.recipients.size() > 0` (lines 467–469)
- Sets `is_group = channel.recipients.size() > 1` (line 470)
- For group DMs, iterates all recipients and builds a comma-separated `display_name` (lines 481–492):
  ```
  names = [recipient1.display_name, recipient2.display_name, ...]
  user_dict["display_name"] = ", ".join(names)
  ```
- The synthetic `user_dict` for group DMs has `id = ""`, `username = ""`, and `avatar = null` (lines 485–492)
- Color is generated from the channel ID via `_color_from_id(channel.id)` (line 489), not from any recipient
- For 1:1 DMs, uses the first (and only) recipient's full user dict instead (line 494)
- Includes `owner_id` and `name` fields in the returned dictionary (lines 510–513)

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
    "owner_id": "12345",           # User who created the group
    "name": "My Group",            # Custom name (empty if not set)
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

### Create Group DM (client_mutations.gd + create_group_dm_dialog.gd)

**create_group_dm_dialog.gd** (lines 1–117):
- Extends `ColorRect` as a modal overlay
- `_populate_users()` (lines 39–86): Iterates `Client._user_cache`, excludes self and bots, sorts alphabetically, creates CheckBox rows with search filtering
- `_on_user_toggled()` (lines 93–99): Tracks selected IDs in `_selected_ids` array
- `_update_selection_ui()` (lines 102–107): Shows count and enables create button when ≥2 selected
- `_on_create_pressed()` (lines 110–116): Calls `Client.create_group_dm(_selected_ids)`, disables button with "Creating..." text

**client_mutations.create_group_dm()** (lines 432–470):
- Sends `{"recipients": user_ids}` to `users.create_dm()`
- Caches all recipients in `_user_cache`
- Stores channel in `_dm_channel_cache` via `ClientModels.dm_channel_to_dict()`
- Emits `dm_channels_updated`, enters DM mode, selects the new channel

### Add/Remove Members (client_mutations.gd + channels_api.gd)

**channels_api.gd** (lines 67–80):
- `add_recipient(channel_id, user_id)` — PUT `/channels/{id}/recipients/{user_id}`
- `remove_recipient(channel_id, user_id)` — DELETE `/channels/{id}/recipients/{user_id}`

**client_mutations.gd**:
- `add_dm_member()` (lines 473–499): Routes to correct server, calls `channels.add_recipient()`
- `remove_dm_member()` (lines 502–535): Calls `channels.remove_recipient()`. If removing self, cleans up `_dm_channel_cache` and `_dm_to_conn`, resets channel if needed, emits `dm_channels_updated`
- `rename_group_dm()` (lines 538–563): Calls `channels.update(channel_id, {"name": new_name})`

**client.gd delegate methods** (lines 434–456):
- `create_group_dm()`, `add_dm_member()`, `remove_dm_member()`, `rename_group_dm()`

### DM List UI (dm_list.gd)

- `_populate_dms()` (lines 25–41): Iterates `Client.dm_channels` and instantiates `DMChannelItemScene` for each
- "+" button in header (line 13): `NewGroupBtn` connected to `_on_new_group_pressed()` (lines 53–55) which instantiates `CreateGroupDMDialog`
- Search filtering (lines 57–96): Matches against `user.display_name` and `user.username`. For group DMs, also searches custom `name` and individual recipients' `display_name`/`username` (lines 77–95)

### DM Channel Item UI (dm_channel_item.gd)

- `setup()`: Detects `is_group` flag
  - Groups: Shows custom name if set, otherwise comma-separated display_name. Shows stacked 2x2 mini-avatar grid via `GroupAvatar.setup_recipients()`. Shows participant count badge.
  - 1:1: Shows recipient's display_name, first letter avatar or loaded avatar URL. Hides group avatar and count badge.
- Right-click context menu: Only for group DMs. Shows "Add Member" (owner only), "Rename Group" (owner only), and "Leave Group"
- `_add_member()`: Instantiates `AddMemberDialog`, calls `setup(dm_id, recipients)` to filter out existing members
- `_rename_group()`: AcceptDialog with LineEdit, calls `Client.rename_group_dm()`
- `_leave_group()`: Calls `Client.remove_dm_member(dm_id, my_id)`
- `set_active()`: Highlight styling is the same for both types

### Group DM Participant List (member_list.gd + member_item.gd)

**member_list.gd**:
- `_on_channel_selected()` (lines 84–95): When in DM mode, looks up the current channel in `Client.dm_channels`. If `is_group`, calls `_build_dm_participants(dm)`
- `_build_dm_participants()` (lines 255–297): Builds `_row_data` from `dm.recipients` + current user. Adds "PARTICIPANTS — N" header (line 283). Marks owner with `_is_owner = true` flag (lines 289–290). Sorts alphabetically.

**member_item.gd**:
- `setup()` (lines 22–40): If `data._is_owner` is true, appends " (Owner)" to display name (lines 25–26)

**main_window.gd**:
- `_update_member_list_visibility()` (lines 257–271): In DM mode, detects if current channel is a group DM. Shows member toggle and member list for group DMs, hides for 1:1 DMs.
- `_on_dm_mode_entered()` (lines 247–250): Hides search, defers to `_update_member_list_visibility()` for member list

### Typing Indicator (message_view.gd + typing_indicator.gd)

- `client_gateway.on_typing_start()` (lines 277–284): Looks up user by ID from `_user_cache`, gets `display_name` (fallback "Someone"), emits `typing_started` with username
- `message_view._on_typing_started()` (lines 494–496): Forwards username to `typing_indicator.show_typing()`
- `typing_indicator.show_typing()` (lines 33–38): Displays "username is typing..." with animated dots
- Works identically for 1:1 and group DMs — the username is always resolved from the typing user's ID

### AccordChannel Model (channel.gd)

The `AccordChannel` model has fields relevant to group DMs:

- `recipients` (line 17): Array of `AccordUser` objects, parsed from JSON
- `owner_id` (line 18): The user who created the group DM, used for owner indicator and rename permissions
- `type` (line 7): String, either `"dm"` or `"group_dm"` — used by gateway to route to DM cache

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
- [x] "G" letter avatar for group DMs
- [x] Gateway handling for `"group_dm"` channel type (create/update/delete)
- [x] Group DMs appear in DM list alongside 1:1 DMs
- [x] Group DM selection loads messages in message view
- [x] Tab creation with comma-separated name
- [x] Window title shows comma-separated participant names
- [x] Composer placeholder uses comma-separated names
- [x] Search filtering works on comma-separated display_name, custom name, and individual recipients
- [x] Last message preview fetching works for group DMs
- [x] Unread state tracking works for group DMs
- [x] Close/leave group DM via X button
- [x] Multi-server routing for group DM channels
- [x] Unit tests for group DM dictionary conversion
- [x] Create group DM (multi-select user picker dialog)
- [x] Add member to existing group DM (API wrapper)
- [x] Remove member from existing group DM (API wrapper + self-leave cache cleanup)
- [x] Rename group DM (owner-only via context menu)
- [x] Group DM stacked 2x2 mini-avatar grid (replaced "G" letter)
- [x] Group DM member list / participant sidebar with "PARTICIPANTS" header
- [x] Owner indicator ("(Owner)" suffix in member list)
- [x] Custom group name display (shows custom name when set)
- [x] Right-click context menu on group DM items (Rename / Leave)
- [x] Typing indicator shows typer's display name
- [x] `owner_id` and `name` fields in DM dictionary shape
- [x] Server: DM participants database module (`db/dm_participants.rs`)
- [x] Server: Permission system fix for DM channels (bypass space-based permissions)
- [x] Server: Recipients included in channel JSON responses
- [x] Server: `POST /users/@me/channels` endpoint for creating DMs and group DMs
- [x] Server: `PUT/DELETE /channels/{id}/recipients/{user_id}` for member management
- [x] Server: Gateway targeting by user IDs for DM broadcasts
- [x] Server: DM rename restricted to owner only
- [x] Server: DM delete semantics (leave vs delete, ownership transfer)
- [x] "Add Member" UI in group DM context menu (owner-only, single-select user picker)
- [x] Participant count badge on group DM list items
- [x] Member list auto-updates on recipient changes via `dm_channels_updated` signal

## Tasks

No open tasks.
