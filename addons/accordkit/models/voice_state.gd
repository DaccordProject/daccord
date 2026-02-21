class_name AccordVoiceState
extends RefCounted

## Discord voice state object.

var user_id: String = ""
var space_id = null
var channel_id = null
var session_id: String = ""
var deaf: bool = false
var mute: bool = false
var self_deaf: bool = false
var self_mute: bool = false
var self_stream: bool = false
var self_video: bool = false
var suppress: bool = false


static func from_dict(d: Dictionary) -> AccordVoiceState:
	var v := AccordVoiceState.new()
	v.user_id = str(d.get("user_id", ""))
	v.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		v.space_id = str(raw_space)
	v.channel_id = null
	var raw_channel = d.get("channel_id", null)
	if raw_channel != null:
		v.channel_id = str(raw_channel)
	v.session_id = d.get("session_id", "")
	v.deaf = d.get("deaf", false)
	v.mute = d.get("mute", false)
	v.self_deaf = d.get("self_deaf", false)
	v.self_mute = d.get("self_mute", false)
	v.self_stream = d.get("self_stream", false)
	v.self_video = d.get("self_video", false)
	v.suppress = d.get("suppress", false)
	return v


func to_dict() -> Dictionary:
	var d := {
		"user_id": user_id,
		"session_id": session_id,
		"deaf": deaf,
		"mute": mute,
		"self_deaf": self_deaf,
		"self_mute": self_mute,
		"self_stream": self_stream,
		"self_video": self_video,
		"suppress": suppress,
	}
	if space_id != null:
		d["space_id"] = space_id
	if channel_id != null:
		d["channel_id"] = channel_id
	return d
