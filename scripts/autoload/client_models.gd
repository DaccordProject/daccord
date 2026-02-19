class_name ClientModels

## Converts AccordKit typed models into the dictionary shapes UI components expect.
## Also defines the shared enums that form the data contract between AccordKit and UI.

# Channel types
enum ChannelType { TEXT, VOICE, ANNOUNCEMENT, FORUM, CATEGORY }

# User statuses
enum UserStatus { ONLINE, IDLE, DND, OFFLINE }

## Known user flag bits and their labels.
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

# Custom emoji caches — populated by Client when custom emoji are fetched.
# Maps emoji_name -> local cache path (user://emoji_cache/{id}.png)
static var custom_emoji_paths: Dictionary = {}
# Maps emoji_name -> Texture2D (in-memory for reaction pills)
static var custom_emoji_textures: Dictionary = {}

static var _hsv_colors := [
	Color.from_hsv(0.0, 0.7, 0.9),
	Color.from_hsv(0.08, 0.7, 0.9),
	Color.from_hsv(0.16, 0.7, 0.9),
	Color.from_hsv(0.28, 0.7, 0.9),
	Color.from_hsv(0.45, 0.7, 0.9),
	Color.from_hsv(0.55, 0.7, 0.9),
	Color.from_hsv(0.65, 0.7, 0.9),
	Color.from_hsv(0.75, 0.7, 0.9),
	Color.from_hsv(0.85, 0.7, 0.9),
	Color.from_hsv(0.95, 0.7, 0.9),
]

static func _color_from_id(id: String) -> Color:
	var idx := id.hash() % _hsv_colors.size()
	if idx < 0:
		idx += _hsv_colors.size()
	return _hsv_colors[idx]

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
		UserStatus.ONLINE:
			return Color(0.231, 0.647, 0.365)
		UserStatus.IDLE:
			return Color(0.98, 0.659, 0.157)
		UserStatus.DND:
			return Color(0.929, 0.259, 0.271)
		_:
			return Color(0.58, 0.608, 0.643)

static func status_label(status: int) -> String:
	match status:
		UserStatus.ONLINE:
			return "Online"
		UserStatus.IDLE:
			return "Idle"
		UserStatus.DND:
			return "Do Not Disturb"
		_:
			return "Offline"

static func _channel_type_to_enum(type_str: String) -> int:
	match type_str:
		"text":
			return ClientModels.ChannelType.TEXT
		"voice":
			return ClientModels.ChannelType.VOICE
		"category":
			return ClientModels.ChannelType.CATEGORY
		"announcement":
			return ClientModels.ChannelType.ANNOUNCEMENT
		"forum":
			return ClientModels.ChannelType.FORUM
		_:
			return ClientModels.ChannelType.TEXT

static func _format_timestamp(iso: String) -> String:
	if iso.is_empty():
		return ""
	# Parse ISO 8601 timestamp like "2025-05-10T14:30:00Z" or "2025-05-10T14:30:00.000Z"
	var t_idx := iso.find("T")
	if t_idx == -1:
		return iso

	# Parse date portion
	var date_part := iso.substr(0, t_idx)
	var date_parts := date_part.split("-")
	var msg_year := 0
	var msg_month := 0
	var msg_day := 0
	if date_parts.size() >= 3:
		msg_year = date_parts[0].to_int()
		msg_month = date_parts[1].to_int()
		msg_day = date_parts[2].to_int()

	# Extract time portion
	var time_part := iso.substr(t_idx + 1)
	# Strip timezone suffix
	for suffix in ["Z", "+", "-"]:
		var s_idx := time_part.find(suffix)
		if s_idx != -1:
			time_part = time_part.substr(0, s_idx)
	# Strip milliseconds
	var dot_idx := time_part.find(".")
	if dot_idx != -1:
		time_part = time_part.substr(0, dot_idx)
	# time_part is now "HH:MM:SS"
	var parts := time_part.split(":")
	if parts.size() < 2:
		return iso
	var hour := parts[0].to_int()
	var minute := parts[1]
	var am_pm := "AM"
	if hour >= 12:
		am_pm = "PM"
	if hour > 12:
		hour -= 12
	if hour == 0:
		hour = 12
	var time_str := "%d:%s %s" % [hour, minute, am_pm]

	# Compare to today/yesterday using UTC
	if msg_year > 0:
		var now: Dictionary = Time.get_datetime_dict_from_system(true)
		var today_y: int = now["year"]
		var today_m: int = now["month"]
		var today_d: int = now["day"]
		if msg_year == today_y and msg_month == today_m and msg_day == today_d:
			return "Today at " + time_str
		# Check yesterday
		var yesterday: Dictionary = Time.get_datetime_dict_from_unix_time(
			Time.get_unix_time_from_system() - 86400
		)
		var y_y: int = yesterday["year"]
		var y_m: int = yesterday["month"]
		var y_d: int = yesterday["day"]
		if msg_year == y_y and msg_month == y_m and msg_day == y_d:
			return "Yesterday at " + time_str
		return "%02d/%02d/%d %s" % [msg_month, msg_day, msg_year, time_str]

	return "Today at " + time_str

