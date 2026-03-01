class_name AdminApi
extends RefCounted

## REST endpoint helpers for instance-level admin routes (`/admin/*`).
## All methods return RestResult via await and deserialize successful
## responses into the appropriate AccordKit model types.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists all spaces on the instance (admin view with owner + member count).
func list_spaces(query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request(
		"GET", "/admin/spaces", null, query
	)
	if result.ok and result.data is Array:
		var spaces := []
		for item in result.data:
			if item is Dictionary:
				spaces.append(AccordSpace.from_dict(item))
		result.data = spaces
	return result


## Updates a space via admin endpoint (supports owner_id transfer).
func update_space(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"PATCH", "/admin/spaces/" + space_id, data
	)
	if result.ok and result.data is Dictionary:
		result.data = AccordSpace.from_dict(result.data)
	return result


## Lists all users on the instance with pagination.
func list_users(query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request(
		"GET", "/admin/users", null, query
	)
	if result.ok and result.data is Array:
		var users := []
		for item in result.data:
			if item is Dictionary:
				users.append(AccordUser.from_dict(item))
		result.data = users
	return result


## Updates a user via admin endpoint (toggle is_admin, disable, etc.).
func update_user(user_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"PATCH", "/admin/users/" + user_id, data
	)
	if result.ok and result.data is Dictionary:
		result.data = AccordUser.from_dict(result.data)
	return result


## Deletes a user from the instance (cascades: spaces, messages, tokens).
func delete_user(user_id: String) -> RestResult:
	return await _rest.make_request(
		"DELETE", "/admin/users/" + user_id
	)


## Fetches server-wide settings.
func get_settings() -> RestResult:
	return await _rest.make_request("GET", "/admin/settings")


## Updates server-wide settings.
func update_settings(data: Dictionary) -> RestResult:
	return await _rest.make_request(
		"PATCH", "/admin/settings", data
	)
