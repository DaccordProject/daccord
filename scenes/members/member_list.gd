extends PanelContainer

const MEMBER_ITEM_SCENE := preload("res://scenes/members/member_item.tscn")
const MEMBER_HEADER_SCENE := preload("res://scenes/members/member_header.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const ROW_HEIGHT := 44

const DEBOUNCE_MS := 100
const POOL_SHRINK_HYSTERESIS := 8

var _guild_id: String = ""
var _row_data: Array = []
var _item_pool: Array = []
var _header_pool: Array = []
var _pool_size: int = 0
var _active_items: Array = []
var _active_headers: Array = []
var _debounce_timer: Timer
var _search_text: String = ""
var _group_by_role: bool = false
var _incremental_handled: bool = false

@onready var header_label: Label = $VBox/HeaderBar/HeaderLabel
@onready var group_toggle: Button = $VBox/HeaderBar/GroupToggle
@onready var invite_btn: Button = $VBox/InviteButton
@onready var search_bar: LineEdit = $VBox/SearchBar
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var virtual_content: Control = $VBox/ScrollContainer/VirtualContent

func _ready() -> void:
	header_label.add_theme_font_size_override("font_size", 11)
	header_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	header_label.uppercase = true
	header_label.text = "Members"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.184, 0.192, 0.212)
	add_theme_stylebox_override("panel", style)

	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color(0.118, 0.129, 0.149)
	search_style.set_content_margin_all(4)
	search_bar.add_theme_stylebox_override("normal", search_style)

	invite_btn.pressed.connect(_on_invite_pressed)
	search_bar.text_changed.connect(_on_search_changed)
	group_toggle.pressed.connect(_on_group_toggle_pressed)

	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = DEBOUNCE_MS / 1000.0
	_debounce_timer.timeout.connect(_rebuild_row_data)
	add_child(_debounce_timer)

	AppState.guild_selected.connect(_on_guild_selected)
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.members_updated.connect(_on_members_updated)
	AppState.member_joined.connect(_on_member_joined)
	AppState.member_left.connect(_on_member_left)
	AppState.member_status_changed.connect(
		_on_member_status_changed
	)
	AppState.roles_updated.connect(_on_roles_updated)
	scroll_container.get_v_scroll_bar().value_changed.connect(
		_on_scroll_changed
	)
	scroll_container.resized.connect(_on_scroll_resized)

func _on_guild_selected(guild_id: String) -> void:
	_guild_id = guild_id
	_row_data.clear()
	_search_text = ""
	search_bar.text = ""
	_update_virtual_height()
	_hide_all_pool_nodes()
	invite_btn.visible = Client.has_permission(
		guild_id, AccordPermission.CREATE_INVITES
	)
	if not Client.get_members_for_guild(guild_id).is_empty():
		_rebuild_row_data()

func _on_channel_selected(channel_id: String) -> void:
	if not AppState.is_dm_mode:
		return
	# Check if this is a group DM — show participants
	var dm: Dictionary = {}
	for d in Client.dm_channels:
		if d["id"] == channel_id:
			dm = d
			break
	if not dm.get("is_group", false):
		return
	_build_dm_participants(dm)

func _on_members_updated(guild_id: String) -> void:
	if guild_id != _guild_id:
		return
	if _incremental_handled:
		_incremental_handled = false
		return
	_debounce_timer.start()

func _on_roles_updated(guild_id: String) -> void:
	if guild_id == _guild_id and _group_by_role:
		_rebuild_row_data()

func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges().to_lower()
	_rebuild_row_data()

func _on_group_toggle_pressed() -> void:
	_group_by_role = not _group_by_role
	group_toggle.text = "Roles" if _group_by_role else "Status"
	_rebuild_row_data()

# -- Full rebuild --

func _rebuild_row_data() -> void:
	_row_data.clear()
	if _group_by_role:
		_build_role_groups()
	else:
		_build_status_groups()
	_update_virtual_height()
	_adjust_pool_size()
	_update_visible_items(
		scroll_container.get_v_scroll_bar().value
	)

