extends GutTest


func test_all_returns_all_permissions() -> void:
	var perms := AccordPermission.all()
	# Should contain all 37 defined permissions
	assert_eq(perms.size(), 37)
	assert_true(perms.has(AccordPermission.ADMINISTRATOR))
	assert_true(perms.has(AccordPermission.SEND_MESSAGES))
	assert_true(perms.has(AccordPermission.MODERATE_MEMBERS))


func test_has_present() -> void:
	var perms := ["send_messages", "read_history"]
	assert_true(AccordPermission.has(perms, "send_messages"))
	assert_true(AccordPermission.has(perms, "read_history"))


func test_has_missing() -> void:
	var perms := ["send_messages"]
	assert_false(AccordPermission.has(perms, "manage_messages"))


func test_administrator_grants_all() -> void:
	var perms := ["administrator"]
	assert_true(AccordPermission.has(perms, "kick_members"))
	assert_true(AccordPermission.has(perms, "ban_members"))
	assert_true(AccordPermission.has(perms, "manage_channels"))
	assert_true(AccordPermission.has(perms, "send_messages"))
	assert_true(AccordPermission.has(perms, "moderate_members"))


func test_has_empty_permissions() -> void:
	assert_false(AccordPermission.has([], "send_messages"))


func test_permission_constants_are_strings() -> void:
	assert_eq(typeof(AccordPermission.ADMINISTRATOR), TYPE_STRING)
	assert_eq(typeof(AccordPermission.SEND_MESSAGES), TYPE_STRING)
	assert_eq(typeof(AccordPermission.CREATE_INVITES), TYPE_STRING)


func test_all_permissions_are_unique() -> void:
	var perms := AccordPermission.all()
	var seen := {}
	for p in perms:
		assert_false(seen.has(p), "Duplicate permission: %s" % p)
		seen[p] = true
