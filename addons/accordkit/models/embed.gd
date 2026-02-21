class_name AccordEmbed
extends RefCounted

## Discord message embed with builder pattern.

var title = null
var type = null
var description = null
var url = null
var timestamp = null
var color = null
var footer = null
var image = null
var thumbnail = null
var author = null
var fields = null


static func from_dict(d: Dictionary) -> AccordEmbed:
	var e := AccordEmbed.new()
	e.title = d.get("title", null)
	e.type = d.get("type", null)
	e.description = d.get("description", null)
	e.url = d.get("url", null)
	e.timestamp = d.get("timestamp", null)
	e.color = d.get("color", null)
	e.footer = d.get("footer", null)
	e.image = d.get("image", null)
	e.thumbnail = d.get("thumbnail", null)
	e.author = d.get("author", null)
	e.fields = d.get("fields", null)
	return e


func to_dict() -> Dictionary:
	var d := {}
	if title != null:
		d["title"] = title
	if type != null:
		d["type"] = type
	if description != null:
		d["description"] = description
	if url != null:
		d["url"] = url
	if timestamp != null:
		d["timestamp"] = timestamp
	if color != null:
		d["color"] = color
	if footer != null:
		d["footer"] = footer
	if image != null:
		d["image"] = image
	if thumbnail != null:
		d["thumbnail"] = thumbnail
	if author != null:
		d["author"] = author
	if fields != null:
		d["fields"] = fields
	return d


static func build() -> AccordEmbed:
	return AccordEmbed.new()


func set_title(t: String) -> AccordEmbed:
	title = t
	return self


func set_description(desc: String) -> AccordEmbed:
	description = desc
	return self


func set_color(c: int) -> AccordEmbed:
	color = c
	return self


func set_url(u: String) -> AccordEmbed:
	url = u
	return self


func set_timestamp(ts: String) -> AccordEmbed:
	timestamp = ts
	return self


func add_field(field_name: String, value: String, inline: bool = false) -> AccordEmbed:
	if fields == null:
		fields = []
	fields.append({"name": field_name, "value": value, "inline": inline})
	return self


func set_footer(text: String, icon_url = null) -> AccordEmbed:
	footer = {"text": text}
	if icon_url != null:
		footer["icon_url"] = icon_url
	return self


func set_image(image_url: String) -> AccordEmbed:
	image = {"url": image_url}
	return self


func set_thumbnail(thumbnail_url: String) -> AccordEmbed:
	thumbnail = {"url": thumbnail_url}
	return self


func set_author(author_name: String, author_url = null, icon_url = null) -> AccordEmbed:
	author = {"name": author_name}
	if author_url != null:
		author["url"] = author_url
	if icon_url != null:
		author["icon_url"] = icon_url
	return self
