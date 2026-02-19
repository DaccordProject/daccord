extends PanelContainer

const VideoTileScene := preload(
	"res://scenes/video/video_tile.tscn"
)

@onready var grid: GridContainer = $Scroll/Grid

func _ready() -> void:
	visible = false
	AppState.video_enabled_changed.connect(
		_on_video_changed
	)
	AppState.screen_share_changed.connect(
		_on_video_changed
	)
	AppState.voice_state_updated.connect(
		_on_voice_state_updated
	)
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
	_update_grid_columns()

func _on_video_changed(_value: bool) -> void:
	_rebuild()

func _on_voice_state_updated(_channel_id: String) -> void:
	if AppState.voice_channel_id.is_empty():
		return
	_rebuild()

func _on_voice_left(_channel_id: String) -> void:
	_clear()
	visible = false

func _on_remote_track_received(
	_user_id: String,
	_track: AccordMediaTrack,
) -> void:
	_rebuild()

func _on_remote_track_removed(
	_user_id: String,
) -> void:
	_rebuild()

func _on_layout_mode_changed(
	_mode: AppState.LayoutMode,
) -> void:
	_update_grid_columns()

func _update_grid_columns() -> void:
	match AppState.current_layout_mode:
		AppState.LayoutMode.COMPACT:
			grid.columns = 1
		AppState.LayoutMode.MEDIUM:
			grid.columns = 2
		AppState.LayoutMode.FULL:
			grid.columns = 2

func _clear() -> void:
	for child in grid.get_children():
		child.queue_free()

func _rebuild() -> void:
	_clear()
	var has_tiles := false

	# Local camera tile
	var cam_track: AccordMediaTrack = (
		Client.get_camera_track()
	)
	if cam_track != null:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		tile.setup_local(cam_track, Client.current_user)
		has_tiles = true

	# Local screen share tile
	var screen_track: AccordMediaTrack = (
		Client.get_screen_track()
	)
	if screen_track != null:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		tile.setup_local(
			screen_track, Client.current_user
		)
		has_tiles = true

	# Remote peer tiles (live if track available, else placeholder)
	var cid := AppState.voice_channel_id
	if not cid.is_empty():
		var my_id: String = Client.current_user.get(
			"id", ""
		)
		var states: Array = Client.get_voice_users(cid)
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			var has_video: bool = state.get(
				"self_video", false
			)
			var has_stream: bool = state.get(
				"self_stream", false
			)
			if has_video or has_stream:
				var user: Dictionary = state.get(
					"user", {}
				)
				if user.is_empty():
					user = Client.get_user_by_id(uid)
				var tile: PanelContainer = (
					VideoTileScene.instantiate()
				)
				grid.add_child(tile)
				var remote_track: AccordMediaTrack = (
					Client.get_remote_track(uid)
				)
				if remote_track != null:
					tile.setup_local(
						remote_track, user
					)
				else:
					tile.setup_placeholder(user, state)
				has_tiles = true

	visible = has_tiles
