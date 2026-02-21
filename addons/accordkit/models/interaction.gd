class_name AccordInteraction
extends RefCounted

## Discord interaction object.

var id: String
var application_id: String = ""
var type: String = "command"
var data = null
var space_id = null
var channel_id = null
var member_id = null
var user_id = null
var token: String = ""
var message = null
var locale = null


static func from_dict(d: Dictionary) -> AccordInteraction:
	var i := AccordInteraction.new()
	i.id = str(d.get("id", ""))
	i.application_id = str(d.get("application_id", ""))
	i.type = d.get("type", "command")
	i.data = d.get("data", null)

	i.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		i.space_id = str(raw_space)

	i.channel_id = null
	var raw_channel = d.get("channel_id", null)
	if raw_channel != null:
		i.channel_id = str(raw_channel)

	i.member_id = null
	var raw_member = d.get("member", null)
	if raw_member is Dictionary:
		var member_user = raw_member.get("user", null)
		if member_user is Dictionary:
			i.member_id = str(member_user.get("id", ""))
	elif d.has("member_id"):
		var raw_mid = d.get("member_id", null)
		if raw_mid != null:
			i.member_id = str(raw_mid)

	i.user_id = null
	var raw_user = d.get("user", null)
	if raw_user is Dictionary:
		i.user_id = str(raw_user.get("id", ""))
	elif d.has("user_id"):
		var raw_uid = d.get("user_id", null)
		if raw_uid != null:
			i.user_id = str(raw_uid)

	i.token = d.get("token", "")

	i.message = null
	var raw_message = d.get("message", null)
	if raw_message is Dictionary:
		i.message = AccordMessage.from_dict(raw_message)

	i.locale = d.get("locale", null)
	return i


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"application_id": application_id,
		"type": type,
		"token": token,
	}
	if data != null:
		d["data"] = data
	if space_id != null:
		d["space_id"] = space_id
	if channel_id != null:
		d["channel_id"] = channel_id
	if member_id != null:
		d["member_id"] = member_id
	if user_id != null:
		d["user_id"] = user_id
	if message != null:
		if message is AccordMessage:
			d["message"] = message.to_dict()
		else:
			d["message"] = message
	if locale != null:
		d["locale"] = locale
	return d
