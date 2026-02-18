extends GutTest


func test_default_intents() -> void:
	var defaults := GatewayIntents.default()
	assert_eq(defaults.size(), 3)
	assert_true(defaults.has(GatewayIntents.SPACES))
	assert_true(defaults.has(GatewayIntents.MESSAGES))
	assert_true(defaults.has(GatewayIntents.MESSAGE_CONTENT))


func test_all_includes_privileged() -> void:
	var all := GatewayIntents.all()
	assert_true(all.has(GatewayIntents.MEMBERS))
	assert_true(all.has(GatewayIntents.PRESENCES))
	assert_true(all.has(GatewayIntents.MESSAGE_CONTENT))


func test_all_includes_unprivileged() -> void:
	var all := GatewayIntents.all()
	assert_true(all.has(GatewayIntents.SPACES))
	assert_true(all.has(GatewayIntents.MESSAGES))
	assert_true(all.has(GatewayIntents.VOICE_STATES))


func test_unprivileged_excludes_privileged() -> void:
	var unpriv := GatewayIntents.unprivileged()
	assert_false(unpriv.has(GatewayIntents.MEMBERS))
	assert_false(unpriv.has(GatewayIntents.PRESENCES))
	assert_false(unpriv.has(GatewayIntents.MESSAGE_CONTENT))


func test_privileged_count() -> void:
	var priv := GatewayIntents.privileged()
	assert_eq(priv.size(), 3)


func test_unprivileged_count() -> void:
	var unpriv := GatewayIntents.unprivileged()
	assert_eq(unpriv.size(), 11)


func test_all_is_union() -> void:
	var all := GatewayIntents.all()
	var unpriv := GatewayIntents.unprivileged()
	var priv := GatewayIntents.privileged()
	assert_eq(all.size(), unpriv.size() + priv.size())
	for intent in unpriv:
		assert_true(all.has(intent))
	for intent in priv:
		assert_true(all.has(intent))


func test_intent_constants_are_strings() -> void:
	assert_eq(typeof(GatewayIntents.SPACES), TYPE_STRING)
	assert_eq(typeof(GatewayIntents.MEMBERS), TYPE_STRING)
	assert_eq(typeof(GatewayIntents.MESSAGE_CONTENT), TYPE_STRING)
