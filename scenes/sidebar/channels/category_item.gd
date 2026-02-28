extends VBoxContainer

signal channel_pressed(channel_id: String)

const CHEVRON_DOWN := preload("res://assets/theme/icons/chevron_down.svg")
const CHEVRON_RIGHT := preload("res://assets/theme/icons/chevron_right.svg")
const PLUS_ICON := preload("res://assets/theme/icons/plus.svg")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")
const VoiceChannelItemScene := preload("res://scenes/sidebar/channels/voice_channel_item.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const CreateChannelDialogScene := preload("res://scenes/admin/create_channel_dialog.tscn")
const CategoryEditDialogScene := preload("res://scenes/admin/category_edit_dialog.tscn")

var is_collapsed: bool = false
var space_id: String = ""
var _category_data: Dictionary = {}
var _context_menu: PopupMenu
var _plus_btn: Button
var _count_label: Label
var _drop_above: bool = false
var _drop_hovered: bool = false
var _drop_channel_hover: bool = false
var _drop_style: StyleBoxFlat

@onready var header: Button = $Header
@onready var chevron: TextureRect = $Header/HBox/Chevron
@onready var category_name: Label = $Header/HBox/CategoryName
@onready var channel_container: VBoxContainer = $ChannelContainer

func _ready() -> void:
	header.pressed.connect(_toggle_collapsed)
	chevron.texture = CHEVRON_DOWN
	chevron.modulate = Color(0.58, 0.608, 0.643)
	category_name.add_theme_font_size_override("font_size", 11)
	category_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

	# Display-only children should not intercept mouse events (especially drag)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	category_name.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Forward _get_drag_data from Header so category drags start from the header.
	# Drop handling (_can_drop_data, _drop_data) is on this VBoxContainer directly;
	# the header is set to MOUSE_FILTER_IGNORE during drags so events reach us.
	header.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)

	# Pre-build the drop highlight style (reused across frames)
	_drop_style = StyleBoxFlat.new()
	_drop_style.bg_color = Color(0.34, 0.52, 0.89, 0.25)
	_drop_style.border_color = Color(0.34, 0.52, 0.89)
	_drop_style.set_border_width_all(2)
	_drop_style.set_corner_radius_all(4)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	header.gui_input.connect(_on_header_gui_input)
	header.mouse_entered.connect(_on_header_mouse_entered)
	header.mouse_exited.connect(_on_header_mouse_exited)

func setup(data: Dictionary, child_channels: Array) -> void:
	space_id = data.get("space_id", "")
	_category_data = data
	category_name.text = data.get("name", "").to_upper()
	header.tooltip_text = data.get("name", "")

	# Channel count label (shown when collapsed)
	_count_label = Label.new()
	_count_label.text = str(child_channels.size())
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.visible = false
	$Header/HBox.add_child(_count_label)

	for ch in child_channels:
		var is_voice: bool = ch.get("type", 0) == ClientModels.ChannelType.VOICE
		var item: Control
		if is_voice:
			item = VoiceChannelItemScene.instantiate()
		else:
			item = ChannelItemScene.instantiate()
		channel_container.add_child(item)
		item.setup(ch)
		item.channel_pressed.connect(func(id: String): channel_pressed.emit(id))

	# "+" button (only if user has permission)
	if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		_plus_btn = Button.new()
		_plus_btn.flat = true
		_plus_btn.visible = false
		_plus_btn.custom_minimum_size = Vector2(16, 16)
		_plus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_plus_btn.icon = PLUS_ICON
		_plus_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_plus_btn.expand_icon = true
		_plus_btn.add_theme_color_override("icon_normal_color", Color(0.58, 0.608, 0.643))
		_plus_btn.add_theme_color_override("icon_hover_color", Color(1, 1, 1))
		_plus_btn.tooltip_text = "Create Channel"
		_plus_btn.pressed.connect(_on_create_channel)
		$Header/HBox.add_child(_plus_btn)

func _toggle_collapsed() -> void:
	is_collapsed = !is_collapsed
	channel_container.visible = !is_collapsed
	chevron.texture = CHEVRON_RIGHT if is_collapsed else CHEVRON_DOWN
	if _count_label:
		_count_label.visible = is_collapsed
	var cat_id: String = _category_data.get("id", "")
	if space_id != "" and cat_id != "":
		Config.set_category_collapsed(space_id, cat_id, is_collapsed)

func restore_collapse_state() -> void:
	var cat_id: String = _category_data.get("id", "")
	if space_id == "" or cat_id == "":
		return
	var collapsed: bool = Config.is_category_collapsed(space_id, cat_id)
	if collapsed:
		is_collapsed = true
		channel_container.visible = false
		chevron.texture = CHEVRON_RIGHT
		if _count_label:
			_count_label.visible = true

func get_channel_items() -> Array:
	var items := []
	for child in channel_container.get_children():
		items.append(child)
	return items

func _on_header_mouse_entered() -> void:
	if _plus_btn:
		_plus_btn.visible = true

