extends ColorRect

const AuditLogRowScene := preload("res://scenes/admin/audit_log_row.tscn")

const PAGE_SIZE := 25

var _guild_id: String = ""
var _all_entries: Array = []
var _last_entry_id: String = ""
var _has_more: bool = false

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
@onready var _filter_option: OptionButton = $CenterContainer/Panel/VBox/FilterRow/FilterOption
@onready var _entry_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/EntryList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _load_more_btn: Button = $CenterContainer/Panel/VBox/LoadMoreButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_search_input.text_changed.connect(_on_search_changed)
	_filter_option.item_selected.connect(_on_filter_changed)
	_load_more_btn.pressed.connect(_on_load_more)

	_filter_option.add_item("All Actions", 0)
	_filter_option.add_item("Member Kick", 1)
	_filter_option.add_item("Member Ban Add", 2)
	_filter_option.add_item("Member Ban Remove", 3)
	_filter_option.add_item("Member Update", 4)
	_filter_option.add_item("Role Create", 5)
	_filter_option.add_item("Role Update", 6)
	_filter_option.add_item("Role Delete", 7)
	_filter_option.add_item("Channel Create", 8)
	_filter_option.add_item("Channel Update", 9)
	_filter_option.add_item("Channel Delete", 10)
	_filter_option.add_item("Invite Create", 11)
	_filter_option.add_item("Invite Delete", 12)
	_filter_option.add_item("Message Delete", 13)
	_filter_option.add_item("Space Update", 14)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_load_entries()

func _load_entries() -> void:
	for child in _entry_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_entries.clear()
	_last_entry_id = ""
	_has_more = false
	_load_more_btn.visible = false
	await _fetch_page()

func _fetch_page() -> void:
	var query: Dictionary = {"limit": PAGE_SIZE}
	if not _last_entry_id.is_empty():
		query["before"] = _last_entry_id

	var action_filter: String = _get_selected_action_type()
	if not action_filter.is_empty():
		query["action_type"] = action_filter

	var result: RestResult = await Client.admin.get_audit_log(
		_guild_id, query
	)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load audit log"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var entries: Array = result.data if result.data is Array else []

	if entries.is_empty() and _all_entries.is_empty():
		_empty_label.visible = true
		return

	for entry in entries:
		var entry_dict: Dictionary = entry if entry is Dictionary else {}
		if entry_dict.has("id"):
			_all_entries.append(entry_dict)
			_last_entry_id = str(entry_dict.get("id", ""))

	_has_more = entries.size() >= PAGE_SIZE
	_load_more_btn.visible = _has_more
	_rebuild_list(_all_entries)

func _rebuild_list(entries: Array) -> void:
	for child in _entry_list.get_children():
		child.queue_free()

	if entries.is_empty():
		_empty_label.visible = _all_entries.is_empty()
		return
	_empty_label.visible = false

	for entry_dict in entries:
		var row := AuditLogRowScene.instantiate()
		_entry_list.add_child(row)
		row.setup(entry_dict)

func _get_selected_action_type() -> String:
	var idx: int = _filter_option.selected
	var action_types := [
		"", "member_kick", "member_ban_add", "member_ban_remove",
		"member_update", "role_create", "role_update", "role_delete",
		"channel_create", "channel_update", "channel_delete",
		"invite_create", "invite_delete", "message_delete", "space_update",
	]
	if idx >= 0 and idx < action_types.size():
		return action_types[idx]
	return ""

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_rebuild_list(_all_entries)
		return
	var filtered: Array = []
	for entry in _all_entries:
		var action: String = entry.get("action_type", "").to_lower()
		var user_id: String = str(entry.get("user_id", ""))
		var reason: String = entry.get("reason", "").to_lower()
		if action.contains(query) or user_id.contains(query) or reason.contains(query):
			filtered.append(entry)
	_rebuild_list(filtered)

func _on_filter_changed(_idx: int) -> void:
	_load_entries()

func _on_load_more() -> void:
	_load_more_btn.disabled = true
	_load_more_btn.text = "Loading..."
	await _fetch_page()
	_load_more_btn.disabled = false
	_load_more_btn.text = "Load More"

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
