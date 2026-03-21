extends HBoxContainer

signal toggled(pressed: bool, code: String)
signal copy_requested(code: String)
signal revoke_requested(code: String)

var _code: String = ""
var _space_id: String = ""

@onready var _checkbox: CheckBox = $CheckBox
@onready var _code_label: Label = $CodeLabel
@onready var _uses_label: Label = $UsesLabel
@onready var _copy_btn: Button = $CopyButton
@onready var _revoke_btn: Button = $RevokeButton

func _ready() -> void:
	_checkbox.toggled.connect(func(pressed: bool): toggled.emit(pressed, _code))
	_copy_btn.pressed.connect(_on_copy)
	_revoke_btn.pressed.connect(func(): revoke_requested.emit(_code))
	ThemeManager.apply_font_colors(self)

func _on_copy() -> void:
	var url := _build_invite_url()
	DisplayServer.clipboard_set(url)
	copy_requested.emit(_code)

func _build_invite_url() -> String:
	var base_url: String = Client.get_base_url_for_space(_space_id)
	if base_url.is_empty():
		return _code
	# Generate an HTTP URL so links are shareable anywhere — the server
	# will redirect to daccord:// for desktop clients.
	if not base_url.ends_with("/"):
		base_url += "/"
	return base_url + "invite/" + _code

func setup(invite: Dictionary, selected: bool, space_id: String = "") -> void:
	_code = invite.get("code", "")
	_space_id = space_id
	set_meta("code", _code)
	_code_label.text = _code
	_checkbox.button_pressed = selected

	var uses: int = invite.get("uses", 0)
	var max_uses: int = invite.get("max_uses", 0)
	if max_uses > 0:
		_uses_label.text = tr("%d/%d uses") % [uses, max_uses]
	else:
		_uses_label.text = tr("%d uses") % uses
