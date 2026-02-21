class_name AccordCommand
extends RefCounted

## Discord application command.

var id: String
var application_id: String = ""
var space_id = null
var name: String = ""
var description: String = ""
var options = null
var type: String = "chat_input"


static func from_dict(d: Dictionary) -> AccordCommand:
	var c := AccordCommand.new()
	c.id = str(d.get("id", ""))
	c.application_id = str(d.get("application_id", ""))
	c.space_id = null
	var raw_space = d.get("space_id", d.get("guild_id", null))
	if raw_space != null:
		c.space_id = str(raw_space)
	c.name = d.get("name", "")
	c.description = d.get("description", "")
	c.options = d.get("options", null)
	c.type = d.get("type", "chat_input")
	return c


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"application_id": application_id,
		"name": name,
		"description": description,
		"type": type,
	}
	if space_id != null:
		d["space_id"] = space_id
	if options != null:
		d["options"] = options
	return d
