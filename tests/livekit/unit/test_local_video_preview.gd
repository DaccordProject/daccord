extends GutTest

## Unit tests for LiveKitAdapter.LocalVideoPreview.
##
## Verifies that update_frame() produces RGBA8 textures with full opacity
## across multiple frame updates.  Two bugs existed previously:
## 1. Converting to RGB8 before ImageTexture.update() caused intermittent
##    transparency on some GL drivers.
## 2. X11 on 32-bit depth displays returns alpha=0 for most windows,
##    so the preview must force alpha to 1.0 regardless of input.

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


func _make_zero_alpha_image(w: int = 320, h: int = 240) -> Image:
	## Simulates X11 on 32-bit depth displays where the alpha byte is 0.
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.3, 0.8, 0.0))
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


func test_zero_alpha_input_becomes_opaque() -> void:
	# X11 on 32-bit depth displays returns alpha=0 for most windows.
	# update_frame() must force alpha to 1.0 so the preview is visible.
	var img := _make_zero_alpha_image()
	assert_eq(img.get_pixelv(Vector2i(0, 0)).a, 0.0, "Precondition: input alpha is 0")

	_preview.update_frame(img)

	var tex_image := _preview.get_texture().get_image()
	assert_eq(
		tex_image.get_format(),
		Image.FORMAT_RGBA8,
		"Texture should be RGBA8",
	)
	for pos in [Vector2i(0, 0), Vector2i(160, 120), Vector2i(319, 239)]:
		var pixel := tex_image.get_pixelv(pos)
		assert_eq(
			pixel.a,
			1.0,
			"Pixel at %s should be fully opaque despite zero-alpha input" % pos,
		)


func test_zero_alpha_sustained_across_frames() -> void:
	# Verify opacity holds across many frames with zero-alpha input,
	# covering both the create_from_image and update() code paths.
	for i in 30:
		_preview.update_frame(_make_zero_alpha_image())

	var tex_image := _preview.get_texture().get_image()
	var pixel := tex_image.get_pixelv(Vector2i(160, 120))
	assert_eq(
		pixel.a,
		1.0,
		"Pixel should be fully opaque after 30 zero-alpha frames",
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
