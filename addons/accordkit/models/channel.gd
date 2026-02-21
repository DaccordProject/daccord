class_name AccordChannel
extends RefCounted

## Discord channel object.

var id: String
var type: String = "text"
var space_id = null
var name = null
var topic = null
var position = null
var parent_id = null
var nsfw: bool = false
var rate_limit = null
var bitrate = null
var user_limit = null
var recipients = null
var owner_id = null
var last_message_id = null
var permission_overwrites: Array = []
var archived = null
var auto_archive_after = null
var created_at: String = ""


static func from_dict(d: Dictionary) -> AccordChannel:
	var c := AccordChannel.new()
	c.id = str(d.get("id", ""))
	c.type = d.get("type", "text")
	c.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		c.space_id = str(raw_space)
	c.name = d.get("name", null)
	c.topic = d.get("topic", null)
	c.position = d.get("position", null)
	c.parent_id = null
	var raw_parent = d.get("parent_id", null)
	if raw_parent != null:
		c.parent_id = str(raw_parent)
	c.nsfw = d.get("nsfw", false)
	c.rate_limit = d.get("rate_limit", d.get("rate_limit_per_user", null))
	c.bitrate = d.get("bitrate", null)
	c.user_limit = d.get("user_limit", null)

	c.recipients = null
	var raw_recipients = d.get("recipients", null)
	if raw_recipients is Array:
		c.recipients = []
		for r in raw_recipients:
			if r is Dictionary:
				c.recipients.append(AccordUser.from_dict(r))

	c.owner_id = null
	var raw_owner = d.get("owner_id", null)
	if raw_owner != null:
		c.owner_id = str(raw_owner)
	c.last_message_id = null
	var raw_last = d.get("last_message_id", null)
	if raw_last != null:
		c.last_message_id = str(raw_last)

	c.permission_overwrites = []
	var raw_overwrites = d.get("permission_overwrites", [])
	for o in raw_overwrites:
		if o is Dictionary:
			c.permission_overwrites.append(AccordPermissionOverwrite.from_dict(o))

	c.archived = d.get("archived", null)
	c.auto_archive_after = d.get("auto_archive_after", d.get("auto_archive_duration", null))
	c.created_at = d.get("created_at", "")
	return c


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"type": type,
		"nsfw": nsfw,
		"created_at": created_at,
	}

	var overwrite_dicts := []
	for o in permission_overwrites:
		if o is AccordPermissionOverwrite:
			overwrite_dicts.append(o.to_dict())
	d["permission_overwrites"] = overwrite_dicts

	if space_id != null:
		d["space_id"] = space_id
	if name != null:
		d["name"] = name
	if topic != null:
		d["topic"] = topic
	if position != null:
		d["position"] = position
	if parent_id != null:
		d["parent_id"] = parent_id
	if rate_limit != null:
		d["rate_limit"] = rate_limit
	if bitrate != null:
		d["bitrate"] = bitrate
	if user_limit != null:
		d["user_limit"] = user_limit
	if recipients != null:
		var recipient_dicts := []
		for r in recipients:
			if r is AccordUser:
				recipient_dicts.append(r.to_dict())
		d["recipients"] = recipient_dicts
	if owner_id != null:
		d["owner_id"] = owner_id
	if last_message_id != null:
		d["last_message_id"] = last_message_id
	if archived != null:
		d["archived"] = archived
	if auto_archive_after != null:
		d["auto_archive_after"] = auto_archive_after
	return d
