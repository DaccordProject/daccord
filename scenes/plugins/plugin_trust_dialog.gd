class_name PluginTrustDialog
extends ModalBase

## Confirmation dialog shown before running an untrusted native plugin.
## The user can trust this plugin once, always for this server, or cancel.

signal trust_granted(remember: bool)
signal trust_denied()

var _plugin_name: String = ""
var _server_name: String = ""

@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _warning_label: RichTextLabel = \
	$CenterContainer/Panel/VBox/Content/WarningLabel
@onready var _remember_check: CheckBox = \
	$CenterContainer/Panel/VBox/Content/RememberCheck
@onready var _cancel_btn: Button = \
	$CenterContainer/Panel/VBox/Content/ButtonRow/CancelButton
@onready var _trust_btn: Button = \
	$CenterContainer/Panel/VBox/Content/ButtonRow/TrustButton


func setup(plugin_name: String, server_name: String) -> void:
	_plugin_name = plugin_name
	_server_name = server_name


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 420)
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_on_cancel)
	_trust_btn.pressed.connect(_on_trust)

	# Style trust button
	ThemeManager.style_button(
		_trust_btn, "accent", "accent_hover",
		"accent_pressed", 4, [16, 6, 16, 6]
	)

	# Apply theme-driven font colors
	ThemeManager.apply_font_colors(self)

	# Set warning text (setup() is called before add_child/ready)
	_warning_label.text = (
		tr("[b]%s[/b] is a native plugin from [b]%s[/b]. ")
		% [_plugin_name, _server_name]
		+ tr("Native plugins run GDScript scenes with full access to "
		+ "Godot's API. Only run plugins from servers you trust.")
	)


func _on_trust() -> void:
	trust_granted.emit(_remember_check.button_pressed)
	_close()


func _on_cancel() -> void:
	trust_denied.emit()
	_close()
