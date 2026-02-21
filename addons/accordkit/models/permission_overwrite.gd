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
	o.type = d.get("type", "role")
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
