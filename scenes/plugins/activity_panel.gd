extends PanelContainer

## Displays the active activity: lobby, running viewport, or ended state.
## Integrated into the main window's content body alongside MessageView.

const ActivityLobbyScript := preload(
	"res://scenes/plugins/activity_lobby.gd"
)

var _plugin_id: String = ""
var _manifest: Dictionary = {}
var _is_host: bool = false

var _header: HBoxContainer
var _name_label: Label
var _runtime_badge: Label
var _participant_label: Label
var _leave_btn: Button
var _start_btn: Button

var _content_stack: Control
var _lobby: VBoxContainer
var _viewport_rect: TextureRect
var _ended_label: Label
var _progress_bar: ProgressBar

var _footer: HBoxContainer
var _role_label: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(300, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_to_group("themed")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# --- Header ---
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	var header_panel := PanelContainer.new()
	var header_style := ThemeManager.make_flat_style("nav_bg", 0, [12, 8, 12, 8])
	header_panel.add_theme_stylebox_override("panel", header_style)
	header_panel.add_child(_header)
	vbox.add_child(header_panel)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_name_label)

	_runtime_badge = Label.new()
	_runtime_badge.add_theme_font_size_override("font_size", 11)
	_runtime_badge.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_header.add_child(_runtime_badge)

	_participant_label = Label.new()
	_participant_label.add_theme_font_size_override("font_size", 12)
	_participant_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_header.add_child(_participant_label)

	_start_btn = Button.new()
	_start_btn.text = "Start"
	_start_btn.custom_minimum_size = Vector2(60, 32)
	var start_style := ThemeManager.make_flat_style("accent", 4, [8, 4, 8, 4])
	_start_btn.add_theme_stylebox_override("normal", start_style)
	_start_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	_start_btn.visible = false
	_start_btn.pressed.connect(_on_start_pressed)
	_header.add_child(_start_btn)

	_leave_btn = Button.new()
	_leave_btn.text = "Leave"
	_leave_btn.custom_minimum_size = Vector2(60, 32)
	var leave_style := ThemeManager.make_flat_style(
		Color(ThemeManager.get_color("error"), 0.3), 4, [8, 4, 8, 4]
	)
	_leave_btn.add_theme_stylebox_override("normal", leave_style)
	_leave_btn.pressed.connect(_on_leave_pressed)
	_header.add_child(_leave_btn)

	# --- Content area ---
	_content_stack = Control.new()
	_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_stack.clip_contents = true
	vbox.add_child(_content_stack)

	# Lobby
	_lobby = ActivityLobbyScript.new()
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby.start_requested.connect(_on_start_pressed)
	_lobby.visible = false
	_content_stack.add_child(_lobby)

	# Running viewport
	_viewport_rect = TextureRect.new()
	_viewport_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewport_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_viewport_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_rect.gui_input.connect(_on_viewport_input)
	_viewport_rect.visible = false
	_content_stack.add_child(_viewport_rect)

	# Ended message
	_ended_label = Label.new()
	_ended_label.text = "Activity ended."
	_ended_label.set_anchors_preset(Control.PRESET_CENTER)
	_ended_label.add_theme_font_size_override("font_size", 18)
	_ended_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_ended_label.visible = false
	_content_stack.add_child(_ended_label)

	# Download progress
	_progress_bar = ProgressBar.new()
	_progress_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_progress_bar.custom_minimum_size = Vector2(200, 20)
	_progress_bar.visible = false
	_content_stack.add_child(_progress_bar)

	# --- Footer ---
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	var footer_panel := PanelContainer.new()
	var footer_style := ThemeManager.make_flat_style("nav_bg", 0, [12, 6, 12, 6])
	footer_panel.add_theme_stylebox_override("panel", footer_style)
	footer_panel.add_child(_footer)
	vbox.add_child(footer_panel)

	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 12)
	_role_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_footer.add_child(_role_label)

	# Connect AppState signals
	AppState.activity_session_state_changed.connect(_on_state_changed)
	AppState.activity_role_changed.connect(_on_role_changed)
	AppState.activity_download_progress.connect(_on_download_progress)
	AppState.activity_ended.connect(_on_activity_ended)
	AppState.activity_started.connect(_on_activity_started)


func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("content_bg")
	ThemeManager.apply_font_colors(self)


func _on_activity_started(plugin_id: String, _channel_id: String) -> void:
	_plugin_id = plugin_id
	_manifest = Client.plugins.get_plugin(plugin_id)
	_is_host = true  # Creator is the host
	visible = true

	_name_label.text = _manifest.get("name", "Activity")
	_runtime_badge.text = _manifest.get("runtime", "").capitalize()
	_role_label.text = "Role: " + AppState.active_activity_role.capitalize()

	_update_state_view(AppState.active_activity_session_state)


func _update_state_view(state: String) -> void:
	_lobby.visible = false
	_viewport_rect.visible = false
	_ended_label.visible = false
	_start_btn.visible = false

	match state:
		"lobby":
			_lobby.visible = true
			_lobby.setup(_manifest, _is_host)
			_start_btn.visible = _is_host
		"running":
			_viewport_rect.visible = true
			var tex: ViewportTexture = Client.plugins.get_activity_viewport_texture()
			if tex != null:
				_viewport_rect.texture = tex
		"ended":
			_ended_label.visible = true


func _on_state_changed(plugin_id: String, state: String) -> void:
	if plugin_id != _plugin_id:
		return
	_update_state_view(state)


func _on_role_changed(
	plugin_id: String, user_id: String, role: String,
) -> void:
	if plugin_id != _plugin_id:
		return
	if user_id == Client.current_user.get("id", ""):
		_role_label.text = "Role: " + role.capitalize()


func _on_download_progress(plugin_id: String, progress: float) -> void:
	if plugin_id != _plugin_id:
		return
	if progress < 1.0:
		_progress_bar.visible = true
		_progress_bar.value = progress * 100.0
	else:
		_progress_bar.visible = false


func _on_activity_ended(plugin_id: String) -> void:
	if plugin_id != _plugin_id:
		return
	_update_state_view("ended")


func _on_leave_pressed() -> void:
	if _plugin_id.is_empty():
		return
	Client.plugins.stop_activity(_plugin_id)


func _on_start_pressed() -> void:
	Client.plugins.start_session()


func _on_viewport_input(event: InputEvent) -> void:
	Client.plugins.forward_activity_input(event)


func hide_panel() -> void:
	visible = false
	_plugin_id = ""
