extends HBoxContainer

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

	# Default: select first guild
	if Client.guilds.size() > 0:
		var first_guild_id: String = Client.guilds[0]["id"]
		guild_bar._on_guild_pressed(first_guild_id)

func _on_guild_selected(guild_id: String) -> void:
	channel_list.visible = true
	dm_list.visible = false
	channel_list.load_guild(guild_id)
	AppState.select_guild(guild_id)
	# In medium mode, show channel panel when guild is selected
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = true
		channel_panel.visible = true

func _on_dm_selected() -> void:
	channel_list.visible = false
	dm_list.visible = true
	AppState.enter_dm_mode()
	# In medium mode, show channel panel when DMs selected
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = true
		channel_panel.visible = true

func _on_channel_selected(channel_id: String) -> void:
	AppState.select_channel(channel_id)
	# In medium mode, hide channel panel after selection
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = false
		channel_panel.visible = false
	# In compact mode, close the drawer
	AppState.close_sidebar_drawer()

func _on_dm_selected_channel(dm_id: String) -> void:
	AppState.select_channel(dm_id)
	# In medium mode, hide channel panel after selection
	if AppState.current_layout_mode == AppState.LayoutMode.MEDIUM:
		AppState.channel_panel_visible = false
		channel_panel.visible = false
	# In compact mode, close the drawer
	AppState.close_sidebar_drawer()

func set_channel_panel_visible(vis: bool) -> void:
	channel_panel.visible = vis
