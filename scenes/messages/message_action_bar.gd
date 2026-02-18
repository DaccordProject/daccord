extends PanelContainer

signal action_reply(msg_data: Dictionary)
signal action_edit(msg_data: Dictionary)
signal action_delete(msg_data: Dictionary)

const ReactionPickerScene := preload("res://scenes/messages/reaction_picker.tscn")

var _message_data: Dictionary = {}
var _message_node: Control = null
var _reaction_picker: Control = null

@onready var react_btn: Button = $HBox/ReactButton
@onready var reply_btn: Button = $HBox/ReplyButton
@onready var edit_btn: Button = $HBox/EditButton
@onready var delete_btn: Button = $HBox/DeleteButton

func _ready() -> void:
	react_btn.pressed.connect(_on_react_pressed)
	reply_btn.pressed.connect(_on_reply_pressed)
	edit_btn.pressed.connect(_on_edit_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)

func show_for_message(msg_node: Control, msg_data: Dictionary) -> void:
	_message_node = msg_node
	_message_data = msg_data
	var author: Dictionary = msg_data.get("author", {})
	var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
	edit_btn.visible = is_own
	delete_btn.visible = is_own
	visible = true

func hide_bar() -> void:
	visible = false
	_message_node = null
	# Keep message data while reaction picker is open so the callback
	# can still read channel_id / msg_id after the bar auto-hides.
	if not (_reaction_picker and is_instance_valid(_reaction_picker)):
		_message_data = {}

func is_bar_hovered() -> bool:
	return visible and get_global_rect().has_point(get_global_mouse_position())

func get_message_node() -> Control:
	return _message_node

func _on_react_pressed() -> void:
	_open_reaction_picker()

func _on_reply_pressed() -> void:
	action_reply.emit(_message_data)

func _on_edit_pressed() -> void:
	action_edit.emit(_message_data)

func _on_delete_pressed() -> void:
	action_delete.emit(_message_data)

func _open_reaction_picker() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
	_reaction_picker = ReactionPickerScene.instantiate()
	get_tree().root.add_child(_reaction_picker)
	var channel_id: String = _message_data.get("channel_id", "")
	var msg_id: String = _message_data.get("id", "")
	var btn_rect := react_btn.get_global_rect()
	_reaction_picker.open(channel_id, msg_id, btn_rect.position)
	_reaction_picker.closed.connect(func():
		_reaction_picker = null
	)

func _exit_tree() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
