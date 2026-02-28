extends SettingsBase

## Global app settings panel — client-side preferences only.
## Pages: Profiles, Voice & Video, Sound, Appearance, Notifications, Updates.

const UserSettingsProfilesPage := preload(
	"res://scenes/user/user_settings_profiles_page.gd"
)
const UpdateDownloadDialogScene := preload(
	"res://scenes/messages/update_download_dialog.tscn"
)

var _profiles_pg: RefCounted
var _idle_dropdown: OptionButton

# Mic test state
var _mic_test_btn: Button
var _mic_test_bar: ProgressBar
var _mic_monitor_cb: CheckBox
var _mic_testing: bool = false
var _mic_test_player: AudioStreamPlayer
var _mic_test_effect: AudioEffectCapture
var _mic_test_bus_idx: int = -1

# Volume controls
var _input_vol_slider: HSlider
var _input_vol_label: Label
var _output_vol_slider: HSlider
var _output_vol_label: Label

# Threshold marker & bar fill
var _threshold_marker: ColorRect
var _bar_fill: StyleBoxFlat

# Input sensitivity
var _sensitivity_slider: HSlider
var _sensitivity_label: Label

# Update page refs
var _check_btn: Button
var _status_label: Label
var _update_row: HBoxContainer
var _update_version_label: Label
var _download_btn: Button
var _view_changes_btn: Button
var _skip_btn: Button
var _restart_btn: Button
var _progress_row: HBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _cancel_btn: Button
var _error_label_update: Label
var _cached_version_info: Dictionary = {}

func _get_sections() -> Array:
	return [
		"Profiles", "Voice & Video", "Sound",
		"Appearance", "Notifications", "Updates",
	]

func _build_pages() -> Array:
	return [
		_build_profiles_page(),
		_build_voice_page(),
		_build_sound_page(),
		_build_appearance_page(),
		_build_notifications_page(),
		_build_updates_page(),
	]

# --- Profiles page ---

func _build_profiles_page() -> VBoxContainer:
	_profiles_pg = UserSettingsProfilesPage.new(
		self, _page_vbox, _section_label,
	)
	return _profiles_pg.build()

# --- Voice & Video page ---

