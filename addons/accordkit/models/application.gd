class_name AccordApplication
extends RefCounted

## Discord application object.

var id: String
var name: String = ""
var icon = null
var description: String = ""
var bot_public: bool = false
var owner_id: String = ""
var flags: int = 0


static func from_dict(d: Dictionary) -> AccordApplication:
	var a := AccordApplication.new()
	a.id = str(d.get("id", ""))
	a.name = d.get("name", "")
	a.icon = d.get("icon", null)
	a.description = d.get("description", "")
	a.bot_public = d.get("bot_public", false)

	var raw_owner = d.get("owner", null)
	if raw_owner is Dictionary:
		a.owner_id = str(raw_owner.get("id", ""))
	else:
		a.owner_id = str(d.get("owner_id", ""))

	a.flags = d.get("flags", 0)
	return a


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"description": description,
		"bot_public": bot_public,
		"owner_id": owner_id,
		"flags": flags,
	}
	if icon != null:
		d["icon"] = icon
	return d
