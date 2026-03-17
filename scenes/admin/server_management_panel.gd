extends SettingsBase

## Instance-level server management panel — admin only.
## Tabs: Spaces, Users, Settings.

const ConfirmDialogScene := preload(
	"res://scenes/admin/confirm_dialog.tscn"
)
const SpaceSettingsDialogScene := preload(
	"res://scenes/admin/space_settings_dialog.tscn"
)
const AvatarScene := preload("res://scenes/common/avatar.tscn")
const CreateSpaceDialogScene := preload(
	"res://scenes/admin/create_space_dialog.tscn"
)
const TransferOwnershipDialogScene := preload(
	"res://scenes/admin/transfer_ownership_dialog.gd"
)
const ResetPasswordDialogScene := preload(
	"res://scenes/admin/reset_password_dialog.tscn"
)
const ReportListDialogScene := preload(
	"res://scenes/admin/report_list_dialog.tscn"
)
const RoleMgmtScene := preload(
	"res://scenes/admin/role_management_dialog.tscn"
)
const PluginMgmtScript := preload(
	"res://scenes/admin/plugin_management_dialog.gd"
)
const ServerManagementReportsScript := preload(
	"res://scenes/admin/server_management_reports.gd"
)

# Spaces tab
var _spaces_list: VBoxContainer
var _spaces_search: LineEdit
var _spaces_error: Label
var _spaces_data: Array = []

# Users tab
var _users_list: VBoxContainer
var _users_search: LineEdit
var _users_error: Label
var _users_data: Array = []
var _users_has_more: bool = false
var _users_load_more_btn: Button

# Reports tab (delegated to server_management_reports.gd)
var _reports_helper

# Settings tab
var _server_name_input: LineEdit
var _reg_policy_dropdown: OptionButton
var _max_spaces_spin: SpinBox
var _max_members_spin: SpinBox
var _motd_input: TextEdit
var _public_listing_cb: CheckBox
var _tos_enabled_cb: CheckBox
var _tos_text_input: TextEdit
var _tos_url_input: LineEdit
var _tos_version_label: Label
var _settings_save_btn: Button
var _settings_error: Label

func _get_sections() -> Array:
	return [tr("Spaces"), tr("Users"), tr("Reports"), tr("Settings")]

func _get_subtitle() -> String:
	var servers: Array = Config.get_servers()
	if servers.size() > 0:
		return servers[0].get("base_url", "")
	return ""

func _get_modal_size() -> Vector2:
	return Vector2(950, 650)

func _build_pages() -> Array:
	return [
		_build_spaces_page(),
		_build_users_page(),
		_build_reports_page(),
		_build_settings_page(),
	]

# ── Spaces tab ──────────────────────────────────────────────

func _build_spaces_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Spaces"))

	# Create Space button
	var create_btn := SettingsBase.create_action_button(tr("Create Space"))
	create_btn.pressed.connect(_on_create_space)
	vbox.add_child(create_btn)

	# Search
	vbox.add_child(_section_label(tr("SEARCH")))
	_spaces_search = LineEdit.new()
	_spaces_search.placeholder_text = tr("Filter by name...")
	_spaces_search.text_changed.connect(
		func(_t: String) -> void: _filter_spaces()
	)
	vbox.add_child(_spaces_search)

	# Error label
	_spaces_error = _error_label()
	vbox.add_child(_spaces_error)

	# Space list
	_spaces_list = VBoxContainer.new()
	_spaces_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_spaces_list)

	# Fetch on ready (deferred so tree is stable)
	_fetch_spaces.call_deferred()
	return vbox

func _fetch_spaces() -> void:
	_spaces_error.visible = false
	_clear_children(_spaces_list)
	var loading := Label.new()
	loading.text = tr("Loading spaces...")
	loading.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_spaces_list.add_child(loading)

	var result: RestResult = await Client.admin.list_all_spaces()
	_clear_children(_spaces_list)

	if result == null or not result.ok:
		var msg := tr("Failed to load spaces")
		if result != null and result.error:
			msg = result.error.message
		_spaces_error.text = msg
		_spaces_error.visible = true
		return

	if result.data is Array:
		_spaces_data = result.data
	else:
		_spaces_data = []
	_render_spaces()

func _filter_spaces() -> void:
	_render_spaces()

