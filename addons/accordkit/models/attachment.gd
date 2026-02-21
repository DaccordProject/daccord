class_name AccordAttachment
extends RefCounted

## Discord message attachment.

var id: String
var filename: String = ""
var description = null
var content_type = null
var size: int = 0
var url: String = ""
var width = null
var height = null


static func from_dict(d: Dictionary) -> AccordAttachment:
	var a := AccordAttachment.new()
	a.id = str(d.get("id", ""))
	a.filename = d.get("filename", "")
	a.description = d.get("description", null)
	a.content_type = d.get("content_type", null)
	a.size = d.get("size", 0)
	a.url = d.get("url", "")
	a.width = d.get("width", null)
	a.height = d.get("height", null)
	return a


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"filename": filename,
		"size": size,
		"url": url,
	}
	if description != null:
		d["description"] = description
	if content_type != null:
		d["content_type"] = content_type
	if width != null:
		d["width"] = width
	if height != null:
		d["height"] = height
	return d
