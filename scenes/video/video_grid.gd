extends PanelContainer

enum GridMode { INLINE, FULL_AREA }

const VideoTileScene := preload(
	"res://scenes/video/video_tile.tscn"
)
const ActivityLobbyScene := preload(
	"res://scenes/plugins/activity_lobby.tscn"
)
const VerticalResizeHandle := preload(
	"res://scenes/video/vertical_resize_handle.gd"
)

var _mode: GridMode = GridMode.INLINE
var _rebuild_pending: bool = false

# Activity state
var _activity_plugin_id: String = ""
var _activity_manifest: Dictionary = {}
var _activity_is_host: bool = false
var _activity_container: Control = null
var _v_resize_handle: Control = null
# Pending activity (not yet joined)
var _pending_plugin_id: String = ""
var _pending_session_id: String = ""

@onready var spotlight_area: PanelContainer = $MainLayout/SpotlightArea
@onready var grid: GridContainer = $MainLayout/ParticipantGrid
@onready var _main_layout: VBoxContainer = $MainLayout

func _ready() -> void:
	visible = false
	add_to_group("themed")
	_apply_theme()
	AppState.video_enabled_changed.connect(
		_on_video_changed
	)
	AppState.screen_share_changed.connect(
		_on_video_changed
	)
	AppState.voice_state_updated.connect(
		_on_voice_state_updated
	)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.remote_track_received.connect(
		_on_remote_track_received
	)
	AppState.remote_track_removed.connect(
		_on_remote_track_removed
	)
	AppState.layout_mode_changed.connect(
		_on_layout_mode_changed
	)
	AppState.spotlight_changed.connect(
		_on_spotlight_changed
	)
	AppState.activity_started.connect(
		_on_activity_started
	)
	AppState.activity_ended.connect(
		_on_activity_ended
	)
	AppState.activity_session_state_changed.connect(
		_on_activity_state_changed
	)
	AppState.activity_role_changed.connect(
		_on_activity_role_changed
	)
	AppState.activity_download_progress.connect(
		_on_activity_download_progress
	)
	AppState.activity_available.connect(
		_on_activity_available
	)
	AppState.activity_participants_updated.connect(
		_on_activity_participants_updated
	)
	# Vertical resize handle between spotlight and grid
	_v_resize_handle = VerticalResizeHandle.new(
		spotlight_area, 100.0, 200.0, 0.7,
	)
	_v_resize_handle.visible = false
	_main_layout.add_child(_v_resize_handle)
	_main_layout.move_child(
		_v_resize_handle, spotlight_area.get_index() + 1
	)
	_update_grid_columns()

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("nav_bg")

func set_full_area(full: bool) -> void:
	if full:
		_mode = GridMode.FULL_AREA
		custom_minimum_size = Vector2.ZERO
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_mode = GridMode.INLINE
		custom_minimum_size = Vector2(0, 140)
		size_flags_vertical = 0
	_update_grid_columns()
	_rebuild()

func _on_video_changed(_value: bool) -> void:
	_schedule_rebuild()

func _on_voice_state_updated(_channel_id: String) -> void:
	if AppState.voice_channel_id.is_empty():
		return
	_schedule_rebuild()

func _on_voice_joined(_channel_id: String) -> void:
	_schedule_rebuild()

func _on_voice_left(_channel_id: String) -> void:
	_clear()
	visible = false

func _on_remote_track_received(
	_user_id: String,
	_track,
) -> void:
	_schedule_rebuild()

func _on_remote_track_removed(
	_user_id: String,
) -> void:
	_schedule_rebuild()

func _on_layout_mode_changed(
	_layout_mode: AppState.LayoutMode,
) -> void:
	_update_grid_columns()

func _on_spotlight_changed(_user_id: String) -> void:
	_schedule_rebuild()

# --- Activity signal handlers ---

