extends HBoxContainer

const ReactionPickerScene := preload("res://scenes/messages/reaction_picker.tscn")

var _message_data: Dictionary = {}
var _context_menu: PopupMenu
var _long_press: LongPressDetector
var _reaction_picker: Control = null
var _is_hovered: bool = false
var _delete_dialog: ConfirmationDialog

@onready var timestamp_label: Label = $TimestampSpacer/TimestampLabel
@onready var message_content: VBoxContainer = $MessageContent

@onready var timestamp_spacer: Control = $TimestampSpacer

func _ready() -> void:
	# Allow mouse events to pass through so hover detection
	# covers the entire message area.
	timestamp_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
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
	_context_menu.add_item("Add Reaction", 3)
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
			AppState.start_editing(_message_data.get("id", ""))
			message_content.enter_edit_mode(_message_data.get("id", ""), _message_data.get("content", ""))
		2: # Delete
			_confirm_delete()
		3: # Add Reaction
			_open_reaction_picker()

func _confirm_delete() -> void:
	if not _delete_dialog:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.dialog_text = "Are you sure you want to delete this message?"
		_delete_dialog.confirmed.connect(func():
			AppState.delete_message(_message_data.get("id", ""))
		)
		add_child(_delete_dialog)
	_delete_dialog.popup_centered()

func _open_reaction_picker() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
	_reaction_picker = ReactionPickerScene.instantiate()
	get_tree().root.add_child(_reaction_picker)
	var channel_id: String = _message_data.get("channel_id", "")
	var msg_id: String = _message_data.get("id", "")
	var pos := get_global_mouse_position()
	_reaction_picker.open(channel_id, msg_id, pos)
	_reaction_picker.closed.connect(func():
		_reaction_picker = null
	)

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

func _draw() -> void:
	if _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.25, 0.27, 0.3))

func _exit_tree() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
