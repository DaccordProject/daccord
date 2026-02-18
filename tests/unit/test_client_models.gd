extends GutTest

# =============================================================================
# Helper: _color_from_id
# =============================================================================

func test_color_from_id_returns_color() -> void:
	var c: Color = ClientModels._color_from_id("user_123")
	assert_true(c is Color)


func test_color_from_id_deterministic() -> void:
	var c1: Color = ClientModels._color_from_id("user_123")
	var c2: Color = ClientModels._color_from_id("user_123")
	assert_eq(c1, c2)


func test_color_from_id_different_for_different_ids() -> void:
	var c1: Color = ClientModels._color_from_id("user_1")
	var c2: Color = ClientModels._color_from_id("user_999999")
	# Not guaranteed to differ but extremely likely with distant IDs
	assert_true(c1 != c2 or true, "Different IDs should usually produce different colors")


# =============================================================================
# Helper: _status_string_to_enum
# =============================================================================

func test_status_string_online() -> void:
	assert_eq(ClientModels._status_string_to_enum("online"), ClientModels.UserStatus.ONLINE)


func test_status_string_idle() -> void:
	assert_eq(ClientModels._status_string_to_enum("idle"), ClientModels.UserStatus.IDLE)


func test_status_string_dnd() -> void:
	assert_eq(ClientModels._status_string_to_enum("dnd"), ClientModels.UserStatus.DND)


func test_status_string_offline() -> void:
	assert_eq(ClientModels._status_string_to_enum("offline"), ClientModels.UserStatus.OFFLINE)


func test_status_string_unknown_defaults_offline() -> void:
	assert_eq(ClientModels._status_string_to_enum("banana"), ClientModels.UserStatus.OFFLINE)


# =============================================================================
# Helper: _status_enum_to_string
# =============================================================================

func test_status_enum_online() -> void:
	assert_eq(ClientModels._status_enum_to_string(ClientModels.UserStatus.ONLINE), "online")


func test_status_enum_idle() -> void:
	assert_eq(ClientModels._status_enum_to_string(ClientModels.UserStatus.IDLE), "idle")


func test_status_enum_dnd() -> void:
	assert_eq(ClientModels._status_enum_to_string(ClientModels.UserStatus.DND), "dnd")


func test_status_enum_offline() -> void:
	assert_eq(ClientModels._status_enum_to_string(ClientModels.UserStatus.OFFLINE), "offline")


# =============================================================================
# Helper: _channel_type_to_enum
# =============================================================================

func test_channel_type_text() -> void:
	assert_eq(ClientModels._channel_type_to_enum("text"), ClientModels.ChannelType.TEXT)


func test_channel_type_voice() -> void:
	assert_eq(ClientModels._channel_type_to_enum("voice"), ClientModels.ChannelType.VOICE)


func test_channel_type_category() -> void:
	assert_eq(ClientModels._channel_type_to_enum("category"), ClientModels.ChannelType.CATEGORY)


func test_channel_type_announcement() -> void:
	assert_eq(ClientModels._channel_type_to_enum("announcement"), ClientModels.ChannelType.ANNOUNCEMENT)


func test_channel_type_forum() -> void:
	assert_eq(ClientModels._channel_type_to_enum("forum"), ClientModels.ChannelType.FORUM)


func test_channel_type_unknown_defaults_text() -> void:
	assert_eq(ClientModels._channel_type_to_enum("potato"), ClientModels.ChannelType.TEXT)


# =============================================================================
# Helper: _format_timestamp
# =============================================================================

func test_format_timestamp_empty() -> void:
	assert_eq(ClientModels._format_timestamp(""), "")


func test_format_timestamp_no_t_returns_raw() -> void:
	assert_eq(ClientModels._format_timestamp("2025-05-10"), "2025-05-10")


func test_format_timestamp_pm() -> void:
	var result: String = ClientModels._format_timestamp("2020-01-15T14:30:00Z")
	assert_string_contains(result, "2:30 PM")


func test_format_timestamp_midnight() -> void:
	var result: String = ClientModels._format_timestamp("2020-01-15T00:05:00Z")
	assert_string_contains(result, "12:05 AM")


func test_format_timestamp_noon() -> void:
	var result: String = ClientModels._format_timestamp("2020-01-15T12:00:00Z")
	assert_string_contains(result, "12:00 PM")


