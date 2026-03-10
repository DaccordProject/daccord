class_name AccordUser
extends RefCounted

## Discord user object.

var id: String
var username: String
var display_name = null
var avatar = null
var banner = null
var accent_color = null
var bio = null
var bot: bool = false
var system: bool = false
var flags: int = 0
var public_flags: int = 0
var is_admin: bool = false
var mfa_enabled: bool = false
var disabled: bool = false
var is_guest: bool = false
var created_at: String = ""


static func from_dict(d: Dictionary) -> AccordUser:
	var u := AccordUser.new()
	u.id = str(d.get("id", ""))
	u.username = d.get("username", "")
	u.display_name = d.get("display_name", null)
	u.avatar = d.get("avatar", null)
	u.banner = d.get("banner", null)
	u.accent_color = d.get("accent_color", null)
	u.bio = d.get("bio", null)
	u.bot = d.get("bot", false)
	u.system = d.get("system", false)
	u.flags = d.get("flags", 0)
	u.public_flags = d.get("public_flags", 0)
	u.is_admin = d.get("is_admin", false)
	u.mfa_enabled = d.get("mfa_enabled", false)
	u.disabled = d.get("disabled", false)
	u.is_guest = d.get("is_guest", false)
	u.created_at = d.get("created_at", "")
	return u


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"username": username,
		"bot": bot,
		"system": system,
		"flags": flags,
		"public_flags": public_flags,
		"is_admin": is_admin,
		"mfa_enabled": mfa_enabled,
		"disabled": disabled,
		"is_guest": is_guest,
		"created_at": created_at,
	}
	if display_name != null:
		d["display_name"] = display_name
	if avatar != null:
		d["avatar"] = avatar
	if banner != null:
		d["banner"] = banner
	if accent_color != null:
		d["accent_color"] = accent_color
	if bio != null:
		d["bio"] = bio
	return d
