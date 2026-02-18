extends PanelContainer

const ScreenPickerDialog := preload("res://scenes/sidebar/screen_picker_dialog.tscn")
const VoiceSettingsDialog := preload("res://scenes/sidebar/voice_settings_dialog.tscn")

@onready var channel_label: Label = $VBox/StatusRow/ChannelLabel
@onready var status_dot: ColorRect = $VBox/StatusRow/StatusDot
@onready var mute_btn: Button = $VBox/ButtonRow/MuteBtn
@onready var deafen_btn: Button = $VBox/ButtonRow/DeafenBtn
@onready var video_btn: Button = $VBox/ButtonRow/VideoBtn
@onready var share_btn: Button = $VBox/ButtonRow/ShareBtn
@onready var settings_btn: Button = $VBox/ButtonRow/SettingsBtn
@onready var disconnect_btn: Button = $VBox/ButtonRow/DisconnectBtn

func _ready() -> void:
	visible = false
	mute_btn.pressed.connect(_on_mute_pressed)
	deafen_btn.pressed.connect(_on_deafen_pressed)
	video_btn.pressed.connect(_on_video_pressed)
	share_btn.pressed.connect(_on_share_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	disconnect_btn.pressed.connect(_on_disconnect_pressed)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.voice_mute_changed.connect(_on_mute_changed)
	AppState.voice_deafen_changed.connect(_on_deafen_changed)
	AppState.video_enabled_changed.connect(_on_video_changed)
	AppState.screen_share_changed.connect(_on_screen_share_changed)

func _on_voice_joined(channel_id: String) -> void:
	visible = true
	# Look up channel name
	var channels: Array = Client.get_channels_for_guild(AppState.voice_guild_id)
	var ch_name := "Voice Connected"
	for ch in channels:
		if ch.get("id", "") == channel_id:
			ch_name = ch.get("name", "Voice Connected")
			break
	channel_label.text = ch_name
	status_dot.color = Color(0.231, 0.647, 0.365)
	_update_button_visuals()

func _on_voice_left(_channel_id: String) -> void:
	visible = false

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

func _on_settings_pressed() -> void:
	var dialog := VoiceSettingsDialog.instantiate()
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

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
