extends VBoxContainer

## Lobby view shown when an activity session is in the "lobby" state.
## Displays player slots and a Start button for the host.

signal start_requested()
signal role_change_requested(user_id: String, role: String)

var _slots_grid: GridContainer
var _spectator_list: VBoxContainer
var _start_btn: Button
var _status_label: Label
var _max_participants: int = 0
var _is_host: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Lobby"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_status_label = Label.new()
	_status_label.text = "Waiting for players..."
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	# Player slot grid
	var slots_label := Label.new()
	slots_label.text = "Players"
	slots_label.add_theme_font_size_override("font_size", 13)
	add_child(slots_label)

	_slots_grid = GridContainer.new()
	_slots_grid.columns = 2
	_slots_grid.add_theme_constant_override("h_separation", 8)
	_slots_grid.add_theme_constant_override("v_separation", 8)
	add_child(_slots_grid)

	# Spectator section
	var spec_label := Label.new()
	spec_label.text = "Spectators"
	spec_label.add_theme_font_size_override("font_size", 13)
	add_child(spec_label)

	_spectator_list = VBoxContainer.new()
	_spectator_list.add_theme_constant_override("separation", 4)
	add_child(_spectator_list)

	# Start button (host only)
	_start_btn = Button.new()
	_start_btn.text = "Start Activity"
	_start_btn.custom_minimum_size = Vector2(0, 40)
	var btn_style := ThemeManager.make_flat_style("accent", 4, [16, 8, 16, 8])
	_start_btn.add_theme_stylebox_override("normal", btn_style)
	_start_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	_start_btn.pressed.connect(func() -> void: start_requested.emit())
	_start_btn.visible = false
	add_child(_start_btn)


func setup(manifest: Dictionary, is_host: bool) -> void:
	_max_participants = manifest.get("max_participants", 0)
	_is_host = is_host
	_start_btn.visible = is_host
	_start_btn.disabled = true
	_rebuild_slots([])


func update_participants(participants: Array) -> void:
	_rebuild_slots(participants)
	# Enable start if at least 1 player
	var player_count: int = 0
	for p in participants:
		if p.get("role", "spectator") == "player":
			player_count += 1
	_start_btn.disabled = player_count == 0
	_status_label.text = "%d player(s) joined" % player_count


func _rebuild_slots(participants: Array) -> void:
	for child in _slots_grid.get_children():
		child.queue_free()
	for child in _spectator_list.get_children():
		child.queue_free()

	# Create player slots
	var slot_count: int = _max_participants if _max_participants > 0 else 8
	var players: Array = participants.filter(
		func(p: Dictionary) -> bool:
			return p.get("role", "spectator") == "player"
	)
	var spectators: Array = participants.filter(
		func(p: Dictionary) -> bool:
			return p.get("role", "spectator") == "spectator"
	)

	for i in slot_count:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(0, 40)
		var style := ThemeManager.make_flat_style("input_bg", 4, [8, 6, 8, 6])
		slot.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i < players.size():
			label.text = players[i].get("display_name", "Player %d" % (i + 1))
		else:
			label.text = "Empty Slot"
			label.add_theme_color_override(
				"font_color", ThemeManager.get_color("text_muted")
			)
		slot.add_child(label)
		_slots_grid.add_child(slot)

	# Spectators
	for spec in spectators:
		var label := Label.new()
		label.text = spec.get("display_name", "Spectator")
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_spectator_list.add_child(label)
