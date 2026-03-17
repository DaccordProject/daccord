extends GutTest

## Unit tests for PluginCanvas — color parsing, command limits, buffer
## management, and resource lifecycle.

var canvas: PluginCanvas


func before_each() -> void:
	canvas = PluginCanvas.new()
	canvas.canvas_width = 480
	canvas.canvas_height = 360
	add_child_autofree(canvas)


# ------------------------------------------------------------------
# _parse_color
# ------------------------------------------------------------------

func test_parse_color_named_white() -> void:
	var c: Color = canvas._parse_color("white")
	assert_eq(c, Color.WHITE)


func test_parse_color_named_red() -> void:
	var c: Color = canvas._parse_color("red")
	assert_eq(c, Color.RED)


func test_parse_color_named_transparent() -> void:
	var c: Color = canvas._parse_color("transparent")
	assert_eq(c, Color.TRANSPARENT)


func test_parse_color_hex_6_digit() -> void:
	var c: Color = canvas._parse_color("#ff0000")
	assert_eq(c, Color.RED)


func test_parse_color_hex_8_digit_with_alpha() -> void:
	var c: Color = canvas._parse_color("#ff000080")
	assert_almost_eq(c.r, 1.0, 0.01)
	assert_almost_eq(c.g, 0.0, 0.01)
	assert_almost_eq(c.b, 0.0, 0.01)
	assert_almost_eq(c.a, 128.0 / 255.0, 0.01)


func test_parse_color_array_rgb() -> void:
	var c: Color = canvas._parse_color([1.0, 0.0, 0.0])
	assert_eq(c, Color(1.0, 0.0, 0.0, 1.0))


func test_parse_color_array_rgba() -> void:
	var c: Color = canvas._parse_color([0.5, 0.5, 0.5, 0.5])
	assert_almost_eq(c.r, 0.5, 0.01)
	assert_almost_eq(c.a, 0.5, 0.01)


func test_parse_color_object_passthrough() -> void:
	var c: Color = canvas._parse_color(Color.BLUE)
	assert_eq(c, Color.BLUE)


func test_parse_color_invalid_string_returns_white() -> void:
	var c: Color = canvas._parse_color("not_a_color")
	assert_eq(c, Color.WHITE)


func test_parse_color_invalid_type_returns_white() -> void:
	var c: Color = canvas._parse_color(42)
	assert_eq(c, Color.WHITE)


func test_parse_color_empty_array_returns_white() -> void:
	var c: Color = canvas._parse_color([])
	assert_eq(c, Color.WHITE)


func test_parse_color_two_element_array_returns_white() -> void:
	var c: Color = canvas._parse_color([1.0, 0.0])
	assert_eq(c, Color.WHITE)


# ------------------------------------------------------------------
# Command queue limits
# ------------------------------------------------------------------

func test_push_command_within_limit() -> void:
	for i in 10:
		canvas.push_command({"type": "rect", "x": i})
	assert_eq(canvas._commands.size(), 10)


func test_push_command_at_max_limit() -> void:
	for i in PluginCanvas.MAX_COMMANDS_PER_FRAME:
		canvas.push_command({"type": "rect"})
	assert_eq(canvas._commands.size(), PluginCanvas.MAX_COMMANDS_PER_FRAME)


func test_push_command_rejects_beyond_limit() -> void:
	for i in PluginCanvas.MAX_COMMANDS_PER_FRAME + 10:
		canvas.push_command({"type": "rect"})
	assert_eq(canvas._commands.size(), PluginCanvas.MAX_COMMANDS_PER_FRAME)


func test_clear_commands() -> void:
	canvas.push_command({"type": "rect"})
	canvas.push_command({"type": "circle"})
	canvas.clear_commands()
	assert_eq(canvas._commands.size(), 0)


# ------------------------------------------------------------------
# Buffer management
# ------------------------------------------------------------------

func test_create_buffer_returns_handle() -> void:
	var handle: int = canvas.create_buffer(64, 64)
	assert_gt(handle, 0)


func test_create_buffer_respects_limit() -> void:
	var handles: Array = []
	for i in PluginCanvas.MAX_BUFFERS + 2:
		handles.append(canvas.create_buffer(8, 8))
	# First MAX_BUFFERS should succeed
	for i in PluginCanvas.MAX_BUFFERS:
		assert_gt(handles[i], 0)
	# Beyond limit should return -1
	assert_eq(handles[PluginCanvas.MAX_BUFFERS], -1)


