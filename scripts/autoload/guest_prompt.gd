class_name GuestPrompt

## Shared utility for showing a registration prompt when a guest user
## clicks a grayed-out interactive element. Uses class_name so any script
## can call GuestPrompt.show_if_guest() without an autoload dependency.

const AuthDialogScene := preload(
	"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
)

## Returns true if the user is in guest mode (and shows the prompt).
## Call at the top of any interactive handler to gate it:
##   if GuestPrompt.show_if_guest(): return
static func show_if_guest() -> bool:
	if not AppState.is_guest_mode:
		return false
	_show_prompt()
	return true

static func _show_prompt() -> void:
	var root: Window = Engine.get_main_loop().root
	# Prevent duplicate prompts
	for child in root.get_children():
		if child.is_in_group("guest_prompt"):
			return
	var dialog := _build_dialog()
	dialog.add_to_group("guest_prompt")
	root.add_child(dialog)

static func _build_dialog() -> ModalBase:
	var modal := ModalBase.new()
	modal.modal_width = 360.0
	modal._setup_modal("", 360.0, 0.0, false)

	var vbox := modal.content_container

	var title := Label.new()
	title.text = "Create an account to join\nthe conversation"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var register_btn := Button.new()
	register_btn.text = "Register"
	register_btn.custom_minimum_size = Vector2(120, 36)
	btn_row.add_child(register_btn)

	var sign_in_btn := Button.new()
	sign_in_btn.text = "Sign In"
	sign_in_btn.custom_minimum_size = Vector2(120, 36)
	btn_row.add_child(sign_in_btn)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "No thanks"
	dismiss_btn.flat = true
	dismiss_btn.add_theme_font_size_override("font_size", 13)
	dismiss_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(dismiss_btn)

	dismiss_btn.pressed.connect(func(): modal._close())

	register_btn.pressed.connect(func():
		modal._close()
		_open_auth_dialog()
	)
	sign_in_btn.pressed.connect(func():
		modal._close()
		_open_auth_dialog()
	)

	return modal

static func _open_auth_dialog() -> void:
	var base_url := AppState.guest_base_url
	if base_url.is_empty():
		return
	var root: Window = Engine.get_main_loop().root
	var auth_dialog := AuthDialogScene.instantiate()
	auth_dialog.setup(base_url)
	auth_dialog.auth_completed.connect(
		func(resolved_url: String, t: String, u: String, _p: String, dn: String):
			# Determine space_name from current space
			var space_name := "general"
			if not AppState.current_space_id.is_empty():
				var space: Dictionary = Client.get_space_by_id(
					AppState.current_space_id
				)
				if not space.is_empty():
					space_name = space.get("name", "general")
			Client.upgrade_guest_connection(
				resolved_url, t, space_name, u, dn,
			)
	)
	root.add_child(auth_dialog)
