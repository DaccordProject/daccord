class_name NodeUtils
extends RefCounted

## Lightweight node utility helpers.


## Frees all children of the given node via queue_free().
static func free_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


## Extracts an error message string from a RestResult.
static func rest_error(result: Variant) -> String:
	if result == null:
		return "unknown"
	var e: Variant = result.error
	return e.message if e else "unknown"
