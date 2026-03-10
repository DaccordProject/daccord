# Friends

## Overview

A cross-server friends system that lets users manage relationships (friend, blocked, pending) independently of any particular space. Friends appear in the DM sidebar with online/offline status, activity display, "since" dates, and mutual friend counts. They can be messaged directly. Friendships are per-server -- each accordserver maintains its own relationship table, so the same person on two servers appears as two separate entries.

## User Steps

### Viewing the friends list
1. User clicks the DM button in the space bar (enters DM mode)
2. DM sidebar shows two tabs at the top: **Friends** (default) and **Messages**
3. Friends tab shows sub-tabs: **All** | **Online** | **Pending** | **Blocked**, plus a **+** (Add Friend) button
4. Each friend row shows avatar, display name, status (with "since" date), activity, mutual friend count, and action buttons

### Sending a friend request (via member context menu)
1. User right-clicks a member in the member list
2. Context menu shows "Add Friend" (only if no existing relationship with that user)
3. Clicking sends a PUT request to create a pending relationship

### Sending a friend request (via Add Friend dialog)
1. User clicks the **+** button on the friends list tab bar
2. A modal dialog appears with a username input field and hint text
3. User enters a username and clicks "Send Request"
4. The dialog searches the server via `GET /users/search`, falling back to the local user cache
5. If found, sends a friend request; if not, shows "User not found." error

### Accepting / declining a friend request
1. When an incoming friend request arrives, the friends list auto-switches to the Pending tab
2. Pending tab shows incoming requests with **Accept** / **Decline** buttons, and outgoing requests with **Cancel**
3. A badge on the Pending tab shows the count of incoming requests

### Messaging a friend
1. User clicks "Message" on a friend row
2. Creates or opens a DM channel with that user via `Client.create_dm()`

### Blocking a user
1. User right-clicks a member and selects "Block" (or "Unblock" if already blocked)
2. Blocked users appear in the "Blocked" tab with an "Unblock" button

### Removing a friend
1. User clicks "Remove" on a friend row
2. A confirmation dialog appears ("Remove [name] from your friends?")
3. On confirm, the relationship is deleted

## Signal Flow

