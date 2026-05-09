class_name MembersApi
extends EndpointBase

## REST endpoint helpers for space member management: listing, searching,
## fetching, updating, kicking, and role assignment.


## Lists members of a space. Supports pagination query parameters such as
## "limit" and "after".
func list(space_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/members", null, query)
	return result.deserialize_array(AccordMember.from_dict)


## Searches for members in a space whose username or nickname matches the
## query string. Additional query parameters like "limit" are supported.
func search(
	space_id: String, query_str: String, query: Dictionary = {},
) -> RestResult:
	query["query"] = query_str
	var path := "/spaces/" + space_id + "/members/search"
	var result := await _rest.make_request("GET", path, null, query)
	return result.deserialize_array(AccordMember.from_dict)


## Fetches a single member by their user ID within a space.
func fetch(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/members/" + user_id)
	return result.deserialize(AccordMember.from_dict)


## Updates a member's attributes (nickname, roles, mute, deaf, etc.).
func update(space_id: String, user_id: String, data: Dictionary) -> RestResult:
	var path := "/spaces/" + space_id + "/members/" + user_id
	var result := await _rest.make_request("PATCH", path, data)
	return result.deserialize(AccordMember.from_dict)


## Removes a member from a space (kick).
func kick(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/members/" + user_id)
	return result


## Updates the current bot's own member profile in a space (nickname, etc.).
func update_me(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/members/@me", data)
	return result.deserialize(AccordMember.from_dict)


## Leaves a space (self-removal). If delete_data is true, all of the user's
## messages, reactions, read states, and channel mutes within the space are
## also deleted (GDPR per-space erasure).
func leave_me(space_id: String, delete_data: bool = false) -> RestResult:
	var query := {}
	if delete_data:
		query["delete_data"] = "true"
	var result := await _rest.make_request(
		"DELETE", "/spaces/" + space_id + "/members/@me", null, query
	)
	return result


## Adds a role to a member in a space.
func add_role(space_id: String, user_id: String, role_id: String) -> RestResult:
	var path := (
		"/spaces/" + space_id + "/members/" + user_id
		+ "/roles/" + role_id
	)
	var result := await _rest.make_request("PUT", path)
	return result


## Removes a role from a member in a space.
func remove_role(space_id: String, user_id: String, role_id: String) -> RestResult:
	var path := (
		"/spaces/" + space_id + "/members/" + user_id
		+ "/roles/" + role_id
	)
	var result := await _rest.make_request("DELETE", path)
	return result
