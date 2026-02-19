extends AccordTestBase


func test_get_me_bot() -> void:
	var result: RestResult = await bot_client.users.get_me()
	assert_true(result.ok, "get_me (bot) should succeed")
	assert_eq(result.status_code, 200)
	assert_eq(result.data["id"], bot_id)
	assert_true(result.data["bot"])


func test_get_me_user() -> void:
	var result: RestResult = await user_client.users.get_me()
	assert_true(result.ok, "get_me (user) should succeed")
	assert_eq(result.status_code, 200)
	assert_eq(result.data["id"], user_id)
	assert_eq(result.data["username"], "test_user")


func test_get_user_by_id() -> void:
	var result: RestResult = await bot_client.users.fetch(user_id)
	assert_true(result.ok, "get user by ID should succeed")
	assert_eq(result.data["id"], user_id)
	assert_eq(result.data["username"], "test_user")


func test_get_nonexistent_user() -> void:
	var result: RestResult = await bot_client.users.fetch("99999999999999")
	assert_false(result.ok, "get nonexistent user should fail")
	assert_eq(result.status_code, 404)


func test_list_spaces() -> void:
	var result: RestResult = await user_client.users.list_spaces()
	assert_true(result.ok, "list_spaces should succeed")
	# User should be in at least the seeded space
	assert_true(result.data is Array)
	var found := false
	for s in result.data:
		if s.id == space_id:
			found = true
			break
	assert_true(found, "Seeded space should appear in user's spaces")


func test_update_me() -> void:
	var result: RestResult = await user_client.users.update_me({
		"display_name": "Updated Name",
	})
	assert_true(result.ok, "update_me should succeed")
	assert_eq(result.data["display_name"], "Updated Name")

	# Verify via get_me
	var verify: RestResult = await user_client.users.get_me()
	assert_eq(verify.data["display_name"], "Updated Name")