```
User right-clicks member -> "Add Friend"
    -> Client.relationships.send_friend_request(user_id)
        -> _conn_for_user() finds the server owning the relationship
        -> AccordClient.users.put_relationship(user_id, {type: 1})
            -> PUT /users/@me/relationships/{user_id}
            -> Server creates PENDING relationship for both users
            -> Gateway: "relationship.add" event
                -> gateway_socket.gd emits relationship_add (line 392)
                -> accord_client.gd relays signal (line 260)
                -> client_gateway.gd routes to _events (line 107)
                -> client_gateway_events.gd on_relationship_add (line 208)
                    -> Converts via ClientModels.relationship_to_dict()
                    -> Stores in _relationship_cache["{conn_index}:{user_id}"]
                    -> AppState.relationships_updated emitted
                    -> If type == PENDING_INCOMING: AppState.friend_request_received emitted

friends_list.gd receives relationships_updated
    -> _refresh() clears and rebuilds friend rows
    -> Updates pending badge count

friends_list.gd receives friend_request_received
    -> Auto-switches to Pending tab

User clicks "Accept" on incoming request
    -> Client.relationships.accept_friend_request(user_id)
        -> Calls send_friend_request() internally (same PUT endpoint, server resolves)
        -> Gateway: "relationship.update" event
            -> on_relationship_update() updates cache
            -> AppState.relationships_updated emitted
            -> Friends list refreshes

User clicks "Block"
    -> Client.relationships.block_user(user_id)
        -> AccordClient.users.put_relationship(user_id, {type: 2})
        -> Gateway: "relationship.add" event with type BLOCKED

User clicks "Remove" on friend row
    -> Confirmation dialog shown (ConfirmDialogScene)
    -> Client.relationships.remove_friend(user_id)
        -> Calls delete_relationship() (DELETE endpoint)
        -> Gateway: "relationship.remove" event
            -> on_relationship_remove() erases from cache
            -> AppState.relationships_updated emitted

Presence updates for friends:
    -> Server broadcasts presence.update to friend user IDs (via list_friend_ids)
    -> client_gateway.gd on_presence_update (line 525)
        -> Updates _user_cache status/activities
        -> Scans _relationship_cache for matching user_id, updates status/activities
        -> AppState.relationships_updated emitted -> friends list refreshes

User search in Add Friend dialog:
    -> Client.relationships.search_user_by_username(username)
        -> Checks local _user_cache first
        -> Falls back to AccordClient.users.search_users(query)
            -> GET /users/search?query=...&limit=5
        -> Returns user_id on exact username/display_name match

Mutual friend count on friend rows:
    -> friend_item.gd _fetch_mutual_count(user_id) (line 119)
        -> Client.relationships.get_mutual_friends(user_id) (line 68)
            -> GET /users/{user_id}/mutual-friends
        -> Appends "· N mutual friends" to status label
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/accord_relationship.gd` | `AccordRelationship` model with `from_dict()` (id, user, type, since, user_status, user_activities) |
| `addons/accordkit/rest/endpoints/users_api.gd` | REST methods: `get_mutual_friends` (line 94), `search_users` (line 108), `list_relationships` (line 122), `put_relationship` (line 135), `delete_relationship` (line 142) |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway signals: `relationship_add/update/remove` (lines 82-84), event dispatch (lines 391-396) |
| `addons/accordkit/core/accord_client.gd` | Relays gateway relationship signals (lines 82-84, 260-262), `update_presence()` (line 173) |
| `scripts/autoload/app_state.gd` | `relationships_updated` (line 143) and `friend_request_received` (line 145) signals |
| `scripts/autoload/client.gd` | `relationships: ClientRelationships` (line 33), `_relationship_cache` (line 108), `find_user_id_by_username()` (line 405), `send_presence()` (line 414) |
| `scripts/autoload/client_relationships.gd` | All relationship operations: fetch, get, send/accept/decline, block/unblock, remove, `get_mutual_friends()` (line 68), `search_user_by_username()` (line 80) |
| `scripts/autoload/client_models.gd` | `relationship_to_dict()` (line 230), `status_color()` (line 70), `status_label()` (line 81), `format_activity()` (line 614) |
| `scripts/autoload/client_gateway.gd` | Connects relationship signals (lines 107-112), `on_presence_update()` (line 525) updates relationship cache, fetches relationships on connect (line 240) |
| `scripts/autoload/client_gateway_events.gd` | `on_relationship_add/update/remove` handlers (lines 208-237) |
| `scenes/sidebar/direct/dm_list.gd` | Friends/Messages tab toggle (lines 13-14, 36-45) |
| `scenes/sidebar/direct/dm_list.tscn` | DM sidebar layout with FriendsBtn/MessagesBtn tabs and embedded FriendsList |
| `scenes/sidebar/direct/friends_list.gd` | Friends list panel: filter tabs, friend rows, action handlers |
| `scenes/sidebar/direct/friends_list.tscn` | Layout: TabBar (All/Online/Pending/Blocked/+), ScrollContainer, EmptyLabel |
| `scenes/sidebar/direct/friend_item.gd` | Friend row: avatar, name, status (with since date), activity label, mutual friends count, dynamic action buttons per relationship type |
| `scenes/sidebar/direct/friend_item.tscn` | Row layout: Avatar (36px), InfoBox (name+status+activity), ActionBox |
| `scenes/sidebar/direct/add_friend_dialog.gd` | Add Friend dialog: server-side user search with local cache fallback |
| `scenes/sidebar/direct/add_friend_dialog.tscn` | Modal: username input, error label, Cancel/Send buttons |
| `scenes/members/member_item.gd` | Context menu: Add Friend/Remove Friend/Accept/Block/Unblock (lines 78-95) |
| `accordserver/migrations/013_relationships.sql` | Relationships table (id, user_id, target_user_id, type, created_at) |
| `accordserver/src/models/relationship.rs` | `Relationship` and `PutRelationship` structs |
| `accordserver/src/db/relationships.rs` | CRUD: get, list, create, update_type, delete, delete_pair, is_blocked_by, `list_friend_ids` (line 128), `list_mutual_friend_ids` (line 143) |
| `accordserver/src/db/users.rs` | `search_users()` (line 128) — username/display_name LIKE search |
| `accordserver/src/routes/relationships.rs` | REST handlers: list (with presence), put (friend request / block), delete (unfriend / unblock), `get_mutual_friends` (line 256) |
| `accordserver/src/routes/users.rs` | `search_users()` handler (line 229) — `GET /users/search?query=...&limit=...` |
| `accordserver/src/gateway/mod.rs` | Presence broadcast includes friend user IDs via `list_friend_ids()` |
| `accordserver/src/gateway/intents.rs` | `relationship.*` events mapped to `None` (always delivered) |
| `accordserver/src/presence.rs` | `get_user_presence()` used by `relationship_to_json()` for initial status |

