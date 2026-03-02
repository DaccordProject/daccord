extends Node

## Centralised theme manager. Holds a semantic color palette and applies it to
## the global Theme resource. Components read colors via `ThemeManager.get_color()`
## and long-lived nodes connect to `AppState.theme_changed` for live updates.

var _palette: Dictionary = {}
var _presets: Dictionary = {}

func _ready() -> void:
	_init_presets()
	_load_palette()
	_apply_to_theme()


# --- Public API ---

func get_color(key: String) -> Color:
	if _palette.has(key):
		return _palette[key]
	push_warning("[ThemeManager] Unknown color key: %s" % key)
	return Color.MAGENTA


func get_palette() -> Dictionary:
	return _palette.duplicate()


func set_palette(new_palette: Dictionary) -> void:
	_palette = new_palette.duplicate()
	_apply_to_theme()
	_notify_theme_changed()


func apply_preset(preset_name: String) -> void:
	if not _presets.has(preset_name):
		push_warning("[ThemeManager] Unknown preset: %s" % preset_name)
		return
	Config.set_theme_preset(preset_name)
	_palette = _presets[preset_name].duplicate()
	_apply_to_theme()
	_notify_theme_changed()


func apply_custom_color(key: String, color: Color) -> void:
	_palette[key] = color
	var saved: Dictionary = Config.get_custom_palette()
	saved[key] = color.to_html(true)
	Config.set_custom_palette(saved)
	Config.set_theme_preset("custom")
	_apply_to_theme()
	_notify_theme_changed()


func get_preset_names() -> Array:
	return ["dark", "light", "nord", "monokai", "solarized"]


func export_theme_string() -> String:
	var dict := {}
	for key in _palette:
		dict[key] = _palette[key].to_html(true)
	var json := JSON.stringify(dict)
	return Marshalls.utf8_to_base64(json)


func import_theme_string(base64_str: String) -> bool:
	var json: String = Marshalls.base64_to_utf8(base64_str)
	if json.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or not (parsed is Dictionary):
		return false
	var new_palette: Dictionary = _presets["dark"].duplicate()
	for key in parsed:
		if new_palette.has(key) and parsed[key] is String:
			new_palette[key] = Color.from_string(parsed[key], Color.MAGENTA)
	_palette = new_palette
	# Save as custom
	var save_dict := {}
	for key in _palette:
		save_dict[key] = _palette[key].to_html(true)
	Config.set_custom_palette(save_dict)
	Config.set_theme_preset("custom")
	_apply_to_theme()
	_notify_theme_changed()
	return true


# --- Internal ---

func _notify_theme_changed() -> void:
	AppState.theme_changed.emit()
	get_tree().call_group("themed", "_apply_theme")


func _load_palette() -> void:
	var preset_name: String = Config.get_theme_preset()
	if preset_name == "custom":
		# Start from dark, overlay custom values
		_palette = _presets["dark"].duplicate()
		var saved: Dictionary = Config.get_custom_palette()
		for key in saved:
			if _palette.has(key) and saved[key] is String:
				_palette[key] = Color.from_string(saved[key], _palette[key])
	elif _presets.has(preset_name):
		_palette = _presets[preset_name].duplicate()
	else:
		_palette = _presets["dark"].duplicate()


func _apply_to_theme() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		return

	# Update StyleBoxFlat backgrounds on common types
	_set_stylebox_color(theme, "PanelContainer", "panel", "panel_bg")
	_set_stylebox_color(theme, "PopupPanel", "panel", "popup_bg")

	# Button styles
	_set_stylebox_color(theme, "Button", "hover", "button_hover")
	_set_stylebox_color(theme, "Button", "pressed", "button_pressed")

	# Font colors on common types
	_set_font_color(theme, "Label", "font_color", "text_body")
	_set_font_color(theme, "Button", "font_color", "text_body")
	_set_font_color(theme, "Button", "font_hover_color", "text_body")
	_set_font_color(theme, "LineEdit", "font_color", "text_body")
	_set_font_color(theme, "TextEdit", "font_color", "text_body")
	_set_font_color(theme, "RichTextLabel", "default_color", "text_body")

	# LineEdit / TextEdit backgrounds
	_set_stylebox_color(theme, "LineEdit", "normal", "input_bg")
	_set_stylebox_color(theme, "TextEdit", "normal", "input_bg")

	# Scrollbar
	_set_stylebox_color(theme, "VScrollBar", "grabber", "scrollbar")
	_set_stylebox_color(theme, "VScrollBar", "grabber_highlight", "scrollbar_hover")
	_set_stylebox_color(theme, "HScrollBar", "grabber", "scrollbar")
	_set_stylebox_color(theme, "HScrollBar", "grabber_highlight", "scrollbar_hover")


func _set_stylebox_color(theme: Theme, type: String, style_name: String, color_key: String) -> void:
	if not theme.has_stylebox(style_name, type):
		return
	var sb: StyleBox = theme.get_stylebox(style_name, type)
	if sb is StyleBoxFlat:
		sb.bg_color = _palette.get(color_key, Color.MAGENTA)


