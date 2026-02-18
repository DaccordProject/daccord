extends HBoxContainer

signal toggled(pressed: bool, code: String)
signal copy_requested(code: String)
signal revoke_requested(code: String)

var _code: String = ""

@onready var _checkbox: CheckBox = $CheckBox
@onready var _code_label: Label = $CodeLabel
@onready var _uses_label: Label = $UsesLabel
@onready var _copy_btn: Button = $CopyButton
@onready var _revoke_btn: Button = $RevokeButton

func _ready() -> void:
	_checkbox.toggled.connect(func(pressed: bool): toggled.emit(pressed, _code))
	_copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(_code)
		copy_requested.emit(_code)
	)
	_revoke_btn.pressed.connect(func(): revoke_requested.emit(_code))

func setup(invite: Dictionary, selected: bool) -> void:
	_code = invite.get("code", "")
	set_meta("code", _code)
	_code_label.text = _code
	_checkbox.button_pressed = selected

	var uses: int = invite.get("uses", 0)
	var max_uses: int = invite.get("max_uses", 0)
	if max_uses > 0:
		_uses_label.text = "%d/%d uses" % [uses, max_uses]
	else:
		_uses_label.text = "%d uses" % uses