## Implementation Details

### Data Model

Relationship types (enum values used throughout the codebase):
```
FRIEND = 1
BLOCKED = 2
PENDING_INCOMING = 3
PENDING_OUTGOING = 4
```

The `AccordRelationship` model (`accord_relationship.gd`) has six fields: `id` (String), `user` (AccordUser, nullable), `type` (int), `since` (String), `user_status` (String, line 12), `user_activities` (Array, line 13). The `from_dict()` static method (line 16) constructs from a server response dictionary, extracting `status` and `activities` from the nested user object.

`ClientModels.relationship_to_dict()` (line 230) converts an `AccordRelationship` into the dictionary shape the UI consumes. It now reads `user_status` to set the correct initial status enum instead of defaulting to OFFLINE, and passes through `user_activities` to the user dict:
```gdscript
{
    "id": String,           # relationship snowflake ID
    "user": Dictionary,     # user dict (id, display_name, avatar, status, activities)
    "type": int,            # RelationshipType value
    "since": String,        # ISO 8601 timestamp
}
```

### Relationship Cache

`Client` stores relationships in `_relationship_cache` (line 108), a Dictionary keyed by `"{conn_index}:{user_id}"` composite keys to avoid collisions across multiple server connections. The `ClientRelationships` class (line 33) is initialized in `_init()` (line 172) and receives a reference to the Client node.

On gateway connect, `client_gateway.gd` calls `relationships.fetch_relationships()` (line 240), which iterates all connected servers and populates the cache via `list_relationships()` REST calls. The server now includes `status` and `activities` in each relationship's user object (sourced from `crate::presence::get_user_presence()`), so friends show correct online/idle/dnd status on initial load.

### ClientRelationships Operations

`client_relationships.gd` provides the public API:

- **`fetch_relationships()`** (line 13): Iterates `_connections`, calls `users.list_relationships()` on each, converts via `ClientModels.relationship_to_dict()`, stores with composite keys, emits `AppState.relationships_updated`
- **`get_relationship(user_id)`** (line 31): Linear scan of cache by user ID, returns dict or null
- **`get_friends/blocked/pending_incoming/pending_outgoing()`** (lines 45-56): Filter cache by type value
- **`get_mutual_friends(user_id)`** (line 68): Calls `AccordClient.users.get_mutual_friends()` -> `GET /users/{user_id}/mutual-friends`. Returns array of AccordUser.
- **`search_user_by_username(username)`** (line 80): Checks local `_user_cache` first via `find_user_id_by_username()`, then falls back to server search via `users.search_users(username, 5)`. Returns user_id on exact case-insensitive match.
- **`send_friend_request(user_id)`** (line 102): Uses `_conn_for_user()` to find the server, calls `put_relationship(user_id, {type: 1})`
- **`accept_friend_request(user_id)`** (line 109): Delegates to `send_friend_request()` -- same PUT endpoint, server resolves pending to friend
- **`decline_friend_request(user_id)`** (line 112): Calls `delete_relationship()` to remove the pending relationship
- **`block_user(user_id)`** (line 119): Calls `put_relationship(user_id, {type: 2})`
- **`unblock_user(user_id)`** (line 126): Delegates to `decline_friend_request()` -- DELETE removes any relationship
- **`remove_friend(user_id)`** (line 129): Also delegates to `decline_friend_request()`

### Friend Presence

The server broadcasts `presence.update` events to friends in addition to space members. In `gateway/mod.rs`, after the space broadcast loop, `db::relationships::list_friend_ids()` is called and a targeted `GatewayBroadcast` is sent to all friend user IDs. This happens in three places: initial online broadcast, opcode 8 presence update, and offline cleanup.

