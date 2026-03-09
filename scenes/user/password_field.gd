class_name PasswordField
extends HBoxContainer

## Reusable password input with a visibility-toggle eye button.
##
## Wraps a LineEdit (secret=true by default) and a flat icon Button that
## toggles password visibility.  Exposes the same text/signal API as
## LineEdit so dialogs can use it as a drop-in replacement.

signal text_changed(new_text: String)
signal text_submitted(submitted_text: String)

const _ICON_EYE: Texture2D = preload("res://assets/theme/icons/eye.svg")
const _ICON_EYE_CLOSED: Texture2D = preload("res://assets/theme/icons/eye_closed.svg")

## Exported so the placeholder can be set directly in the scene file.
@export var placeholder_text: String = "":
	set(v):
		placeholder_text = v
		if _input != null:
			_input.placeholder_text = v

@onready var _input: LineEdit = $Input
@onready var _toggle_btn: Button = $ToggleBtn

# --- Public API (mirrors LineEdit) ---

var text: String:
	get:
		return _input.text
	set(v):
		_input.text = v

var secret: bool:
	get:
		return _input.secret
	set(v):
		_input.secret = v
		_update_icon()

var editable: bool:
	get:
		return _input.editable
	set(v):
		_input.editable = v
		_toggle_btn.visible = v


func _ready() -> void:
	_input.placeholder_text = placeholder_text
	_input.text_changed.connect(func(t: String) -> void: text_changed.emit(t))
	_input.text_submitted.connect(func(t: String) -> void: text_submitted.emit(t))
	_toggle_btn.pressed.connect(_on_toggle)
	_update_icon()


func grab_focus() -> void:
	_input.grab_focus()


# --- Private ---

func _on_toggle() -> void:
	secret = not secret


func _update_icon() -> void:
	if _toggle_btn == null:
		return
	_toggle_btn.icon = _ICON_EYE_CLOSED if _input.secret else _ICON_EYE
