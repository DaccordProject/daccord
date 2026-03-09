# Friends

## Overview

A cross-server friends system that lets users manage relationships (friend, blocked, pending) independently of any particular space. Friends appear in the DM sidebar with online/offline status and can be messaged directly. Friendships are per-server -- each accordserver maintains its own relationship table, so the same person on two servers appears as two separate entries.

## User Steps

### Viewing the friends list
1. User clicks the DM button in the space bar (enters DM mode)
2. DM sidebar shows two tabs at the top: **Friends** (default) and **Messages**
3. Friends tab shows sub-tabs: **All** | **Online** | **Pending** | **Blocked**, plus a **+** (Add Friend) button
4. Each friend row shows avatar, display name, status, and action buttons

### Sending a friend request (via member context menu)
1. User right-clicks a member in the member list
2. Context menu shows "Add Friend" (only if no existing relationship with that user)
3. Clicking sends a PUT request to create a pending relationship

### Sending a friend request (via Add Friend dialog)
1. User clicks the **+** button on the friends list tab bar
2. A modal dialog appears with a username input field and hint text
3. User enters a username and clicks "Send Request"
4. The dialog searches the local user cache (members from connected servers) for a match
5. If found, sends a friend request; if not, shows "User not found" error

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
        -> _first_connected_conn() finds connected server
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
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/accord_relationship.gd` | `AccordRelationship` model with `from_dict()` (id, user, type, since) |
| `addons/accordkit/rest/endpoints/users_api.gd` | REST methods: `list_relationships` (line 94), `put_relationship` (line 107), `delete_relationship` (line 114) |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway signals: `relationship_add/update/remove` (lines 82-84), event dispatch (lines 391-396) |
| `addons/accordkit/core/accord_client.gd` | Relays gateway relationship signals (lines 82-84, 260-262) |
| `scripts/autoload/app_state.gd` | `relationships_updated` (line 143) and `friend_request_received` (line 145) signals |
| `scripts/autoload/client.gd` | `relationships: ClientRelationships` (line 33), `_relationship_cache` (line 102), `find_user_id_by_username()` (line 399) |
| `scripts/autoload/client_relationships.gd` | All relationship operations: fetch, get, send/accept/decline, block/unblock, remove |
| `scripts/autoload/client_models.gd` | `relationship_to_dict()` (line 230), `status_color()` (line 70), `status_label()` (line 81) |
| `scripts/autoload/client_gateway.gd` | Connects relationship signals (lines 107-112), fetches relationships on connect (line 240) |
| `scripts/autoload/client_gateway_events.gd` | `on_relationship_add/update/remove` handlers (lines 208-237) |
| `scenes/sidebar/direct/dm_list.gd` | Friends/Messages tab toggle (lines 13-14, 36-45) |
| `scenes/sidebar/direct/dm_list.tscn` | DM sidebar layout with FriendsBtn/MessagesBtn tabs and embedded FriendsList |
| `scenes/sidebar/direct/friends_list.gd` | Friends list panel: filter tabs, friend rows, action handlers |
| `scenes/sidebar/direct/friends_list.tscn` | Layout: TabBar (All/Online/Pending/Blocked/+), ScrollContainer, EmptyLabel |
| `scenes/sidebar/direct/friend_item.gd` | Friend row: avatar, name, status, dynamic action buttons per relationship type |
| `scenes/sidebar/direct/friend_item.tscn` | Row layout: Avatar (36px), InfoBox (name+status), ActionBox |
| `scenes/sidebar/direct/add_friend_dialog.gd` | Add Friend dialog: username search against local user cache |
| `scenes/sidebar/direct/add_friend_dialog.tscn` | Modal: username input, error label, Cancel/Send buttons |
| `scenes/members/member_item.gd` | Context menu: Add Friend/Remove Friend/Accept/Block/Unblock (lines 78-95) |

## Implementation Details

### Data Model

Relationship types (enum values used throughout the codebase):
```
FRIEND = 1
BLOCKED = 2
PENDING_INCOMING = 3
PENDING_OUTGOING = 4
```

The `AccordRelationship` model (`accord_relationship.gd`) has four fields: `id` (String), `user` (AccordUser, nullable), `type` (int), `since` (String). The `from_dict()` static method (line 14) constructs from a server response dictionary.

`ClientModels.relationship_to_dict()` (line 230) converts an `AccordRelationship` into the dictionary shape the UI consumes:
```gdscript
{
    "id": String,           # relationship snowflake ID
    "user": Dictionary,     # user dict (id, display_name, avatar, status)
    "type": int,            # RelationshipType value
    "since": String,        # ISO 8601 timestamp
}
```

### Relationship Cache

`Client` stores relationships in `_relationship_cache` (line 102), a Dictionary keyed by `"{conn_index}:{user_id}"` composite keys to avoid collisions across multiple server connections. The `ClientRelationships` class (line 33) is initialized in `_init()` (line 172) and receives a reference to the Client node.

On gateway connect, `client_gateway.gd` calls `relationships.fetch_relationships()` (line 240), which iterates all connected servers and populates the cache via `list_relationships()` REST calls.

### ClientRelationships Operations

`client_relationships.gd` provides the public API:

- **`fetch_relationships()`** (line 13): Iterates `_connections`, calls `users.list_relationships()` on each, converts via `ClientModels.relationship_to_dict()`, stores with composite keys, emits `AppState.relationships_updated`
- **`get_relationship(user_id)`** (line 31): Linear scan of cache by user ID, returns dict or null
- **`get_friends/blocked/pending_incoming/pending_outgoing()`** (lines 38-48): Filter cache by type value
- **`send_friend_request(user_id)`** (line 50): Uses `_first_connected_conn()` to find a server, calls `put_relationship(user_id, {type: 1})`
- **`accept_friend_request(user_id)`** (line 57): Delegates to `send_friend_request()` -- same PUT endpoint, server resolves pending to friend
- **`decline_friend_request(user_id)`** (line 60): Calls `delete_relationship()` to remove the pending relationship
- **`block_user(user_id)`** (line 67): Calls `put_relationship(user_id, {type: 2})`
- **`unblock_user(user_id)`** (line 74): Delegates to `decline_friend_request()` -- DELETE removes any relationship
- **`remove_friend(user_id)`** (line 77): Also delegates to `decline_friend_request()`

### Gateway Event Handling

Gateway events use string-based event types (`relationship.add`, `relationship.update`, `relationship.remove`) dispatched in `gateway_socket.gd` (lines 391-396). The socket parses the data into `AccordRelationship.from_dict()` for add/update events and passes raw Dictionary for remove.

`client_gateway.gd` connects these signals (lines 107-112) to handlers in `client_gateway_events.gd`:

- **`on_relationship_add`** (line 208): Converts to dict, stores in cache, emits `relationships_updated`. If `type == 3` (PENDING_INCOMING), also emits `friend_request_received`
- **`on_relationship_update`** (line 220): Updates cache entry, emits `relationships_updated`
- **`on_relationship_remove`** (line 229): Erases cache entry by composite key, emits `relationships_updated`

### DM Sidebar Integration

`dm_list.gd` manages the Friends/Messages tab toggle (lines 13-14). On `_ready()`, it defaults to friends mode (`_set_friends_mode(true)`, line 34). The `_set_friends_mode()` method (lines 36-45) toggles visibility between `friends_list` and `dm_panel`, highlighting the active tab with the accent color via `ThemeManager.get_color("accent")`.

The `dm_list.tscn` scene embeds the `friends_list.tscn` as a child node (line 37) alongside the DMPanel, both inside a VBox.

### Friends List Panel

`friends_list.gd` manages the filter tabs (All/Online/Pending/Blocked) and friend rows:

- **Tab switching** (`_set_tab`, line 42): Sets `_current_tab`, refreshes list, highlights active tab with accent color
- **Refresh** (`_refresh`, line 61): Clears list, updates pending badge, gets filtered relationships, instantiates `FriendItemScene` for each, connects action signals
- **Filtering** (`_get_filtered_rels`, line 87):
  - All: `get_friends()` (type 1 only)
  - Online: friends filtered by status != OFFLINE
  - Pending: `get_pending_incoming() + get_pending_outgoing()` combined
  - Blocked: `get_blocked()` (type 2)
- **Friend request notification** (line 108): On `friend_request_received`, auto-switches to Pending tab
- **Remove confirmation** (line 115): Shows `ConfirmDialogScene` before calling `remove_friend()`
- **Empty state**: Shows "No friends here yet." label when filtered list is empty

### Friend Item

`friend_item.gd` renders a single relationship row as an HBoxContainer (48px height):

- **Avatar**: Uses `avatar.setup_from_dict(user)` with the common avatar component (36px, circle shader)
- **Status display** (lines 42-63): Status text and color vary by relationship type:
  - FRIEND: Uses `ClientModels.status_label()` and `status_color()` for online/idle/dnd/offline
  - BLOCKED: Shows "Blocked" in muted text
  - PENDING_INCOMING: Shows "Incoming Friend Request" in muted text
  - PENDING_OUTGOING: Shows "Outgoing Friend Request" in muted text
- **Action buttons** (lines 66-81): Dynamically built per relationship type:
  - FRIEND: Message, Remove, Block
  - BLOCKED: Unblock
  - PENDING_INCOMING: Accept, Decline
  - PENDING_OUTGOING: Cancel

### Add Friend Dialog

`add_friend_dialog.gd` is a modal overlay (ColorRect background, click-to-dismiss):

- Username input with Enter-to-submit (line 21)
- **Send flow** (line 23): Validates non-empty, calls `Client.find_user_id_by_username()` (line 31) which searches the local `_user_cache` by username or display_name (case-insensitive). If not found, shows "User not found. Make sure you share a server with them." error
- On success: Disables button, shows "Sending...", calls `Client.relationships.send_friend_request()`, then closes
- Dismissible via Escape key, click outside, or Cancel button

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
- `send_friend_request()` and other mutation methods use `_first_connected_conn()` to find a connected server -- this means they route to the first available connection, not necessarily the correct one for a specific user
- The same real person on two servers would appear as two separate friend entries

## Implementation Status

- [x] AccordRelationship model (`accord_relationship.gd`)
- [x] UsersApi REST endpoints (`list_relationships`, `put_relationship`, `delete_relationship`)
- [x] Gateway relationship event signals and dispatch (`gateway_socket.gd`, `accord_client.gd`)
- [x] Gateway event handler wiring (`client_gateway.gd` connects, `client_gateway_events.gd` handles)
- [x] AppState signals (`relationships_updated`, `friend_request_received`)
- [x] Client relationship cache with composite keys (`client.gd`)
- [x] ClientRelationships operation class (`client_relationships.gd`)
- [x] Friends list panel with All/Online/Pending/Blocked tabs (`friends_list.gd/.tscn`)
- [x] Friend item with avatar, name, status, and dynamic action buttons (`friend_item.gd/.tscn`)
- [x] DM sidebar Friends/Messages tab toggle (`dm_list.gd/.tscn`)
- [x] Member context menu: Add Friend / Remove Friend / Accept / Block / Unblock (`member_item.gd`)
- [x] Pending friend request badge on Pending tab
- [x] Auto-switch to Pending tab on incoming friend request
- [x] Add Friend by username search dialog (`add_friend_dialog.gd/.tscn`)
- [x] Remove Friend confirmation dialog
- [ ] Client-side block enforcement (DM filtering, request auto-decline)
- [ ] Server-side relationship API (accordserver has no `/users/@me/relationships` routes or tables)
- [ ] Server-side gateway relationship events (no `relationship.add/update/remove` events in server)
- [ ] Server-side block enforcement (DM creation, friend requests)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side relationship API | High | accordserver has no relationship routes or database tables; entire backend must be built before any relationship features work end-to-end |
| No server-side gateway relationship events | High | Server does not emit `relationship.add/update/remove` events; client handlers exist but never fire |
| No server-side block enforcement | High | Server does not enforce blocks on DM creation or friend requests |
| `_first_connected_conn()` routing for mutations | Medium | `send_friend_request()`, `block_user()`, etc. route to the first connected server, not the server the target user is on; should use `_client_for_user()` or similar routing |
| No client-side block enforcement | Medium | Client does not filter DMs or auto-decline requests from blocked users |
| Add Friend searches local cache only | Low | `find_user_id_by_username()` (client.gd line 399) only searches users already in `_user_cache` from connected servers; no server-side user search endpoint |
| No mutual friends display | Low | Profile cards don't show mutual friends count |
| No friend activity / rich presence | Low | No system to show what a friend is doing |
