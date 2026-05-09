extends HBoxContainer

## Single activity session row displayed in the Activities section.

signal join_lobby_pressed(session_data: Dictionary)
signal join_voice_pressed(channel_id: String)

const ACTIVITY_ICON := preload("res://assets/theme/icons/rocket.svg")

var _session_data: Dictionary = {}

@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $Info/NameLabel
@onready var state_badge: Label = $Info/MetaRow/StateBadge
@onready var participant_count: Label = $Info/MetaRow/ParticipantCount
@onready var join_lobby_btn: Button = $Buttons/JoinLobbyBtn
@onready var join_voice_btn: Button = $Buttons/JoinVoiceBtn


func _ready() -> void:
	add_to_group("themed")
	join_lobby_btn.pressed.connect(
		func() -> void: join_lobby_pressed.emit(_session_data)
	)
	join_voice_btn.pressed.connect(
		func() -> void:
			var ch_id: String = _session_data.get("channel_id", "")
			if not ch_id.is_empty():
				join_voice_pressed.emit(ch_id)
	)
	_apply_theme()


func _apply_theme() -> void:
	name_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_primary")
	)
	state_badge.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	participant_count.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	var accent: Color = ThemeManager.get_color("accent")
	ThemeManager.style_button(
		join_lobby_btn, accent, accent.lightened(0.15),
		accent.darkened(0.15), 4, [8, 4, 8, 4]
	)
	join_lobby_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	var success: Color = ThemeManager.get_color("success")
	ThemeManager.style_button(
		join_voice_btn, success, success.lightened(0.15),
		success.darkened(0.15), 4, [8, 4, 8, 4]
	)
	join_voice_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)


func setup(session: Dictionary, manifest: Dictionary) -> void:
	_session_data = session
	var plugin_name: String = manifest.get("name", tr("Unknown Activity"))
	name_label.text = plugin_name
	icon.texture = ACTIVITY_ICON
	icon.modulate = ThemeManager.get_color("icon_default")
	update_state(session, manifest)


func update_state(session: Dictionary, manifest: Dictionary) -> void:
	_session_data = session
	var state: String = session.get("state", "")
	var participants: Array = session.get("participants", [])
	var max_p: int = manifest.get("max_participants", 0)

	# State badge
	if state == "lobby":
		state_badge.text = tr("Lobby")
		state_badge.add_theme_color_override(
			"font_color", ThemeManager.get_color("success")
		)
	elif state == "running":
		state_badge.text = tr("In Progress")
		state_badge.add_theme_color_override(
			"font_color", ThemeManager.get_color("warning")
		)
	else:
		state_badge.text = state.capitalize()

	# Participant count
	if max_p > 0:
		participant_count.text = "%d/%d" % [participants.size(), max_p]
	else:
		participant_count.text = str(participants.size())

	# Join Lobby button state
	var at_capacity: bool = max_p > 0 and participants.size() >= max_p
	join_lobby_btn.disabled = state == "running" or at_capacity
	if join_lobby_btn.disabled:
		var muted: Color = ThemeManager.get_color("text_muted")
		ThemeManager.style_button(
			join_lobby_btn, muted, muted, muted, 4, [8, 4, 8, 4]
		)

	# Join Voice button visibility — show only when host is in voice
	var channel_id: String = session.get("channel_id", "")
	var host_id: String = session.get("host_user_id", "")
	join_voice_btn.visible = _is_host_in_voice(channel_id, host_id)


func update_voice_state() -> void:
	var channel_id: String = _session_data.get("channel_id", "")
	var host_id: String = _session_data.get("host_user_id", "")
	join_voice_btn.visible = _is_host_in_voice(channel_id, host_id)


func get_session_id() -> String:
	return str(_session_data.get("id", ""))


func _is_host_in_voice(channel_id: String, host_id: String) -> bool:
	if channel_id.is_empty() or host_id.is_empty():
		return false
	var voice_users: Array = Client.get_voice_users(channel_id)
	for vs in voice_users:
		if vs.get("user_id", "") == host_id:
			return true
	return false
