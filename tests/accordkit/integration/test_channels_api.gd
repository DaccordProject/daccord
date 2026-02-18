extends AccordTestBase


func test_get_channel() -> void:
	var result: RestResult = await bot_client.channels.fetch(testing_channel_id)
	assert_true(result.ok, "get channel should succeed")
	assert_eq(result.data["id"], testing_channel_id)
	assert_eq(result.data["name"], "testing")


func test_get_general_channel() -> void:
	var result: RestResult = await bot_client.channels.fetch(general_channel_id)
	assert_true(result.ok, "get general channel should succeed")
	assert_eq(result.data["name"], "general")


func test_update_channel_topic() -> void:
	var result: RestResult = await user_client.channels.update(testing_channel_id, {
		"topic": "Updated topic",
	})
	assert_true(result.ok, "update channel topic should succeed")
	assert_eq(result.data["topic"], "Updated topic")

	# Verify via GET
	var verify: RestResult = await user_client.channels.fetch(testing_channel_id)
	assert_eq(verify.data["topic"], "Updated topic")
