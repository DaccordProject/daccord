extends VBoxContainer

signal guild_pressed(guild_id: String)
signal folder_changed()

const GuildIconScene := preload("res://scenes/sidebar/guild_bar/guild_icon.tscn")
const AvatarScene := preload("res://scenes/common/avatar.tscn")

var folder_name: String = ""
var is_expanded: bool = false
var is_active: bool = false
var guild_icons: Array = []
var _has_unread: bool = false
var _active_guild_id: String = ""
var _expand_tween: Tween
var _guilds_data_cache: Array = []
var _context_menu: PopupMenu
var _drop_above: bool = false
var _drop_hovered: bool = false

@onready var pill: ColorRect = $FolderRow/PillContainer/Pill
@onready var folder_button: Button = $FolderRow/ButtonContainer/FolderButton
@onready var mini_grid: GridContainer = $FolderRow/ButtonContainer/FolderButton/MiniGrid
@onready var mention_badge: PanelContainer = $FolderRow/ButtonContainer/BadgeAnchor/MentionBadge
@onready var guild_list: VBoxContainer = $GuildList

func _ready() -> void:
	folder_button.pressed.connect(_toggle_expanded)
	folder_button.tooltip_text = folder_name
	# Style folder button
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.212, 0.224, 0.247)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	folder_button.add_theme_stylebox_override("normal", style)

	# Context menu
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	folder_button.gui_input.connect(_on_folder_gui_input)
	folder_button.set_drag_forwarding(_folder_get_drag_data, _folder_can_drop_data, _folder_drop_data)

func setup(p_name: String, guilds: Array, folder_color: Color = Color(0.212, 0.224, 0.247)) -> void:
	folder_name = p_name
	_guilds_data_cache = guilds
	if folder_button:
		folder_button.tooltip_text = p_name
		# Apply folder color (darkened)
		var style: StyleBoxFlat = folder_button.get_theme_stylebox("normal").duplicate()
		style.bg_color = folder_color.darkened(0.6)
		folder_button.add_theme_stylebox_override("normal", style)

	# Create mini grid preview (up to 4 tiny guild avatars)
	for child in mini_grid.get_children():
		child.queue_free()
	for i in min(guilds.size(), 4):
		var avatar: ColorRect = AvatarScene.instantiate()
		avatar.avatar_size = 14
		avatar.show_letter = false
		avatar.custom_minimum_size = Vector2(14, 14)
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini_grid.add_child(avatar)
		avatar.set_avatar_color(guilds[i].get("icon_color", Color.GRAY))
		var icon_url = guilds[i].get("icon", null)
		if icon_url is String and not icon_url.is_empty():
			avatar.set_avatar_url(icon_url)

	# Create full guild icons for expanded view
	for child in guild_list.get_children():
		child.queue_free()
	guild_icons.clear()
	for g in guilds:
		var icon: HBoxContainer = GuildIconScene.instantiate()
		guild_list.add_child(icon)
		icon.setup(g)
		icon.guild_pressed.connect(func(id: String): guild_pressed.emit(id))
		guild_icons.append(icon)

	# Aggregate notifications
	_update_notifications(guilds)

func _update_notifications(guilds: Array) -> void:
	var total_mentions: int = 0
	var any_unread: bool = false
	for g in guilds:
		total_mentions += g.get("mentions", 0)
		if g.get("unread", false):
			any_unread = true
	_has_unread = any_unread

	if mention_badge:
		mention_badge.count = total_mentions

	_update_pill_state()

func _update_pill_state() -> void:
	if not pill:
		return
	if is_active:
		pill.pill_state = pill.PillState.ACTIVE
	elif _has_unread:
		pill.pill_state = pill.PillState.UNREAD
	else:
		pill.pill_state = pill.PillState.HIDDEN

func set_active(active: bool) -> void:
	is_active = active
	if not active:
		_active_guild_id = ""
		# Deactivate all child guild icons
		for icon in guild_icons:
			if icon.has_method("set_active"):
				icon.set_active(false)
	if pill:
		if active:
			pill.set_state_animated(pill.PillState.ACTIVE)
		elif _has_unread:
			pill.set_state_animated(pill.PillState.UNREAD)
		else:
			pill.set_state_animated(pill.PillState.HIDDEN)

func set_active_guild(guild_id: String) -> void:
	_active_guild_id = guild_id
	is_active = true
	# Activate the matching child icon, deactivate others
	for icon in guild_icons:
		if icon.has_method("set_active"):
			icon.set_active(icon.guild_id == guild_id)
	if pill:
		pill.set_state_animated(pill.PillState.ACTIVE)

