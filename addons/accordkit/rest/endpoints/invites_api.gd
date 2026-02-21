class_name InvitesApi
extends RefCounted

## REST endpoint helpers for invite management: fetching, deleting,
## accepting, and creating invites for spaces and channels.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Fetches invite details by its code.
func fetch(code: String) -> RestResult:
	var result := await _rest.make_request("GET", "/invites/" + code)
	if result.ok and result.data is Dictionary:
		result.data = AccordInvite.from_dict(result.data)
	return result


## Deletes (revokes) an invite by its code.
func delete(code: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/invites/" + code)
	return result


## Accepts an invite by its code, joining the associated space.
func accept(code: String) -> RestResult:
	var result := await _rest.make_request("POST", "/invites/" + code + "/accept")
	return result


## Lists all active invites for a space.
func list_space(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/invites")
	if result.ok and result.data is Array:
		var invites := []
		for item in result.data:
			if item is Dictionary:
				invites.append(AccordInvite.from_dict(item))
		result.data = invites
	return result


## Lists all active invites for a specific channel.
func list_channel(channel_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id + "/invites")
	if result.ok and result.data is Array:
		var invites := []
		for item in result.data:
			if item is Dictionary:
				invites.append(AccordInvite.from_dict(item))
		result.data = invites
	return result


## Creates a new space-level invite. The optional data dictionary may
## contain "max_age", "max_uses", and "temporary" fields.
func create_space(space_id: String, data: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/invites", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordInvite.from_dict(result.data)
	return result


## Creates a new invite for a channel. The optional data dictionary may
## contain "max_age", "max_uses", and "temporary" fields.
func create_channel(channel_id: String, data: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("POST", "/channels/" + channel_id + "/invites", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordInvite.from_dict(result.data)
	return result
