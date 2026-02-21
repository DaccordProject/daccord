class_name AccordSound
extends RefCounted

## Soundboard sound object.

var id = null
var name: String = ""
var audio_url: String = ""
var volume: float = 1.0
var creator_id = null
var created_at: String = ""
var updated_at: String = ""


static func from_dict(d: Dictionary) -> AccordSound:
	var s := AccordSound.new()
	var raw_id = d.get("id", null)
	s.id = str(raw_id) if raw_id != null else null
	s.name = d.get("name", "")
	s.audio_url = d.get("audio_url", "")
	s.volume = float(d.get("volume", 1.0))
	s.creator_id = null
	var raw_creator = d.get("creator_id", null)
	if raw_creator != null:
		s.creator_id = str(raw_creator)
	s.created_at = d.get("created_at", "")
	s.updated_at = d.get("updated_at", "")
	return s


func to_dict() -> Dictionary:
	var d := {
		"name": name,
		"audio_url": audio_url,
		"volume": volume,
		"created_at": created_at,
		"updated_at": updated_at,
	}
	if id != null:
		d["id"] = id
	if creator_id != null:
		d["creator_id"] = creator_id
	return d
