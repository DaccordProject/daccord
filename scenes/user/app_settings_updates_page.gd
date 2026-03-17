extends RefCounted

## Updates settings page — extracted from AppSettings.

const SettingsBase := preload("res://scenes/user/settings_base.gd")

var _host: Control
var _page_vbox: Callable
var _section_label: Callable

# Update page refs
var _check_btn: Button
var _status_label: Label
var _update_row: HBoxContainer
var _update_version_label: Label
var _download_btn: Button
var _view_changes_btn: Button
var _skip_btn: Button
var _restart_btn: Button
var _progress_row: HBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _cancel_btn: Button
var _error_label_update: Label
var _cached_version_info: Dictionary = {}


func _init(
	host: Control, page_vbox: Callable, section_label: Callable,
) -> void:
	_host = host
	_page_vbox = page_vbox
	_section_label = section_label


func build() -> VBoxContainer:
	var vbox: VBoxContainer = _page_vbox.call(tr("Updates"))

	# Current version
	vbox.add_child(_section_label.call(tr("CURRENT VERSION")))
	var version_label := Label.new()
	version_label.text = "v%s" % Client.app_version
	vbox.add_child(version_label)

	# Check for updates
	vbox.add_child(_section_label.call(tr("CHECK FOR UPDATES")))
	var check_row := HBoxContainer.new()
	check_row.add_theme_constant_override("separation", 12)
	_check_btn = SettingsBase.create_action_button(tr("Check for Updates"))
	_check_btn.pressed.connect(_on_check_updates_pressed)
	check_row.add_child(_check_btn)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	check_row.add_child(_status_label)
	vbox.add_child(check_row)

	# Update available row (hidden until update found)
	_update_row = HBoxContainer.new()
	_update_row.add_theme_constant_override("separation", 8)
	_update_row.visible = false
	_update_version_label = Label.new()
	_update_version_label.add_theme_font_size_override("font_size", 14)
	_update_version_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("accent")
	)
	_update_row.add_child(_update_version_label)
	_view_changes_btn = Button.new()
	_view_changes_btn.text = tr("View Changes")
	_view_changes_btn.flat = true
	_view_changes_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("accent")
	)
	_view_changes_btn.add_theme_font_size_override("font_size", 12)
	_view_changes_btn.pressed.connect(_on_view_changes)
	_update_row.add_child(_view_changes_btn)
	_download_btn = SettingsBase.create_action_button(
		tr("Download & Install")
	)
	_download_btn.pressed.connect(_on_download_pressed)
	_update_row.add_child(_download_btn)
	_skip_btn = Button.new()
	_skip_btn.text = tr("Skip This Version")
	_skip_btn.flat = true
	_skip_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.pressed.connect(_on_skip_pressed)
	_update_row.add_child(_skip_btn)
	vbox.add_child(_update_row)

	# Download progress row (hidden until downloading)
	_progress_row = HBoxContainer.new()
	_progress_row.add_theme_constant_override("separation", 8)
	_progress_row.visible = false
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(200, 20)
	_progress_bar.max_value = 100.0
	_progress_row.add_child(_progress_bar)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_progress_row.add_child(_progress_label)
	_cancel_btn = Button.new()
	_cancel_btn.text = tr("Cancel")
	_cancel_btn.flat = true
	_cancel_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_cancel_btn.pressed.connect(_on_cancel_download)
	_progress_row.add_child(_cancel_btn)
	vbox.add_child(_progress_row)

	# Restart button (hidden until update ready)
	_restart_btn = SettingsBase.create_action_button(
		tr("Restart to Update")
	)
	_restart_btn.visible = false
	_restart_btn.pressed.connect(func() -> void:
		Updater.apply_update_and_restart()
	)
	vbox.add_child(_restart_btn)

	# Error label
	_error_label_update = Label.new()
	_error_label_update.add_theme_color_override(
		"font_color", ThemeManager.get_color("error")
	)
	_error_label_update.add_theme_font_size_override("font_size", 13)
	_error_label_update.visible = false
	vbox.add_child(_error_label_update)

	# Auto-check toggle
	vbox.add_child(HSeparator.new())
	var auto_cb := CheckBox.new()
	auto_cb.text = tr("Automatically check for updates")
	auto_cb.button_pressed = Config.get_auto_update_check()
	auto_cb.toggled.connect(func(pressed: bool) -> void:
		Config._set_auto_update_check(pressed)
	)
	vbox.add_child(auto_cb)

	# Master server URL
	vbox.add_child(_section_label.call(tr("MASTER SERVER URL")))
	var url_input := LineEdit.new()
	url_input.text = Config.get_master_server_url()
	url_input.placeholder_text = "https://master.daccord.gg"
	vbox.add_child(url_input)

	var url_save := SettingsBase.create_secondary_button(tr("Save URL"))
	url_save.pressed.connect(func() -> void:
		var new_url: String = url_input.text.strip_edges()
		if not new_url.is_empty():
			Config.set_master_server_url(new_url)
	)
	vbox.add_child(url_save)

	# Connect update signals
	AppState.update_available.connect(_on_update_available)
	AppState.update_check_complete.connect(
		_on_update_check_complete
	)
	AppState.update_check_failed.connect(_on_update_check_failed)
	AppState.update_download_started.connect(
		_on_update_download_started
	)
	AppState.update_download_progress.connect(
		_on_update_download_progress
	)
	AppState.update_download_complete.connect(
		_on_update_download_complete
	)
	AppState.update_download_failed.connect(
		_on_update_download_failed
	)

	# If an update is already known, show it
	if Updater.is_update_ready():
		_show_restart_state()
	elif not Updater.get_latest_version_info().is_empty():
		var info: Dictionary = Updater.get_latest_version_info()
		if Updater.is_newer(
			info.get("version", ""), Client.app_version
		):
			_on_update_available(info)

	return vbox


