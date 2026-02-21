class_name MembersApi
extends RefCounted

## REST endpoint helpers for space member management: listing, searching,
## fetching, updating, kicking, and role assignment.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists members of a space. Supports pagination query parameters such as
## "limit" and "after".
func list(space_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/members", null, query)
	if result.ok and result.data is Array:
		var members := []
		for item in result.data:
			if item is Dictionary:
				members.append(AccordMember.from_dict(item))
		result.data = members
	return result


## Searches for members in a space whose username or nickname matches the
## query string. Additional query parameters like "limit" are supported.
func search(
	space_id: String, query_str: String, query: Dictionary = {},
) -> RestResult:
	query["query"] = query_str
	var path := "/spaces/" + space_id + "/members/search"
	var result := await _rest.make_request("GET", path, null, query)
	if result.ok and result.data is Array:
		var members := []
		for item in result.data:
			if item is Dictionary:
				members.append(AccordMember.from_dict(item))
		result.data = members
	return result


## Fetches a single member by their user ID within a space.
func fetch(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/members/" + user_id)
	if result.ok and result.data is Dictionary:
		result.data = AccordMember.from_dict(result.data)
	return result


## Updates a member's attributes (nickname, roles, mute, deaf, etc.).
func update(space_id: String, user_id: String, data: Dictionary) -> RestResult:
	var path := "/spaces/" + space_id + "/members/" + user_id
	var result := await _rest.make_request("PATCH", path, data)
	if result.ok and result.data is Dictionary:
		result.data = AccordMember.from_dict(result.data)
	return result


## Removes a member from a space (kick).
func kick(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/members/" + user_id)
	return result


## Updates the current bot's own member profile in a space (nickname, etc.).
func update_me(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/members/@me", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordMember.from_dict(result.data)
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
