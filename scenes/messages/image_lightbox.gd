extends ColorRect

@onready var image_rect: TextureRect = $CenterContainer/VBox/ImageRect
@onready var close_button: Button = $CenterContainer/VBox/ButtonRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(_close)
	gui_input.connect(_on_backdrop_input)

func show_image(texture: ImageTexture) -> void:
	image_rect.texture = texture
	# Scale to fit viewport with padding
	var vp_size := get_viewport().get_visible_rect().size
	var max_w: float = vp_size.x * 0.85
	var max_h: float = vp_size.y * 0.75
	var img_w: float = texture.get_width()
	var img_h: float = texture.get_height()
	if img_w > max_w or img_h > max_h:
		var scale_factor: float = minf(max_w / img_w, max_h / img_h)
		img_w = img_w * scale_factor
		img_h = img_h * scale_factor
	image_rect.custom_minimum_size = Vector2(img_w, img_h)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	queue_free()