func _build_status_groups() -> void:
	var members: Array = Client.get_members_for_guild(_guild_id)

	var groups: Dictionary = {
		ClientModels.UserStatus.ONLINE: [],
		ClientModels.UserStatus.IDLE: [],
		ClientModels.UserStatus.DND: [],
		ClientModels.UserStatus.OFFLINE: [],
	}

	for member in members:
		if not _search_text.is_empty():
			var name_lower: String = member.get(
				"display_name", ""
			).to_lower()
			if _search_text not in name_lower:
				continue
		var status: int = member.get(
			"status", ClientModels.UserStatus.OFFLINE
		)
		if groups.has(status):
			groups[status].append(member)
		else:
			groups[ClientModels.UserStatus.OFFLINE].append(member)

	for status_key in groups:
		groups[status_key].sort_custom(func(a, b):
			return a.get("display_name", "").to_lower() \
				< b.get("display_name", "").to_lower()
		)

	var status_labels: Array = [
		[ClientModels.UserStatus.ONLINE, "ONLINE"],
		[ClientModels.UserStatus.IDLE, "IDLE"],
		[ClientModels.UserStatus.DND, "DO NOT DISTURB"],
		[ClientModels.UserStatus.OFFLINE, "OFFLINE"],
	]

	for entry in status_labels:
		var status: int = entry[0]
		var label: String = entry[1]
		var group: Array = groups[status]
		if group.is_empty():
			continue
		_row_data.append({
			"type": "header",
			"label": "%s — %d" % [label, group.size()],
			"status": status,
		})
		for member in group:
			_row_data.append({"type": "member", "data": member})

func _build_role_groups() -> void:
	var members: Array = Client.get_members_for_guild(_guild_id)
	var roles: Array = Client.get_roles_for_guild(_guild_id)

	var role_lookup: Dictionary = {}
	for role in roles:
		role_lookup[role.get("id", "")] = role

	var sorted_roles: Array = roles.duplicate()
	sorted_roles.sort_custom(func(a, b):
		return a.get("position", 0) > b.get("position", 0)
	)

	var groups: Dictionary = {}
	var no_role_members: Array = []

	for member in members:
		if not _search_text.is_empty():
			var name_lower: String = member.get(
				"display_name", ""
			).to_lower()
			if _search_text not in name_lower:
				continue
		var member_roles: Array = member.get("roles", [])
		var highest_role_id: String = ""
		var highest_position: int = -1
		for rid in member_roles:
			var role: Dictionary = role_lookup.get(rid, {})
			var pos: int = role.get("position", 0)
			if pos > highest_position and pos > 0:
				highest_position = pos
				highest_role_id = rid
		if highest_role_id.is_empty():
			no_role_members.append(member)
		else:
			if not groups.has(highest_role_id):
				groups[highest_role_id] = []
			groups[highest_role_id].append(member)

	for role in sorted_roles:
		if role.get("position", 0) <= 0:
			continue
		var rid: String = role.get("id", "")
		if not groups.has(rid):
			continue
		var group: Array = groups[rid]
		group.sort_custom(func(a, b):
			return a.get("display_name", "").to_lower() \
				< b.get("display_name", "").to_lower()
		)
		_row_data.append({
			"type": "header",
			"label": "%s — %d" % [
				role.get("name", "Unknown"), group.size()
			],
		})
		for member in group:
			_row_data.append({"type": "member", "data": member})

	if not no_role_members.is_empty():
		no_role_members.sort_custom(func(a, b):
			return a.get("display_name", "").to_lower() \
				< b.get("display_name", "").to_lower()
		)
		_row_data.append({
			"type": "header",
			"label": "No Role — %d" % no_role_members.size(),
		})
		for member in no_role_members:
			_row_data.append({"type": "member", "data": member})

func _build_dm_participants(dm: Dictionary) -> void:
	_row_data.clear()
	_guild_id = ""
	invite_btn.visible = false
	group_toggle.visible = false

	var recipients: Array = dm.get("recipients", [])
	var owner_id: String = dm.get("owner_id", "")
	var my_dict: Dictionary = Client.current_user

	# Combine recipients + current user
	var participants: Array = recipients.duplicate()
	var has_self: bool = false
	var my_id: String = my_dict.get("id", "")
	for r in participants:
		if r.get("id", "") == my_id:
			has_self = true
			break
	if not has_self and not my_id.is_empty():
		participants.append(my_dict)

	participants.sort_custom(func(a, b):
		return a.get("display_name", "").to_lower() \
			< b.get("display_name", "").to_lower()
	)

	_row_data.append({
		"type": "header",
		"label": "PARTICIPANTS — %d" % participants.size(),
	})

	for p in participants:
		var member: Dictionary = p.duplicate()
		# Mark the owner
		if member.get("id", "") == owner_id:
			member["_is_owner"] = true
		_row_data.append({"type": "member", "data": member})

	_update_virtual_height()
	_adjust_pool_size()
	_update_visible_items(
		scroll_container.get_v_scroll_bar().value
	)

