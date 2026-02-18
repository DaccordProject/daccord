extends Button

var emoji_key: String = ""
var reaction_count: int = 0

@onready var emoji_rect: TextureRect = $HBox/Emoji
@onready var count_label: Label = $HBox/Count

func _ready() -> void:
	count_label.add_theme_font_size_override("font_size", 12)
	_update_active_style()
	toggled.connect(_on_toggled)

func setup(data: Dictionary) -> void:
	emoji_key = data.get("emoji", "")
	reaction_count = data.get("count", 0)
	button_pressed = data.get("active", false)

	if EmojiData.TEXTURES.has(emoji_key):
		emoji_rect.texture = EmojiData.TEXTURES[emoji_key]

	count_label.text = str(reaction_count)
	_update_active_style()

func _on_toggled(pressed: bool) -> void:
	if pressed:
		reaction_count += 1
	else:
		reaction_count = max(0, reaction_count - 1)
	count_label.text = str(reaction_count)
	_update_active_style()

func _update_active_style() -> void:
	if button_pressed:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.345, 0.396, 0.949, 0.3)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.345, 0.396, 0.949)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 6.0
		style.content_margin_top = 4.0
		style.content_margin_right = 6.0
		style.content_margin_bottom = 4.0
		add_theme_stylebox_override("normal", style)
		add_theme_stylebox_override("pressed", style)
