class_name RestResult
extends RefCounted

## Wraps the outcome of a REST API call. Contains either parsed model data
## on success or an AccordError on failure. The cursor dictionary holds
## pagination state when the endpoint supports cursor-based paging.

var ok: bool = false
var status_code: int = 0
var data = null  # typed model, array of models, or null
var error = null  # AccordError or null
var cursor: Dictionary = {}  # pagination info: { "after": "id", "has_more": bool }
var has_more: bool:
	get: return cursor.get("has_more", false)


static func success(status: int, d, cur: Dictionary = {}) -> RestResult:
	var r := RestResult.new()
	r.ok = true
	r.status_code = status
	r.data = d
	r.cursor = cur
	return r


static func failure(status: int, err) -> RestResult:
	var r := RestResult.new()
	r.ok = false
	r.status_code = status
	r.error = err
	return r


## Deserializes a successful Dictionary response using the given converter.
func deserialize(from_dict: Callable) -> RestResult:
	if ok and data is Dictionary:
		data = from_dict.call(data)
	return self


## Deserializes a successful Array response, converting each Dictionary
## element using the given converter.
func deserialize_array(from_dict: Callable) -> RestResult:
	if ok and data is Array:
		var items := []
		for item in data:
			if item is Dictionary:
				items.append(from_dict.call(item))
		data = items
	return self
