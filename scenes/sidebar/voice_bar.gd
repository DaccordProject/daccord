extends PanelContainer

const AppSettingsScene := preload("res://scenes/user/app_settings.tscn")
const SoundboardPanelScene := preload("res://scenes/soundboard/soundboard_panel.tscn")
const ActivityModalScript := preload("res://scenes/plugins/activity_modal.gd")

const ICON_MIC := preload("res://assets/theme/icons/microphone.svg")
const ICON_MIC_OFF := preload("res://assets/theme/icons/microphone_off.svg")
const ICON_HEADPHONES := preload("res://assets/theme/icons/headphones.svg")
const ICON_HEADPHONES_OFF := preload("res://assets/theme/icons/headphones_off.svg")
const ICON_CAMERA := preload("res://assets/theme/icons/camera.svg")
const ICON_CAMERA_OFF := preload("res://assets/theme/icons/camera_off.svg")
const ICON_SCREEN_SHARE := preload("res://assets/theme/icons/screen_share.svg")
const ICON_SCREEN_SHARE_OFF := preload(
	"res://assets/theme/icons/screen_share_off.svg"
)

var _screen_picker_scene: PackedScene
var _soundboard_panel: PanelContainer = null
var _saved_channel_label: String = ""
var _error_tween: Tween
var _pulse_tween: Tween

@onready var status_row: HBoxContainer = $VBox/StatusRow
@onready var channel_label: Label = $VBox/StatusRow/ChannelLabel
@onready var status_dot: ColorRect = $VBox/StatusRow/StatusDot
@onready var mute_btn: Button = $VBox/ButtonRow/MuteBtn
@onready var deafen_btn: Button = $VBox/ButtonRow/DeafenBtn
@onready var video_btn: Button = $VBox/ButtonRow/VideoBtn
@onready var share_btn: Button = $VBox/ButtonRow/ShareBtn
@onready var activity_btn: Button = $VBox/ButtonRow/ActivityBtn
@onready var sfx_btn: Button = $VBox/ButtonRow/SfxBtn
@onready var settings_btn: Button = $VBox/ButtonRow/SettingsBtn
@onready var disconnect_btn: Button = $VBox/ButtonRow/DisconnectBtn

func _ready() -> void:
	visible = false
	status_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	status_row.gui_input.connect(_on_status_row_input)
	mute_btn.pressed.connect(_on_mute_pressed)
	deafen_btn.pressed.connect(_on_deafen_pressed)
	video_btn.pressed.connect(_on_video_pressed)
	share_btn.pressed.connect(_on_share_pressed)
	sfx_btn.pressed.connect(_on_sfx_pressed)
	activity_btn.pressed.connect(_on_activity_pressed)
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
	AppState.reduce_motion_changed.connect(_on_reduce_motion_changed)
	if OS.get_name() == "Web":
		share_btn.visible = false
	else:
		_screen_picker_scene = load("res://scenes/sidebar/screen_picker_dialog.tscn")
	add_to_group("themed")

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("nav_bg")
	if visible:
		_update_button_visuals()
	ThemeManager.apply_font_colors(self)

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
		"font_color", ThemeManager.get_color("warning")
	)
	status_dot.color = ThemeManager.get_color("warning")
	_start_pulse()
	sfx_btn.visible = Client.has_permission(
		AppState.voice_space_id,
		AccordPermission.USE_SOUNDBOARD,
	)
	_update_button_visuals()

func _on_status_row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AppState.open_voice_view()

func _on_voice_left(_channel_id: String) -> void:
	_stop_pulse()
	visible = false
	_close_soundboard_panel()

func _on_voice_error(error: String) -> void:
	if not visible:
		return
	_saved_channel_label = channel_label.text
	channel_label.text = error
	status_dot.color = ThemeManager.get_color("error")
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	_error_tween = create_tween()
	_error_tween.tween_interval(4.0)
	_error_tween.tween_callback(_clear_voice_error)

