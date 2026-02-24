extends PanelContainer

const ProfileEditDialog := preload(
	"res://scenes/user/profile_edit_dialog.tscn"
)

var _update_ready_label: Label = null
var _status_popup: PopupMenu = null

@onready var avatar: ColorRect = $HBox/Avatar
@onready var display_name: Label = $HBox/Info/DisplayName
@onready var username: Label = $HBox/Info/Username
@onready var voice_indicator: Label = $HBox/VoiceIndicator
@onready var status_icon: ColorRect = $HBox/StatusIcon
@onready var menu_button: MenuButton = $HBox/MenuButton

func _ready() -> void:
	username.add_theme_font_size_override("font_size", 11)
	username.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	voice_indicator.visible = false
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	# Avatar hover animation
	avatar.mouse_entered.connect(_on_avatar_hover_enter)
	avatar.mouse_exited.connect(_on_avatar_hover_exit)
	# Setup status popup on the status icon
	_status_popup = PopupMenu.new()
	_status_popup.add_item("Online", 0)
	_status_popup.add_item("Idle", 1)
	_status_popup.add_item("Do Not Disturb", 2)
	_status_popup.add_item("Invisible", 3)
	_status_popup.add_separator()
	_status_popup.add_item("Set Custom Status", 4)
	_status_popup.id_pressed.connect(_on_status_id_pressed)
	add_child(_status_popup)
	status_icon.gui_input.connect(_on_status_icon_input)
	# Setup menu
	var popup := menu_button.get_popup()
	popup.add_item("Edit Profile", 5)
	popup.add_separator()
	popup.add_item("Settings", 6)
	popup.add_separator()
	popup.add_check_item("Suppress @everyone", 15)
	var se_idx: int = popup.get_item_index(15)
	popup.set_item_checked(
		se_idx, Config.get_suppress_everyone()
	)
	popup.add_separator()
	popup.add_item("Export Profile", 18)
	popup.add_item("Import Profile", 19)
	popup.add_separator()
	popup.add_item("Report a Problem", 13)
	popup.add_separator()
	popup.add_item("Check for Updates", 16)
	popup.add_item("About", 10)
	popup.add_item("Quit", 11)
	popup.id_pressed.connect(_on_menu_id_pressed)
	AppState.update_download_complete.connect(_on_update_ready)
	# Load current user (active view)
	_refresh_active_user()
	# Refresh when a server connection completes
	AppState.guilds_updated.connect(_on_guilds_updated)
	AppState.user_updated.connect(_on_user_updated)
	AppState.guild_selected.connect(_on_active_view_changed)
	AppState.dm_mode_entered.connect(_on_active_view_changed)
	AppState.channel_selected.connect(_on_active_view_changed)

func setup(user: Dictionary) -> void:
	display_name.text = user.get(
		"display_name", "User"
	)
	username.text = user.get("username", "user")
	avatar.set_avatar_color(
		user.get("color", Color(0.345, 0.396, 0.949))
	)
	var dn: String = user.get("display_name", "")
	if dn.length() > 0:
		avatar.set_letter(dn[0].to_upper())
	else:
		avatar.set_letter("")
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		avatar.set_avatar_url(avatar_url)

	var status: int = user.get(
		"status", ClientModels.UserStatus.OFFLINE
	)
	status_icon.color = ClientModels.status_color(status)

	# Show custom status as tooltip
	var custom: String = Config.get_custom_status()
	tooltip_text = custom if not custom.is_empty() else ""

func _on_guilds_updated() -> void:
	_refresh_active_user()

func _on_user_updated(user_id: String) -> void:
	var active_user: Dictionary = Client.get_active_user()
	if user_id == active_user.get("id", ""):
		setup(active_user)

func _on_active_view_changed(_id: String = "") -> void:
	_refresh_active_user()

func _refresh_active_user() -> void:
	var user: Dictionary = Client.get_active_user()
	if not user.is_empty():
		setup(user)

func _on_voice_joined(_channel_id: String) -> void:
	voice_indicator.visible = true

func _on_voice_left(_channel_id: String) -> void:
	voice_indicator.visible = false

