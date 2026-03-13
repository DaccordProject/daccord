extends AccordTestBase


func test_list_plugins() -> void:
	var result: RestResult = await user_client.plugins.list_plugins(space_id)
	assert_true(result.ok, "list plugins should succeed")
	assert_true(result.data is Array, "data should be an array")
	# The seed creates a test plugin, so we should have at least one
	assert_true(result.data.size() >= 1, "should have at least the seeded plugin")


func test_list_plugins_with_type_filter() -> void:
	var result: RestResult = await user_client.plugins.list_plugins(space_id, "activity")
	assert_true(result.ok, "list plugins with type filter should succeed")
	assert_true(result.data is Array, "data should be an array")
	for p in result.data:
		assert_eq(p.type, "activity", "all plugins should be activities")


func test_list_plugins_empty_type_filter() -> void:
	var result: RestResult = await user_client.plugins.list_plugins(space_id, "bot")
	assert_true(result.ok, "list plugins with bot filter should succeed")
	assert_eq(result.data.size(), 0, "no bot plugins should exist")


func test_seeded_plugin_manifest_fields() -> void:
	var result: RestResult = await user_client.plugins.list_plugins(space_id)
	assert_true(result.ok)
	var found := false
	for p in result.data:
		if p is AccordPluginManifest and p.id == plugin_id:
			found = true
			assert_eq(p.name, "Test Plugin")
			assert_eq(p.runtime, "scripted")
			assert_eq(p.type, "activity")
			assert_eq(p.version, "1.0.0")
			assert_eq(p.max_participants, 8)
			assert_true(p.lobby)
			break
	assert_true(found, "seeded plugin should be in the list")


func test_create_and_delete_session() -> void:
	# Create a session on the testing channel
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok, "create session should succeed")

	var session: Dictionary = create_result.data
	assert_true(session.has("id"), "session should have an id")
	assert_eq(session.get("plugin_id", ""), plugin_id)
	assert_eq(session.get("channel_id", ""), testing_channel_id)
	assert_eq(session.get("state", ""), "lobby", "plugin has lobby=true so initial state should be lobby")
	assert_eq(session.get("host_user_id", ""), user_id)

	var session_id: String = str(session["id"])

	# Delete the session
	var delete_result: RestResult = await user_client.plugins.delete_session(
		plugin_id, session_id
	)
	assert_true(delete_result.ok, "delete session should succeed")


func test_session_state_transitions() -> void:
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok)
	var session_id: String = str(create_result.data["id"])

	# Transition lobby -> running
	var running_result: RestResult = await user_client.plugins.update_session_state(
		plugin_id, session_id, "running"
	)
	assert_true(running_result.ok, "lobby -> running should succeed")
	assert_eq(running_result.data.get("state", ""), "running")

	# Transition running -> ended
	var ended_result: RestResult = await user_client.plugins.update_session_state(
		plugin_id, session_id, "ended"
	)
	assert_true(ended_result.ok, "running -> ended should succeed")
	assert_eq(ended_result.data.get("state", ""), "ended")

	# Cleanup
	await user_client.plugins.delete_session(plugin_id, session_id)


func test_assign_role() -> void:
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok)
	var session_id: String = str(create_result.data["id"])

	# Host is already a player; switch to spectator
	var role_result: RestResult = await user_client.plugins.assign_role(
		plugin_id, session_id, user_id, "spectator"
	)
	assert_true(role_result.ok, "assign spectator role should succeed")

	# Verify the participant's role changed
	var session: Dictionary = role_result.data
	var participants: Array = session.get("participants", [])
	var found := false
	for p in participants:
		if str(p.get("user_id", "")) == user_id:
			found = true
			assert_eq(p.get("role", ""), "spectator")
			break
	assert_true(found, "user should be in participants")

	# Switch back to player
	var player_result: RestResult = await user_client.plugins.assign_role(
		plugin_id, session_id, user_id, "player"
	)
	assert_true(player_result.ok, "assign player role should succeed")

	# Cleanup
	await user_client.plugins.delete_session(plugin_id, session_id)


func test_send_action() -> void:
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok)
	var session_id: String = str(create_result.data["id"])

	# Must be in "running" state to send actions
	var running_result: RestResult = await user_client.plugins.update_session_state(
		plugin_id, session_id, "running"
	)
	assert_true(running_result.ok)

	# Send an action
	var action_result: RestResult = await user_client.plugins.send_action(
		plugin_id, session_id, {"action": "test_move", "value": 42}
	)
	assert_true(action_result.ok, "send action should succeed")

	# Cleanup
	await user_client.plugins.delete_session(plugin_id, session_id)


func test_send_action_requires_running_state() -> void:
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok)
	var session_id: String = str(create_result.data["id"])

	# Session is in "lobby" state — action should fail
	var action_result: RestResult = await user_client.plugins.send_action(
		plugin_id, session_id, {"action": "test_move"}
	)
	assert_false(action_result.ok, "action in lobby state should fail")

	# Cleanup
	await user_client.plugins.delete_session(plugin_id, session_id)


func test_invalid_state_transition() -> void:
	var create_result: RestResult = await user_client.plugins.create_session(
		plugin_id, testing_channel_id
	)
	assert_true(create_result.ok)
	var session_id: String = str(create_result.data["id"])

	# Try invalid transition: lobby -> ended (should work per server code)
	# Try: lobby -> lobby (should fail)
	var invalid_result: RestResult = await user_client.plugins.update_session_state(
		plugin_id, session_id, "lobby"
	)
	assert_false(invalid_result.ok, "lobby -> lobby should be invalid")

	# Cleanup
	await user_client.plugins.delete_session(plugin_id, session_id)
