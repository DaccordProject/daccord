extends GutTest

## Tests for ClientFetch: members, roles, voice, current user, DMs.
##
## Split from test_client_fetch.gd to stay under 800 lines.
## Uses the same StubRest + setup strategy as the primary file.

var client: Node
var fetch_obj: ClientFetch
var _stub_rest: StubRest
var _accord_clients: Array = []


# ------------------------------------------------------------------
# StubRest -- replaces AccordRest to avoid real HTTP
# ------------------------------------------------------------------

class StubRest extends AccordRest:
	## Maps "METHOD /path" -> RestResult with raw dict/array data.
	var responses: Dictionary = {}
	## Tracks calls made: array of {"method", "path", "query"} dicts.
	var calls: Array = []

	func make_request(
		method: String, path: String,
		body = null, query: Dictionary = {},
	) -> RestResult:
		calls.append({
			"method": method, "path": path, "query": query,
		})
		var key: String = method + " " + path
		if responses.has(key):
			return responses[key]
		return RestResult.failure(404, null)


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func _make_accord_client() -> AccordClient:
	## Creates an AccordClient with StubRest (no tree needed).
	var ac := AccordClient.new()
	_stub_rest = StubRest.new()
	ac.users = UsersApi.new(_stub_rest)
	ac.spaces = SpacesApi.new(_stub_rest)
	ac.messages = MessagesApi.new(_stub_rest)
	ac.members = MembersApi.new(_stub_rest)
	ac.roles = RolesApi.new(_stub_rest)
	ac.voice = VoiceApi.new(_stub_rest)
	_accord_clients.append(ac)
	return ac


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.mutations = ClientMutations.new(client)
	var UnreadClass = load("res://scripts/autoload/client_unread.gd")
	client.unread = UnreadClass.new(client)
	client.emoji = ClientEmoji.new(client)
	var PermClass = load(
		"res://scripts/autoload/client_permissions.gd"
	)
	client.permissions = PermClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["me_1"] = client.current_user
	fetch_obj = client.fetch
	watch_signals(AppState)


func after_each() -> void:
	for ac in _accord_clients:
		if is_instance_valid(ac):
			ac.free()
	_accord_clients.clear()
	if _stub_rest != null and is_instance_valid(_stub_rest):
		_stub_rest.free()
		_stub_rest = null
	client.free()


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _setup_connection(
	ac: AccordClient,
	space_id: String = "g_1",
	cdn_url: String = "http://cdn",
) -> void:
	client._connections = [{
		"space_id": space_id,
		"cdn_url": cdn_url,
		"client": ac,
		"status": "connected",
		"config": {"base_url": "http://test"},
		"user": client.current_user,
		"user_id": "me_1",
	}]
	client._space_to_conn = {space_id: 0}


func _setup_channel_routing(
	channel_id: String, space_id: String,
) -> void:
	client._channel_to_space[channel_id] = space_id


# ==================================================================
# fetch_members
# ==================================================================

func test_fetch_members_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /spaces/g_1/members"] = \
		RestResult.success(200, [
			{
				"user_id": "u_1",
				"space_id": "g_1",
				"roles": [],
				"joined_at": "2025-01-01T00:00:00Z",
			},
		])
	await fetch_obj.fetch_members("g_1")
	assert_true(client._member_cache.has("g_1"))
	assert_eq(client._member_cache["g_1"].size(), 1)
	assert_signal_emitted_with_parameters(
		AppState, "members_updated", ["g_1"]
	)


func test_fetch_members_fetches_missing_users() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/members"] = \
		RestResult.success(200, [
			{
				"user_id": "u_new",
				"space_id": "g_1",
				"roles": [],
				"joined_at": "2025-01-01T00:00:00Z",
			},
		])
	_stub_rest.responses["GET /users/u_new"] = RestResult.success(
		200,
		{
			"id": "u_new",
			"username": "newuser",
			"display_name": "New User",
		},
	)
	await fetch_obj.fetch_members("g_1")
	assert_true(client._user_cache.has("u_new"))


func test_fetch_members_null_client() -> void:
	await fetch_obj.fetch_members("g_nonexistent")
	assert_false(client._member_cache.has("g_nonexistent"))


