## Message-related model converters: messages, mentions, timestamps.

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

	# Extract time portion (UTC from server)
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
	var utc_hour := parts[0].to_int()
	var utc_minute := parts[1].to_int()

	# Compute UTC offset: get_unix_time_from_datetime_dict treats dicts as UTC, so the
	# difference between local and UTC dicts gives the offset in seconds.
	var sys_local: Dictionary = Time.get_datetime_dict_from_system(false)
	var sys_utc: Dictionary = Time.get_datetime_dict_from_system(true)
	var sys_local_unix: int = Time.get_unix_time_from_datetime_dict(sys_local)
	var sys_utc_unix: int = Time.get_unix_time_from_datetime_dict(sys_utc)
	var utc_offset: int = sys_local_unix - sys_utc_unix

	# Convert message UTC time to local by shifting its unix time.
	# Reading the shifted value back via get_datetime_dict_from_unix_time (which treats
	# its input as UTC) yields the correct local hour/minute/day values.
	var msg_dt: Dictionary = {
		"year": msg_year, "month": msg_month, "day": msg_day,
		"hour": utc_hour, "minute": utc_minute, "second": 0
	}
	var msg_utc_unix: int = Time.get_unix_time_from_datetime_dict(msg_dt)
	var msg_local: Dictionary = Time.get_datetime_dict_from_unix_time(
		msg_utc_unix + utc_offset
	)

	var local_hour: int = msg_local["hour"]
	var local_minute: String = "%02d" % msg_local["minute"]
	var am_pm := "AM"
	if local_hour >= 12:
		am_pm = "PM"
	if local_hour > 12:
		local_hour -= 12
	if local_hour == 0:
		local_hour = 12
	var time_str := "%d:%s %s" % [local_hour, local_minute, am_pm]

	# Compare to today/yesterday using local date
	if msg_year > 0:
		var local_y: int = msg_local["year"]
		var local_m: int = msg_local["month"]
		var local_d: int = msg_local["day"]
		var today_y: int = sys_local["year"]
		var today_m: int = sys_local["month"]
		var today_d: int = sys_local["day"]
		if local_y == today_y and local_m == today_m and local_d == today_d:
			return "Today at " + time_str
		# Yesterday in local time: shift sys_local_unix back 24 h and read as "UTC"
		var yesterday: Dictionary = Time.get_datetime_dict_from_unix_time(
			sys_local_unix - 86400
		)
		var y_y: int = yesterday["year"]
		var y_m: int = yesterday["month"]
		var y_d: int = yesterday["day"]
		if local_y == y_y and local_m == y_m and local_d == y_d:
			return "Yesterday at " + time_str
		return "%02d/%02d/%d %s" % [local_m, local_d, local_y, time_str]

	return "Today at " + time_str

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
			"color": ClientModels._color_from_id(msg.author_id),
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
		if e.author != null and e.author is Dictionary:
			ed["author"] = {
				"name": e.author.get("name", ""),
				"url": e.author.get("url", ""),
				"icon_url": e.author.get("icon_url", ""),
			}
		if e.fields != null and e.fields is Array:
			var fields_arr: Array = []
			for f in e.fields:
				if f is Dictionary:
					fields_arr.append({
						"name": f.get("name", ""),
						"value": f.get("value", ""),
						"inline": f.get("inline", false),
					})
			if not fields_arr.is_empty():
				ed["fields"] = fields_arr
		if e.url != null:
			ed["url"] = str(e.url)
		if e.type != null:
			ed["type"] = str(e.type)
		embeds_arr.append(ed)
	# First embed for backward compat
	var embed_dict: Dictionary = embeds_arr[0] if not embeds_arr.is_empty() else {}

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
	var message_type: String = msg.type if msg.type != null else "default"

	var mentions_arr: Array = []
	if msg.mentions is Array:
		mentions_arr = msg.mentions
	var mention_roles_arr: Array = []
	if msg.mention_roles is Array:
		mention_roles_arr = msg.mention_roles

	var thread_id_str: String = ""
	if msg.thread_id != null:
		thread_id_str = str(msg.thread_id)

	var last_reply_str: String = ""
	if msg.last_reply_at != null:
		last_reply_str = str(msg.last_reply_at)

	var title_str: String = ""
	if msg.title != null:
		title_str = str(msg.title)

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
		"message_type": message_type,
		"mentions": mentions_arr,
		"mention_everyone": msg.mention_everyone,
		"mention_roles": mention_roles_arr,
		"thread_id": thread_id_str,
		"reply_count": msg.reply_count,
		"last_reply_at": last_reply_str,
		"thread_participants": msg.thread_participants,
		"title": title_str,
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
