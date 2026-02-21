class_name AccordActivity
extends RefCounted

## Discord activity object (part of presence).

var name: String = ""
var type: String = "playing"
var url = null
var state = null
var details = null
var timestamps = null
var assets = null


static func from_dict(d: Dictionary) -> AccordActivity:
	var a := AccordActivity.new()
	a.name = d.get("name", "")
	a.type = d.get("type", "playing")
	a.url = d.get("url", null)
	a.state = d.get("state", null)
	a.details = d.get("details", null)
	a.timestamps = d.get("timestamps", null)
	a.assets = d.get("assets", null)
	return a


func to_dict() -> Dictionary:
	var d := {
		"name": name,
		"type": type,
	}
	if url != null:
		d["url"] = url
	if state != null:
		d["state"] = state
	if details != null:
		d["details"] = details
	if timestamps != null:
		d["timestamps"] = timestamps
	if assets != null:
		d["assets"] = assets
	return d