On the client, `on_presence_update()` in `client_gateway.gd` (line 525) now updates both the `_user_cache` and the `_relationship_cache`. After updating `_user_cache`, it scans `_relationship_cache` for a matching user_id and updates `status` and `activities`, then emits `AppState.relationships_updated` to refresh the friends list UI.

The server also includes presence data in the `list_relationships` REST response: `relationship_to_json()` (line 20 in `routes/relationships.rs`) calls `crate::presence::get_user_presence()` and injects `status` and `activities` into the user JSON.

### Activity Display

`ClientModels.format_activity()` (line 614) formats an activity dictionary based on its type:
- `playing` -> "Playing [name]"
- `streaming` -> "Streaming [name]"
- `listening` -> "Listening to [name]"
- `watching` -> "Watching [name]"
- `competing` -> "Competing in [name]"
- `custom` -> state text or name

`friend_item.gd` displays the primary activity (activities[0]) in an `ActivityLabel` below the status line (line 81). The label uses 11px font size and muted text color.

`Client.send_presence()` (line 414 in `client.gd`) sends a presence update with optional activity to all connected servers via `AccordClient.update_presence()`.

### Gateway Event Handling

Gateway events use string-based event types (`relationship.add`, `relationship.update`, `relationship.remove`) dispatched in `gateway_socket.gd` (lines 391-396). The socket parses the data into `AccordRelationship.from_dict()` for add/update events and passes raw Dictionary for remove.

`client_gateway.gd` connects these signals (lines 107-112) to handlers in `client_gateway_events.gd`:

- **`on_relationship_add`** (line 208): Converts to dict, stores in cache, emits `relationships_updated`. If `type == 3` (PENDING_INCOMING), also emits `friend_request_received`
- **`on_relationship_update`** (line 223): Updates cache entry, emits `relationships_updated`
- **`on_relationship_remove`** (line 232): Erases cache entry by composite key, emits `relationships_updated`

### DM Sidebar Integration

`dm_list.gd` manages the Friends/Messages tab toggle (lines 13-14). On `_ready()`, it defaults to friends mode (`_set_friends_mode(true)`, line 34). The `_set_friends_mode()` method (lines 36-45) toggles visibility between `friends_list` and `dm_panel`, highlighting the active tab with the accent color via `ThemeManager.get_color("accent")`.

The `dm_list.tscn` scene embeds the `friends_list.tscn` as a child node (line 37) alongside the DMPanel, both inside a VBox.

### Friends List Panel

`friends_list.gd` manages the filter tabs (All/Online/Pending/Blocked) and friend rows:

- **Tab switching** (`_set_tab`, line 43): Sets `_current_tab`, refreshes list, highlights active tab with accent color
- **Refresh** (`_refresh`, line 62): Clears list, updates pending badge, gets filtered relationships, instantiates `FriendItemScene` for each, connects action signals
- **Filtering** (`_get_filtered_rels`, line 146):
  - All: `get_friends()` (type 1 only)
  - Online: friends filtered by status != OFFLINE
  - Pending: `get_pending_incoming() + get_pending_outgoing()` combined
  - Blocked: `get_blocked()` (type 2)
- **Friend request notification** (line 167): On `friend_request_received`, auto-switches to Pending tab
- **Remove confirmation** (line 174): Shows `ConfirmDialogScene` before calling `remove_friend()`
- **Empty state**: Shows contextual empty message per tab

### Friend Item

`friend_item.gd` renders a single relationship row as an HBoxContainer (48px height):

- **Avatar**: Uses `avatar.setup_from_dict(user)` with the common avatar component (36px, circle shader)
- **Status display** (lines 49-78): Status text and color vary by relationship type:
  - FRIEND: Uses `ClientModels.status_label()` and `status_color()` for online/idle/dnd/offline. Appends "· Friends since Mon YYYY" if `since` is present.
  - BLOCKED: Shows "Blocked · Since Mon YYYY" in muted text
  - PENDING_INCOMING: Shows "Incoming Friend Request" in muted text
  - PENDING_OUTGOING: Shows "Outgoing Friend Request" in muted text