# -- Incremental updates (status grouping, no search) --

func _can_incremental() -> bool:
	return _search_text.is_empty() and not _group_by_role

func _on_member_joined(
	guild_id: String, member_data: Dictionary,
) -> void:
	if guild_id != _guild_id or not _can_incremental():
		return
	_incremental_handled = true
	var user_id: String = member_data.get("id", "")
	if not user_id.is_empty() \
			and _find_member_row(user_id) != -1:
		return
	_insert_member_into_group(member_data)
	_after_incremental_change()

func _on_member_left(
	guild_id: String, user_id: String,
) -> void:
	if guild_id != _guild_id or not _can_incremental():
		return
	_incremental_handled = true
	_remove_member_row(user_id)
	_after_incremental_change()

func _on_member_status_changed(
	guild_id: String, user_id: String, new_status: int,
) -> void:
	if guild_id != _guild_id or not _can_incremental():
		return
	_incremental_handled = true
	var member_data: Dictionary = _remove_member_row(user_id)
	if not member_data.is_empty():
		member_data["status"] = new_status
		_insert_member_into_group(member_data)
	_after_incremental_change()

func _after_incremental_change() -> void:
	_update_virtual_height()
	_adjust_pool_size()
	_update_visible_items(
		scroll_container.get_v_scroll_bar().value
	)

# -- Incremental helpers --

func _status_label_for(status: int) -> String:
	match status:
		ClientModels.UserStatus.ONLINE:
			return "ONLINE"
		ClientModels.UserStatus.IDLE:
			return "IDLE"
		ClientModels.UserStatus.DND:
			return "DO NOT DISTURB"
		ClientModels.UserStatus.OFFLINE:
			return "OFFLINE"
	return "UNKNOWN"

func _status_order() -> Array:
	return [
		ClientModels.UserStatus.ONLINE,
		ClientModels.UserStatus.IDLE,
		ClientModels.UserStatus.DND,
		ClientModels.UserStatus.OFFLINE,
	]

func _find_group_range(status: int) -> Array:
	for i in _row_data.size():
		var row: Dictionary = _row_data[i]
		if row["type"] == "header" \
				and row.get("status", -1) == status:
			var start: int = i + 1
			var end_idx: int = start
			while end_idx < _row_data.size() \
					and _row_data[end_idx]["type"] == "member":
				end_idx += 1
			return [i, start, end_idx]
	return [-1, -1, -1]

func _find_member_row(user_id: String) -> int:
	for i in _row_data.size():
		if _row_data[i]["type"] == "member" \
				and _row_data[i]["data"].get("id", "") == user_id:
			return i
	return -1

func _insert_member_into_group(
	member_data: Dictionary,
) -> void:
	var status: int = member_data.get(
		"status", ClientModels.UserStatus.OFFLINE
	)
	var range_info: Array = _find_group_range(status)
	var name_lower: String = member_data.get(
		"display_name", ""
	).to_lower()

	if range_info[0] == -1:
		# Group doesn't exist — create at correct position
		var insert_at: int = _row_data.size()
		var order: Array = _status_order()
		for s_idx in order.size():
			if order[s_idx] == status:
				for later_idx in range(
					s_idx + 1, order.size()
				):
					var later_range: Array = _find_group_range(
						order[later_idx]
					)
					if later_range[0] != -1:
						insert_at = later_range[0]
						break
				break
		var label: String = _status_label_for(status)
		_row_data.insert(insert_at, {
			"type": "header",
			"label": "%s — 1" % label,
			"status": status,
		})
		_row_data.insert(
			insert_at + 1,
			{"type": "member", "data": member_data},
		)
	else:
		# Group exists — find alphabetical position
		var start: int = range_info[1]
		var end_idx: int = range_info[2]
		var pos: int = start
		while pos < end_idx:
			var existing_name: String = _row_data[pos] \
				["data"].get("display_name", "").to_lower()
			if name_lower < existing_name:
				break
			pos += 1
		_row_data.insert(
			pos, {"type": "member", "data": member_data}
		)
		var count: int = (end_idx - start) + 1
		var label: String = _status_label_for(status)
		_row_data[range_info[0]]["label"] = \
			"%s — %d" % [label, count]

