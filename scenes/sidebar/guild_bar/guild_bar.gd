extends PanelContainer

signal guild_selected(guild_id: String)
signal dm_selected()

const GuildIconScene := preload("res://scenes/sidebar/guild_bar/guild_icon.tscn")
const GuildFolderScene := preload("res://scenes/sidebar/guild_bar/guild_folder.tscn")
const AddServerDialogScene := preload("res://scenes/sidebar/guild_bar/add_server_dialog.tscn")

var guild_icon_nodes: Dictionary = {}
var active_guild_id: String = ""

@onready var dm_button: HBoxContainer = $ScrollContainer/VBox/DMButton
@onready var guild_list: VBoxContainer = $ScrollContainer/VBox/GuildList
@onready var add_server_button: HBoxContainer = $ScrollContainer/VBox/AddServerButton

func _ready() -> void:
	dm_button.dm_pressed.connect(_on_dm_pressed)
	add_server_button.add_server_pressed.connect(_on_add_server_pressed)
	AppState.guilds_updated.connect(_on_guilds_updated)
	_populate_guilds()

func _populate_guilds() -> void:
	# Group guilds by folder
	var standalone: Dictionary = {}  # guild_id -> data
	var folders: Dictionary = {}  # folder_name -> [guild_data, ...]

	for g in Client.guilds:
		var folder_name: String = g.get("folder", "")
		if folder_name.is_empty():
			standalone[g.get("id", "")] = g
		else:
			if not folders.has(folder_name):
				folders[folder_name] = []
			folders[folder_name].append(g)

	# Read saved order and place items in saved sequence
	var saved_order: Array = Config.get_guild_order()
	var placed_guild_ids: Array = []
	var placed_folder_names: Array = []

	for entry in saved_order:
		if not entry is Dictionary:
			continue
		var entry_type: String = entry.get("type", "")
		if entry_type == "guild":
			var gid: String = entry.get("id", "")
			if standalone.has(gid):
				_add_guild_icon(standalone[gid])
				placed_guild_ids.append(gid)
		elif entry_type == "folder":
			var fname: String = entry.get("name", "")
			if folders.has(fname):
				_add_guild_folder(fname, folders[fname])
				placed_folder_names.append(fname)

	# Append any items not in saved order (new servers/folders)
	var processed_folders: Array = []
	for g in Client.guilds:
		var folder_name: String = g.get("folder", "")
		if folder_name.is_empty():
			if g.get("id", "") not in placed_guild_ids:
				_add_guild_icon(g)
		elif folder_name not in placed_folder_names and folder_name not in processed_folders:
			processed_folders.append(folder_name)
			_add_guild_folder(folder_name, folders[folder_name])

	# Add pending (disconnected) servers
	for pending in Client.pending_servers:
		_add_guild_icon(pending)

func _add_guild_icon(data: Dictionary) -> void:
	var icon: HBoxContainer = GuildIconScene.instantiate()
	guild_list.add_child(icon)
	icon.setup(data)
	icon.guild_pressed.connect(_on_guild_pressed)
	guild_icon_nodes[data["id"]] = icon

func _add_guild_folder(folder_name: String, guilds: Array) -> void:
	var folder: VBoxContainer = GuildFolderScene.instantiate()
	guild_list.add_child(folder)
	var folder_color: Color = Config.get_folder_color(folder_name)
	folder.setup(folder_name, guilds, folder_color)
	folder.guild_pressed.connect(_on_guild_pressed)
	folder.folder_changed.connect(_on_guilds_updated)
	for g in guilds:
		guild_icon_nodes[g["id"]] = folder

func _on_guild_pressed(guild_id: String) -> void:
	# Deactivate previous
	if active_guild_id != "" and guild_icon_nodes.has(active_guild_id):
		var prev = guild_icon_nodes[active_guild_id]
		if prev.has_method("set_active"):
			prev.set_active(false)

	active_guild_id = guild_id
	dm_button.set_active(false)

	# Activate new
	if guild_icon_nodes.has(guild_id):
		var node = guild_icon_nodes[guild_id]
		if node.has_method("set_active_guild"):
			node.set_active_guild(guild_id)
		elif node.has_method("set_active"):
			node.set_active(true)

	guild_selected.emit(guild_id)

func _on_guilds_updated() -> void:
	var prev_active := active_guild_id
	for child in guild_list.get_children():
		child.queue_free()
	guild_icon_nodes.clear()
	_populate_guilds()
	# Restore active state after rebuild
	if prev_active != "" and guild_icon_nodes.has(prev_active):
		active_guild_id = prev_active
		var node = guild_icon_nodes[prev_active]
		if node.has_method("set_active_guild"):
			node.set_active_guild(prev_active)
		elif node.has_method("set_active"):
			node.set_active(true)

func _on_add_server_pressed() -> void:
	var dialog := AddServerDialogScene.instantiate()
	dialog.server_added.connect(_on_server_added)
	get_tree().root.add_child(dialog)

func _on_server_added(guild_id: String) -> void:
	if not guild_id.is_empty():
		_on_guild_pressed(guild_id)

func _on_dm_pressed() -> void:
	if active_guild_id != "" and guild_icon_nodes.has(active_guild_id):
		var prev = guild_icon_nodes[active_guild_id]
		if prev.has_method("set_active"):
			prev.set_active(false)
	active_guild_id = ""
	dm_button.set_active(true)
	dm_selected.emit()

func get_active_guild_id() -> String:
	return active_guild_id
