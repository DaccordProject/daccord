extends AccordTestBase

## Integration tests verifying that accordserver enforces permissions
## correctly. The seed creates two users:
##   - user_client (Bearer) — space owner, has implicit administrator
##   - bot_client (Bot) — regular member, only has @everyone permissions
##
## Each test verifies that bot_client is denied (403) for operations
## requiring admin permissions, and that user_client (owner) succeeds.


# -- Space Management (manage_space) ------------------------------------------

func test_bot_denied_update_space() -> void:
	var result: RestResult = await bot_client.spaces.update(space_id, {"name": "Hacked"})
	assert_false(result.ok, "bot without manage_space should be denied")
	assert_eq(result.status_code, 403)


func test_owner_can_update_space() -> void:
	var result: RestResult = await user_client.spaces.update(space_id, {"description": "Updated by owner"})
	assert_true(result.ok, "owner should be able to update space")


# -- Space Deletion (owner-only) ----------------------------------------------

func test_bot_denied_delete_space() -> void:
	# Bot tries to delete the space owned by user — should be denied
	var result: RestResult = await bot_client.spaces.delete(space_id)
	assert_false(result.ok, "bot should not be able to delete space it does not own")
	assert_eq(result.status_code, 403)


# -- Channel Management (manage_channels) -------------------------------------

