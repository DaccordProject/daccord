extends RefCounted

var _view: Control # MainWindow
var _pip: PanelContainer = null
var _video_pip_scene: PackedScene

# Saved indices for reparenting back
var _video_grid_parent: Control = null
var _video_grid_index: int = -1
var _voice_text_parent: Control = null
var _voice_text_index: int = -1
var _voice_text_handle_parent: Control = null
var _voice_text_handle_index: int = -1

func _init(view: Control) -> void:
	_view = view
	_video_pip_scene = preload("res://scenes/video/video_pip.tscn")

func on_voice_view_opened(
	_channel_id: String,
	topic_bar: Control,
	content_body: Control,
	voice_text_panel: Control,
	video_grid: PanelContainer,
	voice_view_body: HBoxContainer,
	voice_text_handle: Control,
) -> void:
	remove_pip()
	# Keep content_header visible so the tab bar remains usable
	_view.search_toggle.visible = false
	_view.member_toggle.visible = false
	if _view._update_indicator:
		_view._update_indicator.visible = false
	topic_bar.visible = false
	content_body.visible = false

	# Save original parents and indices
	_video_grid_parent = video_grid.get_parent()
	_video_grid_index = video_grid.get_index()
	_voice_text_parent = voice_text_panel.get_parent()
	_voice_text_index = voice_text_panel.get_index()
	_voice_text_handle_parent = voice_text_handle.get_parent()
	_voice_text_handle_index = voice_text_handle.get_index()

	# Reparent VideoGrid into VoiceViewBody
	_video_grid_parent.remove_child(video_grid)
	voice_view_body.add_child(video_grid)

	# Reparent voice text handle + panel into VoiceViewBody
	_voice_text_handle_parent.remove_child(voice_text_handle)
	voice_view_body.add_child(voice_text_handle)
	_voice_text_parent.remove_child(voice_text_panel)
	voice_view_body.add_child(voice_text_panel)

	voice_view_body.visible = true
	video_grid.set_full_area(true)

	# Auto-open voice text chat
	var is_compact: bool = (
		AppState.current_layout_mode
		== AppState.LayoutMode.COMPACT
	)
	if not is_compact:
		AppState.open_voice_text(AppState.voice_channel_id)
	voice_text_handle.visible = (
		voice_text_panel.visible and not is_compact
	)

func on_voice_view_closed(
	content_body: Control,
	message_view: Control,
	topic_bar: Control,
	video_grid: PanelContainer,
	voice_view_body: HBoxContainer,
	voice_text_handle: Control,
	sync_handle_fn: Callable,
) -> void:
	voice_view_body.visible = false

	# Reparent VideoGrid back to original parent
	voice_view_body.remove_child(video_grid)
	_video_grid_parent.add_child(video_grid)
	_video_grid_parent.move_child(
		video_grid, _video_grid_index
	)

	# Reparent voice text panel + handle back
	voice_view_body.remove_child(voice_text_handle)
	_voice_text_handle_parent.add_child(voice_text_handle)
	_voice_text_handle_parent.move_child(
		voice_text_handle, _voice_text_handle_index
	)
	var vtp: Control = _view.voice_text_panel
	voice_view_body.remove_child(vtp)
	_voice_text_parent.add_child(vtp)
	_voice_text_parent.move_child(vtp, _voice_text_index)

	# Restore normal layout
	content_body.visible = true
	message_view.visible = true
	# Restore header button visibility via main window helpers
	_view._update_member_list_visibility()
	_view._update_search_visibility()
	if _view._update_indicator:
		_view._update_indicator.visible = (
			Updater.is_update_ready()
			or (
				not Updater.get_latest_version_info().is_empty()
				and Updater.is_newer(
					Updater.get_latest_version_info().get(
						"version", ""
					),
					Client.app_version,
				)
			)
		)
	sync_handle_fn.call()

	# Restore topic bar based on current channel
	var topic := ""
	for ch in Client.channels:
		if ch["id"] == AppState.current_channel_id:
			topic = ch.get("topic", "")
			break
	topic_bar.visible = topic != ""
	video_grid.set_full_area(false)

	# Close voice text since we're leaving voice view
	AppState.close_voice_text()

	# Spawn PiP if still in voice with active video
	maybe_spawn_pip()

func on_voice_left(_channel_id: String) -> void:
	remove_pip()

func maybe_spawn_pip() -> void:
	if AppState.voice_channel_id.is_empty():
		return
	# Only spawn PiP if there's any video content
	var has_video := (
		Client.get_camera_track() != null
		or Client.get_screen_track() != null
	)
	if not has_video:
		# Check remote peers
		var cid := AppState.voice_channel_id
		var my_id: String = Client.current_user.get("id", "")
		var states: Array = Client.get_voice_users(cid)
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			if (
				state.get("self_video", false)
				or state.get("self_stream", false)
			):
				has_video = true
				break
	if not has_video:
		return
	_pip = _video_pip_scene.instantiate()
	_pip.pip_clicked.connect(_on_pip_clicked)
	_view.add_child(_pip)

func remove_pip() -> void:
	if _pip != null and is_instance_valid(_pip):
		_pip.queue_free()
		_pip = null

func _on_pip_clicked() -> void:
	remove_pip()
	AppState.open_voice_view()