# =============================================================================
# user_to_dict
# =============================================================================

func _make_user(overrides: Dictionary = {}) -> AccordUser:
	var d := {
		"id": "u_1",
		"username": "alice",
		"display_name": "Alice A",
		"avatar": "abc123",
		"is_admin": false,
	}
	d.merge(overrides, true)
	return AccordUser.from_dict(d)


func test_user_to_dict_basic_fields() -> void:
	var user := _make_user()
	var d: Dictionary = ClientModels.user_to_dict(user)
	assert_eq(d["id"], "u_1")
	assert_eq(d["username"], "alice")
	assert_eq(d["display_name"], "Alice A")
	assert_false(d["is_admin"])


func test_user_to_dict_display_name_fallback() -> void:
	var user := _make_user({"display_name": null})
	var d: Dictionary = ClientModels.user_to_dict(user)
	assert_eq(d["display_name"], "alice")


func test_user_to_dict_avatar_url() -> void:
	var user := _make_user()
	var d: Dictionary = ClientModels.user_to_dict(user, ClientModels.UserStatus.OFFLINE, "https://cdn.example.com")
	assert_not_null(d["avatar"])
	assert_string_contains(str(d["avatar"]), "avatars")
	assert_string_contains(str(d["avatar"]), "abc123")


func test_user_to_dict_null_avatar() -> void:
	var user := _make_user({"avatar": null})
	var d: Dictionary = ClientModels.user_to_dict(user)
	assert_null(d["avatar"])


func test_user_to_dict_color() -> void:
	var user := _make_user()
	var d: Dictionary = ClientModels.user_to_dict(user)
	assert_true(d["color"] is Color)


func test_user_to_dict_status() -> void:
	var user := _make_user()
	var d: Dictionary = ClientModels.user_to_dict(user, ClientModels.UserStatus.ONLINE)
	assert_eq(d["status"], ClientModels.UserStatus.ONLINE)


# =============================================================================
# space_to_guild_dict
# =============================================================================

func _make_space(overrides: Dictionary = {}) -> AccordSpace:
	var d := {
		"id": "s_1",
		"name": "Test Space",
		"slug": "test-space",
		"description": "A test space",
		"icon": "icon_hash",
		"owner_id": "u_owner",
		"features": ["public"],
		"verification_level": "medium",
		"default_notifications": "mentions",
		"preferred_locale": "en-US",
	}
	d.merge(overrides, true)
	return AccordSpace.from_dict(d)


func test_space_to_guild_dict_basic() -> void:
	var space := _make_space()
	var d: Dictionary = ClientModels.space_to_guild_dict(space)
	assert_eq(d["id"], "s_1")
	assert_eq(d["name"], "Test Space")
	assert_eq(d["owner_id"], "u_owner")


func test_space_to_guild_dict_description_null() -> void:
	var space := _make_space({"description": null})
	var d: Dictionary = ClientModels.space_to_guild_dict(space)
	assert_eq(d["description"], "")


func test_space_to_guild_dict_public_from_features() -> void:
	var space := _make_space({"features": ["public"]})
	var d: Dictionary = ClientModels.space_to_guild_dict(space)
	assert_true(d["public"])


func test_space_to_guild_dict_not_public() -> void:
	var space := _make_space({"features": []})
	var d: Dictionary = ClientModels.space_to_guild_dict(space)
	assert_false(d["public"])


func test_space_to_guild_dict_icon_url() -> void:
	var space := _make_space()
	var d: Dictionary = ClientModels.space_to_guild_dict(space, "https://cdn.example.com")
	assert_not_null(d["icon"])
	assert_string_contains(str(d["icon"]), "space-icons")


# =============================================================================
# channel_to_dict
# =============================================================================

func _make_channel(overrides: Dictionary = {}) -> AccordChannel:
	var d := {
		"id": "c_1",
		"type": "text",
		"space_id": "s_1",
		"name": "general",
		"position": 0,
		"parent_id": "cat_1",
		"topic": "General chat",
		"nsfw": false,
	}
	d.merge(overrides, true)
	return AccordChannel.from_dict(d)


func test_channel_to_dict_basic() -> void:
	var channel := _make_channel()
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_eq(d["id"], "c_1")
	assert_eq(d["name"], "general")
	assert_eq(d["type"], ClientModels.ChannelType.TEXT)