func _on_activity_started(
	plugin_id: String, _channel_id: String,
) -> void:
	_activity_plugin_id = plugin_id
	_activity_manifest = Client.plugins.get_plugin(plugin_id)
	_activity_is_host = Client.plugins.is_activity_host()
	_pending_plugin_id = ""
	_pending_session_id = ""
	_schedule_rebuild()

func _on_activity_ended(plugin_id: String) -> void:
	if plugin_id != _activity_plugin_id:
		return
	_activity_plugin_id = ""
	_activity_manifest = {}
	_activity_is_host = false
	_pending_plugin_id = ""
	_pending_session_id = ""
	_schedule_rebuild()

func _on_activity_available(
	plugin_id: String, _channel_id: String,
	session_id: String,
) -> void:
	_pending_plugin_id = plugin_id
	_pending_session_id = session_id
	_schedule_rebuild()

func _on_activity_participants_updated(
	session_id: String, participants: Array,
) -> void:
	if _activity_container == null:
		return
	if session_id != AppState.active_activity_session_id:
		return
	var lobby: VBoxContainer = _activity_container.get_meta(
		"lobby", null
	)
	if lobby != null and lobby.has_method("update_participants"):
		lobby.update_participants(participants)

func _on_activity_state_changed(
	plugin_id: String, _state: String,
) -> void:
	if plugin_id != _activity_plugin_id:
		return
	_schedule_rebuild()

func _on_activity_role_changed(
	plugin_id: String, user_id: String, role: String,
) -> void:
	if plugin_id != _activity_plugin_id:
		return
	if user_id != Client.current_user.get("id", ""):
		return
	# Update the role label if the activity container exists
	if _activity_container == null:
		return
	var role_lbl: Label = _activity_container.get_meta(
		"role_label", null
	)
	if role_lbl:
		role_lbl.text = tr("Role: %s") % role.capitalize()

func _on_activity_download_progress(
	plugin_id: String, progress: float,
) -> void:
	if plugin_id != _activity_plugin_id:
		return
	if _activity_container == null:
		return
	var bar: ProgressBar = _activity_container.get_meta(
		"progress_bar", null
	)
	if bar == null:
		return
	if progress < 1.0:
		bar.visible = true
		bar.value = progress * 100.0
	else:
		bar.visible = false

func _has_activity() -> bool:
	return not _activity_plugin_id.is_empty()

func _has_pending_activity() -> bool:
	return not _pending_plugin_id.is_empty()

func _update_grid_columns() -> void:
	if _mode == GridMode.FULL_AREA:
		var has_focus := _has_activity() or _has_pending_activity()
		if has_focus or not AppState.spotlight_user_id.is_empty() or _has_screen_share():
			grid.columns = 99
		else:
			var count := _count_tiles()
			if count <= 1:
				grid.columns = 1
			elif count <= 4:
				grid.columns = 2
			elif count <= 9:
				grid.columns = 3
			elif count <= 16:
				grid.columns = 4
			else:
				grid.columns = 5
	else:
		match AppState.current_layout_mode:
			AppState.LayoutMode.COMPACT:
				grid.columns = 1
			AppState.LayoutMode.MEDIUM:
				grid.columns = 2
			AppState.LayoutMode.FULL:
				grid.columns = 2

func _has_screen_share() -> bool:
	if Client.get_screen_track() != null:
		return true
	var cid := AppState.voice_channel_id
	if cid.is_empty():
		return false
	var my_id: String = Client.current_user.get("id", "")
	var states: Array = Client.get_voice_users(cid)
	for state in states:
		var uid: String = state.get("user_id", "")
		if uid == my_id:
			continue
		if state.get("self_stream", false):
			return true
	return false

func _count_tiles() -> int:
	var count := 0
	var cid := AppState.voice_channel_id
	if cid.is_empty():
		return count
	if _mode == GridMode.FULL_AREA:
		var my_id: String = Client.current_user.get("id", "")
		var voice_states: Array = Client.get_voice_users(cid)
		count = voice_states.size()
		if Client.get_screen_track() != null:
			count += 1
		for state in voice_states:
			if state.get("user_id", "") != my_id and state.get("self_stream", false):
				count += 1
	else:
		if Client.get_camera_track() != null:
			count += 1
		if Client.get_screen_track() != null:
			count += 1
		var my_id: String = Client.current_user.get("id", "")
		var states: Array = Client.get_voice_users(cid)
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			if state.get("self_video", false) or state.get("self_stream", false):
				count += 1
	return count

