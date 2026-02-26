extends PanelContainer

signal pip_clicked

const VideoTileScene := preload(
	"res://scenes/video/video_tile.tscn"
)

var _tile: PanelContainer = null

@onready var tile_slot: Control = $Margin/TileSlot

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	AppState.video_enabled_changed.connect(_on_track_changed)
	AppState.screen_share_changed.connect(_on_track_changed)
	AppState.remote_track_received.connect(_on_remote_changed)
	AppState.remote_track_removed.connect(_on_remote_changed)
	AppState.voice_left.connect(_on_voice_left)
	_rebuild_pip()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pip_clicked.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()

func _on_track_changed(_value: bool) -> void:
	_rebuild_pip()

func _on_remote_changed(_user_id: String, _track = null) -> void:
	_rebuild_pip()

func _on_voice_left(_channel_id: String) -> void:
	queue_free()

func _rebuild_pip() -> void:
	if _tile != null:
		_tile.queue_free()
		_tile = null

	# Priority: screen share > local camera > first remote track
	var track = Client.get_screen_track()
	var user: Dictionary = Client.current_user
	if track == null:
		track = Client.get_camera_track()
	if track == null:
		# Try first remote peer with video
		var cid := AppState.voice_channel_id
		if not cid.is_empty():
			var my_id: String = Client.current_user.get("id", "")
			var states: Array = Client.get_voice_users(cid)
			for state in states:
				var uid: String = state.get("user_id", "")
				if uid == my_id:
					continue
				if state.get("self_video", false) or state.get("self_stream", false):
					track = Client.get_remote_track(uid)
					user = state.get("user", {})
					if user.is_empty():
						user = Client.get_user_by_id(uid)
					break

	if track == null:
		visible = false
		return

	visible = true
	_tile = VideoTileScene.instantiate()
	tile_slot.add_child(_tile)
	_tile.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tile.setup_local(track, user)

func _exit_tree() -> void:
	if _tile != null:
		_tile.queue_free()
		_tile = null
