extends ColorRect

const AvatarShader := preload("res://assets/theme/avatar_circle.gdshader")

# Simple in-memory image cache shared across all avatars
const AVATAR_CACHE_CAP := 200
static var _image_cache: Dictionary = {}
static var _cache_access_order: Array[String] = []

@export var avatar_size: int = 32
@export var show_letter: bool = false
@export var letter_font_size: int = 14

var _shader_material: ShaderMaterial
var _texture_rect: TextureRect
var _http: HTTPRequest
var _current_url: String = ""

@onready var letter_label: Label = $LetterLabel

func _ready() -> void:
	custom_minimum_size = Vector2(avatar_size, avatar_size)
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = AvatarShader
	_shader_material.set_shader_parameter("radius", 0.5)
	material = _shader_material
	letter_label.visible = show_letter
	letter_label.add_theme_font_size_override("font_size", letter_font_size)
	_resize_letter_label()

func set_avatar_color(c: Color) -> void:
	color = c
	if not letter_label:
		return
	var luminance: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	var font_color := Color.BLACK if luminance > 0.5 else Color.WHITE
	letter_label.add_theme_color_override("font_color", font_color)

func set_letter(text: String) -> void:
	if not letter_label:
		return
	letter_label.text = text
	letter_label.visible = show_letter and text != ""

func set_avatar_url(url: String) -> void:
	if url == null or url.is_empty():
		return
	_current_url = url

	# Check static cache first
	if _image_cache.has(url):
		_touch_cache(url)
		_apply_texture(_image_cache[url])
		return

	# Defer HTTP fetch until we're in the scene tree
	if not is_inside_tree():
		if not tree_entered.is_connected(_fetch_deferred):
			tree_entered.connect(_fetch_deferred, CONNECT_ONE_SHOT)
		return

	_do_fetch(url)

func _fetch_deferred() -> void:
	if _current_url.is_empty():
		return
	# Re-check cache in case it was populated while waiting
	if _image_cache.has(_current_url):
		_touch_cache(_current_url)
		_apply_texture(_image_cache[_current_url])
		return
	_do_fetch(_current_url)

func _do_fetch(url: String) -> void:
	if _http != null:
		_http.cancel_request()
	else:
		_http = HTTPRequest.new()
		_http.request_completed.connect(_on_image_loaded)
		add_child(_http)
	_http.request(url)

func _on_image_loaded(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		return
	var tex := ImageTexture.create_from_image(image)
	_image_cache[_current_url] = tex
	_touch_cache(_current_url)
	_evict_cache()
	_apply_texture(tex)

func _apply_texture(tex: ImageTexture) -> void:
	if _texture_rect == null:
		_texture_rect = TextureRect.new()
		_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Apply same circle shader
		var mat := ShaderMaterial.new()
		mat.shader = AvatarShader
		mat.set_shader_parameter("radius", 0.5)
		_texture_rect.material = mat
		add_child(_texture_rect)
		# Keep letter label on top
		move_child(letter_label, get_child_count() - 1)
	_texture_rect.texture = tex
	# Make background transparent so avatar image transparency is preserved
	color = Color.TRANSPARENT
	letter_label.visible = false
	# Preserve ring state on the new material
	var ring_val = _shader_material.get_shader_parameter("ring_opacity")
	var current_ring: float = ring_val if ring_val != null else 0.0
	if current_ring > 0.0 and _texture_rect.material is ShaderMaterial:
		_texture_rect.material.set_shader_parameter("ring_opacity", current_ring)

func set_radius(value: float) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("radius", value)
	if _texture_rect and _texture_rect.material is ShaderMaterial:
		_texture_rect.material.set_shader_parameter("radius", value)

func tween_radius(from: float, to: float, duration: float = 0.15) -> Tween:
	if _shader_material:
		if Config.get_reduced_motion():
			set_radius(to)
			return null
		var tw := create_tween()
		tw.tween_method(set_radius, from, to, duration)
		return tw
	return null

func set_ring_opacity(value: float) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("ring_opacity", value)
	if _texture_rect and _texture_rect.material is ShaderMaterial:
		_texture_rect.material.set_shader_parameter("ring_opacity", value)

func tween_ring(from: float, to: float, duration: float = 0.15) -> Tween:
	if _shader_material:
		if Config.get_reduced_motion():
			set_ring_opacity(to)
			return null
		var tw := create_tween()
		tw.tween_method(set_ring_opacity, from, to, duration)
		return tw
	return null

func set_speaking(is_speaking: bool) -> void:
	if is_speaking:
		tween_ring(0.0, 1.0, 0.15)
	else:
		tween_ring(1.0, 0.0, 0.15)

func _resize_letter_label() -> void:
	letter_label.offset_right = avatar_size
	letter_label.offset_bottom = avatar_size

static func _touch_cache(url: String) -> void:
	var idx := _cache_access_order.find(url)
	if idx != -1:
		_cache_access_order.remove_at(idx)
	_cache_access_order.append(url)

static func _evict_cache() -> void:
	while _image_cache.size() > AVATAR_CACHE_CAP and _cache_access_order.size() > 0:
		var oldest: String = _cache_access_order[0]
		_cache_access_order.remove_at(0)
		_image_cache.erase(oldest)