func _on_header_mouse_exited() -> void:
	if _plus_btn:
		_plus_btn.visible = false

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	_context_menu.add_item("Create Channel", 0)
	_context_menu.add_item("Edit Category", 1)
	_context_menu.add_item("Delete Category", 2)
	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_create_channel()
		1: _on_edit_category()
		2: _on_delete_category()

func _on_create_channel() -> void:
	var dialog := CreateChannelDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(space_id, _category_data.get("id", ""))

func _on_edit_category() -> void:
	var dialog := CategoryEditDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(_category_data)

func _on_delete_category() -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	var child_count: int = channel_container.get_child_count()
	var msg: String
	var cat_name: String = _category_data.get("name", "")
	if child_count > 0:
		msg = "Are you sure you want to delete \"%s\"?" % cat_name \
			+ " It contains %d channel(s)" % child_count \
			+ " that will become uncategorized." \
			+ " This cannot be undone."
	else:
		msg = "Are you sure you want to delete \"%s\"?" % cat_name \
			+ " This cannot be undone."
	dialog.setup(
		"Delete Category",
		msg,
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.admin.delete_channel(_category_data.get("id", ""))
	)

func get_category_id() -> String:
	return _category_data.get("id", "")

# --- Drag-and-drop reordering ---

func _get_drag_data(_at_position: Vector2) -> Variant:
	if space_id == "" or not Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		return null
	var preview := Label.new()
	preview.text = _category_data.get("name", "").to_upper()
	preview.add_theme_font_size_override("font_size", 11)
	preview.add_theme_color_override("font_color", Color(1, 1, 1))
	set_drag_preview(preview)
	return {"type": "category", "category_data": _category_data, "source_node": self}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var accepted := false
	if data is Dictionary:
		var drop_type: String = data.get("type", "")
		if drop_type == "channel":
			var ch_data: Dictionary = data.get("channel_data", {})
			var cat_id: String = _category_data.get("id", "")
			if ch_data.get("parent_id", "") != cat_id:
				if not _drop_channel_hover:
					header.add_theme_stylebox_override("normal", _drop_style)
				_drop_channel_hover = true
				_drop_hovered = true
				accepted = true
		elif drop_type == "category":
			if _drop_channel_hover:
				header.remove_theme_stylebox_override("normal")
			_drop_channel_hover = false
			var source: Control = data.get("source_node")
			var valid_source: bool = (
				source != null
				and source != self
				and source.get_parent() == get_parent()
			)
			if valid_source:
				_drop_above = at_position.y < header.size.y / 2.0
				_drop_hovered = true
				queue_redraw()
				accepted = true
	if not accepted:
		_clear_drop_indicator()
	return accepted

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_indicator()
	if not data is Dictionary:
		return
	var drop_type: String = data.get("type", "")
	if drop_type == "channel":
		# Move channel into this category
		var ch_data: Dictionary = data.get("channel_data", {})
		var ch_id: String = ch_data.get("id", "")
		var cat_id: String = _category_data.get("id", "")
		if ch_id != "" and cat_id != "":
			_move_channel_to_category(ch_id, cat_id)
		return
	if drop_type == "category":
		var source: Control = data.get("source_node")
		if source == null or source.get_parent() != get_parent():
			return
		var container := get_parent()
		var target_idx: int = get_index()
		if not _drop_above:
			target_idx += 1
		container.move_child(source, target_idx)
		# Build position update array for all categories in the container
		var positions: Array = []
		var pos: int = 0
		for child in container.get_children():
			if child.has_method("get_category_id"):
				var cid: String = child.get_category_id()
				if cid != "":
					positions.append({"id": cid, "position": pos})
					pos += 1
		if positions.size() > 0:
			Client.admin.reorder_channels(space_id, positions)

func _move_channel_to_category(ch_id: String, cat_id: String) -> void:
	var result: RestResult = await Client.admin.update_channel(ch_id, {"parent_id": cat_id})
	if result == null:
		push_warning("[CategoryItem] No connection for channel %s" % ch_id)
	elif not result.ok:
		var err_msg: String = ""
		if result.error != null:
			err_msg = "%s (code=%s, status=%d)" % [
				result.error.message, result.error.code, result.status_code
			]
		else:
			err_msg = "status=%d" % result.status_code
		push_warning("[CategoryItem] Failed to move channel %s to category %s: %s" % [
			ch_id, cat_id, err_msg
		])

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		# Let drops pass through the header and channel container
		# to this VBoxContainer so _can_drop_data/_drop_data fire directly.
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		channel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _plus_btn:
			_plus_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		channel_container.mouse_filter = Control.MOUSE_FILTER_STOP
		if _plus_btn:
			_plus_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_clear_drop_indicator()

func _clear_drop_indicator() -> void:
	if _drop_hovered:
		_drop_hovered = false
		if _drop_channel_hover:
			header.remove_theme_stylebox_override("normal")
		_drop_channel_hover = false
		queue_redraw()

func _draw() -> void:
	if not _drop_hovered:
		return
	if _drop_channel_hover:
		# Channel-on-category indicator is shown via header StyleBox override
		return
	var line_color := Color(0.34, 0.52, 0.89)
	if _drop_above:
		draw_line(Vector2(0, 0), Vector2(size.x, 0), line_color, 2.0)
	else:
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), line_color, 2.0)
