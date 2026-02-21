extends VBoxContainer

signal join_pressed(server_url: String, space_id: String)

const SpaceRowScene := preload("res://scenes/sidebar/guild_bar/space_row.tscn")

var _expanded: bool = false

@onready var _header: Button = $Header
@onready var _name_label: Label = $Header/HBox/NameLabel
@onready var _version_label: Label = $Header/HBox/VersionLabel
@onready var _arrow: Label = $Header/HBox/Arrow
@onready var _spaces_container: VBoxContainer = $SpacesContainer

func _ready() -> void:
	_header.pressed.connect(_toggle)
	_spaces_container.visible = false

func setup(server: Dictionary) -> void:
	_name_label.text = server.get("name", "Unknown Server")
	var version: String = server.get("version", "")
	if version.is_empty():
		_version_label.visible = false
	else:
		_version_label.text = "v" + version

	var url: String = server.get("url", "")
	var spaces: Array = server.get("spaces", [])
	for space in spaces:
		var row: HBoxContainer = SpaceRowScene.instantiate()
		_spaces_container.add_child(row)
		row.setup(url, space)
		row.join_pressed.connect(func(s_url: String, s_id: String): join_pressed.emit(s_url, s_id))

func _toggle() -> void:
	_expanded = not _expanded
	_spaces_container.visible = _expanded
	_arrow.text = "▾" if _expanded else "▸"
