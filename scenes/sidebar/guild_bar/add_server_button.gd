extends HBoxContainer

signal add_server_pressed()

var _pulse_tween: Tween
var _normal_style: StyleBoxFlat
var _hover_style: StyleBoxFlat

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $IconButton

func _ready() -> void:
	add_to_group("themed")
	icon_button.icon = IconEmoji.get_texture("plus")
	icon_button.pressed.connect(_on_pressed)
	icon_button.tooltip_text = "Add a Server"
	AppState.reduce_motion_changed.connect(_on_reduce_motion_changed)
	# Style the button as a circle
	_normal_style = StyleBoxFlat.new()
	_normal_style.corner_radius_top_left = 24
	_normal_style.corner_radius_top_right = 24
	_normal_style.corner_radius_bottom_left = 24
	_normal_style.corner_radius_bottom_right = 24
	icon_button.add_theme_stylebox_override("normal", _normal_style)
	_hover_style = _normal_style.duplicate()
	icon_button.add_theme_stylebox_override("hover", _hover_style)
	_apply_theme()

func _apply_theme() -> void:
	_normal_style.bg_color = ThemeManager.get_color("nav_bg")
	_hover_style.bg_color = ThemeManager.get_color("success")

	# Pulse animation when no servers are configured
	if not Config.has_servers():
		_start_pulse()
		AppState.spaces_updated.connect(_stop_pulse, CONNECT_ONE_SHOT)

func _on_pressed() -> void:
	add_server_pressed.emit()

func _start_pulse() -> void:
	if Config.get_reduced_motion():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(
		icon_button, "modulate", Color(1.1, 1.1, 1.1, 1.0), 1.0
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(
		icon_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.0
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	icon_button.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_reduce_motion_changed(enabled: bool) -> void:
	if enabled:
		_stop_pulse()
