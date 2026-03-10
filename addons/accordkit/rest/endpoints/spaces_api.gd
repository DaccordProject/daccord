class_name SpacesApi
extends EndpointBase

## REST endpoint helpers for space (guild) management routes. All methods
## return RestResult via await and deserialize successful responses into the
## appropriate AccordKit model types.


## Creates a new space.
func create(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces", data)
	return result.deserialize(AccordSpace.from_dict)


## Fetches a space by its snowflake ID.
func fetch(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id)
	return result.deserialize(AccordSpace.from_dict)


## Updates a space's settings.
func update(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id, data)
	return result.deserialize(AccordSpace.from_dict)


## Permanently deletes a space. Requires owner permissions.
func delete(space_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id)
	return result


## Lists all channels in a space.
func list_channels(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/channels")
	return result.deserialize_array(AccordChannel.from_dict)


## Creates a new channel in a space.
func create_channel(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/channels", data)
	return result.deserialize(AccordChannel.from_dict)


## Reorders channels in a space. The data array should contain objects
## with "id" and "position" keys.
func reorder_channels(space_id: String, data: Array) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/channels", data)
	return result


## Joins a public space without an invite.
func join(space_id: String) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/join")
	return result