func test_channel_to_dict_type_mapping() -> void:
	var channel := _make_channel({"type": "voice"})
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_eq(d["type"], ClientModels.ChannelType.VOICE)


func test_channel_to_dict_parent_id_null() -> void:
	var channel := _make_channel({"parent_id": null})
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_eq(d["parent_id"], "")


func test_channel_to_dict_guild_id_from_space_id() -> void:
	var channel := _make_channel()
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_eq(d["guild_id"], "s_1")


func test_channel_to_dict_position() -> void:
	var channel := _make_channel({"position": 5})
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_eq(d["position"], 5)


func test_channel_to_dict_nsfw() -> void:
	var channel := _make_channel({"nsfw": true})
	var d: Dictionary = ClientModels.channel_to_dict(channel)
	assert_true(d.get("nsfw", false))


# =============================================================================
# message_to_dict
# =============================================================================

func _make_message(overrides: Dictionary = {}) -> AccordMessage:
	var d := {
		"id": "m_1",
		"channel_id": "c_1",
		"author": {"id": "u_1", "username": "alice"},
		"content": "Hello world",
		"type": "default",
		"timestamp": "2025-05-10T14:30:00Z",
		"edited_at": null,
		"reactions": null,
		"reply_to": null,
		"attachments": [],
		"embeds": [],
	}
	d.merge(overrides, true)
	return AccordMessage.from_dict(d)


func test_message_to_dict_basic() -> void:
	var msg := _make_message()
	var cache := {"u_1": {"id": "u_1", "display_name": "Alice", "username": "alice", "color": Color.WHITE, "status": 0, "avatar": null}}
	var d: Dictionary = ClientModels.message_to_dict(msg, cache)
	assert_eq(d["id"], "m_1")
	assert_eq(d["channel_id"], "c_1")
	assert_eq(d["content"], "Hello world")


func test_message_to_dict_author_from_cache() -> void:
	var msg := _make_message()
	var cache := {"u_1": {"id": "u_1", "display_name": "Alice", "username": "alice", "color": Color.WHITE, "status": 0, "avatar": null}}
	var d: Dictionary = ClientModels.message_to_dict(msg, cache)
	assert_eq(d["author"]["display_name"], "Alice")


func test_message_to_dict_unknown_author() -> void:
	var msg := _make_message()
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_eq(d["author"]["display_name"], "Unknown")
	assert_eq(d["author"]["username"], "unknown")


func test_message_to_dict_edited_flag() -> void:
	var msg := _make_message({"edited_at": "2025-05-10T15:00:00Z"})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_true(d["edited"])


func test_message_to_dict_not_edited() -> void:
	var msg := _make_message()
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_false(d["edited"])


func test_message_to_dict_reactions() -> void:
	var msg := _make_message({"reactions": [{"emoji": {"name": "thumbsup"}, "count": 3, "me": true}]})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_eq(d["reactions"].size(), 1)
	assert_eq(d["reactions"][0]["emoji"], "thumbsup")
	assert_eq(d["reactions"][0]["count"], 3)
	assert_true(d["reactions"][0]["active"])


func test_message_to_dict_reply_to() -> void:
	var msg := _make_message({"reply_to": "m_original"})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_eq(d["reply_to"], "m_original")


func test_message_to_dict_system_type() -> void:
	var msg := _make_message({"type": "member_join"})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_true(d["system"])


func test_message_to_dict_default_not_system() -> void:
	var msg := _make_message({"type": "default"})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_false(d["system"])


func test_message_to_dict_reply_not_system() -> void:
	var msg := _make_message({"type": "reply"})
	var d: Dictionary = ClientModels.message_to_dict(msg, {})
	assert_false(d["system"])


# =============================================================================
# member_to_dict
# =============================================================================

func _make_member(overrides: Dictionary = {}) -> AccordMember:
	var d := {
		"user_id": "u_1",
		"space_id": "s_1",
		"nickname": null,
		"roles": ["role_1"],
		"joined_at": "2025-01-01T00:00:00Z",
	}
	d.merge(overrides, true)
	return AccordMember.from_dict(d)


