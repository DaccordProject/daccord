class_name RolesApi
extends EndpointBase

## REST endpoint helpers for role management within a space: listing,
## creating, updating, deleting, and reordering roles.


## Lists all roles in a space.
func list(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/roles")
	return result.deserialize_array(AccordRole.from_dict)


## Creates a new role in a space.
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/roles", data)
	return result.deserialize(AccordRole.from_dict)


## Updates an existing role's attributes (name, color, permissions, etc.).
func update(space_id: String, role_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/roles/" + role_id, data)
	return result.deserialize(AccordRole.from_dict)


## Permanently deletes a role from a space.
func delete(space_id: String, role_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/roles/" + role_id)
	return result


## Reorders roles in a space. The data array should contain objects with
## "id" and "position" keys.
func reorder(space_id: String, data: Array) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/roles", data)
	return result.deserialize_array(AccordRole.from_dict)