func _on_avatar_hover_enter() -> void:
	avatar.tween_radius(0.5, 0.3)

func _on_avatar_hover_exit() -> void:
	avatar.tween_radius(0.3, 0.5)

func _on_status_icon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = status_icon.global_position
		pos.y += status_icon.size.y
		_status_popup.position = Vector2i(pos)
		_status_popup.popup()

func _on_status_id_pressed(id: int) -> void:
	match id:
		0:
			Client.update_presence(
				ClientModels.UserStatus.ONLINE
			)
		1:
			Client.update_presence(
				ClientModels.UserStatus.IDLE
			)
		2:
			Client.update_presence(
				ClientModels.UserStatus.DND
			)
		3:
			Client.update_presence(
				ClientModels.UserStatus.OFFLINE
			)
		4:
			_show_custom_status_dialog()
	if id >= 0 and id <= 3:
		_refresh_active_user()

func _on_menu_id_pressed(id: int) -> void:
	match id:
		5:
			_show_profile_edit_dialog()
		6:
			_show_user_settings()
		10:
			_show_about_dialog()
		11:
			get_tree().quit()
		13:
			_show_feedback_dialog()
		15:
			_toggle_suppress_everyone()
		16:
			if Updater.is_update_ready():
				Updater.apply_update_and_restart()
			else:
				_check_for_updates()
		18:
			_show_export_dialog()
		19:
			_show_import_dialog()

func _show_profile_edit_dialog() -> void:
	var dlg: ColorRect = ProfileEditDialog.instantiate()
	get_tree().root.add_child(dlg)

func _show_user_settings() -> void:
	var UserSettingsScene: PackedScene = load(
		"res://scenes/user/user_settings.tscn"
	)
	if UserSettingsScene:
		var settings: ColorRect = UserSettingsScene.instantiate()
		get_tree().root.add_child(settings)

func _show_about_dialog() -> void:
	var version: String = Client.app_version
	var dlg := AcceptDialog.new()
	dlg.title = "About daccord"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title_label := Label.new()
	title_label.text = "daccord v%s" % version
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = "A chat client for accordserver instances."
	desc_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc_label)

	var license_label := Label.new()
	license_label.text = "License: MIT"
	license_label.add_theme_font_size_override("font_size", 12)
	license_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(license_label)

	var link := LinkButton.new()
	link.text = "github.com/daccord-projects/daccord"
	link.uri = "https://github.com/daccord-projects/daccord"
	link.add_theme_font_size_override("font_size", 12)
	vbox.add_child(link)

	dlg.add_child(vbox)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(340, 160))

func _show_custom_status_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Set Custom Status"
	dlg.ok_button_text = "Save"

	var vbox := VBoxContainer.new()
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "What's on your mind?"
	line_edit.text = Config.get_custom_status()
	vbox.add_child(line_edit)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Status"
	clear_btn.pressed.connect(func() -> void:
		line_edit.text = ""
	)
	vbox.add_child(clear_btn)

	dlg.add_child(vbox)
	dlg.confirmed.connect(func() -> void:
		var text: String = line_edit.text.strip_edges()
		Config.set_custom_status(text)
		var activity: Dictionary = {}
		if not text.is_empty():
			activity = {"name": text}
		var status: int = Client.get_active_user().get(
			"status", ClientModels.UserStatus.ONLINE
		)
		Client.update_presence(status, activity)
		_refresh_active_user()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(300, 120))

