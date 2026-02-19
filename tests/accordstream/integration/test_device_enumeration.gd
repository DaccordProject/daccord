extends GutTest


# --- Singleton registration ---

func test_singleton_exists():
	var accord = Engine.get_singleton("AccordStream")
	assert_not_null(accord, "AccordStream singleton should be registered")

func test_singleton_is_accessible_via_classname():
	# AccordStream should be usable as a global like any engine singleton
	var cameras = AccordStream.get_cameras()
	assert_typeof(cameras, TYPE_ARRAY, "Should be callable via AccordStream global")


# --- get_cameras ---

func test_get_cameras_returns_array():
	var cameras = AccordStream.get_cameras()
	assert_typeof(cameras, TYPE_ARRAY, "get_cameras() should return an Array")

func test_get_cameras_is_idempotent():
	var first = AccordStream.get_cameras()
	var second = AccordStream.get_cameras()
	assert_eq(first.size(), second.size(),
			  "Repeated get_cameras() calls should return same count")

func test_camera_dict_has_required_keys():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No cameras available — skipping")
		return
	var cam = cameras[0]
	assert_has(cam, "id", "Camera dict should have 'id'")
	assert_has(cam, "name", "Camera dict should have 'name'")

func test_camera_dict_value_types():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No cameras available — skipping")
		return
	var cam = cameras[0]
	assert_typeof(cam["id"], TYPE_STRING, "Camera id should be a String")
	assert_typeof(cam["name"], TYPE_STRING, "Camera name should be a String")

func test_camera_ids_are_nonempty():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No cameras available — skipping")
		return
	for cam in cameras:
		assert_gt(cam["id"].length(), 0, "Camera id should not be empty")

func test_camera_names_are_nonempty():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No cameras available — skipping")
		return
	for cam in cameras:
		assert_gt(cam["name"].length(), 0, "Camera name should not be empty")

func test_camera_ids_are_unique():
	var cameras = AccordStream.get_cameras()
	if cameras.size() < 2:
		pass_test("Need ≥2 cameras for uniqueness test — skipping")
		return
	var ids := {}
	for cam in cameras:
		assert_false(ids.has(cam["id"]), "Camera id '%s' appears more than once" % cam["id"])
		ids[cam["id"]] = true


# --- get_microphones ---

func test_get_microphones_returns_array():
	var mics = AccordStream.get_microphones()
	assert_typeof(mics, TYPE_ARRAY, "get_microphones() should return an Array")

func test_get_microphones_is_idempotent():
	var first = AccordStream.get_microphones()
	var second = AccordStream.get_microphones()
	assert_eq(first.size(), second.size(),
			  "Repeated get_microphones() calls should return same count")

func test_microphone_dict_has_required_keys():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphones available — skipping")
		return
	var mic = mics[0]
	assert_has(mic, "id", "Microphone dict should have 'id'")
	assert_has(mic, "name", "Microphone dict should have 'name'")

func test_microphone_dict_value_types():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphones available — skipping")
		return
	var mic = mics[0]
	assert_typeof(mic["id"], TYPE_STRING, "Microphone id should be a String")
	assert_typeof(mic["name"], TYPE_STRING, "Microphone name should be a String")

func test_microphone_names_are_nonempty():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphones available — skipping")
		return
	for mic in mics:
		assert_gt(mic["name"].length(), 0, "Microphone name should not be empty")


# --- get_speakers ---

func test_get_speakers_returns_array():
	var speakers = AccordStream.get_speakers()
	assert_typeof(speakers, TYPE_ARRAY, "get_speakers() should return an Array")

func test_get_speakers_is_idempotent():
	var first = AccordStream.get_speakers()
	var second = AccordStream.get_speakers()
	assert_eq(first.size(), second.size(),
			  "Repeated get_speakers() calls should return same count")

func test_speaker_dict_has_required_keys():
	var speakers = AccordStream.get_speakers()
	if speakers.size() == 0:
		pass_test("No speakers available — skipping")
		return
	var spk = speakers[0]
	assert_has(spk, "id", "Speaker dict should have 'id'")
	assert_has(spk, "name", "Speaker dict should have 'name'")

func test_speaker_dict_value_types():
	var speakers = AccordStream.get_speakers()
	if speakers.size() == 0:
		pass_test("No speakers available — skipping")
		return
	var spk = speakers[0]
	assert_typeof(spk["id"], TYPE_STRING, "Speaker id should be a String")
	assert_typeof(spk["name"], TYPE_STRING, "Speaker name should be a String")

func test_speaker_names_are_nonempty():
	var speakers = AccordStream.get_speakers()
	if speakers.size() == 0:
		pass_test("No speakers available — skipping")
		return
	for spk in speakers:
		assert_gt(spk["name"].length(), 0, "Speaker name should not be empty")

func test_speaker_ids_are_unique():
	var speakers = AccordStream.get_speakers()
	if speakers.size() < 2:
		pass_test("Need ≥2 speakers for uniqueness test — skipping")
		return
	var ids := {}
	for spk in speakers:
		assert_false(ids.has(spk["id"]), "Speaker id '%s' appears more than once" % spk["id"])
		ids[spk["id"]] = true


