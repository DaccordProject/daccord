class_name AccordEmoji
extends RefCounted

## Discord emoji object.

var id = null
var name: String = ""
var animated: bool = false
var managed: bool = false
var available: bool = true
var require_colons: bool = true
var role_ids: Array = []
var creator_id = null
var image_url: String = ""


static func from_dict(d: Dictionary) -> AccordEmoji:
	var e := AccordEmoji.new()
	var raw_id = d.get("id", null)
	e.id = str(raw_id) if raw_id != null else null
	e.name = d.get("name", "")
	e.animated = d.get("animated", false)
	e.managed = d.get("managed", false)
	e.available = d.get("available", true)
	e.require_colons = d.get("require_colons", true)
	e.image_url = d.get("image_url", "")
	var raw_roles = d.get("role_ids", d.get("roles", []))
	e.role_ids = []
	for r in raw_roles:
		e.role_ids.append(str(r))
	e.creator_id = null
	var raw_creator = d.get("creator_id", null)
	if raw_creator != null:
		e.creator_id = str(raw_creator)
	return e


func to_dict() -> Dictionary:
	var d := {
		"name": name,
		"animated": animated,
		"managed": managed,
		"available": available,
		"require_colons": require_colons,
		"role_ids": role_ids,
	}
	if id != null:
		d["id"] = id
	if creator_id != null:
		d["creator_id"] = creator_id
	if not image_url.is_empty():
		d["image_url"] = image_url
	return d
