extends AccordTestBase


var _created_message_id: String = ""


func test_create_message() -> void:
	var result: RestResult = await bot_client.messages.create(testing_channel_id, {
		"content": "Hello from test!",
	})
	assert_true(result.ok, "create message should succeed")
	assert_eq(result.data["content"], "Hello from test!")
	assert_eq(result.data["channel_id"], testing_channel_id)
	_created_message_id = str(result.data["id"])


func test_list_messages() -> void:
	# Create a message first
	var create: RestResult = await bot_client.messages.create(testing_channel_id, {
		"content": "List test message",
	})
	assert_true(create.ok)

	var result: RestResult = await bot_client.messages.list(testing_channel_id, {"limit": 10})
	assert_true(result.ok, "list messages should succeed")
	assert_true(result.data is Array)
	assert_true(result.data.size() >= 1, "Should have at least one message")


func test_get_message() -> void:
	# Create a message first
	var create: RestResult = await bot_client.messages.create(testing_channel_id, {
		"content": "Get test message",
	})
	assert_true(create.ok)
	var msg_id: String = str(create.data["id"])

	var result: RestResult = await bot_client.messages.fetch(testing_channel_id, msg_id)
	assert_true(result.ok, "get message should succeed")
	assert_eq(result.data["id"], msg_id)
	assert_eq(result.data["content"], "Get test message")


func test_edit_message() -> void:
	# Create a message first
	var create: RestResult = await bot_client.messages.create(testing_channel_id, {
		"content": "Before edit",
	})
	assert_true(create.ok)
	var msg_id: String = str(create.data["id"])

	var result: RestResult = await bot_client.messages.edit(testing_channel_id, msg_id, {
		"content": "After edit",
	})
	assert_true(result.ok, "edit message should succeed")
	assert_eq(result.data["content"], "After edit")


func test_delete_message() -> void:
	# Create a message first
	var create: RestResult = await bot_client.messages.create(testing_channel_id, {
		"content": "To be deleted",
	})
	assert_true(create.ok)
	var msg_id: String = str(create.data["id"])

	var result: RestResult = await bot_client.messages.delete(testing_channel_id, msg_id)
	assert_true(result.ok, "delete message should succeed")

	# Verify it's gone
	var verify: RestResult = await bot_client.messages.fetch(testing_channel_id, msg_id)
	assert_false(verify.ok, "Deleted message should not be found")
	assert_eq(verify.status_code, 404)


func test_typing_indicator() -> void:
	var result: RestResult = await bot_client.messages.typing(testing_channel_id)
	assert_true(result.ok, "typing indicator should succeed")
