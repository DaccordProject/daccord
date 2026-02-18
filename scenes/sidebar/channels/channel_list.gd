extends PanelContainer

signal channel_selected(channel_id: String)

const CategoryItemScene := preload("res://scenes/sidebar/channels/category_item.tscn")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")

var channel_item_nodes: Dictionary = {}
var active_channel_id: String = ""
var _current_guild_id: String = ""

@onready var banner: Control = $VBox/Banner
@onready var channel_vbox: VBoxContainer = $VBox/ScrollContainer/ChannelVBox

func _ready() -> void:
	AppState.channels_updated.connect(_on_channels_updated)

func load_guild(guild_id: String) -> void:
	_current_guild_id = guild_id
	# Clear existing
	for child in channel_vbox.get_children():
		child.queue_free()
	channel_item_nodes.clear()
	active_channel_id = ""

	var guild_data := Client.get_guild_by_id(guild_id)
	banner.setup(guild_data)

	var channels := Client.get_channels_for_guild(guild_id)

	# Group by categories
	var categories: Dictionary = {}
	var uncategorized: Array = []

	for ch in channels:
		if ch["type"] == ClientModels.ChannelType.CATEGORY:
			categories[ch["id"]] = {"data": ch, "children": []}

	for ch in channels:
		if ch["type"] == ClientModels.ChannelType.CATEGORY:
			continue
		var parent_id: String = ch.get("parent_id", "")
		if parent_id != "" and categories.has(parent_id):
			categories[parent_id]["children"].append(ch)
		else:
			uncategorized.append(ch)

	# Add uncategorized channels first
	for ch in uncategorized:
		var item: Button = ChannelItemScene.instantiate()
		channel_vbox.add_child(item)
		item.setup(ch)
		item.channel_pressed.connect(_on_channel_pressed)
		channel_item_nodes[ch["id"]] = item

	# Add categories with their children
	for cat_id in categories:
		var cat_data: Dictionary = categories[cat_id]
		var category: VBoxContainer = CategoryItemScene.instantiate()
		channel_vbox.add_child(category)
		category.setup(cat_data["data"], cat_data["children"])
		category.channel_pressed.connect(_on_channel_pressed)
		for ch in cat_data["children"]:
			# Find the channel items within the category
			for item in category.get_channel_items():
				if item.channel_id == ch["id"]:
					channel_item_nodes[ch["id"]] = item

func _on_channel_pressed(channel_id: String) -> void:
	# Deactivate previous
	if active_channel_id != "" and channel_item_nodes.has(active_channel_id):
		channel_item_nodes[active_channel_id].set_active(false)

	active_channel_id = channel_id

	# Activate new
	if channel_item_nodes.has(channel_id):
		channel_item_nodes[channel_id].set_active(true)

	channel_selected.emit(channel_id)

func _on_channels_updated(guild_id: String) -> void:
	if guild_id == _current_guild_id:
		load_guild(guild_id)
