extends GutTest


# =============================================================================
# AccordVoiceState
# =============================================================================

func test_voice_state_from_dict_full() -> void:
	var d := {
		"user_id": "u1",
		"space_id": "sp1",
		"channel_id": "ch1",
		"session_id": "sess1",
		"deaf": true,
		"mute": false,
		"self_deaf": true,
		"self_mute": true,
		"self_stream": false,
		"self_video": true,
		"suppress": false,
	}
	var v := AccordVoiceState.from_dict(d)
	assert_eq(v.user_id, "u1")
	assert_eq(v.space_id, "sp1")
	assert_eq(v.channel_id, "ch1")
	assert_true(v.deaf)
	assert_true(v.self_deaf)
	assert_true(v.self_video)


func test_voice_state_from_dict_guild_id_alias() -> void:
	var v := AccordVoiceState.from_dict({"guild_id": "g1"})
	assert_eq(v.space_id, "g1")


func test_voice_state_from_dict_minimal() -> void:
	var v := AccordVoiceState.from_dict({})
	assert_null(v.space_id)
	assert_null(v.channel_id)
	assert_false(v.deaf)


func test_voice_state_to_dict_omits_null() -> void:
	var v := AccordVoiceState.from_dict({"user_id": "u1"})
	var out := v.to_dict()
	assert_false(out.has("space_id"))
	assert_false(out.has("channel_id"))


# =============================================================================
# AccordVoiceServerUpdate
# =============================================================================

func test_voice_server_update_livekit_rest() -> void:
	var d := {
		"space_id": "sp1",
		"channel_id": "ch1",
		"backend": "livekit",
		"livekit_url": "wss://lk.example.com",
		"token": "jwt_token_here",
		"voice_state": {
			"user_id": "u1",
			"space_id": "sp1",
			"channel_id": "ch1",
			"session_id": "sess1",
			"deaf": false,
			"mute": false,
			"self_deaf": false,
			"self_mute": false,
		},
	}
	var v := AccordVoiceServerUpdate.from_dict(d)
	assert_eq(v.space_id, "sp1")
	assert_eq(v.channel_id, "ch1")
	assert_eq(v.backend, "livekit")
	assert_eq(v.livekit_url, "wss://lk.example.com")
	assert_eq(v.token, "jwt_token_here")
	assert_null(v.sfu_endpoint)
	assert_not_null(v.voice_state)
	assert_eq(v.voice_state.user_id, "u1")
	assert_eq(v.voice_state.session_id, "sess1")


func test_voice_server_update_livekit_gateway() -> void:
	var d := {
		"space_id": "sp1",
		"channel_id": "ch1",
		"backend": "livekit",
		"url": "wss://lk.example.com",
		"token": "gw_token",
	}
	var v := AccordVoiceServerUpdate.from_dict(d)
	assert_eq(v.backend, "livekit")
	assert_eq(v.livekit_url, "wss://lk.example.com")
	assert_eq(v.token, "gw_token")
	assert_null(v.sfu_endpoint)
	assert_null(v.voice_state)


func test_voice_server_update_custom_rest() -> void:
	var d := {
		"space_id": "sp2",
		"channel_id": "ch2",
		"backend": "custom",
		"sfu_endpoint": "wss://sfu.example.com:4443",
		"voice_state": {
			"user_id": "u2",
			"space_id": "sp2",
			"channel_id": "ch2",
			"session_id": "sess2",
		},
	}
	var v := AccordVoiceServerUpdate.from_dict(d)
	assert_eq(v.backend, "custom")
	assert_null(v.livekit_url)
	assert_null(v.token)
	assert_eq(v.sfu_endpoint, "wss://sfu.example.com:4443")
	assert_not_null(v.voice_state)
	assert_eq(v.voice_state.user_id, "u2")


func test_voice_server_update_custom_gateway() -> void:
	var d := {
		"space_id": "sp2",
		"channel_id": "ch2",
		"backend": "custom",
		"endpoint": "wss://sfu.example.com:4443",
	}
	var v := AccordVoiceServerUpdate.from_dict(d)
	assert_eq(v.backend, "custom")
	assert_eq(v.sfu_endpoint, "wss://sfu.example.com:4443")
	assert_null(v.livekit_url)
	assert_null(v.token)
	assert_null(v.voice_state)


func test_voice_server_update_minimal() -> void:
	var v := AccordVoiceServerUpdate.from_dict({})
	assert_eq(v.space_id, "")
	assert_eq(v.channel_id, "")
	assert_eq(v.backend, "")
	assert_null(v.livekit_url)
	assert_null(v.token)
	assert_null(v.sfu_endpoint)
	assert_null(v.voice_state)


func test_voice_server_update_to_dict_roundtrip() -> void:
	var d := {
		"space_id": "sp1",
		"channel_id": "ch1",
		"backend": "livekit",
		"livekit_url": "wss://lk.example.com",
		"token": "tok",
		"voice_state": {"user_id": "u1", "session_id": "s1"},
	}
	var v := AccordVoiceServerUpdate.from_dict(d)
	var out := v.to_dict()
	assert_eq(out["space_id"], "sp1")
	assert_eq(out["channel_id"], "ch1")
	assert_eq(out["backend"], "livekit")
	assert_eq(out["livekit_url"], "wss://lk.example.com")
	assert_eq(out["token"], "tok")
	assert_true(out.has("voice_state"))
	assert_eq(out["voice_state"]["user_id"], "u1")


func test_voice_server_update_to_dict_omits_null() -> void:
	var v := AccordVoiceServerUpdate.from_dict({"backend": "custom"})
	var out := v.to_dict()
	assert_false(out.has("livekit_url"))
	assert_false(out.has("token"))
	assert_false(out.has("sfu_endpoint"))
	assert_false(out.has("voice_state"))
