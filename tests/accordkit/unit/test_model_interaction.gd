extends GutTest


# =============================================================================
# AccordInteraction
# =============================================================================

func test_interaction_from_dict_full() -> void:
	var d := {
		"id": "i1",
		"application_id": "app1",
		"type": "command",
		"data": {"name": "ping"},
		"space_id": "sp1",
		"channel_id": "ch1",
		"user_id": "u1",
		"token": "interaction_token",
		"locale": "en-US",
	}
	var i := AccordInteraction.from_dict(d)
	assert_eq(i.id, "i1")
	assert_eq(i.application_id, "app1")
	assert_eq(i.type, "command")
	assert_eq(i.data["name"], "ping")
	assert_eq(i.space_id, "sp1")
	assert_eq(i.token, "interaction_token")
	assert_eq(i.locale, "en-US")


func test_interaction_from_dict_member_extraction() -> void:
	var d := {
		"id": "i2",
		"member": {"user": {"id": "mu1", "username": "x"}},
	}
	var i := AccordInteraction.from_dict(d)
	assert_eq(i.member_id, "mu1")


func test_interaction_from_dict_user_extraction() -> void:
	var d := {
		"id": "i3",
		"user": {"id": "uu1", "username": "y"},
	}
	var i := AccordInteraction.from_dict(d)
	assert_eq(i.user_id, "uu1")


func test_interaction_from_dict_minimal() -> void:
	var i := AccordInteraction.from_dict({"id": "i"})
	assert_eq(i.id, "i")
	assert_null(i.data)
	assert_null(i.space_id)
	assert_null(i.member_id)
	assert_null(i.user_id)
	assert_null(i.message)


func test_interaction_to_dict_omits_null() -> void:
	var i := AccordInteraction.from_dict({"id": "i"})
	var out := i.to_dict()
	assert_false(out.has("data"))
	assert_false(out.has("space_id"))
	assert_false(out.has("member_id"))
	assert_false(out.has("user_id"))
	assert_false(out.has("message"))
	assert_false(out.has("locale"))


# =============================================================================
# AccordApplication
# =============================================================================

func test_application_from_dict_full() -> void:
	var d := {
		"id": "app1",
		"name": "MyApp",
		"icon": "app_icon",
		"description": "An app",
		"bot_public": true,
		"owner_id": "u1",
		"flags": 42,
	}
	var a := AccordApplication.from_dict(d)
	assert_eq(a.id, "app1")
	assert_eq(a.name, "MyApp")
	assert_eq(a.icon, "app_icon")
	assert_eq(a.description, "An app")
	assert_true(a.bot_public)
	assert_eq(a.owner_id, "u1")
	assert_eq(a.flags, 42)


func test_application_from_dict_owner_as_dict() -> void:
	var d := {"id": "app", "owner": {"id": "o1", "username": "x"}}
	var a := AccordApplication.from_dict(d)
	assert_eq(a.owner_id, "o1")


func test_application_from_dict_minimal() -> void:
	var a := AccordApplication.from_dict({"id": "a"})
	assert_eq(a.name, "")
	assert_null(a.icon)
	assert_false(a.bot_public)


func test_application_to_dict_omits_null_icon() -> void:
	var a := AccordApplication.from_dict({"id": "a"})
	var out := a.to_dict()
	assert_false(out.has("icon"))


# =============================================================================
# AccordCommand
# =============================================================================

func test_command_from_dict_full() -> void:
	var d := {
		"id": "cmd1",
		"application_id": "app1",
		"space_id": "sp1",
		"name": "ping",
		"description": "Pong!",
		"options": [{"name": "target", "type": "string"}],
		"type": "chat_input",
	}
	var c := AccordCommand.from_dict(d)
	assert_eq(c.id, "cmd1")
	assert_eq(c.name, "ping")
	assert_eq(c.space_id, "sp1")
	assert_eq(c.options.size(), 1)


func test_command_from_dict_guild_id_alias() -> void:
	var c := AccordCommand.from_dict({"id": "c", "guild_id": "g1"})
	assert_eq(c.space_id, "g1")


func test_command_from_dict_minimal() -> void:
	var c := AccordCommand.from_dict({"id": "c"})
	assert_eq(c.name, "")
	assert_null(c.space_id)
	assert_null(c.options)


func test_command_to_dict_omits_null() -> void:
	var c := AccordCommand.from_dict({"id": "c"})
	var out := c.to_dict()
	assert_false(out.has("space_id"))
	assert_false(out.has("options"))


# =============================================================================
# AccordInvite
# =============================================================================

func test_invite_from_dict_full() -> void:
	var d := {
		"code": "abc123",
		"space_id": "sp1",
		"channel_id": "ch1",
		"inviter_id": "u1",
		"max_uses": 10,
		"uses": 3,
		"max_age": 86400,
		"temporary": true,
		"created_at": "2024-01-01T00:00:00Z",
		"expires_at": "2024-01-02T00:00:00Z",
	}
	var i := AccordInvite.from_dict(d)
	assert_eq(i.code, "abc123")
	assert_eq(i.space_id, "sp1")
	assert_eq(i.inviter_id, "u1")
	assert_eq(i.max_uses, 10)
	assert_eq(i.uses, 3)
	assert_true(i.temporary)
	assert_eq(i.expires_at, "2024-01-02T00:00:00Z")


func test_invite_from_dict_inviter_as_dict() -> void:
	var d := {"code": "x", "inviter": {"id": "inv1", "username": "y"}}
	var i := AccordInvite.from_dict(d)
	assert_eq(i.inviter_id, "inv1")


func test_invite_from_dict_minimal() -> void:
	var i := AccordInvite.from_dict({"code": "x"})
	assert_eq(i.code, "x")
	assert_null(i.inviter_id)
	assert_null(i.max_uses)
	assert_null(i.expires_at)


func test_invite_to_dict_omits_null() -> void:
	var i := AccordInvite.from_dict({"code": "x"})
	var out := i.to_dict()
	assert_false(out.has("inviter_id"))
	assert_false(out.has("max_uses"))
	assert_false(out.has("max_age"))
	assert_false(out.has("expires_at"))
