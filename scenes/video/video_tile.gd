extends PanelContainer

var _stream  # LiveKitVideoStream
var _is_live := false
var _user_id: String = ""
var _speaking_style: StyleBoxFlat

@onready var video_rect: TextureRect = $VBox/VideoRect
@onready var name_label: Label = $VBox/NameBar/NameLabel
@onready var mute_label: Label = $VBox/NameBar/MuteLabel
@onready var initials_label: Label = $VBox/InitialsLabel

func _ready() -> void:
	AppState.speaking_changed.connect(_on_speaking_changed)
	gui_input.connect(_on_gui_input)

func setup_local(
	stream, user: Dictionary,
) -> void:
	_stream = stream
	_is_live = true
	_user_id = user.get("id", "")
	name_label.text = user.get(
		"display_name", "You"
	)
	mute_label.visible = false
	initials_label.visible = false
	video_rect.visible = true

func setup_placeholder(
	user: Dictionary, voice_state: Dictionary,
) -> void:
	_is_live = false
	_stream = null
	_user_id = user.get("id", "")
	var dn: String = user.get("display_name", "?")
	name_label.text = dn
	# Show initials
	var initials := ""
	var parts: PackedStringArray = dn.split(" ")
	for part in parts:
		if not part.is_empty():
			initials += part[0].to_upper()
		if initials.length() >= 2:
			break
	if initials.is_empty():
		initials = "?"
	initials_label.text = initials
	initials_label.visible = true
	video_rect.visible = false
	# Mute indicator
	var is_muted: bool = voice_state.get("self_mute", false)
	mute_label.visible = is_muted

func _on_speaking_changed(user_id: String, is_speaking: bool) -> void:
	if user_id != _user_id or _user_id.is_empty():
		return
	if is_speaking:
		if _speaking_style == null:
			_speaking_style = StyleBoxFlat.new()
			_speaking_style.bg_color = Color(0, 0, 0, 0)
			_speaking_style.border_color = Color(0.231, 0.647, 0.365)
			_speaking_style.set_border_width_all(2)
			_speaking_style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", _speaking_style)
	else:
		remove_theme_stylebox_override("panel")

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		if _user_id.is_empty():
			return
		if AppState.spotlight_user_id == _user_id:
			AppState.clear_spotlight()
		else:
			AppState.set_spotlight(_user_id)

func _process(_delta: float) -> void:
	if not _is_live or _stream == null:
		return
	_stream.poll()
	var tex: ImageTexture = _stream.get_texture()
	if tex != null:
		video_rect.texture = tex

func _exit_tree() -> void:
	if _stream != null and _stream.has_method("close"):
		_stream.close()
	_stream = null
	_is_live = false
