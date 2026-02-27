extends PanelContainer

enum GridMode { INLINE, FULL_AREA }

const VideoTileScene := preload(
	"res://scenes/video/video_tile.tscn"
)

var _mode: GridMode = GridMode.INLINE
var _rebuild_pending: bool = false

@onready var spotlight_area: PanelContainer = $MainLayout/SpotlightArea
@onready var grid: GridContainer = $MainLayout/ParticipantGrid

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
	AppState.spotlight_changed.connect(
		_on_spotlight_changed
	)
	_update_grid_columns()

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

func _update_grid_columns() -> void:
	if _mode == GridMode.FULL_AREA:
		if not AppState.spotlight_user_id.is_empty() or _has_screen_share():
			# Participant strip is a single horizontal row
			grid.columns = 99
		else:
			# Adaptive columns based on tile count
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
	if Client.get_camera_track() != null:
		count += 1
	if Client.get_screen_track() != null:
		count += 1
	var cid := AppState.voice_channel_id
	if not cid.is_empty():
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
		child.detach_stream()
		child.queue_free()
	spotlight_area.visible = false

func _collect_tiles() -> Array:
	# Returns array of dictionaries: {track, user, is_screen, user_id}
	var tiles: Array = []

	# Local camera tile
	var cam_track = Client.get_camera_track()
	if cam_track != null:
		tiles.append({
			"track": cam_track,
			"user": Client.current_user,
			"is_screen": false,
			"user_id": Client.current_user.get("id", ""),
		})

	# Local screen share tile
	var screen_track = Client.get_screen_track()
	if screen_track != null:
		tiles.append({
			"track": screen_track,
			"user": Client.current_user,
			"is_screen": true,
			"user_id": Client.current_user.get("id", ""),
		})

	# Remote peer tiles
	var cid := AppState.voice_channel_id
	if not cid.is_empty():
		var my_id: String = Client.current_user.get("id", "")
		var states: Array = Client.get_voice_users(cid)
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
				var remote_track = Client.get_remote_track(uid)
				tiles.append({
					"track": remote_track,
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
	if tiles.is_empty():
		if _mode == GridMode.FULL_AREA:
			visible = true
		else:
			visible = false
		return

	visible = true

	# Determine if we should use spotlight layout
	var use_spotlight := false
	var spotlight_tile_idx := -1

	if _mode == GridMode.FULL_AREA:
		# Manual spotlight takes priority
		if not AppState.spotlight_user_id.is_empty():
			for i in tiles.size():
				if tiles[i]["user_id"] == AppState.spotlight_user_id:
					spotlight_tile_idx = i
					use_spotlight = true
					break
		# Auto-spotlight screen shares
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

func _rebuild_spotlight(tiles: Array, spotlight_idx: int) -> void:
	spotlight_area.visible = true
	var spotlight_data: Dictionary = tiles[spotlight_idx]

	# Place spotlight tile
	var spotlight_tile: PanelContainer = VideoTileScene.instantiate()
	spotlight_area.add_child(spotlight_tile)
	spotlight_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spotlight_tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_tile(spotlight_tile, spotlight_data)

	# Place remaining tiles in participant grid
	for i in tiles.size():
		if i == spotlight_idx:
			continue
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tiles[i])

func _rebuild_grid_only(tiles: Array) -> void:
	spotlight_area.visible = false
	for tile_data in tiles:
		var tile: PanelContainer = VideoTileScene.instantiate()
		grid.add_child(tile)
		_setup_tile(tile, tile_data)

func _setup_tile(tile: PanelContainer, data: Dictionary) -> void:
	var track = data.get("track")
	var user: Dictionary = data.get("user", {})
	if track != null:
		tile.setup_local(track, user)
	else:
		var voice_state: Dictionary = data.get("voice_state", {})
		tile.setup_placeholder(user, voice_state)
