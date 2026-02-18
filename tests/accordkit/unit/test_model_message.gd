extends GutTest


# =============================================================================
# AccordMessage
# =============================================================================

func test_message_from_dict_full() -> void:
	var d := {
		"id": "msg1",
		"channel_id": "ch1",
		"space_id": "sp1",
		"author_id": "u1",
		"content": "Hello!",
		"type": "default",
		"timestamp": "2024-06-01T12:00:00Z",
		"edited_at": "2024-06-01T13:00:00Z",
		"tts": false,
		"pinned": true,
		"mention_everyone": false,
		"mentions": ["u2", "u3"],
		"mention_roles": ["r1"],
		"flags": 4,
		"reply_to": "msg0",
	}
	var m := AccordMessage.from_dict(d)
	assert_eq(m.id, "msg1")
	assert_eq(m.channel_id, "ch1")
	assert_eq(m.space_id, "sp1")
	assert_eq(m.author_id, "u1")
	assert_eq(m.content, "Hello!")
	assert_true(m.pinned)
	assert_eq(m.edited_at, "2024-06-01T13:00:00Z")
	assert_eq(m.mentions.size(), 2)
	assert_eq(m.flags, 4)
	assert_eq(m.reply_to, "msg0")


func test_message_from_dict_author_as_dict() -> void:
	var d := {
		"id": "msg2",
		"author": {"id": "user42", "username": "bob"},
	}
	var m := AccordMessage.from_dict(d)
	assert_eq(m.author_id, "user42")


func test_message_from_dict_guild_id_alias() -> void:
	var d := {"id": "msg3", "guild_id": "g1"}
	var m := AccordMessage.from_dict(d)
	assert_eq(m.space_id, "g1")


func test_message_from_dict_minimal() -> void:
	var m := AccordMessage.from_dict({"id": "m1"})
	assert_eq(m.id, "m1")
	assert_eq(m.content, "")
	assert_null(m.space_id)
	assert_null(m.reactions)
	assert_null(m.reply_to)


func test_message_to_dict_roundtrip() -> void:
	var d := {
		"id": "msg10",
		"channel_id": "ch10",
		"author_id": "u10",
		"content": "test content",
		"type": "default",
		"timestamp": "2024-01-01T00:00:00Z",
		"tts": false,
		"pinned": false,
		"mention_everyone": false,
		"mentions": [],
		"mention_roles": [],
		"flags": 0,
	}
	var m := AccordMessage.from_dict(d)
	var out := m.to_dict()
	assert_eq(out["id"], "msg10")
	assert_eq(out["content"], "test content")


func test_message_to_dict_omits_null() -> void:
	var m := AccordMessage.from_dict({"id": "m"})
	var out := m.to_dict()
	assert_false(out.has("space_id"))
	assert_false(out.has("edited_at"))
	assert_false(out.has("reactions"))
	assert_false(out.has("reply_to"))
	assert_false(out.has("webhook_id"))


# =============================================================================
# AccordEmbed
# =============================================================================

func test_embed_from_dict_full() -> void:
	var d := {
		"title": "Embed Title",
		"type": "rich",
		"description": "Description",
		"url": "https://example.com",
		"color": 0xFF0000,
		"fields": [{"name": "F1", "value": "V1", "inline": true}],
		"footer": {"text": "Footer text"},
		"image": {"url": "https://example.com/img.png"},
		"thumbnail": {"url": "https://example.com/thumb.png"},
		"author": {"name": "Author"},
	}
	var e := AccordEmbed.from_dict(d)
	assert_eq(e.title, "Embed Title")
	assert_eq(e.description, "Description")
	assert_eq(e.color, 0xFF0000)
	assert_eq(e.fields.size(), 1)


func test_embed_from_dict_minimal() -> void:
	var e := AccordEmbed.from_dict({})
	assert_null(e.title)
	assert_null(e.description)
	assert_null(e.fields)


func test_embed_builder_pattern() -> void:
	var e := AccordEmbed.build() \
		.set_title("Test") \
		.set_description("Desc") \
		.set_color(0x00FF00) \
		.set_url("https://example.com") \
		.add_field("F1", "V1", true) \
		.add_field("F2", "V2") \
		.set_footer("Footer", "https://example.com/icon.png") \
		.set_image("https://example.com/img.png") \
		.set_thumbnail("https://example.com/thumb.png") \
		.set_author("Author", "https://example.com", "https://example.com/av.png")
	assert_eq(e.title, "Test")
	assert_eq(e.description, "Desc")
	assert_eq(e.color, 0x00FF00)
	assert_eq(e.fields.size(), 2)
	assert_eq(e.footer["text"], "Footer")
	assert_eq(e.footer["icon_url"], "https://example.com/icon.png")
	assert_eq(e.image["url"], "https://example.com/img.png")
	assert_eq(e.author["name"], "Author")
	assert_eq(e.author["url"], "https://example.com")
	assert_eq(e.author["icon_url"], "https://example.com/av.png")


func test_embed_to_dict_omits_null() -> void:
	var e := AccordEmbed.from_dict({})
	var out := e.to_dict()
	assert_eq(out.size(), 0)


func test_embed_to_dict_roundtrip() -> void:
	var e := AccordEmbed.build().set_title("T").set_color(123)
	var out := e.to_dict()
	assert_eq(out["title"], "T")
	assert_eq(out["color"], 123)
	assert_false(out.has("description"))


# =============================================================================
# AccordAttachment
# =============================================================================

func test_attachment_from_dict_full() -> void:
	var d := {
		"id": "att1",
		"filename": "image.png",
		"description": "A picture",
		"content_type": "image/png",
		"size": 12345,
		"url": "https://cdn.example.com/image.png",
		"width": 800,
		"height": 600,
	}
	var a := AccordAttachment.from_dict(d)
	assert_eq(a.id, "att1")
	assert_eq(a.filename, "image.png")
	assert_eq(a.description, "A picture")
	assert_eq(a.content_type, "image/png")
	assert_eq(a.size, 12345)
	assert_eq(a.width, 800)
	assert_eq(a.height, 600)


func test_attachment_from_dict_minimal() -> void:
	var a := AccordAttachment.from_dict({"id": "a1"})
	assert_eq(a.id, "a1")
	assert_eq(a.filename, "")
	assert_null(a.description)
	assert_null(a.content_type)
	assert_eq(a.size, 0)


func test_attachment_to_dict_omits_null() -> void:
	var a := AccordAttachment.from_dict({"id": "a", "filename": "f.txt", "size": 10, "url": "x"})
	var out := a.to_dict()
	assert_false(out.has("description"))
	assert_false(out.has("content_type"))
	assert_false(out.has("width"))
	assert_false(out.has("height"))


# =============================================================================
# AccordReaction
# =============================================================================

func test_reaction_from_dict() -> void:
	var d := {
		"emoji": {"id": "e1", "name": "fire"},
		"count": 5,
		"me": true,
	}
	var r := AccordReaction.from_dict(d)
	assert_eq(r.emoji["id"], "e1")
	assert_eq(r.emoji["name"], "fire")
	assert_eq(r.count, 5)
	assert_true(r.includes_me)


func test_reaction_from_dict_defaults() -> void:
	var r := AccordReaction.from_dict({})
	assert_eq(r.count, 0)
	assert_false(r.includes_me)


func test_reaction_to_dict() -> void:
	var r := AccordReaction.from_dict({"emoji": {"name": "x"}, "count": 3})
	var out := r.to_dict()
	assert_eq(out["count"], 3)
	assert_eq(out["emoji"]["name"], "x")
