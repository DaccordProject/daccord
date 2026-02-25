extends ColorRect

var _total_servers: int = 0
var _completed: int = 0
var _anim_time: float = 0.0
var _dots: Array[Label] = []
var _dismiss_tween: Tween

@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var detail_label: Label = $CenterContainer/VBox/DetailLabel
@onready var dots_hbox: HBoxContainer = $CenterContainer/VBox/DotsHBox

func _ready() -> void:
	_total_servers = Config.get_servers().size()

	# Create three animated dots
	for i in 3:
		var dot := Label.new()
		dot.text = "."
		dot.add_theme_font_size_override("font_size", 24)
		dot.add_theme_color_override(
			"font_color", Color(0.345, 0.396, 0.949)
		)
		dots_hbox.add_child(dot)
		_dots.append(dot)

	AppState.server_connecting.connect(_on_server_connecting)
	AppState.spaces_updated.connect(_on_server_done)
	AppState.server_connection_failed.connect(_on_server_failed)

	# Fade in
	if Config.get_reduced_motion():
		modulate.a = 1.0
	else:
		modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.3)

func _process(delta: float) -> void:
	if Config.get_reduced_motion():
		return
	_anim_time += delta
	for i in _dots.size():
		var phase: float = _anim_time * 3.0 - float(i) * 0.8
		var alpha: float = (sin(phase) + 1.0) * 0.5
		alpha = clampf(alpha, 0.3, 1.0)
		_dots[i].modulate.a = alpha

func _on_server_connecting(
	server_name: String, index: int, total: int,
) -> void:
	_total_servers = total
	detail_label.text = "Connecting to %s (%d/%d)" % [
		server_name, index + 1, total,
	]

func _on_server_done() -> void:
	_completed += 1
	_check_dismiss()

func _on_server_failed(
	_space_id: String, _reason: String,
) -> void:
	_completed += 1
	_check_dismiss()

func _check_dismiss() -> void:
	if _completed >= _total_servers:
		dismiss()

func dismiss() -> void:
	if _dismiss_tween:
		return
	set_process(false)
	if Config.get_reduced_motion():
		queue_free()
		return
	_dismiss_tween = create_tween()
	_dismiss_tween.tween_property(
		self, "modulate:a", 0.0, 0.3
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_dismiss_tween.tween_callback(queue_free)
