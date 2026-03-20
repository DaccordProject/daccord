extends ModalBase

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _space_id: String = ""
var _dirty: bool = false
var _pending_icon_data_uri: String = ""
var _icon_removed: bool = false
var _icon_preview: ColorRect
var _rules_channel_btn: OptionButton
var _system_channel_btn: OptionButton

@onready var _vbox: VBoxContainer = $CenterContainer/Panel/VBox
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _desc_input: TextEdit = $CenterContainer/Panel/VBox/DescInput
@onready var _verification_btn: OptionButton = \
	$CenterContainer/Panel/VBox/VerificationRow/VerificationOption
@onready var _notifications_btn: OptionButton = \
	$CenterContainer/Panel/VBox/NotificationsRow/NotificationsOption
@onready var _public_check: CheckBox = $CenterContainer/Panel/VBox/PublicRow/PublicCheck
@onready var _guest_access_check: CheckBox = \
	$CenterContainer/Panel/VBox/GuestAccessRow/GuestAccessCheck
@onready var _nsfw_level_btn: OptionButton = \
	$CenterContainer/Panel/VBox/NsfwLevelRow/NsfwLevelOption
@onready var _content_filter_btn: OptionButton = \
	$CenterContainer/Panel/VBox/ContentFilterRow/ContentFilterOption
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/SaveRow/SaveButton
@onready var _delete_btn: Button = $CenterContainer/Panel/VBox/DangerZone/DeleteButton
@onready var _danger_zone: VBoxContainer = $CenterContainer/Panel/VBox/DangerZone
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 440, 0)
	_close_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_delete_btn.pressed.connect(_on_delete)
	_verification_btn.add_item(tr("None"), 0)
	_verification_btn.add_item(tr("Low"), 1)
	_verification_btn.add_item(tr("Medium"), 2)
	_verification_btn.add_item(tr("High"), 3)
	_notifications_btn.add_item(tr("All Messages"), 0)
	_notifications_btn.add_item(tr("Mentions Only"), 1)
	_nsfw_level_btn.add_item(tr("Default"), 0)
	_nsfw_level_btn.add_item(tr("Moderate"), 1)
	_nsfw_level_btn.add_item(tr("Explicit"), 2)
	_content_filter_btn.add_item(tr("Disabled"), 0)
	_content_filter_btn.add_item(tr("Members Without Roles"), 1)
	_content_filter_btn.add_item(tr("Everyone"), 2)

	# Rules channel selector
	var rules_row := HBoxContainer.new()
	rules_row.name = "RulesChannelRow"

	var rules_label := Label.new()
	rules_label.text = tr("Rules Channel")
	rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_row.add_child(rules_label)

	var rules_info := Label.new()
	rules_info.text = "ⓘ"
	rules_info.tooltip_text = \
		tr("New members will be shown the rules channel " \
		+ "content before they can interact. " \
		+ "Select 'None' to disable.")
	rules_info.mouse_filter = Control.MOUSE_FILTER_STOP
	rules_info.add_theme_font_size_override("font_size", 14)
	rules_row.add_child(rules_info)

	_rules_channel_btn = OptionButton.new()
	_rules_channel_btn.custom_minimum_size = Vector2(140, 0)
	rules_row.add_child(_rules_channel_btn)

	_vbox.add_child(rules_row)
	_vbox.move_child(rules_row, _save_btn.get_parent().get_index())

	# System messages channel selector
	var system_row := HBoxContainer.new()
	system_row.name = "SystemChannelRow"

	var system_label := Label.new()
	system_label.text = tr("System Messages Channel")
	system_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_row.add_child(system_label)

	var system_info := Label.new()
	system_info.text = "\u24d8"
	system_info.tooltip_text = \
		tr("Join announcements will be posted in this channel. " \
		+ "Select 'None' to disable.")
	system_info.mouse_filter = Control.MOUSE_FILTER_STOP
	system_info.add_theme_font_size_override("font_size", 14)
	system_row.add_child(system_info)

	_system_channel_btn = OptionButton.new()
	_system_channel_btn.custom_minimum_size = Vector2(140, 0)
	system_row.add_child(_system_channel_btn)

	_vbox.add_child(system_row)
	_vbox.move_child(system_row, _save_btn.get_parent().get_index())

	# Build icon upload section (inserted after Header)
	var icon_label := Label.new()
	icon_label.text = tr("SPACE ICON")
	ThemeManager.style_label(icon_label, 11, "text_body")
	_vbox.add_child(icon_label)
	_vbox.move_child(icon_label, 1)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 12)
	_vbox.add_child(icon_row)
	_vbox.move_child(icon_row, 2)

	_icon_preview = AvatarScene.instantiate()
	_icon_preview.avatar_size = 64
	_icon_preview.show_letter = true
	_icon_preview.letter_font_size = 22
	_icon_preview.custom_minimum_size = Vector2(64, 64)
	icon_row.add_child(_icon_preview)

	var icon_btns := VBoxContainer.new()
	icon_btns.add_theme_constant_override("separation", 4)
	icon_row.add_child(icon_btns)

	var upload_btn := SettingsBase.create_secondary_button(tr("Upload Icon"))
	upload_btn.pressed.connect(_on_icon_upload)
	icon_btns.add_child(upload_btn)

	var remove_btn := SettingsBase.create_secondary_button(tr("Remove"))
	remove_btn.pressed.connect(_on_icon_remove)
	icon_btns.add_child(remove_btn)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_desc_input.text_changed.connect(func(): _dirty = true)
	_verification_btn.item_selected.connect(func(_i: int): _dirty = true)
	_notifications_btn.item_selected.connect(func(_i: int): _dirty = true)
	_public_check.toggled.connect(func(_b: bool): _dirty = true)
	_guest_access_check.toggled.connect(func(_b: bool): _dirty = true)
	_nsfw_level_btn.item_selected.connect(func(_i: int): _dirty = true)
	_content_filter_btn.item_selected.connect(func(_i: int): _dirty = true)
	_rules_channel_btn.item_selected.connect(func(_i: int): _dirty = true)
	_system_channel_btn.item_selected.connect(func(_i: int): _dirty = true)

