class_name PluginContext
extends RefCounted

## Bridge resource that native plugins receive via setup(context).
## Provides identity, session state, participant info, and communication
## methods (data channels via LiveKit, file transfer).

signal data_received(sender_id: String, topic: String, payload: PackedByteArray)
signal file_received(sender_id: String, filename: String, data: PackedByteArray)
signal session_state_changed(new_state: String)
signal participant_joined(user_id: String, role: String)
signal participant_left(user_id: String)
signal role_changed(user_id: String, new_role: String)

# Identity
var plugin_id: String = ""
var session_id: String = ""
var conn_index: int = -1
var local_user_id: String = ""

# Session
var session_state: String = "lobby"  # "lobby", "running", "ended"
var participants: Array = []  # Array of { user_id, role, display_name }
var host_user_id: String = ""

# Internal references (set by ClientPlugins, not exposed to plugin scenes)
var _client_plugins = null  # ClientPlugins
var _livekit_adapter: Node = null  # LiveKitAdapter


## Sends data to other participants via LiveKit data channel.
## topic: application-defined topic string (e.g. "game:state", "chat")
## payload: arbitrary bytes
## reliable: true for TCP-like delivery, false for UDP-like (lower latency)
## destination_ids: empty array = broadcast to all session participants
func send_data(
	topic: String, payload: PackedByteArray,
	reliable: bool = true, destination_ids: Array = [],
) -> void:
	if _livekit_adapter == null:
		return
	var full_topic := "plugin:%s:%s" % [plugin_id, topic]
	if _livekit_adapter.has_method("publish_plugin_data"):
		_livekit_adapter.publish_plugin_data(
			payload, reliable, full_topic, destination_ids,
		)


## Sends a file to participants via chunked data channel transfer.
## Thin wrapper around send_data with a "file:" prefixed topic.
func send_file(
	filename: String, data: PackedByteArray,
	destination_ids: Array = [],
) -> void:
	# Encode filename + data into a single payload:
	# [4 bytes: filename length][filename bytes][file data]
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + data
	send_data("file:" + filename, payload, true, destination_ids)


## Returns the current participant list.
func get_participants() -> Array:
	return participants.duplicate()


## Returns the role of a specific user, or "" if not found.
func get_role(user_id: String) -> String:
	for p in participants:
		if p.get("user_id", "") == user_id:
			return p.get("role", "")
	return ""


## Returns true if the local user is the session host.
func is_host() -> bool:
	return local_user_id == host_user_id


## Sends a REST action to the server (for server-authoritative game logic).
func send_action(data: Dictionary) -> void:
	if _client_plugins != null and _client_plugins.has_method("send_action"):
		_client_plugins.send_action(plugin_id, data)


## Submits a score to a plugin leaderboard.
func leaderboard_submit(board_id: String, score: float, metadata: Dictionary = {}) -> void:
	if _client_plugins != null and _client_plugins.has_method("leaderboard_submit"):
		_client_plugins.leaderboard_submit(plugin_id, board_id, score, metadata)


## Returns the top entries for a leaderboard.
func leaderboard_get(board_id: String, limit: int = 50) -> Array:
	if _client_plugins != null and _client_plugins.has_method("leaderboard_get"):
		return await _client_plugins.leaderboard_get(plugin_id, board_id, limit)
	return []


## Returns leaderboard entries around the current user's rank.
func leaderboard_around_me(board_id: String, limit: int = 10) -> Array:
	if _client_plugins != null and _client_plugins.has_method("leaderboard_around"):
		return await _client_plugins.leaderboard_around(plugin_id, board_id, limit)
	return []


## Returns a specific user's leaderboard record.
func leaderboard_get_user(board_id: String, user_id: String) -> Dictionary:
	if _client_plugins != null and _client_plugins.has_method("leaderboard_get_user"):
		return await _client_plugins.leaderboard_get_user(plugin_id, board_id, user_id)
	return {}


## Requests a file from the host (sends a data channel message asking for it).
func request_file(filename: String) -> void:
	var payload: PackedByteArray = filename.to_utf8_buffer()
	send_data("file_request", payload, true, [host_user_id])
