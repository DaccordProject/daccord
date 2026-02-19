extends AccordTestBase


func test_get_space() -> void:
	var result: RestResult = await user_client.spaces.fetch(space_id)
	assert_true(result.ok, "get space should succeed")
	assert_eq(result.data["id"], space_id)
	assert_eq(result.data["name"], "Test Space")


func test_create_space() -> void:
	var result: RestResult = await user_client.spaces.create({
		"name": "New Space",
	})
	assert_true(result.ok, "create space should succeed")
	assert_eq(result.data["name"], "New Space")
	assert_eq(result.data["owner_id"], user_id)
	# Cleanup: ID is available for further assertions
	var new_space_id: String = str(result.data["id"])
	assert_false(new_space_id.is_empty())


func test_update_space() -> void:
	# Create a space to update
	var create_result: RestResult = await user_client.spaces.create({"name": "ToUpdate"})
	assert_true(create_result.ok)
	var sid: String = str(create_result.data["id"])

	var result: RestResult = await user_client.spaces.update(sid, {
		"name": "UpdatedName",
		"description": "A description",
	})
	assert_true(result.ok, "update space should succeed")
	assert_eq(result.data["name"], "UpdatedName")


func test_list_channels() -> void:
	var result: RestResult = await user_client.spaces.list_channels(space_id)
	assert_true(result.ok, "list channels should succeed")
	assert_true(result.data is Array)
	# Should have at least general and testing channels
	assert_true(result.data.size() >= 2, "Space should have at least 2 channels")

	var names := []
	for ch in result.data:
		names.append(ch.name if ch.name != null else "")
	assert_true(names.has("general"), "Should have #general")
	assert_true(names.has("testing"), "Should have #testing")


func test_create_channel() -> void:
	var result: RestResult = await user_client.spaces.create_channel(space_id, {
		"name": "new-channel",
		"type": "text",
		"topic": "A new channel",
	})
	assert_true(result.ok, "create channel should succeed")
	assert_eq(result.data["name"], "new-channel")
	assert_eq(result.data["space_id"], space_id)