func setup(space_id: String) -> void:
	_space_id = space_id
	var space: Dictionary = Client.get_space_by_id(space_id)

	if _name_input:
		_name_input.text = space.get("name", "")
	if _desc_input:
		_desc_input.text = space.get("description", "")

	# Icon preview
	_icon_preview.setup_from_dict(space, "icon_color", "name", "icon")

	var ver: String = space.get("verification_level", "none")
	match ver:
		"low": _verification_btn.select(1)
		"medium": _verification_btn.select(2)
		"high": _verification_btn.select(3)
		_: _verification_btn.select(0)

	var notif: String = space.get("default_notifications", "all")
	if notif == "mentions":
		_notifications_btn.select(1)
	else:
		_notifications_btn.select(0)

	_public_check.button_pressed = space.get("public", false)
	_guest_access_check.button_pressed = space.get("allow_guest_access", true)

	var nsfw: String = space.get("nsfw_level", "default")
	match nsfw:
		"moderate": _nsfw_level_btn.select(1)
		"explicit": _nsfw_level_btn.select(2)
		_: _nsfw_level_btn.select(0)

	var ecf: String = space.get("explicit_content_filter", "disabled")
	match ecf:
		"no_role": _content_filter_btn.select(1)
		"everyone": _content_filter_btn.select(2)
		_: _content_filter_btn.select(0)

	# Rules channel dropdown
	_rules_channel_btn.clear()
	_rules_channel_btn.add_item(tr("None"), 0)
	var channels: Array = Client.get_channels_for_space(space_id)
	var rules_id: String = space.get("rules_channel_id", "")
	var rules_idx: int = 0
	var ch_idx: int = 1
	for ch in channels:
		if ch.get("type", 0) == ClientModels.ChannelType.TEXT:
			_rules_channel_btn.add_item("#" + ch.get("name", ""), ch_idx)
			_rules_channel_btn.set_item_metadata(ch_idx, ch.get("id", ""))
			if ch.get("id", "") == rules_id:
				rules_idx = ch_idx
			ch_idx += 1
	_rules_channel_btn.select(rules_idx)

	# System messages channel dropdown
	_system_channel_btn.clear()
	_system_channel_btn.add_item(tr("None"), 0)
	var sys_id: String = space.get("system_channel_id", "")
	var sys_idx: int = 0
	var sys_ch_idx: int = 1
	for ch in channels:
		if ch.get("type", 0) == ClientModels.ChannelType.TEXT:
			_system_channel_btn.add_item("#" + ch.get("name", ""), sys_ch_idx)
			_system_channel_btn.set_item_metadata(sys_ch_idx, ch.get("id", ""))
			if ch.get("id", "") == sys_id:
				sys_idx = sys_ch_idx
			sys_ch_idx += 1
	_system_channel_btn.select(sys_idx)

	# Only the owner can see the danger zone
	_danger_zone.visible = Client.is_space_owner(space_id)
	_dirty = false

