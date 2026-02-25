extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ChannelEditScene := preload("res://scenes/admin/channel_edit_dialog.tscn")
const ChannelPermissionsScene := preload("res://scenes/admin/channel_permissions_dialog.tscn")
const ChannelRowScene := preload("res://scenes/admin/channel_row.tscn")

var _space_id: String = ""
var _all_channels: Array = []
var _selected_ids: Array = []

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
@onready var _channel_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/ChannelList
@onready var _create_toggle: Button = $CenterContainer/Panel/VBox/CreateToggle
@onready var _create_form: VBoxContainer = $CenterContainer/Panel/VBox/CreateForm
@onready var _create_name: LineEdit = $CenterContainer/Panel/VBox/CreateForm/CreateNameInput
@onready var _create_type: OptionButton = $CenterContainer/Panel/VBox/CreateForm/CreateTypeOption
@onready var _create_parent: OptionButton = \
	$CenterContainer/Panel/VBox/CreateForm/CreateParentOption
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/CreateForm/CreateButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

@onready var _bulk_bar: HBoxContainer = $CenterContainer/Panel/VBox/BulkBar
@onready var _select_all_check: CheckBox = $CenterContainer/Panel/VBox/BulkBar/SelectAllCheck
@onready var _bulk_delete_btn: Button = $CenterContainer/Panel/VBox/BulkBar/BulkDeleteBtn

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_create_toggle.pressed.connect(_toggle_create_form)
	_create_btn.pressed.connect(_on_create)
	_create_form.visible = false
	_search_input.text_changed.connect(_on_search_changed)
	_select_all_check.toggled.connect(_on_select_all)
	_bulk_delete_btn.pressed.connect(_on_bulk_delete)

	_create_type.add_item("Text", 0)
	_create_type.add_item("Voice", 1)
	_create_type.add_item("Announcement", 2)
	_create_type.add_item("Forum", 3)
	_create_type.add_item("Category", 4)

	AppState.channels_updated.connect(_on_channels_updated)

func setup(space_id: String) -> void:
	_space_id = space_id
	_rebuild_list()
	_rebuild_parent_options()

func _rebuild_list() -> void:
	_all_channels = Client.get_channels_for_space(_space_id)
	_all_channels.sort_custom(func(a: Dictionary, b: Dictionary):
		var pos_a: int = a.get("position", 0) if a.has("position") else 0
		var pos_b: int = b.get("position", 0) if b.has("position") else 0
		if pos_a != pos_b:
			return pos_a < pos_b
		return a.get("name", "") < b.get("name", "")
	)
	_selected_ids.clear()
	_update_bulk_ui()
	_build_channel_rows(_all_channels)
	_bulk_bar.visible = _all_channels.size() > 0

func _build_channel_rows(channels: Array) -> void:
	for child in _channel_list.get_children():
		child.queue_free()

	for ch in channels:
		var row := ChannelRowScene.instantiate()
		_channel_list.add_child(row)
		row.setup(
			ch, ch.get("id", "") in _selected_ids,
			_space_id,
		)
		row.toggled.connect(_on_row_toggled)
		row.move_requested.connect(_on_move_channel)
		row.edit_requested.connect(_on_edit_channel)
		row.delete_requested.connect(_on_delete_channel)
		row.permissions_requested.connect(_on_permissions_channel)

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_build_channel_rows(_all_channels)
		return
	var filtered: Array = []
	for ch in _all_channels:
		if ch.get("name", "").to_lower().contains(query):
			filtered.append(ch)
	_build_channel_rows(filtered)

func _on_row_toggled(pressed: bool, ch_id: String) -> void:
	if pressed and ch_id not in _selected_ids:
		_selected_ids.append(ch_id)
	elif not pressed:
		_selected_ids.erase(ch_id)
	_update_bulk_ui()

func _on_select_all(pressed: bool) -> void:
	_selected_ids.clear()
	if pressed:
		for ch in _all_channels:
			_selected_ids.append(ch.get("id", ""))
	for row in _channel_list.get_children():
		var cb := row.get_child(0)
		if cb is CheckBox:
			cb.set_pressed_no_signal(pressed)
	_update_bulk_ui()