func _render_spaces() -> void:
	_clear_children(_spaces_list)
	var query: String = _spaces_search.text.strip_edges().to_lower()

	for space in _spaces_data:
		var sname: String = ""
		var sid: String = ""
		var owner_id: String = ""
		var member_count: int = 0
		if space is AccordSpace:
			sname = space.name
			sid = space.id
			owner_id = space.owner_id
			member_count = space.member_count
		elif space is Dictionary:
			sname = space.get("name", "")
			sid = space.get("id", "")
			owner_id = space.get("owner_id", "")
			member_count = space.get("member_count", 0)
		else:
			continue

		if not query.is_empty() and sname.to_lower().find(query) == -1:
			continue

		var row := _build_space_row(sid, sname, owner_id, member_count)
		_spaces_list.add_child(row)

	if _spaces_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = tr("No spaces found.")
		empty.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_spaces_list.add_child(empty)

func _build_space_row(
	space_id: String, sname: String,
	_owner_id: String, member_count: int,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Letter avatar
	var letter_rect := ColorRect.new()
	letter_rect.custom_minimum_size = Vector2(36, 36)
	letter_rect.color = ThemeManager.get_color("accent")
	var letter_lbl := Label.new()
	letter_lbl.text = sname[0].to_upper() if sname.length() > 0 else "?"
	letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter_rect.add_child(letter_lbl)
	row.add_child(letter_rect)

	# Name + member count
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_lbl := Label.new()
	name_lbl.text = sname
	info.add_child(name_lbl)
	var detail_lbl := Label.new()
	detail_lbl.text = tr("%d members") % member_count
	detail_lbl.add_theme_font_size_override("font_size", 11)
	detail_lbl.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	info.add_child(detail_lbl)
	row.add_child(info)

	# Roles button
	var roles_btn := SettingsBase.create_secondary_button(tr("Roles"))
	roles_btn.pressed.connect(func() -> void:
		DialogHelper.open(RoleMgmtScene, get_tree()).setup(space_id)
	)
	row.add_child(roles_btn)

	# Plugins button
	var plugins_btn := SettingsBase.create_secondary_button(tr("Plugins"))
	plugins_btn.pressed.connect(func() -> void:
		var dialog: ColorRect = PluginMgmtScript.new()
		get_tree().root.add_child(dialog)
		dialog.setup(space_id)
	)
	row.add_child(plugins_btn)

	# Settings button
	var settings_btn := SettingsBase.create_secondary_button(tr("Settings"))
	settings_btn.pressed.connect(func() -> void:
		var dialog := SpaceSettingsDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(space_id)
	)
	row.add_child(settings_btn)

	# Transfer button
	var transfer_btn := SettingsBase.create_secondary_button(tr("Transfer"))
	transfer_btn.pressed.connect(func() -> void:
		_on_transfer_ownership(space_id, sname)
	)
	row.add_child(transfer_btn)

	# Delete button
	var delete_btn := SettingsBase.create_danger_button(tr("Delete"))
	delete_btn.pressed.connect(func() -> void:
		_on_delete_space(space_id, sname)
	)
	row.add_child(delete_btn)

	return row

func _on_create_space() -> void:
	var dialog: ColorRect = CreateSpaceDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.tree_exited.connect(_fetch_spaces)

func _on_transfer_ownership(space_id: String, sname: String) -> void:
	var dialog: ColorRect = TransferOwnershipDialogScene.new()
	get_tree().root.add_child(dialog)
	dialog.setup(space_id, sname)

func _on_delete_space(space_id: String, sname: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("Delete Space"),
		tr("Are you sure you want to delete '%s'? This cannot be undone.") % sname,
		tr("Delete"),
		true
	)
	dialog.confirmed.connect(func() -> void:
		var result: RestResult = await Client.admin.delete_space(
			space_id
		)
		if result != null and result.ok:
			_fetch_spaces()
	)

# ── Reports tab (delegated to ServerManagementReports) ──────

func _build_reports_page() -> VBoxContainer:
	_reports_helper = ServerManagementReportsScript.new(self)
	return _reports_helper.build_page(_page_vbox)

# ── Users tab ───────────────────────────────────────────────

func _build_users_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Users"))

	# Search
	vbox.add_child(_section_label(tr("SEARCH")))
	_users_search = LineEdit.new()
	_users_search.placeholder_text = tr("Search by username...")
	vbox.add_child(_users_search)

	var search_btn := SettingsBase.create_secondary_button(tr("Search"))
	search_btn.pressed.connect(func() -> void:
		_fetch_users()
	)
	vbox.add_child(search_btn)

	# Error label
	_users_error = _error_label()
	vbox.add_child(_users_error)

	# User list
	_users_list = VBoxContainer.new()
	_users_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_users_list)

	# Load More button
	_users_load_more_btn = SettingsBase.create_secondary_button(
		tr("Load More")
	)
	_users_load_more_btn.visible = false
	_users_load_more_btn.pressed.connect(_fetch_more_users)
	vbox.add_child(_users_load_more_btn)

	_fetch_users.call_deferred()
	return vbox

