extends GutTest

## Tests for ClientGateway event handlers.
##
## Strategy: create a Client node (add_child to get _ready),
## populate caches, then call on_* handlers directly with
## AccordKit model objects built via from_dict().

var client_node: Node
var gw: ClientGateway


func before_each() -> void:
	client_node = load("res://scripts/autoload/client.gd").new()
	# Temporarily clear server count so _ready() won't try to connect
	var saved_count: int = Config._config.get_value("servers", "count", 0)
	Config._config.set_value("servers", "count", 0)
	# Add to tree so timers work (typing tests) -- _ready() fires here
	add_child(client_node)
	Config._config.set_value("servers", "count", saved_count)
	gw = client_node._gw
	# Set up a mock connection
	client_node._connections = [{
		"guild_id": "g_1",
		"cdn_url": "http://cdn",
		"client": null,
		"status": "connected",
		"config": {"base_url": "http://test"},
	}]
	client_node._guild_to_conn = {"g_1": 0}
	client_node.current_user = {"id": "me_1", "display_name": "Me"}
	client_node._user_cache["me_1"] = client_node.current_user
	watch_signals(AppState)


func after_each() -> void:
	# Clean up typing timers
	for key in gw._typing_timers:
		var t = gw._typing_timers[key]
		if is_instance_valid(t):
			t.queue_free()
	gw._typing_timers.clear()
	remove_child(client_node)
	client_node.free()


# ------------------------------------------------------------------
# Helper: build an AccordMessage from a dictionary
# ------------------------------------------------------------------

func _make_message(overrides: Dictionary = {}) -> AccordMessage:
	var d := {
		"id": "m_1",
		"channel_id": "c_1",
		"author_id": "u_author",
		"content": "hello",
		"timestamp": "2025-01-01T00:00:00Z",
		"mentions": [],
		"mention_everyone": false,
		"reactions": [],
		"attachments": [],
		"embeds": [],
	}
	d.merge(overrides, true)
	# Ensure author is in user cache so on_message_create skips fetch
	var author_id: String = d.get("author_id", "u_author")
	if not client_node._user_cache.has(author_id):
		client_node._user_cache[author_id] = {
			"id": author_id, "display_name": "Author",
			"username": "author", "color": Color.WHITE,
			"status": 0, "avatar": null, "is_admin": false,
		}
	return AccordMessage.from_dict(d)


# ------------------------------------------------------------------
# Message operations
# ------------------------------------------------------------------

func test_on_message_create_appends_to_cache() -> void:
	client_node._message_cache["c_1"] = []
	var msg := _make_message()
	gw.on_message_create(msg, 0)
	# Allow the await in on_message_create to complete
	await get_tree().process_frame
	assert_eq(client_node._message_cache["c_1"].size(), 1)
	assert_eq(client_node._message_cache["c_1"][0]["id"], "m_1")


func test_on_message_create_updates_index() -> void:
	client_node._message_cache["c_1"] = []
	var msg := _make_message()
	gw.on_message_create(msg, 0)
	await get_tree().process_frame
	assert_eq(client_node._message_id_index.get("m_1", ""), "c_1")


func test_on_message_create_creates_channel_bucket() -> void:
	# Channel not yet in cache
	var msg := _make_message({"channel_id": "c_new"})
	gw.on_message_create(msg, 0)
	await get_tree().process_frame
	assert_true(client_node._message_cache.has("c_new"))
	assert_eq(client_node._message_cache["c_new"].size(), 1)


func test_on_message_create_enforces_message_cap() -> void:
	client_node._message_cache["c_1"] = []
	# Fill to cap
	for i in Client.MESSAGE_CAP:
		var m := _make_message({"id": "old_%d" % i, "author_id": "u_author"})
		gw.on_message_create(m, 0)
		await get_tree().process_frame
	assert_eq(client_node._message_cache["c_1"].size(), Client.MESSAGE_CAP)
	# Add one more -- should evict the oldest
	var extra := _make_message({"id": "new_one", "author_id": "u_author"})
	gw.on_message_create(extra, 0)
	await get_tree().process_frame
	assert_eq(client_node._message_cache["c_1"].size(), Client.MESSAGE_CAP)
	# Oldest should be evicted from index
	assert_false(client_node._message_id_index.has("old_0"))