# ==================================================================
# fetch_roles
# ==================================================================

func test_fetch_roles_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/roles"] = \
		RestResult.success(200, [
			{
				"id": "r_1",
				"name": "Admin",
				"color": 0xFF0000,
				"position": 1,
				"permissions": ["administrator"],
			},
		])
	await fetch_obj.fetch_roles("g_1")
	assert_true(client._role_cache.has("g_1"))
	assert_eq(client._role_cache["g_1"].size(), 1)
	assert_eq(client._role_cache["g_1"][0]["name"], "Admin")
	assert_signal_emitted_with_parameters(
		AppState, "roles_updated", ["g_1"]
	)


func test_fetch_roles_failure_does_not_crash() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/roles"] = \
		RestResult.failure(500, null)
	await fetch_obj.fetch_roles("g_1")
	assert_false(client._role_cache.has("g_1"))
	assert_push_error("Failed to fetch roles")


func test_fetch_roles_null_client() -> void:
	await fetch_obj.fetch_roles("g_nonexistent")
	assert_false(
		client._role_cache.has("g_nonexistent")
	)


# ==================================================================
# fetch_voice_states
# ==================================================================

func test_fetch_voice_states_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_voice", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_voice/voice-status"] = \
		RestResult.success(200, [
			{
				"user_id": "u_1",
				"channel_id": "c_voice",
				"session_id": "sess_1",
				"self_mute": false,
				"self_deaf": false,
			},
		])
	await fetch_obj.fetch_voice_states("c_voice")
	assert_true(
		client._voice_state_cache.has("c_voice")
	)
	assert_eq(
		client._voice_state_cache["c_voice"].size(), 1
	)
	assert_signal_emitted_with_parameters(
		AppState, "voice_state_updated", ["c_voice"]
	)


func test_fetch_voice_states_updates_channel_voice_users() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_voice", "g_1")
	client._channel_cache["c_voice"] = {
		"id": "c_voice", "space_id": "g_1",
		"voice_users": 0,
	}
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_voice/voice-status"] = \
		RestResult.success(200, [
			{
				"user_id": "u_1",
				"channel_id": "c_voice",
				"session_id": "sess_1",
			},
		])
	await fetch_obj.fetch_voice_states("c_voice")
	assert_eq(
		client._channel_cache["c_voice"]["voice_users"], 1
	)


func test_fetch_voice_states_null_client() -> void:
	await fetch_obj.fetch_voice_states("c_nonexistent")
	assert_false(
		client._voice_state_cache.has("c_nonexistent")
	)


# ==================================================================
# refresh_current_user
# ==================================================================

func test_refresh_current_user_updates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me"] = RestResult.success(
		200,
		{
			"id": "me_1",
			"username": "updated_name",
			"display_name": "Updated Me",
		},
	)
	await fetch_obj.refresh_current_user(0)
	assert_eq(
		client._user_cache["me_1"]["username"],
		"updated_name",
	)
	assert_eq(
		client.current_user["username"], "updated_name"
	)
	assert_signal_emitted_with_parameters(
		AppState, "user_updated", ["me_1"]
	)


func test_refresh_current_user_updates_connection() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me"] = RestResult.success(
		200,
		{
			"id": "me_1",
			"username": "new_name",
			"display_name": "New Me",
		},
	)
	await fetch_obj.refresh_current_user(0)
	assert_eq(
		client._connections[0]["user"]["username"], "new_name"
	)
	assert_eq(client._connections[0]["user_id"], "me_1")


func test_refresh_current_user_invalid_index() -> void:
	await fetch_obj.refresh_current_user(99)
	assert_eq(client.current_user["display_name"], "Me")


func test_refresh_current_user_null_connection() -> void:
	client._connections = [null]
	await fetch_obj.refresh_current_user(0)
	assert_eq(client.current_user["display_name"], "Me")


# ==================================================================
# fetch_dm_channels
# ==================================================================

func test_fetch_dm_channels_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/channels"] = \
		RestResult.success(200, [
			{
				"id": "dm_1",
				"type": "dm",
				"recipients": [{
					"id": "u_friend",
					"username": "friend",
					"display_name": "Friend",
				}],
			},
		])
	await fetch_obj.fetch_dm_channels()
	assert_true(client._dm_channel_cache.has("dm_1"))
	assert_eq(client._dm_to_conn.get("dm_1", -1), 0)
	assert_signal_emitted(AppState, "dm_channels_updated")


