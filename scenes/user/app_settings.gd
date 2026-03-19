extends SettingsBase

## Global app settings panel — client-side preferences only.
## Pages: Profiles, Voice & Video, Sound, Appearance, Notifications, Updates.

const UserSettingsProfilesPage := preload(
	"res://scenes/user/user_settings_profiles_page.gd"
)
const UpdateDownloadDialogScene := preload(
	"res://scenes/messages/update_download_dialog.tscn"
)
const ServerManagementPanel := preload(
	"res://scenes/admin/server_management_panel.tscn"
)
const AppSettingsUpdatesPage := preload(
	"res://scenes/user/app_settings_updates_page.gd"
)
const AppSettingsAboutPage := preload(
	"res://scenes/user/app_settings_about_page.gd"
)
const AppSettingsDeveloperPage := preload(
	"res://scenes/user/app_settings_developer_page.gd"
)
const WebMicAudio := preload("res://scenes/user/web_mic_audio.gd")

var _profiles_pg: RefCounted
var _updates_pg: RefCounted
var _about_pg: RefCounted
var _developer_pg: RefCounted
var _idle_dropdown: OptionButton

# Mic test state
var _mic_test_btn: Button
var _mic_test_bar: ProgressBar
var _mic_monitor_cb: CheckBox
var _mic_testing: bool = false
var _mic_test_player: AudioStreamPlayer
var _mic_test_effect: AudioEffectCapture
var _mic_test_bus_idx: int = -1
var _web_mic: RefCounted = WebMicAudio.new()

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

# Appearance page refs
var _theme_dropdown: OptionButton
var _theme_preview_row: HBoxContainer
var _custom_colors_container: VBoxContainer
var _color_pickers: Dictionary = {} # key -> ColorPickerButton

func _get_sections() -> Array:
	var sections := [
		tr("Profiles"), tr("Voice & Video"), tr("Sound"),
		tr("Appearance"), tr("Notifications"), tr("Updates"), tr("About"),
	]
	if Config.developer.get_developer_mode():
		sections.append(tr("Developer"))
	if Client.current_user.get("is_admin", false):
		sections.append(tr("Instance Admin"))
	return sections

func _build_pages() -> Array:
	var pages := [
		_build_profiles_page(),
		_build_voice_page(),
		_build_sound_page(),
		_build_appearance_page(),
		_build_notifications_page(),
		_build_updates_page(),
		_build_about_page(),
	]
	if Config.developer.get_developer_mode():
		pages.append(_build_developer_page())
	if Client.current_user.get("is_admin", false):
		pages.append(_build_admin_page())
	return pages

# --- Profiles page ---
func _build_profiles_page() -> VBoxContainer:
	_profiles_pg = UserSettingsProfilesPage.new(
		self , _page_vbox, _section_label,
	)
	return _profiles_pg.build()

# --- Voice & Video page ---
func _build_voice_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Voice & Video"))

	# Microphone
	if OS.get_name() == "Web":
		var web_note := Label.new()
		web_note.text = tr("Device selection is managed by your browser.")
		web_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		web_note.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		vbox.add_child(web_note)
	else:
		vbox.add_child(_section_label(tr("INPUT DEVICE")))
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
	vbox.add_child(_section_label(tr("INPUT VOLUME")))
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
	if OS.get_name() != "Web":
		vbox.add_child(_section_label(tr("OUTPUT DEVICE")))
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
	vbox.add_child(_section_label(tr("OUTPUT VOLUME")))
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
	vbox.add_child(_section_label(tr("MIC TEST")))
	_mic_test_btn = SettingsBase.create_action_button(tr("Let's Check"))
	_mic_test_btn.pressed.connect(_on_mic_test_toggled)
	vbox.add_child(_mic_test_btn)
	_mic_monitor_cb = CheckBox.new()
	_mic_monitor_cb.text = tr("Monitor output")
	_mic_monitor_cb.button_pressed = true
	_mic_monitor_cb.toggled.connect(_on_mic_monitor_toggled)
	vbox.add_child(_mic_monitor_cb)
	_mic_test_bar = ProgressBar.new()
	_mic_test_bar.custom_minimum_size = Vector2(0, 20)
	_mic_test_bar.max_value = 1.0
	_mic_test_bar.value = 0.0
	_mic_test_bar.show_percentage = false
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = ThemeManager.get_color("button_hover")
	_mic_test_bar.add_theme_stylebox_override("fill", _bar_fill)
	vbox.add_child(_mic_test_bar)

	# Threshold marker (thin vertical line on the level bar)
	_threshold_marker = ColorRect.new()
	_threshold_marker.color = Color(1.0, 0.85, 0.2)
	_threshold_marker.custom_minimum_size = Vector2(3, 0)
	_threshold_marker.size = Vector2(3, 20)
	_threshold_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mic_test_bar.add_child(_threshold_marker)
	_mic_test_bar.resized.connect(_update_threshold_position)
	_update_threshold_position()

	# Input sensitivity
	vbox.add_child(_section_label(tr("INPUT SENSITIVITY")))
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
	if OS.get_name() != "Web":
		vbox.add_child(_section_label(tr("CAMERA")))
		var cam_dropdown := OptionButton.new()
		cam_dropdown.add_item(tr("System Default Camera"))
		cam_dropdown.disabled = false
		vbox.add_child(cam_dropdown)

	# Video resolution
	vbox.add_child(_section_label(tr("VIDEO RESOLUTION")))
	var res_dropdown := OptionButton.new()
	res_dropdown.add_item(tr("480p"))
	res_dropdown.add_item(tr("720p"))
	res_dropdown.add_item(tr("1080p"))
	res_dropdown.selected = Config.voice.get_video_resolution()
	res_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.voice.set_video_resolution(idx)
	)
	vbox.add_child(res_dropdown)

	# Video FPS
	vbox.add_child(_section_label(tr("VIDEO FPS")))
	var fps_dropdown := OptionButton.new()
	fps_dropdown.add_item(tr("15 FPS"))
	fps_dropdown.add_item(tr("30 FPS"))
	fps_dropdown.add_item(tr("60 FPS"))
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
	if not _mic_testing:
		return
	if OS.get_name() == "Web":
		if pressed:
			_web_mic.start_monitor()
		else:
			_web_mic.stop_monitor()
	elif _mic_test_bus_idx >= 0:
		AudioServer.set_bus_mute(_mic_test_bus_idx, not pressed)