func _clear() -> void:
	for child in grid.get_children():
		child.detach_stream()
		child.queue_free()
	for child in spotlight_area.get_children():
		if child.has_method("detach_stream"):
			child.detach_stream()
		child.queue_free()
	spotlight_area.visible = false
	if _v_resize_handle != null:
		_v_resize_handle.visible = false
	_activity_container = null

func _collect_tiles() -> Array:
	var tiles: Array = []
	var cid := AppState.voice_channel_id
	if cid.is_empty():
		return tiles

	var my_id: String = Client.current_user.get("id", "")
	var states: Array = Client.get_voice_users(cid)

	if _mode == GridMode.FULL_AREA:
		for state in states:
			var uid: String = state.get("user_id", "")
			var user: Dictionary = state.get("user", {})
			if user.is_empty():
				user = Client.get_user_by_id(uid)
			var track = null
			if uid == my_id:
				track = Client.get_camera_track()
			elif state.get("self_video", false):
				track = Client.get_remote_track(uid)
			tiles.append({
				"track": track,
				"user": user,
				"is_screen": false,
				"user_id": uid,
				"voice_state": state,
			})
		var screen_track = Client.get_screen_track()
		if screen_track != null:
			tiles.append({
				"track": screen_track,
				"user": Client.current_user,
				"is_screen": true,
				"user_id": my_id,
			})
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			if state.get("self_stream", false):
				var user: Dictionary = state.get("user", {})
				if user.is_empty():
					user = Client.get_user_by_id(uid)
				tiles.append({
					"track": Client.get_remote_track(uid),
					"user": user,
					"is_screen": true,
					"user_id": uid,
					"voice_state": state,
				})
	else:
		var cam_track = Client.get_camera_track()
		if cam_track != null:
			tiles.append({
				"track": cam_track,
				"user": Client.current_user,
				"is_screen": false,
				"user_id": my_id,
			})
		var screen_track = Client.get_screen_track()
		if screen_track != null:
			tiles.append({
				"track": screen_track,
				"user": Client.current_user,
				"is_screen": true,
				"user_id": my_id,
			})
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			var has_video: bool = state.get("self_video", false)
			var has_stream: bool = state.get("self_stream", false)
			if has_video or has_stream:
				var user: Dictionary = state.get("user", {})
				if user.is_empty():
					user = Client.get_user_by_id(uid)
				tiles.append({
					"track": Client.get_remote_track(uid),
					"user": user,
					"is_screen": has_stream and not has_video,
					"user_id": uid,
					"voice_state": state,
				})
	return tiles

func _schedule_rebuild() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		call_deferred("_do_rebuild")

func _do_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	_rebuild()

func _rebuild() -> void:
	_clear()
	var tiles := _collect_tiles()

	# Activity takes priority in FULL_AREA mode
	if _mode == GridMode.FULL_AREA and _has_activity():
		visible = true
		_rebuild_activity(tiles)
		_update_grid_columns()
		return

	# Show pending activity banner if available
	if _mode == GridMode.FULL_AREA and _has_pending_activity():
		visible = true
		_rebuild_pending_activity(tiles)
		_update_grid_columns()
		return

	if tiles.is_empty():
		visible = _mode == GridMode.FULL_AREA
		return

	visible = true

	var use_spotlight := false
	var spotlight_tile_idx := -1

	if _mode == GridMode.FULL_AREA:
		if not AppState.spotlight_user_id.is_empty():
			for i in tiles.size():
				if tiles[i]["user_id"] == AppState.spotlight_user_id:
					spotlight_tile_idx = i
					use_spotlight = true
					break
		if not use_spotlight:
			for i in tiles.size():
				if tiles[i]["is_screen"]:
					spotlight_tile_idx = i
					use_spotlight = true
					break

	if use_spotlight and spotlight_tile_idx >= 0:
		_rebuild_spotlight(tiles, spotlight_tile_idx)
	else:
		_rebuild_grid_only(tiles)

	_update_grid_columns()