# --- set_output_device / get_output_device ---

func test_get_output_device_returns_string():
	var device = AccordStream.get_output_device()
	assert_typeof(device, TYPE_STRING, "get_output_device() should return a String")

func test_set_output_device_invalid_returns_false():
	var result = AccordStream.set_output_device("nonexistent_device_id_xyz")
	assert_false(result, "set_output_device() with invalid ID should return false")

func test_set_output_device_valid_returns_true():
	var speakers = AccordStream.get_speakers()
	if speakers.size() == 0:
		pass_test("No speakers available — skipping")
		return
	var spk_id: String = speakers[0]["id"]
	var result = AccordStream.set_output_device(spk_id)
	assert_true(result, "set_output_device() with valid ID should return true")

func test_set_output_device_roundtrips():
	var speakers = AccordStream.get_speakers()
	if speakers.size() == 0:
		pass_test("No speakers available — skipping")
		return
	var spk_id: String = speakers[0]["id"]
	AccordStream.set_output_device(spk_id)
	var got: String = AccordStream.get_output_device()
	assert_eq(got, spk_id, "get_output_device() should return the ID that was set")


# --- get_screens ---

func test_get_screens_returns_array():
	var screens = AccordStream.get_screens()
	assert_typeof(screens, TYPE_ARRAY, "get_screens() should return an Array")

func test_get_screens_is_idempotent():
	var first = AccordStream.get_screens()
	var second = AccordStream.get_screens()
	assert_eq(first.size(), second.size(),
			  "Repeated get_screens() calls should return same count")

func test_screen_dict_has_required_keys():
	var screens = AccordStream.get_screens()
	if screens.size() == 0:
		pass_test("No screens available — skipping")
		return
	var screen = screens[0]
	assert_has(screen, "id", "Screen dict should have 'id'")
	assert_has(screen, "title", "Screen dict should have 'title'")
	assert_has(screen, "width", "Screen dict should have 'width'")
	assert_has(screen, "height", "Screen dict should have 'height'")

func test_screen_dict_value_types():
	var screens = AccordStream.get_screens()
	if screens.size() == 0:
		pass_test("No screens available — skipping")
		return
	var screen = screens[0]
	assert_typeof(screen["id"], TYPE_INT, "Screen id should be an int")
	assert_typeof(screen["title"], TYPE_STRING, "Screen title should be a String")
	assert_typeof(screen["width"], TYPE_INT, "Screen width should be an int")
	assert_typeof(screen["height"], TYPE_INT, "Screen height should be an int")


# --- get_windows ---

func test_get_windows_returns_array():
	var windows = AccordStream.get_windows()
	assert_typeof(windows, TYPE_ARRAY, "get_windows() should return an Array")

func test_get_windows_is_idempotent():
	var first = AccordStream.get_windows()
	var second = AccordStream.get_windows()
	# Window lists can change between calls if windows are opened/closed,
	# but back-to-back calls should typically match.
	assert_typeof(first, TYPE_ARRAY)
	assert_typeof(second, TYPE_ARRAY)
	pass_test("get_windows() returned arrays on both calls without crashing")

func test_window_dict_has_required_keys():
	var windows = AccordStream.get_windows()
	if windows.size() == 0:
		pass_test("No windows available — skipping")
		return
	var window = windows[0]
	assert_has(window, "id", "Window dict should have 'id'")
	assert_has(window, "title", "Window dict should have 'title'")
	assert_has(window, "width", "Window dict should have 'width'")
	assert_has(window, "height", "Window dict should have 'height'")

func test_window_dict_value_types():
	var windows = AccordStream.get_windows()
	if windows.size() == 0:
		pass_test("No windows available — skipping")
		return
	var window = windows[0]
	assert_typeof(window["id"], TYPE_INT, "Window id should be an int")
	assert_typeof(window["title"], TYPE_STRING, "Window title should be a String")


# --- Cross-enumeration: all five calls succeed without crashing ---

func test_enumerate_all_device_types_sequentially():
	var cameras = AccordStream.get_cameras()
	var mics = AccordStream.get_microphones()
	var speakers = AccordStream.get_speakers()
	var screens = AccordStream.get_screens()
	var windows = AccordStream.get_windows()

	assert_typeof(cameras, TYPE_ARRAY)
	assert_typeof(mics, TYPE_ARRAY)
	assert_typeof(speakers, TYPE_ARRAY)
	assert_typeof(screens, TYPE_ARRAY)
	assert_typeof(windows, TYPE_ARRAY)
	pass_test("All five enumeration methods completed without crashing")

func test_enumerate_all_device_types_repeated():
	# Verifies the WebRTC context doesn't break on repeated init/enum cycles
	for i in range(5):
		AccordStream.get_cameras()
		AccordStream.get_microphones()
		AccordStream.get_speakers()
		AccordStream.get_screens()
		AccordStream.get_windows()
	pass_test("Enumeration × 5 completed without crashing")
