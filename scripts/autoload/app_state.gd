extends Node

signal space_selected(space_id: String)
signal channel_selected(channel_id: String)
signal dm_mode_entered()
signal message_sent(text: String)
signal reply_initiated(message_id: String)
signal reply_cancelled()
signal message_edited(message_id: String, new_content: String)
@warning_ignore("unused_signal")
signal edit_requested(message_id: String)
signal message_deleted(message_id: String)
signal layout_mode_changed(mode: LayoutMode)
signal sidebar_drawer_toggled(is_open: bool)
@warning_ignore("unused_signal")
signal spaces_updated()
@warning_ignore("unused_signal")
signal channels_updated(space_id: String)
@warning_ignore("unused_signal")
signal dm_channels_updated()
@warning_ignore("unused_signal")
signal messages_updated(channel_id: String)
@warning_ignore("unused_signal")
signal user_updated(user_id: String)
@warning_ignore("unused_signal")
signal typing_started(channel_id: String, username: String)
@warning_ignore("unused_signal")
signal typing_stopped(channel_id: String)
@warning_ignore("unused_signal")
signal members_updated(space_id: String)
@warning_ignore("unused_signal")
signal member_joined(space_id: String, member_data: Dictionary)
@warning_ignore("unused_signal")
signal member_left(space_id: String, user_id: String)
@warning_ignore("unused_signal")
signal member_status_changed(space_id: String, user_id: String, new_status: int)
@warning_ignore("unused_signal")
signal roles_updated(space_id: String)
@warning_ignore("unused_signal")
signal bans_updated(space_id: String)
@warning_ignore("unused_signal")
signal invites_updated(space_id: String)
@warning_ignore("unused_signal")
signal emojis_updated(space_id: String)
@warning_ignore("unused_signal")
signal soundboard_updated(space_id: String)
@warning_ignore("unused_signal")
signal soundboard_played(space_id: String, sound_id: String, user_id: String)
@warning_ignore("unused_signal")
signal reactions_updated(channel_id: String, message_id: String)
@warning_ignore("unused_signal")
signal voice_state_updated(channel_id: String)
@warning_ignore("unused_signal")
signal voice_joined(channel_id: String)
@warning_ignore("unused_signal")
signal voice_left(channel_id: String)
@warning_ignore("unused_signal")
signal voice_error(error: String)
@warning_ignore("unused_signal")
signal voice_session_state_changed(state: int)
@warning_ignore("unused_signal")
signal voice_mute_changed(is_muted: bool)
@warning_ignore("unused_signal")
signal voice_deafen_changed(is_deafened: bool)
@warning_ignore("unused_signal")
signal video_enabled_changed(is_enabled: bool)
@warning_ignore("unused_signal")
signal screen_share_changed(is_sharing: bool)
@warning_ignore("unused_signal")
signal remote_track_received(user_id: String, track)
@warning_ignore("unused_signal")
signal remote_track_removed(user_id: String)
@warning_ignore("unused_signal")
signal speaking_changed(user_id: String, is_speaking: bool)
@warning_ignore("unused_signal")
signal profile_card_requested(user_id: String, position: Vector2)
signal member_list_toggled(is_visible: bool)
signal channel_panel_toggled(is_visible: bool)
signal search_toggled(is_open: bool)
@warning_ignore("unused_signal")
signal server_removed(space_id: String)
@warning_ignore("unused_signal")
signal server_disconnected(space_id: String, code: int, reason: String)
@warning_ignore("unused_signal")
signal server_reconnecting(space_id: String, attempt: int, max_attempts: int)
@warning_ignore("unused_signal")
signal server_reconnected(space_id: String)
@warning_ignore("unused_signal")
signal server_synced(space_id: String)
@warning_ignore("unused_signal")
signal server_version_warning(space_id: String, server_version: String, client_version: String)
@warning_ignore("unused_signal")
signal profile_switched()
@warning_ignore("unused_signal")
signal imposter_mode_changed(active: bool)
@warning_ignore("unused_signal")
signal connection_step(step: String)
@warning_ignore("unused_signal")
signal server_connecting(server_name: String, index: int, total: int)
@warning_ignore("unused_signal")
signal server_connection_failed(space_id: String, reason: String)
@warning_ignore("unused_signal")
signal message_send_failed(channel_id: String, content: String, error: String)
@warning_ignore("unused_signal")
signal message_edit_failed(message_id: String, error: String)
@warning_ignore("unused_signal")
signal message_delete_failed(message_id: String, error: String)
@warning_ignore("unused_signal")
signal message_fetch_failed(channel_id: String, error: String)
@warning_ignore("unused_signal")
signal reaction_failed(channel_id: String, message_id: String, emoji: String, error: String)
@warning_ignore("unused_signal")
signal image_lightbox_requested(url: String, texture: ImageTexture)

