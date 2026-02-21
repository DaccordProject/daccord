class_name UsersApi
extends RefCounted

## REST endpoint helpers for user-related API routes. All methods return
## RestResult via await and deserialize successful responses into the
## appropriate AccordKit model types.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Fetches the currently authenticated user.
func get_me() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me")
	if result.ok and result.data is Dictionary:
		result.data = AccordUser.from_dict(result.data)
	return result


## Updates the currently authenticated user's profile.
func update_me(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/users/@me", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordUser.from_dict(result.data)
	return result


## Fetches a user by their snowflake ID.
func fetch(user_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/users/" + user_id)
	if result.ok and result.data is Dictionary:
		result.data = AccordUser.from_dict(result.data)
	return result


## Lists all spaces (guilds) the current user belongs to.
func list_spaces() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/spaces")
	if result.ok and result.data is Array:
		var spaces := []
		for item in result.data:
			if item is Dictionary:
				spaces.append(AccordSpace.from_dict(item))
		result.data = spaces
	return result


## Lists all DM channels for the current user.
func list_channels() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/channels")
	if result.ok and result.data is Array:
		var channels := []
		for item in result.data:
			if item is Dictionary:
				channels.append(AccordChannel.from_dict(item))
		result.data = channels
	return result


## Creates a new DM channel with the specified user(s).
func create_dm(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/users/@me/channels", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordChannel.from_dict(result.data)
	return result


## Deletes the currently authenticated user's account.
func delete_me(data: Dictionary = {}) -> RestResult:
	return await _rest.make_request("DELETE", "/users/@me", data)


## Lists all connections linked to the current user's account.
func list_connections() -> RestResult:
	var result := await _rest.make_request("GET", "/users/@me/connections")
	return result
