extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const BanRowScene := preload("res://scenes/admin/ban_row.tscn")

var _guild_id: String = ""
var _all_bans: Array = []
var _selected_user_ids: Array = []

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
@onready var _ban_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/BanList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

@onready var _bulk_bar: HBoxContainer = $CenterContainer/Panel/VBox/BulkBar
@onready var _select_all_check: CheckBox = $CenterContainer/Panel/VBox/BulkBar/SelectAllCheck
@onready var _bulk_unban_btn: Button = $CenterContainer/Panel/VBox/BulkBar/BulkUnbanBtn

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_search_input.text_changed.connect(_on_search_changed)
	_select_all_check.toggled.connect(_on_select_all)
	_bulk_unban_btn.pressed.connect(_on_bulk_unban)
	AppState.bans_updated.connect(_on_bans_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_load_bans()

func _load_bans() -> void:
	for child in _ban_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_bans.clear()
	_selected_user_ids.clear()
	_update_bulk_ui()

	var result: RestResult = await Client.admin.get_bans(_guild_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load bans"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var bans: Array = result.data if result.data is Array else []
	if bans.is_empty():
		_empty_label.visible = true
		return

	for ban in bans:
		var ban_dict: Dictionary = ban if ban is Dictionary else {}
		_all_bans.append(ban_dict)

	_rebuild_list(_all_bans)
	_bulk_bar.visible = _all_bans.size() > 0

func _rebuild_list(bans: Array) -> void:
	for child in _ban_list.get_children():
		child.queue_free()

	if bans.is_empty():
		_empty_label.visible = _all_bans.is_empty()
		return
	_empty_label.visible = false

	for ban_dict in bans:
		var row := BanRowScene.instantiate()
		_ban_list.add_child(row)
		var uid := _get_ban_user_id(ban_dict)
		row.setup(ban_dict, uid in _selected_user_ids)
		row.toggled.connect(_on_row_toggled)
		row.unban_requested.connect(_on_unban)

func _get_ban_username(ban: Dictionary) -> String:
	var user_data = ban.get("user", {})
	if user_data is Dictionary:
		return str(user_data.get("username", user_data.get("display_name", "Unknown")))
	return str(ban.get("user_id", ""))

func _get_ban_user_id(ban: Dictionary) -> String:
	var user_data = ban.get("user", {})
	if user_data is Dictionary:
		return str(user_data.get("id", ""))
	return str(ban.get("user_id", ""))

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_rebuild_list(_all_bans)
		return
	var filtered: Array = []
	for ban in _all_bans:
		if _get_ban_username(ban).to_lower().contains(query):
			filtered.append(ban)
	_rebuild_list(filtered)

func _on_row_toggled(pressed: bool, user_id: String) -> void:
	if pressed and user_id not in _selected_user_ids:
		_selected_user_ids.append(user_id)
	elif not pressed:
		_selected_user_ids.erase(user_id)
	_update_bulk_ui()

func _on_select_all(pressed: bool) -> void:
	_selected_user_ids.clear()
	if pressed:
		for ban in _all_bans:
			_selected_user_ids.append(_get_ban_user_id(ban))
	# Refresh checkboxes
	for row in _ban_list.get_children():
		var cb := row.get_child(0)
		if cb is CheckBox:
			cb.set_pressed_no_signal(pressed)
	_update_bulk_ui()

func _update_bulk_ui() -> void:
	_bulk_unban_btn.visible = _selected_user_ids.size() > 0
	if _selected_user_ids.size() > 0:
		_bulk_unban_btn.text = "Unban Selected (%d)" % _selected_user_ids.size()

func _on_bulk_unban() -> void:
	var count := _selected_user_ids.size()
	if count == 0:
		return
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Bulk Unban",
		"Are you sure you want to unban %d user(s)?" % count,
		"Unban All",
		false
	)
	dialog.confirmed.connect(func():
		for uid in _selected_user_ids.duplicate():
			await Client.admin.unban_member(_guild_id, uid)
		_selected_user_ids.clear()
		_update_bulk_ui()
	)

func _on_unban(user_id: String, username: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Unban User",
		"Are you sure you want to unban %s?" % username,
		"Unban",
		false
	)
	dialog.confirmed.connect(func():
		Client.admin.unban_member(_guild_id, user_id)
	)

func _on_bans_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_load_bans()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
