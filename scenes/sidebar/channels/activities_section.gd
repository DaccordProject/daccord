extends VBoxContainer

## Collapsible "ACTIVITIES" section injected at the bottom of the channel list.
## Shows one row per active plugin session in the current space.

signal join_lobby_requested(session_data: Dictionary)
signal join_voice_requested(channel_id: String)

const CHEVRON_DOWN := preload("res://assets/theme/icons/chevron_down.svg")
const CHEVRON_RIGHT := preload("res://assets/theme/icons/chevron_right.svg")
const ActivityRowScene := preload(
	"res://scenes/sidebar/channels/activity_row.tscn"
)

var _space_id: String = ""
var _is_collapsed: bool = false
var _row_nodes: Dictionary = {}  # session_id -> ActivityRow

@onready var header: Button = $Header
@onready var chevron: TextureRect = $Header/HBox/Chevron
@onready var section_name: Label = $Header/HBox/SectionName
@onready var count_label: Label = $Header/HBox/CountLabel
@onready var row_container: VBoxContainer = $RowContainer


func _ready() -> void:
	add_to_group("themed")
	header.pressed.connect(_toggle_collapsed)
	chevron.texture = CHEVRON_DOWN
	section_name.text = tr("ACTIVITIES")
	section_name.add_theme_font_size_override("font_size", 11)

	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	AppState.active_sessions_updated.connect(_on_active_sessions_updated)
	AppState.activity_session_state_changed.connect(
		_on_session_state_changed
	)
	AppState.activity_participants_updated.connect(
		_on_participants_updated
	)
	AppState.activity_ended.connect(_on_activity_ended)
	AppState.voice_state_updated.connect(_on_voice_state_updated)
	AppState.voice_joined.connect(_on_voice_changed)
	AppState.voice_left.connect(_on_voice_changed)

	_apply_theme()


func _apply_theme() -> void:
	chevron.modulate = ThemeManager.get_color("icon_default")
	section_name.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	count_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)


func setup(space_id: String) -> void:
	_space_id = space_id
	refresh()


func refresh() -> void:
	var sessions: Array = Client.plugins.get_space_sessions(_space_id)

	# Remove rows for sessions that no longer exist
	var current_ids: Dictionary = {}
	for s in sessions:
		current_ids[str(s.get("id", ""))] = true
	var to_remove: Array = []
	for sid in _row_nodes:
		if not current_ids.has(sid):
			to_remove.append(sid)
	for sid in to_remove:
		_row_nodes[sid].queue_free()
		_row_nodes.erase(sid)

	# Add or update rows
	for session in sessions:
		var sid: String = str(session.get("id", ""))
		if sid.is_empty():
			continue
		var plugin_id: String = session.get("plugin_id", "")
		var manifest: Dictionary = Client.plugins.get_plugin(plugin_id)
		if _row_nodes.has(sid):
			_row_nodes[sid].update_state(session, manifest)
		else:
			var row: HBoxContainer = ActivityRowScene.instantiate()
			row_container.add_child(row)
			row.setup(session, manifest)
			row.join_lobby_pressed.connect(_on_join_lobby)
			row.join_voice_pressed.connect(_on_join_voice)
			_row_nodes[sid] = row

	_update_visibility()


func _update_visibility() -> void:
	visible = not _row_nodes.is_empty()
	count_label.text = str(_row_nodes.size())
	count_label.visible = _is_collapsed and not _row_nodes.is_empty()


func _toggle_collapsed() -> void:
	_is_collapsed = not _is_collapsed
	chevron.texture = CHEVRON_RIGHT if _is_collapsed else CHEVRON_DOWN
	row_container.visible = not _is_collapsed
	count_label.visible = _is_collapsed and not _row_nodes.is_empty()


# --- Signal handlers ---

func _on_active_sessions_updated(space_id: String) -> void:
	if space_id == _space_id:
		refresh()


func _on_session_state_changed(_plugin_id: String, _state: String) -> void:
	if not _space_id.is_empty():
		refresh()


func _on_participants_updated(session_id: String, _participants: Array) -> void:
	if _row_nodes.has(session_id):
		var session: Dictionary = _row_nodes[session_id]._session_data
		var plugin_id: String = session.get("plugin_id", "")
		var manifest: Dictionary = Client.plugins.get_plugin(plugin_id)
		session["participants"] = _participants
		_row_nodes[session_id].update_state(session, manifest)


func _on_activity_ended(_plugin_id: String) -> void:
	if not _space_id.is_empty():
		refresh()


func _on_voice_state_updated(_channel_id: String) -> void:
	for row in _row_nodes.values():
		row.update_voice_state()


func _on_voice_changed(_channel_id: String, _intentional: bool = true) -> void:
	for row in _row_nodes.values():
		row.update_voice_state()


# --- Join actions ---

func _on_join_lobby(session_data: Dictionary) -> void:
	join_lobby_requested.emit(session_data)


func _on_join_voice(channel_id: String) -> void:
	join_voice_requested.emit(channel_id)
