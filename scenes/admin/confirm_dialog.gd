extends ModalBase

signal confirmed()

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _message_label: Label = $CenterContainer/Panel/VBox/Message
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _confirm_btn: Button = $CenterContainer/Panel/VBox/Buttons/ConfirmButton

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 380, 0)
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
			ThemeManager.style_button(
				_confirm_btn, "error", "error_hover", "error_pressed",
				4, [12, 4, 12, 4]
			)

func _on_confirm() -> void:
	confirmed.emit()
	_close()

