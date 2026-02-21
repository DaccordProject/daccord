class_name AccordAuditLogEntry
extends RefCounted

## Audit log entry object.

var id: String
var user_id: String = ""
var action_type: String = ""
var target_id: String = ""
var target_type: String = ""
var reason: String = ""
var changes: Array = []
var created_at: String = ""


static func from_dict(d: Dictionary) -> AccordAuditLogEntry:
	var e := AccordAuditLogEntry.new()
	e.id = str(d.get("id", ""))
	e.user_id = str(d.get("user_id", ""))
	e.action_type = d.get("action_type", "")
	e.target_id = str(d.get("target_id", ""))
	e.target_type = d.get("target_type", "")
	e.reason = d.get("reason", "")
	e.changes = d.get("changes", [])
	e.created_at = d.get("created_at", "")
	return e


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"user_id": user_id,
		"action_type": action_type,
		"target_id": target_id,
		"target_type": target_type,
		"reason": reason,
		"changes": changes,
		"created_at": created_at,
	}
	return d
