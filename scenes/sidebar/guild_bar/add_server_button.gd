extends HBoxContainer

signal add_server_pressed()

var _pulse_tween: Tween

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $IconButton

func _ready() -> void:
	icon_button.pressed.connect(_on_pressed)
	icon_button.tooltip_text = "Add a Server"
	# Style the button as a circle
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.212, 0.224, 0.247)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	icon_button.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.176, 0.557, 0.384)
	icon_button.add_theme_stylebox_override("hover", hover_style)

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
