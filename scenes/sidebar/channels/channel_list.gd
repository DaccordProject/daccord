extends PanelContainer

signal channel_selected(channel_id: String)

const CategoryItemScene := preload("res://scenes/sidebar/channels/category_item.tscn")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")
const VoiceChannelItemScene := preload("res://scenes/sidebar/channels/voice_channel_item.tscn")
const CreateChannelDialogScene := preload("res://scenes/admin/create_channel_dialog.tscn")

var channel_item_nodes: Dictionary = {}
var active_channel_id: String = ""
var pending_channel_id: String = ""
var _current_guild_id: String = ""

@onready var banner: Control = $VBox/Banner
@onready var channel_vbox: VBoxContainer = $VBox/ScrollContainer/ChannelVBox
@onready var empty_state: VBoxContainer = $VBox/ScrollContainer/ChannelVBox/EmptyState

func _ready() -> void:
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)

func load_guild(guild_id: String) -> void:
	_current_guild_id = guild_id
	# Clear existing (keep the persistent EmptyState node)
	for child in channel_vbox.get_children():
		if child == empty_state:
			continue
		child.queue_free()
	channel_item_nodes.clear()
	active_channel_id = ""

	var guild_data := Client.get_guild_by_id(guild_id)
	banner.setup(guild_data)

	var channels := Client.get_channels_for_guild(guild_id)

	# Imposter mode: filter out channels the impersonated role can't view
	if AppState.is_imposter_mode and guild_id == AppState.imposter_guild_id:
		var filtered: Array = []
		for ch in channels:
			if ch["type"] == ClientModels.ChannelType.CATEGORY:
				filtered.append(ch)
				continue
			if AccordPermission.has(AppState.imposter_permissions, AccordPermission.VIEW_CHANNEL):
				filtered.append(ch)
		channels = filtered

	# Count non-category channels
	var selectable_channels: int = 0
	for ch in channels:
		if ch["type"] != ClientModels.ChannelType.CATEGORY:
			selectable_channels += 1

	# Show/hide empty state
	var can_manage: bool = Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS)
	if selectable_channels == 0:
		empty_state.visible = true
		var empty_title: Label = empty_state.get_node("EmptyTitle")
		var empty_desc: Label = empty_state.get_node("EmptyDesc")
		var empty_create_btn: Button = empty_state.get_node("EmptyCreateBtn")
		if can_manage:
			empty_title.text = "No channels yet"
			empty_desc.text = "Create your first channel to get started."
			empty_create_btn.visible = true
			# Disconnect old signals to avoid duplicates
			for conn in empty_create_btn.pressed.get_connections():
				empty_create_btn.pressed.disconnect(conn["callable"])
			empty_create_btn.pressed.connect(_on_create_channel_pressed.bind(guild_id, channels))
		else:
			empty_title.text = "No channels yet"
			empty_desc.text = "This space doesn't have any channels yet. Check back soon!"
			empty_create_btn.visible = false
	else:
		empty_state.visible = false

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

	# Sort uncategorized channels by position then name
	var sort_by_position := func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = a.get("position", 0)
		var pb: int = b.get("position", 0)
		if pa != pb: return pa < pb
		return a.get("name", "") < b.get("name", "")

	uncategorized.sort_custom(sort_by_position)

	# Sort children within each category
	for cat_id in categories:
		categories[cat_id]["children"].sort_custom(sort_by_position)

	# Sort categories by position then name
	var sorted_categories: Array = []
	for cat_id in categories:
		sorted_categories.append(categories[cat_id])
	sorted_categories.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = a["data"].get("position", 0)
		var pb: int = b["data"].get("position", 0)
		if pa != pb: return pa < pb
		return a["data"].get("name", "") < b["data"].get("name", "")
	)

	# Add uncategorized channels first
	for ch in uncategorized:
		var is_voice: bool = ch.get("type", 0) == ClientModels.ChannelType.VOICE
		var item: Control
		if is_voice:
			item = VoiceChannelItemScene.instantiate()
		else:
			item = ChannelItemScene.instantiate()
		channel_vbox.add_child(item)
		item.setup(ch)
		item.channel_pressed.connect(_on_channel_pressed)
		channel_item_nodes[ch["id"]] = item

	# Add categories with their children
	for cat_data in sorted_categories:
		var category: VBoxContainer = CategoryItemScene.instantiate()
		channel_vbox.add_child(category)
		category.setup(cat_data["data"], cat_data["children"])
		category.restore_collapse_state()
		category.channel_pressed.connect(_on_channel_pressed)
		for ch in cat_data["children"]:
			# Find the channel items within the category
			for item in category.get_channel_items():
				if item.channel_id == ch["id"]:
					channel_item_nodes[ch["id"]] = item

	# "Create Channel" button at bottom (only if user has permission and channels exist)
	if can_manage and selectable_channels > 0:
		var create_btn := Button.new()
		create_btn.text = "+ Create Channel"
		create_btn.flat = true
		create_btn.custom_minimum_size = Vector2(0, 36)
		create_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		create_btn.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		create_btn.pressed.connect(_on_create_channel_pressed.bind(guild_id, channels))
		channel_vbox.add_child(create_btn)

	# Auto-select: pending channel if it exists, otherwise first non-voice/non-category channel
	var select_id: String = ""
	if pending_channel_id != "" and channel_item_nodes.has(pending_channel_id):
		select_id = pending_channel_id
	else:
		for ch in channels:
			var ch_type: int = ch.get("type", 0)
			if ch_type != ClientModels.ChannelType.CATEGORY \
					and ch_type != ClientModels.ChannelType.VOICE \
					and channel_item_nodes.has(ch["id"]):
				select_id = ch["id"]
				break
	pending_channel_id = ""
	if select_id != "":
		_on_channel_pressed(select_id)

func _on_channel_pressed(channel_id: String) -> void:
	# Check if this is a voice channel
	var ch_data: Dictionary = {}
	for ch in Client.get_channels_for_guild(_current_guild_id):
		if ch.get("id", "") == channel_id:
			ch_data = ch
			break
	if ch_data.get("type", 0) == ClientModels.ChannelType.VOICE:
		# Voice channels toggle join/leave instead of selecting
		if AppState.voice_channel_id == channel_id:
			Client.leave_voice_channel()
		else:
			Client.join_voice_channel(channel_id)
		return

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

func _on_imposter_mode_changed(_active: bool) -> void:
	if not _current_guild_id.is_empty():
		load_guild(_current_guild_id)

func _on_create_channel_pressed(guild_id: String, channels: Array) -> void:
	var dialog := CreateChannelDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(guild_id, "", channels)
