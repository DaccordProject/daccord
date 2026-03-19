## User-related model converters: users, relationships, activities, badges.

const USER_FLAGS := {
	1: "Staff",
	2: "Partner",
	4: "HypeSquad Events",
	8: "Bug Hunter Level 1",
	64: "HypeSquad Bravery",
	128: "HypeSquad Brilliance",
	256: "HypeSquad Balance",
	512: "Early Supporter",
	16384: "Bug Hunter Level 2",
	65536: "Verified Bot",
	131072: "Early Verified Bot Developer",
	262144: "Certified Moderator",
	1048576: "Active Developer",
}

static func _status_string_to_enum(status: String) -> int:
	match status:
		"online":
			return ClientModels.UserStatus.ONLINE
		"idle":
			return ClientModels.UserStatus.IDLE
		"dnd":
			return ClientModels.UserStatus.DND
		_:
			return ClientModels.UserStatus.OFFLINE

static func _status_enum_to_string(status: int) -> String:
	match status:
		ClientModels.UserStatus.ONLINE:
			return "online"
		ClientModels.UserStatus.IDLE:
			return "idle"
		ClientModels.UserStatus.DND:
			return "dnd"
		_:
			return "offline"

static func status_color(status: int) -> Color:
	match status:
		ClientModels.UserStatus.ONLINE:
			return ThemeManager.get_color("status_online")
		ClientModels.UserStatus.IDLE:
			return ThemeManager.get_color("status_idle")
		ClientModels.UserStatus.DND:
			return ThemeManager.get_color("status_dnd")
		_:
			return ThemeManager.get_color("status_offline")

static func status_label(status: int) -> String:
	match status:
		ClientModels.UserStatus.ONLINE:
			return "Online"
		ClientModels.UserStatus.IDLE:
			return "Idle"
		ClientModels.UserStatus.DND:
			return "Do Not Disturb"
		_:
			return "Offline"

static func user_to_dict(
	user: AccordUser,
	status: int = ClientModels.UserStatus.OFFLINE,
	cdn_url: String = "",
) -> Dictionary:
	var dname: String = str(user.display_name) if user.display_name else user.username

	var avatar_url = ClientModels._resolve_media_url(
		user.avatar, user.id, cdn_url, AccordCDN.avatar
	)
	var bio_str: String = str(user.bio) if user.bio != null else ""
	var banner_url = ClientModels._resolve_media_url(
		user.banner, user.id, cdn_url, AccordCDN.space_banner
	)

	var accent: int = 0
	if user.accent_color != null:
		accent = int(user.accent_color)

	return {
		"id": user.id,
		"display_name": dname,
		"username": user.username,
		"color": ClientModels._color_from_id(user.id),
		"status": status,
		"avatar": avatar_url,
		"is_admin": user.is_admin,
		"bio": bio_str,
		"banner": banner_url,
		"accent_color": accent,
		"flags": user.flags,
		"public_flags": user.public_flags,
		"created_at": user.created_at,
		"bot": user.bot,
		"mfa_enabled": user.mfa_enabled,
		"client_status": {},
		"activities": [],
	}

static func relationship_to_dict(
	rel: AccordRelationship, cdn_url: String = "",
	server_url: String = "", space_name: String = "",
) -> Dictionary:
	var user_dict: Dictionary = {}
	if rel.user != null:
		var status: int = ClientModels.UserStatus.OFFLINE
		if not rel.user_status.is_empty():
			status = _status_string_to_enum(rel.user_status)
		user_dict = user_to_dict(rel.user, status, cdn_url)
		# Carry through activities from the relationship response
		if not rel.user_activities.is_empty():
			user_dict["activities"] = rel.user_activities
	return {
		"id": rel.id,
		"user": user_dict,
		"type": rel.type,
		"since": rel.since,
		"server_url": server_url,
		"space_name": space_name,
		"available": true,
	}

## Build a relationship dict from a local friend book entry (unavailable friend).
static func friend_book_entry_to_dict(entry: Dictionary) -> Dictionary:
	var user_id: String = entry.get("user_id", "")
	var user_dict := {
		"id": user_id,
		"display_name": entry.get("display_name", "Unknown"),
		"username": entry.get("username", "unknown"),
		"color": ClientModels._color_from_id(user_id),
		"status": ClientModels.UserStatus.OFFLINE,
		"avatar": null,
		"is_admin": false,
		"bio": "",
		"banner": null,
		"accent_color": 0,
		"flags": 0,
		"public_flags": 0,
		"created_at": "",
		"bot": false,
		"mfa_enabled": false,
		"client_status": {},
		"activities": [],
	}
	return {
		"id": "",
		"user": user_dict,
		"type": entry.get("type", 1),
		"since": entry.get("since", ""),
		"server_url": entry.get("server_url", ""),
		"space_name": entry.get("space_name", ""),
		"available": false,
	}

static func format_activity(activity: Dictionary) -> String:
	var act_name: String = activity.get("name", "")
	if act_name.is_empty():
		return ""
	var act_type: String = str(activity.get("type", "playing")).to_lower()
	match act_type:
		"playing":
			return "Playing " + act_name
		"streaming":
			return "Streaming " + act_name
		"listening":
			return "Listening to " + act_name
		"watching":
			return "Watching " + act_name
		"competing":
			return "Competing in " + act_name
		"custom":
			var state_str: String = str(activity.get("state", ""))
			if not state_str.is_empty():
				return state_str
			return act_name
		_:
			return act_name

static func get_user_badges(flags: int) -> Array:
	var badges: Array = []
	for bit in USER_FLAGS:
		if flags & bit:
			badges.append(USER_FLAGS[bit])
	return badges
