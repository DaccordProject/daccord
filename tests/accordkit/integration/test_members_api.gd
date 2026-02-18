extends AccordTestBase


func test_list_members() -> void:
	var result: RestResult = await bot_client.members.list(space_id, {"limit": 50})
	assert_true(result.ok, "list members should succeed")
	assert_true(result.data is Array)
	# Should have at least the owner and the bot
	assert_true(result.data.size() >= 2, "Space should have at least 2 members")


func test_get_member() -> void:
	var result: RestResult = await bot_client.members.fetch(space_id, user_id)
	assert_true(result.ok, "get member should succeed")
	# The member data should reference the user
	var member_user_id: String = ""
	if result.data.has("user_id"):
		member_user_id = str(result.data["user_id"])
	elif result.data.has("user") and result.data["user"] is Dictionary:
		member_user_id = str(result.data["user"]["id"])
	assert_eq(member_user_id, user_id)


func test_get_bot_member() -> void:
	var result: RestResult = await bot_client.members.fetch(space_id, bot_id)
	assert_true(result.ok, "get bot member should succeed")


func test_update_member_nickname() -> void:
	var result: RestResult = await user_client.members.update(space_id, bot_id, {
		"nick": "TestNick",
	})
	# Owner should be able to update bot's nickname
	assert_true(result.ok, "update member nickname should succeed")