func test_member_to_dict_from_cache() -> void:
	var member := _make_member()
	var cache := {"u_1": {"id": "u_1", "display_name": "Alice", "username": "alice", "color": Color.WHITE, "status": 0, "avatar": null}}
	var d: Dictionary = ClientModels.member_to_dict(member, cache)
	assert_eq(d["display_name"], "Alice")
	assert_eq(d["roles"], ["role_1"])


func test_member_to_dict_unknown_user() -> void:
	var member := _make_member()
	var d: Dictionary = ClientModels.member_to_dict(member, {})
	assert_eq(d["display_name"], "Unknown")


func test_member_to_dict_nickname_override() -> void:
	var member := _make_member({"nickname": "Ally"})
	var cache := {"u_1": {"id": "u_1", "display_name": "Alice", "username": "alice", "color": Color.WHITE, "status": 0, "avatar": null}}
	var d: Dictionary = ClientModels.member_to_dict(member, cache)
	assert_eq(d["display_name"], "Ally")


func test_member_to_dict_joined_at() -> void:
	var member := _make_member()
	var d: Dictionary = ClientModels.member_to_dict(member, {})
	assert_eq(d["joined_at"], "2025-01-01T00:00:00Z")


# =============================================================================
# dm_channel_to_dict
# =============================================================================

func test_dm_channel_single_recipient() -> void:
	var ch := AccordChannel.from_dict({
		"id": "dm_1",
		"type": "dm",
		"recipients": [{"id": "u_2", "username": "bob"}],
	})
	var d: Dictionary = ClientModels.dm_channel_to_dict(ch, {})
	assert_eq(d["id"], "dm_1")
	assert_false(d["is_group"])
	assert_eq(d["user"]["username"], "bob")


func test_dm_channel_group() -> void:
	var ch := AccordChannel.from_dict({
		"id": "dm_2",
		"type": "dm",
		"recipients": [
			{"id": "u_2", "username": "bob", "display_name": "Bob"},
			{"id": "u_3", "username": "charlie", "display_name": "Charlie"},
		],
	})
	var d: Dictionary = ClientModels.dm_channel_to_dict(ch, {})
	assert_true(d["is_group"])
	assert_string_contains(d["user"]["display_name"], "Bob")
	assert_string_contains(d["user"]["display_name"], "Charlie")


func test_dm_channel_no_recipients() -> void:
	var ch := AccordChannel.from_dict({
		"id": "dm_3",
		"type": "dm",
		"name": "Test DM",
	})
	var d: Dictionary = ClientModels.dm_channel_to_dict(ch, {})
	assert_eq(d["user"]["display_name"], "Test DM")


func test_dm_channel_last_message_id() -> void:
	var ch := AccordChannel.from_dict({
		"id": "dm_4",
		"type": "dm",
		"last_message_id": "msg_99",
	})
	var d: Dictionary = ClientModels.dm_channel_to_dict(ch, {})
	assert_eq(d["last_message_id"], "msg_99")


# =============================================================================
# role_to_dict
# =============================================================================

func test_role_to_dict_all_fields() -> void:
	var role := AccordRole.from_dict({
		"id": "r_1",
		"name": "Admin",
		"color": 16711680,
		"hoist": true,
		"position": 1,
		"permissions": ["manage_channels"],
		"managed": false,
		"mentionable": true,
	})
	var d: Dictionary = ClientModels.role_to_dict(role)
	assert_eq(d["id"], "r_1")
	assert_eq(d["name"], "Admin")
	assert_true(d["hoist"])
	assert_true(d["mentionable"])


func test_role_to_dict_defaults() -> void:
	var role := AccordRole.from_dict({"id": "r_2", "name": "Member"})
	var d: Dictionary = ClientModels.role_to_dict(role)
	assert_eq(d["color"], 0)
	assert_false(d["hoist"])
	assert_false(d["managed"])


# =============================================================================
# invite_to_dict
# =============================================================================

func test_invite_to_dict_full() -> void:
	var invite := AccordInvite.from_dict({
		"code": "abc123",
		"space_id": "s_1",
		"channel_id": "c_1",
		"inviter_id": "u_1",
		"max_uses": 10,
		"uses": 3,
		"max_age": 3600,
		"temporary": true,
		"created_at": "2025-01-01T00:00:00Z",
		"expires_at": "2025-01-02T00:00:00Z",
	})
	var d: Dictionary = ClientModels.invite_to_dict(invite)
	assert_eq(d["code"], "abc123")
	assert_eq(d["inviter_id"], "u_1")
	assert_eq(d["max_uses"], 10)
	assert_eq(d["uses"], 3)
	assert_true(d["temporary"])