func _build_voice_page() -> VBoxContainer:
	var vbox := _page_vbox("Voice & Video")

	# Microphone
	vbox.add_child(_section_label("INPUT DEVICE"))
	var mic_dropdown := OptionButton.new()
	var saved_input: String = Config.voice.get_input_device()
	var input_devices: PackedStringArray = (
		AudioServer.get_input_device_list()
	)
	for dev in input_devices:
		mic_dropdown.add_item(dev)
	for i in mic_dropdown.item_count:
		if mic_dropdown.get_item_text(i) == saved_input:
			mic_dropdown.selected = i
			break
	mic_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.voice.set_input_device(
			mic_dropdown.get_item_text(idx)
		)
	)
	vbox.add_child(mic_dropdown)

	# Input volume
	vbox.add_child(_section_label("INPUT VOLUME"))
	var input_vol_row := HBoxContainer.new()
	input_vol_row.add_theme_constant_override("separation", 8)
	_input_vol_slider = HSlider.new()
	_input_vol_slider.min_value = 0
	_input_vol_slider.max_value = 200
	_input_vol_slider.step = 1
	_input_vol_slider.value = Config.voice.get_input_volume()
	_input_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_vol_row.add_child(_input_vol_slider)
	_input_vol_label = Label.new()
	_input_vol_label.text = "%d%%" % int(_input_vol_slider.value)
	_input_vol_label.custom_minimum_size = Vector2(48, 0)
	input_vol_row.add_child(_input_vol_label)
	_input_vol_slider.value_changed.connect(func(val: float) -> void:
		Config.voice.set_input_volume(int(val))
		_input_vol_label.text = "%d%%" % int(val)
		if _mic_testing and _mic_test_bus_idx >= 0:
			AudioServer.set_bus_volume_db(
				_mic_test_bus_idx, linear_to_db(val / 100.0)
			)
	)
	vbox.add_child(input_vol_row)

	# Speaker
	vbox.add_child(_section_label("OUTPUT DEVICE"))
	var speaker_dropdown := OptionButton.new()
	var saved_output: String = Config.voice.get_output_device()
	var output_devices: PackedStringArray = (
		AudioServer.get_output_device_list()
	)
	for dev in output_devices:
		speaker_dropdown.add_item(dev)
	for i in speaker_dropdown.item_count:
		if speaker_dropdown.get_item_text(i) == saved_output:
			speaker_dropdown.selected = i
			break
	speaker_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.voice.set_output_device(
			speaker_dropdown.get_item_text(idx)
		)
	)
	vbox.add_child(speaker_dropdown)

	# Output volume
	vbox.add_child(_section_label("OUTPUT VOLUME"))
	var output_vol_row := HBoxContainer.new()
	output_vol_row.add_theme_constant_override("separation", 8)
	_output_vol_slider = HSlider.new()
	_output_vol_slider.min_value = 0
	_output_vol_slider.max_value = 200
	_output_vol_slider.step = 1
	_output_vol_slider.value = Config.voice.get_output_volume()
	_output_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_vol_row.add_child(_output_vol_slider)
	_output_vol_label = Label.new()
	_output_vol_label.text = "%d%%" % int(_output_vol_slider.value)
	_output_vol_label.custom_minimum_size = Vector2(48, 0)
	output_vol_row.add_child(_output_vol_label)
	_output_vol_slider.value_changed.connect(func(val: float) -> void:
		Config.voice.set_output_volume(int(val))
		_output_vol_label.text = "%d%%" % int(val)
		AudioServer.set_bus_volume_db(
			0, linear_to_db(val / 100.0)
		)
	)
	vbox.add_child(output_vol_row)

	# Mic test
	vbox.add_child(_section_label("MIC TEST"))
	_mic_test_btn = Button.new()
	_mic_test_btn.text = "Let's Check"
	_mic_test_btn.pressed.connect(_on_mic_test_toggled)
	vbox.add_child(_mic_test_btn)
	_mic_monitor_cb = CheckBox.new()
	_mic_monitor_cb.text = "Monitor output"
	_mic_monitor_cb.button_pressed = true
	_mic_monitor_cb.toggled.connect(_on_mic_monitor_toggled)
	vbox.add_child(_mic_monitor_cb)
	_mic_test_bar = ProgressBar.new()
	_mic_test_bar.custom_minimum_size = Vector2(0, 20)
	_mic_test_bar.max_value = 1.0
	_mic_test_bar.value = 0.0
	_mic_test_bar.show_percentage = false
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = Color(0.35, 0.38, 0.42)
	_mic_test_bar.add_theme_stylebox_override("fill", _bar_fill)
	vbox.add_child(_mic_test_bar)

	# Threshold marker (thin vertical line on the level bar)
	_threshold_marker = ColorRect.new()
	_threshold_marker.color = Color(1.0, 0.85, 0.2)
	_threshold_marker.custom_minimum_size = Vector2(2, 0)
	_threshold_marker.size = Vector2(2, 20)
	_threshold_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mic_test_bar.add_child(_threshold_marker)
	_update_threshold_position()

	# Input sensitivity
	vbox.add_child(_section_label("INPUT SENSITIVITY"))
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 8)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0
	_sensitivity_slider.max_value = 100
	_sensitivity_slider.step = 1
	_sensitivity_slider.value = Config.voice.get_input_sensitivity()
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(_sensitivity_slider)
	_sensitivity_label = Label.new()
	_sensitivity_label.text = "%d%%" % int(_sensitivity_slider.value)
	_sensitivity_label.custom_minimum_size = Vector2(40, 0)
	sens_row.add_child(_sensitivity_label)
	_sensitivity_slider.value_changed.connect(func(val: float) -> void:
		Config.voice.set_input_sensitivity(int(val))
		_sensitivity_label.text = "%d%%" % int(val)
		_update_threshold_position()
	)
	vbox.add_child(sens_row)

	# Camera
	vbox.add_child(_section_label("CAMERA"))
	var cam_dropdown := OptionButton.new()
	cam_dropdown.add_item("System Default Camera")
	cam_dropdown.disabled = false
	vbox.add_child(cam_dropdown)

	# Video resolution
	vbox.add_child(_section_label("VIDEO RESOLUTION"))
	var res_dropdown := OptionButton.new()
	res_dropdown.add_item("480p")
	res_dropdown.add_item("720p")
	res_dropdown.add_item("1080p")
	res_dropdown.selected = Config.voice.get_video_resolution()
	res_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.voice.set_video_resolution(idx)
	)
	vbox.add_child(res_dropdown)

	# Video FPS
	vbox.add_child(_section_label("VIDEO FPS"))
	var fps_dropdown := OptionButton.new()
	fps_dropdown.add_item("15 FPS")
	fps_dropdown.add_item("30 FPS")
	fps_dropdown.add_item("60 FPS")
	var fps_val: int = Config.voice.get_video_fps()
	match fps_val:
		15: fps_dropdown.selected = 0
		60: fps_dropdown.selected = 2
		_: fps_dropdown.selected = 1
	fps_dropdown.item_selected.connect(func(idx: int) -> void:
		var fps_map := [15, 30, 60]
		Config.voice.set_video_fps(fps_map[idx])
	)
	vbox.add_child(fps_dropdown)

	set_process(false)
	return vbox