func _remove_member_row(user_id: String) -> Dictionary:
	var row_idx: int = _find_member_row(user_id)
	if row_idx == -1:
		return {}
	var member_data: Dictionary = _row_data[row_idx]["data"]

	# Find header above this member
	var header_idx: int = -1
	for i in range(row_idx - 1, -1, -1):
		if _row_data[i]["type"] == "header":
			header_idx = i
			break

	_row_data.remove_at(row_idx)

	# Update header count or remove empty group
	if header_idx != -1:
		var count: int = 0
		var i: int = header_idx + 1
		while i < _row_data.size() \
				and _row_data[i]["type"] == "member":
			count += 1
			i += 1
		if count == 0:
			_row_data.remove_at(header_idx)
		else:
			var status: int = _row_data[header_idx].get(
				"status", -1
			)
			if status != -1:
				var label: String = _status_label_for(status)
				_row_data[header_idx]["label"] = \
					"%s — %d" % [label, count]
	return member_data

# -- Virtual scroll infrastructure --

func _update_virtual_height() -> void:
	virtual_content.custom_minimum_size.y = \
		_row_data.size() * ROW_HEIGHT

func _adjust_pool_size() -> void:
	var viewport_height: float = scroll_container.size.y
	var needed: int = ceili(viewport_height / ROW_HEIGHT) + 8
	if needed > _pool_size:
		for i in range(_pool_size, needed):
			var item: Control = MEMBER_ITEM_SCENE.instantiate()
			item.visible = false
			virtual_content.add_child(item)
			_item_pool.append(item)
			var header: Control = \
				MEMBER_HEADER_SCENE.instantiate()
			header.visible = false
			virtual_content.add_child(header)
			_header_pool.append(header)
		_pool_size = needed
	elif needed < _pool_size - POOL_SHRINK_HYSTERESIS:
		_hide_all_pool_nodes()
		var excess: int = _pool_size - needed
		for i in range(excess):
			_item_pool.pop_back().queue_free()
			_header_pool.pop_back().queue_free()
		_pool_size = needed

func _hide_all_pool_nodes() -> void:
	for node in _active_items:
		node.visible = false
	for node in _active_headers:
		node.visible = false
	_active_items.clear()
	_active_headers.clear()

func _on_scroll_changed(value: float) -> void:
	_update_visible_items(value)

func _on_scroll_resized() -> void:
	_adjust_pool_size()
	_update_visible_items(
		scroll_container.get_v_scroll_bar().value
	)

func _update_visible_items(scroll_value: float) -> void:
	_hide_all_pool_nodes()
	if _row_data.is_empty():
		return

	var first_row: int = maxi(
		0, floori(scroll_value / ROW_HEIGHT)
	)
	var viewport_height: float = scroll_container.size.y
	var visible_end := ceili(
		(scroll_value + viewport_height) / ROW_HEIGHT
	)
	var last_row: int = mini(
		_row_data.size() - 1, visible_end
	)

	var item_idx: int = 0
	var header_idx: int = 0

	for row_index in range(first_row, last_row + 1):
		var row: Dictionary = _row_data[row_index]
		var y_pos: float = row_index * ROW_HEIGHT

		if row["type"] == "header":
			if header_idx < _header_pool.size():
				var header: Control = \
					_header_pool[header_idx]
				header.setup(row)
				header.position = Vector2(0, y_pos)
				header.size = Vector2(
					virtual_content.size.x, ROW_HEIGHT
				)
				header.visible = true
				_active_headers.append(header)
				header_idx += 1
		else:
			if item_idx < _item_pool.size():
				var item: Control = _item_pool[item_idx]
				item.setup(row["data"])
				item.position = Vector2(0, y_pos)
				item.size = Vector2(
					virtual_content.size.x, ROW_HEIGHT
				)
				item.visible = true
				_active_items.append(item)
				item_idx += 1

func _on_invite_pressed() -> void:
	var dialog := InviteMgmtScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(_guild_id)
