extends GutTest

## Tests for ClientAdmin autoload.
## Covers null-client guard clauses, routing to the correct AccordClient,
## and success-path side effects (cache updates, signal emissions).

var client: Node
var admin: ClientAdmin
var _stub_rest: StubRest
var _accord_clients: Array = []


# ------------------------------------------------------------------
# StubRest -- replaces AccordRest to avoid real HTTP
# ------------------------------------------------------------------

class StubRest extends AccordRest:
	## Maps "METHOD /path" -> RestResult.
	var responses: Dictionary = {}
	## Tracks all calls: array of {"method", "path"} dicts.
	var calls: Array = []

	func make_request(
		method: String, path: String,
		body = null, query: Dictionary = {},
	) -> RestResult:
		calls.append({"method": method, "path": path})
		var key: String = method + " " + path
		if responses.has(key):
			return responses[key]
		return RestResult.failure(404, null)


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func _make_accord_client() -> AccordClient:
	var ac := AccordClient.new()
	_stub_rest = StubRest.new()
	ac.users = UsersApi.new(_stub_rest)
	ac.spaces = SpacesApi.new(_stub_rest)
	ac.channels = ChannelsApi.new(_stub_rest)
	ac.messages = MessagesApi.new(_stub_rest)
	ac.members = MembersApi.new(_stub_rest)
	ac.roles = RolesApi.new(_stub_rest)
	ac.bans = BansApi.new(_stub_rest)
	ac.reports = ReportsApi.new(_stub_rest)
	ac.invites = InvitesApi.new(_stub_rest)
	ac.emojis = EmojisApi.new(_stub_rest)
	ac.soundboard = SoundboardApi.new(_stub_rest)
	ac.voice = VoiceApi.new(_stub_rest)
	ac.audit_logs = AuditLogsApi.new(_stub_rest)
	ac.admin_api = AdminApi.new(_stub_rest)
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
	admin = client.admin
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
# Null-client guard — instance-admin methods
# ==================================================================

func test_create_space_null_client_returns_null() -> void:
	var result: RestResult = await admin.create_space({"name": "x"})
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_list_all_spaces_null_client_returns_null() -> void:
	var result: RestResult = await admin.list_all_spaces()
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_list_all_users_null_client_returns_null() -> void:
	var result: RestResult = await admin.list_all_users()
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_get_server_settings_null_client_returns_null() -> void:
	var result: RestResult = await admin.get_server_settings()
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_update_server_settings_null_client_returns_null() -> void:
	var result: RestResult = await admin.update_server_settings({})
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_admin_delete_user_null_client_returns_null() -> void:
	var result: RestResult = await admin.admin_delete_user("u_1")
	assert_null(result)
	assert_push_error("[Client] No connected server")


func test_reset_user_password_null_client_returns_null() -> void:
	var result: RestResult = await admin.reset_user_password(
		"u_1", "newpass123"
	)
	assert_null(result)
	assert_push_error("[Client] No connected server")


# ==================================================================
# Null-client guard — space-scoped methods
# ==================================================================