func _fetch_users(append: bool = false) -> void:
	_users_error.visible = false
	if not append:
		_clear_children(_users_list)
		_users_data = []
		var loading := Label.new()
		loading.text = tr("Loading users...")
		loading.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_users_list.add_child(loading)

	var query: Dictionary = {"limit": 50}
	var search_text: String = _users_search.text.strip_edges()
	if not search_text.is_empty():
		query["query"] = search_text
	if _users_data.size() > 0 and append:
		var last = _users_data.back()
		if last is AccordUser:
			query["after"] = last.id
		elif last is Dictionary:
			query["after"] = last.get("id", "")

	var result: RestResult = await Client.admin.list_all_users(query)

	if not append:
		_clear_children(_users_list)

	if result == null or not result.ok:
		var msg := tr("Failed to load users")
		if result != null and result.error:
			msg = result.error.message
		_users_error.text = msg
		_users_error.visible = true
		_users_load_more_btn.visible = false
		return

	var new_users: Array = []
	if result.data is Array:
		new_users = result.data
	_users_data.append_array(new_users)
	_users_has_more = result.has_more

	for user in new_users:
		var row := _build_user_row(user)
		_users_list.add_child(row)

	_users_load_more_btn.visible = _users_has_more

	if _users_data.size() == 0:
		var empty := Label.new()
		empty.text = tr("No users found.")
		empty.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_users_list.add_child(empty)

func _fetch_more_users() -> void:
	_fetch_users(true)

func _build_user_row(user) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var uname: String = ""
	var uid: String = ""
	var is_admin_flag: bool = false
	var is_disabled: bool = false
	if user is AccordUser:
		uname = user.username
		uid = user.id
		is_admin_flag = user.is_admin
		is_disabled = user.disabled
	elif user is Dictionary:
		uname = user.get("username", "")
		uid = user.get("id", "")
		is_admin_flag = user.get("is_admin", false)
		is_disabled = user.get("disabled", false)

	# Letter avatar
	var letter_rect := ColorRect.new()
	letter_rect.custom_minimum_size = Vector2(32, 32)
	letter_rect.color = ThemeManager.get_color("accent")
	var letter_lbl := Label.new()
	letter_lbl.text = uname[0].to_upper() if uname.length() > 0 else "?"
	letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter_rect.add_child(letter_lbl)
	row.add_child(letter_rect)

	# Username + badges
	var name_lbl := Label.new()
	name_lbl.text = uname
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_disabled:
		name_lbl.text += "  " + tr("[Disabled]")
		name_lbl.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
	elif is_admin_flag:
		name_lbl.text += "  " + tr("[Admin]")
		name_lbl.add_theme_color_override(
			"font_color", ThemeManager.get_color("accent")
		)
	row.add_child(name_lbl)

	# Admin toggle
	var admin_cb := CheckBox.new()
	admin_cb.text = tr("Admin")
	admin_cb.button_pressed = is_admin_flag
	admin_cb.toggled.connect(func(pressed: bool) -> void:
		var result: RestResult = await Client.admin.admin_update_user(
			uid, {"is_admin": pressed}
		)
		if result == null or not result.ok:
			admin_cb.button_pressed = not pressed
			var msg := tr("Failed to update user")
			if result != null and result.error:
				msg = result.error.message
			_users_error.text = msg
			_users_error.visible = true
	)
	row.add_child(admin_cb)

	# Disable/Enable button
	var disable_btn: Button
	if is_disabled:
		disable_btn = SettingsBase.create_secondary_button(tr("Enable"))
	else:
		disable_btn = SettingsBase.create_danger_button(tr("Disable"))
	disable_btn.pressed.connect(func() -> void:
		_on_toggle_disabled(uid, uname, not is_disabled)
	)
	row.add_child(disable_btn)

	# Reset Password button (not for bots)
	var is_bot: bool = false
	if user is AccordUser:
		is_bot = user.bot
	elif user is Dictionary:
		is_bot = user.get("bot", false)
	if not is_bot:
		var reset_btn := SettingsBase.create_secondary_button(
			tr("Reset Password")
		)
		reset_btn.pressed.connect(func() -> void:
			_on_reset_password(uid, uname)
		)
		row.add_child(reset_btn)

	# Delete button
	var del_btn := SettingsBase.create_danger_button(tr("Delete"))
	del_btn.pressed.connect(func() -> void:
		_on_delete_user(uid, uname)
	)
	row.add_child(del_btn)

	return row

