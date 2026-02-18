extends Button

signal channel_pressed(channel_id: String)

const TEXT_ICON := preload("res://theme/icons/text_channel.svg")
const VOICE_ICON := preload("res://theme/icons/voice_channel.svg")
const ANNOUNCEMENT_ICON := preload("res://theme/icons/announcement_channel.svg")
const FORUM_ICON := preload("res://theme/icons/forum_channel.svg")

var channel_id: String = ""

@onready var type_icon: TextureRect = $HBox/TypeIcon
@onready var channel_name: Label = $HBox/ChannelName
@onready var unread_dot: ColorRect = $HBox/UnreadDot

func _ready() -> void:
	pressed.connect(func(): channel_pressed.emit(channel_id))

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	channel_name.text = data.get("name", "")
	tooltip_text = data.get("name", "")

	var type: int = data.get("type", ClientModels.ChannelType.TEXT)
	match type:
		ClientModels.ChannelType.TEXT:
			type_icon.texture = TEXT_ICON
		ClientModels.ChannelType.VOICE:
			type_icon.texture = VOICE_ICON
		ClientModels.ChannelType.ANNOUNCEMENT:
			type_icon.texture = ANNOUNCEMENT_ICON
		ClientModels.ChannelType.FORUM:
			type_icon.texture = FORUM_ICON
		_:
			type_icon.texture = TEXT_ICON
	# NSFW indicator - tint icon red
	if data.get("nsfw", false):
		type_icon.modulate = Color(0.9, 0.2, 0.2)
	else:
		type_icon.modulate = Color(0.58, 0.608, 0.643)

	# Voice channel participant count
	var voice_users: int = data.get("voice_users", 0)
	if type == ClientModels.ChannelType.VOICE and voice_users > 0:
		var count_label := Label.new()
		count_label.text = str(voice_users)
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		$HBox.add_child(count_label)
		$HBox.move_child(count_label, $HBox.get_child_count() - 1)

	var has_unread: bool = data.get("unread", false)
	unread_dot.visible = has_unread
	if has_unread:
		channel_name.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		channel_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func set_active(active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.24, 0.25, 0.27)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		add_theme_stylebox_override("normal", style)
		channel_name.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		remove_theme_stylebox_override("normal")
