extends GutTest

## Tests for ClientPermissions — has_permission() and has_channel_permission().
##
## Strategy: instantiate a bare Client via load().new() (skipping _ready),
## manually init sub-modules, then inject synthetic _space_cache,
## _role_cache, _member_cache, _member_id_index, and _channel_cache.
## Call client.permissions.has_channel_permission() and has_permission()
## directly and assert expected outcomes.

var client: Node
var perm: RefCounted  # ClientPermissions instance


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.mutations = ClientMutations.new(client)
	var UnreadClass = load("res://scripts/autoload/client_unread.gd")
	client.unread = UnreadClass.new(client)
	client.emoji = ClientEmoji.new(client)
	var PermClass = load("res://scripts/autoload/client_permissions.gd")
	client.permissions = PermClass.new(client)
	var RelClass = load("res://scripts/autoload/client_relationships.gd")
	client.relationships = RelClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["me_1"] = client.current_user
	perm = client.permissions
	# Disable imposter mode for all tests by default
	AppState.is_imposter_mode = false
	AppState.imposter_space_id = ""
	AppState.imposter_permissions = []


func after_each() -> void:
	client.free()
	AppState.is_imposter_mode = false
	AppState.imposter_space_id = ""
	AppState.imposter_permissions = []
	AppState.imposter_role_id = ""


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _setup_space(space_id: String, owner_id: String = "") -> void:
	client._space_cache[space_id] = {
		"id": space_id,
		"name": "Test Space",
		"owner_id": owner_id,
	}


func _setup_member(space_id: String, user_id: String, roles: Array) -> void:
	var members: Array = client._member_cache.get(space_id, [])
	members.append({"id": user_id, "roles": roles})
	client._member_cache[space_id] = members
	# Update index
	var index: Dictionary = client._member_id_index.get(space_id, {})
	index[user_id] = members.size() - 1
	client._member_id_index[space_id] = index


func _setup_role(
	space_id: String,
	role_id: String,
	permissions: Array,
	position: int = 1,
) -> void:
	var roles: Array = client._role_cache.get(space_id, [])
	roles.append({
		"id": role_id,
		"permissions": permissions,
		"position": position,
	})
	client._role_cache[space_id] = roles


func _setup_everyone_role(space_id: String, permissions: Array) -> void:
	## @everyone role has position == 0
	_setup_role(space_id, "everyone_" + space_id, permissions, 0)


func _setup_channel(
	channel_id: String,
	space_id: String,
	overwrites: Array = [],
) -> void:
	client._channel_cache[channel_id] = {
		"id": channel_id,
		"space_id": space_id,
		"permission_overwrites": overwrites,
	}
	client._channel_to_space[channel_id] = space_id


# ==================================================================
# has_permission — space-level checks
# ==================================================================

func test_has_permission_admin_bypasses_all() -> void:
	client.current_user["is_admin"] = true
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])  # no perms
	assert_true(perm.has_permission("g_1", AccordPermission.SEND_MESSAGES))


func test_has_permission_owner_bypasses_all() -> void:
	_setup_space("g_1", "me_1")
	_setup_everyone_role("g_1", [])
	assert_true(perm.has_permission("g_1", AccordPermission.SEND_MESSAGES))


func test_has_permission_everyone_role_grants() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [AccordPermission.SEND_MESSAGES])
	assert_true(perm.has_permission("g_1", AccordPermission.SEND_MESSAGES))


func test_has_permission_assigned_role_grants() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	_setup_role("g_1", "role_mod", [AccordPermission.KICK_MEMBERS], 1)
	_setup_member("g_1", "me_1", ["role_mod"])
	assert_true(perm.has_permission("g_1", AccordPermission.KICK_MEMBERS))


func test_has_permission_unassigned_role_does_not_grant() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	_setup_role("g_1", "role_mod", [AccordPermission.KICK_MEMBERS], 1)
	_setup_member("g_1", "me_1", [])  # user has no roles
	assert_false(perm.has_permission("g_1", AccordPermission.KICK_MEMBERS))


func test_has_permission_imposter_mode_uses_injected_perms() -> void:
	AppState.is_imposter_mode = true
	AppState.imposter_space_id = "g_1"
	AppState.imposter_permissions = [AccordPermission.BAN_MEMBERS]
	_setup_space("g_1")
	assert_true(perm.has_permission("g_1", AccordPermission.BAN_MEMBERS))
	assert_false(perm.has_permission("g_1", AccordPermission.KICK_MEMBERS))


