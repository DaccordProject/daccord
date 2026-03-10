class_name AuditLogsApi
extends EndpointBase

## REST endpoint helpers for fetching audit log entries within a space.


## Lists audit log entries in a space. Supports query parameters such as
## "limit", "before", "user_id", and "action_type".
func list(space_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/audit-log", null, query)
	return result
