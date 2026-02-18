extends GutTest


# =============================================================================
# AccordSpace
# =============================================================================

func test_space_from_dict_full() -> void:
	var d := {
		"id": "sp1",
		"name": "Test Space",
		"description": "A test space",
		"icon": "icon_hash",
		"banner": "banner_hash",
		"owner_id": "u1",
		"features": ["COMMUNITY"],
		"verification_level": "medium",
		"roles": [{"id": "r1", "name": "everyone"}],
		"emojis": [{"id": "e1", "name": "smile"}],
		"member_count": 42,
		"nsfw_level": "safe",
		"created_at": "2024-01-01T00:00:00Z",
	}
	var s := AccordSpace.from_dict(d)
	assert_eq(s.id, "sp1")
	assert_eq(s.name, "Test Space")
	assert_eq(s.description, "A test space")
	assert_eq(s.owner_id, "u1")
	assert_eq(s.features, ["COMMUNITY"])
	assert_eq(s.roles.size(), 1)
	assert_eq(s.emojis.size(), 1)
	assert_eq(s.member_count, 42)


func test_space_from_dict_minimal() -> void:
	var s := AccordSpace.from_dict({"id": "s1", "name": "minimal"})
	assert_eq(s.id, "s1")
	assert_eq(s.name, "minimal")
	assert_null(s.description)
	assert_null(s.icon)
	assert_eq(s.verification_level, "none")
	assert_eq(s.roles.size(), 0)


func test_space_to_dict_roundtrip() -> void:
	var s := AccordSpace.from_dict({"id": "s2", "name": "rt", "owner_id": "o1"})
	var out := s.to_dict()
	assert_eq(out["id"], "s2")
	assert_eq(out["name"], "rt")
	assert_eq(out["owner_id"], "o1")


func test_space_to_dict_omits_null() -> void:
	var s := AccordSpace.from_dict({"id": "s", "name": "n"})
	var out := s.to_dict()
	assert_false(out.has("description"))
	assert_false(out.has("icon"))
	assert_false(out.has("banner"))
	assert_false(out.has("splash"))
	assert_false(out.has("member_count"))


# =============================================================================
# AccordChannel
# =============================================================================

func test_channel_from_dict_full() -> void:
	var d := {
		"id": "ch1",
		"type": "text",
		"space_id": "sp1",
		"name": "general",
		"topic": "Welcome!",
		"position": 0,
		"nsfw": false,
		"permission_overwrites": [
			{"id": "r1", "type": "role", "allow": ["send_messages"], "deny": []},
		],
		"created_at": "2024-01-01T00:00:00Z",
	}
	var c := AccordChannel.from_dict(d)
	assert_eq(c.id, "ch1")
	assert_eq(c.type, "text")
	assert_eq(c.space_id, "sp1")
	assert_eq(c.name, "general")
	assert_eq(c.topic, "Welcome!")
	assert_eq(c.position, 0)
	assert_eq(c.permission_overwrites.size(), 1)


func test_channel_from_dict_guild_id_alias() -> void:
	var c := AccordChannel.from_dict({"id": "ch", "guild_id": "g1"})
	assert_eq(c.space_id, "g1")


func test_channel_from_dict_minimal() -> void:
	var c := AccordChannel.from_dict({"id": "ch2"})
	assert_eq(c.id, "ch2")
	assert_eq(c.type, "text")
	assert_null(c.space_id)
	assert_null(c.name)
	assert_null(c.topic)


func test_channel_to_dict_omits_null() -> void:
	var c := AccordChannel.from_dict({"id": "ch"})
	var out := c.to_dict()
	assert_false(out.has("space_id"))
	assert_false(out.has("name"))
	assert_false(out.has("topic"))
	assert_false(out.has("position"))


# =============================================================================
# AccordRole
# =============================================================================

func test_role_from_dict_full() -> void:
	var d := {
		"id": "r1",
		"name": "Moderator",
		"color": 0x3498db,
		"hoist": true,
		"icon": "role_icon",
		"position": 2,
		"permissions": ["kick_members", "ban_members"],
		"managed": false,
		"mentionable": true,
	}
	var r := AccordRole.from_dict(d)
	assert_eq(r.id, "r1")
	assert_eq(r.name, "Moderator")
	assert_eq(r.color, 0x3498db)
	assert_true(r.hoist)
	assert_eq(r.position, 2)
	assert_eq(r.permissions.size(), 2)
	assert_true(r.mentionable)


func test_role_from_dict_minimal() -> void:
	var r := AccordRole.from_dict({"id": "r"})
	assert_eq(r.id, "r")
	assert_eq(r.name, "")
	assert_eq(r.color, 0)
	assert_false(r.hoist)
	assert_null(r.icon)


func test_role_to_dict_roundtrip() -> void:
	var r := AccordRole.from_dict({"id": "r1", "name": "Admin", "color": 255})
	var out := r.to_dict()
	assert_eq(out["id"], "r1")
	assert_eq(out["name"], "Admin")
	assert_eq(out["color"], 255)


# =============================================================================
# AccordEmoji
# =============================================================================

func test_emoji_from_dict_full() -> void:
	var d := {
		"id": "e1",
		"name": "smile",
		"animated": true,
		"managed": false,
		"available": true,
		"require_colons": true,
		"role_ids": ["r1", "r2"],
		"creator_id": "u1",
	}
	var e := AccordEmoji.from_dict(d)
	assert_eq(e.id, "e1")
	assert_eq(e.name, "smile")
	assert_true(e.animated)
	assert_eq(e.role_ids.size(), 2)
	assert_eq(e.creator_id, "u1")


func test_emoji_from_dict_null_id() -> void:
	var e := AccordEmoji.from_dict({"name": "unicode_emoji"})
	assert_null(e.id)
	assert_eq(e.name, "unicode_emoji")


func test_emoji_from_dict_roles_alias() -> void:
	var e := AccordEmoji.from_dict({"roles": ["r1"]})
	assert_eq(e.role_ids.size(), 1)


func test_emoji_to_dict_omits_null_id() -> void:
	var e := AccordEmoji.from_dict({"name": "x"})
	var out := e.to_dict()
	assert_false(out.has("id"))
	assert_false(out.has("creator_id"))


# =============================================================================
# AccordPermissionOverwrite
# =============================================================================

func test_permission_overwrite_from_dict() -> void:
	var d := {
		"id": "r1",
		"type": "role",
		"allow": ["send_messages", "read_history"],
		"deny": ["manage_messages"],
	}
	var o := AccordPermissionOverwrite.from_dict(d)
	assert_eq(o.id, "r1")
	assert_eq(o.type, "role")
	assert_eq(o.allow.size(), 2)
	assert_eq(o.deny.size(), 1)


func test_permission_overwrite_to_dict() -> void:
	var o := AccordPermissionOverwrite.from_dict({"id": "m1", "type": "member", "allow": ["speak"], "deny": []})
	var out := o.to_dict()
	assert_eq(out["id"], "m1")
	assert_eq(out["type"], "member")
	assert_eq(out["allow"], ["speak"])
	assert_eq(out["deny"], [])
