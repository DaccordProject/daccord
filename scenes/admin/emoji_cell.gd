extends VBoxContainer

signal delete_requested(emoji: Dictionary)

var _emoji_data: Dictionary = {}

@onready var _placeholder: ColorRect = $Placeholder
@onready var _name_label: Label = $NameLabel
@onready var _delete_btn: Button = $DeleteButton

func _ready() -> void:
	_delete_btn.pressed.connect(func(): delete_requested.emit(_emoji_data))

func setup(emoji: Dictionary, guild_id: String) -> void:
	_emoji_data = emoji
	_name_label.text = ":%s:" % emoji.get("name", "")
	_placeholder.color = Color.from_hsv(
		fmod(emoji.get("name", "").hash() * 0.618, 1.0), 0.6, 0.8
	)

	# Load emoji image from CDN
	var emoji_id: String = emoji.get("id", "")
	if not emoji_id.is_empty():
		var url := Client.admin.get_emoji_url(guild_id, emoji_id, emoji.get("animated", false))
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(
			_result: int, response_code: int,
			_headers: PackedStringArray, body: PackedByteArray):
			http.queue_free()
			if response_code != 200:
				return
			var img := Image.new()
			var err: int = img.load_png_from_buffer(body)
			if err != OK:
				return
			var tex := ImageTexture.create_from_image(img)
			var tex_rect := TextureRect.new()
			tex_rect.texture = tex
			tex_rect.custom_minimum_size = Vector2(32, 32)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			# Replace placeholder with texture
			var idx := get_children().find(_placeholder)
			if idx != -1:
				_placeholder.visible = false
				add_child(tex_rect)
				move_child(tex_rect, idx)
		)
		http.request(url)
