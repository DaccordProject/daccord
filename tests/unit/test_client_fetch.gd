extends GutTest

## Tests for ClientFetch data-fetching methods.
##
## Strategy: create a bare Client node via load().new() WITHOUT add_child
## (to skip _ready), manually init sub-modules, and inject a StubRest into
## AccordClient instances.  The stub returns pre-configured RestResult
## responses keyed by request path, letting the real API layer deserialize
## raw dictionaries into AccordKit models.  Tests then verify that caches
## are populated correctly and AppState signals are emitted.

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
	# Manually init sub-modules (skip _ready to avoid GDExtension deps)
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
	## Registers a connected server with the given AccordClient.
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
# fetch_spaces
# ==================================================================

func test_fetch_spaces_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/spaces"] = RestResult.success(
		200,
		[{
			"id": "g_1",
			"name": "Test Space",
			"owner_id": "u_1",
			"features": [],
		}],
	)
	await fetch_obj.fetch_spaces()
	assert_true(client._space_cache.has("g_1"))
	assert_eq(
		client._space_cache["g_1"]["name"], "Test Space"
	)
	assert_signal_emitted(AppState, "spaces_updated")


func test_fetch_spaces_preserves_unread_and_folder() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._space_cache["g_1"] = {
		"id": "g_1",
		"folder": "My Folder",
		"unread": true,
		"mentions": 3,
	}
	_stub_rest.responses["GET /users/@me/spaces"] = RestResult.success(
		200,
		[{
			"id": "g_1",
			"name": "Test Space",
			"owner_id": "u_1",
			"features": [],
		}],
	)
	await fetch_obj.fetch_spaces()
	var cached: Dictionary = client._space_cache["g_1"]
	assert_eq(cached["folder"], "My Folder")
	assert_true(cached["unread"])
	assert_eq(cached["mentions"], 3)


func test_fetch_spaces_skips_disconnected() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._connections[0]["status"] = "disconnected"
	await fetch_obj.fetch_spaces()
	assert_false(client._space_cache.has("g_1"))
	# Signal still emits (always emits at end)
	assert_signal_emitted(AppState, "spaces_updated")


func test_fetch_spaces_skips_non_matching_space() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/spaces"] = RestResult.success(
		200,
		[{
			"id": "g_other",
			"name": "Other Space",
			"owner_id": "u_1",
			"features": [],
		}],
	)
	await fetch_obj.fetch_spaces()
	assert_false(client._space_cache.has("g_other"))


func test_fetch_spaces_failure_does_not_crash() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/spaces"] = RestResult.failure(
		500, null
	)
	await fetch_obj.fetch_spaces()
	assert_false(client._space_cache.has("g_1"))
	assert_signal_emitted(AppState, "spaces_updated")


# ==================================================================
# fetch_channels
# ==================================================================

func test_fetch_channels_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/channels"] = RestResult.success(
		200,
		[
			{
				"id": "c_1",
				"name": "general",
				"type": "text",
				"space_id": "g_1",
			},
			{
				"id": "c_2",
				"name": "random",
				"type": "text",
				"space_id": "g_1",
			},
		],
	)
	await fetch_obj.fetch_channels("g_1")
	assert_eq(client._channel_cache.size(), 2)
	assert_true(client._channel_cache.has("c_1"))
	assert_eq(
		client._channel_cache["c_1"]["name"], "general"
	)
	assert_eq(client._channel_to_space["c_1"], "g_1")
	assert_signal_emitted_with_parameters(
		AppState, "channels_updated", ["g_1"]
	)


func test_fetch_channels_clears_old_cache_for_space() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	# Pre-populate with an old channel
	client._channel_cache["c_old"] = {
		"id": "c_old", "space_id": "g_1", "name": "old",
	}
	client._channel_to_space["c_old"] = "g_1"
	_stub_rest.responses["GET /spaces/g_1/channels"] = RestResult.success(
		200,
		[{
			"id": "c_new",
			"name": "new",
			"type": "text",
			"space_id": "g_1",
		}],
	)
	await fetch_obj.fetch_channels("g_1")
	assert_false(client._channel_cache.has("c_old"))
	assert_false(client._channel_to_space.has("c_old"))
	assert_true(client._channel_cache.has("c_new"))


func test_fetch_channels_null_client_returns_early() -> void:
	# No connections set up => _client_for_space returns null
	await fetch_obj.fetch_channels("g_nonexistent")
	assert_eq(client._channel_cache.size(), 0)
	assert_signal_not_emitted(AppState, "channels_updated")


func test_fetch_channels_failure_pushes_error() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/channels"] = RestResult.failure(
		500, null
	)
	await fetch_obj.fetch_channels("g_1")
	assert_eq(client._channel_cache.size(), 0)
	assert_signal_not_emitted(AppState, "channels_updated")
	assert_push_error("Failed to fetch channels")


