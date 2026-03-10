class_name AccordRelationship
extends RefCounted

## Represents a relationship between the current user and another user.
## type values mirror the server-side enum:
##   1 = FRIEND, 2 = BLOCKED, 3 = PENDING_INCOMING, 4 = PENDING_OUTGOING

var id: String = ""
var user = null  # AccordUser (nullable)
var type: int = 0
var since: String = ""
var user_status: String = ""      # Presence status from server (online/idle/dnd/offline)
var user_activities: Array = []   # Presence activities from server


static func from_dict(d: Dictionary) -> AccordRelationship:
	var r := AccordRelationship.new()
	r.id = str(d.get("id", ""))
	if d.has("user") and d["user"] is Dictionary:
		r.user = AccordUser.from_dict(d["user"])
		r.user_status = str(d["user"].get("status", ""))
		var acts = d["user"].get("activities", [])
		if acts is Array:
			r.user_activities = acts
	r.type = int(d.get("type", 0))
	r.since = str(d.get("since", ""))
	return r
