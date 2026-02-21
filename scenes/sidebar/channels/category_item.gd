extends VBoxContainer

signal channel_pressed(channel_id: String)

const CHEVRON_DOWN := preload("res://assets/theme/icons/chevron_down.svg")
const CHEVRON_RIGHT := preload("res://assets/theme/icons/chevron_right.svg")
const PLUS_ICON := preload("res://assets/theme/icons/plus.svg")
const DRAG_HANDLE_ICON := preload("res://assets/theme/icons/drag_handle.svg")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")
const VoiceChannelItemScene := preload("res://scenes/sidebar/channels/voice_channel_item.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const CreateChannelDialogScene := preload("res://scenes/admin/create_channel_dialog.tscn")
const CategoryEditDialogScene := preload("res://scenes/admin/category_edit_dialog.tscn")

var is_collapsed: bool = false
var guild_id: String = ""
var _category_data: Dictionary = {}
var _context_menu: PopupMenu
var _plus_btn: Button
var _drag_handle: TextureRect
var _count_label: Label
var _drop_above: bool = false
var _drop_hovered: bool = false
var _drop_channel_hover: bool = false

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

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	header.gui_input.connect(_on_header_gui_input)
	header.mouse_entered.connect(_on_header_mouse_entered)
	header.mouse_exited.connect(_on_header_mouse_exited)

func setup(data: Dictionary, child_channels: Array) -> void:
	guild_id = data.get("guild_id", "")
	_category_data = data
	category_name.text = data.get("name", "").to_upper()
	header.tooltip_text = data.get("name", "")

	# Channel count label (shown when collapsed)
	_count_label = Label.new()
	_count_label.text = str(child_channels.size())
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

	# Drag handle and "+" button (only if user has permission)
	if guild_id != "" and Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS):
		_drag_handle = TextureRect.new()
		_drag_handle.texture = DRAG_HANDLE_ICON
		_drag_handle.custom_minimum_size = Vector2(10, 16)
		_drag_handle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_drag_handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_drag_handle.modulate = Color(0.58, 0.608, 0.643)
		_drag_handle.visible = false
		_drag_handle.mouse_filter = Control.MOUSE_FILTER_PASS
		$Header/HBox.add_child(_drag_handle)
		$Header/HBox.move_child(_drag_handle, 0)

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
	if guild_id != "" and cat_id != "":
		Config.set_category_collapsed(guild_id, cat_id, is_collapsed)

func restore_collapse_state() -> void:
	var cat_id: String = _category_data.get("id", "")
	if guild_id == "" or cat_id == "":
		return
	var collapsed: bool = Config.is_category_collapsed(guild_id, cat_id)
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
	if _drag_handle:
		_drag_handle.visible = true
	if _plus_btn:
		_plus_btn.visible = true

func _on_header_mouse_exited() -> void:
	if _drag_handle:
		_drag_handle.visible = false
	if _plus_btn:
		_plus_btn.visible = false

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if guild_id != "" and Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS):
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	_context_menu.add_item("Create Channel", 0)
	_context_menu.add_item("Edit Category", 1)
	_context_menu.add_item("Delete Category", 2)
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
	dialog.setup(guild_id, _category_data.get("id", ""))

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
	if guild_id == "" or not Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS):
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
				_drop_channel_hover = true
				_drop_hovered = true
				queue_redraw()
				accepted = true
		elif drop_type == "category":
			_drop_channel_hover = false
			var source: Control = data.get("source_node")
			var valid_source: bool = (
				source != null
				and source != self
				and source.get_parent() == get_parent()
			)
			if valid_source:
				_drop_above = at_position.y < size.y / 2.0
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
			Client.admin.update_channel(ch_id, {"parent_id": cat_id})
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
			Client.admin.reorder_channels(guild_id, positions)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_indicator()

func _clear_drop_indicator() -> void:
	if _drop_hovered:
		_drop_hovered = false
		_drop_channel_hover = false
		queue_redraw()

func _draw() -> void:
	if not _drop_hovered:
		return
	var line_color := Color(0.34, 0.52, 0.89)
	if _drop_channel_hover:
		# Highlight the header area when a channel is being dropped onto this category
		var header_rect := Rect2(Vector2.ZERO, Vector2(size.x, header.size.y))
		draw_rect(header_rect, Color(line_color, 0.25))
		draw_rect(header_rect, line_color, false, 2.0)
	else:
		if _drop_above:
			draw_line(Vector2(0, 0), Vector2(size.x, 0), line_color, 2.0)
		else:
			draw_line(Vector2(0, size.y), Vector2(size.x, size.y), line_color, 2.0)