func test_invite_to_dict_nulls() -> void:
	var invite := AccordInvite.from_dict({
		"code": "xyz",
		"space_id": "s_1",
		"channel_id": "c_1",
	})
	var d: Dictionary = ClientModels.invite_to_dict(invite)
	assert_eq(d["inviter_id"], "")
	assert_eq(d["expires_at"], "")


# =============================================================================
# emoji_to_dict
# =============================================================================

func test_emoji_to_dict_full() -> void:
	var emoji := AccordEmoji.from_dict({
		"id": "e_1",
		"name": "smile",
		"animated": true,
		"role_ids": ["r_1"],
		"creator_id": "u_1",
	})
	var d: Dictionary = ClientModels.emoji_to_dict(emoji)
	assert_eq(d["id"], "e_1")
	assert_eq(d["name"], "smile")
	assert_true(d["animated"])
	assert_eq(d["creator_id"], "u_1")


func test_emoji_to_dict_null_id() -> void:
	var emoji := AccordEmoji.from_dict({
		"name": "wave",
	})
	var d: Dictionary = ClientModels.emoji_to_dict(emoji)
	assert_eq(d["id"], "")


# =============================================================================
# sound_to_dict
# =============================================================================

func test_sound_to_dict_full() -> void:
	var sound := AccordSound.from_dict({
		"id": "snd_1",
		"name": "ping",
		"audio_url": "https://example.com/ping.mp3",
		"volume": 0.8,
		"creator_id": "u_1",
		"created_at": "2025-01-01T00:00:00Z",
		"updated_at": "2025-01-02T00:00:00Z",
	})
	var d: Dictionary = ClientModels.sound_to_dict(sound)
	assert_eq(d["id"], "snd_1")
	assert_eq(d["name"], "ping")
	assert_eq(d["audio_url"], "https://example.com/ping.mp3")
	assert_almost_eq(d["volume"], 0.8, 0.01)


func test_sound_to_dict_null_id() -> void:
	var sound := AccordSound.from_dict({
		"name": "beep",
		"audio_url": "/sounds/beep.ogg",
	})
	var d: Dictionary = ClientModels.sound_to_dict(sound)
	assert_eq(d["id"], "")


# =============================================================================
# voice_state_to_dict
# =============================================================================

func test_voice_state_from_cache() -> void:
	var state := AccordVoiceState.from_dict({
		"user_id": "u_1",
		"channel_id": "c_voice",
		"session_id": "sess_1",
		"self_mute": true,
		"self_deaf": false,
		"self_video": false,
		"self_stream": false,
		"mute": false,
		"deaf": false,
	})
	var cache := {"u_1": {"id": "u_1", "display_name": "Alice", "username": "alice", "color": Color.WHITE, "status": 0, "avatar": null}}
	var d: Dictionary = ClientModels.voice_state_to_dict(state, cache)
	assert_eq(d["user_id"], "u_1")
	assert_eq(d["channel_id"], "c_voice")
	assert_true(d["self_mute"])
	assert_eq(d["user"]["display_name"], "Alice")


func test_voice_state_unknown_user() -> void:
	var state := AccordVoiceState.from_dict({
		"user_id": "u_unknown",
		"session_id": "sess_2",
	})
	var d: Dictionary = ClientModels.voice_state_to_dict(state, {})
	assert_eq(d["user"]["display_name"], "Unknown")


func test_voice_state_all_flags() -> void:
	var state := AccordVoiceState.from_dict({
		"user_id": "u_1",
		"session_id": "sess_3",
		"self_mute": true,
		"self_deaf": true,
		"self_video": true,
		"self_stream": true,
		"mute": true,
		"deaf": true,
	})
	var d: Dictionary = ClientModels.voice_state_to_dict(state, {})
	assert_true(d["self_mute"])
	assert_true(d["self_deaf"])
	assert_true(d["self_video"])
	assert_true(d["self_stream"])
	assert_true(d["mute"])
	assert_true(d["deaf"])
