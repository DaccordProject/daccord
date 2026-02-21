extends HBoxContainer

signal join_pressed(server_url: String, space_id: String)

var _server_url: String = ""
var _space_id: String = ""

@onready var _name_label: Label = $Info/NameLabel
@onready var _desc_label: Label = $Info/DescLabel
@onready var _members_label: Label = $Info/MembersLabel
@onready var _join_btn: Button = $JoinButton

func _ready() -> void:
	_join_btn.pressed.connect(_on_join)

func setup(server_url: String, space: Dictionary) -> void:
	_server_url = server_url
	_space_id = space.get("space_id", "")
	_name_label.text = space.get("name", "Unknown")
	var desc: String = space.get("description", "")
	if desc.is_empty():
		_desc_label.visible = false
	else:
		_desc_label.text = desc
	var count: int = space.get("member_count", 0)
	_members_label.text = "%d member%s" % [count, "" if count == 1 else "s"]

func _on_join() -> void:
	join_pressed.emit(_server_url, _space_id)
