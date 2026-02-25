extends PanelContainer

signal space_selected(space_id: String)
signal dm_selected()

const GuildIconScene := preload("res://scenes/sidebar/guild_bar/guild_icon.tscn")
const GuildFolderScene := preload("res://scenes/sidebar/guild_bar/guild_folder.tscn")
const AddServerDialogScene := preload("res://scenes/sidebar/guild_bar/add_server_dialog.tscn")

var space_icon_nodes: Dictionary = {}
var active_space_id: String = ""

@onready var dm_button: HBoxContainer = $ScrollContainer/VBox/DMButton
@onready var space_list: VBoxContainer = $ScrollContainer/VBox/GuildList
@onready var add_server_button: HBoxContainer = $ScrollContainer/VBox/AddServerButton

func _ready() -> void:
	dm_button.dm_pressed.connect(_on_dm_pressed)
	add_server_button.add_server_pressed.connect(_on_add_server_pressed)
	AppState.spaces_updated.connect(_on_spaces_updated)
	_populate_spaces()

func _populate_spaces() -> void:
	# Group spaces by folder
	var standalone: Dictionary = {}  # space_id -> data
	var folders: Dictionary = {}  # folder_name -> [space_data, ...]

	for g in Client.spaces:
		var folder_name: String = g.get("folder", "")
		if folder_name.is_empty():
			standalone[g.get("id", "")] = g
		else:
			if not folders.has(folder_name):
				folders[folder_name] = []
			folders[folder_name].append(g)

	# Read saved order and place items in saved sequence
	var saved_order: Array = Config.get_space_order()
	var final_order: Array = []
	var placed_space_ids: Array = []
	var placed_folder_names: Array = []

	for entry in saved_order:
		if not entry is Dictionary:
			continue
		var entry_type: String = entry.get("type", "")
		if entry_type == "space":
			var gid: String = entry.get("id", "")
			if gid.begins_with("__pending_"):
				continue
			if standalone.has(gid) and gid not in placed_space_ids:
				_add_space_icon(standalone[gid])
				placed_space_ids.append(gid)
				final_order.append(entry)
		elif entry_type == "folder":
			var fname: String = entry.get("name", "")
			if folders.has(fname):
				_add_space_folder(fname, folders[fname])
				placed_folder_names.append(fname)
				final_order.append(entry)

	# Append any items not in saved order (new servers/folders)
	var has_new_items := false
	var processed_folders: Array = []
	for g in Client.spaces:
		var folder_name: String = g.get("folder", "")
		if folder_name.is_empty():
			if g.get("id", "") not in placed_space_ids:
				_add_space_icon(g)
				final_order.append({"type": "space", "id": g.get("id", "")})
				has_new_items = true
		elif folder_name not in placed_folder_names and folder_name not in processed_folders:
			processed_folders.append(folder_name)
			_add_space_folder(folder_name, folders[folder_name])
			final_order.append({"type": "folder", "name": folder_name})
			has_new_items = true

	# Persist the cleaned order
	if has_new_items or final_order != saved_order:
		Config.set_space_order(final_order)

	# Add pending (disconnected) servers
	for pending in Client.pending_servers:
		_add_space_icon(pending)

func _add_space_icon(data: Dictionary) -> void:
	var icon: HBoxContainer = GuildIconScene.instantiate()
	space_list.add_child(icon)
	icon.setup(data)
	icon.space_pressed.connect(_on_space_pressed)
	space_icon_nodes[data["id"]] = icon

func _add_space_folder(folder_name: String, spaces: Array) -> void:
	var folder: VBoxContainer = GuildFolderScene.instantiate()
	space_list.add_child(folder)
	var folder_color: Color = Config.get_folder_color(folder_name)
	folder.setup(folder_name, spaces, folder_color)
	folder.space_pressed.connect(_on_space_pressed)
	folder.folder_changed.connect(_on_spaces_updated)
	for g in spaces:
		space_icon_nodes[g["id"]] = folder

func _on_space_pressed(space_id: String) -> void:
	# Deactivate previous
	if active_space_id != "" and space_icon_nodes.has(active_space_id):
		var prev = space_icon_nodes[active_space_id]
		if prev.has_method("set_active"):
			prev.set_active(false)

	active_space_id = space_id
	dm_button.set_active(false)

	# Activate new
	if space_icon_nodes.has(space_id):
		var node = space_icon_nodes[space_id]
		if node.has_method("set_active_space"):
			node.set_active_space(space_id)
		elif node.has_method("set_active"):
			node.set_active(true)

	space_selected.emit(space_id)

func _on_spaces_updated() -> void:
	var prev_active := active_space_id
	for child in space_list.get_children():
		space_list.remove_child(child)
		child.queue_free()
	space_icon_nodes.clear()
	_populate_spaces()
	# Restore active state after rebuild
	if prev_active != "" and space_icon_nodes.has(prev_active):
		active_space_id = prev_active
		var node = space_icon_nodes[prev_active]
		if node.has_method("set_active_space"):
			node.set_active_space(prev_active)
		elif node.has_method("set_active"):
			node.set_active(true)

func _on_add_server_pressed() -> void:
	var dialog := AddServerDialogScene.instantiate()
	dialog.server_added.connect(_on_server_added)
	get_tree().root.add_child(dialog)

func _on_server_added(space_id: String) -> void:
	if not space_id.is_empty():
		_on_space_pressed(space_id)

func _on_dm_pressed() -> void:
	if active_space_id != "" and space_icon_nodes.has(active_space_id):
		var prev = space_icon_nodes[active_space_id]
		if prev.has_method("set_active"):
			prev.set_active(false)
	active_space_id = ""
	dm_button.set_active(true)
	dm_selected.emit()

func get_active_space_id() -> String:
	return active_space_id
