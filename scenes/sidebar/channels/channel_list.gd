extends PanelContainer

signal channel_selected(channel_id: String)

const CategoryItemScene := preload("res://scenes/sidebar/channels/category_item.tscn")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")
const VoiceChannelItemScene := preload("res://scenes/sidebar/channels/voice_channel_item.tscn")
const CreateChannelDialogScene := preload("res://scenes/admin/create_channel_dialog.tscn")
const NsfwGateDialogScene := preload("res://scenes/admin/nsfw_gate_dialog.tscn")
const UncategorizedDropTargetScene := preload(
	"res://scenes/sidebar/channels/uncategorized_drop_target.tscn"
)

var channel_item_nodes: Dictionary = {}
var active_channel_id: String = ""
var pending_channel_id: String = ""
var _current_space_id: String = ""

@onready var banner: Control = $VBox/Banner
@onready var channel_vbox: VBoxContainer = $VBox/ScrollContainer/ChannelVBox
@onready var channel_skeleton: VBoxContainer = $VBox/ScrollContainer/ChannelVBox/ChannelSkeleton
@onready var empty_state: VBoxContainer = $VBox/ScrollContainer/ChannelVBox/EmptyState

func _ready() -> void:
	add_to_group("themed")
	_apply_theme()
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.spaces_updated.connect(_on_spaces_updated)
	AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)
	AppState.channel_selected.connect(_on_app_channel_selected)
	# Show skeleton immediately if servers are configured but not yet connected
	if Config.has_servers() and Client.spaces.is_empty():
		channel_skeleton.visible = true
		channel_skeleton.reset_shimmer()

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("panel_bg")
	ThemeManager.apply_font_colors(self)

func show_connecting(space_data: Dictionary) -> void:
	_current_space_id = space_data.get("id", "")
	for child in channel_vbox.get_children():
		if child == empty_state or child == channel_skeleton:
			continue
		child.queue_free()
	channel_item_nodes.clear()
	active_channel_id = ""
	banner.setup(space_data)
	empty_state.visible = false
	channel_skeleton.visible = true
	channel_skeleton.reset_shimmer()