func _clear_voice_error() -> void:
	if not visible:
		return
	channel_label.text = _saved_channel_label
	status_dot.color = ThemeManager.get_color("success")

func _on_session_state_changed(state: int) -> void:
	if not visible:
		return
	match state:
		ClientModels.VoiceSessionState.CONNECTING:
			_stop_pulse()
			channel_label.text = "Connecting..."
			channel_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("warning")
			)
			status_dot.color = ThemeManager.get_color("warning")
			_start_pulse()
		ClientModels.VoiceSessionState.CONNECTED:
			_stop_pulse()
			channel_label.text = _saved_channel_label
			channel_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("success")
			)
			status_dot.color = ThemeManager.get_color("success")
			status_dot.modulate.a = 1.0
		ClientModels.VoiceSessionState.RECONNECTING:
			_stop_pulse()
			_saved_channel_label = channel_label.text
			channel_label.text = "Reconnecting..."
			channel_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("warning")
			)
			status_dot.color = ThemeManager.get_color("warning")
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
		var picker := _screen_picker_scene.instantiate()
		picker.source_selected.connect(_on_screen_source_selected)
		get_tree().root.add_child(picker)

func _on_screen_source_selected(source: Dictionary) -> void:
	Client.start_screen_share(source)

func _on_activity_pressed() -> void:
	var modal: ColorRect = ActivityModalScript.new()
	get_tree().root.add_child(modal)
	modal.setup(AppState.voice_space_id, AppState.voice_channel_id)
	modal.activity_launched.connect(_on_activity_launched)

func _on_activity_launched(plugin_id: String, channel_id: String) -> void:
	Client.plugins.launch_activity(plugin_id, channel_id)

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
		mute_btn.icon = ICON_MIC_OFF
		mute_btn.tooltip_text = "Unmute"
		mute_btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style(Color(ThemeManager.get_color("error"), 0.3), 4))
	else:
		mute_btn.icon = ICON_MIC
		mute_btn.tooltip_text = "Mute"
		mute_btn.remove_theme_stylebox_override("normal")

	# Deafen button
	if AppState.is_voice_deafened:
		deafen_btn.icon = ICON_HEADPHONES_OFF
		deafen_btn.tooltip_text = "Undeafen"
		deafen_btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style(Color(ThemeManager.get_color("error"), 0.3), 4))
	else:
		deafen_btn.icon = ICON_HEADPHONES
		deafen_btn.tooltip_text = "Deafen"
		deafen_btn.remove_theme_stylebox_override("normal")

	# Video button (green when active, disabled when no camera)
	var cam_available := _has_camera()
	video_btn.disabled = not cam_available
	if not cam_available:
		video_btn.tooltip_text = "No camera detected"
	elif AppState.is_video_enabled:
		video_btn.icon = ICON_CAMERA_OFF
		video_btn.tooltip_text = "Stop Camera"
		video_btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style(Color(ThemeManager.get_color("success"), 0.3), 4))
	else:
		video_btn.icon = ICON_CAMERA
		video_btn.tooltip_text = "Camera"
		video_btn.remove_theme_stylebox_override("normal")

	# Share button (green when active)
	if AppState.is_screen_sharing:
		share_btn.icon = ICON_SCREEN_SHARE_OFF
		share_btn.tooltip_text = "Stop Sharing"
		share_btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style(Color(ThemeManager.get_color("success"), 0.3), 4))
	else:
		share_btn.icon = ICON_SCREEN_SHARE
		share_btn.tooltip_text = "Screen Share"
		share_btn.remove_theme_stylebox_override("normal")

func _has_camera() -> bool:
	if OS.get_name() == "Linux":
		if not DirAccess.dir_exists_absolute("/sys/class/video4linux"):
			return false
		var entries: PackedStringArray = DirAccess.get_directories_at(
			"/sys/class/video4linux"
		)
		return entries.size() > 0
	return true

func _on_reduce_motion_changed(enabled: bool) -> void:
	if enabled:
		_stop_pulse()
