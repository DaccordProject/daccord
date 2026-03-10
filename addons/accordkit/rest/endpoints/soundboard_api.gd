class_name SoundboardApi
extends EndpointBase

## REST endpoint helpers for soundboard management within a space:
## listing, fetching, creating, updating, deleting sounds, and triggering playback.


## Lists all sounds in a space's soundboard.
func list(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/soundboard")
	return result.deserialize_array(AccordSound.from_dict)


## Fetches a single sound by its ID within a space.
func fetch(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/soundboard/" + sound_id)
	return result.deserialize(AccordSound.from_dict)


## Creates a new sound in a space's soundboard. The data dictionary should
## contain "name" and "audio" (base64 data URI), and optionally "volume".
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/soundboard", data)
	return result.deserialize(AccordSound.from_dict)


## Updates a sound's name or volume.
func update(space_id: String, sound_id: String, data: Dictionary) -> RestResult:
	var path := "/spaces/" + space_id + "/soundboard/" + sound_id
	var result := await _rest.make_request("PATCH", path, data)
	return result.deserialize(AccordSound.from_dict)


## Deletes a sound from a space's soundboard.
func delete(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/soundboard/" + sound_id)
	return result


## Triggers playback of a sound.
func play(space_id: String, sound_id: String) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/soundboard/" + sound_id + "/play")
	return result
