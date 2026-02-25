extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const InviteRowScene := preload("res://scenes/admin/invite_row.tscn")

var _space_id: String = ""
var _all_invites: Array = []
var _selected_codes: Array = []

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
@onready var _invite_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/InviteList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _create_toggle: Button = $CenterContainer/Panel/VBox/CreateToggle
@onready var _create_form: VBoxContainer = $CenterContainer/Panel/VBox/CreateForm
@onready var _max_age_option: OptionButton = $CenterContainer/Panel/VBox/CreateForm/MaxAgeOption
@onready var _max_uses_spin: SpinBox = $CenterContainer/Panel/VBox/CreateForm/MaxUsesRow/MaxUsesSpin
@onready var _temporary_check: CheckBox = \
	$CenterContainer/Panel/VBox/CreateForm/TemporaryRow/TemporaryCheck
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/CreateForm/CreateButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

@onready var _bulk_bar: HBoxContainer = $CenterContainer/Panel/VBox/BulkBar
@onready var _select_all_check: CheckBox = $CenterContainer/Panel/VBox/BulkBar/SelectAllCheck
@onready var _bulk_revoke_btn: Button = $CenterContainer/Panel/VBox/BulkBar/BulkRevokeBtn

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_create_toggle.pressed.connect(_toggle_create)
	_create_btn.pressed.connect(_on_create)
	_create_form.visible = false
	_search_input.text_changed.connect(_on_search_changed)
	_select_all_check.toggled.connect(_on_select_all)
	_bulk_revoke_btn.pressed.connect(_on_bulk_revoke)

	_max_age_option.add_item("30 minutes", 0)
	_max_age_option.add_item("1 hour", 1)
	_max_age_option.add_item("6 hours", 2)
	_max_age_option.add_item("12 hours", 3)
	_max_age_option.add_item("1 day", 4)
	_max_age_option.add_item("7 days", 5)
	_max_age_option.add_item("Never", 6)
	_max_age_option.select(4) # Default: 1 day

	_max_uses_spin.min_value = 0
	_max_uses_spin.max_value = 100
	_max_uses_spin.value = 0

	AppState.invites_updated.connect(_on_invites_updated)

func setup(space_id: String) -> void:
	_space_id = space_id
	_load_invites()

func _load_invites() -> void:
	for child in _invite_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_invites.clear()
	_selected_codes.clear()
	_update_bulk_ui()

	var result: RestResult = await Client.admin.get_invites(_space_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load invites"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var invites: Array = result.data if result.data is Array else []
	if invites.is_empty():
		_empty_label.visible = true
		return

	for invite in invites:
		var invite_dict: Dictionary
		if invite is AccordInvite:
			invite_dict = ClientModels.invite_to_dict(invite)
		elif invite is Dictionary:
			invite_dict = invite
		else:
			continue
		_all_invites.append(invite_dict)

	_rebuild_list(_all_invites)
	_bulk_bar.visible = _all_invites.size() > 0

func _rebuild_list(invites: Array) -> void:
	for child in _invite_list.get_children():
		child.queue_free()

	if invites.is_empty():
		_empty_label.visible = _all_invites.is_empty()
		return
	_empty_label.visible = false

	for invite_dict in invites:
		var row := InviteRowScene.instantiate()
		_invite_list.add_child(row)
		row.setup(invite_dict, invite_dict.get("code", "") in _selected_codes)
		row.toggled.connect(_on_row_toggled)
		row.revoke_requested.connect(_on_revoke)

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_rebuild_list(_all_invites)
		return
	var filtered: Array = []
	for invite in _all_invites:
		if invite.get("code", "").to_lower().contains(query):
			filtered.append(invite)
	_rebuild_list(filtered)

func _on_row_toggled(pressed: bool, code: String) -> void:
	if pressed and code not in _selected_codes:
		_selected_codes.append(code)
	elif not pressed:
		_selected_codes.erase(code)
	_update_bulk_ui()

func _on_select_all(pressed: bool) -> void:
	_selected_codes.clear()
	if pressed:
		for invite in _all_invites:
			_selected_codes.append(invite.get("code", ""))
	for row in _invite_list.get_children():
		var cb := row.get_child(0)
		if cb is CheckBox:
			cb.set_pressed_no_signal(pressed)
	_update_bulk_ui()

func _update_bulk_ui() -> void:
	_bulk_revoke_btn.visible = _selected_codes.size() > 0
	if _selected_codes.size() > 0:
		_bulk_revoke_btn.text = "Revoke Selected (%d)" % _selected_codes.size()

func _on_bulk_revoke() -> void:
	var count := _selected_codes.size()
	if count == 0:
		return
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Bulk Revoke",
		"Are you sure you want to revoke %d invite(s)?" % count,
		"Revoke All",
		true
	)
	dialog.confirmed.connect(func():
		var failed := 0
		for code in _selected_codes.duplicate():
			var result: RestResult = await Client.admin.delete_invite(code, _space_id)
			if result == null or not result.ok:
				failed += 1
		_selected_codes.clear()
		_update_bulk_ui()
		if failed > 0:
			_error_label.text = "Failed to revoke %d invite(s)" % failed
			_error_label.visible = true
	)

func _toggle_create() -> void:
	_create_form.visible = not _create_form.visible
	_create_toggle.text = "Cancel" if _create_form.visible else "Create Invite"

func _on_create() -> void:
	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var age_map := [1800, 3600, 21600, 43200, 86400, 604800, 0]
	var data := {
		"max_age": age_map[_max_age_option.selected],
		"max_uses": int(_max_uses_spin.value),
		"temporary": _temporary_check.button_pressed,
	}

	var result: RestResult = await Client.admin.create_invite(_space_id, data)
	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var err_msg: String = "Failed to create invite"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_create_form.visible = false
		_create_toggle.text = "Create Invite"
		_load_invites()

func _on_revoke(code: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Revoke Invite",
		"Are you sure you want to revoke invite '%s'?" % code,
		"Revoke",
		true
	)
	dialog.confirmed.connect(func():
		await Client.admin.delete_invite(code, _space_id)
	)

func _on_invites_updated(space_id: String) -> void:
	if space_id == _space_id:
		_load_invites()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
