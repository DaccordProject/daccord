extends GutTest

## Tests for the Client autoload's pure data access, routing,
## permissions, and unread tracking.
##
## Strategy: create a bare Client node via load().new() WITHOUT
## add_child so _ready() never fires (avoids AccordVoiceSession
## and Config dependencies).  Populate internal caches directly.

var client: Node


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	# Manually init the pieces _ready() would create, minus the
	# native AccordVoiceSession that is unavailable in headless.
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.mutations = ClientMutations.new(client)
	client.emoji = ClientEmoji.new(client)
	client.current_user = {"id": "me_1", "display_name": "Me", "is_admin": false}
	client._user_cache["me_1"] = client.current_user


func after_each() -> void:
	client.free()


# ------------------------------------------------------------------
# URL derivation
# ------------------------------------------------------------------

func test_derive_gateway_url_https_to_wss() -> void:
	var url: String = client._derive_gateway_url("https://example.com:39099")
	assert_eq(url, "wss://example.com:39099/ws")


func test_derive_gateway_url_http_to_ws() -> void:
	var url: String = client._derive_gateway_url("http://localhost:39099")
	assert_eq(url, "ws://localhost:39099/ws")


func test_derive_cdn_url() -> void:
	var url: String = client._derive_cdn_url("https://example.com:39099")
	assert_eq(url, "https://example.com:39099/cdn")


# ------------------------------------------------------------------
# Cache getters
# ------------------------------------------------------------------

func test_get_channels_for_guild_returns_matching() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "name": "general"}
	client._channel_cache["c2"] = {"id": "c2", "guild_id": "g1", "name": "random"}
	client._channel_cache["c3"] = {"id": "c3", "guild_id": "g2", "name": "other"}
	var result: Array = client.get_channels_for_guild("g1")
	assert_eq(result.size(), 2)


func test_get_channels_for_guild_no_match() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "name": "general"}
	var result: Array = client.get_channels_for_guild("g_none")
	assert_eq(result.size(), 0)


func test_get_channels_for_guild_empty_cache() -> void:
	var result: Array = client.get_channels_for_guild("g1")
	assert_eq(result.size(), 0)


func test_get_messages_for_channel_hit() -> void:
	client._message_cache["c1"] = [{"id": "m1", "content": "hi"}]
	var result: Array = client.get_messages_for_channel("c1")
	assert_eq(result.size(), 1)
	assert_eq(result[0]["content"], "hi")


func test_get_messages_for_channel_miss() -> void:
	var result: Array = client.get_messages_for_channel("c_none")
	assert_eq(result.size(), 0)


func test_get_user_by_id_hit() -> void:
	client._user_cache["u1"] = {"id": "u1", "display_name": "Alice"}
	var result: Dictionary = client.get_user_by_id("u1")
	assert_eq(result["display_name"], "Alice")


func test_get_user_by_id_miss() -> void:
	var result: Dictionary = client.get_user_by_id("u_none")
	assert_true(result.is_empty())


func test_get_guild_by_id() -> void:
	client._guild_cache["g1"] = {"id": "g1", "name": "TestGuild"}
	var result: Dictionary = client.get_guild_by_id("g1")
	assert_eq(result["name"], "TestGuild")


func test_get_members_for_guild() -> void:
	client._member_cache["g1"] = [{"id": "u1"}, {"id": "u2"}]
	var result: Array = client.get_members_for_guild("g1")
	assert_eq(result.size(), 2)


func test_get_roles_for_guild() -> void:
	client._role_cache["g1"] = [{"id": "r1", "name": "Admin"}]
	var result: Array = client.get_roles_for_guild("g1")
	assert_eq(result.size(), 1)
	assert_eq(result[0]["name"], "Admin")


func test_get_message_by_id_indexed_hit() -> void:
	client._message_cache["c1"] = [
		{"id": "m1", "content": "first"},
		{"id": "m2", "content": "second"},
	]
	client._message_id_index["m2"] = "c1"
	var result: Dictionary = client.get_message_by_id("m2")
	assert_eq(result["content"], "second")


func test_get_message_by_id_fallback_search() -> void:
	# Index points to wrong channel, but linear search finds it
	client._message_cache["c1"] = [{"id": "m1", "content": "found"}]
	client._message_id_index["m1"] = "c_stale"
	var result: Dictionary = client.get_message_by_id("m1")
	assert_eq(result["content"], "found")