func test_fetch_dm_channels_preserves_unread() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._dm_channel_cache["dm_1"] = {
		"id": "dm_1", "unread": true,
	}
	_stub_rest.responses["GET /users/@me/channels"] = \
		RestResult.success(200, [
			{
				"id": "dm_1",
				"type": "dm",
				"recipients": [{
					"id": "u_friend",
					"username": "friend",
				}],
			},
		])
	await fetch_obj.fetch_dm_channels()
	assert_true(
		client._dm_channel_cache["dm_1"].get("unread", false)
	)


func test_fetch_dm_channels_preserves_preview() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._dm_channel_cache["dm_1"] = {
		"id": "dm_1",
		"last_message": "hey there",
	}
	_stub_rest.responses["GET /users/@me/channels"] = \
		RestResult.success(200, [
			{
				"id": "dm_1",
				"type": "dm",
				"recipients": [{
					"id": "u_friend",
					"username": "friend",
				}],
			},
		])
	await fetch_obj.fetch_dm_channels()
	assert_eq(
		client._dm_channel_cache["dm_1"].get(
			"last_message", ""
		),
		"hey there",
	)


func test_fetch_dm_channels_caches_recipients() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/channels"] = \
		RestResult.success(200, [
			{
				"id": "dm_1",
				"type": "dm",
				"recipients": [{
					"id": "u_new_friend",
					"username": "new_friend",
					"display_name": "New Friend",
				}],
			},
		])
	await fetch_obj.fetch_dm_channels()
	assert_true(client._user_cache.has("u_new_friend"))


func test_fetch_dm_channels_skips_disconnected() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._connections[0]["status"] = "disconnected"
	await fetch_obj.fetch_dm_channels()
	assert_eq(client._dm_channel_cache.size(), 0)
	assert_signal_emitted(AppState, "dm_channels_updated")


# ==================================================================
# _fetch_unknown_authors (tested indirectly via fetch_messages)
# ==================================================================

func test_unknown_authors_deduplicates() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_unk", "content": "a",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
			{
				"id": "m_2", "channel_id": "c_1",
				"author_id": "u_unk", "content": "b",
				"timestamp": "2025-01-01T00:00:01Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	_stub_rest.responses["GET /users/u_unk"] = RestResult.success(
		200,
		{"id": "u_unk", "username": "unk"},
	)
	await fetch_obj.fetch_messages("c_1")
	var fetch_count := 0
	for c in _stub_rest.calls:
		if c["path"] == "/users/u_unk":
			fetch_count += 1
	assert_eq(fetch_count, 1)


func test_known_authors_not_fetched() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_known"] = {
		"id": "u_known", "display_name": "Known",
		"username": "known", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_known", "content": "hi",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_messages("c_1")
	for c in _stub_rest.calls:
		assert_ne(c["path"], "/users/u_known")


# ==================================================================
# resync_voice_states
# ==================================================================

func test_resync_voice_states_fetches_voice_channels() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_cache["c_text"] = {
		"id": "c_text", "type": ClientModels.ChannelType.TEXT,
	}
	client._channel_cache["c_voice"] = {
		"id": "c_voice",
		"type": ClientModels.ChannelType.VOICE,
		"voice_users": 0,
	}
	client._channel_to_space["c_text"] = "g_1"
	client._channel_to_space["c_voice"] = "g_1"
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_voice/voice-status"] = \
		RestResult.success(200, [
			{
				"user_id": "u_1",
				"channel_id": "c_voice",
				"session_id": "s_1",
			},
		])
	fetch_obj.resync_voice_states("g_1")
	await get_tree().process_frame
	await get_tree().process_frame
	var found := false
	for c in _stub_rest.calls:
		if "/channels/c_voice/voice-status" in c["path"]:
			found = true
	assert_true(found, "voice channel status was fetched")
	for c in _stub_rest.calls:
		assert_false(
			"/channels/c_text/voice-status" in c["path"]
		)
