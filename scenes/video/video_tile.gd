extends PanelContainer

var _track
var _texture: ImageTexture
var _is_live := false

@onready var video_rect: TextureRect = $VBox/VideoRect
@onready var name_label: Label = $VBox/NameBar/NameLabel
@onready var mute_label: Label = $VBox/NameBar/MuteLabel
@onready var initials_label: Label = $VBox/InitialsLabel

func setup_local(
	track, user: Dictionary,
) -> void:
	_track = track
	_is_live = true
	name_label.text = user.get(
		"display_name", "You"
	)
	mute_label.visible = false
	initials_label.visible = false
	video_rect.visible = true
	# Attach video sink if method exists
	if _track.has_method("attach_video_sink"):
		_track.attach_video_sink()

func setup_placeholder(
	user: Dictionary, voice_state: Dictionary,
) -> void:
	_is_live = false
	_track = null
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

func _process(_delta: float) -> void:
	if not _is_live or _track == null:
		return
	if not _track.has_video_frame():
		return
	var frame: Image = _track.get_video_frame()
	if frame == null:
		return
	if _texture == null:
		_texture = ImageTexture.create_from_image(frame)
		video_rect.texture = _texture
	else:
		_texture.update(frame)

func _exit_tree() -> void:
	if _track != null and _track.has_method(
		"detach_video_sink"
	):
		_track.detach_video_sink()
	_track = null
	_is_live = false