func _show_feedback_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Report a Problem"
	dlg.ok_button_text = "Send Report"

	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "Describe what happened (optional):"
	label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(label)

	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(350, 120)
	text_edit.placeholder_text = (
		"Steps to reproduce, what you expected..."
	)
	vbox.add_child(text_edit)

	var info := Label.new()
	info.text = (
		"No messages, usernames, or personal info is sent."
	)
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(info)

	dlg.add_child(vbox)
	dlg.confirmed.connect(func() -> void:
		var desc: String = text_edit.text.strip_edges()
		if desc.is_empty():
			desc = "User-initiated report (no description)"
		ErrorReporting.report_problem(desc)
		_show_report_sent_toast()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _show_report_sent_toast() -> void:
	_show_toast("Report sent. Thank you!")

func _show_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 13)
	toast.add_theme_color_override(
		"font_color", Color(0.75, 0.75, 0.75)
	)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.19, 0.21, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(toast)
	# Position at bottom center of the main window
	var main_win: Control = get_tree().root.get_child(
		get_tree().root.get_child_count() - 1
	)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_bottom = 1.0
	panel.anchor_top = 1.0
	panel.offset_top = -60.0
	panel.offset_bottom = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_win.add_child(panel)
	var tween := main_win.create_tween()
	tween.tween_interval(3.0)
	if Config.get_reduced_motion():
		tween.tween_callback(panel.queue_free)
	else:
		tween.tween_property(panel, "modulate:a", 0.0, 1.0)
		tween.tween_callback(panel.queue_free)

func _toggle_suppress_everyone() -> void:
	var suppressed: bool = not Config.get_suppress_everyone()
	Config.set_suppress_everyone(suppressed)
	var popup := menu_button.get_popup()
	var idx: int = popup.get_item_index(15)
	popup.set_item_checked(idx, suppressed)

func _check_for_updates() -> void:
	_show_toast("Checking for updates...")

	var on_complete: Callable
	var on_failed: Callable
	var on_available: Callable

	var cleanup := func() -> void:
		if AppState.update_check_complete.is_connected(on_complete):
			AppState.update_check_complete.disconnect(on_complete)
		if AppState.update_check_failed.is_connected(on_failed):
			AppState.update_check_failed.disconnect(on_failed)
		if AppState.update_available.is_connected(on_available):
			AppState.update_available.disconnect(on_available)

	on_complete = func(_info: Variant) -> void:
		cleanup.call()
		_show_toast(
			"You're on the latest version (v%s)." % Client.app_version
		)

	on_failed = func(error: String) -> void:
		cleanup.call()
		_show_toast("Couldn't check for updates: %s" % error)

	on_available = func(info: Dictionary) -> void:
		cleanup.call()
		var version: String = info.get("version", "")
		_show_toast("Update available: v%s" % version)

	AppState.update_check_complete.connect(on_complete, CONNECT_ONE_SHOT)
	AppState.update_check_failed.connect(on_failed, CONNECT_ONE_SHOT)
	AppState.update_available.connect(on_available, CONNECT_ONE_SHOT)
	Updater.check_for_updates(true)

func _on_update_ready(_path: String) -> void:
	# Update menu item text
	var popup := menu_button.get_popup()
	var idx: int = popup.get_item_index(16)
	popup.set_item_text(idx, "Restart to Update")

	# Show persistent "Update ready" label
	if _update_ready_label == null:
		_update_ready_label = Label.new()
		_update_ready_label.text = "Update ready"
		_update_ready_label.add_theme_font_size_override("font_size", 11)
		_update_ready_label.add_theme_color_override(
			"font_color", Color(0.345, 0.396, 0.949)
		)
		_update_ready_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_update_ready_label.tooltip_text = "Click to restart and apply update"
		_update_ready_label.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				Updater.apply_update_and_restart()
		)
		var info_vbox: VBoxContainer = $HBox/Info
		info_vbox.add_child(_update_ready_label)

func _show_export_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Export Profile"
	fd.add_filter("*.daccord-profile", "daccord Profile")
	fd.file_selected.connect(func(path: String) -> void:
		var err := Config.export_config(path)
		if err == OK:
			_show_toast("Profile exported successfully.")
		else:
			_show_toast("Export failed (error %d)." % err)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _show_import_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Import Profile"
	fd.add_filter(
		"*.daccord-profile; *.cfg", "Profile Files"
	)
	fd.file_selected.connect(func(path: String) -> void:
		fd.queue_free()
		_show_import_name_dialog(path)
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _show_import_name_dialog(
	import_path: String,
) -> void:
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
			var cfg_path := (
				"user://profiles/" + slug + "/config.cfg"
			)
			new_cfg.save(cfg_path)
			_show_toast("Profile imported successfully.")
		else:
			_show_toast(
				"Import failed (error %d)." % err
			)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(300, 80))
