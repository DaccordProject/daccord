extends GutTest

## Unit tests for LiveKitAdapter.LocalVideoPreview.
##
## Verifies that update_frame() preserves RGBA8 format and full opacity
## across multiple frame updates.  A previous bug converted images to RGB8
## before calling ImageTexture.update(), which caused intermittent
## transparency on some GL drivers.

var _preview: LiveKitAdapter.LocalVideoPreview


func before_each() -> void:
	_preview = LiveKitAdapter.LocalVideoPreview.new()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_rgba8_image(w: int = 320, h: int = 240, color := Color.RED) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_texture_null_before_first_frame() -> void:
	assert_null(
		_preview.get_texture(),
		"Texture should be null before any frames",
	)


func test_first_frame_creates_texture() -> void:
	var img := _make_rgba8_image()
	_preview.update_frame(img)

	var tex := _preview.get_texture()
	assert_not_null(tex, "Texture should exist after first frame")
	assert_eq(tex.get_width(), 320, "Texture width")
	assert_eq(tex.get_height(), 240, "Texture height")


func test_texture_stays_rgba8() -> void:
	var img := _make_rgba8_image()
	_preview.update_frame(img)

	var tex_image := _preview.get_texture().get_image()
	assert_eq(
		tex_image.get_format(),
		Image.FORMAT_RGBA8,
		"Texture should remain RGBA8 (not converted to RGB8)",
	)


func test_texture_fully_opaque_after_multiple_updates() -> void:
	# Feed 30 frames and verify the texture stays opaque on every one.
	# This is the scenario that triggered the intermittent transparency bug:
	# the first create_from_image() worked, but subsequent update() calls
	# with RGB8 format could produce zero-alpha on some GL drivers.
	for i in 30:
		var img := _make_rgba8_image(320, 240, Color.BLUE)
		_preview.update_frame(img)

	var tex_image := _preview.get_texture().get_image()
	assert_eq(
		tex_image.get_format(),
		Image.FORMAT_RGBA8,
		"Format should still be RGBA8 after 30 frames",
	)
	# Sample a few pixels to verify alpha is 255.
	for pos in [Vector2i(0, 0), Vector2i(160, 120), Vector2i(319, 239)]:
		var pixel := tex_image.get_pixelv(pos)
		assert_eq(
			pixel.a,
			1.0,
			"Pixel at %s should be fully opaque" % pos,
		)


func test_texture_reused_when_resolution_unchanged() -> void:
	var img_a := _make_rgba8_image(320, 240, Color.RED)
	_preview.update_frame(img_a)
	var tex_first := _preview.get_texture()

	var img_b := _make_rgba8_image(320, 240, Color.GREEN)
	_preview.update_frame(img_b)
	var tex_second := _preview.get_texture()

	assert_same(
		tex_first,
		tex_second,
		"Same-resolution frames should reuse the ImageTexture object",
	)


func test_texture_recreated_on_resolution_change() -> void:
	var img_a := _make_rgba8_image(320, 240)
	_preview.update_frame(img_a)
	var tex_first := _preview.get_texture()

	var img_b := _make_rgba8_image(640, 480)
	_preview.update_frame(img_b)
	var tex_second := _preview.get_texture()

	assert_ne(
		tex_second,
		tex_first,
		"Resolution change should create a new texture",
	)
	assert_eq(tex_second.get_width(), 640, "New texture width")
	assert_eq(tex_second.get_height(), 480, "New texture height")


func test_frame_received_signal_emitted() -> void:
	var calls := []
	_preview.frame_received.connect(func() -> void:
		calls.append(true)
	)

	_preview.update_frame(_make_rgba8_image())
	_preview.update_frame(_make_rgba8_image())
	_preview.update_frame(_make_rgba8_image())

	assert_eq(calls.size(), 3, "frame_received should fire once per update_frame()")


func test_close_clears_texture() -> void:
	_preview.update_frame(_make_rgba8_image())
	assert_not_null(_preview.get_texture(), "Texture should exist")

	_preview.close()
	assert_null(
		_preview.get_texture(),
		"Texture should be null after close()",
	)
