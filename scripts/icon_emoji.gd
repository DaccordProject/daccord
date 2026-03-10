class_name IconEmoji

## Maps UI icon concepts to Twemoji emoji names.
## Use get_texture() to retrieve the Texture2D for a given icon name.

const ICON_MAP := {
	"text_channel": "memo",
	"voice_channel": "headphone",
	"announcement_channel": "megaphone",
	"forum_channel": "speech_balloon",
	"lock": "locked",
	"chevron_down": "down_triangle",
	"chevron_right": "play_button",
	"compass": "compass",
	"delete": "wastebasket",
	"edit": "pencil",
	"bell": "bell",
	"members": "busts_in_silhouette",
	"menu": "clipboard",
	"plus": "heavy_plus_sign",
	"reply": "left_hook_arrow",
	"reply_arrow": "left_hook_arrow",
	"search": "magnifying_glass",
	"send": "airplane",
	"settings": "gear",
	"sidebar_toggle": "clipboard",
	"smile": "grinning_face",
	"thread": "left_speech_bubble",
	"update": "star",
	"chat": "speech_balloon",
}

static func get_texture(icon_name: String) -> Texture2D:
	var emoji_name: String = ICON_MAP.get(icon_name, "")
	if emoji_name.is_empty():
		push_warning("[IconEmoji] Unknown icon: %s" % icon_name)
		return null
	return EmojiData.get_texture(emoji_name)