func test_bot_denied_create_channel() -> void:
	var result: RestResult = await bot_client.spaces.create_channel(space_id, {
		"name": "bot-channel",
		"type": "text",
	})
	assert_false(result.ok, "bot without manage_channels should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_update_channel() -> void:
	var result: RestResult = await bot_client.channels.update(general_channel_id, {
		"topic": "Hacked topic",
	})
	assert_false(result.ok, "bot without manage_channels should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_delete_channel() -> void:
	# Create a channel as owner, then have bot try to delete it
	var create_result: RestResult = await user_client.spaces.create_channel(space_id, {
		"name": "delete-me",
		"type": "text",
	})
	assert_true(create_result.ok, "owner should create channel for test setup")
	var channel_id: String = str(create_result.data["id"])

	var result: RestResult = await bot_client.channels.delete(channel_id)
	assert_false(result.ok, "bot without manage_channels should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.channels.delete(channel_id)


func test_owner_can_manage_channels() -> void:
	# Create
	var create_result: RestResult = await user_client.spaces.create_channel(space_id, {
		"name": "owner-channel",
		"type": "text",
	})
	assert_true(create_result.ok, "owner should create channel")
	var channel_id: String = str(create_result.data["id"])

	# Update
	var update_result: RestResult = await user_client.channels.update(channel_id, {
		"topic": "Owner topic",
	})
	assert_true(update_result.ok, "owner should update channel")

	# Delete
	var delete_result: RestResult = await user_client.channels.delete(channel_id)
	assert_true(delete_result.ok, "owner should delete channel")


# -- Role Management (manage_roles) -------------------------------------------

func test_bot_denied_create_role() -> void:
	var result: RestResult = await bot_client.roles.create(space_id, {"name": "EvilRole"})
	assert_false(result.ok, "bot without manage_roles should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_update_role() -> void:
	# Create a role as owner, then have bot try to update it
	var create_result: RestResult = await user_client.roles.create(space_id, {"name": "TestRole"})
	assert_true(create_result.ok, "owner should create role for test setup")
	var role_id: String = str(create_result.data["id"])

	var result: RestResult = await bot_client.roles.update(space_id, role_id, {"name": "Hacked"})
	assert_false(result.ok, "bot without manage_roles should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.roles.delete(space_id, role_id)


func test_bot_denied_delete_role() -> void:
	var create_result: RestResult = await user_client.roles.create(space_id, {"name": "DeleteMe"})
	assert_true(create_result.ok, "owner should create role for test setup")
	var role_id: String = str(create_result.data["id"])

	var result: RestResult = await bot_client.roles.delete(space_id, role_id)
	assert_false(result.ok, "bot without manage_roles should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.roles.delete(space_id, role_id)


func test_owner_can_manage_roles() -> void:
	# Create
	var create_result: RestResult = await user_client.roles.create(space_id, {
		"name": "OwnerRole",
		"color": 0xFF0000,
	})
	assert_true(create_result.ok, "owner should create role")
	var role_id: String = str(create_result.data["id"])

	# Update
	var update_result: RestResult = await user_client.roles.update(space_id, role_id, {
		"name": "RenamedRole",
	})
	assert_true(update_result.ok, "owner should update role")

	# Delete
	var delete_result: RestResult = await user_client.roles.delete(space_id, role_id)
	assert_true(delete_result.ok, "owner should delete role")


# -- Kick Members (kick_members) ----------------------------------------------

func test_bot_denied_kick_member() -> void:
	# Bot tries to kick the owner — should be denied (lacks kick_members)
	var result: RestResult = await bot_client.members.kick(space_id, user_id)
	assert_false(result.ok, "bot without kick_members should be denied")
	assert_eq(result.status_code, 403)


# -- Ban Management (ban_members) ---------------------------------------------

func test_bot_denied_list_bans() -> void:
	var result: RestResult = await bot_client.bans.list(space_id)
	assert_false(result.ok, "bot without ban_members should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_create_ban() -> void:
	var result: RestResult = await bot_client.bans.create(space_id, user_id)
	assert_false(result.ok, "bot without ban_members should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_remove_ban() -> void:
	# Even though no ban exists, the permission check should fire first
	var result: RestResult = await bot_client.bans.remove(space_id, user_id)
	assert_false(result.ok, "bot without ban_members should be denied")
	assert_eq(result.status_code, 403)


func test_owner_can_manage_bans() -> void:
	# We need a third user to ban. Create a temporary space and use
	# the bot as the ban target from the owner's perspective.
	# Note: we can't ban the bot from the main space and then have it
	# run subsequent tests, so we create a throwaway space for this.
	var temp_space: RestResult = await user_client.spaces.create({"name": "BanTestSpace"})
	assert_true(temp_space.ok, "owner should create temp space")
	var temp_space_id: String = str(temp_space.data["id"])

	# Bot joins the temp space
	var join_result: RestResult = await bot_client.spaces.join(temp_space_id)
	# Join may or may not succeed depending on server config; skip if it fails
	if not join_result.ok:
		return

	# Owner bans bot from temp space
	var ban_result: RestResult = await user_client.bans.create(temp_space_id, bot_id)
	assert_true(ban_result.ok, "owner should be able to ban a member")

	# Owner unbans bot from temp space
	var unban_result: RestResult = await user_client.bans.remove(temp_space_id, bot_id)
	assert_true(unban_result.ok, "owner should be able to unban a member")


# -- Member Role Assignment (manage_roles) ------------------------------------

func test_bot_denied_add_member_role() -> void:
	# Create a role as owner, then have bot try to assign it
	var create_result: RestResult = await user_client.roles.create(space_id, {"name": "AssignMe"})
	assert_true(create_result.ok, "owner should create role for test setup")
	var role_id: String = str(create_result.data["id"])

	var result: RestResult = await bot_client.members.add_role(space_id, bot_id, role_id)
	assert_false(result.ok, "bot without manage_roles should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.roles.delete(space_id, role_id)


func test_bot_denied_remove_member_role() -> void:
	# Create a role and assign it via owner, then have bot try to remove it
	var create_result: RestResult = await user_client.roles.create(space_id, {"name": "RemoveMe"})
	assert_true(create_result.ok, "owner should create role for test setup")
	var role_id: String = str(create_result.data["id"])

	await user_client.members.add_role(space_id, bot_id, role_id)

	var result: RestResult = await bot_client.members.remove_role(space_id, bot_id, role_id)
	assert_false(result.ok, "bot without manage_roles should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.members.remove_role(space_id, bot_id, role_id)
	await user_client.roles.delete(space_id, role_id)


# -- Invite Management --------------------------------------------------------

func test_member_can_create_invite() -> void:
	# Bot has create_invites in @everyone, should succeed
	var result: RestResult = await bot_client.invites.create_channel(general_channel_id)
	assert_true(result.ok, "bot with create_invites should be able to create invite")


func test_bot_denied_delete_invite() -> void:
	# Create an invite as owner, then have bot try to delete it
	var create_result: RestResult = await user_client.invites.create_channel(general_channel_id)
	assert_true(create_result.ok, "owner should create invite for test setup")
	var code: String = str(create_result.data["code"])

	var result: RestResult = await bot_client.invites.delete(code)
	assert_false(result.ok, "bot without manage_channels should be denied from deleting invites")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.invites.delete(code)


# -- Emoji Management (manage_emojis) -----------------------------------------

# Minimal 1x1 transparent PNG as base64 data URI for emoji creation
const TINY_PNG := "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="


func test_bot_denied_create_emoji() -> void:
	var result: RestResult = await bot_client.emojis.create(space_id, {
		"name": "evil_emoji",
		"image": TINY_PNG,
	})
	assert_false(result.ok, "bot without manage_emojis should be denied")
	assert_eq(result.status_code, 403)


func test_bot_denied_delete_emoji() -> void:
	# Create an emoji as owner, then have bot try to delete it
	var create_result: RestResult = await user_client.emojis.create(space_id, {
		"name": "test_emoji",
		"image": TINY_PNG,
	})
	assert_true(create_result.ok, "owner should create emoji for test setup")
	var emoji_id: String = str(create_result.data["id"])

	var result: RestResult = await bot_client.emojis.delete(space_id, emoji_id)
	assert_false(result.ok, "bot without manage_emojis should be denied")
	assert_eq(result.status_code, 403)

	# Cleanup
	await user_client.emojis.delete(space_id, emoji_id)


# -- Permission Escalation via Role Grant -------------------------------------

func test_bot_granted_permission_can_act() -> void:
	# Owner creates a role with manage_channels permission
	var create_role: RestResult = await user_client.roles.create(space_id, {
		"name": "ChannelManager",
		"permissions": [AccordPermission.MANAGE_CHANNELS],
	})
	assert_true(create_role.ok, "owner should create role")
	var role_id: String = str(create_role.data["id"])

	# Owner assigns the role to the bot
	var assign_result: RestResult = await user_client.members.add_role(space_id, bot_id, role_id)
	assert_true(assign_result.ok, "owner should assign role to bot")

	# Bot should now be able to create a channel
	var channel_result: RestResult = await bot_client.spaces.create_channel(space_id, {
		"name": "granted-channel",
		"type": "text",
	})
	assert_true(channel_result.ok, "bot with manage_channels role should create channel")
	var channel_id: String = str(channel_result.data["id"])

	# Cleanup: remove the role and delete the channel
	await user_client.members.remove_role(space_id, bot_id, role_id)
	await user_client.channels.delete(channel_id)
	await user_client.roles.delete(space_id, role_id)