func test_update_space_no_connection_returns_null() -> void:
	var result: RestResult = await admin.update_space(
		"g_missing", {}
	)
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_delete_space_no_connection_returns_null() -> void:
	var result: RestResult = await admin.delete_space("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_create_channel_no_connection_returns_null() -> void:
	var result: RestResult = await admin.create_channel(
		"g_missing", {}
	)
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_update_channel_no_connection_returns_null() -> void:
	var result: RestResult = await admin.update_channel(
		"c_missing", {}
	)
	assert_null(result)
	assert_push_error("[Client] No connection for channel:")


func test_delete_channel_no_connection_returns_null() -> void:
	var result: RestResult = await admin.delete_channel("c_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for channel:")


func test_create_role_no_connection_returns_null() -> void:
	var result: RestResult = await admin.create_role("g_missing", {})
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_bans_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_bans("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_ban_member_no_connection_returns_null() -> void:
	var result: RestResult = await admin.ban_member(
		"g_missing", "u_1"
	)
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_invites_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_invites("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_emojis_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_emojis("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_sounds_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_sounds("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_audit_log_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_audit_log("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


func test_get_reports_no_connection_returns_null() -> void:
	var result: RestResult = await admin.get_reports("g_missing")
	assert_null(result)
	assert_push_error("[Client] No connection for space:")


# ==================================================================
# list_all_spaces — routes to first connected client
# ==================================================================

func test_list_all_spaces_routes_to_first_client() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /admin/spaces"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.list_all_spaces()
	assert_not_null(result)
	assert_true(result.ok)


# ==================================================================
# get_server_settings / update_server_settings
# ==================================================================

func test_get_server_settings_routes_correctly() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /admin/settings"] = \
		RestResult.success(200, {})
	var result: RestResult = await admin.get_server_settings()
	assert_not_null(result)
	assert_true(result.ok)


func test_update_server_settings_routes_correctly() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["PATCH /admin/settings"] = \
		RestResult.success(200, {})
	var result: RestResult = await admin.update_server_settings(
		{"key": "value"}
	)
	assert_not_null(result)
	assert_true(result.ok)


# ==================================================================
# ban_member — emits bans_updated + fetches members on success
# ==================================================================

func test_ban_member_success_emits_bans_updated() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["PUT /spaces/g_1/bans/u_bad"] = \
		RestResult.success(200, {})
	_stub_rest.responses["GET /spaces/g_1/members"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.ban_member("g_1", "u_bad")
	assert_not_null(result)
	assert_true(result.ok)
	assert_signal_emitted_with_parameters(
		AppState, "bans_updated", ["g_1"]
	)


func test_ban_member_failure_does_not_emit_signal() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["PUT /spaces/g_1/bans/u_bad"] = \
		RestResult.failure(403, null)
	var result: RestResult = await admin.ban_member("g_1", "u_bad")
	assert_false(result.ok)
	assert_signal_not_emitted(AppState, "bans_updated")


# ==================================================================
# unban_member — emits bans_updated on success
# ==================================================================

func test_unban_member_success_emits_bans_updated() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["DELETE /spaces/g_1/bans/u_bad"] = \
		RestResult.success(204, null)
	var result: RestResult = await admin.unban_member("g_1", "u_bad")
	assert_not_null(result)
	assert_true(result.ok)
	assert_signal_emitted_with_parameters(
		AppState, "bans_updated", ["g_1"]
	)


# ==================================================================
# create_invite — emits invites_updated on success
# ==================================================================

func test_create_invite_success_emits_invites_updated() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["POST /spaces/g_1/invites"] = \
		RestResult.success(201, {
			"code": "abc123", "space_id": "g_1",
		})
	var result: RestResult = await admin.create_invite("g_1")
	assert_not_null(result)
	assert_true(result.ok)
	assert_signal_emitted_with_parameters(
		AppState, "invites_updated", ["g_1"]
	)


func test_create_invite_failure_does_not_emit_signal() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["POST /spaces/g_1/invites"] = \
		RestResult.failure(403, null)
	var result: RestResult = await admin.create_invite("g_1")
	assert_false(result.ok)
	assert_signal_not_emitted(AppState, "invites_updated")


# ==================================================================
# get_invites
# ==================================================================

func test_get_invites_routes_to_correct_space_client() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/invites"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.get_invites("g_1")
	assert_not_null(result)
	assert_true(result.ok)


# ==================================================================
# get_emojis / create_emoji
# ==================================================================

func test_get_emojis_routes_to_correct_space_client() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/emojis"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.get_emojis("g_1")
	assert_not_null(result)
	assert_true(result.ok)


func test_create_emoji_success_emits_emojis_updated() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["POST /spaces/g_1/emojis"] = \
		RestResult.success(201, {
			"id": "e_1", "name": "smile",
		})
	var result: RestResult = await admin.create_emoji(
		"g_1", {"name": "smile", "image": "data:image/png;base64,"}
	)
	assert_not_null(result)
	assert_true(result.ok)
	assert_signal_emitted_with_parameters(
		AppState, "emojis_updated", ["g_1"]
	)


# ==================================================================
# get_bans
# ==================================================================

func test_get_bans_routes_to_correct_space_client() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/bans"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.get_bans("g_1")
	assert_not_null(result)
	assert_true(result.ok)


# ==================================================================
# update_channel_overwrites
# ==================================================================

func test_update_channel_overwrites_null_client_returns_null() -> void:
	# channel not registered -> _client_for_channel returns null
	var result: RestResult = await admin.update_channel_overwrites(
		"c_missing", []
	)
	assert_null(result)
	assert_push_error("[Client] No connection for channel:")


func test_update_channel_overwrites_empty_success() -> void:
	## Empty overwrites/deleted_ids -> returns a synthetic success.
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_setup_channel_routing("c_text", "g_1")
	# Stub channels fetch to prevent push_error from fetch_channels
	_stub_rest.responses["GET /spaces/g_1/channels"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.update_channel_overwrites(
		"c_text", [], []
	)
	assert_not_null(result)
	assert_true(result.ok)


# ==================================================================
# get_audit_log
# ==================================================================

func test_get_audit_log_routes_to_correct_space_client() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /spaces/g_1/audit-log"] = \
		RestResult.success(200, [])
	var result: RestResult = await admin.get_audit_log("g_1")
	assert_not_null(result)
	assert_true(result.ok)