func _start_mic_test() -> void:
	_mic_testing = true
	_mic_test_btn.text = tr("Stop Test")
	Config.voice.apply_devices()
	var is_web: bool = OS.get_name() == "Web"
	if is_web:
		# On web, AudioStreamMicrophone cannot be sampled — use getUserMedia
		# with an AnalyserNode for the level meter and a GainNode for monitor
		# playback, all through the Web Audio API.
		_web_mic.start_analyser()
		if _mic_monitor_cb.button_pressed:
			_web_mic.start_monitor()
	else:
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
	_mic_test_btn.text = tr("Let's Check")
	_cleanup_mic_test()
	if _mic_test_bar != null:
		_mic_test_bar.value = 0.0
	if _bar_fill != null:
		_bar_fill.bg_color = ThemeManager.get_color("button_hover")
	set_process(false)

func _update_threshold_position() -> void:
	if _threshold_marker == null or _mic_test_bar == null:
		return
	var thr: float = Config.voice.get_speaking_threshold()
	var thr_norm: float = pow(clampf(thr / 0.1, 0.0, 1.0), 0.4)
	_threshold_marker.position.x = thr_norm * _mic_test_bar.size.x
	_threshold_marker.size.y = _mic_test_bar.size.y

func _cleanup_mic_test() -> void:
	_web_mic.stop_monitor()
	_web_mic.stop_analyser()
	if _mic_test_player != null:
		_mic_test_player.stop()
		_mic_test_player.queue_free()
		_mic_test_player = null
	_mic_test_effect = null
	if _mic_test_bus_idx >= 0 and _mic_test_bus_idx < AudioServer.bus_count:
		AudioServer.remove_bus(_mic_test_bus_idx)
	_mic_test_bus_idx = -1

func _process(_delta: float) -> void:
	if _mic_test_bar == null:
		return
	_update_threshold_position()
	var display_rms: float = 0.0
	if OS.get_name() == "Web":
		display_rms = _web_mic.get_rms()
	else:
		if _mic_test_effect == null:
			return
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
		var gain: float = _input_vol_slider.value / 100.0
		display_rms = rms * gain
	_mic_test_bar.value = pow(clampf(display_rms / 0.1, 0.0, 1.0), 0.4)
	# Bar color: green when above threshold, gray when below
	var thr: float = Config.voice.get_speaking_threshold()
	var above_thr: bool = display_rms > thr
	if above_thr:
		_bar_fill.bg_color = ThemeManager.get_color("success")
	else:
		_bar_fill.bg_color = ThemeManager.get_color("button_hover")
	# Gate monitor output: mute when below threshold or monitor disabled.
	if OS.get_name() == "Web":
		_web_mic.set_monitor_gate(
			_mic_monitor_cb.button_pressed and above_thr
		)
	elif _mic_test_bus_idx >= 0:
		var should_mute: bool = (
			not _mic_monitor_cb.button_pressed or not above_thr
		)
		AudioServer.set_bus_mute(_mic_test_bus_idx, should_mute)

func _exit_tree() -> void:
	_cleanup_mic_test()

