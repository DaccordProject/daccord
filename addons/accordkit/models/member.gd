class_name AccordMember
extends RefCounted

## Discord guild member object.

var user_id: String = ""
var user: AccordUser = null
var space_id: String = ""
var nickname = null
var avatar = null
var roles: Array = []
var joined_at: String = ""
var premium_since = null
var deaf: bool = false
var mute: bool = false
var pending = null
var timed_out_until = null
var permissions = null


static func from_dict(d: Dictionary) -> AccordMember:
	var m := AccordMember.new()

	var raw_user = d.get("user", null)
	if raw_user is Dictionary:
		m.user_id = str(raw_user.get("id", ""))
		m.user = AccordUser.from_dict(raw_user)
	else:
		m.user_id = str(d.get("user_id", ""))

	m.space_id = str(d.get("space_id", d.get("guild_id", "")))
	m.nickname = d.get("nick", d.get("nickname", null))
	m.avatar = d.get("avatar", null)

	m.roles = []
	var raw_roles = d.get("roles", [])
	for r in raw_roles:
		m.roles.append(str(r))

	m.joined_at = d.get("joined_at", "")
	m.premium_since = d.get("premium_since", null)
	m.deaf = d.get("deaf", false)
	m.mute = d.get("mute", false)
	m.pending = d.get("pending", null)
	m.timed_out_until = d.get("communication_disabled_until", d.get("timed_out_until", null))
	m.permissions = d.get("permissions", null)
	return m


func to_dict() -> Dictionary:
	var d := {
		"user_id": user_id,
		"space_id": space_id,
		"roles": roles,
		"joined_at": joined_at,
		"deaf": deaf,
		"mute": mute,
	}
	if nickname != null:
		d["nickname"] = nickname
	if avatar != null:
		d["avatar"] = avatar
	if premium_since != null:
		d["premium_since"] = premium_since
	if pending != null:
		d["pending"] = pending
	if timed_out_until != null:
		d["timed_out_until"] = timed_out_until
	if permissions != null:
		d["permissions"] = permissions
	return d
