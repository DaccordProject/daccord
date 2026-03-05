extends PanelContainer

signal card_clicked(space_data: Dictionary)

var _data: Dictionary = {}

@onready var _icon: TextureRect = $Margin/VBox/Header/Icon
@onready var _name_label: Label = $Margin/VBox/Header/Info/TopRow/NameLabel
@onready var _ping_label: Label = $Margin/VBox/Header/Info/TopRow/PingLabel
@onready var _member_label: Label = $Margin/VBox/Header/Info/MemberLabel
@onready var _desc_label: Label = $Margin/VBox/DescLabel
@onready var _tag_container: HFlowContainer = $Margin/VBox/TagContainer

func _ready() -> void:
	add_to_group("themed")
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_style()

func setup(data: Dictionary) -> void:
	_data = data
	_name_label.text = data.get("name", "Unknown Space")
	var member_count: int = data.get("member_count", 0)
	var presence_count: int = data.get("presence_count", 0)
	_member_label.text = "%d members" % member_count
	if presence_count > 0:
		_member_label.text += " · %d online" % presence_count
	_member_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))

	var desc: String = data.get("description", "")
	if desc.is_empty():
		_desc_label.visible = false
	else:
		_desc_label.text = desc
		_desc_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))

	var tags: Array = data.get("tags", [])
	for tag in tags:
		var chip := Label.new()
		chip.text = str(tag)
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = ThemeManager.get_color("secondary_button")
		chip_style.set_corner_radius_all(4)
		chip_style.content_margin_left = 6.0
		chip_style.content_margin_right = 6.0
		chip_style.content_margin_top = 2.0
		chip_style.content_margin_bottom = 2.0
		chip.add_theme_stylebox_override("normal", chip_style)
		_tag_container.add_child(chip)

	# Load icon asynchronously
	var icon_url: String = data.get("icon_url", "")
	if not icon_url.is_empty():
		if icon_url.begins_with("/"):
			var server_url: String = data.get("server_url", "")
			icon_url = server_url.rstrip("/") + icon_url
		_load_icon(icon_url)

func set_ping(ms: int) -> void:
	if ms < 0:
		_ping_label.text = ""
		return
	var bars: String
	var color: Color
	if ms < 100:
		bars = "\u2582\u2584\u2586\u2588"
		color = ThemeManager.get_color("success")
	elif ms < 200:
		bars = "\u2582\u2584\u2586"
		color = ThemeManager.get_color("success")
	elif ms < 400:
		bars = "\u2582\u2584"
		color = ThemeManager.get_color("warning")
	else:
		bars = "\u2582"
		color = ThemeManager.get_color("error")
	_ping_label.text = "%s %dms" % [bars, ms]
	_ping_label.add_theme_color_override("font_color", color)

func _apply_theme() -> void:
	_apply_style()

func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("nav_bg")
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(_data)

func _on_mouse_entered() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("button_hover")
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)

func _on_mouse_exited() -> void:
	_apply_style()

func _load_icon(url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var result: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(self):
		return
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300 or body.is_empty():
		return
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		return
	var tex := ImageTexture.create_from_image(image)
	if is_instance_valid(_icon):
		_icon.texture = tex
