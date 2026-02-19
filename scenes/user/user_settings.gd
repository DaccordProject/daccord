extends ColorRect

## Fullscreen user settings panel with left nav and right content area.

const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _nav_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_page: int = 0

# Page references
var _account_page: VBoxContainer
var _profile_page: VBoxContainer
var _voice_page: VBoxContainer
var _sound_page: VBoxContainer
var _notifications_page: VBoxContainer
var _password_page: VBoxContainer
var _delete_page: VBoxContainer
var _twofa_page: VBoxContainer
var _connections_page: VBoxContainer

# Profile page delegate
var _profile: UserSettingsProfile

# Password + Delete page delegate
var _danger: UserSettingsDanger

# 2FA page delegate
var _twofa: UserSettingsTwofa

# Notifications page fields
var _idle_dropdown: OptionButton

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.188, 0.196, 0.212)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)

	# Left nav panel
	var nav_panel := PanelContainer.new()
	nav_panel.custom_minimum_size = Vector2(200, 0)
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = Color(0.153, 0.161, 0.176)
	nav_panel.add_theme_stylebox_override("panel", nav_style)
	hbox.add_child(nav_panel)

	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nav_panel.add_child(nav_scroll)

	var nav_vbox := VBoxContainer.new()
	nav_vbox.add_theme_constant_override("separation", 2)
	nav_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 8)
	nav_margin.add_theme_constant_override("margin_right", 8)
	nav_margin.add_theme_constant_override("margin_top", 12)
	nav_margin.add_theme_constant_override("margin_bottom", 12)
	nav_margin.add_child(nav_vbox)
	nav_scroll.add_child(nav_margin)

	var sections := [
		"My Account", "Profile", "Voice & Video", "Sound",
		"Notifications", "Change Password", "Delete Account",
		"Two-Factor Auth", "Connections",
	]
	for i in sections.size():
		var btn := Button.new()
		btn.text = sections[i]
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_nav_pressed.bind(i))
		nav_vbox.add_child(btn)
		_nav_buttons.append(btn)

	# Close button at bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_vbox.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(queue_free)
	nav_vbox.add_child(close_btn)

	# Right content area
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(content_scroll)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_bottom", 20)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_margin)

	var content_stack := VBoxContainer.new()
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content_stack)

	# Build all pages
	_account_page = _build_account_page()
	_profile_page = _build_profile_page()
	_voice_page = _build_voice_page()
	_sound_page = _build_sound_page()
	_notifications_page = _build_notifications_page()
	_password_page = _build_password_page()
	_delete_page = _build_delete_page()
	_twofa_page = _build_twofa_page()
	_connections_page = _build_connections_page()

	_pages = [
		_account_page, _profile_page, _voice_page, _sound_page,
		_notifications_page, _password_page, _delete_page,
		_twofa_page, _connections_page,
	]
	for page in _pages:
		content_stack.add_child(page)
		page.visible = false

	_show_page(0)

func _on_nav_pressed(index: int) -> void:
	_show_page(index)

func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = (i == index)
	_current_page = index
	# Highlight active nav button
	for i in _nav_buttons.size():
		if i == index:
			_nav_buttons[i].add_theme_color_override(
				"font_color", Color.WHITE
			)
		else:
			_nav_buttons[i].remove_theme_color_override("font_color")

# --- My Account page ---