# --- Sound page ---
func _build_sound_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Sound"))

	vbox.add_child(_section_label(tr("VOLUME")))
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

	vbox.add_child(_section_label(tr("SOUND EVENTS")))
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
		cb.text = tr(slabel)
		cb.button_pressed = Config.is_sound_enabled(sname)
		cb.toggled.connect(func(pressed: bool) -> void:
			Config.set_sound_enabled(sname, pressed)
		)
		vbox.add_child(cb)

	return vbox

# --- Appearance page ---

func _build_appearance_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Appearance"))

	# Theme preset
	vbox.add_child(_section_label(tr("THEME")))
	_theme_dropdown = OptionButton.new()
	var preset_names: Array = ThemeManager.get_preset_names()
	var preset_labels := {
		"dark": tr("Dark"), "light": tr("Light"), "nord": tr("Nord"),
		"monokai": tr("Monokai"), "solarized": tr("Solarized"),
	}
	for pname in preset_names:
		_theme_dropdown.add_item(preset_labels.get(pname, pname))
	_theme_dropdown.add_item(tr("Custom"))
	# Select current preset
	var current_preset: String = Config.get_theme_preset()
	var preset_idx: int = preset_names.find(current_preset)
	if current_preset == "custom":
		_theme_dropdown.selected = preset_names.size()
	elif preset_idx >= 0:
		_theme_dropdown.selected = preset_idx
	_theme_dropdown.item_selected.connect(_on_theme_preset_changed)
	vbox.add_child(_theme_dropdown)

	# Theme preview swatches
	_theme_preview_row = HBoxContainer.new()
	_theme_preview_row.add_theme_constant_override("separation", 4)
	vbox.add_child(_theme_preview_row)
	_update_theme_preview()

	# Custom color pickers (visible only when "Custom" is selected)
	_custom_colors_container = VBoxContainer.new()
	_custom_colors_container.add_theme_constant_override("separation", 8)
	_custom_colors_container.visible = (current_preset == "custom")
	vbox.add_child(_custom_colors_container)

	var editable_keys := [
		["accent", tr("Accent")],
		["text_body", tr("Text")],
		["text_muted", tr("Muted Text")],
		["error", tr("Error / Danger")],
		["success", tr("Success")],
		["panel_bg", tr("Panel Background")],
		["nav_bg", tr("Navigation Background")],
		["input_bg", tr("Input Background")],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	_custom_colors_container.add_child(grid)

	for entry in editable_keys:
		var key: String = entry[0]
		var label_text: String = entry[1]
		var lbl := Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 13)
		grid.add_child(lbl)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(48, 28)
		picker.color = ThemeManager.get_color(key)
		picker.edit_alpha = false
		picker.color_changed.connect(_on_custom_color_changed.bind(key))
		grid.add_child(picker)
		_color_pickers[key] = picker

	# Theme sharing buttons
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 8)
	_custom_colors_container.add_child(share_row)

	var copy_btn := SettingsBase.create_secondary_button(tr("Copy Theme"))
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(ThemeManager.export_theme_string())
	)
	share_row.add_child(copy_btn)

	var paste_btn := SettingsBase.create_secondary_button(tr("Paste Theme"))
	paste_btn.pressed.connect(func() -> void:
		var clip: String = DisplayServer.clipboard_get()
		if ThemeManager.import_theme_string(clip):
			_theme_dropdown.selected = _theme_dropdown.item_count - 1
			_custom_colors_container.visible = true
			_refresh_color_pickers()
	)
	share_row.add_child(paste_btn)

	var reset_btn := SettingsBase.create_secondary_button(tr("Reset to Preset"))
	reset_btn.pressed.connect(func() -> void:
		ThemeManager.apply_preset("dark")
		_theme_dropdown.selected = 0
		_custom_colors_container.visible = false
		_refresh_color_pickers()
	)
	_custom_colors_container.add_child(reset_btn)

	# Separator
	vbox.add_child(HSeparator.new())

	# Reduce motion
	vbox.add_child(_section_label(tr("ACCESSIBILITY")))
	var motion_cb := CheckBox.new()
	motion_cb.text = tr("Reduce motion")
	motion_cb.button_pressed = Config.get_reduced_motion()
	motion_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_reduced_motion(pressed)
	)
	vbox.add_child(motion_cb)

	# Emoji skin tone
	vbox.add_child(_section_label(tr("EMOJI SKIN TONE")))
	var tone_dropdown := OptionButton.new()
	tone_dropdown.add_item(tr("Default"))
	tone_dropdown.add_item(tr("Light"))
	tone_dropdown.add_item(tr("Medium-Light"))
	tone_dropdown.add_item(tr("Medium"))
	tone_dropdown.add_item(tr("Medium-Dark"))
	tone_dropdown.add_item(tr("Dark"))
	tone_dropdown.selected = Config.get_emoji_skin_tone()
	tone_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_emoji_skin_tone(idx)
	)
	vbox.add_child(tone_dropdown)

	# Language
	vbox.add_child(_section_label(tr("LANGUAGE")))
	var locale_dropdown := OptionButton.new()
	var locale_codes := ["en", "fr", "de", "es", "pt", "ja", "zh", "ko", "ar", "ru", "sv"]
	var locale_names := [
		"English", "Français", "Deutsch", "Español",
		"Português", "日本語", "中文", "한국어", "العربية", "Русский",
		"Svenska",
	]
	for i in locale_names.size():
		locale_dropdown.add_item(locale_names[i])
	var current_locale: String = Config.get_locale()
	var loc_idx: int = locale_codes.find(current_locale)
	if loc_idx >= 0:
		locale_dropdown.selected = loc_idx
	locale_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_locale(locale_codes[idx])
	)
	vbox.add_child(locale_dropdown)

	return vbox


