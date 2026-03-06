# Friends

## Overview

A Discord-like cross-server friends system that lets users manage relationships (friend, blocked, pending) independently of any particular space. Friends appear in the DM sidebar with online/offline status, can be messaged directly from a friends list, and persist across all connected servers. Since daccord is multi-server, a user's identity is scoped per server -- friendships are per-connection, not global.

## User Steps

### Sending a friend request
1. User right-clicks a member in the member list or a message author
2. Context menu shows "Add Friend"
3. Request is sent; target user receives a pending friend request

### Accepting / declining a friend request
1. User opens the Friends panel (via DM sidebar tab or guild bar button)
2. "Pending" tab shows incoming and outgoing requests
3. User clicks Accept (checkmark) or Decline (X) on an incoming request
4. Accepted: both users appear in each other's friends list; Declined: request removed

### Viewing friends list
1. User clicks the Friends tab in the DM sidebar header
2. Tabs: All / Online / Pending / Blocked
3. Each friend row shows avatar, display name, status, and action buttons (Message, Remove, Block)

### Messaging a friend
1. User clicks "Message" on a friend row
2. Creates or opens a DM channel with that user (reuses existing `Client.create_dm()`)

### Blocking a user
1. User right-clicks a member or friend and selects "Block"
2. Blocked user cannot send DMs or friend requests to the blocker
3. Blocked users appear in the "Blocked" tab with an "Unblock" button

### Removing a friend
1. User clicks "Remove Friend" from the friend row or context menu
2. Confirmation dialog appears
3. Both users are removed from each other's friend lists

## Signal Flow

```
User right-clicks member -> "Add Friend"
    -> Client.send_friend_request(user_id)
        -> PUT /users/@me/relationships/{user_id} {type: 1}
        -> Server creates PENDING relationship for both users
        -> Gateway: RELATIONSHIP_ADD {user, type: PENDING_INCOMING}
            -> AppState.relationships_updated emitted
            -> Friends panel refreshes pending list

Target user receives gateway event
    -> Gateway: RELATIONSHIP_ADD {user, type: PENDING_INCOMING}
    -> AppState.relationships_updated emitted
    -> Pending badge incremented on Friends tab

Target clicks Accept
    -> Client.accept_friend_request(user_id)
        -> PUT /users/@me/relationships/{user_id} {type: 1}
        -> Server updates both rows to FRIEND
        -> Gateway: RELATIONSHIP_UPDATE {user, type: FRIEND} (to both users)
            -> AppState.relationships_updated emitted
            -> Friends list refreshes

User clicks "Block"
    -> Client.block_user(user_id)
        -> PUT /users/@me/relationships/{user_id} {type: 2}
        -> Server creates BLOCKED relationship (one-directional)
        -> Gateway: RELATIONSHIP_ADD {user, type: BLOCKED}
            -> AppState.relationships_updated emitted
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/rest/endpoints/users_api.gd` | Would host relationship REST methods (currently: user CRUD, DM creation) |
| `addons/accordkit/core/accord_client.gd` | Would declare relationship gateway signals |
| `addons/accordkit/models/accord_relationship.gd` | New model: AccordRelationship (id, user, type, since) |
| `scripts/autoload/app_state.gd` | Would declare `relationships_updated` signal |
| `scripts/autoload/client.gd` | Would host relationship cache + methods |
| `scripts/autoload/client_models.gd` | Would add `relationship_to_dict()` conversion |
| `scenes/sidebar/direct/dm_list.gd` | Would gain a friends tab header |
| `scenes/sidebar/direct/friends_list.gd` | New scene: friends list with filter tabs |
| `scenes/sidebar/direct/friend_item.gd` | New scene: friend row (avatar, name, status, actions) |
| `scenes/members/member_item.gd` | Context menu gains "Add Friend" / "Block" items (line 79) |

## Implementation Details

### Data Model

Relationship types (mirrors Discord):
```
enum RelationshipType {
    FRIEND = 1,
    BLOCKED = 2,
    PENDING_INCOMING = 3,
    PENDING_OUTGOING = 4,
}
```

Relationship dictionary shape:
```gdscript
{
    "id": String,           # relationship snowflake ID
    "user": Dictionary,     # user dict (id, display_name, avatar, status)
    "type": int,            # RelationshipType enum value
    "since": String,        # ISO 8601 timestamp
}
```

### REST API (server-side, not yet implemented)