func _build_account_page() -> VBoxContainer:
	var vbox := _page_vbox("My Account")

	var user: Dictionary = Client.current_user
	var username_row := _labeled_value(
		"USERNAME", user.get("username", "")
	)
	vbox.add_child(username_row)

	var av: ColorRect = AvatarScene.instantiate()
	av.avatar_size = 80
	av.show_letter = true
	av.letter_font_size = 28
	av.custom_minimum_size = Vector2(80, 80)
	vbox.add_child(av)
	av.set_avatar_color(
		user.get("color", Color(0.345, 0.396, 0.949))
	)
	var dn: String = user.get("display_name", "")
	if dn.length() > 0:
		av.set_letter(dn[0].to_upper())
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		av.set_avatar_url(avatar_url)

	var created: String = user.get("created_at", "")
	if not created.is_empty():
		var t_idx := created.find("T")
		var date_str: String = created.substr(0, t_idx) if t_idx != -1 else created
		vbox.add_child(_labeled_value("ACCOUNT CREATED", date_str))

	var edit_btn := Button.new()
	edit_btn.text = "Edit Profile"
	edit_btn.pressed.connect(func() -> void:
		_show_page(1)
	)
	vbox.add_child(edit_btn)

	return vbox

# --- Profile page ---

func _build_profile_page() -> VBoxContainer:
	var vbox := _page_vbox("Profile")
	_profile = UserSettingsProfile.new()
	_profile.build(vbox, _section_label, _error_label, self)
	return vbox

# --- Voice & Video page ---

func _build_voice_page() -> VBoxContainer:
	var vbox := _page_vbox("Voice & Video")

	# Microphone
	vbox.add_child(_section_label("INPUT DEVICE"))
	var mic_dropdown := OptionButton.new()
	var input_devices := AudioServer.get_input_device_list()
	for dev in input_devices:
		mic_dropdown.add_item(dev)
	var saved_input: String = Config.get_voice_input_device()
	for i in mic_dropdown.item_count:
		if mic_dropdown.get_item_text(i) == saved_input:
			mic_dropdown.selected = i
			break
	mic_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_voice_input_device(
			mic_dropdown.get_item_text(idx)
		)
	)
	vbox.add_child(mic_dropdown)

	# Speaker
	vbox.add_child(_section_label("OUTPUT DEVICE"))
	var speaker_dropdown := OptionButton.new()
	var output_devices := AudioServer.get_output_device_list()
	for dev in output_devices:
		speaker_dropdown.add_item(dev)
	var saved_output: String = Config.get_voice_output_device()
	for i in speaker_dropdown.item_count:
		if speaker_dropdown.get_item_text(i) == saved_output:
			speaker_dropdown.selected = i
			break
	speaker_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_voice_output_device(
			speaker_dropdown.get_item_text(idx)
		)
	)
	vbox.add_child(speaker_dropdown)

	# Video resolution
	vbox.add_child(_section_label("VIDEO RESOLUTION"))
	var res_dropdown := OptionButton.new()
	res_dropdown.add_item("480p")
	res_dropdown.add_item("720p")
	res_dropdown.add_item("1080p")
	res_dropdown.selected = Config.get_video_resolution()
	res_dropdown.item_selected.connect(func(idx: int) -> void:
		Config.set_video_resolution(idx)
	)
	vbox.add_child(res_dropdown)

	# Video FPS
	vbox.add_child(_section_label("VIDEO FPS"))
	var fps_dropdown := OptionButton.new()
	fps_dropdown.add_item("15 FPS")
	fps_dropdown.add_item("30 FPS")
	fps_dropdown.add_item("60 FPS")
	var fps_val: int = Config.get_video_fps()
	match fps_val:
		15: fps_dropdown.selected = 0
		60: fps_dropdown.selected = 2
		_: fps_dropdown.selected = 1
	fps_dropdown.item_selected.connect(func(idx: int) -> void:
		var fps_map := [15, 30, 60]
		Config.set_video_fps(fps_map[idx])
	)
	vbox.add_child(fps_dropdown)

	return vbox

# --- Sound page ---