func test_has_permission_no_roles_returns_false() -> void:
	_setup_space("g_1")
	assert_false(perm.has_permission("g_1", AccordPermission.SEND_MESSAGES))


# ==================================================================
# has_channel_permission — basic cases
# ==================================================================

func test_hcp_admin_bypasses() -> void:
	client.current_user["is_admin"] = true
	_setup_space("g_1")
	_setup_channel("c_1", "g_1")
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.VIEW_CHANNEL)
	)


func test_hcp_owner_bypasses() -> void:
	_setup_space("g_1", "me_1")
	_setup_channel("c_1", "g_1")
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


func test_hcp_imposter_mode() -> void:
	AppState.is_imposter_mode = true
	AppState.imposter_space_id = "g_1"
	AppState.imposter_permissions = [AccordPermission.VIEW_CHANNEL]
	_setup_space("g_1")
	_setup_channel("c_1", "g_1")
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.VIEW_CHANNEL)
	)
	assert_false(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.KICK_MEMBERS)
	)


func test_hcp_no_overwrites_falls_back_to_base() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [AccordPermission.SEND_MESSAGES])
	_setup_channel("c_1", "g_1", [])  # no overwrites
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


func test_hcp_no_overwrites_denies_missing_perm() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [AccordPermission.VIEW_CHANNEL])
	_setup_channel("c_1", "g_1", [])
	assert_false(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.KICK_MEMBERS)
	)


# ==================================================================
# has_channel_permission — @everyone overwrite
# ==================================================================

func test_hcp_everyone_overwrite_deny_removes_perm() -> void:
	_setup_space("g_1")
	# @everyone grants send_messages at space level
	_setup_everyone_role("g_1", [AccordPermission.SEND_MESSAGES])
	# Channel overwrite for @everyone denies it
	_setup_channel("c_1", "g_1", [{
		"id": "everyone_g_1",
		"type": "role",
		"deny": [AccordPermission.SEND_MESSAGES],
		"allow": [],
	}])
	assert_false(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


func test_hcp_everyone_overwrite_allow_grants_perm() -> void:
	_setup_space("g_1")
	# @everyone has no perms at space level
	_setup_everyone_role("g_1", [])
	# Channel overwrite for @everyone allows view_channel
	_setup_channel("c_1", "g_1", [{
		"id": "everyone_g_1",
		"type": "role",
		"deny": [],
		"allow": [AccordPermission.VIEW_CHANNEL],
	}])
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.VIEW_CHANNEL)
	)


# ==================================================================
# has_channel_permission — role overwrites
# ==================================================================

func test_hcp_role_allow_overwrite_grants_perm() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	_setup_role("g_1", "role_read", [], 1)
	_setup_member("g_1", "me_1", ["role_read"])
	# Channel grants view_channel via role overwrite
	_setup_channel("c_1", "g_1", [{
		"id": "role_read",
		"type": "role",
		"allow": [AccordPermission.VIEW_CHANNEL],
		"deny": [],
	}])
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.VIEW_CHANNEL)
	)


func test_hcp_role_deny_overwrite_blocks_perm() -> void:
	_setup_space("g_1")
	# @everyone grants send_messages
	_setup_everyone_role("g_1", [AccordPermission.SEND_MESSAGES])
	_setup_role("g_1", "role_readonly", [], 1)
	_setup_member("g_1", "me_1", ["role_readonly"])
	# Channel denies send_messages for this role
	_setup_channel("c_1", "g_1", [{
		"id": "role_readonly",
		"type": "role",
		"allow": [],
		"deny": [AccordPermission.SEND_MESSAGES],
	}])
	assert_false(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


func test_hcp_role_allow_wins_over_role_deny() -> void:
	## When two roles conflict (one allow, one deny), allow wins.
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	_setup_role("g_1", "role_a", [], 1)
	_setup_role("g_1", "role_b", [], 2)
	_setup_member("g_1", "me_1", ["role_a", "role_b"])
	_setup_channel("c_1", "g_1", [
		{
			"id": "role_a",
			"type": "role",
			"allow": [AccordPermission.SEND_MESSAGES],
			"deny": [],
		},
		{
			"id": "role_b",
			"type": "role",
			"allow": [],
			"deny": [AccordPermission.SEND_MESSAGES],
		},
	])
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


# ==================================================================
# has_channel_permission — user-specific overwrite
# ==================================================================

func test_hcp_user_allow_overwrite_grants_perm() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])  # no base perms
	_setup_channel("c_1", "g_1", [{
		"id": "me_1",
		"type": "user",
		"allow": [AccordPermission.SEND_MESSAGES],
		"deny": [],
	}])
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


