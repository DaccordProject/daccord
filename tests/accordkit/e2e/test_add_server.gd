extends AccordTestBase


func test_add_server_via_invite() -> void:
	# 1. User creates a new space
	var create_space_result: RestResult = await user_client.spaces.create({
		"name": "Invite Test Space",
	})
	assert_true(create_space_result.ok, "Step 1: create space should succeed")
	var new_space_id: String = create_space_result.data.id
	assert_false(new_space_id.is_empty())

	# 2. User creates an invite for the new space
	var invite_result: RestResult = await user_client.invites.create_space(new_space_id)
	assert_true(invite_result.ok, "Step 2: create invite should succeed")
	var invite: AccordInvite = invite_result.data
	assert_false(invite.code.is_empty(), "Step 2: invite code should not be empty")

	# 3. Bot connects to gateway and waits for ready
	var bot_ready := false
	var joined_member: AccordMember = null

	bot_client.ready_received.connect(func(_data):
		bot_ready = true
	)

	bot_client.login()

	var elapsed := 0.0
	while not bot_ready and elapsed < 10.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_true(bot_ready, "Step 3: Bot should receive ready")

	# 4. Listen for member_join on user's side, then bot accepts the invite
	user_client.member_join.connect(func(member: AccordMember):
		if member.user_id == bot_id:
			joined_member = member
	)

	var accept_result: RestResult = await bot_client.invites.accept(invite.code)
	assert_true(accept_result.ok, "Step 4: bot accept invite should succeed")

	# 5. Verify gateway event — member_join fires with the bot's user ID
	elapsed = 0.0
	while joined_member == null and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_not_null(joined_member, "Step 5: user should receive member_join for bot")
	if joined_member != null:
		assert_eq(joined_member.user_id, bot_id, "Step 5: joined member should be the bot")

	# 6. Verify via REST — member list includes the bot
	var members_result: RestResult = await user_client.members.list(new_space_id)
	assert_true(members_result.ok, "Step 6: list members should succeed")
	var found_bot := false
	for member in members_result.data:
		if member.user_id == bot_id:
			found_bot = true
			break
	assert_true(found_bot, "Step 6: bot should appear in member list")

	# 7. Bot sends a message in the space's general channel to prove access
	var channels_result: RestResult = await user_client.spaces.list_channels(new_space_id)
	assert_true(channels_result.ok, "Step 7: list channels should succeed")

	var general_ch_id: String = ""
	for ch in channels_result.data:
		if ch.name == "general":
			general_ch_id = ch.id
			break

	if general_ch_id.is_empty() and channels_result.data.size() > 0:
		general_ch_id = channels_result.data[0].id

	assert_false(general_ch_id.is_empty(), "Step 7: should find a channel in the new space")

	var send_result: RestResult = await bot_client.messages.create(general_ch_id, {
		"content": "Bot joined via invite!",
	})
	assert_true(send_result.ok, "Step 7: bot should be able to send a message")
	assert_eq(send_result.data.content, "Bot joined via invite!")

	# 8. Cleanup — bot logs out
	bot_client.logout()
	await get_tree().create_timer(0.5).timeout
	assert_true(true, "Step 8: Add server lifecycle completed successfully")
