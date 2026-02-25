extends HBoxContainer

const CHANNEL_PANEL_WIDTH: float = 240.0
const CHANNEL_PANEL_ANIM_DURATION: float = 0.15

var _startup_selection_done: bool = false
var _startup_fallback_selected: bool = false
var _startup_timer: Timer
var _channel_panel_tween: Tween

@onready var guild_bar: PanelContainer = $GuildBar
@onready var channel_panel: VBoxContainer = $ChannelPanel
@onready var channel_list: PanelContainer = $ChannelPanel/ChannelList
@onready var dm_list: PanelContainer = $ChannelPanel/DMList
@onready var user_bar: PanelContainer = $ChannelPanel/UserBar

func _ready() -> void:
	guild_bar.space_selected.connect(_on_space_selected)
	guild_bar.dm_selected.connect(_on_dm_selected)
	channel_list.channel_selected.connect(_on_channel_selected)
	dm_list.dm_selected.connect(_on_dm_selected_channel)
	AppState.spaces_updated.connect(_on_spaces_updated)
	AppState.server_removed.connect(_on_server_removed)
	_startup_timer = Timer.new()
	_startup_timer.wait_time = 5.0
	_startup_timer.one_shot = true
	_startup_timer.timeout.connect(_on_startup_timeout)
	add_child(_startup_timer)

func _on_spaces_updated() -> void:
	if _startup_selection_done:
		return
	if Client.spaces.size() == 0:
		return

	var saved := Config.get_last_selection()

	# Check if saved space is now available
	if saved["space_id"] != "":
		for g in Client.spaces:
			if g["id"] == saved["space_id"]:
				# Saved space found -- select it and finish startup
				_startup_selection_done = true
				_startup_timer.stop()
				channel_list.pending_channel_id = saved["channel_id"]
				guild_bar._on_space_pressed(saved["space_id"])
				return

	# Saved space not yet available -- select first space as fallback
	if not _startup_fallback_selected:
		_startup_fallback_selected = true
		channel_list.pending_channel_id = ""
		guild_bar._on_space_pressed(Client.spaces[0]["id"])
		_startup_timer.start()

func _on_startup_timeout() -> void:
	# Saved space never appeared -- accept current selection
	_startup_selection_done = true

func _on_server_removed(space_id: String) -> void:
	if guild_bar.active_space_id != space_id:
		return
	# Active server was removed -- select a fallback space
	if Client.spaces.size() > 0:
		guild_bar._on_space_pressed(Client.spaces[0]["id"])

func _on_space_selected(space_id: String) -> void:
	channel_list.visible = true
	dm_list.visible = false
	channel_list.load_space(space_id)
	AppState.select_space(space_id)
	Config.set_last_selection(space_id, AppState.current_channel_id)
	# In medium mode, show channel panel when space is selected
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = true
		set_channel_panel_visible(true)

func _on_dm_selected() -> void:
	channel_list.visible = false
	dm_list.visible = true
	AppState.enter_dm_mode()
	# In medium mode, show channel panel when DMs selected
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = true
		set_channel_panel_visible(true)

func _on_channel_selected(channel_id: String) -> void:
	AppState.select_channel(channel_id)
	Config.set_last_selection(AppState.current_space_id, channel_id)
	# In medium mode, hide channel panel after selection
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = false
		set_channel_panel_visible(false)
	# In compact mode, close the drawer
	AppState.close_sidebar_drawer()

func _on_dm_selected_channel(dm_id: String) -> void:
	AppState.select_channel(dm_id)
	# In medium mode, hide channel panel after selection
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = false
		set_channel_panel_visible(false)
	# In compact mode, close the drawer
	AppState.close_sidebar_drawer()

func set_channel_panel_visible(vis: bool) -> void:
	if Config.get_reduced_motion():
		set_channel_panel_visible_immediate(vis)
		return
	if _channel_panel_tween:
		_channel_panel_tween.kill()
	if vis:
		channel_panel.visible = true
		_channel_panel_tween = create_tween()
		_channel_panel_tween.tween_property(
			channel_panel, "custom_minimum_size:x", CHANNEL_PANEL_WIDTH, CHANNEL_PANEL_ANIM_DURATION
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		_channel_panel_tween = create_tween()
		_channel_panel_tween.tween_property(
			channel_panel, "custom_minimum_size:x", 0.0, CHANNEL_PANEL_ANIM_DURATION
		).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_channel_panel_tween.tween_callback(func() -> void: channel_panel.visible = false)

func set_channel_panel_visible_immediate(vis: bool) -> void:
	if _channel_panel_tween:
		_channel_panel_tween.kill()
	channel_panel.visible = vis
	if vis:
		channel_panel.custom_minimum_size.x = CHANNEL_PANEL_WIDTH
	else:
		channel_panel.custom_minimum_size.x = 0.0
