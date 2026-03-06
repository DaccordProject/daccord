extends RefCounted

var _view: Control # MainWindow
var _pip: PanelContainer = null
var _video_pip_scene: PackedScene

func _init(view: Control) -> void:
	_view = view
	_video_pip_scene = preload("res://scenes/video/video_pip.tscn")

func on_voice_view_opened(
	_channel_id: String,
	content_header: Control,
	topic_bar: Control,
	content_body: Control,
	voice_text_panel: Control,
	video_grid: PanelContainer,
) -> void:
	remove_pip()
	content_header.visible = false
	topic_bar.visible = false
	# Hide content_body children except voice text panel
	if voice_text_panel.visible:
		for child in content_body.get_children():
			if child != voice_text_panel:
				child.visible = false
	else:
		content_body.visible = false
	video_grid.set_full_area(true)

func on_voice_view_closed(
	content_header: Control,
	content_body: Control,
	message_view: Control,
	topic_bar: Control,
	video_grid: PanelContainer,
	sync_handle_fn: Callable,
) -> void:
	content_header.visible = true
	content_body.visible = true
	# Restore visibility of content_body children hidden during voice view
	message_view.visible = true
	sync_handle_fn.call()
	# Restore topic bar based on current channel
	var topic := ""
	for ch in Client.channels:
		if ch["id"] == AppState.current_channel_id:
			topic = ch.get("topic", "")
			break
	topic_bar.visible = topic != ""
	video_grid.set_full_area(false)
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
			if state.get("self_video", false) or state.get("self_stream", false):
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
