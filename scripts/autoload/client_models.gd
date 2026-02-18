class_name ClientModels

## Converts AccordKit typed models into the dictionary shapes UI components expect.
## Also defines the shared enums that form the data contract between AccordKit and UI.

# Channel types
enum ChannelType { TEXT, VOICE, ANNOUNCEMENT, FORUM, CATEGORY }

# User statuses
enum UserStatus { ONLINE, IDLE, DND, OFFLINE }

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
	# Extract time portion
	var t_idx := iso.find("T")
	if t_idx == -1:
		return iso
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
	return "Today at %d:%s %s" % [hour, minute, am_pm]

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

	return {
		"id": user.id,
		"display_name": dname,
		"username": user.username,
		"color": _color_from_id(user.id),
		"status": status,
		"avatar": avatar_url,
	}

static func space_to_guild_dict(space: AccordSpace) -> Dictionary:
	var desc: String = ""
	if space.description != null:
		desc = str(space.description)
	var is_public: bool = "PUBLIC" in space.features or "public" in space.features
	return {
		"id": space.id,
		"name": space.name,
		"icon_color": _color_from_id(space.id),
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
	}
	if not topic_str.is_empty():
		d["topic"] = topic_str
	if channel.nsfw:
		d["nsfw"] = true
	return d

static func message_to_dict(msg: AccordMessage, user_cache: Dictionary) -> Dictionary:
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

	var embed_dict: Dictionary = {}
	if msg.embeds.size() > 0:
		var e: AccordEmbed = msg.embeds[0]
		embed_dict = {}
		if e.title != null:
			embed_dict["title"] = str(e.title)
		if e.description != null:
			embed_dict["description"] = str(e.description)
		if e.color != null:
			embed_dict["color"] = Color.hex(int(e.color))
		if e.footer != null and e.footer is Dictionary:
			embed_dict["footer"] = e.footer.get("text", "")

	var reply_to_str: String = ""
	if msg.reply_to != null:
		reply_to_str = str(msg.reply_to)

	var is_system: bool = msg.type != "default" and msg.type != "reply"

	return {
		"id": msg.id,
		"channel_id": msg.channel_id,
		"author": author_dict,
		"content": msg.content,
		"timestamp": _format_timestamp(msg.timestamp),
		"reactions": reactions_arr,
		"reply_to": reply_to_str,
		"embed": embed_dict,
		"system": is_system,
	}

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
	if channel.recipients != null and channel.recipients is Array and channel.recipients.size() > 0:
		var recipient: AccordUser = channel.recipients[0]
		if user_cache.has(recipient.id):
			user_dict = user_cache[recipient.id]
		else:
			user_dict = user_to_dict(recipient)
	else:
		user_dict = {
			"id": "",
			"display_name": str(channel.name) if channel.name != null else "DM",
			"username": "",
			"color": _color_from_id(channel.id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}

	return {
		"id": channel.id,
		"user": user_dict,
		"last_message": "",
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

static func markdown_to_bbcode(text: String) -> String:
	var result := text
	# Code blocks (``` ```)
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(?:\\w+\\n)?([\\s\\S]*?)```")
	result = code_block_regex.sub(result, "[code]$1[/code]", true)
	# Inline code
	var inline_code_regex := RegEx.new()
	inline_code_regex.compile("`([^`]+)`")
	result = inline_code_regex.sub(result, "[code]$1[/code]", true)
	# Strikethrough ~~text~~
	var strike_regex := RegEx.new()
	strike_regex.compile("~~(.+?)~~")
	result = strike_regex.sub(result, "[s]$1[/s]", true)
	# Underline __text__ (must come before bold to avoid conflict)
	var underline_regex := RegEx.new()
	underline_regex.compile("__(.+?)__")
	result = underline_regex.sub(result, "[u]$1[/u]", true)
	# Bold
	var bold_regex := RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	result = bold_regex.sub(result, "[b]$1[/b]", true)
	# Italic
	var italic_regex := RegEx.new()
	italic_regex.compile("\\*(.+?)\\*")
	result = italic_regex.sub(result, "[i]$1[/i]", true)
	# Spoilers ||text||
	var spoiler_regex := RegEx.new()
	spoiler_regex.compile("\\|\\|(.+?)\\|\\|")
	result = spoiler_regex.sub(
		result,
		"[bgcolor=#1e1f22][color=#1e1f22]$1[/color][/bgcolor]",
		true,
	)
	# Links
	var link_regex := RegEx.new()
	link_regex.compile("\\[(.+?)\\]\\((.+?)\\)")
	result = link_regex.sub(result, "[url=$2]$1[/url]", true)
	# Blockquotes (line-level: > text)
	var blockquote_regex := RegEx.new()
	blockquote_regex.compile("(?m)^> (.+)$")
	result = blockquote_regex.sub(
		result,
		"[indent][color=#8a8e94]$1[/color][/indent]",
		true,
	)
	return result
