class_name RolesApi
extends RefCounted

## REST endpoint helpers for role management within a space: listing,
## creating, updating, deleting, and reordering roles.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists all roles in a space.
func list(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/roles")
	if result.ok and result.data is Array:
		var roles := []
		for item in result.data:
			if item is Dictionary:
				roles.append(AccordRole.from_dict(item))
		result.data = roles
	return result


## Creates a new role in a space.
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/roles", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordRole.from_dict(result.data)
	return result


## Updates an existing role's attributes (name, color, permissions, etc.).
func update(space_id: String, role_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/roles/" + role_id, data)
	if result.ok and result.data is Dictionary:
		result.data = AccordRole.from_dict(result.data)
	return result


## Permanently deletes a role from a space.
func delete(space_id: String, role_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/roles/" + role_id)
	return result


## Reorders roles in a space. The data array should contain objects with
## "id" and "position" keys.
func reorder(space_id: String, data: Array) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/roles", data)
	if result.ok and result.data is Array:
		var roles := []
		for item in result.data:
			if item is Dictionary:
				roles.append(AccordRole.from_dict(item))
		result.data = roles
	return result
