extends HBoxContainer

## Reusable password input with a visibility-toggle eye button.
##
## Wraps a LineEdit (secret=true by default) and a flat icon Button that
## toggles password visibility.  Exposes the same text/signal API as
## LineEdit so dialogs can use it as a drop-in replacement.
##
## Focus: the HBoxContainer accepts focus (FOCUS_ALL) and immediately
## redirects it to the inner LineEdit via the focus_entered signal, so
## callers can call grab_focus() on the PasswordField node as usual.

signal text_changed(new_text: String)
signal text_submitted(submitted_text: String)

## Exported so the placeholder can be set directly in the scene file.
@export var placeholder_text: String = "":
	set(v):
		placeholder_text = v
		if _input != null:
			_input.placeholder_text = v

# --- Public API (mirrors LineEdit) ---
# Getters/setters delegate to the inner LineEdit once the node is ready.

var text: String:
	get:
		if _input == null:
			return ""
		return _input.text
	set(v):
		if _input == null:
			return
		_input.text = v

var secret: bool:
	get:
		if _input == null:
			return true
		return _input.secret
	set(v):
		if _input == null:
			return
		_input.secret = v
		_update_icon()

var editable: bool:
	get:
		if _input == null:
			return true
		return _input.editable
	set(v):
		if _input == null or _toggle_btn == null:
			return
		_input.editable = v
		_toggle_btn.visible = v

var _icon_eye: Texture2D
var _icon_eye_closed: Texture2D

@onready var _input: LineEdit = $Input
@onready var _toggle_btn: Button = $ToggleBtn


func _ready() -> void:
	_icon_eye = load("res://assets/theme/icons/eye.svg")
	_icon_eye_closed = load("res://assets/theme/icons/eye_closed.svg")
	_input.placeholder_text = placeholder_text
	_input.text_changed.connect(func(t: String) -> void: text_changed.emit(t))
	_input.text_submitted.connect(func(t: String) -> void: text_submitted.emit(t))
	_toggle_btn.pressed.connect(_on_toggle)
	# Redirect focus from the container to the inner input.
	focus_entered.connect(func() -> void: _input.grab_focus())
	_update_icon()


# --- Private ---

func _on_toggle() -> void:
	secret = not secret


func _update_icon() -> void:
	if _toggle_btn == null or _input == null:
		return
	_toggle_btn.icon = _icon_eye_closed if _input.secret else _icon_eye
