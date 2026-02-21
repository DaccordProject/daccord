class_name AccordInvite
extends RefCounted

## Discord invite object.

var code: String = ""
var space_id: String = ""
var channel_id: String = ""
var inviter_id = null
var max_uses = null
var uses: int = 0
var max_age = null
var temporary: bool = false
var created_at: String = ""
var expires_at = null


static func from_dict(d: Dictionary) -> AccordInvite:
	var i := AccordInvite.new()
	i.code = d.get("code", "")
	i.space_id = str(d.get("space_id", d.get("guild_id", "")))
	i.channel_id = str(d.get("channel_id", ""))

	i.inviter_id = null
	var raw_inviter = d.get("inviter", null)
	if raw_inviter is Dictionary:
		i.inviter_id = str(raw_inviter.get("id", ""))
	elif d.has("inviter_id"):
		var raw_id = d.get("inviter_id", null)
		if raw_id != null:
			i.inviter_id = str(raw_id)

	i.max_uses = d.get("max_uses", null)
	i.uses = d.get("uses", 0)
	i.max_age = d.get("max_age", null)
	i.temporary = d.get("temporary", false)
	i.created_at = d.get("created_at", "")
	i.expires_at = d.get("expires_at", null)
	return i


func to_dict() -> Dictionary:
	var d := {
		"code": code,
		"space_id": space_id,
		"channel_id": channel_id,
		"uses": uses,
		"temporary": temporary,
		"created_at": created_at,
	}
	if inviter_id != null:
		d["inviter_id"] = inviter_id
	if max_uses != null:
		d["max_uses"] = max_uses
	if max_age != null:
		d["max_age"] = max_age
	if expires_at != null:
		d["expires_at"] = expires_at
	return d
