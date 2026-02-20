extends ColorRect

## Dialog for selecting a single user to add to a group DM.

var _channel_id: String = ""
var _existing_ids: Array = []
var _selected_id: String = ""

@onready var close_button: Button
@onready var search_input: LineEdit
@onready var user_list: VBoxContainer
@onready var add_button: Button


func _ready() -> void:
	close_button = $CenterContainer/Panel/VBox/Header/CloseButton
	search_input = $CenterContainer/Panel/VBox/SearchInput
	user_list = $CenterContainer/Panel/VBox/Scroll/UserList
	add_button = $CenterContainer/Panel/VBox/AddButton

	close_button.pressed.connect(_close)
	search_input.text_changed.connect(_on_search_changed)
	add_button.pressed.connect(_on_add_pressed)


func setup(
	channel_id: String, existing_recipients: Array,
) -> void:
	_channel_id = channel_id
	_existing_ids.clear()
	var my_id: String = Client.current_user.get("id", "")
	if not my_id.is_empty():
		_existing_ids.append(my_id)
	for r in existing_recipients:
		var rid: String = r.get("id", "")
		if not rid.is_empty():
			_existing_ids.append(rid)
	_populate_users()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	queue_free()


func _populate_users() -> void:
	for child in user_list.get_children():
		child.queue_free()

	var query: String = search_input.text.strip_edges().to_lower()

	var users: Array = []
	for uid in Client._user_cache:
		if _existing_ids.has(uid):
			continue
		var user: Dictionary = Client._user_cache[uid]
		if user.get("bot", false):
			continue
		users.append(user)

	users.sort_custom(func(a, b):
		return a.get("display_name", "").to_lower() \
			< b.get("display_name", "").to_lower()
	)

	for user in users:
		var uid: String = user.get("id", "")
		var display_name: String = user.get(
			"display_name", "Unknown"
		)
		var username: String = user.get("username", "")

		if not query.is_empty():
			var dn_lower: String = display_name.to_lower()
			var un_lower: String = username.to_lower()
			if not dn_lower.contains(query) \
					and not un_lower.contains(query):
				continue

		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = display_name
		if not username.is_empty() \
				and username != display_name:
			row.text += " (" + username + ")"
		row.set_meta("user_id", uid)
		row.pressed.connect(_on_user_selected.bind(uid, row))
		user_list.add_child(row)


func _on_search_changed(_new_text: String) -> void:
	_populate_users()


func _on_user_selected(uid: String, btn: Button) -> void:
	# Deselect previous
	for child in user_list.get_children():
		child.remove_theme_stylebox_override("normal")
	_selected_id = uid
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.345, 0.396, 0.949, 0.3)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	add_button.disabled = false


func _on_add_pressed() -> void:
	if _selected_id.is_empty():
		return
	add_button.disabled = true
	add_button.text = "Adding..."
	await Client.add_dm_member(_channel_id, _selected_id)
	_close()
