extends PanelContainer

const ScreenPickerDialog := preload("res://scenes/sidebar/screen_picker_dialog.tscn")
const AppSettingsScene := preload("res://scenes/user/app_settings.tscn")
const SoundboardPanelScene := preload("res://scenes/soundboard/soundboard_panel.tscn")

var _soundboard_panel: PanelContainer = null
var _saved_channel_label: String = ""
var _error_tween: Tween
var _pulse_tween: Tween

@onready var channel_label: Label = $VBox/StatusRow/ChannelLabel
@onready var status_dot: ColorRect = $VBox/StatusRow/StatusDot
@onready var mute_btn: Button = $VBox/ButtonRow/MuteBtn
@onready var deafen_btn: Button = $VBox/ButtonRow/DeafenBtn
@onready var video_btn: Button = $VBox/ButtonRow/VideoBtn
@onready var share_btn: Button = $VBox/ButtonRow/ShareBtn
@onready var sfx_btn: Button = $VBox/ButtonRow/SfxBtn
@onready var settings_btn: Button = $VBox/ButtonRow/SettingsBtn
@onready var disconnect_btn: Button = $VBox/ButtonRow/DisconnectBtn

func _ready() -> void:
	visible = false
	mute_btn.pressed.connect(_on_mute_pressed)
	deafen_btn.pressed.connect(_on_deafen_pressed)
	video_btn.pressed.connect(_on_video_pressed)
	share_btn.pressed.connect(_on_share_pressed)
	sfx_btn.pressed.connect(_on_sfx_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	disconnect_btn.pressed.connect(_on_disconnect_pressed)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.voice_mute_changed.connect(_on_mute_changed)
	AppState.voice_deafen_changed.connect(_on_deafen_changed)
	AppState.video_enabled_changed.connect(_on_video_changed)
	AppState.screen_share_changed.connect(_on_screen_share_changed)
	AppState.voice_error.connect(_on_voice_error)
	AppState.voice_session_state_changed.connect(_on_session_state_changed)

func _on_voice_joined(channel_id: String) -> void:
	visible = true
	# Look up channel name and save it for state transitions
	var channels: Array = Client.get_channels_for_space(AppState.voice_space_id)
	var ch_name := "Voice Connected"
	for ch in channels:
		if ch.get("id", "") == channel_id:
			ch_name = ch.get("name", "Voice Connected")
			break
	_saved_channel_label = ch_name
	# Show connecting state until LiveKit session confirms CONNECTED
	channel_label.text = "Connecting..."
	channel_label.add_theme_color_override(
		"font_color", Color(0.98, 0.82, 0.24)
	)
	status_dot.color = Color(0.98, 0.82, 0.24)
	_start_pulse()
	sfx_btn.visible = Client.has_permission(
		AppState.voice_space_id,
		AccordPermission.USE_SOUNDBOARD,
	)
	_update_button_visuals()

func _on_voice_left(_channel_id: String) -> void:
	_stop_pulse()
	visible = false
	_close_soundboard_panel()

func _on_voice_error(error: String) -> void:
	if not visible:
		return
	_saved_channel_label = channel_label.text
	channel_label.text = error
	status_dot.color = Color(0.929, 0.259, 0.271)
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	_error_tween = create_tween()
	_error_tween.tween_interval(4.0)
	_error_tween.tween_callback(_clear_voice_error)

func _clear_voice_error() -> void:
	if not visible:
		return
	channel_label.text = _saved_channel_label
	status_dot.color = Color(0.231, 0.647, 0.365)

func _on_session_state_changed(state: int) -> void:
	if not visible:
		return
	match state:
		LiveKitAdapter.State.CONNECTING:
			_stop_pulse()
			channel_label.text = "Connecting..."
			channel_label.add_theme_color_override(
				"font_color", Color(0.98, 0.82, 0.24)
			)
			status_dot.color = Color(0.98, 0.82, 0.24)
			_start_pulse()
		LiveKitAdapter.State.CONNECTED:
			_stop_pulse()
			channel_label.text = _saved_channel_label
			channel_label.add_theme_color_override(
				"font_color", Color(0.231, 0.647, 0.365)
			)
			status_dot.color = Color(0.231, 0.647, 0.365)
			status_dot.modulate.a = 1.0
		LiveKitAdapter.State.RECONNECTING:
			_stop_pulse()
			_saved_channel_label = channel_label.text
			channel_label.text = "Reconnecting..."
			channel_label.add_theme_color_override(
				"font_color", Color(0.96, 0.59, 0.15)
			)
			status_dot.color = Color(0.96, 0.59, 0.15)
			_start_pulse()

func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(status_dot, "modulate:a", 0.3, 0.6)
	_pulse_tween.tween_property(status_dot, "modulate:a", 1.0, 0.6)

func _stop_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	status_dot.modulate.a = 1.0

func _on_mute_pressed() -> void:
	Client.set_voice_muted(not AppState.is_voice_muted)

func _on_deafen_pressed() -> void:
	Client.set_voice_deafened(not AppState.is_voice_deafened)

func _on_video_pressed() -> void:
	Client.toggle_video()

func _on_share_pressed() -> void:
	if AppState.is_screen_sharing:
		Client.stop_screen_share()
	else:
		var picker := ScreenPickerDialog.instantiate()
		picker.source_selected.connect(_on_screen_source_selected)
		get_tree().root.add_child(picker)

func _on_screen_source_selected(
	source_type: String, source_id: int,
) -> void:
	Client.start_screen_share(source_type, source_id)

func _on_sfx_pressed() -> void:
	if _soundboard_panel != null and is_instance_valid(_soundboard_panel):
		_close_soundboard_panel()
		return
	_soundboard_panel = SoundboardPanelScene.instantiate()
	add_child(_soundboard_panel)
	_soundboard_panel.setup(AppState.voice_space_id)
	_soundboard_panel.tree_exited.connect(
		func() -> void: _soundboard_panel = null
	)
	# Position above voice bar after layout settles
	await get_tree().process_frame
	if _soundboard_panel != null and is_instance_valid(_soundboard_panel):
		_soundboard_panel.position = Vector2(
			0, -_soundboard_panel.size.y - 4
		)

func _close_soundboard_panel() -> void:
	if _soundboard_panel != null and is_instance_valid(_soundboard_panel):
		_soundboard_panel.close()
		_soundboard_panel = null

func _on_settings_pressed() -> void:
	var settings: ColorRect = AppSettingsScene.instantiate()
	settings.initial_page = 1  # Voice & Video
	get_tree().root.add_child(settings)

func _on_disconnect_pressed() -> void:
	Client.leave_voice_channel()

func _on_mute_changed(_is_muted: bool) -> void:
	_update_button_visuals()

func _on_deafen_changed(_is_deafened: bool) -> void:
	_update_button_visuals()

func _on_video_changed(_is_enabled: bool) -> void:
	_update_button_visuals()

func _on_screen_share_changed(_is_sharing: bool) -> void:
	_update_button_visuals()

func _update_button_visuals() -> void:
	# Mute button
	if AppState.is_voice_muted:
		mute_btn.text = "Mic Off"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.929, 0.259, 0.271, 0.3)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		mute_btn.add_theme_stylebox_override("normal", style)
	else:
		mute_btn.text = "Mic"
		mute_btn.remove_theme_stylebox_override("normal")

	# Deafen button
	if AppState.is_voice_deafened:
		deafen_btn.text = "Deaf"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.929, 0.259, 0.271, 0.3)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		deafen_btn.add_theme_stylebox_override("normal", style)
	else:
		deafen_btn.text = "Deaf"
		deafen_btn.remove_theme_stylebox_override("normal")

	# Video button (green when active)
	if AppState.is_video_enabled:
		video_btn.text = "Cam On"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.231, 0.647, 0.365, 0.3)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		video_btn.add_theme_stylebox_override("normal", style)
	else:
		video_btn.text = "Cam"
		video_btn.remove_theme_stylebox_override("normal")

	# Share button (green when active)
	if AppState.is_screen_sharing:
		share_btn.text = "Sharing"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.231, 0.647, 0.365, 0.3)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		share_btn.add_theme_stylebox_override("normal", style)
	else:
		share_btn.text = "Share"
		share_btn.remove_theme_stylebox_override("normal")