func test_get_message_by_id_miss() -> void:
	var result: Dictionary = client.get_message_by_id("m_none")
	assert_true(result.is_empty())


# ------------------------------------------------------------------
# Routing helpers
# ------------------------------------------------------------------

func test_conn_for_guild_valid() -> void:
	var conn := {"guild_id": "g1", "cdn_url": "http://cdn", "client": null, "status": "connected"}
	client._connections = [conn]
	client._guild_to_conn = {"g1": 0}
	var result = client._conn_for_guild("g1")
	assert_eq(result, conn)


func test_conn_for_guild_invalid() -> void:
	client._connections = []
	client._guild_to_conn = {}
	var result = client._conn_for_guild("g_none")
	assert_null(result)


func test_conn_for_guild_out_of_bounds() -> void:
	client._connections = []
	client._guild_to_conn = {"g1": 5}
	var result = client._conn_for_guild("g1")
	assert_null(result)


func test_client_for_guild_returns_null_when_no_conn() -> void:
	client._connections = []
	client._guild_to_conn = {}
	var result: AccordClient = client._client_for_guild("g1")
	assert_null(result)


func test_cdn_for_guild() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "http://cdn.test", "client": null, "status": "connected"}]
	client._guild_to_conn = {"g1": 0}
	var result: String = client._cdn_for_guild("g1")
	assert_eq(result, "http://cdn.test")


func test_cdn_for_channel_via_guild() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "http://cdn.test", "client": null, "status": "connected"}]
	client._guild_to_conn = {"g1": 0}
	client._channel_to_guild = {"c1": "g1"}
	var result: String = client._cdn_for_channel("c1")
	assert_eq(result, "http://cdn.test")


func test_cdn_for_channel_via_dm() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "http://cdn.test", "client": null, "status": "connected"}]
	client._dm_channel_cache["dm1"] = {"id": "dm1"}
	client._dm_to_conn = {"dm1": 0}
	var result: String = client._cdn_for_channel("dm1")
	assert_eq(result, "http://cdn.test")


func test_cdn_for_channel_unknown() -> void:
	var result: String = client._cdn_for_channel("c_unknown")
	assert_eq(result, "")


func test_first_connected_client_returns_null_when_empty() -> void:
	client._connections = []
	var result: AccordClient = client._first_connected_client()
	assert_null(result)


func test_first_connected_cdn_returns_empty_when_none() -> void:
	client._connections = []
	var result: String = client._first_connected_cdn()
	assert_eq(result, "")


func test_first_connected_cdn_skips_error() -> void:
	client._connections = [
		{"guild_id": "g1", "cdn_url": "http://bad", "client": null, "status": "error"},
		{"guild_id": "g2", "cdn_url": "http://good", "client": null, "status": "connected"},
	]
	var result: String = client._first_connected_cdn()
	assert_eq(result, "http://good")


# ------------------------------------------------------------------
# Permission checking
# ------------------------------------------------------------------

func test_has_permission_admin_bypass() -> void:
	client.current_user = {"id": "me_1", "is_admin": true}
	assert_true(client.has_permission("g1", AccordPermission.MANAGE_CHANNELS))


func test_has_permission_owner_bypass() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "me_1"}
	assert_true(client.has_permission("g1", AccordPermission.MANAGE_CHANNELS))


func test_has_permission_role_based_grant() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "other"}
	client._member_cache["g1"] = [{"id": "me_1", "roles": ["r1"]}]
	client._rebuild_member_index("g1")
	client._role_cache["g1"] = [
		{"id": "r1", "position": 1, "permissions": [AccordPermission.MANAGE_CHANNELS]},
	]
	assert_true(client.has_permission("g1", AccordPermission.MANAGE_CHANNELS))


func test_has_permission_role_based_deny() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "other"}
	client._member_cache["g1"] = [{"id": "me_1", "roles": ["r1"]}]
	client._rebuild_member_index("g1")
	client._role_cache["g1"] = [
		{"id": "r1", "position": 1, "permissions": [AccordPermission.SEND_MESSAGES]},
	]
	assert_false(client.has_permission("g1", AccordPermission.MANAGE_CHANNELS))


