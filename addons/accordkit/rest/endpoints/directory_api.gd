class_name DirectoryApi
extends RefCounted

## REST endpoint wrapper for the master server directory API. Unlike other
## AccordKit endpoint classes, this talks to the master server (not an
## accordserver instance) and does not require authentication.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Browses the public space directory with optional search query, tag filter,
## and pagination. Returns a RestResult whose data is the raw response
## dictionary (spaces array + pagination metadata).
func browse(query: String = "", tag: String = "", page: int = 1) -> RestResult:
	var params := {}
	if not query.is_empty():
		params["q"] = query
	if not tag.is_empty():
		params["tag"] = tag
	if page > 1:
		params["page"] = page
	var result: RestResult = await _rest.make_request("GET", AccordConfig.API_BASE_PATH + "/directory", null, params)
	return result


## Fetches detail for a specific space listing in the directory.
func get_space(space_id: String) -> RestResult:
	var result: RestResult = await _rest.make_request("GET", AccordConfig.API_BASE_PATH + "/directory/" + space_id)
	return result