# ==================================================================
# fetch_messages
# ==================================================================

func test_fetch_messages_populates_cache_reversed() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	# Pre-populate author so _fetch_unknown_authors is a no-op
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	# API returns newest-first: m_2, m_1
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_2", "channel_id": "c_1",
				"author_id": "u_1", "content": "second",
				"timestamp": "2025-01-01T00:01:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_1", "content": "first",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_messages("c_1")
	assert_true(client._message_cache.has("c_1"))
	var msgs: Array = client._message_cache["c_1"]
	# Reversed: oldest first
	assert_eq(msgs.size(), 2)
	assert_eq(msgs[0]["content"], "first")
	assert_eq(msgs[1]["content"], "second")
	assert_signal_emitted_with_parameters(
		AppState, "messages_updated", ["c_1"]
	)


func test_fetch_messages_builds_index() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_1", "content": "hi",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_messages("c_1")
	assert_eq(client._message_id_index.get("m_1", ""), "c_1")


func test_fetch_messages_clears_old_index() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	# Pre-populate old messages
	client._message_cache["c_1"] = [{"id": "m_old"}]
	client._message_id_index["m_old"] = "c_1"
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_new", "channel_id": "c_1",
				"author_id": "u_1", "content": "new",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_messages("c_1")
	assert_false(client._message_id_index.has("m_old"))
	assert_true(client._message_id_index.has("m_new"))


func test_fetch_messages_null_client_emits_failure() -> void:
	await fetch_obj.fetch_messages("c_nonexistent")
	assert_signal_emitted(AppState, "message_fetch_failed")


func test_fetch_messages_api_failure_emits_failure() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.failure(500, null)
	await fetch_obj.fetch_messages("c_1")
	assert_signal_emitted(AppState, "message_fetch_failed")
	assert_false(client._message_cache.has("c_1"))
	assert_push_error("Failed to fetch messages")


func test_fetch_messages_fetches_unknown_authors() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	# u_unknown is NOT in user cache
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_unknown", "content": "hi",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	_stub_rest.responses["GET /users/u_unknown"] = RestResult.success(
		200,
		{
			"id": "u_unknown",
			"username": "stranger",
			"display_name": "Stranger",
		},
	)
	await fetch_obj.fetch_messages("c_1")
	assert_true(client._user_cache.has("u_unknown"))
	assert_eq(
		client._user_cache["u_unknown"]["username"], "stranger"
	)


# ==================================================================
# fetch_older_messages
# ==================================================================

func test_fetch_older_prepends_to_existing() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	# Existing messages in cache (oldest-first)
	client._message_cache["c_1"] = [
		{"id": "m_5", "content": "existing"},
	]
	client._message_id_index["m_5"] = "c_1"
	# Stub: older messages (newest-first from API)
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_2", "channel_id": "c_1",
				"author_id": "u_1", "content": "older_b",
				"timestamp": "2025-01-01T00:00:02Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
			{
				"id": "m_1", "channel_id": "c_1",
				"author_id": "u_1", "content": "older_a",
				"timestamp": "2025-01-01T00:00:01Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_older_messages("c_1")
	var msgs: Array = client._message_cache["c_1"]
	# older_a, older_b, existing
	assert_eq(msgs.size(), 3)
	assert_eq(msgs[0]["content"], "older_a")
	assert_eq(msgs[1]["content"], "older_b")
	assert_eq(msgs[2]["content"], "existing")
	assert_signal_emitted(AppState, "messages_updated")


func test_fetch_older_empty_cache_returns_early() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	await fetch_obj.fetch_older_messages("c_1")
	assert_signal_not_emitted(AppState, "messages_updated")


func test_fetch_older_caps_at_max() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	# Fill existing cache to MAX_CHANNEL_MESSAGES - 1
	var max_msgs: int = client.MAX_CHANNEL_MESSAGES
	var existing: Array = []
	for i in range(max_msgs - 1):
		var mid: String = "m_e_%d" % i
		existing.append({"id": mid, "content": "existing_%d" % i})
		client._message_id_index[mid] = "c_1"
	client._message_cache["c_1"] = existing
	# Fetch 5 older messages -> combined would exceed MAX
	var older: Array = []
	for i in range(5):
		older.append({
			"id": "m_old_%d" % i, "channel_id": "c_1",
			"author_id": "u_1",
			"content": "old_%d" % i,
			"timestamp": "2025-01-01T00:00:00Z",
			"mentions": [], "mention_everyone": false,
			"reactions": [], "attachments": [],
			"embeds": [],
		})
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, older)
	await fetch_obj.fetch_older_messages("c_1")
	assert_eq(
		client._message_cache["c_1"].size(), max_msgs
	)


func test_fetch_older_empty_result_still_emits() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._message_cache["c_1"] = [
		{"id": "m_1", "content": "only"},
	]
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [])
	await fetch_obj.fetch_older_messages("c_1")
	assert_signal_emitted(AppState, "messages_updated")


