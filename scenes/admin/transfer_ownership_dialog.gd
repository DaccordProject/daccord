extends ColorRect

## Dialog for transferring space ownership to another member.
## Instantiate via script, then call setup(space_id, space_name).

const ConfirmDialogScene := preload(
	"res://scenes/admin/confirm_dialog.tscn"
)

var _space_id: String = ""
var _space_name: String = ""
var _search_input: LineEdit
var _member_list: VBoxContainer
var _error_label: Label
var _members: Array = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 450)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.188, 0.196, 0.212)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Transfer Ownership"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.flat = true
	close_btn.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	close_btn.add_theme_color_override(
		"font_hover_color", Color.WHITE
	)
	close_btn.pressed.connect(queue_free)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Search
	var search_label := Label.new()
	search_label.text = "SEARCH MEMBERS"
	search_label.add_theme_font_size_override("font_size", 11)
	search_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(search_label)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Filter by username..."
	_search_input.text_changed.connect(
		func(_t: String) -> void: _render_members()
	)
	vbox.add_child(_search_input)

	# Error
	_error_label = Label.new()
	_error_label.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.visible = false
	vbox.add_child(_error_label)

	# Member list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_member_list = VBoxContainer.new()
	_member_list.add_theme_constant_override("separation", 4)
	_member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_member_list)

func setup(space_id: String, space_name: String) -> void:
	_space_id = space_id
	_space_name = space_name
	_load_members.call_deferred()

func _load_members() -> void:
	_error_label.visible = false
	_clear_children(_member_list)
	var loading := Label.new()
	loading.text = "Loading members..."
	loading.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_member_list.add_child(loading)

	_members = Client.get_members_for_space(_space_id)
	_clear_children(_member_list)
	_render_members()

func _render_members() -> void:
	_clear_children(_member_list)
	var query: String = _search_input.text.strip_edges().to_lower()

	for member in _members:
		var uname: String = member.get("username", "")
		var uid: String = member.get("id", "")
		if uid.is_empty():
			continue
		if not query.is_empty() \
				and uname.to_lower().find(query) == -1:
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# Letter avatar
		var letter_rect := ColorRect.new()
		letter_rect.custom_minimum_size = Vector2(28, 28)
		letter_rect.color = Color(0.345, 0.396, 0.949)
		var letter_lbl := Label.new()
		letter_lbl.text = (
			uname[0].to_upper() if uname.length() > 0 else "?"
		)
		letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter_rect.add_child(letter_lbl)
		row.add_child(letter_rect)

		var name_lbl := Label.new()
		name_lbl.text = uname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var transfer_btn := SettingsBase.create_action_button(
			"Transfer"
		)
		transfer_btn.pressed.connect(
			_on_transfer.bind(uid, uname)
		)
		row.add_child(transfer_btn)

		_member_list.add_child(row)

	if _member_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "No members found."
		empty.add_theme_color_override(
			"font_color", Color(0.58, 0.608, 0.643)
		)
		_member_list.add_child(empty)

func _on_transfer(user_id: String, uname: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Transfer Ownership",
		"Transfer ownership of '%s' to %s?" % [
			_space_name, uname
		],
		"Transfer",
		true
	)
	dialog.confirmed.connect(func() -> void:
		_error_label.visible = false
		var result: RestResult = await Client.admin.admin_update_space(
			_space_id, {"owner_id": user_id}
		)
		if result == null or not result.ok:
			var msg := "Failed to transfer ownership"
			if result != null and result.error:
				msg = result.error.message
			_error_label.text = msg
			_error_label.visible = true
		else:
			queue_free()
	)

func _clear_children(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
