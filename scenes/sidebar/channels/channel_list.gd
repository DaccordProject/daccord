extends PanelContainer

signal channel_selected(channel_id: String)

const CategoryItemScene := preload("res://scenes/sidebar/channels/category_item.tscn")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")
const VoiceChannelItemScene := preload("res://scenes/sidebar/channels/voice_channel_item.tscn")
const CreateChannelDialogScene := preload("res://scenes/admin/create_channel_dialog.tscn")
const UncategorizedDropTargetScene := preload(
	"res://scenes/sidebar/channels/uncategorized_drop_target.tscn"
)

var channel_item_nodes: Dictionary = {}
var active_channel_id: String = ""
var pending_channel_id: String = ""
var _current_space_id: String = ""

@onready var banner: Control = $VBox/Banner
@onready var channel_vbox: VBoxContainer = $VBox/ScrollContainer/ChannelVBox
@onready var empty_state: VBoxContainer = $VBox/ScrollContainer/ChannelVBox/EmptyState

func _ready() -> void:
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.spaces_updated.connect(_on_spaces_updated)
	AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)
	AppState.channel_selected.connect(_on_app_channel_selected)

func load_space(space_id: String) -> void:
	_current_space_id = space_id
	# Clear existing (keep the persistent EmptyState node)
	for child in channel_vbox.get_children():
		if child == empty_state:
			continue
		child.queue_free()
	channel_item_nodes.clear()
	active_channel_id = ""

	var space_data := Client.get_space_by_id(space_id)
	banner.setup(space_data)

	var channels := Client.get_channels_for_space(space_id)

	# Imposter mode: filter out channels the impersonated role can't view
	if AppState.is_imposter_mode and space_id == AppState.imposter_space_id:
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
	var can_manage: bool = Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS)
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
			empty_create_btn.pressed.connect(_on_create_channel_pressed.bind(space_id, channels))
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

	# Drop target for uncategorized root when empty (supports dragging out of categories)
	if can_manage and uncategorized.is_empty() and not sorted_categories.is_empty():
		var drop_target = UncategorizedDropTargetScene.instantiate()
		channel_vbox.add_child(drop_target)
		drop_target.setup(space_id)
		drop_target.channel_dropped.connect(_on_uncategorized_drop)

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
		create_btn.pressed.connect(_on_create_channel_pressed.bind(space_id, channels))
		channel_vbox.add_child(create_btn)

	# Auto-select: pending channel if it exists, otherwise first non-voice/non-category channel
	var select_id: String = ""
	if pending_channel_id != "" and channel_item_nodes.has(pending_channel_id):
		select_id = pending_channel_id
	elif AppState.current_channel_id != "" and channel_item_nodes.has(AppState.current_channel_id):
		select_id = AppState.current_channel_id
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
	for ch in Client.get_channels_for_space(_current_space_id):
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

	_set_active_channel(channel_id)

	channel_selected.emit(channel_id)

func _on_spaces_updated() -> void:
	if _current_space_id.is_empty():
		return
	var space_data := Client.get_space_by_id(_current_space_id)
	if not space_data.is_empty():
		banner.setup(space_data)

func _on_channels_updated(space_id: String) -> void:
	if space_id == _current_space_id:
		load_space(space_id)

func _on_imposter_mode_changed(_active: bool) -> void:
	if not _current_space_id.is_empty():
		load_space(_current_space_id)

func _on_app_channel_selected(channel_id: String) -> void:
	if _current_space_id.is_empty():
		return
	if not channel_item_nodes.has(channel_id):
		return
	_set_active_channel(channel_id)

func _set_active_channel(channel_id: String) -> void:
	if channel_id == active_channel_id:
		return
	if active_channel_id != "" and channel_item_nodes.has(active_channel_id):
		channel_item_nodes[active_channel_id].set_active(false)
	active_channel_id = channel_id
	if channel_item_nodes.has(channel_id):
		channel_item_nodes[channel_id].set_active(true)

func _on_create_channel_pressed(space_id: String, channels: Array) -> void:
	var dialog := CreateChannelDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(space_id, "", channels)

func _on_uncategorized_drop(channel_data: Dictionary) -> void:
	var channel_id: String = channel_data.get("id", "")
	if channel_id == "":
		return
	if channel_data.get("parent_id", "") == "":
		return
	Client.admin.update_channel(channel_id, {"parent_id": null})