func _on_theme_preset_changed(idx: int) -> void:
	var preset_names: Array = ThemeManager.get_preset_names()
	if idx < preset_names.size():
		ThemeManager.apply_preset(preset_names[idx])
		_custom_colors_container.visible = false
	else:
		# "Custom" selected — keep current palette, show pickers
		_custom_colors_container.visible = true
		Config.set_theme_preset("custom")
		# Save current palette as custom starting point
		var palette: Dictionary = ThemeManager.get_palette()
		var save_dict := {}
		for key in palette:
			save_dict[key] = palette[key].to_html(true)
		Config.set_custom_palette(save_dict)
	_refresh_color_pickers()


func _on_custom_color_changed(color: Color, key: String) -> void:
	ThemeManager.apply_custom_color(key, color)


func _refresh_color_pickers() -> void:
	for key in _color_pickers:
		_color_pickers[key].color = ThemeManager.get_color(key)
	_update_theme_preview()


func _update_theme_preview() -> void:
	if _theme_preview_row == null:
		return
	NodeUtils.free_children(_theme_preview_row)
	var preview_keys := [
		[tr("Accent"), "accent"],
		[tr("Text"), "text_body"],
		[tr("Muted"), "text_muted"],
		[tr("Panel"), "panel_bg"],
		[tr("Nav"), "nav_bg"],
		[tr("Input"), "input_bg"],
		[tr("Error"), "error"],
		[tr("Success"), "success"],
	]
	for entry in preview_keys:
		var swatch_col := VBoxContainer.new()
		swatch_col.add_theme_constant_override("separation", 2)
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(28, 28)
		rect.color = ThemeManager.get_color(entry[1])
		swatch_col.add_child(rect)
		var lbl := Label.new()
		lbl.text = entry[0]
		ThemeManager.style_label(lbl, 10, "text_muted")
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swatch_col.add_child(lbl)
		_theme_preview_row.add_child(swatch_col)

# --- Notifications page (trimmed — global only) ---
func _build_notifications_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Notifications"))

	var suppress_cb := CheckBox.new()
	suppress_cb.text = tr("Suppress @everyone and @here")
	suppress_cb.button_pressed = Config.get_suppress_everyone()
	suppress_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_suppress_everyone(pressed)
	)
	vbox.add_child(suppress_cb)

	# Idle timeout
	vbox.add_child(_section_label(tr("IDLE TIMEOUT")))
	_idle_dropdown = OptionButton.new()
	_idle_dropdown.add_item(tr("Disabled"))
	_idle_dropdown.add_item(tr("1 minute"))
	_idle_dropdown.add_item(tr("5 minutes"))
	_idle_dropdown.add_item(tr("10 minutes"))
	_idle_dropdown.add_item(tr("30 minutes"))
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
	vbox.add_child(_section_label(tr("ERROR REPORTING")))
	var error_cb := CheckBox.new()
	error_cb.text = tr("Send anonymous crash and error reports")
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
	_updates_pg = AppSettingsUpdatesPage.new(
		self, _page_vbox, _section_label,
	)
	return _updates_pg.build()

# --- About page ---
func _build_about_page() -> VBoxContainer:
	_about_pg = AppSettingsAboutPage.new(
		self, _page_vbox, _section_label,
	)
	return _about_pg.build()

# --- Developer page ---
func _build_developer_page() -> VBoxContainer:
	_developer_pg = AppSettingsDeveloperPage.new(
		self, _page_vbox, _section_label,
	)
	return _developer_pg.build()

# --- Instance Admin page ---
func _build_admin_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Instance Admin"))

	var desc := Label.new()
	desc.text = tr("You are an instance administrator.")
	desc.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(desc)

	var open_btn := SettingsBase.create_action_button(
		tr("Open Server Management")
	)
	open_btn.pressed.connect(func() -> void:
		var panel := ServerManagementPanel.instantiate()
		get_tree().root.add_child(panel)
		queue_free()
	)
	vbox.add_child(open_btn)

	return vbox
