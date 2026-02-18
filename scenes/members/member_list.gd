extends PanelContainer

const MEMBER_ITEM_SCENE := preload("res://scenes/members/member_item.tscn")
const MEMBER_HEADER_SCENE := preload("res://scenes/members/member_header.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const ROW_HEIGHT := 44

var _guild_id: String = ""
var _row_data: Array = []
var _item_pool: Array = []
var _header_pool: Array = []
var _pool_size: int = 0

@onready var header_label: Label = $VBox/HeaderLabel
@onready var invite_btn: Button = $VBox/InviteButton
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var virtual_content: Control = $VBox/ScrollContainer/VirtualContent

func _ready() -> void:
	header_label.add_theme_font_size_override("font_size", 11)
	header_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	header_label.uppercase = true
	header_label.text = "Members"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.184, 0.192, 0.212)
	add_theme_stylebox_override("panel", style)

	invite_btn.pressed.connect(_on_invite_pressed)

	AppState.guild_selected.connect(_on_guild_selected)
	AppState.members_updated.connect(_on_members_updated)
	scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	scroll_container.resized.connect(_on_scroll_resized)

func _on_guild_selected(guild_id: String) -> void:
	_guild_id = guild_id
	_row_data.clear()
	_update_virtual_height()
	_hide_all_pool_nodes()
	invite_btn.visible = Client.has_permission(guild_id, AccordPermission.CREATE_INVITES)
	if not Client.get_members_for_guild(guild_id).is_empty():
		_rebuild_row_data()

func _on_members_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_rebuild_row_data()

func _rebuild_row_data() -> void:
	_row_data.clear()
	var members: Array = Client.get_members_for_guild(_guild_id)

	var groups: Dictionary = {
		ClientModels.UserStatus.ONLINE: [],
		ClientModels.UserStatus.IDLE: [],
		ClientModels.UserStatus.DND: [],
		ClientModels.UserStatus.OFFLINE: [],
	}

	for member in members:
		var status: int = member.get("status", ClientModels.UserStatus.OFFLINE)
		if groups.has(status):
			groups[status].append(member)
		else:
			groups[ClientModels.UserStatus.OFFLINE].append(member)

	for status_key in groups:
		groups[status_key].sort_custom(func(a, b):
			return a.get("display_name", "").to_lower() < b.get("display_name", "").to_lower()
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
		_row_data.append({"type": "header", "label": "%s — %d" % [label, group.size()]})
		for member in group:
			_row_data.append({"type": "member", "data": member})

	_update_virtual_height()
	_ensure_pool_size()
	_update_visible_items(scroll_container.get_v_scroll_bar().value)

func _update_virtual_height() -> void:
	virtual_content.custom_minimum_size.y = _row_data.size() * ROW_HEIGHT

func _ensure_pool_size() -> void:
	var viewport_height: float = scroll_container.size.y
	var needed: int = ceili(viewport_height / ROW_HEIGHT) + 8
	if needed <= _pool_size:
		return
	for i in range(_pool_size, needed):
		var item: Control = MEMBER_ITEM_SCENE.instantiate()
		item.visible = false
		virtual_content.add_child(item)
		_item_pool.append(item)
		var header: Control = MEMBER_HEADER_SCENE.instantiate()
		header.visible = false
		virtual_content.add_child(header)
		_header_pool.append(header)
	_pool_size = needed

func _hide_all_pool_nodes() -> void:
	for node in _item_pool:
		node.visible = false
	for node in _header_pool:
		node.visible = false

func _on_scroll_changed(value: float) -> void:
	_update_visible_items(value)

func _on_scroll_resized() -> void:
	_ensure_pool_size()
	_update_visible_items(scroll_container.get_v_scroll_bar().value)

func _update_visible_items(scroll_value: float) -> void:
	_hide_all_pool_nodes()
	if _row_data.is_empty():
		return

	var first_row: int = maxi(0, floori(scroll_value / ROW_HEIGHT))
	var viewport_height: float = scroll_container.size.y
	var visible_end := ceili((scroll_value + viewport_height) / ROW_HEIGHT)
	var last_row: int = mini(_row_data.size() - 1, visible_end)

	var item_idx: int = 0
	var header_idx: int = 0

	for row_index in range(first_row, last_row + 1):
		var row: Dictionary = _row_data[row_index]
		var y_pos: float = row_index * ROW_HEIGHT

		if row["type"] == "header":
			if header_idx < _header_pool.size():
				var header: Control = _header_pool[header_idx]
				header.setup(row)
				header.position = Vector2(0, y_pos)
				header.size = Vector2(virtual_content.size.x, ROW_HEIGHT)
				header.visible = true
				header_idx += 1
		else:
			if item_idx < _item_pool.size():
				var item: Control = _item_pool[item_idx]
				item.setup(row["data"])
				item.position = Vector2(0, y_pos)
				item.size = Vector2(virtual_content.size.x, ROW_HEIGHT)
				item.visible = true
				item_idx += 1

func _on_invite_pressed() -> void:
	var dialog := InviteMgmtScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(_guild_id)
