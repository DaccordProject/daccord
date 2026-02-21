class_name AccordVoiceServerUpdate
extends RefCounted

## Voice server connection info returned by the REST join endpoint or
## received via the gateway voice.server_update event. Contains backend
## type and the credentials needed to connect to either LiveKit or the
## custom SFU.

var space_id: String = ""
var channel_id: String = ""
var backend: String = ""  # "livekit" or "custom"
var livekit_url = null
var token = null
var sfu_endpoint = null
var voice_state = null  # AccordVoiceState — present in REST join response, absent in gateway event


static func from_dict(d: Dictionary) -> AccordVoiceServerUpdate:
	var v := AccordVoiceServerUpdate.new()
	v.space_id = str(d.get("space_id", ""))
	v.channel_id = str(d.get("channel_id", ""))
	v.backend = d.get("backend", "")

	# REST uses livekit_url / sfu_endpoint; gateway uses url / endpoint
	var raw_livekit_url = d.get("livekit_url", d.get("url", null))
	if raw_livekit_url != null:
		v.livekit_url = str(raw_livekit_url)

	var raw_token = d.get("token", null)
	if raw_token != null:
		v.token = str(raw_token)

	var raw_sfu = d.get("sfu_endpoint", d.get("endpoint", null))
	if raw_sfu != null:
		v.sfu_endpoint = str(raw_sfu)

	var raw_vs = d.get("voice_state", null)
	if raw_vs != null and raw_vs is Dictionary:
		v.voice_state = AccordVoiceState.from_dict(raw_vs)

	return v


func to_dict() -> Dictionary:
	var d := {
		"space_id": space_id,
		"channel_id": channel_id,
		"backend": backend,
	}
	if livekit_url != null:
		d["livekit_url"] = livekit_url
	if token != null:
		d["token"] = token
	if sfu_endpoint != null:
		d["sfu_endpoint"] = sfu_endpoint
	if voice_state != null:
		d["voice_state"] = voice_state.to_dict()
	return d
