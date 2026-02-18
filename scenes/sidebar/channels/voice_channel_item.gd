extends VBoxContainer

signal channel_pressed(channel_id: String)

const VOICE_ICON := preload("res://theme/icons/voice_channel.svg")
const AvatarScene := preload("res://scenes/common/avatar.tscn")

var channel_id: String = ""
var guild_id: String = ""
var _channel_data: Dictionary = {}

@onready var channel_button: Button = $ChannelButton
@onready var type_icon: TextureRect = $ChannelButton/HBox/TypeIcon
@onready var channel_name: Label = $ChannelButton/HBox/ChannelName
@onready var user_count: Label = $ChannelButton/HBox/UserCount
@onready var participant_container: VBoxContainer = $ParticipantContainer

func _ready() -> void:
	channel_button.pressed.connect(func(): channel_pressed.emit(channel_id))
	AppState.voice_state_updated.connect(_on_voice_state_updated)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	guild_id = data.get("guild_id", "")
	_channel_data = data
	channel_name.text = data.get("name", "")
	channel_button.tooltip_text = data.get("name", "")
	type_icon.texture = VOICE_ICON
	_refresh_participants()

func set_active(_active: bool) -> void:
	# Voice channels don't have a persistent active state like text channels,
	# but we support the interface for polymorphism with channel_item.
	pass

func _on_voice_state_updated(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _on_voice_joined(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _on_voice_left(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _refresh_participants() -> void:
	# Clear old participant items
	for child in participant_container.get_children():
		child.queue_free()

	var voice_users: Array = Client.get_voice_users(channel_id)
	var count: int = voice_users.size()

	# Update count label
	if count > 0:
		user_count.text = str(count)
		user_count.visible = true
	else:
		user_count.visible = false

	# Green tint when we are connected to this channel
	if AppState.voice_channel_id == channel_id:
		type_icon.modulate = Color(0.231, 0.647, 0.365)
		channel_name.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		type_icon.modulate = Color(0.58, 0.608, 0.643)
		channel_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

	# Build participant items
	for vs in voice_users:
		var user: Dictionary = vs.get("user", {})
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 24)

		# Indent spacer
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(28, 0)
		row.add_child(spacer)

		# Avatar
		var av := AvatarScene.instantiate()
		av.avatar_size = 18
		av.show_letter = true
		av.letter_font_size = 9
		av.custom_minimum_size = Vector2(18, 18)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
		av.set_avatar_color(user.get("color", Color(0.345, 0.396, 0.949)))
		var dn: String = user.get("display_name", "?")
		av.set_letter(dn.left(1).to_upper() if not dn.is_empty() else "?")
		var avatar_url = user.get("avatar", null)
		if avatar_url is String and not avatar_url.is_empty():
			av.set_avatar_url(avatar_url)

		# Spacer between avatar and name
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		row.add_child(gap)

		# Username label
		var name_label := Label.new()
		name_label.text = user.get("display_name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.72, 0.73, 0.76))
		row.add_child(name_label)

		# Mute/deaf indicators
		var self_mute: bool = vs.get("self_mute", false)
		var self_deaf: bool = vs.get("self_deaf", false)
		if self_deaf:
			var deaf_label := Label.new()
			deaf_label.text = "D"
			deaf_label.add_theme_font_size_override("font_size", 10)
			deaf_label.add_theme_color_override("font_color", Color(0.929, 0.259, 0.271))
			deaf_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(deaf_label)
		elif self_mute:
			var mute_label := Label.new()
			mute_label.text = "M"
			mute_label.add_theme_font_size_override("font_size", 10)
			mute_label.add_theme_color_override("font_color", Color(0.929, 0.259, 0.271))
			mute_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(mute_label)

		# Video/screen share indicators
		var self_video: bool = vs.get("self_video", false)
		var self_stream: bool = vs.get("self_stream", false)
		if self_video:
			var video_label := Label.new()
			video_label.text = "V"
			video_label.add_theme_font_size_override("font_size", 10)
			video_label.add_theme_color_override("font_color", Color(0.231, 0.647, 0.365))
			video_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(video_label)
		if self_stream:
			var stream_label := Label.new()
			stream_label.text = "S"
			stream_label.add_theme_font_size_override("font_size", 10)
			stream_label.add_theme_color_override("font_color", Color(0.345, 0.396, 0.949))
			stream_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(stream_label)

		participant_container.add_child(row)
