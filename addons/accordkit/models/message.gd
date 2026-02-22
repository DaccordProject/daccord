class_name AccordMessage
extends RefCounted

## Discord message object.

var id: String
var channel_id: String = ""
var space_id = null
var author_id: String = ""
var content: String = ""
var type: String = "default"
var timestamp: String = ""
var edited_at = null
var tts: bool = false
var pinned: bool = false
var mention_everyone: bool = false
var mentions: Array = []
var mention_roles: Array = []
var attachments: Array = []
var embeds: Array = []
var reactions = null
var reply_to = null
var flags: int = 0
var components = null
var sticker_ids = null
var webhook_id = null
var thread_id = null
var reply_count: int = 0
var last_reply_at = null
var thread_participants: Array = []
var title = null


static func from_dict(d: Dictionary) -> AccordMessage:
	var m := AccordMessage.new()
	m.id = str(d.get("id", ""))
	m.channel_id = str(d.get("channel_id", ""))
	m.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		m.space_id = str(raw_space)

	var raw_author = d.get("author", null)
	if raw_author is Dictionary:
		m.author_id = str(raw_author.get("id", ""))
	else:
		m.author_id = str(d.get("author_id", ""))

	m.content = d.get("content", "")
	m.type = d.get("type", "default")
	m.timestamp = d.get("timestamp", "")
	m.edited_at = d.get("edited_at", d.get("edited_timestamp", null))
	m.tts = d.get("tts", false)
	m.pinned = d.get("pinned", false)
	m.mention_everyone = d.get("mention_everyone", false)

	m.mentions = []
	var raw_mentions = d.get("mentions", [])
	for u in raw_mentions:
		if u is Dictionary:
			m.mentions.append(str(u.get("id", "")))
		elif u is String:
			m.mentions.append(u)

	m.mention_roles = []
	var raw_roles = d.get("mention_roles", [])
	for r in raw_roles:
		m.mention_roles.append(str(r))

	m.attachments = []
	var raw_attachments = d.get("attachments", [])
	for a in raw_attachments:
		if a is Dictionary:
			m.attachments.append(AccordAttachment.from_dict(a))

	m.embeds = []
	var raw_embeds = d.get("embeds", [])
	for e in raw_embeds:
		if e is Dictionary:
			m.embeds.append(AccordEmbed.from_dict(e))

	m.reactions = null
	var raw_reactions = d.get("reactions", null)
	if raw_reactions is Array:
		m.reactions = []
		for r in raw_reactions:
			if r is Dictionary:
				m.reactions.append(AccordReaction.from_dict(r))

	m.reply_to = null
	var raw_ref = d.get("reply_to", d.get("message_reference", null))
	if raw_ref is Dictionary:
		var ref_id = raw_ref.get("message_id", null)
		if ref_id != null:
			m.reply_to = str(ref_id)
	elif raw_ref is String:
		m.reply_to = raw_ref

	m.flags = d.get("flags", 0)
	m.components = d.get("components", null)

	m.sticker_ids = null
	var raw_stickers = d.get("sticker_ids", d.get("sticker_items", null))
	if raw_stickers is Array:
		m.sticker_ids = []
		for s in raw_stickers:
			if s is Dictionary:
				m.sticker_ids.append(str(s.get("id", "")))
			else:
				m.sticker_ids.append(str(s))

	m.webhook_id = null
	var raw_webhook = d.get("webhook_id", null)
	if raw_webhook != null:
		m.webhook_id = str(raw_webhook)

	m.thread_id = null
	var raw_thread = d.get("thread_id", null)
	if raw_thread != null:
		m.thread_id = str(raw_thread)

	m.reply_count = d.get("reply_count", 0)

	m.last_reply_at = d.get("last_reply_at", null)

	m.thread_participants = []
	var raw_participants = d.get("thread_participants", [])
	for p in raw_participants:
		m.thread_participants.append(str(p))

	m.title = d.get("title", null)

	return m


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"channel_id": channel_id,
		"author_id": author_id,
		"content": content,
		"type": type,
		"timestamp": timestamp,
		"tts": tts,
		"pinned": pinned,
		"mention_everyone": mention_everyone,
		"mentions": mentions,
		"mention_roles": mention_roles,
		"flags": flags,
	}

	var attachment_dicts := []
	for a in attachments:
		if a is AccordAttachment:
			attachment_dicts.append(a.to_dict())
	d["attachments"] = attachment_dicts

	var embed_dicts := []
	for e in embeds:
		if e is AccordEmbed:
			embed_dicts.append(e.to_dict())
	d["embeds"] = embed_dicts

	if space_id != null:
		d["space_id"] = space_id
	if edited_at != null:
		d["edited_at"] = edited_at
	if reactions != null:
		var reaction_dicts := []
		for r in reactions:
			if r is AccordReaction:
				reaction_dicts.append(r.to_dict())
		d["reactions"] = reaction_dicts
	if reply_to != null:
		d["reply_to"] = reply_to
	if components != null:
		d["components"] = components
	if sticker_ids != null:
		d["sticker_ids"] = sticker_ids
	if webhook_id != null:
		d["webhook_id"] = webhook_id
	if thread_id != null:
		d["thread_id"] = thread_id
	if reply_count > 0:
		d["reply_count"] = reply_count
	if last_reply_at != null:
		d["last_reply_at"] = last_reply_at
	if thread_participants.size() > 0:
		d["thread_participants"] = thread_participants
	if title != null:
		d["title"] = title
	return d
