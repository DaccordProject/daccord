class_name ReportsApi
extends RefCounted

## REST endpoint helpers for report management within a space: creating,
## listing, fetching, and resolving reports.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Creates a report in a space. Data should include: target_type, target_id,
## category, and optionally channel_id and description.
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/reports", data)
	return result


## Lists reports in a space. Supports query parameters: status, limit, before.
func list(space_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/reports", null, query)
	return result


## Fetches a single report by ID.
func fetch(space_id: String, report_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/reports/" + report_id)
	return result


## Resolves a report (action or dismiss). Data should include: status and
## optionally action_taken.
func resolve(space_id: String, report_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/spaces/" + space_id + "/reports/" + report_id, data)
	return result