- **"Since" date** (`_format_since`, line 134): Parses ISO 8601 timestamp and formats as "Mon YYYY" (e.g. "Jan 2025")
- **Activity display** (lines 80-88): For FRIEND type, shows `activities[0]` formatted via `ClientModels.format_activity()` in a muted ActivityLabel below the status line
- **Mutual friend count** (`_fetch_mutual_count`, line 119): For FRIEND type, lazily fetches mutual friends via `Client.relationships.get_mutual_friends()` and appends "· N mutual friends" to the status label
- **Action buttons** (lines 95-106): Dynamically built per relationship type:
  - FRIEND: Message, Remove, Block
  - BLOCKED: Unblock
  - PENDING_INCOMING: Accept, Decline
  - PENDING_OUTGOING: Cancel

### Add Friend Dialog

`add_friend_dialog.gd` is a modal overlay (ColorRect background, click-to-dismiss):

- Username input with Enter-to-submit (line 21)
- **Send flow** (line 23): Validates non-empty, disables button and shows "Searching...", calls `Client.relationships.search_user_by_username()` which first checks local `_user_cache` then falls back to server `GET /users/search` endpoint. If not found, re-enables button and shows "User not found." error. Checks for self-friending (FRND-15) and existing relationships (FRND-16) before sending.
- On success: Shows "Sending...", calls `Client.relationships.send_friend_request()`, then closes
- Dismissible via Escape key, click outside, or Cancel button

### Server-Side User Search

`GET /users/search?query=...&limit=...` (authenticated) searches by username or display_name using SQL LIKE, excluding disabled users. Default limit is 25, max 100. Returns array of user objects.

- Route: `routes/users.rs` `search_users()` (line 229)
- DB: `db/users.rs` `search_users()` (line 128)

### Mutual Friends

`GET /users/{user_id}/mutual-friends` (authenticated) returns users who are type=1 (FRIEND) of both the auth user and the target user.

- Route: `routes/relationships.rs` `get_mutual_friends()` (line 256)
- DB: `db/relationships.rs` `list_mutual_friend_ids()` (line 143) — SQL join on relationships table

### Member Context Menu

`member_item.gd` integrates friend/block actions in the right-click context menu (lines 78-95):

- Checks `Client.relationships.get_relationship(user_id)` to determine current state
- No relationship: Shows "Add Friend"
- FRIEND (type 1): Shows "Remove Friend"
- PENDING_INCOMING (type 3): Shows "Accept Friend Request"
- Blocked (type 2): Shows "Unblock" instead of "Block"
- Non-blocked: Shows "Block"

The handler (`_on_context_menu_id_pressed`, line 158) dispatches to the appropriate `Client.relationships` method (lines 162-171). Left-clicking a member emits `AppState.profile_card_requested` (line 59).

### Cross-Server Considerations

Since daccord connects to multiple independent servers:
- Friendships are **per-server** (each accordserver maintains its own relationship table)
- The `_relationship_cache` uses `"{conn_index}:{user_id}"` composite keys to avoid collisions
- `send_friend_request()` and other mutation methods use `_conn_for_user()` to find the server with the matching relationship, falling back to `_first_connected_conn()`
- The same real person on two servers would appear as two separate friend entries

## Implementation Status