# --- Callbacks ---

func _on_check_updates_pressed() -> void:
	_check_btn.disabled = true
	_status_label.text = tr("Checking...")
	_error_label_update.visible = false
	Updater.check_for_updates(true)


func _on_update_available(info: Dictionary) -> void:
	_cached_version_info = info
	_check_btn.disabled = false
	_status_label.text = ""
	var version: String = info.get("version", "unknown")
	_update_version_label.text = tr("v%s is available") % version
	_update_row.visible = true
	_download_btn.visible = true
	_skip_btn.visible = true
	_progress_row.visible = false
	_restart_btn.visible = false
	_error_label_update.visible = false


func _on_update_check_complete(_info: Variant) -> void:
	_check_btn.disabled = false
	_status_label.text = tr("You're on the latest version.")


func _on_update_check_failed(error: String) -> void:
	_check_btn.disabled = false
	_status_label.text = ""
	_error_label_update.text = tr("Check failed: %s") % error
	_error_label_update.visible = true


func _on_view_changes() -> void:
	var url: String = _cached_version_info.get("release_url", "")
	if not url.is_empty():
		OS.shell_open(url)


func _on_download_pressed() -> void:
	if _cached_version_info.is_empty():
		return
	var download_url: String = _cached_version_info.get(
		"download_url", ""
	)
	# No downloadable asset: open release page in browser
	if download_url.is_empty():
		var url: String = _cached_version_info.get(
			"release_url", ""
		)
		if not url.is_empty():
			OS.shell_open(url)
		return
	# Start in-app download
	_download_btn.visible = false
	_skip_btn.visible = false
	_progress_row.visible = true
	_progress_bar.value = 0
	_progress_label.text = tr("Starting...")
	_cancel_btn.visible = true
	_error_label_update.visible = false
	Updater.download_update(_cached_version_info)


func _on_skip_pressed() -> void:
	var version: String = _cached_version_info.get("version", "")
	if not version.is_empty():
		Updater.skip_version(version)
	_update_row.visible = false
	_status_label.text = tr("Version v%s skipped.") % version


func _on_cancel_download() -> void:
	Updater.cancel_download()
	_progress_row.visible = false
	_download_btn.visible = true
	_skip_btn.visible = true


func _on_update_download_started() -> void:
	_progress_row.visible = true
	_progress_bar.value = 0
	_progress_label.text = tr("Downloading...")
	_cancel_btn.visible = true


func _on_update_download_progress(percent: float) -> void:
	_progress_bar.value = percent
	var total_size: int = _cached_version_info.get(
		"download_size", 0
	)
	if total_size > 0:
		var downloaded: int = int(percent / 100.0 * total_size)
		_progress_label.text = tr("%s / %s") % [
			_format_size(downloaded), _format_size(total_size)
		]
	else:
		_progress_label.text = "%.0f%%" % percent


func _on_update_download_complete(_path: String) -> void:
	_show_restart_state()


func _on_update_download_failed(error: String) -> void:
	_progress_row.visible = false
	_download_btn.visible = true
	_skip_btn.visible = true
	_error_label_update.text = tr("Download failed: %s") % error
	_error_label_update.visible = true


func _show_restart_state() -> void:
	_check_btn.disabled = false
	_status_label.text = ""
	_update_row.visible = false
	_progress_row.visible = false
	_restart_btn.visible = true
	_error_label_update.visible = false


static func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	if bytes < 1024 * 1024:
		return str(snappedi(bytes / 1024, 1)) + " KB"
	return "%.1f MB" % (bytes / 1048576.0)
