extends Button

signal emoji_selected(emoji_name: String)

var _emoji_name: String = ""

func setup(data: Dictionary) -> void:
	_emoji_name = data.get("name", "")
	var tone: int = Config.get_emoji_skin_tone()
	var tex: Texture2D = EmojiData.get_texture(_emoji_name, tone)
	if tex:
		icon = tex
	tooltip_text = _emoji_name.replace("_", " ")
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	emoji_selected.emit(_emoji_name)
