extends HBoxContainer

const CHANNEL_PANEL_WIDTH: float = 240.0
const CHANNEL_PANEL_ANIM_DURATION: float = 0.15

var _startup_selection_done: bool = false
var _channel_panel_tween: Tween

@onready var guild_bar: PanelContainer = $GuildBar
@onready var channel_panel: VBoxContainer = $ChannelPanel
@onready var channel_list: PanelContainer = $ChannelPanel/ChannelList
@onready var dm_list: PanelContainer = $ChannelPanel/DMList
@onready var user_bar: PanelContainer = $ChannelPanel/UserBar

func _ready() -> void:
	guild_bar.guild_selected.connect(_on_guild_selected)
	guild_bar.dm_selected.connect(_on_dm_selected)
	channel_list.channel_selected.connect(_on_channel_selected)
	dm_list.dm_selected.connect(_on_dm_selected_channel)
	AppState.guilds_updated.connect(_on_guilds_updated)

func _on_guilds_updated() -> void:
	if _startup_selection_done:
		return
	if Client.guilds.size() == 0:
		return
	_startup_selection_done = true

	var saved := Config.get_last_selection()
	var target_guild_id: String = ""
	var target_channel_id: String = saved["channel_id"]

	# Check if saved guild still exists
	if saved["guild_id"] != "":
		for g in Client.guilds:
			if g["id"] == saved["guild_id"]:
				target_guild_id = saved["guild_id"]
				break

	# Fall back to first guild
	if target_guild_id == "":
		target_guild_id = Client.guilds[0]["id"]
		target_channel_id = ""

	channel_list.pending_channel_id = target_channel_id
	guild_bar._on_guild_pressed(target_guild_id)

func _on_guild_selected(guild_id: String) -> void:
	channel_list.visible = true
	dm_list.visible = false
	channel_list.load_guild(guild_id)
	AppState.select_guild(guild_id)
	Config.set_last_selection(guild_id, AppState.current_channel_id)
	# In medium mode, show channel panel when guild is selected
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
	Config.set_last_selection(AppState.current_guild_id, channel_id)
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