| Method | Route | Body | Description |
|--------|-------|------|-------------|
| GET | `/users/@me/relationships` | -- | List all relationships for current user |
| PUT | `/users/@me/relationships/{user_id}` | `{type: int}` | Create or update a relationship |
| DELETE | `/users/@me/relationships/{user_id}` | -- | Remove a relationship |

### Gateway Events (server-side, not yet implemented)

| Event | Payload | When |
|-------|---------|------|
| `RELATIONSHIP_ADD` | `{user, type}` | New relationship created (friend request sent, block) |
| `RELATIONSHIP_UPDATE` | `{user, type}` | Relationship type changed (request accepted) |
| `RELATIONSHIP_REMOVE` | `{user_id}` | Relationship deleted (unfriend, unblock, decline) |

### AccordKit: AccordRelationship Model

New file `addons/accordkit/models/accord_relationship.gd`:
```gdscript
class_name AccordRelationship extends RefCounted

var id: String = ""
var user = null           # AccordUser (nullable)
var type: int = 0         # RelationshipType
var since: String = ""

static func from_dict(d: Dictionary) -> AccordRelationship:
    var r := AccordRelationship.new()
    r.id = str(d.get("id", ""))
    if d.has("user") and d["user"] is Dictionary:
        r.user = AccordUser.from_dict(d["user"])
    r.type = int(d.get("type", 0))
    r.since = str(d.get("since", ""))
    return r
```

### AccordKit: UsersApi Extensions

Add to `addons/accordkit/rest/endpoints/users_api.gd`:
```gdscript
func list_relationships() -> RestResult:
    var result := await _rest.make_request("GET", "/users/@me/relationships")
    if result.ok and result.data is Array:
        var rels := []
        for item in result.data:
            if item is Dictionary:
                rels.append(AccordRelationship.from_dict(item))
        result.data = rels
    return result

func put_relationship(user_id: String, data: Dictionary) -> RestResult:
    return await _rest.make_request(
        "PUT", "/users/@me/relationships/" + user_id, data
    )

func delete_relationship(user_id: String) -> RestResult:
    return await _rest.make_request(
        "DELETE", "/users/@me/relationships/" + user_id
    )
```

### AccordClient Gateway Signals

Add to `addons/accordkit/core/accord_client.gd`:
```gdscript
# Relationships
signal relationship_add(relationship: AccordRelationship)
signal relationship_update(relationship: AccordRelationship)
signal relationship_remove(data: Dictionary)
```

### AppState Signals

Add to `scripts/autoload/app_state.gd`:
```gdscript
signal relationships_updated()
signal friend_request_received(user_id: String)
```

### Client: Relationship Cache and Methods

Add to `scripts/autoload/client.gd` (or a new `client_relationships.gd` extract):
```gdscript
var _relationship_cache: Dictionary = {}  # user_id -> relationship dict

func fetch_relationships() -> void:
    for conn in _connections:
        if conn.status != Status.LIVE:
            continue
        var result: RestResult = await conn.client.users.list_relationships()
        if result.ok:
            for rel in result.data:
                var d: Dictionary = ClientModels.relationship_to_dict(rel, conn.cdn_url)
                _relationship_cache[d.user.id] = d
    AppState.relationships_updated.emit()

func send_friend_request(user_id: String) -> void:
    var client: AccordClient = _client_for_user(user_id)
    if client == null:
        return
    await client.users.put_relationship(user_id, {"type": 1})

func accept_friend_request(user_id: String) -> void:
    await send_friend_request(user_id)  # same endpoint, server resolves

func decline_friend_request(user_id: String) -> void:
    var client: AccordClient = _client_for_user(user_id)
    if client == null:
        return
    await client.users.delete_relationship(user_id)

func block_user(user_id: String) -> void:
    var client: AccordClient = _client_for_user(user_id)
    if client == null:
        return
    await client.users.put_relationship(user_id, {"type": 2})

func unblock_user(user_id: String) -> void:
    await decline_friend_request(user_id)  # DELETE removes any relationship

func remove_friend(user_id: String) -> void:
    await decline_friend_request(user_id)

var relationships: Array:
    get:
        return _relationship_cache.values()

func get_friends() -> Array:
    return relationships.filter(func(r): return r.type == 1)

func get_blocked() -> Array:
    return relationships.filter(func(r): return r.type == 2)

func get_pending_incoming() -> Array:
    return relationships.filter(func(r): return r.type == 3)

func get_pending_outgoing() -> Array:
    return relationships.filter(func(r): return r.type == 4)
```