func _rebuild_activity(tiles: Array) -> void:
	spotlight_area.visible = true
	_v_resize_handle.visible = true

	# Build activity content in a VBoxContainer inside spotlight
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spotlight_area.add_child(container)
	_activity_container = container

	# --- Header overlay ---
	var header := _build_activity_header()
	container.add_child(header)

	# --- Content area ---
	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	container.add_child(content)

	var session_state: String = AppState.active_activity_session_state
	match session_state:
		"lobby":
			var lobby: VBoxContainer = ActivityLobbyScene.instantiate()
			lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
			lobby.start_requested.connect(_on_activity_start)
			lobby.setup(_activity_manifest, _activity_is_host)
			content.add_child(lobby)
			container.set_meta("lobby", lobby)
		"running":
			var vp_rect := TextureRect.new()
			vp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			vp_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vp_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			vp_rect.mouse_filter = Control.MOUSE_FILTER_STOP
			vp_rect.gui_input.connect(_on_activity_viewport_input.bind(vp_rect))
			var tex: ViewportTexture = Client.plugins.get_activity_viewport_texture()
			if tex != null:
				vp_rect.texture = tex
			content.add_child(vp_rect)
		"ended":
			var ended := Label.new()
			ended.text = tr("Activity ended.")
			ended.set_anchors_preset(Control.PRESET_CENTER)
			ThemeManager.style_label(ended, 18, "text_muted")
			content.add_child(ended)

	# Download progress bar (hidden by default)
	var progress_bar := ProgressBar.new()
	progress_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	progress_bar.custom_minimum_size = Vector2(200, 20)
	progress_bar.visible = false
	content.add_child(progress_bar)
	container.set_meta("progress_bar", progress_bar)

	# --- Footer ---
	var footer := _build_activity_footer()
	container.add_child(footer)

	# All participants go in the grid strip below
	for tile_data in tiles:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tile_data)

func _rebuild_pending_activity(tiles: Array) -> void:
	spotlight_area.visible = true
	_v_resize_handle.visible = false

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 12)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	spotlight_area.add_child(container)

	var manifest: Dictionary = Client.plugins.get_plugin(
		_pending_plugin_id
	)
	var activity_name: String = manifest.get("name", tr("Activity"))
	var host_id: String = AppState.pending_activity_host_user_id
	var host_user: Dictionary = Client.get_user_by_id(host_id)
	var host_name: String = host_user.get(
		"display_name", host_user.get("username", tr("Someone"))
	)

	var label := Label.new()
	label.text = tr("%s started %s") % [host_name, activity_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	container.add_child(label)

	var join_btn := Button.new()
	join_btn.text = tr("Join Activity")
	join_btn.custom_minimum_size = Vector2(140, 40)
	var btn_style := ThemeManager.make_flat_style(
		"accent", 6, [16, 10, 16, 10]
	)
	join_btn.add_theme_stylebox_override("normal", btn_style)
	join_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	join_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_btn.pressed.connect(_on_join_activity)
	container.add_child(join_btn)

	# Voice participant tiles below
	for tile_data in tiles:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tile_data)


func _on_join_activity() -> void:
	Client.plugins.join_activity()