static func user_to_dict(
	user: AccordUser,
	status: int = ClientModels.UserStatus.OFFLINE,
	cdn_url: String = "",
) -> Dictionary:
	var dname: String = ""
	if user.display_name != null:
		dname = str(user.display_name)
	if dname.is_empty():
		dname = user.username

	var avatar_url = null
	if user.avatar != null and not str(user.avatar).is_empty():
		avatar_url = AccordCDN.avatar(user.id, str(user.avatar), "png", cdn_url)

	var bio_str: String = ""
	if user.bio != null:
		bio_str = str(user.bio)

	var banner_url = null
	if user.banner != null and not str(user.banner).is_empty():
		banner_url = AccordCDN.space_banner(
			user.id, str(user.banner), "png", cdn_url
		)

	var accent: int = 0
	if user.accent_color != null:
		accent = int(user.accent_color)

	return {
		"id": user.id,
		"display_name": dname,
		"username": user.username,
		"color": _color_from_id(user.id),
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
		"client_status": {},
		"activities": [],
	}

static func space_to_guild_dict(
	space: AccordSpace, cdn_url: String = ""
) -> Dictionary:
	var desc: String = ""
	if space.description != null:
		desc = str(space.description)
	var is_public: bool = "PUBLIC" in space.features or "public" in space.features

	var icon_url = null
	if space.icon != null and not str(space.icon).is_empty():
		icon_url = AccordCDN.space_icon(
			space.id, str(space.icon), "png", cdn_url
		)

	return {
		"id": space.id,
		"name": space.name,
		"icon_color": _color_from_id(space.id),
		"icon": icon_url,
		"folder": "",
		"unread": false,
		"mentions": 0,
		"owner_id": space.owner_id,
		"description": desc,
		"verification_level": space.verification_level,
		"default_notifications": space.default_notifications,
		"preferred_locale": space.preferred_locale,
		"public": is_public,
	}

static func channel_to_dict(channel: AccordChannel) -> Dictionary:
	var ch_type: int = _channel_type_to_enum(channel.type)
	var parent: String = ""
	if channel.parent_id != null:
		parent = str(channel.parent_id)
	var guild_id: String = ""
	if channel.space_id != null:
		guild_id = str(channel.space_id)
	var topic_str: String = ""
	if channel.topic != null:
		topic_str = str(channel.topic)

	var d := {
		"id": channel.id,
		"guild_id": guild_id,
		"name": str(channel.name) if channel.name != null else "",
		"type": ch_type,
		"parent_id": parent,
		"unread": false,
		"voice_users": 0,
	}
	if channel.position != null:
		d["position"] = channel.position
	if not topic_str.is_empty():
		d["topic"] = topic_str
	if channel.nsfw:
		d["nsfw"] = true
	# Include permission overwrites for admin UI
	if channel.permission_overwrites.size() > 0:
		var ow_list: Array = []
		for ow in channel.permission_overwrites:
			if ow is AccordPermissionOverwrite:
				ow_list.append(ow.to_dict())
			elif ow is Dictionary:
				ow_list.append(ow)
		d["permission_overwrites"] = ow_list
	return d