### Member Context Menu: Add Friend / Block

Extend `scenes/members/member_item.gd` `_show_context_menu()` (after the "Message" item at line 83):
```gdscript
# After "Message" item:
var rel = Client.get_relationship(user_id)
if rel == null:
    _context_menu.add_item("Add Friend", idx)
    _actions.append("add_friend")
    idx += 1
elif rel.type == 1:  # FRIEND
    _context_menu.add_item("Remove Friend", idx)
    _actions.append("remove_friend")
    idx += 1
elif rel.type == 3:  # PENDING_INCOMING
    _context_menu.add_item("Accept Friend Request", idx)
    _actions.append("accept_friend")
    idx += 1

_context_menu.add_item("Block", idx)
_actions.append("block_user")
idx += 1
```

### Friends List UI

New `scenes/sidebar/direct/friends_list.gd`:
- Tabs: All | Online | Pending | Blocked (HBoxContainer of Buttons)
- Friend rows: VBoxContainer inside ScrollContainer
- Each `friend_item` has: avatar (circle shader), display name, status text, action buttons
- "Add Friend" button at top opens a username search dialog
- Pending tab shows incoming requests with Accept/Decline buttons and outgoing with Cancel
- Badge on "Pending" tab shows count of incoming requests

### DM Sidebar Integration

The DM list header (`dm_list.gd`) gains a tab bar or toggle:
- "Friends" tab -> shows `friends_list` scene
- "Messages" tab -> shows existing DM channel list
- Default to "Friends" on DM mode entry (matches Discord behavior)

### Cross-Server Considerations

Since daccord connects to multiple independent servers:
- Friendships are **per-server** (each accordserver maintains its own relationship table)
- The same real person on two servers would appear as two separate friend entries
- `_relationship_cache` keys should be `{conn_id}:{user_id}` to avoid collisions
- The friends list UI groups by server or shows a server icon badge per friend
- Blocking on one server does not block on another

### Block Enforcement

When a user is blocked:
- Client filters out their DM messages locally (server should also enforce)
- Friend requests from blocked users are auto-declined
- Blocked user's messages in shared spaces are hidden client-side (optional, configurable)
- Server prevents blocked user from creating DM channels with the blocker

## Implementation Status

- [ ] AccordRelationship model
- [ ] UsersApi relationship endpoints
- [ ] Gateway relationship event signals
- [ ] Gateway event handler wiring
- [ ] AppState `relationships_updated` signal
- [ ] Client relationship cache and methods
- [ ] Friends list UI (scenes/sidebar/direct/friends_list)
- [ ] Friend item scene (avatar, name, status, actions)
- [ ] DM sidebar Friends/Messages tab toggle
- [ ] Member context menu "Add Friend" / "Block" items
- [ ] Pending friend request badge
- [ ] "Add Friend" by username search dialog
- [ ] Block enforcement (DM filtering, request auto-decline)
- [ ] Server-side relationship API (accordserver)
- [ ] Server-side gateway relationship events (accordserver)
- [ ] Server-side block enforcement (DM creation, friend requests)
- [ ] Cross-server relationship cache keying

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side relationship API | High | accordserver has no `/users/@me/relationships` routes or database tables; entire backend must be built first |
| No gateway relationship events | High | No `RELATIONSHIP_ADD/UPDATE/REMOVE` events defined in the gateway protocol |
| No AccordRelationship model | Medium | `addons/accordkit/models/` needs a new model class |
| No friends list UI | Medium | DM sidebar currently only shows DM channels; needs a friends tab |
| No block enforcement | Medium | Neither client nor server enforces blocks on DM creation or message visibility |
| Member context menu missing friend actions | Medium | `member_item.gd` context menu (line 79) has Message/Report/Kick/Ban but no Add Friend or Block |
| Cross-server identity collision | Medium | `_relationship_cache` uses plain user_id keys; multi-server needs `conn_id:user_id` composite keys |
| No "Add Friend by username" flow | Low | Discord lets users add friends by `username#discriminator`; daccord has no equivalent global lookup |
| No mutual friends display | Low | Profile cards / user popups don't show mutual friends count |
| No friend activity / "Playing" status | Low | No rich presence system to show what a friend is doing |
