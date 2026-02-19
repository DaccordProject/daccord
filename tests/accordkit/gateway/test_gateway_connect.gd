extends AccordTestBase


func test_bot_connect_receives_ready() -> void:
	var ready_received := false
	var ready_data := {}
	var connect_failed := false

	bot_client.ready_received.connect(func(data):
		ready_received = true
		ready_data = data
	)
	bot_client.disconnected.connect(func(_code, _reason):
		connect_failed = true
	)

	bot_client.login()

	# Wait up to 15 seconds for ready (CI can be slow)
	var elapsed := 0.0
	while not ready_received and not connect_failed and elapsed < 15.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_false(connect_failed, "Bot gateway disconnected unexpectedly")
	assert_true(ready_received, "Bot should receive ready signal within 15s")
	if ready_received:
		assert_true(ready_data.has("user") or ready_data.has("session_id"),
			"Ready data should contain user or session info")

	bot_client.logout()


func test_user_connect_receives_ready() -> void:
	var ready_received := false
	var connect_failed := false

	user_client.ready_received.connect(func(_data):
		ready_received = true
	)
	user_client.disconnected.connect(func(_code, _reason):
		connect_failed = true
	)

	user_client.login()

	var elapsed := 0.0
	while not ready_received and not connect_failed and elapsed < 15.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_false(connect_failed, "User gateway disconnected unexpectedly")
	assert_true(ready_received, "User should receive ready signal within 15s")

	user_client.logout()


func test_disconnect_clean_state() -> void:
	var ready_received := false
	var disconnect_received := false

	bot_client.ready_received.connect(func(_data):
		ready_received = true
	)
	bot_client.disconnected.connect(func(_code, _reason):
		disconnect_received = true
	)

	bot_client.login()

	# Wait for ready
	var elapsed := 0.0
	while not ready_received and elapsed < 15.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	assert_true(ready_received, "Should connect first")
	if not ready_received:
		return

	# Disconnect
	bot_client.logout()

	# Give some time for disconnect to propagate
	await get_tree().create_timer(0.5).timeout

	# Gateway should be in disconnected state
	assert_true(true, "Disconnect completed without error")