- [x] AccordRelationship model (`accord_relationship.gd`)
- [x] UsersApi REST endpoints (`list_relationships`, `put_relationship`, `delete_relationship`, `search_users`, `get_mutual_friends`)
- [x] Gateway relationship event signals and dispatch (`gateway_socket.gd`, `accord_client.gd`)
- [x] Gateway event handler wiring (`client_gateway.gd` connects, `client_gateway_events.gd` handles)
- [x] AppState signals (`relationships_updated`, `friend_request_received`)
- [x] Client relationship cache with composite keys (`client.gd`)
- [x] ClientRelationships operation class (`client_relationships.gd`)
- [x] Friends list panel with All/Online/Pending/Blocked tabs (`friends_list.gd/.tscn`)
- [x] Friend item with avatar, name, status, activity, mutual friends, and dynamic action buttons (`friend_item.gd/.tscn`)
- [x] DM sidebar Friends/Messages tab toggle (`dm_list.gd/.tscn`)
- [x] Member context menu: Add Friend / Remove Friend / Accept / Block / Unblock (`member_item.gd`)
- [x] Pending friend request badge on Pending tab
- [x] Auto-switch to Pending tab on incoming friend request
- [x] Add Friend by server-side user search dialog (`add_friend_dialog.gd/.tscn`)
- [x] Remove Friend confirmation dialog
- [x] Client-side block enforcement (DM filtering, request auto-decline)
- [x] Server-side relationship API (`accordserver/src/routes/relationships.rs`, migration 013)
- [x] Server-side gateway relationship events (`relationship.add/update/remove` broadcast to targeted users)
- [x] Server-side block enforcement (DM creation blocked when either user has blocked the other)
- [x] Block confirmation dialog (FRND-4)
- [x] Remove Friend confirmation in member context menu (FRND-5)
- [x] RestResult return from relationship mutations (FRND-6)
- [x] Add Friend dialog send failure handling (FRND-7)
- [x] Friend item action button disabled state (FRND-8)
- [x] Decline/Cancel in member context menu (FRND-9)
- [x] Pending tab incoming/outgoing grouping (FRND-10)
- [x] Alphabetical sorting in friends list (FRND-11)
- [x] Friend count header (FRND-12)
- [x] Friend presence visible in Online tab (FRND-13)
- [x] Contextual empty state messages (FRND-14)
- [x] Self-friending prevention (FRND-15)
- [x] Existing relationship check in Add Friend (FRND-16)
- [x] Click-to-profile on friend rows (FRND-17)
- [x] "Friends since" date display (FRND-18)
- [x] Server-side user search in Add Friend (FRND-19)
- [x] Mutual friends display (FRND-20)
- [x] Activity / rich presence display (FRND-21)

## Tasks

### FRND-1: Server-side relationship API
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** server, api, backend
- **Notes:** `GET/PUT/DELETE /users/@me/relationships` routes in `accordserver/src/routes/relationships.rs`. Migration 013 creates `relationships` table. DB layer in `src/db/relationships.rs`. Internal types: 1=FRIEND, 2=BLOCKED, 3=PENDING (direction derived at route layer). PUT type=1 creates pending pair or accepts existing; PUT type=2 blocks; DELETE removes both sides.

### FRND-2: Server-side gateway relationship events
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** server, gateway, backend
- **Notes:** Routes broadcast `relationship.add`, `relationship.update`, `relationship.remove` via `GatewayBroadcast` with `target_user_ids` for targeted delivery. Intent mapping in `intents.rs` returns `None` (always delivered). Events match the shape the client already handles.

### FRND-3: Server-side block enforcement
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** server, backend, security
- **Notes:** `create_dm_channel` in `routes/users.rs` checks `is_blocked_by()` in both directions for 1:1 DMs, returns 403. Friend request route checks block status and returns 403 if target blocked requester, 400 if requester blocked target (must unblock first).

### FRND-4: No confirmation dialog for Block action
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `friends_list.gd` now shows a `ConfirmDialogScene` before calling `block_user()`, matching the Remove Friend pattern.

### FRND-5: No confirmation for Remove Friend from member context menu
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `member_item.gd` "Remove Friend" context menu now shows a `ConfirmDialogScene`, consistent with `friends_list.gd`.

### FRND-6: No error handling on relationship mutations
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** ux, client, error-handling
- **Notes:** All mutation methods in `client_relationships.gd` now return `RestResult` (or null if no connection). Callers can check `result.ok` for error handling.

### FRND-7: Add Friend dialog ignores send failure
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, client, error-handling
- **Notes:** `add_friend_dialog.gd` now checks the returned `RestResult`. On failure, re-enables the button and shows "Failed to send friend request. Please try again."

### FRND-8: No loading/disabled state on friend item actions
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `friend_item.gd` now disables all action buttons when any button is clicked, preventing duplicate requests. Buttons re-enable on next `_refresh()`.

### FRND-9: No Decline/Cancel options in member context menu
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `member_item.gd` now shows "Decline Friend Request" for PENDING_INCOMING and "Cancel Friend Request" for PENDING_OUTGOING in the context menu.