# --- Mic test ---

func _on_mic_test_toggled() -> void:
	if _mic_testing:
		_stop_mic_test()
	else:
		_start_mic_test()

func _on_mic_monitor_toggled(pressed: bool) -> void:
	if _mic_testing and _mic_test_bus_idx >= 0:
		AudioServer.set_bus_mute(_mic_test_bus_idx, not pressed)

func _start_mic_test() -> void:
	_mic_testing = true
	_mic_test_btn.text = "Stop Test"
	Config.voice.apply_devices()
	_mic_test_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(_mic_test_bus_idx)
	AudioServer.set_bus_name(_mic_test_bus_idx, "MicTest")
	AudioServer.set_bus_mute(
		_mic_test_bus_idx, not _mic_monitor_cb.button_pressed
	)
	var gain: float = Config.voice.get_input_volume() / 100.0
	AudioServer.set_bus_volume_db(
		_mic_test_bus_idx, linear_to_db(gain)
	)
	var effect := AudioEffectCapture.new()
	AudioServer.add_bus_effect(_mic_test_bus_idx, effect)
	_mic_test_effect = effect
	_mic_test_player = AudioStreamPlayer.new()
	_mic_test_player.stream = AudioStreamMicrophone.new()
	_mic_test_player.bus = "MicTest"
	add_child(_mic_test_player)
	_mic_test_player.play()
	set_process(true)

func _stop_mic_test() -> void:
	_mic_testing = false
	_mic_test_btn.text = "Let's Check"
	_cleanup_mic_test()
	if _mic_test_bar != null:
		_mic_test_bar.value = 0.0
	if _bar_fill != null:
		_bar_fill.bg_color = Color(0.35, 0.38, 0.42)
	set_process(false)

func _update_threshold_position() -> void:
	if _threshold_marker == null or _mic_test_bar == null:
		return
	var thr: float = Config.voice.get_speaking_threshold()
	var thr_norm: float = pow(clampf(thr / 0.5, 0.0, 1.0), 0.4)
	_threshold_marker.position.x = thr_norm * _mic_test_bar.size.x
	_threshold_marker.size.y = _mic_test_bar.size.y

func _cleanup_mic_test() -> void:
	if _mic_test_player != null:
		_mic_test_player.stop()
		_mic_test_player.queue_free()
		_mic_test_player = null
	_mic_test_effect = null
	if _mic_test_bus_idx >= 0 and _mic_test_bus_idx < AudioServer.bus_count:
		AudioServer.remove_bus(_mic_test_bus_idx)
	_mic_test_bus_idx = -1

func _process(_delta: float) -> void:
	if _mic_test_effect == null or _mic_test_bar == null:
		return
	_update_threshold_position()
	var frames: int = _mic_test_effect.get_frames_available()
	if frames <= 0:
		return
	var buf: PackedVector2Array = _mic_test_effect.get_buffer(frames)
	var rms: float = 0.0
	for i in buf.size():
		var sample: float = (buf[i].x + buf[i].y) * 0.5
		rms += sample * sample
	if buf.size() > 0:
		rms = sqrt(rms / buf.size())
	# Scale by input volume gain
	var gain: float = _input_vol_slider.value / 100.0
	var display_rms: float = rms * gain
	_mic_test_bar.value = pow(clampf(display_rms / 0.5, 0.0, 1.0), 0.4)
	# Bar color: green when above threshold, gray when below
	var thr: float = Config.voice.get_speaking_threshold()
	if display_rms > thr:
		_bar_fill.bg_color = Color(0.263, 0.694, 0.431)
	else:
		_bar_fill.bg_color = Color(0.35, 0.38, 0.42)

func _exit_tree() -> void:
	_cleanup_mic_test()

# --- Sound page ---

