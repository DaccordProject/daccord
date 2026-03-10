extends ColorRect

## Dialog for sending a friend request by searching for a username.
## Searches the local user cache (members from connected servers).

@onready var _username_input: LineEdit = \
	$CenterContainer/Panel/VBox/UsernameInput
@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _send_btn: Button = \
	$CenterContainer/Panel/VBox/Buttons/SendButton
@onready var _error_label: Label = \
	$CenterContainer/Panel/VBox/ErrorLabel
@onready var _cancel_btn: Button = \
	$CenterContainer/Panel/VBox/Buttons/CancelButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_send_btn.pressed.connect(_on_send)
	_username_input.text_submitted.connect(func(_t: String): _on_send())

func _show_error(text: String) -> void:
	_send_btn.disabled = false
	_send_btn.text = "Send Request"
	_error_label.text = text
	_error_label.visible = true


func _rel_error_message(existing: Dictionary) -> String:
	match existing.get("type", 0):
		1:
			return "You're already friends with this user."
		2:
			return "You have this user blocked."
		3:
			return "This user already sent you a friend request. Check the Pending tab."
		4:
			return "You already sent a friend request to this user."
	return ""


func _on_send() -> void:
	_error_label.visible = false
	var username: String = _username_input.text.strip_edges()
	if username.is_empty():
		_error_label.text = "Please enter a username."
		_error_label.visible = true
		return

	_send_btn.disabled = true
	_send_btn.text = "Searching..."
	var user_id: String = await Client.relationships.search_user_by_username(username)
	if user_id.is_empty():
		_show_error("User not found.")
		return

	# FRND-15: Prevent self-friending
	if user_id == Client.current_user.get("id", ""):
		_show_error("You can't add yourself as a friend.")
		return

	# FRND-16: Check existing relationships
	var existing = Client.relationships.get_relationship(user_id)
	if existing != null:
		var msg: String = _rel_error_message(existing as Dictionary)
		if not msg.is_empty():
			_show_error(msg)
			return

	_send_btn.text = "Sending..."
	var result: RestResult = await Client.relationships.send_friend_request(user_id)

	# FRND-7: Handle send failure
	if result == null or not result.ok:
		_show_error("Failed to send friend request. Please try again.")
		return

	_close()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