func _on_toggle_disabled(
	user_id: String, uname: String, disable: bool,
) -> void:
	var action: String = tr("Disable") if disable else tr("Enable")
	var msg: String
	if disable:
		msg = tr("Disable '%s'? They will be unable to log in.") % uname
	else:
		msg = tr("Re-enable '%s'? They will be able to log in again.") % uname
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("%s User") % action, msg, action, disable
	)
	dialog.confirmed.connect(func() -> void:
		var result: RestResult = await Client.admin.admin_update_user(
			user_id, {"disabled": disable}
		)
		if result != null and result.ok:
			_fetch_users()
		elif result != null and result.error:
			_users_error.text = result.error.message
			_users_error.visible = true
	)

func _on_reset_password(user_id: String, uname: String) -> void:
	var dialog := ResetPasswordDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(user_id, uname)

func _on_delete_user(user_id: String, uname: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("Delete User"),
		tr("Are you sure you want to delete '%s'? This cannot be undone.") % uname,
		tr("Delete"),
		true
	)
	dialog.confirmed.connect(func() -> void:
		var result: RestResult = await Client.admin.admin_delete_user(
			user_id
		)
		if result != null and result.ok:
			_fetch_users()
		elif result != null and result.error:
			_users_error.text = result.error.message
			_users_error.visible = true
	)

# ── Settings tab ────────────────────────────────────────────

func _build_settings_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Server Settings"))

	# Error label
	_settings_error = _error_label()
	vbox.add_child(_settings_error)

	# Server name
	vbox.add_child(_section_label(tr("SERVER NAME")))
	_server_name_input = LineEdit.new()
	_server_name_input.placeholder_text = tr("Accord Server")
	vbox.add_child(_server_name_input)

	# Registration policy
	vbox.add_child(_section_label(tr("REGISTRATION POLICY")))
	_reg_policy_dropdown = OptionButton.new()
	_reg_policy_dropdown.add_item(tr("Open"))
	_reg_policy_dropdown.add_item(tr("Invite Only"))
	_reg_policy_dropdown.add_item(tr("Closed"))
	vbox.add_child(_reg_policy_dropdown)

	# Max spaces
	vbox.add_child(_section_label(tr("MAX SPACES (0 = unlimited)")))
	_max_spaces_spin = SpinBox.new()
	_max_spaces_spin.min_value = 0
	_max_spaces_spin.max_value = 10000
	_max_spaces_spin.step = 1
	vbox.add_child(_max_spaces_spin)

	# Max members per space
	vbox.add_child(
		_section_label(tr("MAX MEMBERS PER SPACE (0 = unlimited)"))
	)
	_max_members_spin = SpinBox.new()
	_max_members_spin.min_value = 0
	_max_members_spin.max_value = 100000
	_max_members_spin.step = 1
	vbox.add_child(_max_members_spin)

	# MOTD
	vbox.add_child(_section_label(tr("MESSAGE OF THE DAY")))
	_motd_input = TextEdit.new()
	_motd_input.custom_minimum_size = Vector2(0, 80)
	_motd_input.placeholder_text = tr("Shown to users on login")
	vbox.add_child(_motd_input)

	# Public listing
	_public_listing_cb = CheckBox.new()
	_public_listing_cb.text = tr("List on public server directory")
	vbox.add_child(_public_listing_cb)

	# Terms of Service section
	var tos_sep := HSeparator.new()
	vbox.add_child(tos_sep)
	vbox.add_child(_section_label(tr("TERMS OF SERVICE")))

	_tos_enabled_cb = CheckBox.new()
	_tos_enabled_cb.text = tr("Require ToS acceptance during registration")
	vbox.add_child(_tos_enabled_cb)

	_tos_version_label = Label.new()
	_tos_version_label.text = tr("Current version: %d") % 1
	_tos_version_label.add_theme_font_size_override("font_size", 11)
	_tos_version_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(_tos_version_label)

	vbox.add_child(_section_label(tr("TOS TEXT (MARKDOWN)")))
	_tos_text_input = TextEdit.new()
	_tos_text_input.custom_minimum_size = Vector2(0, 160)
	_tos_text_input.placeholder_text = tr("Enter Terms of Service text...")
	vbox.add_child(_tos_text_input)

	vbox.add_child(_section_label(tr("TOS EXTERNAL URL (OPTIONAL)")))
	_tos_url_input = LineEdit.new()
	_tos_url_input.placeholder_text = "https://example.com/tos"
	vbox.add_child(_tos_url_input)

	# Save button
	_settings_save_btn = SettingsBase.create_action_button(tr("Save Settings"))
	_settings_save_btn.pressed.connect(_on_save_settings)
	vbox.add_child(_settings_save_btn)

	_fetch_settings.call_deferred()
	return vbox

