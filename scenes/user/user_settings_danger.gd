class_name UserSettingsDanger
extends RefCounted

## Builds and manages the Change Password and Delete Account pages
## within UserSettings.

var _pw_current: LineEdit
var _pw_new: LineEdit
var _pw_confirm: LineEdit
var _pw_error: Label
var _pw_save_btn: Button

var _del_password: LineEdit
var _del_confirm: LineEdit
var _del_error: Label
var _del_btn: Button

var _tree: SceneTree


func build_password_page(
	page_vbox: VBoxContainer,
	section_label_fn: Callable,
	error_label_fn: Callable,
) -> void:
	page_vbox.add_child(section_label_fn.call("CURRENT PASSWORD"))
	_pw_current = LineEdit.new()
	_pw_current.secret = true
	page_vbox.add_child(_pw_current)

	page_vbox.add_child(section_label_fn.call("NEW PASSWORD"))
	_pw_new = LineEdit.new()
	_pw_new.secret = true
	page_vbox.add_child(_pw_new)

	page_vbox.add_child(section_label_fn.call("CONFIRM NEW PASSWORD"))
	_pw_confirm = LineEdit.new()
	_pw_confirm.secret = true
	page_vbox.add_child(_pw_confirm)

	_pw_error = error_label_fn.call()
	page_vbox.add_child(_pw_error)

	_pw_save_btn = Button.new()
	_pw_save_btn.text = "Change Password"
	_pw_save_btn.pressed.connect(_on_password_save)
	page_vbox.add_child(_pw_save_btn)


func _on_password_save() -> void:
	_pw_error.visible = false
	var current: String = _pw_current.text
	var new_pw: String = _pw_new.text
	var confirm: String = _pw_confirm.text
	if current.is_empty():
		_pw_error.text = "Current password is required"
		_pw_error.visible = true
		return
	if new_pw.length() < 8:
		_pw_error.text = "New password must be at least 8 characters"
		_pw_error.visible = true
		return
	if new_pw != confirm:
		_pw_error.text = "Passwords do not match"
		_pw_error.visible = true
		return
	_pw_save_btn.disabled = true
	var result: Dictionary = await Client.change_password(
		current, new_pw
	)
	_pw_save_btn.disabled = false
	if result.get("ok", false):
		_pw_current.text = ""
		_pw_new.text = ""
		_pw_confirm.text = ""
		_pw_error.text = "Password changed successfully"
		_pw_error.add_theme_color_override(
			"font_color", Color(0.231, 0.647, 0.365)
		)
		_pw_error.visible = true
	else:
		_pw_error.add_theme_color_override(
			"font_color", Color(0.929, 0.259, 0.271)
		)
		_pw_error.text = result.get(
			"error", "Failed to change password"
		)
		_pw_error.visible = true


func build_delete_page(
	page_vbox: VBoxContainer,
	section_label_fn: Callable,
	error_label_fn: Callable,
	tree: SceneTree,
) -> void:
	_tree = tree

	var warning := Label.new()
	warning.text = (
		"WARNING: This action is irreversible. "
		+ "All your data will be permanently deleted."
	)
	warning.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD
	page_vbox.add_child(warning)

	page_vbox.add_child(section_label_fn.call("PASSWORD"))
	_del_password = LineEdit.new()
	_del_password.secret = true
	page_vbox.add_child(_del_password)

	page_vbox.add_child(section_label_fn.call("TYPE 'DELETE' TO CONFIRM"))
	_del_confirm = LineEdit.new()
	_del_confirm.placeholder_text = "DELETE"
	page_vbox.add_child(_del_confirm)

	_del_error = error_label_fn.call()
	page_vbox.add_child(_del_error)

	_del_btn = Button.new()
	_del_btn.text = "Delete My Account"
	var del_style := StyleBoxFlat.new()
	del_style.bg_color = Color(0.929, 0.259, 0.271)
	del_style.corner_radius_top_left = 4
	del_style.corner_radius_top_right = 4
	del_style.corner_radius_bottom_left = 4
	del_style.corner_radius_bottom_right = 4
	del_style.content_margin_left = 12.0
	del_style.content_margin_right = 12.0
	del_style.content_margin_top = 8.0
	del_style.content_margin_bottom = 8.0
	_del_btn.add_theme_stylebox_override("normal", del_style)
	_del_btn.pressed.connect(_on_delete_account)
	page_vbox.add_child(_del_btn)


func _on_delete_account() -> void:
	_del_error.visible = false
	var pw: String = _del_password.text
	var confirm_text: String = _del_confirm.text.strip_edges()
	if pw.is_empty():
		_del_error.text = "Password is required"
		_del_error.visible = true
		return
	if confirm_text != "DELETE":
		_del_error.text = "Please type DELETE to confirm"
		_del_error.visible = true
		return
	_del_btn.disabled = true
	var result: Dictionary = await Client.delete_account(pw)
	_del_btn.disabled = false
	if result.get("ok", false):
		_tree.quit()
	else:
		_del_error.text = result.get(
			"error", "Failed to delete account"
		)
		_del_error.visible = true
