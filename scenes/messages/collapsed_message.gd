extends HBoxContainer

var _message_data: Dictionary = {}
var _context_menu: PopupMenu
var _long_press: LongPressDetector

@onready var timestamp_label: Label = $TimestampSpacer/TimestampLabel
@onready var message_content: VBoxContainer = $MessageContent

func _ready() -> void:
	timestamp_label.add_theme_font_size_override("font_size", 9)
	timestamp_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	timestamp_label.visible = false
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# Context menu
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Reply", 0)
	_context_menu.add_item("Edit", 1)
	_context_menu.add_item("Delete", 2)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	gui_input.connect(_on_gui_input)
	# Long-press for touch
	_long_press = LongPressDetector.new(self, _show_context_menu)
	# Listen for layout changes to show timestamps in compact mode
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	_apply_timestamp_visibility(AppState.current_layout_mode)

func setup(data: Dictionary) -> void:
	_message_data = data
	# Extract short time from "Today at 10:31 AM" -> "10:31"
	var ts: String = data.get("timestamp", "")
	var parts := ts.split(" ")
	if parts.size() >= 3:
		timestamp_label.text = parts[2]
	else:
		timestamp_label.text = ts
	message_content.setup(data)

	# Mention highlight
	var content: String = data.get("content", "")
	var current_user_name: String = Client.current_user.get("display_name", "")
	if content.contains("@" + current_user_name):
		modulate = Color(1.0, 0.95, 0.85)

func _on_mouse_entered() -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		timestamp_label.visible = true

func _on_mouse_exited() -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		timestamp_label.visible = false

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_timestamp_visibility(mode)

func _apply_timestamp_visibility(mode: AppState.LayoutMode) -> void:
	if mode == AppState.LayoutMode.COMPACT:
		timestamp_label.visible = true
	else:
		timestamp_label.visible = false

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	var author: Dictionary = _message_data.get("author", {})
	var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
	_context_menu.set_item_disabled(1, not is_own)
	_context_menu.set_item_disabled(2, not is_own)
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Reply
			AppState.initiate_reply(_message_data.get("id", ""))
		1: # Edit
			message_content.enter_edit_mode(_message_data.get("id", ""), _message_data.get("content", ""))
		2: # Delete
			AppState.delete_message(_message_data.get("id", ""))