static func message_to_dict(
	msg: AccordMessage, user_cache: Dictionary,
	cdn_url: String = "",
) -> Dictionary:
	var author_dict: Dictionary = {}
	if user_cache.has(msg.author_id):
		author_dict = user_cache[msg.author_id]
	else:
		author_dict = {
			"id": msg.author_id,
			"display_name": "Unknown",
			"username": "unknown",
			"color": _color_from_id(msg.author_id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}

	var reactions_arr: Array = []
	if msg.reactions != null and msg.reactions is Array:
		for r in msg.reactions:
			var reaction: AccordReaction = r
			reactions_arr.append({
				"emoji": reaction.emoji.get("name", ""),
				"count": reaction.count,
				"active": reaction.includes_me,
			})

	# Convert all embeds
	var embeds_arr: Array = []
	for e in msg.embeds:
		var ed: Dictionary = {}
		if e.title != null:
			ed["title"] = str(e.title)
		if e.description != null:
			ed["description"] = str(e.description)
		if e.color != null:
			ed["color"] = Color.hex(int(e.color))
		if e.footer != null and e.footer is Dictionary:
			ed["footer"] = e.footer.get("text", "")
		if e.image != null and e.image is Dictionary:
			ed["image"] = e.image.get("url", "")
		if e.thumbnail != null and e.thumbnail is Dictionary:
			ed["thumbnail"] = e.thumbnail.get("url", "")
		embeds_arr.append(ed)
	# First embed for backward compat
	var embed_dict: Dictionary = embeds_arr[0] if embeds_arr.size() > 0 else {}

	# Convert attachments
	var attachments_arr: Array = []
	for a in msg.attachments:
		var att: AccordAttachment = a
		var att_url: String = att.url
		if not att_url.is_empty() and not att_url.begins_with("http"):
			att_url = AccordCDN.attachment(
				msg.channel_id, att.id, att.filename, cdn_url
			)
		var att_dict := {
			"id": att.id,
			"filename": att.filename,
			"size": att.size,
			"url": att_url,
		}
		if att.content_type != null:
			att_dict["content_type"] = str(att.content_type)
		if att.width != null:
			att_dict["width"] = att.width
		if att.height != null:
			att_dict["height"] = att.height
		attachments_arr.append(att_dict)

	var reply_to_str: String = ""
	if msg.reply_to != null:
		reply_to_str = str(msg.reply_to)

	var is_system: bool = msg.type != "default" and msg.type != "reply"

	var mentions_arr: Array = []
	if msg.mentions is Array:
		mentions_arr = msg.mentions
	var mention_roles_arr: Array = []
	if msg.mention_roles is Array:
		mention_roles_arr = msg.mention_roles

	return {
		"id": msg.id,
		"channel_id": msg.channel_id,
		"author": author_dict,
		"content": msg.content,
		"timestamp": _format_timestamp(msg.timestamp),
		"edited": msg.edited_at != null,
		"reactions": reactions_arr,
		"reply_to": reply_to_str,
		"embed": embed_dict,
		"embeds": embeds_arr,
		"attachments": attachments_arr,
		"system": is_system,
		"mentions": mentions_arr,
		"mention_everyone": msg.mention_everyone,
		"mention_roles": mention_roles_arr,
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

static func member_to_dict(member: AccordMember, user_cache: Dictionary) -> Dictionary:
	var user_dict: Dictionary = {}
	if user_cache.has(member.user_id):
		user_dict = user_cache[member.user_id].duplicate()
	else:
		user_dict = {
			"id": member.user_id,
			"display_name": "Unknown",
			"username": "unknown",
			"color": _color_from_id(member.user_id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}
	if member.nickname != null and not str(member.nickname).is_empty():
		user_dict["display_name"] = str(member.nickname)
	user_dict["roles"] = member.roles.duplicate()
	user_dict["joined_at"] = member.joined_at
	return user_dict

static func dm_channel_to_dict(channel: AccordChannel, user_cache: Dictionary) -> Dictionary:
	var user_dict: Dictionary = {}
	var all_recipients: Array = []
	var is_group: bool = false

	if channel.recipients != null \
			and channel.recipients is Array \
			and channel.recipients.size() > 0:
		is_group = channel.recipients.size() > 1
		for recipient in channel.recipients:
			var r: AccordUser = recipient
			var rd: Dictionary
			if user_cache.has(r.id):
				rd = user_cache[r.id]
			else:
				rd = user_to_dict(r)
			all_recipients.append(rd)
		# Primary user dict is first recipient (1:1) or
		# a combined entry (group)
		if is_group:
			var names: Array = []
			for rd in all_recipients:
				names.append(rd.get("display_name", "Unknown"))
			user_dict = {
				"id": "",
				"display_name": ", ".join(names),
				"username": "",
				"color": _color_from_id(channel.id),
				"status": ClientModels.UserStatus.OFFLINE,
				"avatar": null,
			}
		else:
			user_dict = all_recipients[0]
	else:
		user_dict = {
			"id": "",
			"display_name": str(channel.name) \
				if channel.name != null else "DM",
			"username": "",
			"color": _color_from_id(channel.id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}

	var last_msg_id: String = ""
	if channel.last_message_id != null:
		last_msg_id = str(channel.last_message_id)

	return {
		"id": channel.id,
		"user": user_dict,
		"recipients": all_recipients,
		"is_group": is_group,
		"last_message": "",
		"last_message_id": last_msg_id,
		"unread": false,
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

static func voice_state_to_dict(
	state: AccordVoiceState, user_cache: Dictionary,
) -> Dictionary:
	var user_dict: Dictionary = {}
	if user_cache.has(state.user_id):
		user_dict = user_cache[state.user_id]
	else:
		user_dict = {
			"id": state.user_id,
			"display_name": "Unknown",
			"username": "unknown",
			"color": _color_from_id(state.user_id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}
	var channel_id: String = ""
	if state.channel_id != null:
		channel_id = str(state.channel_id)
	return {
		"user_id": state.user_id,
		"channel_id": channel_id,
		"session_id": state.session_id,
		"self_mute": state.self_mute,
		"self_deaf": state.self_deaf,
		"self_video": state.self_video,
		"self_stream": state.self_stream,
		"mute": state.mute,
		"deaf": state.deaf,
		"user": user_dict,
	}

static func markdown_to_bbcode(text: String) -> String:
	return ClientMarkdown.markdown_to_bbcode(text)

static func get_user_badges(flags: int) -> Array:
	var badges: Array = []
	for bit in USER_FLAGS:
		if flags & bit:
			badges.append(USER_FLAGS[bit])
	return badges
