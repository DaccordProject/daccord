class_name AccordRole
extends RefCounted

## Discord role object.

var id: String
var name: String = ""
var color: int = 0
var hoist: bool = false
var icon = null
var position: int = 0
var permissions: Array = []
var managed: bool = false
var mentionable: bool = false


static func from_dict(d: Dictionary) -> AccordRole:
	var r := AccordRole.new()
	r.id = str(d.get("id", ""))
	r.name = d.get("name", "")
	r.color = d.get("color", 0)
	r.hoist = d.get("hoist", false)
	r.icon = d.get("icon", null)
	r.position = d.get("position", 0)
	r.permissions = d.get("permissions", [])
	r.managed = d.get("managed", false)
	r.mentionable = d.get("mentionable", false)
	return r


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"color": color,
		"hoist": hoist,
		"position": position,
		"permissions": permissions,
		"managed": managed,
		"mentionable": mentionable,
	}
	if icon != null:
		d["icon"] = icon
	return d
