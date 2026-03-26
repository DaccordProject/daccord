extends RefCounted
## Virtual scroll renderer for MessageView.
## Manages row data model, visible-window rendering (create/destroy),
## height measurement, and scroll compensation.

const CozyMessageScene := preload(
	"res://scenes/messages/cozy_message.tscn"
)
const CollapsedMessageScene := preload(
	"res://scenes/messages/collapsed_message.tscn"
)

const EST_COZY_HEIGHT := 72.0
const EST_COLLAPSED_HEIGHT := 28.0
const OVERSCAN := 3
const BUFFER_TARGET := 4

var _view: Control
var _row_data: Array = []
var _y_offsets: PackedFloat64Array = PackedFloat64Array()
var _total_height: float = 0.0
var _row_assignments: Dictionary = {}
var _assigned_set: Dictionary = {}
var _assignments_dirty: bool = false
var _pinned_message_id: String = ""
var _last_visible_first: int = -1
var _last_visible_last: int = -1

# Pre-instantiation buffers
var _cozy_buffer: Array = []
var _collapsed_buffer: Array = []


func _init(view: Control) -> void:
	_view = view


# -- Data model --

func rebuild_from_messages(messages: Array) -> void:
	clear()
	_row_data.clear()
	var prev_author_id: String = ""
	for i in messages.size():
		var msg: Dictionary = messages[i]
		var author: Dictionary = msg.get("author", {})
		var author_id: String = author.get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var use_collapsed: bool = (
			author_id == prev_author_id
			and not has_reply and i > 0
		)
		var row_type: String = (
			"collapsed" if use_collapsed else "cozy"
		)
		var est: float = (
			EST_COLLAPSED_HEIGHT
			if use_collapsed
			else EST_COZY_HEIGHT
		)
		_row_data.append({
			"msg_id": msg.get("id", ""),
			"msg": msg,
			"type": row_type,
			"height": est,
			"measured": false,
		})
		prev_author_id = author_id
	_rebuild_offsets()


func diff_update(messages: Array) -> int:
	# Build lookup of current row msg_ids
	var existing_ids: Dictionary = {}
	for i in _row_data.size():
		existing_ids[_row_data[i]["msg_id"]] = i

	# REMOVE rows for deleted messages
	var cache_ids: Dictionary = {}
	for msg in messages:
		cache_ids[msg.get("id", "")] = true
	var removed_indices: Array = []
	for i in range(_row_data.size() - 1, -1, -1):
		var mid: String = _row_data[i]["msg_id"]
		if not cache_ids.has(mid):
			# Free assigned node if any
			if _row_assignments.has(i):
				var node: Control = _row_assignments[i]
				_assigned_set.erase(node)
				_row_assignments.erase(i)
				node.queue_free()
			_row_data.remove_at(i)
			removed_indices.append(i)

	# Rebuild existing_ids after removals
	existing_ids.clear()
	for i in _row_data.size():
		existing_ids[_row_data[i]["msg_id"]] = i

	# UPDATE existing rows with fresh data
	for msg in messages:
		var mid: String = msg.get("id", "")
		if existing_ids.has(mid):
			var idx: int = existing_ids[mid]
			_row_data[idx]["msg"] = msg
			# Update visible node if assigned
			if _row_assignments.has(idx):
				var node: Control = _row_assignments[idx]
				if is_instance_valid(node) \
						and node.has_method("update_data"):
					node.update_data(msg)

	# APPEND new messages at the end
	var appended: int = 0
	for i in range(messages.size() - 1, -1, -1):
		var msg: Dictionary = messages[i]
		var mid: String = msg.get("id", "")
		if existing_ids.has(mid):
			break
		appended += 1

	if appended > 0:
		var start_idx: int = messages.size() - appended
		for i in range(start_idx, messages.size()):
			var msg: Dictionary = messages[i]
			var author: Dictionary = msg.get("author", {})
			var author_id: String = author.get("id", "")
			var has_reply: bool = msg.get("reply_to", "") != ""
			var prev_author_id: String = ""
			if i > 0:
				prev_author_id = messages[i - 1].get(
					"author", {}
				).get("id", "")
			var use_collapsed: bool = (
				author_id == prev_author_id
				and not has_reply and i > 0
			)
			var row_type: String = (
				"collapsed" if use_collapsed else "cozy"
			)
			var est: float = (
				EST_COLLAPSED_HEIGHT
				if use_collapsed
				else EST_COZY_HEIGHT
			)
			_row_data.append({
				"msg_id": msg.get("id", ""),
				"msg": msg,
				"type": row_type,
				"height": est,
				"measured": false,
			})

	# Fix layouts after deletion
	if not removed_indices.is_empty():
		_fixup_row_types(messages)

	# Rebuild assignments mapping after index shifts
	if not removed_indices.is_empty():
		_reassign_after_index_shift()

	_rebuild_offsets()
	_assignments_dirty = true
	return appended