func _build_sound_page() -> VBoxContainer:
	var vbox := _page_vbox("Sound")

	vbox.add_child(_section_label("VOLUME"))
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = Config.get_sfx_volume()
	vol_slider.value_changed.connect(func(val: float) -> void:
		Config.set_sfx_volume(val)
	)
	vbox.add_child(vol_slider)

	vbox.add_child(_section_label("SOUND EVENTS"))
	var sound_events := [
		"message_received", "message_sent", "voice_join",
		"voice_leave", "notification",
	]
	for sname in sound_events:
		var cb := CheckBox.new()
		cb.text = sname.replace("_", " ").capitalize()
		cb.button_pressed = Config.is_sound_enabled(sname)
		cb.toggled.connect(func(pressed: bool) -> void:
			Config.set_sound_enabled(sname, pressed)
		)
		vbox.add_child(cb)

	return vbox

# --- Notifications page ---

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

	# Per-server mute toggles
	vbox.add_child(_section_label("SERVER MUTE"))
	for guild in Client.guilds:
		var gid: String = guild.get("id", "")
		var gname: String = guild.get("name", gid)
		var mute_cb := CheckBox.new()
		mute_cb.text = "Mute " + gname
		mute_cb.button_pressed = Config.is_server_muted(gid)
		mute_cb.toggled.connect(func(pressed: bool) -> void:
			Config.set_server_muted(gid, pressed)
		)
		vbox.add_child(mute_cb)

	return vbox

# --- Change Password page ---

func _build_password_page() -> VBoxContainer:
	var vbox := _page_vbox("Change Password")
	_danger = UserSettingsDanger.new()
	_danger.build_password_page(vbox, _section_label, _error_label)
	return vbox

# --- Delete Account page ---

func _build_delete_page() -> VBoxContainer:
	var vbox := _page_vbox("Delete Account")
	if _danger == null:
		_danger = UserSettingsDanger.new()
	_danger.build_delete_page(
		vbox, _section_label, _error_label, get_tree()
	)
	return vbox

# --- 2FA page ---

func _build_twofa_page() -> VBoxContainer:
	var vbox := _page_vbox("Two-Factor Authentication")
	_twofa = UserSettingsTwofa.new()
	_twofa.build(vbox, _section_label, _error_label)
	return vbox

# --- Connections page ---

func _build_connections_page() -> VBoxContainer:
	var vbox := _page_vbox("Connections")

	var loading := Label.new()
	loading.text = "Loading connections..."
	loading.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(loading)

	# Fetch connections async
	_fetch_connections(vbox, loading)

	return vbox

func _fetch_connections(
	vbox: VBoxContainer, loading: Label,
) -> void:
	var client: AccordClient = Client._first_connected_client()
	if client == null:
		loading.text = "Not connected"
		return
	var result: RestResult = await client.users.list_connections()
	loading.visible = false
	if not result.ok:
		var err_lbl := Label.new()
		err_lbl.text = "Failed to load connections"
		err_lbl.add_theme_color_override(
			"font_color", Color(0.929, 0.259, 0.271)
		)
		vbox.add_child(err_lbl)
		return
	var connections: Array = result.data if result.data is Array else []
	if connections.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No connections linked."
		none_lbl.add_theme_color_override(
			"font_color", Color(0.58, 0.608, 0.643)
		)
		vbox.add_child(none_lbl)
		return
	for conn in connections:
		if conn is Dictionary:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var service := Label.new()
			service.text = str(conn.get("type", "Unknown"))
			service.add_theme_font_size_override("font_size", 14)
			row.add_child(service)
			var name_lbl := Label.new()
			name_lbl.text = str(conn.get("name", ""))
			name_lbl.add_theme_color_override(
				"font_color", Color(0.58, 0.608, 0.643)
			)
			row.add_child(name_lbl)
			vbox.add_child(row)

# --- Helper builders ---

func _page_vbox(title_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	var sep := HSeparator.new()
	vbox.add_child(sep)
	return vbox

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	return lbl

func _labeled_value(label_text: String, value_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(_section_label(label_text))
	var val := Label.new()
	val.text = value_text
	vbox.add_child(val)
	return vbox

func _error_label() -> Label:
	var lbl := Label.new()
	lbl.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.visible = false
	return lbl

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
