class_name AccordReaction
extends RefCounted

## Discord message reaction.

var emoji: Dictionary = {}
var count: int = 0
var includes_me: bool = false


static func from_dict(d: Dictionary) -> AccordReaction:
	var r := AccordReaction.new()
	var raw_emoji = d.get("emoji", {})
	r.emoji = {}
	if raw_emoji is Dictionary:
		var eid = raw_emoji.get("id", null)
		r.emoji["id"] = str(eid) if eid != null else null
		r.emoji["name"] = raw_emoji.get("name", "")
	elif raw_emoji is String:
		r.emoji["id"] = null
		r.emoji["name"] = raw_emoji
	r.count = d.get("count", 0)
	r.includes_me = d.get("me", d.get("includes_me", false))
	return r


func to_dict() -> Dictionary:
	return {
		"emoji": emoji,
		"count": count,
		"includes_me": includes_me,
	}
