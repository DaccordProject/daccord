extends ModalBase

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
	_setup_modal(tr("Transfer Ownership"), 440.0, 450.0, true, 20.0)

	# Override title font size to match original
	if _modal_title_label:
		_modal_title_label.add_theme_font_size_override("font_size", 18)

	# Search
	var search_label := Label.new()
	search_label.text = tr("SEARCH MEMBERS")
	search_label.add_theme_font_size_override("font_size", 11)
	search_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	content_container.add_child(search_label)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = tr("Filter by username...")
	_search_input.text_changed.connect(
		func(_t: String) -> void: _render_members()
	)
	content_container.add_child(_search_input)

	# Error
	_error_label = Label.new()
	_error_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("error")
	)
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.visible = false
	content_container.add_child(_error_label)

	# Member list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(scroll)

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
	loading.text = tr("Loading members...")
	loading.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
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
		letter_rect.color = ThemeManager.get_color("accent")
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
			tr("Transfer")
		)
		transfer_btn.pressed.connect(
			_on_transfer.bind(uid, uname)
		)
		row.add_child(transfer_btn)

		_member_list.add_child(row)

	if _member_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = tr("No members found.")
		empty.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_member_list.add_child(empty)

func _on_transfer(user_id: String, uname: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("Transfer Ownership"),
		tr("Transfer ownership of '%s' to %s?") % [
			_space_name, uname
		],
		tr("Transfer"),
		true
	)
	dialog.confirmed.connect(func() -> void:
		_error_label.visible = false
		var result: RestResult = await Client.admin.admin_update_space(
			_space_id, {"owner_id": user_id}
		)
		if result == null or not result.ok:
			var msg := tr("Failed to transfer ownership")
			if result != null and result.error:
				msg = result.error.message
			_error_label.text = msg
			_error_label.visible = true
		else:
			queue_free()
	)

static func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
