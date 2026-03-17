extends PanelContainer

## Single activity card displayed in the activity modal.

signal launch_pressed(plugin_id: String)

var _plugin_id: String = ""

@onready var _name_label: Label = $HBox/Info/NameLabel
@onready var _desc_label: Label = $HBox/Info/DescLabel
@onready var _meta_row: HBoxContainer = $HBox/Info/MetaRow
@onready var _runtime_label: Label = $HBox/Info/MetaRow/RuntimeLabel
@onready var _launch_btn: Button = $HBox/LaunchButton


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		ThemeManager.make_flat_style("input_bg", 6, [12, 10, 12, 10])
	)
	_desc_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_runtime_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	ThemeManager.style_button(
		_launch_btn, "accent", "accent_hover",
		"accent_pressed", 4, [12, 6, 12, 6]
	)
	_launch_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	_launch_btn.pressed.connect(
		func() -> void: launch_pressed.emit(_plugin_id)
	)


func setup(plugin: Dictionary) -> void:
	_plugin_id = plugin.get("id", "")
	_name_label.text = plugin.get("name", tr("Unknown"))
	_desc_label.text = plugin.get("description", "")
	var rt: String = plugin.get("runtime", "scripted")
	_runtime_label.text = rt.capitalize()

	var max_p: int = plugin.get("max_participants", 0)
	if max_p > 0:
		var p_label := Label.new()
		p_label.text = tr("%d players max") % max_p
		p_label.add_theme_font_size_override("font_size", 11)
		p_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_meta_row.add_child(p_label)

	var version_str: String = plugin.get("version", "")
	if not version_str.is_empty():
		var v_label := Label.new()
		v_label.text = "v" + version_str
		v_label.add_theme_font_size_override("font_size", 11)
		v_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_meta_row.add_child(v_label)
