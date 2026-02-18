extends GutTest


# =============================================================================
# AccordUser
# =============================================================================

func test_user_from_dict_full() -> void:
	var d := {
		"id": "123456789",
		"username": "testuser",
		"display_name": "Test User",
		"avatar": "abc123",
		"banner": "banner_hash",
		"accent_color": 0xFF0000,
		"bio": "Hello world",
		"bot": true,
		"system": false,
		"flags": 64,
		"public_flags": 32,
		"created_at": "2024-01-15T00:00:00Z",
	}
	var u := AccordUser.from_dict(d)
	assert_eq(u.id, "123456789")
	assert_eq(u.username, "testuser")
	assert_eq(u.display_name, "Test User")
	assert_eq(u.avatar, "abc123")
	assert_eq(u.banner, "banner_hash")
	assert_eq(u.accent_color, 0xFF0000)
	assert_eq(u.bio, "Hello world")
	assert_true(u.bot)
	assert_false(u.system)
	assert_eq(u.flags, 64)
	assert_eq(u.public_flags, 32)
	assert_eq(u.created_at, "2024-01-15T00:00:00Z")


func test_user_from_dict_minimal() -> void:
	var u := AccordUser.from_dict({"id": "1", "username": "min"})
	assert_eq(u.id, "1")
	assert_eq(u.username, "min")
	assert_null(u.display_name)
	assert_null(u.avatar)
	assert_null(u.bio)
	assert_false(u.bot)
	assert_eq(u.flags, 0)


func test_user_to_dict_roundtrip() -> void:
	var d := {
		"id": "99",
		"username": "roundtrip",
		"display_name": "RT",
		"avatar": "av_hash",
		"bot": false,
		"system": false,
		"flags": 0,
		"public_flags": 0,
		"created_at": "2024-06-01T00:00:00Z",
	}
	var u := AccordUser.from_dict(d)
	var out := u.to_dict()
	assert_eq(out["id"], "99")
	assert_eq(out["username"], "roundtrip")
	assert_eq(out["display_name"], "RT")
	assert_eq(out["avatar"], "av_hash")


func test_user_to_dict_omits_null() -> void:
	var u := AccordUser.from_dict({"id": "1", "username": "x"})
	var out := u.to_dict()
	assert_false(out.has("display_name"))
	assert_false(out.has("avatar"))
	assert_false(out.has("banner"))
	assert_false(out.has("accent_color"))
	assert_false(out.has("bio"))


# =============================================================================
# AccordMember
# =============================================================================

func test_member_from_dict_full() -> void:
	var d := {
		"user_id": "u1",
		"space_id": "sp1",
		"nickname": "Nick",
		"avatar": "mem_avatar",
		"roles": ["r1", "r2"],
		"joined_at": "2024-06-01T00:00:00Z",
		"deaf": false,
		"mute": true,
		"pending": true,
	}
	var m := AccordMember.from_dict(d)
	assert_eq(m.user_id, "u1")
	assert_eq(m.space_id, "sp1")
	assert_eq(m.nickname, "Nick")
	assert_eq(m.roles.size(), 2)
	assert_true(m.mute)
	assert_eq(m.pending, true)


func test_member_from_dict_user_as_dict() -> void:
	var d := {"user": {"id": "u42", "username": "x"}, "space_id": "s1"}
	var m := AccordMember.from_dict(d)
	assert_eq(m.user_id, "u42")


func test_member_from_dict_nick_alias() -> void:
	var m := AccordMember.from_dict({"nick": "nickname_alias"})
	assert_eq(m.nickname, "nickname_alias")


func test_member_from_dict_minimal() -> void:
	var m := AccordMember.from_dict({})
	assert_eq(m.user_id, "")
	assert_null(m.nickname)
	assert_eq(m.roles.size(), 0)
	assert_false(m.deaf)


func test_member_to_dict_omits_null() -> void:
	var m := AccordMember.from_dict({"user_id": "u1"})
	var out := m.to_dict()
	assert_false(out.has("nickname"))
	assert_false(out.has("avatar"))
	assert_false(out.has("pending"))


# =============================================================================
# AccordPresence
# =============================================================================

func test_presence_from_dict_full() -> void:
	var d := {
		"user_id": "u1",
		"status": "online",
		"client_status": {"desktop": "online"},
		"activities": [{"name": "Game", "type": "playing"}],
		"space_id": "sp1",
	}
	var p := AccordPresence.from_dict(d)
	assert_eq(p.user_id, "u1")
	assert_eq(p.status, "online")
	assert_eq(p.activities.size(), 1)
	assert_eq(p.space_id, "sp1")


func test_presence_from_dict_user_as_dict() -> void:
	var p := AccordPresence.from_dict({"user": {"id": "u42"}})
	assert_eq(p.user_id, "u42")


func test_presence_from_dict_minimal() -> void:
	var p := AccordPresence.from_dict({})
	assert_eq(p.status, "offline")
	assert_eq(p.activities.size(), 0)
	assert_null(p.space_id)


# =============================================================================
# AccordActivity
# =============================================================================

func test_activity_from_dict_full() -> void:
	var d := {
		"name": "Game",
		"type": "streaming",
		"url": "https://twitch.tv/x",
		"state": "Playing",
		"details": "Level 5",
	}
	var a := AccordActivity.from_dict(d)
	assert_eq(a.name, "Game")
	assert_eq(a.type, "streaming")
	assert_eq(a.url, "https://twitch.tv/x")
	assert_eq(a.state, "Playing")
	assert_eq(a.details, "Level 5")


func test_activity_from_dict_minimal() -> void:
	var a := AccordActivity.from_dict({})
	assert_eq(a.name, "")
	assert_eq(a.type, "playing")
	assert_null(a.url)


func test_activity_to_dict_omits_null() -> void:
	var a := AccordActivity.from_dict({"name": "X"})
	var out := a.to_dict()
	assert_false(out.has("url"))
	assert_false(out.has("state"))
	assert_false(out.has("details"))
