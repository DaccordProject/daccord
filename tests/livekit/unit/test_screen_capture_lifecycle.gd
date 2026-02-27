extends GutTest

## Reproduction tests for screen capture crash on unshare.
##
## IMPORTANT: These tests require a display (X11).  Run with:
##     godot -s addons/gut/gut_cmdln.gd -gexit -gdir=res://tests/livekit/unit \
##         -ginclude_subdirs=true -gprefix=test_ -gsuffix=.gd -glog=1 \
##         -gtest=test_screen_capture_lifecycle.gd
##
## Or use the shorthand:
##     godot -s tests/livekit/unit/test_screen_capture_lifecycle.gd
##
## The crash being investigated: when actively screen-sharing (frames
## flowing through LiveKitVideoSource's background capture thread) and
## then calling unpublish_track(), the app segfaults.  When frames are
## NOT flowing (screenshot returns empty), cleanup is safe.

const FRAME_COUNT := 30  # frames to feed before cleanup


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_first_monitor() -> Dictionary:
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	if monitors.is_empty():
		return {}
	return monitors[0]


func _create_test_image(w: int = 320, h: int = 240) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return img


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_get_monitors_does_not_crash() -> void:
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	# Just verify it returns an array without crashing.
	assert_typeof(monitors, TYPE_ARRAY, "get_monitors returns an Array")
	gut.p("  monitors found: %d" % monitors.size())


func test_screenshot_single_frame() -> void:
	var monitor := _get_first_monitor()
	if monitor.is_empty():
		pending("No monitor available — skipping")
		return
	var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitor)
	assert_not_null(capture, "create_for_monitor should succeed")

	var image: Image = capture.screenshot()
	gut.p("  screenshot returned: %s" % [image])
	if image != null:
		gut.p("  size: %dx%d  empty: %s" % [image.get_width(), image.get_height(), image.is_empty()])

	capture.close()
	pass_test("screenshot + close did not crash")


func test_video_source_feed_and_destroy() -> void:
	# Create a VideoSource and feed synthetic frames, then destroy it.
	# The destructor joins the background capture thread.
	var source: LiveKitVideoSource = LiveKitVideoSource.create(320, 240)
	assert_not_null(source, "VideoSource.create should succeed")

	var img := _create_test_image()
	for i in FRAME_COUNT:
		source.capture_frame(img)

	# Destroy the source — this joins the background thread.
	source = null
	pass_test("VideoSource feed + destroy did not crash")


func test_video_source_and_track_destroy() -> void:
	# Create source + track, feed frames, destroy in order.
	var source: LiveKitVideoSource = LiveKitVideoSource.create(320, 240)
	var track: LiveKitLocalVideoTrack = LiveKitLocalVideoTrack.create("test", source)
	assert_not_null(source, "VideoSource should exist")
	assert_not_null(track, "LocalVideoTrack should exist")

	var img := _create_test_image()
	for i in FRAME_COUNT:
		source.capture_frame(img)

	# Destroy source first (joins capture thread), then track.
	source = null
	track = null
	pass_test("source-before-track destroy did not crash")


func test_screenshot_to_capture_frame_pipeline() -> void:
	# Full pipeline: screenshot → capture_frame → destroy.
	# This is what livekit_adapter._process() does.
	var monitor := _get_first_monitor()
	if monitor.is_empty():
		pending("No monitor available — skipping")
		return

	var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitor)
	var source: LiveKitVideoSource = LiveKitVideoSource.create(1920, 1080)
	assert_not_null(capture, "capture should exist")
	assert_not_null(source, "source should exist")

	var frames_fed := 0
	for i in FRAME_COUNT:
		var image: Image = capture.screenshot()
		if image != null and not image.is_empty():
			source.capture_frame(image)
			frames_fed += 1

	gut.p("  frames fed: %d / %d" % [frames_fed, FRAME_COUNT])

	# Cleanup matching _cleanup_local_screen order:
	# 1. Stop feeding (null capture ref but keep native alive)
	var cap_ref = capture
	capture = null  # _screen_capture = null

	# 2. Destroy source (joins capture thread)
	source = null  # _local_screen_source = null

	# 3. Close native capture
	cap_ref.close()
	cap_ref = null

	pass_test("Full pipeline + cleanup did not crash (fed %d frames)" % frames_fed)


func test_cleanup_order_source_before_unpublish_simulation() -> void:
	# Simulates _cleanup_local_screen without a room:
	# Feed frames, then destroy source, then destroy track.
	var monitor := _get_first_monitor()
	if monitor.is_empty():
		pending("No monitor available — skipping")
		return

	var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitor)
	var source: LiveKitVideoSource = LiveKitVideoSource.create(1920, 1080)
	var track: LiveKitLocalVideoTrack = LiveKitLocalVideoTrack.create("screen", source)
	assert_not_null(capture, "capture")
	assert_not_null(source, "source")
	assert_not_null(track, "track")

	var frames_fed := 0
	for i in FRAME_COUNT:
		var image: Image = capture.screenshot()
		if image != null and not image.is_empty():
			source.capture_frame(image)
			frames_fed += 1

	gut.p("  frames fed: %d" % frames_fed)

	# Exact _cleanup_local_screen order:
	var cap_ref = capture
	capture = null       # stop _process from calling screenshot

	source = null        # destroy source → join capture thread

	# (unpublish_track would go here — can't test without a room)

	cap_ref.close()      # close frametap
	cap_ref = null

	track = null         # drop track reference

	pass_test("Simulated cleanup did not crash (fed %d frames)" % frames_fed)


func test_rapid_create_feed_destroy_cycles() -> void:
	# Stress test: rapid create/feed/destroy cycles to expose races.
	var monitor := _get_first_monitor()
	if monitor.is_empty():
		pending("No monitor available — skipping")
		return

	for cycle in 5:
		var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitor)
		var source: LiveKitVideoSource = LiveKitVideoSource.create(1920, 1080)
		var track: LiveKitLocalVideoTrack = LiveKitLocalVideoTrack.create("screen", source)

		for i in 10:
			var image: Image = capture.screenshot()
			if image != null and not image.is_empty():
				source.capture_frame(image)

		# Cleanup
		source = null
		capture.close()
		capture = null
		track = null

	pass_test("5 rapid create/destroy cycles did not crash")
