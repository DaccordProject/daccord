extends AccordTestBase

## Integration tests for DM-related API endpoints:
##   - users.list_channels()       — GET /users/@me/channels
##   - users.create_dm()           — POST /users/@me/channels
##   - channels.fetch()            — GET /channels/{id}
##   - channels.delete()           — DELETE /channels/{id} (close DM)
##   - channels.update()           — PATCH /channels/{id} (rename group DM)
##   - channels.add_recipient()    — PUT /channels/{id}/recipients/{user_id}
##   - channels.remove_recipient() — DELETE /channels/{id}/recipients/{user_id}


var third_user_id: String = ""
var third_user_token: String = ""
var third_client: AccordClient


func before_all() -> void:
	await super()
	# Login or register a third user for group DM tests.
	# Login first in case the user exists from a previous run (seed does not
	# drop the full database).
	var reg_client := _create_client("", "Bearer")
	var result: RestResult = await reg_client.auth.login({
		"username": "dm_test_user",
		"password": "testpass123",
	})
	if not result.ok:
		result = await reg_client.auth.register({
			"username": "dm_test_user",
			"password": "testpass123",
		})
	assert_true(result.ok, "login or register third user should succeed")
	third_user_id = str(result.data["user"]["id"])
	third_user_token = str(result.data["token"])
	reg_client.queue_free()


func before_each() -> void:
	super()
	third_client = _create_client(third_user_token, "Bearer")


func after_each() -> void:
	if is_instance_valid(third_client):
		third_client.queue_free()
	super()


# -- 1:1 DM --


func test_create_dm() -> void:
	var result: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(result.ok, "create DM should succeed")
	assert_eq(result.data["type"], "dm")
	var recipients = result.data["recipients"]
	assert_not_null(recipients)
	assert_true(recipients.size() >= 1, "DM should have at least one recipient")


func test_create_dm_is_idempotent() -> void:
	var first: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(first.ok)
	var first_id: String = first.data["id"]

	var second: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(second.ok)
	assert_eq(second.data["id"], first_id, "same DM should be returned")


func test_list_dm_channels() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	var result: RestResult = await user_client.users.list_channels()
	assert_true(result.ok, "list DM channels should succeed")
	assert_true(result.data is Array)
	var found := false
	for ch in result.data:
		if ch["id"] == dm_id:
			found = true
			break
	assert_true(found, "created DM should appear in channel list")


func test_fetch_dm_channel() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	var result: RestResult = await user_client.channels.fetch(dm_id)
	assert_true(result.ok, "fetch DM channel should succeed")
	assert_eq(result.data["id"], dm_id)
	assert_eq(result.data["type"], "dm")


func test_both_participants_see_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	var list: RestResult = await bot_client.users.list_channels()
	assert_true(list.ok)
	var found := false
	for ch in list.data:
		if ch["id"] == dm_id:
			found = true
			break
	assert_true(found, "bot should see the DM in their channel list")


func test_send_message_in_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	var result: RestResult = await user_client.messages.create(dm_id, {
		"content": "Hello from DM test!",
	})
	assert_true(result.ok, "send message in DM should succeed")
	assert_eq(result.data["content"], "Hello from DM test!")
	assert_eq(result.data["channel_id"], dm_id)


func test_list_messages_in_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": bot_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	await user_client.messages.create(dm_id, {"content": "DM list test"})

	var result: RestResult = await user_client.messages.list(dm_id, {"limit": 10})
	assert_true(result.ok, "list DM messages should succeed")
	assert_true(result.data is Array)
	assert_true(result.data.size() >= 1, "should have at least one message")


func test_close_dm() -> void:
	# Use third_user DM to avoid affecting other tests that use user<->bot DM
	var create: RestResult = await user_client.users.create_dm({
		"recipient_id": third_user_id,
	})
	assert_true(create.ok)
	var dm_id: String = create.data["id"]

	var result: RestResult = await user_client.channels.delete(dm_id)
	assert_true(result.ok, "close DM should succeed")

	var list: RestResult = await user_client.users.list_channels()
	assert_true(list.ok)
	var found := false
	for ch in list.data:
		if ch["id"] == dm_id:
			found = true
			break
	assert_false(found, "closed DM should not appear in list")


func test_create_dm_nonexistent_user() -> void:
	var result: RestResult = await user_client.users.create_dm({
		"recipient_id": "99999999999999",
	})
	assert_false(result.ok, "creating DM with nonexistent user should fail")


# -- Group DM --


func test_create_group_dm() -> void:
	var result: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(result.ok, "create group DM should succeed")
	assert_eq(result.data["type"], "group_dm")
	assert_eq(result.data["owner_id"], user_id)
	var recipients = result.data["recipients"]
	assert_not_null(recipients)
	assert_true(recipients.size() >= 2, "group DM should have at least two recipients")


func test_rename_group_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(create.ok)
	var group_id: String = create.data["id"]

	var result: RestResult = await user_client.channels.update(group_id, {
		"name": "Test Group Chat",
	})
	assert_true(result.ok, "owner should be able to rename group DM")
	assert_eq(result.data["name"], "Test Group Chat")

	# Verify via fetch
	var verify: RestResult = await user_client.channels.fetch(group_id)
	assert_true(verify.ok)
	assert_eq(verify.data["name"], "Test Group Chat")


func test_non_owner_cannot_rename_group_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(create.ok)
	var group_id: String = create.data["id"]

	var result: RestResult = await third_client.channels.update(group_id, {
		"name": "Unauthorized Rename",
	})
	assert_false(result.ok, "non-owner should not be able to rename group DM")


func test_add_recipient_to_group_dm() -> void:
	# Create group DM with bot and third user, then remove and re-add third user
	var create: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(create.ok)
	var group_id: String = create.data["id"]

	# Remove third user first
	var remove: RestResult = await user_client.channels.remove_recipient(
		group_id, third_user_id
	)
	assert_true(remove.ok, "removing recipient should succeed before re-add")

	# Re-add third user
	var result: RestResult = await user_client.channels.add_recipient(
		group_id, third_user_id
	)
	assert_true(result.ok, "adding recipient to group DM should succeed")

	# Verify third user can see the channel
	var list: RestResult = await third_client.users.list_channels()
	assert_true(list.ok)
	var found := false
	for ch in list.data:
		if ch["id"] == group_id:
			found = true
			break
	assert_true(found, "re-added user should see the group DM")


func test_remove_recipient_from_group_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(create.ok)
	var group_id: String = create.data["id"]

	var result: RestResult = await user_client.channels.remove_recipient(
		group_id, third_user_id
	)
	assert_true(result.ok, "owner should be able to remove a recipient")

	var list: RestResult = await third_client.users.list_channels()
	assert_true(list.ok)
	var found := false
	for ch in list.data:
		if ch["id"] == group_id:
			found = true
			break
	assert_false(found, "removed user should not see the group DM")


func test_leave_group_dm() -> void:
	var create: RestResult = await user_client.users.create_dm({
		"recipients": [bot_id, third_user_id],
	})
	assert_true(create.ok)
	var group_id: String = create.data["id"]

	# Third user leaves by removing themselves
	var result: RestResult = await third_client.channels.remove_recipient(
		group_id, third_user_id
	)
	assert_true(result.ok, "user should be able to leave group DM")

	var list: RestResult = await third_client.users.list_channels()
	assert_true(list.ok)
	var found := false
	for ch in list.data:
		if ch["id"] == group_id:
			found = true
			break
	assert_false(found, "user who left should not see the group DM")
