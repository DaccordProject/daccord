extends ColorRect

var _guild_id: String = ""
var _parent_id: String = ""

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _type_option: OptionButton = $CenterContainer/Panel/VBox/TypeOption
@onready var _parent_label: Label = $CenterContainer/Panel/VBox/ParentLabel
@onready var _parent_option: OptionButton = $CenterContainer/Panel/VBox/ParentOption
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/Buttons/CreateButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_create_btn.pressed.connect(_on_create)

func setup(guild_id: String, parent_id: String = "", channels: Array = []) -> void:
	_guild_id = guild_id
	_parent_id = parent_id

	# Always add base channel types
	_type_option.add_item("Text", 0)
	_type_option.add_item("Voice", 1)
	_type_option.add_item("Announcement", 2)
	_type_option.add_item("Forum", 3)

	if parent_id.is_empty():
		# Called from channel_list: also add Category type and show parent dropdown
		_type_option.add_item("Category", 4)
		_parent_label.visible = true
		_parent_option.visible = true
		_parent_option.add_item("None", 0)
		var idx: int = 1
		for ch in channels:
			if ch.get("type", 0) == ClientModels.ChannelType.CATEGORY:
				_parent_option.add_item(ch.get("name", ""), idx)
				_parent_option.set_item_metadata(idx, ch.get("id", ""))
				idx += 1
	else:
		# Called from category_item: hide parent dropdown, use parent_id directly
		_type_option.add_item("Category", 4)
		_parent_label.visible = false
		_parent_option.visible = false

func _on_create() -> void:
	var ch_name: String = _name_input.text.strip_edges()
	if ch_name.is_empty():
		_error_label.text = "Channel name cannot be empty."
		_error_label.visible = true
		return

	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var type_map := ["text", "voice", "announcement", "forum", "category"]
	var data := {
		"name": ch_name,
		"type": type_map[_type_option.selected],
	}

	# Categories are always top-level — skip parent_id for category type
	if data["type"] == "category":
		pass
	elif not _parent_id.is_empty():
		data["parent_id"] = _parent_id
	elif _parent_option.visible:
		var parent_idx: int = _parent_option.selected
		if parent_idx > 0:
			var pid = _parent_option.get_item_metadata(parent_idx)
			if pid is String and not pid.is_empty():
				data["parent_id"] = pid

	var result: RestResult = await Client.admin.create_channel(_guild_id, data)
	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var msg: String = "Failed to create channel"
		if result != null and result.error:
			msg = result.error.message
		_error_label.text = msg
		_error_label.visible = true
	else:
		queue_free()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
