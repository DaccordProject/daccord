extends RefCounted

## Manages overlay UI: welcome screen, consent dialog, toasts,
## image lightbox, and profile cards.

const ProfileCardScene := preload(
	"res://scenes/user/profile_card.tscn"
)
const WelcomeScreenScene := preload(
	"res://scenes/main/welcome_screen.tscn"
)
const ImageLightboxScene := preload(
	"res://scenes/messages/image_lightbox.tscn"
)
const ToastScene := preload(
	"res://scenes/main/toast.tscn"
)

var _parent: Control
var _welcome_screen: Control = null
var _active_profile_card: PanelContainer = null
var _layout_hbox: HBoxContainer


func _init(
	parent: Control, layout_hbox: HBoxContainer,
) -> void:
	_parent = parent
	_layout_hbox = layout_hbox


func show_welcome_screen() -> void:
	_welcome_screen = WelcomeScreenScene.instantiate()
	_parent.add_child(_welcome_screen)
	_layout_hbox.visible = false
	if not AppState.spaces_updated.is_connected(on_first_server_added):
		AppState.spaces_updated.connect(
			on_first_server_added, CONNECT_ONE_SHOT
		)


func on_first_server_added() -> void:
	if not Config.has_servers():
		if not AppState.spaces_updated.is_connected(on_first_server_added):
			AppState.spaces_updated.connect(
				on_first_server_added, CONNECT_ONE_SHOT
			)
		return
	if _welcome_screen and is_instance_valid(_welcome_screen):
		_welcome_screen.dismissed.connect(func() -> void:
			_layout_hbox.visible = true
			_welcome_screen = null
		)
		_welcome_screen.dismiss()
	else:
		_layout_hbox.visible = true
		_welcome_screen = null


func show_consent_dialog() -> void:
	Config.set_error_reporting_consent_shown()
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Error Reporting")
	dialog.dialog_text = tr(
		"Help improve daccord by sending anonymous crash and "
		+ "error reports?\n\n"
		+ "No personal data is included. You can change this "
		+ "in Settings > Notifications at any time."
	)
	dialog.ok_button_text = tr("Enable")
	dialog.cancel_button_text = tr("No thanks")
	dialog.confirmed.connect(func() -> void:
		Config.set_error_reporting_enabled(true)
		ErrorReporting.init_sentry()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		Config.set_error_reporting_enabled(false)
		dialog.queue_free()
	)
	_parent.add_child(dialog)
	dialog.popup_centered()


func show_crash_toast() -> void:
	show_toast(
		tr("An error report from your last session was sent.")
	)


func show_toast(text: String, is_error: bool = false) -> void:
	var toast: PanelContainer = ToastScene.instantiate()
	toast.setup(text, is_error)
	_parent.add_child(toast)


func on_image_lightbox_requested(
	_url: String, texture: ImageTexture,
) -> void:
	if texture == null:
		return
	var lightbox: ColorRect = ImageLightboxScene.instantiate()
	_parent.add_child(lightbox)
	lightbox.show_image(texture)


func on_profile_card_requested(
	user_id: String, pos: Vector2,
) -> void:
	if _active_profile_card and is_instance_valid(_active_profile_card):
		_active_profile_card.queue_free()
	var user_data: Dictionary = Client.get_user_by_id(user_id)
	if user_data.is_empty():
		return
	_active_profile_card = ProfileCardScene.instantiate()
	_parent.add_child(_active_profile_card)
	var space_id: String = ""
	if not AppState.is_dm_mode:
		space_id = AppState.current_space_id
	_active_profile_card.setup(user_data, space_id)
	await _parent.get_tree().process_frame
	var vp_size := _parent.get_viewport().get_visible_rect().size
	var card_size := _active_profile_card.size
	var x: float = clampf(pos.x, 0.0, vp_size.x - card_size.x)
	var y: float = clampf(pos.y, 0.0, vp_size.y - card_size.y)
	_active_profile_card.position = Vector2(x, y)