# Thread signals
@warning_ignore("unused_signal")
signal thread_opened(parent_message_id: String)
@warning_ignore("unused_signal")
signal thread_closed()
@warning_ignore("unused_signal")
signal thread_messages_updated(parent_message_id: String)
@warning_ignore("unused_signal")
signal forum_posts_updated(channel_id: String)

# Auto-update signals
@warning_ignore("unused_signal")
signal update_available(version_info: Dictionary)
@warning_ignore("unused_signal")
signal update_check_complete(version_info: Variant)
@warning_ignore("unused_signal")
signal update_check_failed(error: String)
@warning_ignore("unused_signal")
signal update_download_started()
@warning_ignore("unused_signal")
signal update_download_progress(percent: float)
@warning_ignore("unused_signal")
signal update_download_complete(path: String)
@warning_ignore("unused_signal")
signal update_download_failed(error: String)

# Re-authentication needed (token-only connection with expired token)
@warning_ignore("unused_signal")
signal reauth_needed(server_index: int, base_url: String, username: String)

# Config setting changed (section, key identify what changed)
@warning_ignore("unused_signal")
signal config_changed(section: String, key: String)

enum LayoutMode { COMPACT, MEDIUM, FULL }

const COMPACT_BREAKPOINT: float = 500.0
const MEDIUM_BREAKPOINT: float = 768.0

var current_space_id: String = ""
var current_channel_id: String = ""
var is_dm_mode: bool = false
var replying_to_message_id: String = ""
var editing_message_id: String = ""
var current_layout_mode: LayoutMode = LayoutMode.FULL
var sidebar_drawer_open: bool = false
var member_list_visible: bool = true
var channel_panel_visible: bool = true
var search_open: bool = false
var voice_channel_id: String = ""
var voice_space_id: String = ""
var is_voice_muted: bool = false
var is_voice_deafened: bool = false
var is_video_enabled: bool = false
var is_screen_sharing: bool = false
var pending_attachments: Array = []
var current_thread_id: String = ""
var thread_panel_visible: bool = false
var is_imposter_mode: bool = false
var imposter_permissions: Array = []
var imposter_role_name: String = ""
var imposter_space_id: String = ""

func select_space(space_id: String) -> void:
	if is_imposter_mode and space_id != imposter_space_id:
		exit_imposter_mode()
	current_space_id = space_id
	is_dm_mode = false
	space_selected.emit(space_id)

func select_channel(channel_id: String) -> void:
	current_channel_id = channel_id
	channel_selected.emit(channel_id)

func enter_dm_mode() -> void:
	if is_imposter_mode:
		exit_imposter_mode()
	is_dm_mode = true
	current_space_id = ""
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

func update_layout_mode(viewport_width: float, _viewport_height: float = 0.0) -> void:
	var new_mode: LayoutMode
	if viewport_width < COMPACT_BREAKPOINT:
		new_mode = LayoutMode.COMPACT
	elif viewport_width < MEDIUM_BREAKPOINT:
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

func toggle_search() -> void:
	search_open = not search_open
	search_toggled.emit(search_open)

func close_search() -> void:
	if search_open:
		search_open = false
		search_toggled.emit(false)

func join_voice(channel_id: String, space_id: String) -> void:
	voice_channel_id = channel_id
	voice_space_id = space_id
	voice_joined.emit(channel_id)

func leave_voice() -> void:
	var old_channel := voice_channel_id
	voice_channel_id = ""
	voice_space_id = ""
	is_voice_muted = false
	is_voice_deafened = false
	is_video_enabled = false
	is_screen_sharing = false
	if not old_channel.is_empty():
		voice_left.emit(old_channel)

func set_voice_muted(muted: bool) -> void:
	is_voice_muted = muted
	voice_mute_changed.emit(muted)

func set_voice_deafened(deafened: bool) -> void:
	is_voice_deafened = deafened
	voice_deafen_changed.emit(deafened)

func set_video_enabled(enabled: bool) -> void:
	is_video_enabled = enabled
	video_enabled_changed.emit(enabled)

func set_screen_sharing(sharing: bool) -> void:
	is_screen_sharing = sharing
	screen_share_changed.emit(sharing)

func open_thread(parent_message_id: String) -> void:
	current_thread_id = parent_message_id
	thread_panel_visible = true
	thread_opened.emit(parent_message_id)

func close_thread() -> void:
	current_thread_id = ""
	thread_panel_visible = false
	thread_closed.emit()

func enter_imposter_mode(role_data: Dictionary) -> void:
	is_imposter_mode = true
	imposter_permissions = role_data.get("permissions", [])
	imposter_role_name = role_data.get("name", "Unknown")
	imposter_space_id = role_data.get("space_id", current_space_id)
	imposter_mode_changed.emit(true)

func exit_imposter_mode() -> void:
	if not is_imposter_mode:
		return
	is_imposter_mode = false
	imposter_permissions = []
	imposter_role_name = ""
	imposter_space_id = ""
	imposter_mode_changed.emit(false)
