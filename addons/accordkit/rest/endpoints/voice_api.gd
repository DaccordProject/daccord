class_name VoiceApi
extends RefCounted

## REST endpoint helpers for voice-related operations: querying voice
## backend info, joining/leaving voice channels, listing regions, and
## checking voice channel status.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Returns information about the server's voice backend configuration.
func get_info() -> RestResult:
	var result := await _rest.make_request("GET", "/voice/info")
	return result


## Joins a voice channel. Returns an AccordVoiceServerUpdate containing
## backend connection details (LiveKit URL + token, or SFU endpoint).
func join(channel_id: String, self_mute: bool = false, self_deaf: bool = false) -> RestResult:
	var body := {"self_mute": self_mute, "self_deaf": self_deaf}
	var result := await _rest.make_request("POST", "/channels/" + channel_id + "/voice/join", body)
	if result.ok and result.data is Dictionary:
		result.data = AccordVoiceServerUpdate.from_dict(result.data)
	return result


## Leaves the voice channel the authenticated user is currently in.
func leave(channel_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/channels/" + channel_id + "/voice/leave")
	return result


## Lists available voice regions for a space. These can be used when
## creating or updating voice channels.
func list_regions(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/voice-regions")
	return result


## Fetches the current voice status for a channel, including connected
## users and their voice states.
func get_status(channel_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id + "/voice-status")
	if result.ok and result.data is Array:
		var states: Array[AccordVoiceState] = []
		for item in result.data:
			if item is Dictionary:
				states.append(AccordVoiceState.from_dict(item))
		result.data = states
	return result
