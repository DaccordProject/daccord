class_name AccordPermissionOverwrite
extends RefCounted

## Channel permission overwrite for a role or member.

var id: String
var type: String = "role"
var allow: Array = []
var deny: Array = []


static func from_dict(d: Dictionary) -> AccordPermissionOverwrite:
	var o := AccordPermissionOverwrite.new()
	o.id = str(d.get("id", ""))
	var raw_type: String = d.get("type", "role")
	o.type = "user" if raw_type == "member" else raw_type
	o.allow = d.get("allow", [])
	o.deny = d.get("deny", [])
	return o


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"allow": allow,
		"deny": deny,
	}