func _build_sound_page() -> VBoxContainer:
	var vbox := _page_vbox("Sound")

	vbox.add_child(_section_label("VOLUME"))
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = Config.get_sfx_volume()
	vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_row.add_child(vol_slider)
	var vol_label := Label.new()
	vol_label.text = "%d%%" % int(vol_slider.value * 100)
	vol_label.custom_minimum_size = Vector2(40, 0)
	vol_row.add_child(vol_label)
	vol_slider.value_changed.connect(func(val: float) -> void:
		Config.set_sfx_volume(val)
		vol_label.text = "%d%%" % int(val * 100)
	)
	vbox.add_child(vol_row)

	vbox.add_child(_section_label("SOUND EVENTS"))
	var sound_events := [
		["message_received", "Message received (unfocused channel)"],
		["mention_received", "Mention received"],
		["message_sent", "Message sent"],
		["voice_join", "Join voice channel"],
		["voice_leave", "Leave voice channel"],
		["peer_join", "Peer joins voice channel"],
		["peer_leave", "Peer leaves voice channel"],
		["mute", "Mute"],
		["unmute", "Unmute"],
		["deafen", "Deafen"],
		["undeafen", "Undeafen"],
	]
	for event in sound_events:
		var sname: String = event[0]
		var slabel: String = event[1]
		var cb := CheckBox.new()
		cb.text = slabel
		cb.button_pressed = Config.is_sound_enabled(sname)
		cb.toggled.connect(func(pressed: bool) -> void:
			Config.set_sound_enabled(sname, pressed)
		)
		vbox.add_child(cb)

	return vbox

# --- Appearance page (new) ---

func _build_appearance_page() -> VBoxContainer:
	var vbox := _page_vbox("Appearance")

	# Reduce motion
	vbox.add_child(_section_label("ACCESSIBILITY"))
	var motion_cb := CheckBox.new()
	motion_cb.text = "Reduce motion"
	motion_cb.button_pressed = Config.get_reduced_motion()
	motion_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_reduced_motion(pressed)
	)
	vbox.add_child(motion_cb)

	# UI Scale
	vbox.add_child(_section_label("UI SCALE"))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.5
	scale_slider.max_value = 2.0
	scale_slider.step = 0.1
	var current_scale: float = Config.get_ui_scale()
	scale_slider.value = current_scale if current_scale > 0.0 else 1.0
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_slider)
	var scale_label := Label.new()
	scale_label.text = "%d%%" % int(scale_slider.value * 100)
	scale_label.custom_minimum_size = Vector2(50, 0)
	scale_row.add_child(scale_label)
	scale_slider.value_changed.connect(func(val: float) -> void:
		Config._set_ui_scale(val)
		scale_label.text = "%d%%" % int(val * 100)
	)
	vbox.add_child(scale_row)

	# Emoji skin tone
	vbox.add_child(_section_label("EMOJI SKIN TONE"))
	var tone_dropdown := OptionButton.new()
	tone_dropdown.add_item("Default")
	tone_dropdown.add_item("Light")
	tone_dropdown.add_item("Medium-Light")
	tone_dropdown.add_item("Medium")
	tone_dropdown.add_item("Medium-Dark")
	tone_dropdown.add_item("Dark")
	tone_dropdown.selected = Config.get_emoji_skin_tone()
	tone_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_emoji_skin_tone(idx)
	)
	vbox.add_child(tone_dropdown)

	return vbox

# --- Notifications page (trimmed — global only) ---

func _build_notifications_page() -> VBoxContainer:
	var vbox := _page_vbox("Notifications")

	var suppress_cb := CheckBox.new()
	suppress_cb.text = "Suppress @everyone and @here"
	suppress_cb.button_pressed = Config.get_suppress_everyone()
	suppress_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_suppress_everyone(pressed)
	)
	vbox.add_child(suppress_cb)

	# Idle timeout
	vbox.add_child(_section_label("IDLE TIMEOUT"))
	_idle_dropdown = OptionButton.new()
	_idle_dropdown.add_item("Disabled")
	_idle_dropdown.add_item("1 minute")
	_idle_dropdown.add_item("5 minutes")
	_idle_dropdown.add_item("10 minutes")
	_idle_dropdown.add_item("30 minutes")
	var idle_vals := [0, 60, 300, 600, 1800]
	var current_idle: int = Config.get_idle_timeout()
	for i in idle_vals.size():
		if idle_vals[i] == current_idle:
			_idle_dropdown.selected = i
			break
	_idle_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_idle_timeout(idle_vals[idx])
	)
	vbox.add_child(_idle_dropdown)

	# Error reporting
	vbox.add_child(_section_label("ERROR REPORTING"))
	var error_cb := CheckBox.new()
	error_cb.text = "Send anonymous crash and error reports"
	error_cb.button_pressed = Config.get_error_reporting_enabled()
	error_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_error_reporting_enabled(pressed)
		if not Config.has_error_reporting_preference():
			Config.set_error_reporting_consent_shown()
		if pressed:
			ErrorReporting.init_sentry()
	)
	vbox.add_child(error_cb)

	return vbox

