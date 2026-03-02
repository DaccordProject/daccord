extends VBoxContainer

signal back_pressed()
signal join_pressed(server_url: String, space_id: String)

var _data: Dictionary = {}

@onready var _back_button: Button = $Header/BackButton
@onready var _banner: TextureRect = $BannerContainer/Banner
@onready var _banner_container: PanelContainer = $BannerContainer
@onready var _icon: TextureRect = $SpaceInfo/Icon
@onready var _name_label: Label = $SpaceInfo/Info/NameLabel
@onready var _member_label: Label = $SpaceInfo/Info/MemberLabel
@onready var _desc_label: Label = $DescLabel
@onready var _tag_label: Label = $Details/TagRow/TagValue
@onready var _server_label: Label = $Details/ServerRow/ServerValue
@onready var _join_button: Button = $JoinButton
@onready var _status_label: Label = $StatusLabel

func _ready() -> void:
	add_to_group("themed")
	_back_button.pressed.connect(func(): back_pressed.emit())
	_join_button.pressed.connect(_on_join_pressed)
	_apply_style()

func _apply_theme() -> void:
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
		_desc_label.text = "No description available."
		_desc_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	else:
		_desc_label.text = desc

	var tags: Array = data.get("tags", [])
	if tags.is_empty():
		_tag_label.text = "None"
		_tag_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	else:
		var tag_strings := PackedStringArray()
		for tag in tags:
			tag_strings.append(str(tag))
		_tag_label.text = ", ".join(tag_strings)

	var server_url: String = data.get("server_url", "")
	_server_label.text = server_url.replace("https://", "").replace("http://", "")

	# Load banner
	var banner_url: String = data.get("banner_url", "")
	if banner_url.is_empty():
		_banner_container.visible = false
	else:
		_load_image(banner_url, _banner)

	# Load icon
	var icon_url: String = data.get("icon_url", "")
	if not icon_url.is_empty():
		_load_image(icon_url, _icon)

func _apply_style() -> void:
	# Join button
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = ThemeManager.get_color("accent")
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left = 24.0
	btn_style.content_margin_right = 24.0
	btn_style.content_margin_top = 10.0
	btn_style.content_margin_bottom = 10.0
	_join_button.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = ThemeManager.get_color("accent_hover")
	_join_button.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = ThemeManager.get_color("accent_pressed")
	_join_button.add_theme_stylebox_override("pressed", btn_pressed)

	_join_button.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
	_join_button.add_theme_color_override("font_hover_color", ThemeManager.get_color("text_white"))
	_join_button.add_theme_color_override("font_pressed_color", ThemeManager.get_color("text_white"))

	# Back button
	_back_button.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	_back_button.add_theme_color_override("font_hover_color", ThemeManager.get_color("text_body"))

func _on_join_pressed() -> void:
	var server_url: String = _data.get("server_url", "")
	var space_id: String = _data.get("id", "")
	if server_url.is_empty() or space_id.is_empty():
		_status_label.text = "Missing server information"
		_status_label.visible = true
		return
	_join_button.disabled = true
	_join_button.text = "Joining..."
	join_pressed.emit(server_url, space_id)

func show_error(msg: String) -> void:
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", ThemeManager.get_color("error"))
	_status_label.visible = true
	_join_button.disabled = false
	_join_button.text = "Join Server"

func _load_image(url: String, target: TextureRect) -> void:
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
	if is_instance_valid(target):
		target.texture = tex
