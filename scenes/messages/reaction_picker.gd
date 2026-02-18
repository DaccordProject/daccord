extends Control

signal reaction_added(channel_id: String, message_id: String, emoji: String)
signal closed

const EmojiPickerScene := preload("res://scenes/messages/composer/emoji_picker.tscn")

var _channel_id: String = ""
var _message_id: String = ""
var _picker: PanelContainer = null

func open(channel_id: String, message_id: String, at_position: Vector2) -> void:
	_channel_id = channel_id
	_message_id = message_id
	_picker = EmojiPickerScene.instantiate()
	add_child(_picker)
	_picker.emoji_picked.connect(_on_emoji_picked)
	_picker.visibility_changed.connect(_on_picker_visibility_changed)
	var picker_size := _picker.custom_minimum_size
	var vp_size := get_viewport().get_visible_rect().size
	var x := clampf(at_position.x, 4, vp_size.x - picker_size.x - 4)
	var y := clampf(at_position.y - picker_size.y - 4, 4, vp_size.y - picker_size.y - 4)
	_picker.position = Vector2(x, y)
	_picker.visible = true

func _on_emoji_picked(emoji_name: String) -> void:
	if not _channel_id.is_empty() and not _message_id.is_empty():
		var reaction_key := emoji_name
		if emoji_name.begins_with("custom:"):
			reaction_key = emoji_name.substr(7)
		Client.add_reaction(_channel_id, _message_id, reaction_key)
		reaction_added.emit(_channel_id, _message_id, reaction_key)
	_close()

func _on_picker_visibility_changed() -> void:
	if _picker and not _picker.visible:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