func _build_activity_header() -> PanelContainer:
	var header_panel := PanelContainer.new()
	var hstyle := ThemeManager.make_flat_style(
		"nav_bg", 0, [12, 8, 12, 8]
	)
	header_panel.add_theme_stylebox_override("panel", hstyle)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	header_panel.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = _activity_manifest.get("name", tr("Activity"))
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var runtime_lbl := Label.new()
	runtime_lbl.text = _activity_manifest.get(
		"runtime", ""
	).capitalize()
	ThemeManager.style_label(runtime_lbl, 11, "text_muted")
	hbox.add_child(runtime_lbl)

	var session_state: String = AppState.active_activity_session_state
	if session_state == "lobby" and _activity_is_host:
		var start_btn := Button.new()
		start_btn.text = tr("Start")
		start_btn.custom_minimum_size = Vector2(60, 32)
		var start_style := ThemeManager.make_flat_style(
			"accent", 4, [8, 4, 8, 4]
		)
		start_btn.add_theme_stylebox_override(
			"normal", start_style
		)
		start_btn.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_white")
		)
		start_btn.pressed.connect(_on_activity_start)
		hbox.add_child(start_btn)

	var leave_btn := Button.new()
	leave_btn.text = tr("Leave")
	leave_btn.custom_minimum_size = Vector2(60, 32)
	var leave_style := ThemeManager.make_flat_style(
		Color(ThemeManager.get_color("error"), 0.3),
		4, [8, 4, 8, 4],
	)
	leave_btn.add_theme_stylebox_override(
		"normal", leave_style
	)
	leave_btn.pressed.connect(_on_activity_leave)
	hbox.add_child(leave_btn)

	return header_panel

func _build_activity_footer() -> PanelContainer:
	var footer_panel := PanelContainer.new()
	var fstyle := ThemeManager.make_flat_style(
		"nav_bg", 0, [12, 6, 12, 6]
	)
	footer_panel.add_theme_stylebox_override("panel", fstyle)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	footer_panel.add_child(hbox)

	var role_lbl := Label.new()
	role_lbl.text = tr("Role: %s") % AppState.active_activity_role.capitalize()
	ThemeManager.style_label(role_lbl, 12, "text_muted")
	hbox.add_child(role_lbl)
	_activity_container.set_meta("role_label", role_lbl)

	return footer_panel

func _on_activity_start() -> void:
	Client.plugins.start_session()

func _on_activity_leave() -> void:
	if _activity_plugin_id.is_empty():
		return
	Client.plugins.stop_activity(_activity_plugin_id)

func _on_activity_viewport_input(
	event: InputEvent, vp_rect: TextureRect,
) -> void:
	if not event is InputEventMouse:
		return
	var tex: Texture2D = vp_rect.texture
	if tex == null:
		return
	var tex_size := Vector2(tex.get_size())
	var rect_size: Vector2 = vp_rect.size
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_f: float = minf(
		rect_size.x / tex_size.x,
		rect_size.y / tex_size.y,
	)
	var displayed: Vector2 = tex_size * scale_f
	var offset: Vector2 = (rect_size - displayed) * 0.5
	var canvas_pos: Vector2 = (event.position - offset) / scale_f
	event = event.duplicate()
	event.position = canvas_pos
	if event is InputEventMouseMotion:
		event.relative = event.relative / scale_f
	Client.plugins.forward_activity_input(event)

# --- Standard video grid methods ---

func _rebuild_spotlight(
	tiles: Array, spotlight_idx: int,
) -> void:
	spotlight_area.visible = true
	_v_resize_handle.visible = true
	var spotlight_data: Dictionary = tiles[spotlight_idx]

	var spotlight_tile: PanelContainer = VideoTileScene.instantiate()
	spotlight_area.add_child(spotlight_tile)
	spotlight_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spotlight_tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_tile(spotlight_tile, spotlight_data)

	for i in tiles.size():
		if i == spotlight_idx:
			continue
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tiles[i])

func _rebuild_grid_only(tiles: Array) -> void:
	spotlight_area.visible = false
	_v_resize_handle.visible = false
	for tile_data in tiles:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tile_data)

func _setup_tile(
	tile: PanelContainer, data: Dictionary,
) -> void:
	var track = data.get("track")
	var user: Dictionary = data.get("user", {})
	if track != null:
		tile.setup_local(track, user)
	else:
		var voice_state: Dictionary = data.get(
			"voice_state", {}
		)
		tile.setup_placeholder(user, voice_state)
