## Space-related model converters: spaces, channels, DMs, invites, emoji, sounds.

const UserModule := preload("res://scripts/client/client_models_user.gd")

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

static func space_to_dict(
	space: AccordSpace, cdn_url: String = ""
) -> Dictionary:
	var desc: String = str(space.description) if space.description != null else ""
	var is_public: bool = (
		space.public or "PUBLIC" in space.features or "public" in space.features
	)

	var icon_url = ClientModels._resolve_media_url(
		space.icon, space.id, cdn_url, AccordCDN.space_icon
	)

	return {
		"id": space.id,
		"name": space.name,
		"slug": space.slug,
		"icon_color": ClientModels._color_from_id(space.id),
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
		"nsfw_level": space.nsfw_level,
		"explicit_content_filter": space.explicit_content_filter,
		"rules_channel_id": (
			str(space.rules_channel_id)
			if space.rules_channel_id != null else ""
		),
		"system_channel_id": (
			str(space.system_channel_id)
			if space.system_channel_id != null else ""
		),
	}

static func channel_to_dict(channel: AccordChannel) -> Dictionary:
	var ch_type: int = _channel_type_to_enum(channel.type)
	var parent: String = ""
	if channel.parent_id != null:
		parent = str(channel.parent_id)
	var space_id: String = ""
	if channel.space_id != null:
		space_id = str(channel.space_id)
	var topic_str: String = ""
	if channel.topic != null:
		topic_str = str(channel.topic)

	var d := {
		"id": channel.id,
		"space_id": space_id,
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
	if channel.allow_anonymous_read:
		d["allow_anonymous_read"] = true
	# Include permission overwrites for admin UI
	if not channel.permission_overwrites.is_empty():
		var ow_list: Array = []
		for ow in channel.permission_overwrites:
			if ow is AccordPermissionOverwrite:
				ow_list.append(ow.to_dict())
			elif ow is Dictionary:
				ow_list.append(ow)
		d["permission_overwrites"] = ow_list
	return d

static func dm_channel_to_dict(
	channel: AccordChannel, user_cache: Dictionary,
) -> Dictionary:
	var user_dict: Dictionary = {}
	var all_recipients: Array = []
	var is_group: bool = false

	if channel.recipients is Array and not channel.recipients.is_empty():
		is_group = channel.recipients.size() > 1
		for recipient in channel.recipients:
			var r: AccordUser = recipient
			var rd: Dictionary
			if user_cache.has(r.id):
				rd = user_cache[r.id]
			else:
				rd = UserModule.user_to_dict(r)
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
				"color": ClientModels._color_from_id(channel.id),
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
			"color": ClientModels._color_from_id(channel.id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}

	var last_msg_id: String = ""
	if channel.last_message_id != null:
		last_msg_id = str(channel.last_message_id)

	var owner_id: String = str(channel.owner_id) \
		if channel.owner_id != null else ""
	var dm_name: String = str(channel.name) \
		if channel.name != null else ""

	return {
		"id": channel.id,
		"user": user_dict,
		"recipients": all_recipients,
		"is_group": is_group,
		"owner_id": owner_id,
		"name": dm_name,
		"last_message": "",
		"last_message_id": last_msg_id,
		"unread": false,
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