func load_space(space_id: String) -> void:
	_current_space_id = space_id
	var was_skeleton: bool = channel_skeleton.visible
	# Clear existing (keep the persistent EmptyState and ChannelSkeleton nodes)
	for child in channel_vbox.get_children():
		if child == empty_state or child == channel_skeleton:
			continue
		child.queue_free()
	channel_item_nodes.clear()
	active_channel_id = ""
	channel_skeleton.visible = false

	var space_data := Client.get_space_by_id(space_id)
	banner.setup(space_data)

	var channels := Client.get_channels_for_space(space_id)

	# In guest mode, only show channels marked as publicly readable.
	if AppState.is_guest_mode:
		var guest_filtered: Array = []
		for ch in channels:
			if ch["type"] == ClientModels.ChannelType.CATEGORY:
				guest_filtered.append(ch)
				continue
			if ch.get("allow_anonymous_read", false):
				guest_filtered.append(ch)
		# Remove empty categories (no visible children)
		var cat_ids_with_children: Dictionary = {}
		for ch in guest_filtered:
			if ch["type"] != ClientModels.ChannelType.CATEGORY:
				var pid: String = ch.get("parent_id", "")
				if not pid.is_empty():
					cat_ids_with_children[pid] = true
		var final_filtered: Array = []
		for ch in guest_filtered:
			if ch["type"] == ClientModels.ChannelType.CATEGORY:
				if cat_ids_with_children.has(ch["id"]):
					final_filtered.append(ch)
			else:
				final_filtered.append(ch)
		channels = final_filtered

	# Filter channels by VIEW_CHANNEL permission.
	# In imposter mode, show hidden channels with a lock icon so the admin
	# can see which channels the previewed role cannot access.
	var filtered: Array = []
	for ch in channels:
		if ch["type"] == ClientModels.ChannelType.CATEGORY:
			filtered.append(ch)
			continue
		var ch_id: String = ch.get("id", "")
		if Client.has_channel_permission(space_id, ch_id, AccordPermission.VIEW_CHANNEL):
			filtered.append(ch)
		elif AppState.is_imposter_mode:
			var locked_ch: Dictionary = ch.duplicate()
			locked_ch["locked"] = true
			filtered.append(locked_ch)
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
			empty_title.text = tr("No channels yet")
			empty_desc.text = tr("Create your first channel to get started.")
			empty_create_btn.visible = true
			# Disconnect old signals to avoid duplicates
			for conn in empty_create_btn.pressed.get_connections():
				empty_create_btn.pressed.disconnect(conn["callable"])
			empty_create_btn.pressed.connect(_on_create_channel_pressed.bind(space_id, channels))
		else:
			empty_title.text = tr("No channels yet")
			empty_desc.text = tr("This space doesn't have any channels yet. Check back soon!")
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
		create_btn.text = tr("+ Create Channel")
		create_btn.flat = true
		create_btn.custom_minimum_size = Vector2(0, 36)
		create_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		create_btn.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
		create_btn.pressed.connect(_on_create_channel_pressed.bind(space_id, channels))
		channel_vbox.add_child(create_btn)

	# Auto-select: pending channel if it exists, otherwise first non-voice/non-category channel.
	# Skip locked channels — they cannot be selected in imposter mode.
	var select_id: String = ""
	if pending_channel_id != "" and channel_item_nodes.has(pending_channel_id):
		select_id = pending_channel_id
	elif AppState.current_channel_id != "" and channel_item_nodes.has(AppState.current_channel_id):
		select_id = AppState.current_channel_id
	else:
		var nsfw_acked: bool = Client.is_nsfw_acked(_current_space_id)
		for ch in channels:
			if ch.get("locked", false):
				continue
			var ch_type: int = ch.get("type", 0)
			if ch_type != ClientModels.ChannelType.CATEGORY \
					and ch_type != ClientModels.ChannelType.VOICE \
					and channel_item_nodes.has(ch["id"]):
				if ch.get("nsfw", false) and not nsfw_acked:
					if select_id.is_empty():
						select_id = ch["id"]
					continue
				select_id = ch["id"]
				break
	pending_channel_id = ""
	if select_id != "":
		_on_channel_pressed(select_id)

	# Fade in channel content when replacing skeleton
	if was_skeleton and not Config.get_reduced_motion():
		channel_vbox.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(channel_vbox, "modulate:a", 1.0, 0.25) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _on_channel_pressed(channel_id: String) -> void:
	# Check if this is a voice channel
	var ch_data: Dictionary = {}
	for ch in Client.get_channels_for_space(_current_space_id):
		if ch.get("id", "") == channel_id:
			ch_data = ch
			break
	if ch_data.get("type", 0) == ClientModels.ChannelType.VOICE:
		# Guest mode: show registration prompt instead of joining
		if GuestPrompt.show_if_guest():
			return
		# Check CONNECT permission before joining
		if not Client.has_channel_permission(
			_current_space_id, channel_id, AccordPermission.CONNECT
		):
			return
		_set_active_channel(channel_id)
		if AppState.voice_channel_id == channel_id:
			# Already in this voice channel — open the video view
			AppState.open_voice_view()
		else:
			Client.join_voice_channel(channel_id)
		return

	# NSFW age gate
	if ch_data.get("nsfw", false) and not Client.is_nsfw_acked(_current_space_id):
		_show_nsfw_gate(channel_id)
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

func _show_nsfw_gate(channel_id: String) -> void:
	var dialog := NsfwGateDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.acknowledged.connect(func() -> void:
		var base_url := Client.get_base_url_for_space(_current_space_id)
		Config.set_nsfw_ack(base_url)
		_on_channel_pressed(channel_id)
	)

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