func test_has_permission_everyone_role() -> void:
	# Position 0 roles apply to everyone regardless of membership
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "other"}
	client._member_cache["g1"] = [{"id": "me_1", "roles": []}]
	client._role_cache["g1"] = [
		{"id": "everyone", "position": 0, "permissions": [AccordPermission.SEND_MESSAGES]},
	]
	assert_true(client.has_permission("g1", AccordPermission.SEND_MESSAGES))


func test_has_permission_no_members() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "other"}
	client._member_cache["g1"] = []
	client._role_cache["g1"] = []
	assert_false(client.has_permission("g1", AccordPermission.MANAGE_CHANNELS))


func test_is_space_owner_match() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "me_1"}
	assert_true(client.is_space_owner("g1"))


func test_is_space_owner_no_match() -> void:
	client._guild_cache["g1"] = {"id": "g1", "owner_id": "someone_else"}
	assert_false(client.is_space_owner("g1"))


# ------------------------------------------------------------------
# Unread tracking
# ------------------------------------------------------------------

func test_mark_channel_unread_channel() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "unread": false}
	client._guild_cache["g1"] = {"id": "g1", "unread": false, "mentions": 0}
	client.mark_channel_unread("c1")
	assert_true(client._unread_channels.has("c1"))
	assert_true(client._channel_cache["c1"]["unread"])


func test_mark_channel_unread_dm() -> void:
	client._dm_channel_cache["dm1"] = {"id": "dm1", "unread": false}
	client.mark_channel_unread("dm1")
	assert_true(client._unread_channels.has("dm1"))
	assert_true(client._dm_channel_cache["dm1"]["unread"])


func test_mark_channel_unread_with_mention() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "unread": false}
	client._guild_cache["g1"] = {"id": "g1", "unread": false, "mentions": 0}
	client.mark_channel_unread("c1", true)
	assert_eq(client._channel_mention_counts.get("c1", 0), 1)
	# Second mention increments
	client.mark_channel_unread("c1", true)
	assert_eq(client._channel_mention_counts.get("c1", 0), 2)


func test_on_channel_selected_clear_unread_channel() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "unread": true}
	client._guild_cache["g1"] = {"id": "g1", "unread": true, "mentions": 1}
	client._unread_channels["c1"] = true
	client._channel_mention_counts["c1"] = 1
	client._on_channel_selected_clear_unread("c1")
	assert_false(client._unread_channels.has("c1"))
	assert_false(client._channel_cache["c1"]["unread"])
	assert_false(client._channel_mention_counts.has("c1"))


func test_on_channel_selected_clear_unread_dm() -> void:
	client._dm_channel_cache["dm1"] = {"id": "dm1", "unread": true}
	client._unread_channels["dm1"] = true
	client._on_channel_selected_clear_unread("dm1")
	assert_false(client._unread_channels.has("dm1"))
	assert_false(client._dm_channel_cache["dm1"]["unread"])


func test_on_channel_selected_clear_unread_noop_not_unread() -> void:
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1", "unread": false}
	# Should be a no-op when channel is not in _unread_channels
	client._on_channel_selected_clear_unread("c1")
	assert_false(client._channel_cache["c1"]["unread"])


func test_update_guild_unread_aggregates() -> void:
	client._guild_cache["g1"] = {"id": "g1", "unread": false, "mentions": 0}
	client._channel_cache["c1"] = {"id": "c1", "guild_id": "g1"}
	client._channel_cache["c2"] = {"id": "c2", "guild_id": "g1"}
	client._unread_channels["c1"] = true
	client._channel_mention_counts["c1"] = 2
	client._channel_mention_counts["c2"] = 3
	client._update_guild_unread("g1")
	assert_true(client._guild_cache["g1"]["unread"])
	assert_eq(client._guild_cache["g1"]["mentions"], 5)


# ------------------------------------------------------------------
# User cache trimming
# ------------------------------------------------------------------

func test_trim_user_cache_below_cap_noop() -> void:
	# Add a few users (well below 500)
	for i in 10:
		client._user_cache["u_%d" % i] = {"id": "u_%d" % i}
	var size_before: int = client._user_cache.size()
	client.trim_user_cache()
	# me_1 + 10 users = 11, well below cap -- nothing evicted
	assert_eq(client._user_cache.size(), size_before)


