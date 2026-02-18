extends PanelContainer

signal clicked(channel_id: String, message_id: String)

var _channel_id: String = ""
var _message_id: String = ""
var _hover_style: StyleBoxFlat
var _normal_style: StyleBoxFlat

@onready var channel_label: Label = $VBox/ChannelRow/ChannelLabel
@onready var timestamp_label: Label = $VBox/ChannelRow/TimestampLabel
@onready var author_label: Label = $VBox/AuthorLabel
@onready var content_label: Label = $VBox/ContentLabel


func _ready() -> void:
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0, 0, 0, 0)
	_normal_style.content_margin_left = 8.0
	_normal_style.content_margin_right = 8.0
	_normal_style.content_margin_top = 6.0
	_normal_style.content_margin_bottom = 6.0
	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = Color(0.24, 0.25, 0.27)
	_hover_style.content_margin_left = 8.0
	_hover_style.content_margin_right = 8.0
	_hover_style.content_margin_top = 6.0
	_hover_style.content_margin_bottom = 6.0
	_hover_style.corner_radius_top_left = 4
	_hover_style.corner_radius_top_right = 4
	_hover_style.corner_radius_bottom_left = 4
	_hover_style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", _normal_style)

	channel_label.add_theme_font_size_override("font_size", 11)
	channel_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	timestamp_label.add_theme_font_size_override("font_size", 10)
	timestamp_label.add_theme_color_override(
		"font_color", Color(0.44, 0.46, 0.50)
	)
	author_label.add_theme_font_size_override("font_size", 13)
	content_label.add_theme_font_size_override("font_size", 13)
	content_label.add_theme_color_override(
		"font_color", Color(0.78, 0.80, 0.83)
	)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func setup(data: Dictionary) -> void:
	_channel_id = data.get("channel_id", "")
	_message_id = data.get("id", "")

	var ch_name: String = data.get("channel_name", "")
	channel_label.text = "#" + ch_name if not ch_name.is_empty() else "#unknown"
	timestamp_label.text = data.get("timestamp", "")

	var author: Dictionary = data.get("author", {})
	author_label.text = author.get("display_name", "Unknown")
	var color: Color = author.get("color", Color.WHITE)
	author_label.add_theme_color_override("font_color", color)

	var content: String = data.get("content", "")
	if content.length() > 120:
		content = content.substr(0, 120) + "..."
	content_label.text = content


func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", _hover_style)


func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", _normal_style)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(_channel_id, _message_id)
