class_name AccordPresence
extends RefCounted

## Discord presence update.

var user_id: String = ""
var status: String = "offline"
var client_status: Dictionary = {}
var activities: Array = []
var space_id = null


static func from_dict(d: Dictionary) -> AccordPresence:
	var p := AccordPresence.new()

	var raw_user = d.get("user", null)
	if raw_user is Dictionary:
		p.user_id = str(raw_user.get("id", ""))
	else:
		p.user_id = str(d.get("user_id", ""))

	p.status = d.get("status", "offline")
	p.client_status = d.get("client_status", {})

	p.activities = []
	var raw_activities = d.get("activities", [])
	for a in raw_activities:
		if a is Dictionary:
			p.activities.append(AccordActivity.from_dict(a))

	p.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		p.space_id = str(raw_space)

	return p


func to_dict() -> Dictionary:
	var d := {
		"user_id": user_id,
		"status": status,
		"client_status": client_status,
	}

	var activity_dicts := []
	for a in activities:
		if a is AccordActivity:
			activity_dicts.append(a.to_dict())
	d["activities"] = activity_dicts

	if space_id != null:
		d["space_id"] = space_id
	return d
