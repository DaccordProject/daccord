extends Node

signal guild_selected(guild_id: String)
signal channel_selected(channel_id: String)
signal dm_mode_entered()
signal message_sent(text: String)
signal reply_initiated(message_id: String)
signal reply_cancelled()
signal message_edited(message_id: String, new_content: String)
signal message_deleted(message_id: String)
signal layout_mode_changed(mode: LayoutMode)
signal sidebar_drawer_toggled(is_open: bool)
signal guilds_updated()
signal channels_updated(guild_id: String)
signal dm_channels_updated()
signal messages_updated(channel_id: String)
signal user_updated(user_id: String)
signal typing_started(channel_id: String, username: String)
signal typing_stopped(channel_id: String)
signal members_updated(guild_id: String)
signal roles_updated(guild_id: String)
signal bans_updated(guild_id: String)
signal invites_updated(guild_id: String)
signal emojis_updated(guild_id: String)
signal member_list_toggled(is_visible: bool)
signal channel_panel_toggled(is_visible: bool)

enum LayoutMode { COMPACT, MEDIUM, FULL }

var current_guild_id: String = ""
var current_channel_id: String = ""
var is_dm_mode: bool = false
var replying_to_message_id: String = ""
var editing_message_id: String = ""
var current_layout_mode: LayoutMode = LayoutMode.FULL
var sidebar_drawer_open: bool = false
var member_list_visible: bool = true
var channel_panel_visible: bool = true

func select_guild(guild_id: String) -> void:
	current_guild_id = guild_id
	is_dm_mode = false
	guild_selected.emit(guild_id)

func select_channel(channel_id: String) -> void:
	current_channel_id = channel_id
	channel_selected.emit(channel_id)

func enter_dm_mode() -> void:
	is_dm_mode = true
	current_guild_id = ""
	dm_mode_entered.emit()

func send_message(text: String) -> void:
	message_sent.emit(text)

func initiate_reply(message_id: String) -> void:
	replying_to_message_id = message_id
	editing_message_id = ""
	reply_initiated.emit(message_id)

func cancel_reply() -> void:
	replying_to_message_id = ""
	reply_cancelled.emit()

func start_editing(message_id: String) -> void:
	editing_message_id = message_id
	replying_to_message_id = ""

func edit_message(message_id: String, new_content: String) -> void:
	editing_message_id = ""
	message_edited.emit(message_id, new_content)

func delete_message(message_id: String) -> void:
	message_deleted.emit(message_id)

func update_layout_mode(viewport_width: float) -> void:
	var new_mode: LayoutMode
	if viewport_width < 500:
		new_mode = LayoutMode.COMPACT
	elif viewport_width < 768:
		new_mode = LayoutMode.MEDIUM
	else:
		new_mode = LayoutMode.FULL
	if new_mode != current_layout_mode:
		current_layout_mode = new_mode
		layout_mode_changed.emit(new_mode)

func toggle_sidebar_drawer() -> void:
	sidebar_drawer_open = not sidebar_drawer_open
	sidebar_drawer_toggled.emit(sidebar_drawer_open)

func close_sidebar_drawer() -> void:
	if sidebar_drawer_open:
		sidebar_drawer_open = false
		sidebar_drawer_toggled.emit(false)

func toggle_member_list() -> void:
	member_list_visible = not member_list_visible
	member_list_toggled.emit(member_list_visible)

func toggle_channel_panel() -> void:
	channel_panel_visible = not channel_panel_visible
	channel_panel_toggled.emit(channel_panel_visible)