func _update_bulk_ui() -> void:
	_bulk_delete_btn.visible = _selected_ids.size() > 0
	if _selected_ids.size() > 0:
		_bulk_delete_btn.text = "Delete Selected (%d)" % _selected_ids.size()

func _on_bulk_delete() -> void:
	var count := _selected_ids.size()
	if count == 0:
		return
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Bulk Delete",
		"Are you sure you want to delete %d channel(s)? This cannot be undone." % count,
		"Delete All",
		true
	)
	dialog.confirmed.connect(func():
		for cid in _selected_ids.duplicate():
			await Client.admin.delete_channel(cid)
		_selected_ids.clear()
		_update_bulk_ui()
	)

func _on_move_channel(ch: Dictionary, direction: int) -> void:
	var idx := -1
	for i in _all_channels.size():
		if _all_channels[i].get("id", "") == ch.get("id", ""):
			idx = i
			break
	if idx == -1:
		return
	var swap_idx := idx + direction
	if swap_idx < 0 or swap_idx >= _all_channels.size():
		return

	# Swap in local array, then send full position list (like drag-and-drop does).
	# Just swapping two positions fails when channels share the same value.
	var tmp: Dictionary = _all_channels[idx]
	_all_channels[idx] = _all_channels[swap_idx]
	_all_channels[swap_idx] = tmp

	var data: Array = []
	for i in _all_channels.size():
		data.append({"id": _all_channels[i].get("id", ""), "position": i})

	# Rebuild rows immediately so the user sees the change
	_build_channel_rows(_all_channels)

	var result: RestResult = await Client.admin.reorder_channels(_space_id, data)
	if result == null or not result.ok:
		var err_msg: String = "Failed to reorder channels"
		if result != null and result.error:
			err_msg = result.error.message
		_show_error(err_msg)
		# Revert on failure — refetch will restore server state
		_rebuild_list()

func _rebuild_parent_options() -> void:
	_create_parent.clear()
	_create_parent.add_item("None", 0)
	var channels: Array = Client.get_channels_for_space(_space_id)
	var idx: int = 1
	for ch in channels:
		if ch.get("type", 0) == ClientModels.ChannelType.CATEGORY:
			_create_parent.add_item(ch.get("name", ""), idx)
			_create_parent.set_item_metadata(idx, ch.get("id", ""))
			idx += 1

func _toggle_create_form() -> void:
	_create_form.visible = not _create_form.visible
	_create_toggle.text = "Cancel" if _create_form.visible else "Create Channel"

func _on_create() -> void:
	var ch_name: String = _create_name.text.strip_edges()
	if ch_name.is_empty():
		_show_error("Channel name cannot be empty.")
		return

	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var type_map := ["text", "voice", "announcement", "forum", "category"]
	var data := {
		"name": ch_name,
		"type": type_map[_create_type.selected],
	}

	var parent_idx: int = _create_parent.selected
	if parent_idx > 0:
		var parent_id = _create_parent.get_item_metadata(parent_idx)
		if parent_id is String and not parent_id.is_empty():
			data["parent_id"] = parent_id

	var result: RestResult = await Client.admin.create_channel(_space_id, data)
	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var err_msg: String = "Failed to create channel"
		if result != null and result.error:
			err_msg = result.error.message
		_show_error(err_msg)
	else:
		_create_name.text = ""
		_create_form.visible = false
		_create_toggle.text = "Create Channel"

func _on_edit_channel(ch: Dictionary) -> void:
	var dialog := ChannelEditScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(ch)

func _on_permissions_channel(ch: Dictionary) -> void:
	var dialog := ChannelPermissionsScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(ch, _space_id)

func _on_delete_channel(ch: Dictionary) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Channel",
		"Are you sure you want to delete #%s? This cannot be undone." % ch.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.admin.delete_channel(ch.get("id", ""))
	)

func _on_channels_updated(space_id: String) -> void:
	if space_id == _space_id:
		_rebuild_list()
		_rebuild_parent_options()

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