# -- Rendering --

func update_visible_rows(scroll_value: float) -> void:
	if _row_data.is_empty():
		_clear_assignments()
		return

	var viewport_h: float = _view.scroll_container.size.y
	var vis_top: float = scroll_value
	var vis_bottom: float = scroll_value + viewport_h

	var first_row: int = maxi(
		0, _find_row_at_y(vis_top) - OVERSCAN
	)
	var last_row: int = mini(
		_row_data.size() - 1,
		_find_row_at_y(vis_bottom) + OVERSCAN,
	)

	if _assignments_dirty:
		_clear_assignments()
		_assignments_dirty = false

	# Reclaim off-screen nodes (except pinned)
	var to_reclaim: Array = []
	for row_idx in _row_assignments:
		if row_idx < first_row or row_idx > last_row:
			var rd: Dictionary = _row_data[row_idx]
			if (
				not _pinned_message_id.is_empty()
				and rd["msg_id"] == _pinned_message_id
			):
				continue
			to_reclaim.append(row_idx)
	for row_idx in to_reclaim:
		var node: Control = _row_assignments[row_idx]
		_assigned_set.erase(node)
		_row_assignments.erase(row_idx)
		node.queue_free()

	# Create nodes for visible rows that need them
	var virtual_content: Control = _view.virtual_content
	for row_idx in range(first_row, last_row + 1):
		if _row_assignments.has(row_idx):
			# Reposition existing node
			var node: Control = _row_assignments[row_idx]
			node.position.y = _y_offsets[row_idx]
			continue
		var rd: Dictionary = _row_data[row_idx]
		var node: HBoxContainer = _create_node(rd)
		virtual_content.add_child(node)
		node.setup(rd["msg"])
		node.position = Vector2(0, _y_offsets[row_idx])
		node.size.x = virtual_content.size.x
		# Connect hover/context signals
		node.mouse_entered.connect(
			_view._hover.on_msg_hovered.bind(node)
		)
		node.mouse_exited.connect(
			_view._hover.on_msg_unhovered.bind(node)
		)
		if node.has_signal("context_menu_requested"):
			node.context_menu_requested.connect(
				_view._on_context_menu_requested
			)
		_row_assignments[row_idx] = node
		_assigned_set[node] = row_idx

	_last_visible_first = first_row
	_last_visible_last = last_row

	# Schedule deferred height measurement
	if not _row_data.is_empty():
		_view.call_deferred("_on_virtual_measure")


func measure_heights() -> void:
	var sc: ScrollContainer = _view.scroll_container
	var scroll_val: float = float(sc.scroll_vertical)
	var viewport_h: float = sc.size.y
	var vis_top: float = scroll_val
	var correction: float = 0.0

	for row_idx in _row_assignments:
		var node: Control = _row_assignments[row_idx]
		if not is_instance_valid(node):
			continue
		var rd: Dictionary = _row_data[row_idx]
		if rd["measured"]:
			continue
		var actual_h: float = node.size.y
		if actual_h < 1.0:
			continue
		var delta: float = actual_h - rd["height"]
		if absf(delta) < 2.0:
			rd["measured"] = true
			continue
		rd["height"] = actual_h
		rd["measured"] = true
		# Accumulate correction for rows above viewport
		if _y_offsets[row_idx] < vis_top:
			correction += delta

	if correction != 0.0 or _needs_offset_rebuild():
		_rebuild_offsets()
		# Compensate scroll to prevent jumping
		if absf(correction) > 1.0:
			sc.scroll_vertical = int(scroll_val + correction)
		# Reposition visible nodes
		for row_idx in _row_assignments:
			var node: Control = _row_assignments[row_idx]
			if is_instance_valid(node):
				node.position.y = _y_offsets[row_idx]


# -- Lookup --

func find_node_for_message(message_id: String) -> Control:
	for row_idx in _row_assignments:
		var rd: Dictionary = _row_data[row_idx]
		if rd["msg_id"] == message_id:
			var node: Control = _row_assignments[row_idx]
			if is_instance_valid(node):
				return node
	return null


func find_row_index_for_message(
	message_id: String,
) -> int:
	for i in _row_data.size():
		if _row_data[i]["msg_id"] == message_id:
			return i
	return -1


func get_row_y(row_index: int) -> float:
	if row_index < 0 or row_index >= _y_offsets.size():
		return 0.0
	return _y_offsets[row_index]


func get_visible_nodes() -> Array:
	var nodes: Array = []
	for node in _assigned_set:
		if is_instance_valid(node):
			nodes.append(node)
	return nodes


