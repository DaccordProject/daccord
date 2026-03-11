extends GutTest

## Tests for SoundManager autoload.
## Uses add_child_autofree to trigger _ready() so signal connections
## and audio player pool are set up properly.

var sound_manager: Node
var _saved_status: int
var _saved_sfx_vol: float
var _saved_channel: String


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func before_each() -> void:
	sound_manager = load(
		"res://scripts/autoload/sound_manager.gd"
	).new()
	add_child_autofree(sound_manager)
	# Save state we're going to mutate
	_saved_status = Client.current_user.get(
		"status", ClientModels.UserStatus.ONLINE
	)
	_saved_sfx_vol = Config.get_sfx_volume()
	_saved_channel = AppState.current_channel_id
	# Reset to sane defaults
	Client.current_user["status"] = ClientModels.UserStatus.ONLINE
	Config.set_sfx_volume(1.0)
	AppState.current_channel_id = ""


func after_each() -> void:
	# Restore original state
	Client.current_user["status"] = _saved_status
	Config.set_sfx_volume(_saved_sfx_vol)
	AppState.current_channel_id = _saved_channel


# ==================================================================
# Instantiation
# ==================================================================

func test_instantiates_without_crash() -> void:
	assert_not_null(sound_manager)


func test_creates_audio_player_pool() -> void:
	# _players should be filled by _ready()
	var players: Array = sound_manager._players
	assert_eq(players.size(), sound_manager.POOL_SIZE)


# ==================================================================
# play() — early-return guards
# ==================================================================

func test_play_unknown_sound_no_crash() -> void:
	sound_manager.play("nonexistent_sound")
	# Should return early without crash; _next_player stays 0
	assert_eq(sound_manager._next_player, 0)


func test_play_dnd_returns_early() -> void:
	Client.current_user["status"] = ClientModels.UserStatus.DND
	sound_manager.play("message_received")
	# Player pool is not cycled when DND is active
	assert_eq(sound_manager._next_player, 0)


func test_play_sound_disabled_returns_early() -> void:
	Config.set_sound_enabled("message_received", false)
	sound_manager.play("message_received")
	assert_eq(sound_manager._next_player, 0)
	Config.set_sound_enabled("message_received", true)


func test_play_zero_volume_returns_early() -> void:
	Config.set_sfx_volume(0.0)
	sound_manager.play("message_received")
	assert_eq(sound_manager._next_player, 0)


# ==================================================================
# play_for_message() — skip conditions
# ==================================================================

func test_play_for_message_skips_own_message() -> void:
	Client.current_user["id"] = "me_1"
	sound_manager.play_for_message(
		"c_1", "me_1", [], false
	)
	# own message — should not cycle any player
	assert_eq(sound_manager._next_player, 0)


func test_play_for_message_skips_current_channel() -> void:
	Client.current_user["id"] = "me_1"
	AppState.current_channel_id = "c_active"
	sound_manager.play_for_message(
		"c_active", "other_user", [], false
	)
	assert_eq(sound_manager._next_player, 0)


func test_play_for_message_unfocused_not_mention_no_crash() -> void:
	# When unfocused and non-mention, tries to play message_received.
	# With a live audio pool, this succeeds silently in headless mode.
	Client.current_user["id"] = "me_1"
	sound_manager._window_focused = false
	# Should not crash even if audio output is unavailable
	sound_manager.play_for_message(
		"c_other", "other_user", [], false
	)


# ==================================================================
# Signal connections
# ==================================================================

func test_signal_message_sent_is_connected() -> void:
	assert_true(
		AppState.message_sent.is_connected(
			sound_manager._on_message_sent
		)
	)


func test_signal_voice_joined_is_connected() -> void:
	assert_true(
		AppState.voice_joined.is_connected(
			sound_manager._on_voice_joined
		)
	)


func test_signal_voice_left_is_connected() -> void:
	assert_true(
		AppState.voice_left.is_connected(
			sound_manager._on_voice_left
		)
	)


func test_signal_voice_mute_changed_is_connected() -> void:
	assert_true(
		AppState.voice_mute_changed.is_connected(
			sound_manager._on_voice_mute_changed
		)
	)


func test_signal_voice_deafen_changed_is_connected() -> void:
	assert_true(
		AppState.voice_deafen_changed.is_connected(
			sound_manager._on_voice_deafen_changed
		)
	)


# ==================================================================
# Window focus tracking
# ==================================================================

func test_focus_out_sets_unfocused() -> void:
	sound_manager._window_focused = true
	sound_manager._notification(
		NOTIFICATION_APPLICATION_FOCUS_OUT
	)
	assert_false(sound_manager._window_focused)


func test_focus_in_sets_focused() -> void:
	sound_manager._window_focused = false
	sound_manager._notification(
		NOTIFICATION_APPLICATION_FOCUS_IN
	)
	assert_true(sound_manager._window_focused)
