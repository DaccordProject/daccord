class_name InvitesApi
extends EndpointBase

## REST endpoint helpers for invite management: fetching, deleting,
## accepting, and creating invites for spaces and channels.


## Fetches invite details by its code.
func fetch(code: String) -> RestResult:
	var result := await _rest.make_request("GET", "/invites/" + code)
	return result.deserialize(AccordInvite.from_dict)


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
	return result.deserialize_array(AccordInvite.from_dict)


## Lists all active invites for a specific channel.
func list_channel(channel_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id + "/invites")
	return result.deserialize_array(AccordInvite.from_dict)


## Creates a new space-level invite. The optional data dictionary may
## contain "max_age", "max_uses", and "temporary" fields.
func create_space(space_id: String, data: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/invites", data)
	return result.deserialize(AccordInvite.from_dict)


## Creates a new invite for a channel. The optional data dictionary may
## contain "max_age", "max_uses", and "temporary" fields.
func create_channel(channel_id: String, data: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("POST", "/channels/" + channel_id + "/invites", data)
	return result.deserialize(AccordInvite.from_dict)
