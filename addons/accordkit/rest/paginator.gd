class_name AccordPaginator
extends RefCounted

## Cursor-based pagination helper. Wraps a page of items from a paginated
## REST endpoint and provides a next() method to fetch the following page
## using the same path, query, and optional model class for deserialization.

var items: Array = []
var has_more: bool = false
var _after: String = ""
var _rest: AccordRest
var _path: String
var _query: Dictionary
var _model_class  # Reference to model class for deserialization


static func from_result(
	result: RestResult, rest: AccordRest, path: String,
	query: Dictionary, model_class = null,
) -> AccordPaginator:
	var p := AccordPaginator.new()
	p._rest = rest
	p._path = path
	p._query = query
	p._model_class = model_class
	if result.ok:
		if result.data is Array:
			if model_class and result.data.size() > 0:
				for item in result.data:
					if item is Dictionary:
						p.items.append(model_class.from_dict(item))
					else:
						p.items.append(item)
			else:
				p.items = result.data
		p.has_more = result.has_more
		p._after = result.cursor.get("after", "")
	return p


## Fetches the next page using the stored cursor position. Returns a new
## AccordPaginator instance with the next set of items.
func next() -> AccordPaginator:
	_query["after"] = _after
	var result := await _rest.make_request("GET", _path, null, _query)
	return AccordPaginator.from_result(result, _rest, _path, _query, _model_class)
