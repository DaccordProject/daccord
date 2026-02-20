extends Button

signal dm_pressed(dm_id: String)
signal dm_closed(dm_id: String)

var dm_id: String = ""
var _dm_data: Dictionary = {}
var _context_menu: PopupMenu

@onready var avatar: ColorRect = $HBox/Avatar
@onready var username_label: Label = $HBox/Info/Username
@onready var last_message_label: Label = $HBox/Info/LastMessage
@onready var unread_dot: ColorRect = $HBox/UnreadDot
@onready var close_btn: Button = $HBox/CloseBtn

func _ready() -> void:
	pressed.connect(func(): dm_pressed.emit(dm_id))
	last_message_label.add_theme_font_size_override("font_size", 12)
	last_message_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	close_btn.visible = false
	close_btn.pressed.connect(_on_close_pressed)
	mouse_entered.connect(func(): close_btn.visible = true)
	mouse_exited.connect(func(): close_btn.visible = false)
	gui_input.connect(_on_gui_input)

func setup(data: Dictionary) -> void:
	dm_id = data.get("id", "")
	_dm_data = data
	var user: Dictionary = data.get("user", {})
	var is_group: bool = data.get("is_group", false)
	var custom_name: String = data.get("name", "")

	# Use custom name if set, otherwise display_name
	if is_group and not custom_name.is_empty():
		username_label.text = custom_name
		tooltip_text = custom_name
	else:
		username_label.text = user.get(
			"display_name", "Unknown"
		)
		tooltip_text = user.get("display_name", "Unknown")

	last_message_label.text = data.get("last_message", "")
	last_message_label.text_overrun_behavior = \
		TextServer.OVERRUN_TRIM_ELLIPSIS

	if is_group:
		# Group DM avatar: use "G" letter with channel color
		avatar.set_avatar_color(
			user.get("color", Color(0.345, 0.396, 0.949))
		)
		avatar.set_letter("G")
	else:
		avatar.set_avatar_color(
			user.get("color", Color(0.345, 0.396, 0.949))
		)
		var dn: String = user.get("display_name", "")
		if dn.length() > 0:
			avatar.set_letter(dn[0].to_upper())
		else:
			avatar.set_letter("")
		var avatar_url = user.get("avatar", null)
		if avatar_url is String and not avatar_url.is_empty():
			avatar.set_avatar_url(avatar_url)
	unread_dot.visible = data.get("unread", false)

func _on_close_pressed() -> void:
	dm_closed.emit(dm_id)

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if not _dm_data.get("is_group", false):
		return
	_show_group_context_menu(mb.global_position)

func _show_group_context_menu(pos: Vector2) -> void:
	if _context_menu != null:
		_context_menu.queue_free()
	_context_menu = PopupMenu.new()
	add_child(_context_menu)

	var my_id: String = Client.current_user.get("id", "")
	var is_owner: bool = _dm_data.get("owner_id", "") == my_id

	if is_owner:
		_context_menu.add_item("Rename Group", 0)
	_context_menu.add_item("Leave Group", 1)

	_context_menu.id_pressed.connect(_on_context_id_pressed)
	_context_menu.popup(Rect2i(
		Vector2i(int(pos.x), int(pos.y)), Vector2i.ZERO
	))

func _on_context_id_pressed(id: int) -> void:
	match id:
		0: _rename_group()
		1: _leave_group()

func _rename_group() -> void:
	# Show a simple rename dialog using AcceptDialog
	var dialog := AcceptDialog.new()
	dialog.title = "Rename Group DM"
	var line := LineEdit.new()
	line.placeholder_text = "New group name"
	line.text = _dm_data.get("name", "")
	dialog.add_child(line)
	dialog.confirmed.connect(func():
		var new_name: String = line.text.strip_edges()
		if not new_name.is_empty():
			Client.rename_group_dm(dm_id, new_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 80))

func _leave_group() -> void:
	var my_id: String = Client.current_user.get("id", "")
	Client.remove_dm_member(dm_id, my_id)

func set_active(active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.24, 0.25, 0.27)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		add_theme_stylebox_override("normal", style)
		username_label.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		remove_theme_stylebox_override("normal")
		username_label.remove_theme_color_override("font_color")