func test_on_message_create_marks_unread_other_channel() -> void:
	AppState.current_channel_id = "c_other"
	client_node._channel_cache["c_1"] = {"id": "c_1", "guild_id": "g_1", "unread": false}
	client_node._guild_cache["g_1"] = {"id": "g_1", "unread": false, "mentions": 0}
	var msg := _make_message()
	gw.on_message_create(msg, 0)
	await get_tree().process_frame
	assert_true(client_node._unread_channels.has("c_1"))


func test_on_message_update_replaces_in_place() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "content": "old"},
	]
	var updated := _make_message({"content": "new content"})
	gw.on_message_update(updated, 0)
	assert_eq(client_node._message_cache["c_1"][0]["content"], "new content")


func test_on_message_delete_removes() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "content": "hello"},
		{"id": "m_2", "content": "world"},
	]
	client_node._message_id_index["m_1"] = "c_1"
	gw.on_message_delete({"id": "m_1", "channel_id": "c_1"})
	assert_eq(client_node._message_cache["c_1"].size(), 1)
	assert_eq(client_node._message_cache["c_1"][0]["id"], "m_2")
	assert_false(client_node._message_id_index.has("m_1"))


func test_on_message_delete_bulk() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1"}, {"id": "m_2"}, {"id": "m_3"},
	]
	client_node._message_id_index["m_1"] = "c_1"
	client_node._message_id_index["m_3"] = "c_1"
	gw.on_message_delete_bulk({"channel_id": "c_1", "ids": ["m_1", "m_3"]})
	assert_eq(client_node._message_cache["c_1"].size(), 1)
	assert_eq(client_node._message_cache["c_1"][0]["id"], "m_2")


# ------------------------------------------------------------------
# Typing
# ------------------------------------------------------------------

func test_on_typing_start_emits_signal() -> void:
	client_node._user_cache["u_other"] = {"id": "u_other", "display_name": "Other"}
	gw.on_typing_start({"user_id": "u_other", "channel_id": "c_1"})
	assert_signal_emitted(AppState, "typing_started")


func test_on_typing_start_skips_own_user() -> void:
	gw.on_typing_start({"user_id": "me_1", "channel_id": "c_1"})
	assert_signal_not_emitted(AppState, "typing_started")


# ------------------------------------------------------------------
# Presence / User
# ------------------------------------------------------------------

func test_on_presence_update_updates_user_cache() -> void:
	client_node._user_cache["u_1"] = {"id": "u_1", "status": ClientModels.UserStatus.OFFLINE}
	var presence := AccordPresence.from_dict({
		"user_id": "u_1", "status": "online",
	})
	gw.on_presence_update(presence, 0)
	assert_eq(
		client_node._user_cache["u_1"]["status"],
		ClientModels.UserStatus.ONLINE
	)


func test_on_presence_update_updates_member_cache() -> void:
	client_node._user_cache["u_1"] = {"id": "u_1", "status": ClientModels.UserStatus.OFFLINE}
	client_node._member_cache["g_1"] = [{"id": "u_1", "status": ClientModels.UserStatus.OFFLINE}]
	client_node._rebuild_member_index("g_1")
	var presence := AccordPresence.from_dict({
		"user_id": "u_1", "status": "idle",
	})
	gw.on_presence_update(presence, 0)
	assert_eq(
		client_node._member_cache["g_1"][0]["status"],
		ClientModels.UserStatus.IDLE
	)


func test_on_user_update_updates_cache() -> void:
	client_node._user_cache["u_1"] = {
		"id": "u_1", "display_name": "OldName",
		"status": ClientModels.UserStatus.ONLINE,
	}
	var user := AccordUser.from_dict({
		"id": "u_1", "username": "newname",
		"display_name": "NewName",
	})
	gw.on_user_update(user, 0)
	assert_eq(client_node._user_cache["u_1"]["display_name"], "NewName")


func test_on_user_update_updates_current_user() -> void:
	client_node.current_user = {"id": "me_1", "display_name": "OldMe"}
	client_node._user_cache["me_1"] = client_node.current_user
	var user := AccordUser.from_dict({
		"id": "me_1", "username": "me",
		"display_name": "NewMe",
	})
	gw.on_user_update(user, 0)
	assert_eq(client_node.current_user["display_name"], "NewMe")


# ------------------------------------------------------------------
# Space / Guild
# ------------------------------------------------------------------

