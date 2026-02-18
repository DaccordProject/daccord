extends HBoxContainer

signal delete_requested(sound: Dictionary)
signal play_requested(sound: Dictionary)
signal rename_requested(sound: Dictionary, new_name: String)
signal volume_changed(sound: Dictionary, new_volume: float)

var _sound_data: Dictionary = {}
var _can_manage: bool = false
var _editing: bool = false

@onready var _play_btn: Button = $PlayButton
@onready var _name_label: Label = $NameLabel
@onready var _name_edit: LineEdit = $NameEdit
@onready var _volume_slider: HSlider = $VolumeSlider
@onready var _volume_label: Label = $VolumeLabel
@onready var _rename_btn: Button = $RenameButton
@onready var _delete_btn: Button = $DeleteButton

func _ready() -> void:
	_play_btn.pressed.connect(func(): play_requested.emit(_sound_data))
	_delete_btn.pressed.connect(func(): delete_requested.emit(_sound_data))
	_rename_btn.pressed.connect(_on_rename_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_name_edit.visible = false

func setup(sound: Dictionary, can_manage: bool) -> void:
	_sound_data = sound
	_can_manage = can_manage
	_name_label.text = sound.get("name", "")
	_name_edit.text = sound.get("name", "")
	_volume_slider.value = sound.get("volume", 1.0)
	_volume_label.text = "%d%%" % int(sound.get("volume", 1.0) * 100)
	_rename_btn.visible = can_manage
	_delete_btn.visible = can_manage
	_volume_slider.editable = can_manage

func _on_rename_pressed() -> void:
	if _editing:
		_finish_rename()
	else:
		_editing = true
		_name_label.visible = false
		_name_edit.visible = true
		_name_edit.text = _sound_data.get("name", "")
		_name_edit.grab_focus()
		_rename_btn.text = "Save"

func _on_name_submitted(_new_text: String) -> void:
	_finish_rename()

func _finish_rename() -> void:
	_editing = false
	var new_name := _name_edit.text.strip_edges()
	_name_label.visible = true
	_name_edit.visible = false
	_rename_btn.text = "Rename"
	if not new_name.is_empty() and new_name != _sound_data.get("name", ""):
		rename_requested.emit(_sound_data, new_name)

func _on_volume_changed(value: float) -> void:
	_volume_label.text = "%d%%" % int(value * 100)
	volume_changed.emit(_sound_data, value)
