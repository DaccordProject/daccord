extends HBoxContainer

signal context_menu_requested(pos: Vector2i, msg_data: Dictionary)

var is_collapsed: bool = true
var _message_data: Dictionary = {}
var _long_press: LongPressDetector
var _is_hovered: bool = false

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
	gui_input.connect(_on_gui_input)
	# Long-press for touch
	_long_press = LongPressDetector.new(self, _emit_context_menu)
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
	var my_id: String = Client.current_user.get("id", "")
	var my_roles: Array = _get_current_user_roles()
	if ClientModels.is_user_mentioned(data, my_id, my_roles):
		modulate = Color(1.0, 0.95, 0.85)

func update_data(data: Dictionary) -> void:
	_message_data = data
	message_content.update_content(data)

func _get_current_user_roles() -> Array:
	var guild_id: String = Client._channel_to_guild.get(
		AppState.current_channel_id, ""
	)
	if guild_id.is_empty():
		return []
	var my_id: String = Client.current_user.get("id", "")
	for member in Client.get_members_for_guild(guild_id):
		if member.get("id", "") == my_id:
			return member.get("roles", [])
	return []

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
		_emit_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _emit_context_menu(pos: Vector2i) -> void:
	context_menu_requested.emit(pos, _message_data)

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

func _draw() -> void:
	if _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.25, 0.27, 0.3))
