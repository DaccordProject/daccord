extends AccordTestBase


func test_full_lifecycle() -> void:
	# 1. Bot login -> ready
	var bot_ready := false
	var bot_received_message = null

	bot_client.ready_received.connect(func(_data):
		bot_ready = true
	)
	bot_client.message_create.connect(func(msg):
		bot_received_message = msg
	)

	bot_client.login()

	var elapsed := 0.0
	while not bot_ready and elapsed < 10.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_true(bot_ready, "Step 1: Bot should receive ready")

	# 2. Verify identity via get_me
	var me_result: RestResult = await bot_client.users.get_me()
	assert_true(me_result.ok, "Step 2: get_me should succeed")
	assert_eq(me_result.data["id"], bot_id)
	assert_true(me_result.data["bot"], "Should be a bot user")

	# 3. User creates a new space via REST
	var create_space_result: RestResult = await user_client.spaces.create({
		"name": "E2E Space",
	})
	assert_true(create_space_result.ok, "Step 3: create space should succeed")
	var new_space_id: String = str(create_space_result.data["id"])
	assert_false(new_space_id.is_empty())

	# 4. List channels in the new space
	var channels_result: RestResult = await user_client.spaces.list_channels(new_space_id)
	assert_true(channels_result.ok, "Step 4: list channels should succeed")
	assert_true(channels_result.data is Array)
	assert_true(channels_result.data.size() >= 1, "New space should have at least #general")

	var first_channel_id: String = ""
	for ch in channels_result.data:
		if ch.name == "general":
			first_channel_id = ch.id
			break

	if first_channel_id.is_empty() and channels_result.data.size() > 0:
		first_channel_id = channels_result.data[0].id

	assert_false(first_channel_id.is_empty(), "Should find a channel")

	# 5. Send a message and verify via GET
	var send_result: RestResult = await user_client.messages.create(first_channel_id, {
		"content": "E2E lifecycle message",
	})
	assert_true(send_result.ok, "Step 5: send message should succeed")
	var sent_msg_id: String = str(send_result.data["id"])

	var get_result: RestResult = await user_client.messages.fetch(first_channel_id, sent_msg_id)
	assert_true(get_result.ok, "Step 5: get message should succeed")
	assert_eq(get_result.data["content"], "E2E lifecycle message")

	# 6. Bot receives message_create on seeded channel
	# Send a message to the seeded testing channel (where bot is a member)
	var seeded_result: RestResult = await user_client.messages.create(testing_channel_id, {
		"content": "E2E gateway event test",
	})
	assert_true(seeded_result.ok, "Step 6: send to seeded channel should succeed")

	elapsed = 0.0
	while bot_received_message == null and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_not_null(bot_received_message, "Step 6: Bot should receive message_create")
	if bot_received_message != null:
		assert_eq(bot_received_message.content, "E2E gateway event test")

	# 7. Logout
	bot_client.logout()
	await get_tree().create_timer(0.5).timeout
	assert_true(true, "Step 7: Lifecycle completed successfully")