# --- Updates page ---

func _build_updates_page() -> VBoxContainer:
	var vbox := _page_vbox("Updates")

	# Current version
	vbox.add_child(_section_label("CURRENT VERSION"))
	var version_label := Label.new()
	version_label.text = "v%s" % Client.app_version
	vbox.add_child(version_label)

	# Check for updates
	vbox.add_child(_section_label("CHECK FOR UPDATES"))
	var check_row := HBoxContainer.new()
	check_row.add_theme_constant_override("separation", 12)
	_check_btn = Button.new()
	_check_btn.text = "Check for Updates"
	_check_btn.pressed.connect(_on_check_updates_pressed)
	check_row.add_child(_check_btn)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	check_row.add_child(_status_label)
	vbox.add_child(check_row)

	# Update available row (hidden until update found)
	_update_row = HBoxContainer.new()
	_update_row.add_theme_constant_override("separation", 8)
	_update_row.visible = false
	_update_version_label = Label.new()
	_update_version_label.add_theme_font_size_override("font_size", 14)
	_update_version_label.add_theme_color_override(
		"font_color", Color(0.345, 0.396, 0.949)
	)
	_update_row.add_child(_update_version_label)
	_view_changes_btn = Button.new()
	_view_changes_btn.text = "View Changes"
	_view_changes_btn.flat = true
	_view_changes_btn.add_theme_color_override(
		"font_color", Color(0.345, 0.396, 0.949)
	)
	_view_changes_btn.add_theme_font_size_override("font_size", 12)
	_view_changes_btn.pressed.connect(_on_view_changes)
	_update_row.add_child(_view_changes_btn)
	_download_btn = Button.new()
	_download_btn.text = "Download & Install"
	_download_btn.pressed.connect(_on_download_pressed)
	_update_row.add_child(_download_btn)
	_skip_btn = Button.new()
	_skip_btn.text = "Skip This Version"
	_skip_btn.flat = true
	_skip_btn.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.pressed.connect(_on_skip_pressed)
	_update_row.add_child(_skip_btn)
	vbox.add_child(_update_row)

	# Download progress row (hidden until downloading)
	_progress_row = HBoxContainer.new()
	_progress_row.add_theme_constant_override("separation", 8)
	_progress_row.visible = false
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(200, 20)
	_progress_bar.max_value = 100.0
	_progress_row.add_child(_progress_bar)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_progress_row.add_child(_progress_label)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.flat = true
	_cancel_btn.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_cancel_btn.pressed.connect(_on_cancel_download)
	_progress_row.add_child(_cancel_btn)
	vbox.add_child(_progress_row)

	# Restart button (hidden until update ready)
	_restart_btn = Button.new()
	_restart_btn.text = "Restart to Update"
	_restart_btn.visible = false
	_restart_btn.pressed.connect(func() -> void:
		Updater.apply_update_and_restart()
	)
	vbox.add_child(_restart_btn)

	# Error label
	_error_label_update = Label.new()
	_error_label_update.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	_error_label_update.add_theme_font_size_override("font_size", 13)
	_error_label_update.visible = false
	vbox.add_child(_error_label_update)

	# Auto-check toggle
	vbox.add_child(HSeparator.new())
	var auto_cb := CheckBox.new()
	auto_cb.text = "Automatically check for updates"
	auto_cb.button_pressed = Config.get_auto_update_check()
	auto_cb.toggled.connect(func(pressed: bool) -> void:
		Config._set_auto_update_check(pressed)
	)
	vbox.add_child(auto_cb)

	# Master server URL
	vbox.add_child(_section_label("MASTER SERVER URL"))
	var url_input := LineEdit.new()
	url_input.text = Config.get_master_server_url()
	url_input.placeholder_text = "https://master.daccord.chat"
	vbox.add_child(url_input)

	var url_save := Button.new()
	url_save.text = "Save URL"
	url_save.pressed.connect(func() -> void:
		var new_url: String = url_input.text.strip_edges()
		if not new_url.is_empty():
			Config.set_master_server_url(new_url)
	)
	vbox.add_child(url_save)

	# Connect update signals
	AppState.update_available.connect(_on_update_available)
	AppState.update_check_complete.connect(_on_update_check_complete)
	AppState.update_check_failed.connect(_on_update_check_failed)
	AppState.update_download_started.connect(_on_update_download_started)
	AppState.update_download_progress.connect(_on_update_download_progress)
	AppState.update_download_complete.connect(_on_update_download_complete)
	AppState.update_download_failed.connect(_on_update_download_failed)

	# If an update is already known, show it
	if Updater.is_update_ready():
		_show_restart_state()
	elif not Updater.get_latest_version_info().is_empty():
		var info: Dictionary = Updater.get_latest_version_info()
		if Updater.is_newer(
			info.get("version", ""), Client.app_version
		):
			_on_update_available(info)

	return vbox