func test_fetch_older_indexes_new_messages() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	client._message_cache["c_1"] = [
		{"id": "m_5", "content": "existing"},
	]
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_old", "channel_id": "c_1",
				"author_id": "u_1", "content": "old",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_older_messages("c_1")
	assert_eq(
		client._message_id_index.get("m_old", ""), "c_1"
	)


# ==================================================================
# fetch_thread_messages
# ==================================================================

func test_fetch_thread_messages_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_reply", "channel_id": "c_1",
				"author_id": "u_1", "content": "reply",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_thread_messages("c_1", "m_parent")
	assert_true(
		client._thread_message_cache.has("m_parent")
	)
	var msgs: Array = \
		client._thread_message_cache["m_parent"]
	assert_eq(msgs.size(), 1)
	assert_eq(msgs[0]["content"], "reply")
	assert_signal_emitted_with_parameters(
		AppState, "thread_messages_updated", ["m_parent"]
	)


func test_fetch_thread_messages_null_client() -> void:
	await fetch_obj.fetch_thread_messages(
		"c_nonexistent", "m_parent"
	)
	assert_false(
		client._thread_message_cache.has("m_parent")
	)


# ==================================================================
# fetch_forum_posts
# ==================================================================

func test_fetch_forum_posts_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_post", "channel_id": "c_1",
				"author_id": "u_1", "content": "forum post",
				"timestamp": "2025-01-01T00:00:00Z",
				"title": "My Post",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_forum_posts("c_1")
	assert_true(client._forum_post_cache.has("c_1"))
	assert_eq(client._forum_post_cache["c_1"].size(), 1)
	assert_signal_emitted_with_parameters(
		AppState, "forum_posts_updated", ["c_1"]
	)


func test_fetch_forum_posts_indexes_messages() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.success(200, [
			{
				"id": "m_post", "channel_id": "c_1",
				"author_id": "u_1", "content": "post",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	await fetch_obj.fetch_forum_posts("c_1")
	assert_eq(
		client._message_id_index.get("m_post", ""), "c_1"
	)


func test_fetch_forum_posts_failure_emits_fetch_failed() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	_stub_rest.responses["GET /channels/c_1/messages"] = \
		RestResult.failure(500, null)
	await fetch_obj.fetch_forum_posts("c_1")
	assert_signal_emitted(AppState, "message_fetch_failed")
	assert_push_error("Failed to fetch forum posts")


# ==================================================================
# fetch_active_threads
# ==================================================================

func test_fetch_active_threads_returns_messages() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	client._user_cache["u_1"] = {
		"id": "u_1", "display_name": "User",
		"username": "user", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	_stub_rest.responses["GET /channels/c_1/threads"] = \
		RestResult.success(200, [
			{
				"id": "m_thread", "channel_id": "c_1",
				"author_id": "u_1", "content": "thread",
				"timestamp": "2025-01-01T00:00:00Z",
				"mentions": [], "mention_everyone": false,
				"reactions": [], "attachments": [],
				"embeds": [],
			},
		])
	var result: Array = \
		await fetch_obj.fetch_active_threads("c_1")
	assert_eq(result.size(), 1)
	assert_eq(result[0]["content"], "thread")


func test_fetch_active_threads_null_client() -> void:
	var result: Array = \
		await fetch_obj.fetch_active_threads("c_nonexistent")
	assert_eq(result.size(), 0)


# ==================================================================
# fetch_members
# ==================================================================

func test_fetch_members_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	# Pre-populate the user that the member references
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
	# u_new is NOT in user cache
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
	# Should not crash
	assert_eq(client.current_user["display_name"], "Me")


func test_refresh_current_user_null_connection() -> void:
	client._connections = [null]
	await fetch_obj.refresh_current_user(0)
	# Should not crash
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
	# Pre-mark dm_1 as unread
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
	# Pre-populate with a preview
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
	# Signal still emits
	assert_signal_emitted(AppState, "dm_channels_updated")


# ==================================================================
# _fetch_unknown_authors (tested indirectly via fetch_messages)
# ==================================================================

func test_unknown_authors_deduplicates() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_1", "g_1")
	# Two messages from the same unknown author
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
	# Should have fetched u_unk only once
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
	# Should NOT have fetched u_known
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
	# resync is fire-and-forget; just verify it doesn't crash
	fetch_obj.resync_voice_states("g_1")
	# Give the async calls a frame to complete
	await get_tree().process_frame
	await get_tree().process_frame
	# Voice channel should have been fetched
	var found := false
	for c in _stub_rest.calls:
		if "/channels/c_voice/voice-status" in c["path"]:
			found = true
	assert_true(found, "voice channel status was fetched")
	# Text channel should NOT have been fetched
	for c in _stub_rest.calls:
		assert_false(
			"/channels/c_text/voice-status" in c["path"]
		)
