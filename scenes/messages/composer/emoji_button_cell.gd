extends Button

signal emoji_selected(emoji_name: String)

var _emoji_name: String = ""

func setup(data: Dictionary) -> void:
	_emoji_name = data.get("name", "")
	var tex: Texture2D = EmojiData.TEXTURES.get(_emoji_name)
	if tex:
		icon = tex
	tooltip_text = _emoji_name.replace("_", " ")
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	emoji_selected.emit(_emoji_name)
