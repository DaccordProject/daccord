class_name NavigationHistory
extends RefCounted

## Tracks a stack of dismissable navigation entries so the Android back
## button (ui_cancel) can unwind overlays and panels in the correct order.
##
## Each entry is a StringName identifying the layer to close.  The back
## handler pops the most recent entry and invokes the matching close action.

const MAX_ENTRIES := 32

var _stack: Array[StringName] = []


func push(entry: StringName) -> void:
	# Avoid consecutive duplicates (e.g. reopening the same drawer).
	if not _stack.is_empty() and _stack.back() == entry:
		return
	_stack.append(entry)
	if _stack.size() > MAX_ENTRIES:
		_stack.remove_at(0)


func pop() -> StringName:
	if _stack.is_empty():
		return &""
	return _stack.pop_back()


func remove(entry: StringName) -> void:
	var idx: int = _stack.rfind(entry)
	if idx >= 0:
		_stack.remove_at(idx)


func has_entry(entry: StringName) -> bool:
	return _stack.has(entry)


func is_empty() -> bool:
	return _stack.is_empty()


func clear() -> void:
	_stack.clear()
