extends RefCounted

const CreateProfileDialogScene := preload(
	"res://scenes/user/create_profile_dialog.tscn"
)
const ProfilePasswordDialogScene := preload(
	"res://scenes/user/profile_password_dialog.tscn"
)
const ProfileSetPasswordDialogScene := preload(
	"res://scenes/user/profile_set_password_dialog.tscn"
)

var _host: Control
var _profiles_list_vbox: VBoxContainer
var _page_vbox: Callable
var _section_label: Callable


func _init(
	host: Control, page_vbox: Callable, section_label: Callable,
) -> void:
	_host = host
	_page_vbox = page_vbox
	_section_label = section_label


func build() -> VBoxContainer:
	var vbox: VBoxContainer = _page_vbox.call("Profiles")

	_profiles_list_vbox = VBoxContainer.new()
	_profiles_list_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_profiles_list_vbox)
	_refresh_profiles_list()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var new_btn := Button.new()
	new_btn.text = "New Profile"
	new_btn.pressed.connect(_on_new_profile)
	btn_row.add_child(new_btn)

	var import_btn := Button.new()
	import_btn.text = "Import Profile"
	import_btn.pressed.connect(_on_import_profile)
	btn_row.add_child(import_btn)

	# Close settings on profile switch
	AppState.profile_switched.connect(_host.queue_free)

	return vbox


func _refresh_profiles_list() -> void:
	for child in _profiles_list_vbox.get_children():
		child.queue_free()

	var prof_list: Array = Config.profiles.get_profiles()
	var active_slug: String = Config.profiles.get_active_slug()

	for p in prof_list:
		var slug: String = p["slug"]
		var pname: String = p["name"]
		var has_pw: bool = p["has_password"]
		var is_active: bool = slug == active_slug

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_lbl := Label.new()
		name_lbl.text = pname
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		if has_pw:
			var lock_lbl := Label.new()
			lock_lbl.text = "[locked]"
			lock_lbl.add_theme_font_size_override("font_size", 11)
			lock_lbl.add_theme_color_override(
				"font_color", Color(0.58, 0.608, 0.643)
			)
			row.add_child(lock_lbl)

		if is_active:
			var active_lbl := Label.new()
			active_lbl.text = "(Active)"
			active_lbl.add_theme_font_size_override("font_size", 12)
			active_lbl.add_theme_color_override(
				"font_color", Color(0.345, 0.396, 0.949)
			)
			row.add_child(active_lbl)
		else:
			var switch_btn := Button.new()
			switch_btn.text = "Switch"
			switch_btn.pressed.connect(
				_on_switch_profile.bind(slug, pname, has_pw)
			)
			row.add_child(switch_btn)

		# Context menu
		var menu_btn := MenuButton.new()
		menu_btn.text = "..."
		var popup := menu_btn.get_popup()
		popup.add_item("Rename", 0)
		popup.add_item("Set Password", 1)
		popup.add_item("Export", 2)
		if slug != "default":
			popup.add_separator()
			popup.add_item("Delete", 3)
		popup.add_separator()
		popup.add_item("Move Up", 4)
		popup.add_item("Move Down", 5)
		popup.id_pressed.connect(
			_on_profile_menu.bind(slug, pname, has_pw)
		)
		row.add_child(menu_btn)

		_profiles_list_vbox.add_child(row)


func _on_switch_profile(
	slug: String, pname: String, has_pw: bool,
) -> void:
	if has_pw:
		var dlg: ColorRect = ProfilePasswordDialogScene.instantiate()
		dlg.setup(slug, pname)
		dlg.password_verified.connect(func(s: String) -> void:
			Config.profiles.switch(s)
		)
		_host.get_tree().root.add_child(dlg)
	else:
		Config.profiles.switch(slug)


func _on_profile_menu(
	id: int, slug: String, pname: String, has_pw: bool,
) -> void:
	match id:
		0: # Rename
			_show_rename_dialog(slug, pname)
		1: # Set Password
			var dlg: ColorRect = ProfileSetPasswordDialogScene.instantiate()
			dlg.setup(slug, has_pw)
			dlg.tree_exited.connect(_refresh_profiles_list)
			_host.get_tree().root.add_child(dlg)
		2: # Export
			_export_profile(slug)
		3: # Delete
			_confirm_delete_profile(slug, pname)
		4: # Move Up
			Config.profiles.move_up(slug)
			_refresh_profiles_list()
		5: # Move Down
			Config.profiles.move_down(slug)
			_refresh_profiles_list()


func _show_rename_dialog(slug: String, current_name: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Rename Profile"
	dlg.ok_button_text = "Rename"
	var line := LineEdit.new()
	line.text = current_name
	line.max_length = 32
	dlg.add_child(line)
	dlg.confirmed.connect(func() -> void:
		var new_name := line.text.strip_edges()
		if not new_name.is_empty():
			Config.profiles.rename(slug, new_name)
			_refresh_profiles_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	_host.add_child(dlg)
	dlg.popup_centered(Vector2i(300, 80))


func _confirm_delete_profile(slug: String, pname: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete Profile"
	dlg.dialog_text = (
		"Delete profile \"%s\"? This cannot be undone." % pname
	)
	dlg.confirmed.connect(func() -> void:
		Config.profiles.delete(slug)
		_refresh_profiles_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	_host.add_child(dlg)
	dlg.popup_centered()


func _export_profile(_slug: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "Export Profile"
	fd.add_filter("*.daccord-profile", "daccord Profile")
	fd.file_selected.connect(func(path: String) -> void:
		var err := Config.export_config(path)
		if err == OK:
			pass
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	_host.add_child(fd)
	fd.popup_centered(Vector2i(600, 400))


func _on_new_profile() -> void:
	var dlg: ColorRect = CreateProfileDialogScene.instantiate()
	dlg.profile_created.connect(func(_slug: String) -> void:
		_refresh_profiles_list()
	)
	_host.get_tree().root.add_child(dlg)


func _on_import_profile() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "Import Profile"
	fd.add_filter("*.daccord-profile; *.cfg", "Profile Files")
	fd.file_selected.connect(func(path: String) -> void:
		fd.queue_free()
		_show_import_name_dialog(path)
	)
	fd.canceled.connect(fd.queue_free)
	_host.add_child(fd)
	fd.popup_centered(Vector2i(600, 400))


func _show_import_name_dialog(import_path: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Name Imported Profile"
	dlg.ok_button_text = "Import"
	var line := LineEdit.new()
	line.placeholder_text = "Profile name"
	line.max_length = 32
	dlg.add_child(line)
	dlg.confirmed.connect(func() -> void:
		var pname := line.text.strip_edges()
		if pname.is_empty():
			pname = "Imported"
		var slug: String = Config.profiles.create(pname)
		var new_cfg := ConfigFile.new()
		var err := new_cfg.load(import_path)
		if err == OK:
			var cfg_path := "user://profiles/" + slug + "/config.cfg"
			new_cfg.save(cfg_path)
		_refresh_profiles_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	_host.add_child(dlg)
	dlg.popup_centered(Vector2i(300, 80))
