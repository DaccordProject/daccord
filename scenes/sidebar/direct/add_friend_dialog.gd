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

func _on_send() -> void:
	_error_label.visible = false
	var username: String = _username_input.text.strip_edges()
	if username.is_empty():
		_error_label.text = "Please enter a username."
		_error_label.visible = true
		return

	var user_id: String = _find_user_id(username)
	if user_id.is_empty():
		_error_label.text = "User not found. Make sure you share a server with them."
		_error_label.visible = true
		return

	_send_btn.disabled = true
	_send_btn.text = "Sending..."
	await Client.relationships.send_friend_request(user_id)
	_close()

func _find_user_id(username: String) -> String:
	return Client.find_user_id_by_username(username)

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