func _toggle_expanded() -> void:
	is_expanded = !is_expanded
	mini_grid.visible = !is_expanded

	if _expand_tween and _expand_tween.is_valid():
		_expand_tween.kill()

	if Config.get_reduced_motion():
		guild_list.visible = is_expanded
		guild_list.modulate.a = 1.0
		return

	if is_expanded:
		guild_list.visible = true
		guild_list.modulate.a = 0.0
		_expand_tween = create_tween()
		_expand_tween.tween_property(guild_list, "modulate:a", 1.0, 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		_expand_tween = create_tween()
		_expand_tween.tween_property(guild_list, "modulate:a", 0.0, 0.15) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_expand_tween.tween_callback(func(): guild_list.visible = false)

# --- Context Menu ---

func _on_folder_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	_context_menu.add_item("Rename Folder", 0)
	_context_menu.add_item("Change Color", 1)
	_context_menu.add_separator()
	_context_menu.add_item("Delete Folder", 3)
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _show_rename_dialog()
		1: _show_color_picker()
		3: _show_delete_confirm()

func _show_rename_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Rename Folder"
	dialog.ok_button_text = "Rename"

	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "New folder name:"
	label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(label)

	var line_edit := LineEdit.new()
	line_edit.text = folder_name
	line_edit.custom_minimum_size = Vector2(200, 0)
	line_edit.select_all_on_focus = true
	vbox.add_child(line_edit)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		var new_name: String = line_edit.text.strip_edges()
		if not new_name.is_empty() and new_name != folder_name:
			_rename_folder(new_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()

func _rename_folder(new_name: String) -> void:
	var old_name := folder_name
	# Update all guilds in this folder
	for icon in guild_icons:
		Config.set_guild_folder(icon.guild_id, new_name)
		Client.update_guild_folder(icon.guild_id, new_name)
	# Migrate folder color
	Config.rename_folder_color(old_name, new_name)
	# Update saved order
	var order: Array = Config.get_guild_order()
	for entry in order:
		if entry is Dictionary and entry.get("type") == "folder" and entry.get("name") == old_name:
			entry["name"] = new_name
			break
	Config.set_guild_order(order)

func _show_color_picker() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Folder Color"
	dialog.ok_button_text = "Apply"

	var picker := ColorPicker.new()
	picker.custom_minimum_size = Vector2(300, 200)
	picker.color = Config.get_folder_color(folder_name)
	dialog.add_child(picker)

	dialog.confirmed.connect(func():
		Config.set_folder_color(folder_name, picker.color)
		# Trigger rebuild
		AppState.guilds_updated.emit()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _show_delete_confirm() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Folder"
	dialog.ok_button_text = "Delete"
	dialog.dialog_text = (
		"Remove all guilds from '%s'?"
		+ " The servers will remain in your server list."
	) % folder_name

	dialog.confirmed.connect(func():
		_delete_folder()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _delete_folder() -> void:
	# Update saved order: replace folder entry with standalone guild entries
	var order: Array = Config.get_guild_order()
	var new_order: Array = []
	for entry in order:
		if entry is Dictionary and entry.get("type") == "folder" and entry.get("name") == folder_name:
			# Replace folder with its guild entries
			for icon in guild_icons:
				new_order.append({"type": "guild", "id": icon.guild_id})
		else:
			new_order.append(entry)
	Config.set_guild_order(new_order)
	for icon in guild_icons:
		Config.set_guild_folder(icon.guild_id, "")
		Client.update_guild_folder(icon.guild_id, "")
	Config.delete_folder_color(folder_name)

# --- Drag-and-drop reordering ---

func _folder_get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = folder_name
	preview.add_theme_font_size_override("font_size", 11)
	preview.add_theme_color_override("font_color", Color(1, 1, 1))
	set_drag_preview(preview)
	return {"type": "guild_bar_item", "item_type": "folder", "folder_name": folder_name, "source_node": self}

func _folder_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "guild_bar_item":
		_clear_drop_indicator()
		return false
	var source: Control = data.get("source_node")
	if source == self:
		_clear_drop_indicator()
		return false
	# Accept sibling reorder or standalone guild being dropped onto folder
	if source == null or source.get_parent() != get_parent():
		_clear_drop_indicator()
		return false
	# at_position is relative to folder_button (via set_drag_forwarding)
	var btn_h: float = folder_button.size.y
	# If a standalone guild is dropped onto center of folder, add to folder
	var item_type: String = data.get("item_type", "")
	if item_type == "guild":
		var third: float = btn_h / 3.0
		if at_position.y > third and at_position.y < third * 2.0:
			# Center zone: drop into folder
			_drop_above = false
			_drop_hovered = false
			queue_redraw()
			return true
	_drop_above = at_position.y < btn_h / 2.0
	_drop_hovered = true
	queue_redraw()
	return true

func _folder_drop_data(at_position: Vector2, data: Variant) -> void:
	_clear_drop_indicator()
	var source: Control = data.get("source_node")
	if source == null or source.get_parent() != get_parent():
		return
	var item_type: String = data.get("item_type", "")
	# Check if standalone guild dropped onto folder center (add to folder)
	var btn_h: float = folder_button.size.y
	if item_type == "guild":
		var third: float = btn_h / 3.0
		if at_position.y > third and at_position.y < third * 2.0:
			var gid: String = data.get("guild_id", "")
			if not gid.is_empty():
				Config.set_guild_folder(gid, folder_name)
				Client.update_guild_folder(gid, folder_name)
				# Remove standalone entry from order (folder already tracked)
				var order: Array = Config.get_guild_order()
				var cleaned: Array = []
				for entry in order:
					if entry is Dictionary and entry.get("type") == "guild" and entry.get("id") == gid:
						continue
					cleaned.append(entry)
				Config.set_guild_order(cleaned)
			return
	# Sibling reorder
	var container := get_parent()
	var target_idx: int = get_index()
	if not _drop_above:
		target_idx += 1
	container.move_child(source, target_idx)
	_save_guild_bar_order()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_indicator()

func _clear_drop_indicator() -> void:
	if _drop_hovered:
		_drop_hovered = false
		queue_redraw()

func _draw() -> void:
	if not _drop_hovered:
		return
	var line_color := Color(0.34, 0.52, 0.89)
	if _drop_above:
		draw_line(Vector2(0, 0), Vector2(size.x, 0), line_color, 2.0)
	else:
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), line_color, 2.0)

func _save_guild_bar_order() -> void:
	var container := get_parent()
	var order: Array = []
	for child in container.get_children():
		if child is HBoxContainer and "guild_id" in child and not child.guild_id.is_empty():
			order.append({"type": "guild", "id": child.guild_id})
		elif child is VBoxContainer and "folder_name" in child and not child.folder_name.is_empty():
			order.append({"type": "folder", "name": child.folder_name})
	Config.set_guild_order(order)
