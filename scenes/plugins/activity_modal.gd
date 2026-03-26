extends ModalBase

## Modal dialog listing available activities for the current server.
## Shown when the user presses the rocket button in the voice bar.

signal activity_launched(plugin_id: String, channel_id: String)

const ActivityCardScene := preload("res://scenes/plugins/activity_card.tscn")

var _list: VBoxContainer
var _empty_label: Label
var _loading_label: Label
var _space_id: String = ""
var _channel_id: String = ""


func _ready() -> void:
	_setup_modal(tr("Activities"), 480.0, 0.0, true, 24.0)

	_loading_label = Label.new()
	_loading_label.text = tr("Loading...")
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	content_container.add_child(_loading_label)

	_empty_label = Label.new()
	_empty_label.text = tr("No activities installed on this server.")
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_empty_label.visible = false
	content_container.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	AppState.plugins_updated.connect(_refresh_list)


func setup(space_id: String, channel_id: String) -> void:
	_space_id = space_id
	_channel_id = channel_id
	_refresh_list()


func _refresh_list() -> void:
	NodeUtils.free_children(_list)

	var conn_idx: int = Client.get_conn_index_for_space(_space_id)
	if conn_idx == -1:
		_loading_label.visible = false
		_empty_label.visible = true
		return

	var plugin_list: Array = Client.plugins.get_plugins(conn_idx)
	# Filter to activities only
	var activities: Array = plugin_list.filter(
		func(p: Dictionary) -> bool:
			return p.get("type", "") == "activity"
	)

	# Query active sessions in this channel to show Join vs Launch
	# Maps plugin_id -> session state string ("lobby" or "running")
	var active_sessions: Dictionary = {}
	var conn: Dictionary = Client._connections[conn_idx]
	if conn != null and conn.get("client") != null:
		var client: AccordClient = conn["client"]
		var sess_result: RestResult = (
			await client.plugins.get_channel_sessions(_channel_id)
		)
		if sess_result.ok and sess_result.data is Array:
			for s in sess_result.data:
				var pid: String = str(s.get("plugin_id", ""))
				if not pid.is_empty():
					active_sessions[pid] = str(s.get("state", "lobby"))

	_loading_label.visible = false
	_empty_label.visible = activities.is_empty()

	for plugin in activities:
		var card := ActivityCardScene.instantiate()
		_list.add_child(card)
		var pid: String = plugin.get("id", "")
		var session_state: String = active_sessions.get(pid, "")
		card.setup(plugin, not session_state.is_empty(), session_state)
		card.launch_pressed.connect(_on_launch)


func _on_launch(plugin_id: String) -> void:
	activity_launched.emit(plugin_id, _channel_id)
	_close()
