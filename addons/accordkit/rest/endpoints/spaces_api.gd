class_name SpacesApi
extends RefCounted

## REST endpoint helpers for space (guild) management routes. All methods
## return RestResult via await and deserialize successful responses into the
## appropriate AccordKit model types.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Creates a new space.
func create(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordSpace.from_dict(result.data)
	return result


## Fetches a space by its snowflake ID.
func fetch(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id)
	if result.ok and result.data is Dictionary:
		result.data = AccordSpace.from_dict(result.data)
	return result


## Updates a space's settings.
func update(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id, data)
	if result.ok and result.data is Dictionary:
		result.data = AccordSpace.from_dict(result.data)
	return result


## Permanently deletes a space. Requires owner permissions.
func delete(space_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id)
	return result


## Lists all channels in a space.
func list_channels(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/channels")
	if result.ok and result.data is Array:
		var channels := []
		for item in result.data:
			if item is Dictionary:
				channels.append(AccordChannel.from_dict(item))
		result.data = channels
	return result


## Creates a new channel in a space.
func create_channel(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/channels", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordChannel.from_dict(result.data)
	return result


## Reorders channels in a space. The data array should contain objects
## with "id" and "position" keys.
func reorder_channels(space_id: String, data: Array) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/channels", data)
	return result


## Joins a public space without an invite.
func join(space_id: String) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/join")
	return result
