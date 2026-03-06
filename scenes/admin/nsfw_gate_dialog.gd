extends ModalBase

signal acknowledged()

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _confirm_btn: Button = $CenterContainer/Panel/VBox/Buttons/ConfirmButton

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 420, 0)
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_confirm_btn.pressed.connect(_on_acknowledge)

func _on_acknowledge() -> void:
	acknowledged.emit()
	_close()
