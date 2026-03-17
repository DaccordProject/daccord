class_name PluginCanvas
extends Node2D

## Receives a draw command queue from ScriptedRuntime and executes them
## in the _draw() override. All coordinates are clamped to canvas bounds.

const MAX_IMAGES := 64
const MAX_BUFFERS := 4
const MAX_COMMANDS_PER_FRAME := 4096

const _NAMED_COLORS := {
	"white": Color.WHITE,
	"black": Color.BLACK,
	"red": Color.RED,
	"green": Color.GREEN,
	"blue": Color.BLUE,
	"yellow": Color.YELLOW,
	"transparent": Color.TRANSPARENT,
}

var canvas_width: int = 480
var canvas_height: int = 360

# Draw command queue — populated by ScriptedRuntime, consumed in _draw().
var _commands: Array = []

# Loaded images keyed by handle (int).
var _images: Dictionary = {}  # handle -> ImageTexture
var _next_image_handle: int = 1

# Pixel buffers keyed by handle (int).
var _buffers: Dictionary = {}
var _buffer_textures: Dictionary = {}  # handle -> ImageTexture
var _next_buffer_handle: int = 1

# Default font (cached)
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func setup(width: int, height: int) -> void:
	canvas_width = width
	canvas_height = height


## Clears all queued commands.
func clear_commands() -> void:
	_commands.clear()


## Appends a draw command.
func push_command(cmd: Dictionary) -> void:
	if _commands.size() < MAX_COMMANDS_PER_FRAME:
		_commands.append(cmd)


func _draw() -> void:
	draw_rect(
		Rect2(0, 0, canvas_width, canvas_height), Color.BLACK
	)
	for cmd in _commands:
		var type: String = cmd.get("type", "")
		match type:
			"rect":
				_draw_cmd_rect(cmd)
			"circle":
				_draw_cmd_circle(cmd)
			"line":
				_draw_cmd_line(cmd)
			"text":
				_draw_cmd_text(cmd)
			"pixel":
				_draw_cmd_pixel(cmd)
			"image":
				_draw_cmd_image(cmd)
			"image_region":
				_draw_cmd_image_region(cmd)
			"image_scaled":
				_draw_cmd_image_scaled(cmd)
			"buffer":
				_draw_cmd_buffer(cmd)
			"buffer_scaled":
				_draw_cmd_buffer_scaled(cmd)


## Triggers a visual update after populating commands.
func flush() -> void:
	queue_redraw()


# --- Image management ---

## Loads an image from raw PNG/JPEG bytes. Returns handle or -1.
func load_image(data: PackedByteArray) -> int:
	if _images.size() >= MAX_IMAGES:
		push_warning(
			"[PluginCanvas] Image limit reached (%d)" % MAX_IMAGES
		)
		return -1
	var img := Image.new()
	var err: int = img.load_png_from_buffer(data)
	if err != OK:
		err = img.load_jpg_from_buffer(data)
	if err != OK:
		err = img.load_webp_from_buffer(data)
	if err != OK:
		push_warning("[PluginCanvas] Failed to load image")
		return -1
	var tex := ImageTexture.create_from_image(img)
	var handle: int = _next_image_handle
	_next_image_handle += 1
	_images[handle] = tex
	return handle


## Returns the ImageTexture for a handle, or null.
func get_image_texture(handle: int) -> ImageTexture:
	return _images.get(handle)


# --- Buffer management ---

## Creates a pixel buffer. Returns handle or -1.
func create_buffer(width: int, height: int) -> int:
	if _buffers.size() >= MAX_BUFFERS:
		push_warning(
			"[PluginCanvas] Buffer limit reached (%d)" % MAX_BUFFERS
		)
		return -1
	width = clampi(width, 1, canvas_width)
	height = clampi(height, 1, canvas_height)
	var data := PackedByteArray()
	data.resize(width * height * 4)
	data.fill(0)
	var img: Image = Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, data
	)
	var handle: int = _next_buffer_handle
	_next_buffer_handle += 1
	_buffers[handle] = {
		"image": img, "width": width, "height": height,
	}
	_buffer_textures[handle] = ImageTexture.create_from_image(img)
	return handle


## Sets a single pixel in a buffer.
func set_buffer_pixel(
	handle: int, x: int, y: int, color: Color,
) -> void:
	var buf = _buffers.get(handle)
	if buf == null:
		return
	var img: Image = buf["image"]
	if x >= 0 and x < buf["width"] \
			and y >= 0 and y < buf["height"]:
		img.set_pixel(x, y, color)


## Replaces buffer data from PackedByteArray (RGBA8, row-major).
func set_buffer_data(
	handle: int, data: PackedByteArray,
) -> void:
	var buf = _buffers.get(handle)
	if buf == null:
		return
	var expected: int = buf["width"] * buf["height"] * 4
	if data.size() != expected:
		push_warning(
			"[PluginCanvas] Buffer data size mismatch"
		)
		return
	var new_img := Image.create_from_data(
		buf["width"], buf["height"],
		false, Image.FORMAT_RGBA8, data,
	)
	_buffers[handle]["image"] = new_img
	_buffer_textures[handle] = (
		ImageTexture.create_from_image(new_img)
	)


## Updates the GPU texture for a buffer after pixel edits.
func update_buffer_texture(handle: int) -> void:
	var buf = _buffers.get(handle)
	if buf == null:
		return
	_buffer_textures[handle].update(buf["image"])