func test_hcp_user_deny_overwrite_blocks_perm() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [AccordPermission.SEND_MESSAGES])
	_setup_channel("c_1", "g_1", [{
		"id": "me_1",
		"type": "user",
		"allow": [],
		"deny": [AccordPermission.SEND_MESSAGES],
	}])
	assert_false(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


# ==================================================================
# has_channel_permission — ADMINISTRATOR base perm bypass
# ==================================================================

func test_hcp_administrator_in_base_perms_bypasses_overwrites() -> void:
	_setup_space("g_1")
	# @everyone role grants ADMINISTRATOR
	_setup_everyone_role("g_1", [AccordPermission.ADMINISTRATOR])
	# Channel overwrite tries to deny — should be ignored
	_setup_channel("c_1", "g_1", [{
		"id": "everyone_g_1",
		"type": "role",
		"deny": [AccordPermission.SEND_MESSAGES],
		"allow": [],
	}])
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.SEND_MESSAGES)
	)


# ==================================================================
# has_channel_permission — no members case
# ==================================================================

func test_hcp_no_member_entry_uses_everyone_only() -> void:
	_setup_space("g_1")
	_setup_everyone_role("g_1", [AccordPermission.VIEW_CHANNEL])
	_setup_channel("c_1", "g_1", [])
	# me_1 is not in member_cache — should still get everyone perms
	assert_true(
		perm.has_channel_permission("g_1", "c_1", AccordPermission.VIEW_CHANNEL)
	)


# ==================================================================
# has_channel_permission — imposter mode with channel overwrites
# ==================================================================

func test_hcp_imposter_everyone_overwrite_denies() -> void:
	AppState.is_imposter_mode = true
	AppState.imposter_space_id = "g_1"
	AppState.imposter_permissions = [
		AccordPermission.VIEW_CHANNEL,
		AccordPermission.SEND_MESSAGES,
	]
	AppState.imposter_role_id = "role_mod"
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	# Channel denies SEND_MESSAGES for @everyone
	_setup_channel("c_1", "g_1", [{
		"id": "everyone_g_1",
		"type": "role",
		"deny": [AccordPermission.SEND_MESSAGES],
		"allow": [],
	}])
	assert_false(
		perm.has_channel_permission(
			"g_1", "c_1", AccordPermission.SEND_MESSAGES
		)
	)
	assert_true(
		perm.has_channel_permission(
			"g_1", "c_1", AccordPermission.VIEW_CHANNEL
		)
	)


func test_hcp_imposter_role_overwrite_allows() -> void:
	AppState.is_imposter_mode = true
	AppState.imposter_space_id = "g_1"
	AppState.imposter_permissions = [AccordPermission.VIEW_CHANNEL]
	AppState.imposter_role_id = "role_mod"
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	# Channel allows SEND_MESSAGES for the imposter role
	_setup_channel("c_1", "g_1", [{
		"id": "role_mod",
		"type": "role",
		"allow": [AccordPermission.SEND_MESSAGES],
		"deny": [],
	}])
	assert_true(
		perm.has_channel_permission(
			"g_1", "c_1", AccordPermission.SEND_MESSAGES
		)
	)


func test_hcp_imposter_admin_perm_bypasses_overwrites() -> void:
	AppState.is_imposter_mode = true
	AppState.imposter_space_id = "g_1"
	AppState.imposter_permissions = [AccordPermission.ADMINISTRATOR]
	AppState.imposter_role_id = ""
	_setup_space("g_1")
	_setup_everyone_role("g_1", [])
	_setup_channel("c_1", "g_1", [{
		"id": "everyone_g_1",
		"type": "role",
		"deny": [AccordPermission.SEND_MESSAGES],
		"allow": [],
	}])
	assert_true(
		perm.has_channel_permission(
			"g_1", "c_1", AccordPermission.SEND_MESSAGES
		)
	)