### FRND-10: Pending tab mixes incoming and outgoing with no grouping
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `friends_list.gd` Pending tab now shows "INCOMING" and "OUTGOING" section labels, with each group sorted alphabetically.

### FRND-11: Friends list has no sorting
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** All tabs now sort relationships alphabetically by display name. Pending tab sorts within each incoming/outgoing group.

### FRND-12: No friend/result count header
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `CountLabel` node added to `friends_list.tscn`. Shows e.g. "ALL FRIENDS — 5", "ONLINE — 3", "PENDING — 2", "BLOCKED — 1".

### FRND-13: Online tab likely always empty
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** ux, client, presence, server
- **Notes:** Server now broadcasts `presence.update` to friends in addition to space members. In `gateway/mod.rs`, after the space broadcast loop, `list_friend_ids()` is queried and a targeted broadcast is sent. The `list_relationships` REST response now includes `status` and `activities` from the in-memory presence store. On the client, `AccordRelationship` carries `user_status` and `user_activities` (line 12-13), `relationship_to_dict()` sets the correct initial status, and `on_presence_update()` (line 525) updates `_relationship_cache` entries.

### FRND-14: Empty state message is generic across all tabs
- **Status:** done
- **Impact:** 1
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** Each tab now shows a contextual empty message: "No friends yet. Add someone!", "No friends online.", "No pending requests.", "No blocked users."

### FRND-15: Add Friend dialog doesn't prevent self-friending
- **Status:** done
- **Impact:** 1
- **Effort:** 1
- **Tags:** ux, client, validation
- **Notes:** `add_friend_dialog.gd` now checks if the resolved `user_id` matches `Client.current_user.id` and shows "You can't add yourself as a friend."

### FRND-16: Add Friend dialog doesn't check existing relationships
- **Status:** done
- **Impact:** 1
- **Effort:** 1
- **Tags:** ux, client, validation
- **Notes:** `add_friend_dialog.gd` now checks `Client.relationships.get_relationship()` and shows contextual messages for each existing relationship type (already friends, blocked, pending incoming/outgoing).

### FRND-17: No click-to-view-profile on friend rows
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `friend_item.gd` now handles left-click on the row to emit `AppState.profile_card_requested`, matching the `member_item.gd` pattern.

### FRND-18: Relationship "since" date never displayed
- **Status:** done
- **Impact:** 1
- **Effort:** 1
- **Tags:** ux, client
- **Notes:** `friend_item.gd` `_format_since()` (line 134) parses ISO 8601 and formats as "Mon YYYY". FRIEND rows show "Online · Friends since Jan 2025". BLOCKED rows show "Blocked · Since Jan 2025". Pending rows don't show since dates.

### FRND-19: Add Friend searches local cache only
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** ux, client, server, api
- **Notes:** Server: `GET /users/search?query=...&limit=...` in `routes/users.rs` (line 229), DB `search_users()` in `db/users.rs` (line 128) does `LIKE` on username and display_name. Client: `search_user_by_username()` in `client_relationships.gd` (line 80) checks local cache first, falls back to server search. `add_friend_dialog.gd` now awaits the async search, showing "Searching..." state.

### FRND-20: No mutual friends display
- **Status:** done
- **Impact:** 1
- **Effort:** 2
- **Tags:** ux, client, server
- **Notes:** Server: `GET /users/{user_id}/mutual-friends` in `routes/relationships.rs` (line 256), DB `list_mutual_friend_ids()` in `db/relationships.rs` (line 143) joins relationships table. Client: `get_mutual_friends()` in `client_relationships.gd` (line 68). `friend_item.gd` `_fetch_mutual_count()` (line 119) lazily fetches and appends "· N mutual friends" to the status label.

### FRND-21: No friend activity / rich presence
- **Status:** done
- **Impact:** 1
- **Effort:** 3
- **Tags:** ux, client, server
- **Notes:** `ClientModels.format_activity()` (line 614) formats activity dicts by type (playing/streaming/listening/watching/competing/custom). `friend_item.gd` shows the primary activity in an `ActivityLabel` (line 81). `friend_item.tscn` has a third label in InfoBox for activity text. `Client.send_presence()` (line 414) sends presence updates with optional activity to all connected gateways. Server-side activity storage and gateway broadcast were already working.