## Frees all images and buffers.
func free_resources() -> void:
	_images.clear()
	_buffers.clear()
	_buffer_textures.clear()
	_next_image_handle = 1
	_next_buffer_handle = 1


# --- Draw command implementations ---

func _clamp_x(v: float) -> float:
	return clampf(v, 0.0, float(canvas_width))

func _clamp_y(v: float) -> float:
	return clampf(v, 0.0, float(canvas_height))

func _draw_cmd_rect(cmd: Dictionary) -> void:
	var x: float = _clamp_x(cmd.get("x", 0.0))
	var y: float = _clamp_y(cmd.get("y", 0.0))
	var w: float = clampf(
		cmd.get("w", 0.0), 0.0, float(canvas_width) - x
	)
	var h: float = clampf(
		cmd.get("h", 0.0), 0.0, float(canvas_height) - y
	)
	var color: Color = _parse_color(cmd.get("color", "white"))
	var filled: bool = cmd.get("filled", true)
	draw_rect(Rect2(x, y, w, h), color, filled)

func _draw_cmd_circle(cmd: Dictionary) -> void:
	var cx: float = cmd.get("x", 0.0)
	var cy: float = cmd.get("y", 0.0)
	var r: float = maxf(cmd.get("r", 0.0), 0.0)
	var color: Color = _parse_color(cmd.get("color", "white"))
	draw_circle(Vector2(cx, cy), r, color)

func _draw_cmd_line(cmd: Dictionary) -> void:
	var x1: float = cmd.get("x1", 0.0)
	var y1: float = cmd.get("y1", 0.0)
	var x2: float = cmd.get("x2", 0.0)
	var y2: float = cmd.get("y2", 0.0)
	var color: Color = _parse_color(cmd.get("color", "white"))
	var w: float = maxf(cmd.get("width", 1.0), 0.1)
	draw_line(Vector2(x1, y1), Vector2(x2, y2), color, w)

func _draw_cmd_text(cmd: Dictionary) -> void:
	var x: float = cmd.get("x", 0.0)
	var y: float = cmd.get("y", 0.0)
	var text: String = str(cmd.get("text", ""))
	var color: Color = _parse_color(cmd.get("color", "white"))
	var fs: int = clampi(int(cmd.get("font_size", 16)), 4, 128)
	draw_string(
		_font, Vector2(x, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color,
	)

func _draw_cmd_pixel(cmd: Dictionary) -> void:
	var x: float = _clamp_x(cmd.get("x", 0.0))
	var y: float = _clamp_y(cmd.get("y", 0.0))
	var color: Color = _parse_color(cmd.get("color", "white"))
	draw_rect(Rect2(x, y, 1, 1), color)

func _draw_cmd_image(cmd: Dictionary) -> void:
	var handle: int = int(cmd.get("handle", -1))
	var tex: ImageTexture = _images.get(handle)
	if tex == null:
		return
	var x: float = cmd.get("x", 0.0)
	var y: float = cmd.get("y", 0.0)
	draw_texture(tex, Vector2(x, y))

func _draw_cmd_image_region(cmd: Dictionary) -> void:
	var handle: int = int(cmd.get("handle", -1))
	var tex: ImageTexture = _images.get(handle)
	if tex == null:
		return
	var dx: float = cmd.get("x", 0.0)
	var dy: float = cmd.get("y", 0.0)
	var sx: float = cmd.get("sx", 0.0)
	var sy: float = cmd.get("sy", 0.0)
	var sw: float = cmd.get("sw", float(tex.get_width()))
	var sh: float = cmd.get("sh", float(tex.get_height()))
	draw_texture_rect_region(
		tex, Rect2(dx, dy, sw, sh), Rect2(sx, sy, sw, sh),
	)

func _draw_cmd_image_scaled(cmd: Dictionary) -> void:
	var handle: int = int(cmd.get("handle", -1))
	var tex: ImageTexture = _images.get(handle)
	if tex == null:
		return
	var x: float = cmd.get("x", 0.0)
	var y: float = cmd.get("y", 0.0)
	var w: float = cmd.get("w", float(tex.get_width()))
	var h: float = cmd.get("h", float(tex.get_height()))
	draw_texture_rect(tex, Rect2(x, y, w, h), false)

func _draw_cmd_buffer(cmd: Dictionary) -> void:
	var handle: int = int(cmd.get("handle", -1))
	var tex: ImageTexture = _buffer_textures.get(handle)
	if tex == null:
		return
	var x: float = cmd.get("x", 0.0)
	var y: float = cmd.get("y", 0.0)
	draw_texture(tex, Vector2(x, y))

func _draw_cmd_buffer_scaled(cmd: Dictionary) -> void:
	var handle: int = int(cmd.get("handle", -1))
	var tex: ImageTexture = _buffer_textures.get(handle)
	if tex == null:
		return
	var x: float = cmd.get("x", 0.0)
	var y: float = cmd.get("y", 0.0)
	var w: float = cmd.get("w", 0.0)
	var h: float = cmd.get("h", 0.0)
	draw_texture_rect(tex, Rect2(x, y, w, h), false)


# --- Color parsing ---

func _parse_color(value) -> Color:
	if value is Color:
		return value
	if value is String:
		if _NAMED_COLORS.has(value):
			return _NAMED_COLORS[value]
		if Color.html_is_valid(value):
			return Color.html(value)
		return Color.WHITE
	if value is Array and value.size() >= 3:
		var a: float = value[3] if value.size() >= 4 else 1.0
		return Color(
			float(value[0]), float(value[1]),
			float(value[2]), a,
		)
	return Color.WHITE