func test_on_space_update_preserves_unread() -> void:
	client_node._guild_cache["g_1"] = {
		"id": "g_1", "name": "Old", "unread": true,
		"mentions": 5, "folder": "MyFolder",
	}
	var space := AccordSpace.from_dict({
		"id": "g_1", "name": "NewName", "slug": "new",
	})
	gw.on_space_update(space)
	assert_eq(client_node._guild_cache["g_1"]["name"], "NewName")
	assert_true(client_node._guild_cache["g_1"]["unread"])
	assert_eq(client_node._guild_cache["g_1"]["mentions"], 5)
	assert_eq(client_node._guild_cache["g_1"]["folder"], "MyFolder")


func test_on_space_delete_removes() -> void:
	client_node._guild_cache["g_1"] = {"id": "g_1"}
	gw.on_space_delete({"id": "g_1"})
	assert_false(client_node._guild_cache.has("g_1"))


func test_on_space_create_adds() -> void:
	var space := AccordSpace.from_dict({
		"id": "g_1", "name": "NewGuild", "slug": "new",
	})
	gw.on_space_create(space, 0)
	assert_true(client_node._guild_cache.has("g_1"))


# ------------------------------------------------------------------
# Channel
# ------------------------------------------------------------------

func test_on_channel_create_text() -> void:
	var channel := AccordChannel.from_dict({
		"id": "c_new", "type": "text", "name": "new-channel",
		"space_id": "g_1",
	})
	gw.on_channel_create(channel, 0)
	assert_true(client_node._channel_cache.has("c_new"))
	assert_eq(client_node._channel_to_guild.get("c_new", ""), "g_1")


func test_on_channel_create_dm() -> void:
	var channel := AccordChannel.from_dict({
		"id": "dm_new", "type": "dm", "name": "",
	})
	gw.on_channel_create(channel, 0)
	assert_true(client_node._dm_channel_cache.has("dm_new"))
	assert_false(client_node._channel_cache.has("dm_new"))


func test_on_channel_update_preserves_unread() -> void:
	client_node._channel_cache["c_1"] = {
		"id": "c_1", "guild_id": "g_1", "unread": true, "voice_users": 3,
	}
	var channel := AccordChannel.from_dict({
		"id": "c_1", "type": "text", "name": "updated",
		"space_id": "g_1",
	})
	gw.on_channel_update(channel, 0)
	assert_true(client_node._channel_cache["c_1"]["unread"])
	assert_eq(client_node._channel_cache["c_1"]["voice_users"], 3)


func test_on_channel_delete_text() -> void:
	client_node._channel_cache["c_1"] = {"id": "c_1", "guild_id": "g_1"}
	client_node._channel_to_guild["c_1"] = "g_1"
	var channel := AccordChannel.from_dict({
		"id": "c_1", "type": "text", "space_id": "g_1",
	})
	gw.on_channel_delete(channel)
	assert_false(client_node._channel_cache.has("c_1"))
	assert_false(client_node._channel_to_guild.has("c_1"))


func test_on_channel_delete_dm() -> void:
	client_node._dm_channel_cache["dm_1"] = {"id": "dm_1"}
	var channel := AccordChannel.from_dict({
		"id": "dm_1", "type": "dm",
	})
	gw.on_channel_delete(channel)
	assert_false(client_node._dm_channel_cache.has("dm_1"))


# ------------------------------------------------------------------
# Role
# ------------------------------------------------------------------

func test_on_role_create() -> void:
	client_node._role_cache["g_1"] = []
	gw.on_role_create({"role": {"id": "r_1", "name": "Mod", "permissions": []}}, 0)
	assert_eq(client_node._role_cache["g_1"].size(), 1)
	assert_eq(client_node._role_cache["g_1"][0]["name"], "Mod")


func test_on_role_update() -> void:
	client_node._role_cache["g_1"] = [{"id": "r_1", "name": "Old"}]
	gw.on_role_update({"role": {"id": "r_1", "name": "New", "permissions": []}}, 0)
	assert_eq(client_node._role_cache["g_1"][0]["name"], "New")


func test_on_role_delete() -> void:
	client_node._role_cache["g_1"] = [{"id": "r_1", "name": "Mod"}, {"id": "r_2", "name": "Admin"}]
	gw.on_role_delete({"role_id": "r_1"}, 0)
	assert_eq(client_node._role_cache["g_1"].size(), 1)
	assert_eq(client_node._role_cache["g_1"][0]["id"], "r_2")


# ------------------------------------------------------------------
# Reaction
# ------------------------------------------------------------------

