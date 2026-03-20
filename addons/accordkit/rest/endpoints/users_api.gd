class_name UsersApi
extends EndpointBase

## REST endpoint helpers for user-related API routes. All methods return
## RestResult via await and deserialize successful responses into the
## appropriate AccordKit model types.


## Fetches the currently authenticated user.
func get_me() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me")
	return result.deserialize(AccordUser.from_dict)


## Updates the currently authenticated user's profile.
func update_me(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/users/@me", data)
	return result.deserialize(AccordUser.from_dict)


## Fetches a user by their snowflake ID.
func fetch(user_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/users/" + user_id)
	return result.deserialize(AccordUser.from_dict)


## Lists all spaces (guilds) the current user belongs to.
func list_spaces() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/spaces")
	return result.deserialize_array(AccordSpace.from_dict)


## Lists all DM channels for the current user.
func list_channels() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/channels")
	return result.deserialize_array(AccordChannel.from_dict)


## Creates a new DM channel with the specified user(s).
func create_dm(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/users/@me/channels", data)
	return result.deserialize(AccordChannel.from_dict)


## Deletes the currently authenticated user's account.
func delete_me(data: Dictionary = {}) -> RestResult:
	return await _rest.make_request("DELETE", "/users/@me", data)


## Lists all connections linked to the current user's account.
func list_connections() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/connections")
	return result


## Lists all muted channel IDs for the current user.
func list_mutes() -> RestResult:
	return await _rest.make_request("GET", "/users/@me/mutes")


## Lists all channels with unread messages for the current user.
## Each entry is a dict with at least "channel_id" and optionally "mention_count".
func list_unread() -> RestResult:
	return await _rest.make_request("GET", "/users/@me/unread")


## Returns mutual friends between the current user and the given user.
func get_mutual_friends(user_id: String) -> RestResult:
	var result: RestResult = await _rest.make_request(
		"GET", "/users/" + user_id + "/mutual-friends"
	)
	return result.deserialize_array(AccordUser.from_dict)


## Searches for users by username or display name.
func search_users(query: String, limit: int = 25) -> RestResult:
	var result: RestResult = await _rest.make_request(
		"GET", "/users/search?query=%s&limit=%d" % [query.uri_encode(), limit]
	)
	return result.deserialize_array(AccordUser.from_dict)


## Lists all relationships for the current user.
func list_relationships() -> RestResult:
	var result: RestResult = await _rest.make_request("GET", "/users/@me/relationships")
	return result.deserialize_array(AccordRelationship.from_dict)


## Creates or updates a relationship with another user.
## data should contain {"type": int} where 1=friend request, 2=block.
func put_relationship(user_id: String, data: Dictionary) -> RestResult:
	return await _rest.make_request(
		"PUT", "/users/@me/relationships/" + user_id, data
	)


## Removes a relationship (unfriend, decline, cancel, or unblock).
func delete_relationship(user_id: String) -> RestResult:
	return await _rest.make_request(
		"DELETE", "/users/@me/relationships/" + user_id
	)


## Requests a full data export of the current user's personal data
## (GDPR Article 20 — data portability). Returns user profile, messages,
## spaces, and relationships as JSON.
func request_data_export() -> RestResult:
	return await _rest.make_request("GET", "/users/@me/data-export")