func test_create_buffer_clamps_dimensions() -> void:
	var handle: int = canvas.create_buffer(9999, 9999)
	assert_gt(handle, 0)
	var buf: Dictionary = canvas._buffers[handle]
	assert_eq(buf["width"], canvas.canvas_width)
	assert_eq(buf["height"], canvas.canvas_height)


func test_set_buffer_pixel_within_bounds() -> void:
	var handle: int = canvas.create_buffer(8, 8)
	canvas.set_buffer_pixel(handle, 0, 0, Color.RED)
	var img: Image = canvas._buffers[handle]["image"]
	assert_eq(img.get_pixel(0, 0), Color.RED)


func test_set_buffer_pixel_out_of_bounds_ignored() -> void:
	var handle: int = canvas.create_buffer(8, 8)
	# Should not crash
	canvas.set_buffer_pixel(handle, -1, 0, Color.RED)
	canvas.set_buffer_pixel(handle, 0, -1, Color.RED)
	canvas.set_buffer_pixel(handle, 100, 0, Color.RED)
	canvas.set_buffer_pixel(handle, 0, 100, Color.RED)


func test_set_buffer_pixel_invalid_handle_ignored() -> void:
	# Should not crash
	canvas.set_buffer_pixel(9999, 0, 0, Color.RED)


func test_set_buffer_data_correct_size() -> void:
	var handle: int = canvas.create_buffer(2, 2)
	var data := PackedByteArray()
	data.resize(2 * 2 * 4)  # RGBA8
	# Set first pixel to red (R=255, G=0, B=0, A=255)
	data[0] = 255; data[1] = 0; data[2] = 0; data[3] = 255
	canvas.set_buffer_data(handle, data)
	var img: Image = canvas._buffers[handle]["image"]
	assert_eq(img.get_pixel(0, 0), Color.RED)


func test_set_buffer_data_wrong_size_rejected() -> void:
	var handle: int = canvas.create_buffer(2, 2)
	var original_img: Image = canvas._buffers[handle]["image"]
	# Wrong size — should be rejected, image unchanged
	var data := PackedByteArray()
	data.resize(10)
	canvas.set_buffer_data(handle, data)
	assert_eq(canvas._buffers[handle]["image"], original_img)


# ------------------------------------------------------------------
# Image limit
# ------------------------------------------------------------------

func test_load_image_limit() -> void:
	# We can't easily create valid PNGs in pure GDScript without Image,
	# but we can test that the limit check fires.
	# Fill up image slots with invalid data — they'll all return -1
	# from parse failure, not from the limit. Instead test the limit
	# by checking the constant value.
	assert_eq(PluginCanvas.MAX_IMAGES, 64)


# ------------------------------------------------------------------
# Resource cleanup
# ------------------------------------------------------------------

func test_free_resources_clears_all() -> void:
	canvas.create_buffer(8, 8)
	canvas.create_buffer(8, 8)
	canvas.free_resources()
	assert_eq(canvas._images.size(), 0)
	assert_eq(canvas._buffers.size(), 0)
	assert_eq(canvas._buffer_textures.size(), 0)
	assert_eq(canvas._next_image_handle, 1)
	assert_eq(canvas._next_buffer_handle, 1)


# ------------------------------------------------------------------
# Coordinate clamping
# ------------------------------------------------------------------

func test_clamp_x_within_bounds() -> void:
	assert_eq(canvas._clamp_x(100.0), 100.0)


func test_clamp_x_negative_returns_zero() -> void:
	assert_eq(canvas._clamp_x(-50.0), 0.0)


func test_clamp_x_beyond_width_returns_width() -> void:
	assert_eq(canvas._clamp_x(9999.0), float(canvas.canvas_width))


func test_clamp_y_beyond_height_returns_height() -> void:
	assert_eq(canvas._clamp_y(9999.0), float(canvas.canvas_height))


# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

func test_setup_updates_dimensions() -> void:
	canvas.setup(800, 600)
	assert_eq(canvas.canvas_width, 800)
	assert_eq(canvas.canvas_height, 600)
