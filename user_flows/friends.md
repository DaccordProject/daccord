# Friends

Priority: 70
Depends on: User Management, Direct Messages
Status: Complete

Cross-server friends system with friend requests, accept/decline, friends list with filter tabs, block/unblock, DM sidebar integration, mutual friends, activity display, and per-server relationships.

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/accord_relationship.gd` | `AccordRelationship` model with `from_dict()` (id, user, type, since, user_status, user_activities) |
| `addons/accordkit/rest/endpoints/users_api.gd` | REST methods: `get_mutual_friends`, `search_users`, `list_relationships`, `put_relationship`, `delete_relationship` |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway signals: `relationship_add/update/remove`, event dispatch |
| `addons/accordkit/core/accord_client.gd` | Relays gateway relationship signals, `update_presence()` |
| `scripts/autoload/app_state.gd` | `relationships_updated` and `friend_request_received` signals |
| `scripts/autoload/client.gd` | `relationships: ClientRelationships`, `_relationship_cache`, `find_user_id_by_username()`, `send_presence()` |
| `scripts/autoload/client_relationships.gd` | All relationship operations: fetch, get, send/accept/decline, block/unblock, remove, `get_mutual_friends()`, `search_user_by_username()` |
| `scripts/autoload/client_models.gd` | `relationship_to_dict()`, `status_color()`, `status_label()`, `format_activity()` |
| `scripts/autoload/client_gateway.gd` | Connects relationship signals, `on_presence_update()` updates relationship cache, fetches relationships on connect |
| `scripts/autoload/client_gateway_events.gd` | `on_relationship_add/update/remove` handlers |
| `scenes/sidebar/direct/dm_list.gd` | Friends/Messages tab toggle |
| `scenes/sidebar/direct/dm_list.tscn` | DM sidebar layout with FriendsBtn/MessagesBtn tabs and embedded FriendsList |
| `scenes/sidebar/direct/friends_list.gd` | Friends list panel: filter tabs, friend rows, action handlers |
| `scenes/sidebar/direct/friends_list.tscn` | Layout: TabBar (All/Online/Pending/Blocked/+), ScrollContainer, EmptyLabel |
| `scenes/sidebar/direct/friend_item.gd` | Friend row: avatar, name, status (with since date), activity label, mutual friends count, dynamic action buttons per relationship type |
| `scenes/sidebar/direct/friend_item.tscn` | Row layout: Avatar (36px), InfoBox (name+status+activity), ActionBox |
| `scenes/sidebar/direct/add_friend_dialog.gd` | Add Friend dialog: server-side user search with local cache fallback |
| `scenes/sidebar/direct/add_friend_dialog.tscn` | Modal: username input, error label, Cancel/Send buttons |
| `scenes/members/member_item.gd` | Context menu: Add Friend/Remove Friend/Accept/Block/Unblock |
| `accordserver/migrations/013_relationships.sql` | Relationships table (id, user_id, target_user_id, type, created_at) |
| `accordserver/src/models/relationship.rs` | `Relationship` and `PutRelationship` structs |
| `accordserver/src/db/relationships.rs` | CRUD: get, list, create, update_type, delete, delete_pair, is_blocked_by, `list_friend_ids`, `list_mutual_friend_ids` |
| `accordserver/src/db/users.rs` | `search_users()` — username/display_name LIKE search |
| `accordserver/src/routes/relationships.rs` | REST handlers: list (with presence), put (friend request / block), delete (unfriend / unblock), `get_mutual_friends` |
| `accordserver/src/routes/users.rs` | `search_users()` handler — `GET /users/search?query=...&limit=...` |
| `accordserver/src/gateway/mod.rs` | Presence broadcast includes friend user IDs via `list_friend_ids()` |
| `accordserver/src/gateway/intents.rs` | `relationship.*` events mapped to `None` (always delivered) |
| `accordserver/src/presence.rs` | `get_user_presence()` used by `relationship_to_json()` for initial status |