func test_trim_user_cache_preserves_current_user() -> void:
	# Fill cache above cap
	for i in 510:
		client._user_cache["u_%d" % i] = {"id": "u_%d" % i}
	AppState.current_guild_id = ""
	AppState.current_channel_id = ""
	client.trim_user_cache()
	assert_true(client._user_cache.has("me_1"), "Current user should be preserved")


func test_trim_user_cache_preserves_guild_members() -> void:
	client._member_cache["g1"] = [{"id": "member_1"}, {"id": "member_2"}]
	AppState.current_guild_id = "g1"
	AppState.current_channel_id = ""
	for i in 510:
		client._user_cache["u_%d" % i] = {"id": "u_%d" % i}
	client._user_cache["member_1"] = {"id": "member_1"}
	client._user_cache["member_2"] = {"id": "member_2"}
	client.trim_user_cache()
	assert_true(client._user_cache.has("member_1"), "Guild member should be preserved")
	assert_true(client._user_cache.has("member_2"), "Guild member should be preserved")


# ------------------------------------------------------------------
# Guild folder
# ------------------------------------------------------------------

func test_update_guild_folder() -> void:
	client._guild_cache["g1"] = {"id": "g1", "folder": ""}
	client.update_guild_folder("g1", "MyFolder")
	assert_eq(client._guild_cache["g1"]["folder"], "MyFolder")


func test_update_guild_folder_missing_guild_noop() -> void:
	# Should not crash when guild doesn't exist
	client.update_guild_folder("g_none", "MyFolder")
	assert_false(client._guild_cache.has("g_none"))


# ------------------------------------------------------------------
# Connection state
# ------------------------------------------------------------------

func test_is_server_connected_valid() -> void:
	client._connections = [{"guild_id": "g1", "status": "connected", "client": null}]
	assert_true(client.is_server_connected(0))


func test_is_server_connected_invalid_index() -> void:
	client._connections = []
	assert_false(client.is_server_connected(0))
	assert_false(client.is_server_connected(-1))


func test_is_server_connected_error_status() -> void:
	client._connections = [{"guild_id": "g1", "status": "error", "client": null}]
	assert_false(client.is_server_connected(0))


func test_is_guild_connected() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "", "status": "connected", "client": null}]
	client._guild_to_conn = {"g1": 0}
	assert_true(client.is_guild_connected("g1"))


func test_get_guild_connection_status_connected() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "", "status": "connected", "client": null}]
	client._guild_to_conn = {"g1": 0}
	assert_eq(client.get_guild_connection_status("g1"), "connected")


func test_get_guild_connection_status_none() -> void:
	client._connections = []
	client._guild_to_conn = {}
	assert_eq(client.get_guild_connection_status("g_none"), "none")


func test_get_guild_connection_status_error() -> void:
	client._connections = [{"guild_id": "g1", "cdn_url": "", "status": "error", "client": null}]
	client._guild_to_conn = {"g1": 0}
	assert_eq(client.get_guild_connection_status("g1"), "error")


# ------------------------------------------------------------------
# _find_channel_for_message
# ------------------------------------------------------------------

func test_find_channel_for_message_indexed() -> void:
	client._message_cache["c1"] = [{"id": "m1"}]
	client._message_id_index["m1"] = "c1"
	assert_eq(client._find_channel_for_message("m1"), "c1")


func test_find_channel_for_message_fallback() -> void:
	client._message_cache["c1"] = [{"id": "m1"}]
	# No index entry -- should fall back to linear search
	assert_eq(client._find_channel_for_message("m1"), "c1")


func test_find_channel_for_message_miss() -> void:
	assert_eq(client._find_channel_for_message("m_none"), "")


# ------------------------------------------------------------------
# Data access properties
# ------------------------------------------------------------------

func test_guilds_property_returns_values() -> void:
	client._guild_cache["g1"] = {"id": "g1"}
	client._guild_cache["g2"] = {"id": "g2"}
	assert_eq(client.guilds.size(), 2)


func test_channels_property_returns_values() -> void:
	client._channel_cache["c1"] = {"id": "c1"}
	assert_eq(client.channels.size(), 1)


func test_dm_channels_property_returns_values() -> void:
	client._dm_channel_cache["dm1"] = {"id": "dm1"}
	assert_eq(client.dm_channels.size(), 1)
