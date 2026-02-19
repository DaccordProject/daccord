extends Button

static var _style_active: StyleBoxFlat
static var _style_inactive: StyleBoxFlat

var emoji_key: String = ""
var reaction_count: int = 0
var channel_id: String = ""
var message_id: String = ""
var _in_setup: bool = false
var _press_tween: Tween

@onready var emoji_rect: TextureRect = $HBox/Emoji
@onready var count_label: Label = $HBox/Count

func _ready() -> void:
	count_label.add_theme_font_size_override("font_size", 12)
	_update_active_style()
	toggled.connect(_on_toggled)
	AppState.reaction_failed.connect(_on_reaction_failed)

func setup(data: Dictionary) -> void:
	_in_setup = true
	emoji_key = data.get("emoji", "")
	reaction_count = data.get("count", 0)
	channel_id = data.get("channel_id", "")
	message_id = data.get("message_id", "")
	button_pressed = data.get("active", false)

	if EmojiData.TEXTURES.has(emoji_key):
		emoji_rect.texture = EmojiData.TEXTURES[emoji_key]
	elif ClientModels.custom_emoji_textures.has(emoji_key):
		emoji_rect.texture = ClientModels.custom_emoji_textures[emoji_key]

	count_label.text = str(reaction_count)
	tooltip_text = ":%s:" % emoji_key
	_update_active_style()
	_in_setup = false

func _on_toggled(toggled_on: bool) -> void:
	if _in_setup:
		return
	# Optimistic local update
	if toggled_on:
		reaction_count += 1
	else:
		reaction_count = max(0, reaction_count - 1)
	count_label.text = str(reaction_count)
	_update_active_style()
	# Bounce animation
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	pivot_offset = size / 2
	scale = Vector2(1.15, 1.15)
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2.ONE, 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Call server API
	if not channel_id.is_empty() and not message_id.is_empty():
		if toggled_on:
			Client.add_reaction(channel_id, message_id, emoji_key)
		else:
			Client.remove_reaction(channel_id, message_id, emoji_key)

func _on_reaction_failed(ch_id: String, msg_id: String, emoji_name: String, _error: String) -> void:
	if ch_id != channel_id or msg_id != message_id or emoji_name != emoji_key:
		return
	# Revert optimistic update
	_in_setup = true
	button_pressed = not button_pressed
	if button_pressed:
		reaction_count += 1
	else:
		reaction_count = max(0, reaction_count - 1)
	count_label.text = str(reaction_count)
	_update_active_style()
	_in_setup = false

static func _ensure_styles() -> void:
	if _style_active != null:
		return
	_style_active = StyleBoxFlat.new()
	_style_active.set_corner_radius_all(8)
	_style_active.content_margin_left = 6.0
	_style_active.content_margin_top = 4.0
	_style_active.content_margin_right = 6.0
	_style_active.content_margin_bottom = 4.0
	_style_active.border_width_left = 1
	_style_active.border_width_top = 1
	_style_active.border_width_right = 1
	_style_active.border_width_bottom = 1
	_style_active.bg_color = Color(0.345, 0.396, 0.949, 0.3)
	_style_active.border_color = Color(0.345, 0.396, 0.949)

	_style_inactive = StyleBoxFlat.new()
	_style_inactive.set_corner_radius_all(8)
	_style_inactive.content_margin_left = 6.0
	_style_inactive.content_margin_top = 4.0
	_style_inactive.content_margin_right = 6.0
	_style_inactive.content_margin_bottom = 4.0
	_style_inactive.border_width_left = 1
	_style_inactive.border_width_top = 1
	_style_inactive.border_width_right = 1
	_style_inactive.border_width_bottom = 1
	_style_inactive.bg_color = Color(0.184, 0.192, 0.212, 1)
	_style_inactive.border_color = Color(0.25, 0.26, 0.28, 1)

func _update_active_style() -> void:
	_ensure_styles()
	var style: StyleBoxFlat = _style_active if button_pressed else _style_inactive
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("pressed", style)