# --- Updates page callbacks ---

func _on_check_updates_pressed() -> void:
	_check_btn.disabled = true
	_status_label.text = "Checking..."
	_error_label_update.visible = false
	Updater.check_for_updates(true)

func _on_update_available(info: Dictionary) -> void:
	_cached_version_info = info
	_check_btn.disabled = false
	_status_label.text = ""
	var version: String = info.get("version", "unknown")
	_update_version_label.text = "v%s is available" % version
	_update_row.visible = true
	_download_btn.visible = true
	_skip_btn.visible = true
	_progress_row.visible = false
	_restart_btn.visible = false
	_error_label_update.visible = false

func _on_update_check_complete(_info: Variant) -> void:
	_check_btn.disabled = false
	_status_label.text = "You're on the latest version."

func _on_update_check_failed(error: String) -> void:
	_check_btn.disabled = false
	_status_label.text = ""
	_error_label_update.text = "Check failed: %s" % error
	_error_label_update.visible = true

func _on_view_changes() -> void:
	var url: String = _cached_version_info.get("release_url", "")
	if not url.is_empty():
		OS.shell_open(url)

func _on_download_pressed() -> void:
	if _cached_version_info.is_empty():
		return
	var download_url: String = _cached_version_info.get(
		"download_url", ""
	)
	# No downloadable asset: open release page in browser
	if download_url.is_empty():
		var url: String = _cached_version_info.get("release_url", "")
		if not url.is_empty():
			OS.shell_open(url)
		return
	# Start in-app download
	_download_btn.visible = false
	_skip_btn.visible = false
	_progress_row.visible = true
	_progress_bar.value = 0
	_progress_label.text = "Starting..."
	_cancel_btn.visible = true
	_error_label_update.visible = false
	Updater.download_update(_cached_version_info)

func _on_skip_pressed() -> void:
	var version: String = _cached_version_info.get("version", "")
	if not version.is_empty():
		Updater.skip_version(version)
	_update_row.visible = false
	_status_label.text = "Version v%s skipped." % version

func _on_cancel_download() -> void:
	Updater.cancel_download()
	_progress_row.visible = false
	_download_btn.visible = true
	_skip_btn.visible = true

func _on_update_download_started() -> void:
	_progress_row.visible = true
	_progress_bar.value = 0
	_progress_label.text = "Downloading..."
	_cancel_btn.visible = true

func _on_update_download_progress(percent: float) -> void:
	_progress_bar.value = percent
	var total_size: int = _cached_version_info.get("download_size", 0)
	if total_size > 0:
		var downloaded: int = int(percent / 100.0 * total_size)
		_progress_label.text = "%s / %s" % [
			_format_size(downloaded), _format_size(total_size)
		]
	else:
		_progress_label.text = "%.0f%%" % percent

func _on_update_download_complete(_path: String) -> void:
	_show_restart_state()

func _on_update_download_failed(error: String) -> void:
	_progress_row.visible = false
	_download_btn.visible = true
	_skip_btn.visible = true
	_error_label_update.text = "Download failed: %s" % error
	_error_label_update.visible = true

func _show_restart_state() -> void:
	_check_btn.disabled = false
	_status_label.text = ""
	_update_row.visible = false
	_progress_row.visible = false
	_restart_btn.visible = true
	_error_label_update.visible = false

static func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	if bytes < 1024 * 1024:
		return str(snappedi(bytes / 1024, 1)) + " KB"
	return "%.1f MB" % (bytes / 1048576.0)