func test_on_reaction_add_new_emoji() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": []},
	]
	gw._reactions.on_reaction_add({
		"channel_id": "c_1", "message_id": "m_1",
		"user_id": "u_other", "emoji": "thumbsup",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions.size(), 1)
	assert_eq(reactions[0]["emoji"], "thumbsup")
	assert_eq(reactions[0]["count"], 1)


func test_on_reaction_add_existing_emoji() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": [{"emoji": "thumbsup", "count": 1, "active": false}]},
	]
	gw._reactions.on_reaction_add({
		"channel_id": "c_1", "message_id": "m_1",
		"user_id": "u_other", "emoji": "thumbsup",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions[0]["count"], 2)


func test_on_reaction_add_marks_active_for_current_user() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": []},
	]
	gw._reactions.on_reaction_add({
		"channel_id": "c_1", "message_id": "m_1",
		"user_id": "me_1", "emoji": "heart",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_true(reactions[0]["active"])


func test_on_reaction_remove_decrements() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": [{"emoji": "thumbsup", "count": 2, "active": false}]},
	]
	gw._reactions.on_reaction_remove({
		"channel_id": "c_1", "message_id": "m_1",
		"user_id": "u_other", "emoji": "thumbsup",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions[0]["count"], 1)


func test_on_reaction_remove_at_zero_removes_entry() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": [{"emoji": "thumbsup", "count": 1, "active": false}]},
	]
	gw._reactions.on_reaction_remove({
		"channel_id": "c_1", "message_id": "m_1",
		"user_id": "u_other", "emoji": "thumbsup",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions.size(), 0)


func test_on_reaction_clear() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": [
			{"emoji": "a", "count": 1, "active": false},
			{"emoji": "b", "count": 2, "active": true},
		]},
	]
	gw._reactions.on_reaction_clear({"channel_id": "c_1", "message_id": "m_1"})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions.size(), 0)


func test_on_reaction_clear_emoji() -> void:
	client_node._message_cache["c_1"] = [
		{"id": "m_1", "reactions": [
			{"emoji": "a", "count": 1, "active": false},
			{"emoji": "b", "count": 2, "active": true},
		]},
	]
	gw._reactions.on_reaction_clear_emoji({
		"channel_id": "c_1", "message_id": "m_1", "emoji": "a",
	})
	var reactions: Array = client_node._message_cache["c_1"][0]["reactions"]
	assert_eq(reactions.size(), 1)
	assert_eq(reactions[0]["emoji"], "b")


# ------------------------------------------------------------------
# Voice state
# ------------------------------------------------------------------

func test_on_voice_state_update_adds_user() -> void:
	client_node._user_cache["u_1"] = {"id": "u_1", "display_name": "User1"}
	var state := AccordVoiceState.from_dict({
		"user_id": "u_1", "channel_id": "vc_1",
		"session_id": "s1",
	})
	gw._events.on_voice_state_update(state, 0)
	assert_true(client_node._voice_state_cache.has("vc_1"))
	assert_eq(client_node._voice_state_cache["vc_1"].size(), 1)


func test_on_voice_state_update_moves_user() -> void:
	client_node._user_cache["u_1"] = {"id": "u_1", "display_name": "User1"}
	# User already in vc_1
	client_node._voice_state_cache["vc_1"] = [{"user_id": "u_1", "channel_id": "vc_1"}]
	var state := AccordVoiceState.from_dict({
		"user_id": "u_1", "channel_id": "vc_2",
		"session_id": "s1",
	})
	gw._events.on_voice_state_update(state, 0)
	assert_eq(client_node._voice_state_cache["vc_1"].size(), 0)
	assert_eq(client_node._voice_state_cache["vc_2"].size(), 1)


# ------------------------------------------------------------------
# Gateway lifecycle
# ------------------------------------------------------------------

func test_on_gateway_reconnected() -> void:
	client_node._connections[0]["status"] = "reconnecting"
	gw.on_gateway_reconnected(0)
	assert_eq(client_node._connections[0]["status"], "connected")
	assert_signal_emitted(AppState, "server_reconnected")


func test_on_gateway_disconnected_non_fatal() -> void:
	gw.on_gateway_disconnected(1000, "normal", 0)
	assert_eq(client_node._connections[0]["status"], "disconnected")
	assert_signal_emitted(AppState, "server_disconnected")