func get_last_row_node() -> Control:
	if _row_data.is_empty():
		return null
	var last_idx: int = _row_data.size() - 1
	if _row_assignments.has(last_idx):
		var node: Control = _row_assignments[last_idx]
		if is_instance_valid(node):
			return node
	return null


func row_count() -> int:
	return _row_data.size()


# -- Edit pinning --

func pin_editing(message_id: String) -> void:
	_pinned_message_id = message_id


func unpin_editing() -> void:
	_pinned_message_id = ""


# -- Lifecycle --

func clear() -> void:
	for node in _assigned_set:
		if is_instance_valid(node):
			node.queue_free()
	_row_assignments.clear()
	_assigned_set.clear()
	_row_data.clear()
	_y_offsets = PackedFloat64Array()
	_total_height = 0.0
	_last_visible_first = -1
	_last_visible_last = -1
	_pinned_message_id = ""
	if is_instance_valid(_view) and _view.virtual_content:
		_view.virtual_content.custom_minimum_size.y = 0.0


# -- Pre-instantiation buffer --

func replenish_buffer() -> void:
	if _cozy_buffer.size() < BUFFER_TARGET:
		var node: HBoxContainer = CozyMessageScene.instantiate()
		_cozy_buffer.append(node)
		return
	if _collapsed_buffer.size() < BUFFER_TARGET:
		var node: HBoxContainer = CollapsedMessageScene.instantiate()
		_collapsed_buffer.append(node)


func free_buffers() -> void:
	for node in _cozy_buffer:
		if is_instance_valid(node):
			node.queue_free()
	_cozy_buffer.clear()
	for node in _collapsed_buffer:
		if is_instance_valid(node):
			node.queue_free()
	_collapsed_buffer.clear()


# -- Private helpers --

func _create_node(rd: Dictionary) -> HBoxContainer:
	var node: HBoxContainer
	if rd["type"] == "collapsed":
		if not _collapsed_buffer.is_empty():
			node = _collapsed_buffer.pop_back()
		else:
			node = CollapsedMessageScene.instantiate()
	else:
		if not _cozy_buffer.is_empty():
			node = _cozy_buffer.pop_back()
		else:
			node = CozyMessageScene.instantiate()
	return node


func _rebuild_offsets() -> void:
	_y_offsets.resize(_row_data.size())
	var y: float = 0.0
	for i in _row_data.size():
		_y_offsets[i] = y
		y += _row_data[i]["height"]
	_total_height = y
	if is_instance_valid(_view) and _view.virtual_content:
		_view.virtual_content.custom_minimum_size.y = y


func _find_row_at_y(y: float) -> int:
	if _y_offsets.is_empty():
		return 0
	# Binary search for the row containing y position
	var lo: int = 0
	var hi: int = _y_offsets.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if _y_offsets[mid] <= y:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _clear_assignments() -> void:
	for node in _assigned_set:
		if is_instance_valid(node):
			node.queue_free()
	_row_assignments.clear()
	_assigned_set.clear()


func _needs_offset_rebuild() -> bool:
	# Check if any measured height differs from offsets
	var y: float = 0.0
	for i in _row_data.size():
		if i < _y_offsets.size() and absf(_y_offsets[i] - y) > 1.0:
			return true
		y += _row_data[i]["height"]
	return false


func _fixup_row_types(_messages: Array) -> void:
	# After deletion, fix cozy/collapsed types
	for i in _row_data.size():
		var rd: Dictionary = _row_data[i]
		var msg: Dictionary = rd["msg"]
		var author_id: String = msg.get(
			"author", {}
		).get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var prev_author_id: String = ""
		if i > 0:
			prev_author_id = _row_data[i - 1]["msg"].get(
				"author", {}
			).get("id", "")
		var should_collapsed: bool = (
			author_id == prev_author_id
			and not has_reply and i > 0
		)
		var new_type: String = (
			"collapsed" if should_collapsed else "cozy"
		)
		if rd["type"] != new_type:
			rd["type"] = new_type
			rd["height"] = (
				EST_COLLAPSED_HEIGHT
				if should_collapsed
				else EST_COZY_HEIGHT
			)
			rd["measured"] = false
			# Free mismatched node if assigned
			for row_idx in _row_assignments:
				if row_idx == i:
					var node: Control = _row_assignments[row_idx]
					_assigned_set.erase(node)
					_row_assignments.erase(row_idx)
					node.queue_free()
					break


func _reassign_after_index_shift() -> void:
	# After row removals, assignment indices are stale.
	# Clear and let next update_visible_rows recreate.
	_clear_assignments()
	_assignments_dirty = false
