class_name SoundboardApi
extends RefCounted

## REST endpoint helpers for soundboard management within a space:
## listing, fetching, creating, updating, deleting sounds, and triggering playback.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists all sounds in a space's soundboard.
func list(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/soundboard")
	if result.ok and result.data is Array:
		var sounds := []
		for item in result.data:
			if item is Dictionary:
				sounds.append(AccordSound.from_dict(item))
		result.data = sounds
	return result


## Fetches a single sound by its ID within a space.
func fetch(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/soundboard/" + sound_id)
	if result.ok and result.data is Dictionary:
		result.data = AccordSound.from_dict(result.data)
	return result


## Creates a new sound in a space's soundboard. The data dictionary should
## contain "name" and "audio" (base64 data URI), and optionally "volume".
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/soundboard", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordSound.from_dict(result.data)
	return result


## Updates a sound's name or volume.
func update(space_id: String, sound_id: String, data: Dictionary) -> RestResult:
	var path := "/spaces/" + space_id + "/soundboard/" + sound_id
	var result := await _rest.make_request("PATCH", path, data)
	if result.ok and result.data is Dictionary:
		result.data = AccordSound.from_dict(result.data)
	return result


## Deletes a sound from a space's soundboard.
func delete(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/soundboard/" + sound_id)
	return result


## Triggers playback of a sound.
func play(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/soundboard/" + sound_id + "/play")
	return result
