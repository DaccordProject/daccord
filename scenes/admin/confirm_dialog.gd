extends ColorRect

signal confirmed()

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _message_label: Label = $CenterContainer/Panel/VBox/Message
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _confirm_btn: Button = $CenterContainer/Panel/VBox/Buttons/ConfirmButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_confirm_btn.pressed.connect(_on_confirm)

func setup(
	title: String, message: String,
	confirm_text: String = "Confirm", danger: bool = false,
) -> void:
	if _title_label:
		_title_label.text = title
	if _message_label:
		_message_label.text = message
	if _confirm_btn:
		_confirm_btn.text = confirm_text
		if danger:
			var danger_style := StyleBoxFlat.new()
			danger_style.bg_color = Color(0.85, 0.24, 0.24)
			danger_style.corner_radius_top_left = 4
			danger_style.corner_radius_top_right = 4
			danger_style.corner_radius_bottom_left = 4
			danger_style.corner_radius_bottom_right = 4
			danger_style.content_margin_left = 12.0
			danger_style.content_margin_top = 4.0
			danger_style.content_margin_right = 12.0
			danger_style.content_margin_bottom = 4.0
			_confirm_btn.add_theme_stylebox_override("normal", danger_style)
			var danger_hover := danger_style.duplicate()
			danger_hover.bg_color = Color(0.95, 0.3, 0.3)
			_confirm_btn.add_theme_stylebox_override("hover", danger_hover)

func _on_confirm() -> void:
	confirmed.emit()
	_close()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