func _set_font_color(theme: Theme, type: String, color_name: String, color_key: String) -> void:
	if theme.has_color(color_name, type):
		theme.set_color(color_name, type, _palette.get(color_key, Color.MAGENTA))


func _init_presets() -> void:
	# Dark — current Discord-like defaults
	_presets["dark"] = {
		"accent": Color(0.345, 0.396, 0.949),
		"accent_hover": Color(0.29, 0.34, 0.87),
		"accent_pressed": Color(0.25, 0.30, 0.80),
		"text_body": Color(0.839, 0.851, 0.878),
		"text_muted": Color(0.58, 0.608, 0.643),
		"text_white": Color.WHITE,
		"error": Color(0.929, 0.259, 0.271),
		"error_hover": Color(0.85, 0.2, 0.22),
		"error_pressed": Color(0.78, 0.18, 0.2),
		"success": Color(0.263, 0.694, 0.431),
		"warning": Color(1.0, 0.85, 0.2),
		"link": Color(0.0, 0.6, 0.88),
		"panel_bg": Color(0.176, 0.184, 0.204),
		"nav_bg": Color(0.153, 0.161, 0.176),
		"input_bg": Color(0.118, 0.125, 0.141),
		"modal_bg": Color(0.184, 0.192, 0.212),
		"settings_bg": Color(0.188, 0.196, 0.212),
		"button_hover": Color(0.24, 0.25, 0.27),
		"button_pressed": Color(0.2, 0.21, 0.23),
		"icon_default": Color(0.58, 0.608, 0.643),
		"icon_hover": Color(0.839, 0.851, 0.878),
		"icon_active": Color.WHITE,
		"overlay": Color(0, 0, 0, 0.6),
		"mention_bg": Color(0.345, 0.396, 0.949, 0.15),
		"popup_bg": Color(0.11, 0.118, 0.133),
		"scrollbar": Color(0.118, 0.125, 0.141),
		"scrollbar_hover": Color(0.153, 0.161, 0.176),
		"secondary_button": Color(0.24, 0.25, 0.27),
		"secondary_button_hover": Color(0.28, 0.29, 0.31),
		"secondary_button_pressed": Color(0.2, 0.21, 0.23),
	}

	# Light
	_presets["light"] = {
		"accent": Color(0.345, 0.396, 0.949),
		"accent_hover": Color(0.29, 0.34, 0.87),
		"accent_pressed": Color(0.25, 0.30, 0.80),
		"text_body": Color(0.18, 0.2, 0.22),
		"text_muted": Color(0.42, 0.44, 0.48),
		"text_white": Color.WHITE,
		"error": Color(0.85, 0.18, 0.2),
		"error_hover": Color(0.75, 0.12, 0.15),
		"error_pressed": Color(0.65, 0.1, 0.12),
		"success": Color(0.18, 0.6, 0.35),
		"warning": Color(0.9, 0.75, 0.0),
		"link": Color(0.0, 0.5, 0.8),
		"panel_bg": Color(0.96, 0.96, 0.97),
		"nav_bg": Color(0.91, 0.92, 0.93),
		"input_bg": Color(0.88, 0.89, 0.9),
		"modal_bg": Color(0.96, 0.96, 0.97),
		"settings_bg": Color(0.96, 0.96, 0.97),
		"button_hover": Color(0.85, 0.86, 0.88),
		"button_pressed": Color(0.8, 0.81, 0.83),
		"icon_default": Color(0.42, 0.44, 0.48),
		"icon_hover": Color(0.25, 0.27, 0.3),
		"icon_active": Color(0.1, 0.1, 0.12),
		"overlay": Color(0, 0, 0, 0.4),
		"mention_bg": Color(0.345, 0.396, 0.949, 0.1),
		"popup_bg": Color(0.98, 0.98, 0.99),
		"scrollbar": Color(0.78, 0.79, 0.82),
		"scrollbar_hover": Color(0.68, 0.7, 0.73),
		"secondary_button": Color(0.85, 0.86, 0.88),
		"secondary_button_hover": Color(0.8, 0.81, 0.83),
		"secondary_button_pressed": Color(0.75, 0.76, 0.78),
	}

	# Nord
	_presets["nord"] = {
		"accent": Color(0.506, 0.631, 0.757),
		"accent_hover": Color(0.45, 0.58, 0.71),
		"accent_pressed": Color(0.4, 0.53, 0.66),
		"text_body": Color(0.847, 0.871, 0.914),
		"text_muted": Color(0.616, 0.667, 0.737),
		"text_white": Color(0.925, 0.937, 0.957),
		"error": Color(0.749, 0.38, 0.416),
		"error_hover": Color(0.67, 0.32, 0.36),
		"error_pressed": Color(0.59, 0.27, 0.31),
		"success": Color(0.639, 0.745, 0.549),
		"warning": Color(0.922, 0.796, 0.545),
		"link": Color(0.506, 0.631, 0.757),
		"panel_bg": Color(0.18, 0.204, 0.251),
		"nav_bg": Color(0.157, 0.176, 0.22),
		"input_bg": Color(0.133, 0.153, 0.192),
		"modal_bg": Color(0.18, 0.204, 0.251),
		"settings_bg": Color(0.18, 0.204, 0.251),
		"button_hover": Color(0.231, 0.259, 0.322),
		"button_pressed": Color(0.208, 0.235, 0.29),
		"icon_default": Color(0.616, 0.667, 0.737),
		"icon_hover": Color(0.847, 0.871, 0.914),
		"icon_active": Color(0.925, 0.937, 0.957),
		"overlay": Color(0, 0, 0, 0.6),
		"mention_bg": Color(0.506, 0.631, 0.757, 0.15),
		"popup_bg": Color(0.157, 0.176, 0.22),
		"scrollbar": Color(0.208, 0.235, 0.29),
		"scrollbar_hover": Color(0.231, 0.259, 0.322),
		"secondary_button": Color(0.231, 0.259, 0.322),
		"secondary_button_hover": Color(0.263, 0.298, 0.369),
		"secondary_button_pressed": Color(0.208, 0.235, 0.29),
	}

	# Monokai
	_presets["monokai"] = {
		"accent": Color(0.639, 0.835, 0.227),
		"accent_hover": Color(0.56, 0.75, 0.18),
		"accent_pressed": Color(0.48, 0.66, 0.14),
		"text_body": Color(0.973, 0.973, 0.949),
		"text_muted": Color(0.6, 0.6, 0.55),
		"text_white": Color(0.973, 0.973, 0.949),
		"error": Color(0.984, 0.365, 0.365),
		"error_hover": Color(0.9, 0.28, 0.28),
		"error_pressed": Color(0.82, 0.22, 0.22),
		"success": Color(0.639, 0.835, 0.227),
		"warning": Color(0.902, 0.859, 0.455),
		"link": Color(0.404, 0.855, 0.996),
		"panel_bg": Color(0.157, 0.157, 0.129),
		"nav_bg": Color(0.133, 0.133, 0.106),
		"input_bg": Color(0.114, 0.114, 0.09),
		"modal_bg": Color(0.157, 0.157, 0.129),
		"settings_bg": Color(0.157, 0.157, 0.129),
		"button_hover": Color(0.2, 0.2, 0.17),
		"button_pressed": Color(0.18, 0.18, 0.15),
		"icon_default": Color(0.6, 0.6, 0.55),
		"icon_hover": Color(0.973, 0.973, 0.949),
		"icon_active": Color(0.639, 0.835, 0.227),
		"overlay": Color(0, 0, 0, 0.65),
		"mention_bg": Color(0.639, 0.835, 0.227, 0.12),
		"popup_bg": Color(0.114, 0.114, 0.09),
		"scrollbar": Color(0.2, 0.2, 0.17),
		"scrollbar_hover": Color(0.25, 0.25, 0.21),
		"secondary_button": Color(0.2, 0.2, 0.17),
		"secondary_button_hover": Color(0.24, 0.24, 0.2),
		"secondary_button_pressed": Color(0.18, 0.18, 0.15),
	}

	# Solarized Dark
	_presets["solarized"] = {
		"accent": Color(0.149, 0.545, 0.824),
		"accent_hover": Color(0.12, 0.47, 0.73),
		"accent_pressed": Color(0.1, 0.4, 0.64),
		"text_body": Color(0.514, 0.58, 0.588),
		"text_muted": Color(0.396, 0.482, 0.514),
		"text_white": Color(0.933, 0.91, 0.835),
		"error": Color(0.863, 0.196, 0.184),
		"error_hover": Color(0.76, 0.14, 0.13),
		"error_pressed": Color(0.66, 0.1, 0.1),
		"success": Color(0.522, 0.6, 0.0),
		"warning": Color(0.71, 0.537, 0.0),
		"link": Color(0.149, 0.545, 0.824),
		"panel_bg": Color(0.0, 0.169, 0.212),
		"nav_bg": Color(0.0, 0.145, 0.18),
		"input_bg": Color(0.027, 0.212, 0.259),
		"modal_bg": Color(0.0, 0.169, 0.212),
		"settings_bg": Color(0.0, 0.169, 0.212),
		"button_hover": Color(0.027, 0.212, 0.259),
		"button_pressed": Color(0.0, 0.145, 0.18),
		"icon_default": Color(0.396, 0.482, 0.514),
		"icon_hover": Color(0.514, 0.58, 0.588),
		"icon_active": Color(0.933, 0.91, 0.835),
		"overlay": Color(0, 0, 0, 0.6),
		"mention_bg": Color(0.149, 0.545, 0.824, 0.15),
		"popup_bg": Color(0.0, 0.145, 0.18),
		"scrollbar": Color(0.027, 0.212, 0.259),
		"scrollbar_hover": Color(0.035, 0.255, 0.31),
		"secondary_button": Color(0.027, 0.212, 0.259),
		"secondary_button_hover": Color(0.035, 0.255, 0.31),
		"secondary_button_pressed": Color(0.0, 0.145, 0.18),
	}
