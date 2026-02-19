extends AccordTestBase


func test_bot_receives_message_create() -> void:
	var ready_received := false
	var received_message = null
	var connect_failed := false

	bot_client.ready_received.connect(func(_data):
		ready_received = true
	)
	bot_client.message_create.connect(func(msg):
		received_message = msg
	)
	bot_client.disconnected.connect(func(_code, _reason):
		if not ready_received:
			connect_failed = true
	)

	bot_client.login()

	# Wait for bot to be ready (15s for CI)
	var elapsed := 0.0
	while not ready_received and not connect_failed and elapsed < 15.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_false(connect_failed, "Bot gateway disconnected unexpectedly")
	assert_true(ready_received, "Bot should receive ready")
	if not ready_received:
		return

	# User sends a message via REST
	var result: RestResult = await user_client.messages.create(testing_channel_id, {
		"content": "Gateway test message",
	})
	assert_true(result.ok, "User should be able to send a message")
	if not result.ok:
		bot_client.logout()
		return

	# Wait for bot to receive the message_create event
	elapsed = 0.0
	while received_message == null and elapsed < 10.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_not_null(received_message, "Bot should receive message_create within 10s")
	if received_message != null:
		assert_eq(received_message.content, "Gateway test message")
		assert_eq(received_message.channel_id, testing_channel_id)

	bot_client.logout()
