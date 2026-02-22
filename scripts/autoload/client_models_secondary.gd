## Secondary model converters for less frequently modified models.
## Extracted from ClientModels to reduce file size.
## Loaded via preload() from ClientModels — no class_name needed.

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

static func role_to_dict(role: AccordRole) -> Dictionary:
	return {
		"id": role.id,
		"name": role.name,
		"color": role.color,
		"hoist": role.hoist,
		"position": role.position,
		"permissions": role.permissions,
		"managed": role.managed,
		"mentionable": role.mentionable,
	}

static func invite_to_dict(invite: AccordInvite) -> Dictionary:
	var inviter: String = ""
	if invite.inviter_id != null:
		inviter = str(invite.inviter_id)
	var max_uses_val: int = 0
	if invite.max_uses != null:
		max_uses_val = int(invite.max_uses)
	var max_age_val: int = 0
	if invite.max_age != null:
		max_age_val = int(invite.max_age)
	var expires: String = ""
	if invite.expires_at != null:
		expires = str(invite.expires_at)
	return {
		"code": invite.code,
		"space_id": invite.space_id,
		"channel_id": invite.channel_id,
		"inviter_id": inviter,
		"max_uses": max_uses_val,
		"uses": invite.uses,
		"max_age": max_age_val,
		"temporary": invite.temporary,
		"created_at": invite.created_at,
		"expires_at": expires,
	}

static func emoji_to_dict(emoji: AccordEmoji) -> Dictionary:
	var eid: String = ""
	if emoji.id != null:
		eid = str(emoji.id)
	var creator: String = ""
	if emoji.creator_id != null:
		creator = str(emoji.creator_id)
	return {
		"id": eid,
		"name": emoji.name,
		"animated": emoji.animated,
		"role_ids": emoji.role_ids,
		"creator_id": creator,
	}

static func sound_to_dict(sound: AccordSound) -> Dictionary:
	var sid: String = ""
	if sound.id != null:
		sid = str(sound.id)
	var creator: String = ""
	if sound.creator_id != null:
		creator = str(sound.creator_id)
	return {
		"id": sid,
		"name": sound.name,
		"audio_url": sound.audio_url,
		"volume": sound.volume,
		"creator_id": creator,
		"created_at": sound.created_at,
		"updated_at": sound.updated_at,
	}

static func is_user_mentioned(
	data: Dictionary, user_id: String, user_roles: Array,
) -> bool:
	if user_id.is_empty():
		return false
	var mentions: Array = data.get("mentions", [])
	if user_id in mentions:
		return true
	if data.get("mention_everyone", false):
		if not Config.get_suppress_everyone():
			return true
	var mention_roles: Array = data.get("mention_roles", [])
	for role_id in mention_roles:
		if role_id in user_roles:
			return true
	return false

static func get_user_badges(flags: int) -> Array:
	var badges: Array = []
	for bit in USER_FLAGS:
		if flags & bit:
			badges.append(USER_FLAGS[bit])
	return badges
