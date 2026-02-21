class_name BansApi
extends RefCounted

## REST endpoint helpers for ban management within a space: listing,
## fetching, creating, and removing bans.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists bans in a space. Supports pagination query parameters such as
## "limit", "before", and "after".
func list(space_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/bans", null, query)
	return result


## Fetches a single ban entry for a user in a space.
func fetch(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/bans/" + user_id)
	return result


## Creates a ban for a user in a space. The optional data dictionary may
## contain "delete_message_seconds" to prune recent messages.
func create(space_id: String, user_id: String, data: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("PUT", "/spaces/" + space_id + "/bans/" + user_id, data)
	return result


## Removes a ban for a user in a space (unban).
func remove(space_id: String, user_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/bans/" + user_id)
	return result
