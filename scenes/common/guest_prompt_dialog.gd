extends ModalBase

const AuthDialogScene := preload(
	"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
)

@onready var _register_btn: Button = %RegisterButton
@onready var _sign_in_btn: Button = %SignInButton
@onready var _dismiss_btn: Button = %DismissButton

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 360.0)
	_dismiss_btn.pressed.connect(_close)
	_register_btn.pressed.connect(_on_auth)
	_sign_in_btn.pressed.connect(_on_auth)

func _on_auth() -> void:
	_close()
	GuestPrompt._open_auth_dialog()
