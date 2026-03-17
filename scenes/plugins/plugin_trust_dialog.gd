class_name PluginTrustDialog
extends ModalBase

## Confirmation dialog shown before running an untrusted native plugin.
## The user can trust this plugin once, always for this server, or cancel.

signal trust_granted(remember: bool)
signal trust_denied()

var _plugin_name: String = ""
var _server_name: String = ""
var _remember_check: CheckBox


func setup(plugin_name: String, server_name: String) -> void:
	_plugin_name = plugin_name
	_server_name = server_name


func _ready() -> void:
	_setup_modal(tr("Trust Native Plugin?"), 420.0)

	var warning_label := RichTextLabel.new()
	warning_label.bbcode_enabled = true
	warning_label.fit_content = true
	warning_label.scroll_active = false
	warning_label.text = (
		tr("[b]%s[/b] is a native plugin from [b]%s[/b]. ")
		% [_plugin_name, _server_name]
		+ tr("Native plugins run GDScript scenes with full access to "
		+ "Godot's API. Only run plugins from servers you trust.")
	)
	content_container.add_child(warning_label)

	var unsigned_label := Label.new()
	unsigned_label.text = tr("This plugin is not signed.")
	unsigned_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("error")
	)
	unsigned_label.add_theme_font_size_override("font_size", 13)
	content_container.add_child(unsigned_label)

	_remember_check = CheckBox.new()
	_remember_check.text = tr("Always trust plugins from this server")
	content_container.add_child(_remember_check)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	content_container.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var trust_btn := Button.new()
	trust_btn.text = tr("Trust & Run")
	var trust_style := StyleBoxFlat.new()
	trust_style.bg_color = ThemeManager.get_color("accent")
	trust_style.set_corner_radius_all(4)
	trust_style.content_margin_left = 16
	trust_style.content_margin_right = 16
	trust_style.content_margin_top = 6
	trust_style.content_margin_bottom = 6
	trust_btn.add_theme_stylebox_override("normal", trust_style)
	trust_btn.pressed.connect(_on_trust)
	btn_row.add_child(trust_btn)


func _on_trust() -> void:
	trust_granted.emit(_remember_check.button_pressed)
	_close()


func _on_cancel() -> void:
	trust_denied.emit()
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
