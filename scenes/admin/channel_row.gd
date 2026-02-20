extends HBoxContainer

signal toggled(pressed: bool, channel_id: String)
signal move_requested(channel: Dictionary, direction: int)
signal edit_requested(channel: Dictionary)
signal delete_requested(channel: Dictionary)
signal permissions_requested(channel: Dictionary)

var _channel_data: Dictionary = {}

@onready var _checkbox: CheckBox = $CheckBox
@onready var _up_btn: Button = $UpButton
@onready var _down_btn: Button = $DownButton
@onready var _type_label: Label = $TypeLabel
@onready var _name_label: Label = $NameLabel
@onready var _perms_btn: Button = $PermsButton
@onready var _edit_btn: Button = $EditButton
@onready var _del_btn: Button = $DeleteButton

func _ready() -> void:
	_checkbox.toggled.connect(func(pressed: bool):
		toggled.emit(pressed, _channel_data.get("id", ""))
	)
	_up_btn.pressed.connect(func(): move_requested.emit(_channel_data, -1))
	_down_btn.pressed.connect(func(): move_requested.emit(_channel_data, 1))
	_perms_btn.pressed.connect(func(): permissions_requested.emit(_channel_data))
	_edit_btn.pressed.connect(func(): edit_requested.emit(_channel_data))
	_del_btn.pressed.connect(func(): delete_requested.emit(_channel_data))

func setup(
	ch: Dictionary, selected: bool,
	guild_id: String = "",
) -> void:
	_channel_data = ch
	var ch_id: String = ch.get("id", "")
	set_meta("channel_id", ch_id)
	_checkbox.button_pressed = selected
	_name_label.text = ch.get("name", "")

	# Arrow characters
	_up_btn.text = "\u25b2"
	_down_btn.text = "\u25bc"

	# Hide Perms button if user lacks manage_roles
	if not guild_id.is_empty():
		var can_manage: bool = Client.has_permission(
			guild_id, AccordPermission.MANAGE_ROLES
		)
		_perms_btn.visible = can_manage

	var ch_type: int = ch.get("type", 0)
	match ch_type:
		ClientModels.ChannelType.TEXT: _type_label.text = "#"
		ClientModels.ChannelType.VOICE: _type_label.text = "V"
		ClientModels.ChannelType.ANNOUNCEMENT: _type_label.text = "A"
		ClientModels.ChannelType.FORUM: _type_label.text = "F"
		ClientModels.ChannelType.CATEGORY: _type_label.text = "C"
