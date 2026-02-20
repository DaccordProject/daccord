extends ColorRect

## Dialog for selecting multiple users to create a group DM.

var _selected_ids: Array = []

@onready var close_button: Button = %CloseButton
@onready var search_input: LineEdit = %SearchInput
@onready var user_list: VBoxContainer = %UserList
@onready var selected_label: Label = %SelectedLabel
@onready var create_button: Button = %CreateButton


func _ready() -> void:
	# Use unique names for lookup — set them since .tscn doesn't
	close_button = $CenterContainer/Panel/VBox/Header/CloseButton
	search_input = $CenterContainer/Panel/VBox/SearchInput
	user_list = $CenterContainer/Panel/VBox/Scroll/UserList
	selected_label = $CenterContainer/Panel/VBox/SelectedLabel
	create_button = $CenterContainer/Panel/VBox/CreateButton

	close_button.pressed.connect(_close)
	search_input.text_changed.connect(_on_search_changed)
	create_button.pressed.connect(_on_create_pressed)
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

	var my_id: String = Client.current_user.get("id", "")
	var query: String = search_input.text.strip_edges().to_lower()

	# Build a sorted list of users from the cache
	var users: Array = []
	for uid in Client._user_cache:
		if uid == my_id:
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

		# Apply search filter
		if not query.is_empty():
			var dn_lower: String = display_name.to_lower()
			var un_lower: String = username.to_lower()
			if not dn_lower.contains(query) \
					and not un_lower.contains(query):
				continue

		var row := CheckBox.new()
		row.text = display_name
		if not username.is_empty() \
				and username != display_name:
			row.text += " (" + username + ")"
		row.set_meta("user_id", uid)
		row.button_pressed = _selected_ids.has(uid)
		row.toggled.connect(
			_on_user_toggled.bind(uid)
		)
		user_list.add_child(row)


func _on_search_changed(_new_text: String) -> void:
	_populate_users()


func _on_user_toggled(toggled_on: bool, uid: String) -> void:
	if toggled_on:
		if not _selected_ids.has(uid):
			_selected_ids.append(uid)
	else:
		_selected_ids.erase(uid)
	_update_selection_ui()


func _update_selection_ui() -> void:
	var count: int = _selected_ids.size()
	selected_label.text = "%d user%s selected" % [
		count, "" if count == 1 else "s"
	]
	create_button.disabled = count < 2


func _on_create_pressed() -> void:
	if _selected_ids.size() < 2:
		return
	create_button.disabled = true
	create_button.text = "Creating..."
	await Client.create_group_dm(_selected_ids)
	_close()