func _on_save() -> void:
	_error_label.visible = false
	var ver_levels := ["none", "low", "medium", "high"]
	var notif_levels := ["all", "mentions"]
	var nsfw_levels := ["default", "moderate", "explicit"]
	var filter_levels := ["disabled", "no_role", "everyone"]

	var data := {
		"name": _name_input.text.strip_edges(),
		"description": _desc_input.text.strip_edges(),
		"verification_level": ver_levels[_verification_btn.selected],
		"default_notifications": notif_levels[_notifications_btn.selected],
		"nsfw_level": nsfw_levels[_nsfw_level_btn.selected],
		"explicit_content_filter": filter_levels[_content_filter_btn.selected],
	}

	data["public"] = _public_check.button_pressed
	data["allow_guest_access"] = _guest_access_check.button_pressed

	# Rules channel
	var rules_sel: int = _rules_channel_btn.selected
	if rules_sel > 0:
		data["rules_channel_id"] = _rules_channel_btn.get_item_metadata(rules_sel)
	else:
		data["rules_channel_id"] = null

	# System messages channel
	var sys_sel: int = _system_channel_btn.selected
	if sys_sel > 0:
		data["system_channel_id"] = _system_channel_btn.get_item_metadata(sys_sel)
	else:
		data["system_channel_id"] = null

	# Icon upload / removal
	if not _pending_icon_data_uri.is_empty():
		data["icon"] = _pending_icon_data_uri
	elif _icon_removed:
		data["icon"] = ""

	var result: RestResult = await _with_button_loading(
		_save_btn, tr("Save"),
		func() -> RestResult:
			return await Client.admin.update_space(_space_id, data)
	)

	if not _show_rest_error(result, tr("Failed to update space")):
		_dirty = false
		queue_free()

func _on_icon_upload() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
	])
	fd.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return
		var bytes := file.get_buffer(file.get_length())
		file.close()
		_pending_icon_data_uri = AccordCDN.build_data_uri(bytes, path)
		_icon_removed = false
		var img := Image.new()
		if img.load(path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_icon_preview._apply_texture(tex)
		_dirty = true
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _on_icon_remove() -> void:
	_icon_removed = true
	_pending_icon_data_uri = ""
	_icon_preview.letter_label.visible = true
	if _icon_preview._texture_rect != null:
		_icon_preview._texture_rect.queue_free()
		_icon_preview._texture_rect = null
	_dirty = true

func _on_delete() -> void:
	var space: Dictionary = Client.get_space_by_id(_space_id)
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("Delete Space"),
		tr("Are you sure you want to delete '%s'? This cannot be undone.") % space.get("name", ""),
		tr("Delete"),
		true
	)
	dialog.confirmed.connect(func():
		var result: RestResult = await Client.admin.delete_space(_space_id)
		if result != null and result.ok:
			_dirty = false
			queue_free()
	)

func _try_close() -> void:
	_try_close_dirty(_dirty, ConfirmDialogScene)

func _close() -> void:
	_try_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()
