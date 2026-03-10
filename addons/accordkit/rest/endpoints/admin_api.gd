class_name AdminApi
extends EndpointBase

## REST endpoint helpers for instance-level admin routes (`/admin/*`).
## All methods return RestResult via await and deserialize successful
## responses into the appropriate AccordKit model types.


## Lists all spaces on the instance (admin view with owner + member count).
func list_spaces(query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request(
		"GET", "/admin/spaces", null, query
	)
	return result.deserialize_array(AccordSpace.from_dict)


## Updates a space via admin endpoint (supports owner_id transfer).
func update_space(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"PATCH", "/admin/spaces/" + space_id, data
	)
	return result.deserialize(AccordSpace.from_dict)


## Lists all users on the instance with pagination.
func list_users(query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request(
		"GET", "/admin/users", null, query
	)
	return result.deserialize_array(AccordUser.from_dict)


## Updates a user via admin endpoint (toggle is_admin, disable, etc.).
func update_user(user_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"PATCH", "/admin/users/" + user_id, data
	)
	return result.deserialize(AccordUser.from_dict)


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


## Resets a user's password. The user's sessions are revoked and 2FA is
## disabled so the new password is immediately usable.
## data should contain: { "new_password": String } (8–128 characters).
func reset_user_password(user_id: String, data: Dictionary) -> RestResult:
	return await _rest.make_request(
		"POST", "/admin/users/" + user_id + "/reset-password", data
	)
