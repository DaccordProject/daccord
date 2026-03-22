extends ColorRect

const SWIPE_DISMISS_THRESHOLD := 100.0
const SWIPE_DEAD_ZONE := 10.0

var _swipe_tracking := false
var _swipe_start_y := 0.0
var _swipe_active := false
var _original_y := 0.0

@onready var image_rect: TextureRect = $CenterContainer/VBox/ImageRect
@onready var close_button: Button = $CenterContainer/VBox/ButtonRow/CloseButton
@onready var _center: CenterContainer = $CenterContainer

func _ready() -> void:
	close_button.pressed.connect(_close)
	gui_input.connect(_on_backdrop_input)
	AppState.nav_history.push(&"lightbox")

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
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close()

	# Touch: swipe-down-to-dismiss
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_tracking = true
			_swipe_start_y = event.position.y
			_swipe_active = false
			_original_y = _center.position.y
		elif not event.pressed:
			if _swipe_active:
				var disp: float = event.position.y - _swipe_start_y
				if absf(disp) >= SWIPE_DISMISS_THRESHOLD:
					_animate_dismiss(disp > 0.0)
				else:
					_snap_back()
			elif _swipe_tracking:
				# Simple tap — close
				_close()
			_swipe_tracking = false
			_swipe_active = false
	elif event is InputEventScreenDrag and _swipe_tracking:
		var disp: float = event.position.y - _swipe_start_y
		if not _swipe_active and absf(disp) >= SWIPE_DEAD_ZONE:
			_swipe_active = true
		if _swipe_active:
			_center.position.y = _original_y + disp
			# Fade backdrop as image moves away from center
			var vp_h: float = get_viewport().get_visible_rect().size.y
			var progress: float = clampf(
				absf(disp) / (vp_h * 0.4), 0.0, 1.0
			)
			modulate.a = 1.0 - (progress * 0.5)
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _animate_dismiss(downward: bool) -> void:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var target_y: float = vp_h if downward else -vp_h
	if Config.get_reduced_motion():
		_close()
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(
		_center, "position:y", target_y, 0.15
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(_close)

func _snap_back() -> void:
	if Config.get_reduced_motion():
		_center.position.y = _original_y
		modulate.a = 1.0
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(
		_center, "position:y", _original_y, 0.15
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)

func _close() -> void:
	AppState.nav_history.remove(&"lightbox")
	queue_free()
