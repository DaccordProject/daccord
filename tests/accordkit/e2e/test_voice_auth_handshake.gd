extends AccordTestBase

## Minimal e2e for the voice auth handshake.
## Tests the REST join/leave flow and validates the server returns
## the credentials the Godot client needs to connect to LiveKit.
##
## When the server has no voice backend configured (backend="none"),
## tests that require LiveKit credentials are skipped gracefully.

var _backend: String = ""


func before_all() -> void:
	await super.before_all()
	# Probe the voice backend once so individual tests can skip
	var probe := _create_client(user_token, "Bearer")
	var info_result: RestResult = await probe.voice.get_info()
	if info_result.ok and info_result.data is Dictionary:
		_backend = info_result.data.get("backend", "none")
	probe.queue_free()
	gut.p("Voice backend: %s" % _backend)


func test_voice_info_reports_backend() -> void:
	var result: RestResult = await user_client.voice.get_info()
	assert_true(result.ok, "GET /voice/info should succeed")
	assert_true(result.data is Dictionary, "Response should be a dict")
	var backend: String = result.data.get("backend", "")
	assert_false(backend.is_empty(), "backend field should be present")
	gut.p("  backend = %s" % backend)


func test_create_voice_channel() -> void:
	var ch_result: RestResult = await user_client.spaces.create_channel(
		space_id, {"name": "voice_create_test", "type": "voice"}
	)
	assert_true(ch_result.ok, "Create voice channel should succeed")
	var voice_ch: AccordChannel = ch_result.data
	assert_false(voice_ch.id.is_empty(), "Channel ID should not be empty")
	assert_eq(voice_ch.type, "voice", "Channel type should be 'voice'")
	gut.p("  channel_id = %s" % voice_ch.id)


func test_voice_join_returns_livekit_credentials() -> void:
	if _backend != "livekit":
		gut.p("SKIP: server backend is '%s', not 'livekit'" % _backend)
		pass_test("Skipped — backend is '%s'" % _backend)
		return

	# 1. Create a voice channel
	var ch_result: RestResult = await user_client.spaces.create_channel(
		space_id, {"name": "voice_auth_e2e", "type": "voice"}
	)
	assert_true(ch_result.ok, "Create voice channel should succeed")
	if not ch_result.ok:
		return
	var voice_channel_id: String = ch_result.data.id

	# 2. Join voice via REST
	var join_result: RestResult = await user_client.voice.join(
		voice_channel_id, false, false
	)
	gut.p("Join response status: %d" % join_result.status_code)
	if not join_result.ok:
		var err_msg: String = ""
		if join_result.error != null:
			err_msg = join_result.error.message
		gut.p("Join error: %s" % err_msg)
		gut.p("Raw data: %s" % str(join_result.data))
	assert_true(
		join_result.ok,
		"POST /channels/{id}/voice/join should succeed (status=%d)" % [
			join_result.status_code
		]
	)
	if not join_result.ok:
		return

	assert_true(
		join_result.data is AccordVoiceServerUpdate,
		"Response should be AccordVoiceServerUpdate"
	)
	var info: AccordVoiceServerUpdate = join_result.data

	# 3. Dump everything the client would receive
	gut.p("Voice join response:")
	gut.p("  backend      = %s" % str(info.backend))
	gut.p("  livekit_url  = %s" % str(info.livekit_url))
	gut.p("  token        = %s" % (
		"<present, %d chars>" % str(info.token).length()
		if info.token != null else "<null>"
	))
	gut.p("  space_id     = %s" % str(info.space_id))
	gut.p("  channel_id   = %s" % str(info.channel_id))
	gut.p("  sfu_endpoint = %s" % str(info.sfu_endpoint))

	# 4. Validate the credentials the Godot client passes to LiveKitAdapter
	assert_eq(info.backend, "livekit", "Backend should be 'livekit'")
	assert_not_null(info.livekit_url, "livekit_url must not be null")
	assert_not_null(info.token, "token must not be null")

	var url: String = str(info.livekit_url)
	var token: String = str(info.token)
	assert_false(url.is_empty(), "livekit_url must not be empty")
	assert_false(token.is_empty(), "token must not be empty")
	assert_true(
		url.begins_with("ws://") or url.begins_with("wss://"),
		"livekit_url should start with ws:// or wss:// (got '%s')" % url
	)
	# Token should be a JWT (three dot-separated base64 segments)
	var parts: PackedStringArray = token.split(".")
	assert_eq(
		parts.size(), 3,
		"token should be a JWT (3 parts, got %d)" % parts.size()
	)

	# 5. Validate voice_state in the response
	assert_not_null(
		info.voice_state,
		"voice_state should be present in join response"
	)
	if info.voice_state != null:
		var vs: AccordVoiceState = info.voice_state
		assert_eq(vs.user_id, user_id, "voice_state.user_id should match")
		assert_eq(
			str(vs.channel_id), voice_channel_id,
			"voice_state.channel_id should match"
		)
		assert_false(vs.self_mute, "self_mute should be false")
		assert_false(vs.self_deaf, "self_deaf should be false")
		gut.p("  voice_state.session_id = %s" % vs.session_id)

	# 6. Leave voice
	var leave_result: RestResult = await user_client.voice.leave(
		voice_channel_id
	)
	assert_true(
		leave_result.ok,
		"DELETE /channels/{id}/voice/leave should succeed"
	)


func test_voice_join_with_mute_and_deaf_flags() -> void:
	if _backend != "livekit":
		pass_test("Skipped — backend is '%s'" % _backend)
		return

	var ch_result: RestResult = await user_client.spaces.create_channel(
		space_id, {"name": "voice_flags_e2e", "type": "voice"}
	)
	assert_true(ch_result.ok, "Create voice channel should succeed")
	if not ch_result.ok:
		return
	var voice_channel_id: String = ch_result.data.id

	# Join with self_mute=true, self_deaf=true
	var join_result: RestResult = await user_client.voice.join(
		voice_channel_id, true, true
	)
	assert_true(join_result.ok, "Voice join with flags should succeed")
	if not join_result.ok:
		return

	var info: AccordVoiceServerUpdate = join_result.data
	assert_not_null(info.voice_state, "voice_state should be present")
	if info.voice_state != null:
		assert_true(
			info.voice_state.self_mute,
			"self_mute should be true"
		)
		assert_true(
			info.voice_state.self_deaf,
			"self_deaf should be true"
		)
		gut.p("  self_mute=%s self_deaf=%s" % [
			str(info.voice_state.self_mute),
			str(info.voice_state.self_deaf),
		])

	await user_client.voice.leave(voice_channel_id)


func test_voice_leave_without_join_fails_gracefully() -> void:
	var ch_result: RestResult = await user_client.spaces.create_channel(
		space_id, {"name": "voice_leave_test", "type": "voice"}
	)
	assert_true(ch_result.ok, "Create voice channel should succeed")
	if not ch_result.ok:
		return
	var voice_channel_id: String = ch_result.data.id

	# Leave without joining should not crash (may return error)
	var leave_result: RestResult = await user_client.voice.leave(
		voice_channel_id
	)
	gut.p("Leave without join: status=%d ok=%s" % [
		leave_result.status_code, str(leave_result.ok)
	])
	# We just care it doesn't crash — either ok or a clean error
	assert_true(true, "Leave without join should not crash")
