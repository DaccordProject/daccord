## Member-related model converters: members, roles, voice states.

static func member_to_dict(
	member: AccordMember, user_cache: Dictionary,
	cdn_url: String = "",
) -> Dictionary:
	var user_dict: Dictionary = {}
	if user_cache.has(member.user_id):
		user_dict = user_cache[member.user_id].duplicate()
	else:
		user_dict = {
			"id": member.user_id,
			"display_name": "Unknown",
			"username": "unknown",
			"color": ClientModels._color_from_id(member.user_id),
			"status": ClientModels.UserStatus.OFFLINE,
			"avatar": null,
		}
	var nick_str: String = ""
	if member.nickname != null and not str(member.nickname).is_empty():
		nick_str = str(member.nickname)
		user_dict["display_name"] = nick_str
	user_dict["nickname"] = nick_str
	# Per-server member avatar overrides user avatar
	if member.avatar != null and not str(member.avatar).is_empty():
		var mav: String = str(member.avatar)
		if mav.begins_with("/"):
			user_dict["avatar"] = AccordCDN.resolve_path(mav, cdn_url)
		else:
			user_dict["avatar"] = AccordCDN.resolve_path(
				"/cdn/avatars/" + mav, cdn_url
			)
	user_dict["roles"] = member.roles.duplicate()
	user_dict["joined_at"] = member.joined_at
	user_dict["mute"] = member.mute
	user_dict["deaf"] = member.deaf
	var tout: String = ""
	if member.timed_out_until != null:
		tout = str(member.timed_out_until)
	user_dict["timed_out_until"] = tout
	return user_dict

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
			"color": ClientModels._color_from_id(state.user_id),
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