func _fetch_settings() -> void:
	_settings_error.visible = false
	_settings_save_btn.disabled = true
	_settings_save_btn.text = tr("Loading...")

	var result: RestResult = await Client.admin.get_server_settings()

	_settings_save_btn.disabled = false
	_settings_save_btn.text = tr("Save Settings")

	if result == null or not result.ok:
		var msg := tr("Failed to load settings")
		if result != null and result.error:
			msg = result.error.message
		_settings_error.text = msg
		_settings_error.visible = true
		return

	if result.data is Dictionary:
		var d: Dictionary = result.data
		_server_name_input.text = d.get("server_name", "")
		var policy: String = d.get("registration_policy", "open")
		match policy:
			"invite_only": _reg_policy_dropdown.select(1)
			"closed": _reg_policy_dropdown.select(2)
			_: _reg_policy_dropdown.select(0)
		_max_spaces_spin.value = d.get("max_spaces", 0)
		_max_members_spin.value = d.get(
			"max_members_per_space", 0
		)
		var motd = d.get("motd", "")
		_motd_input.text = motd if motd != null else ""
		_public_listing_cb.button_pressed = d.get(
			"public_listing", false
		)
		_tos_enabled_cb.button_pressed = d.get(
			"tos_enabled", false
		)
		var tos_text = d.get("tos_text", "")
		_tos_text_input.text = tos_text if tos_text != null else ""
		var tos_url = d.get("tos_url", "")
		_tos_url_input.text = tos_url if tos_url != null else ""
		var tos_ver: int = d.get("tos_version", 1)
		_tos_version_label.text = tr("Current version: %d") % tos_ver

func _on_save_settings() -> void:
	_settings_save_btn.disabled = true
	_settings_save_btn.text = tr("Saving...")
	_settings_error.visible = false

	var policies := ["open", "invite_only", "closed"]
	var tos_text: String = _tos_text_input.text.strip_edges()
	var tos_url: String = _tos_url_input.text.strip_edges()
	var data := {
		"server_name": _server_name_input.text.strip_edges(),
		"registration_policy": policies[
			_reg_policy_dropdown.selected
		],
		"max_spaces": int(_max_spaces_spin.value),
		"max_members_per_space": int(_max_members_spin.value),
		"motd": _motd_input.text.strip_edges(),
		"public_listing": _public_listing_cb.button_pressed,
		"tos_enabled": _tos_enabled_cb.button_pressed,
		"tos_text": tos_text if not tos_text.is_empty() else null,
		"tos_url": tos_url if not tos_url.is_empty() else null,
	}

	var result: RestResult = await Client.admin.update_server_settings(
		data
	)

	_settings_save_btn.disabled = false
	_settings_save_btn.text = tr("Save Settings")

	if result == null or not result.ok:
		var msg := tr("Failed to save settings")
		if result != null and result.error:
			msg = result.error.message
		_settings_error.text = msg
		_settings_error.visible = true

# ── Helpers ─────────────────────────────────────────────────

static func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
