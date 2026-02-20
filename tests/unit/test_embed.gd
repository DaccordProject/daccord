extends GutTest

var embed_node: PanelContainer


func before_each() -> void:
	embed_node = load("res://scenes/messages/embed.tscn").instantiate()
	add_child(embed_node)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(embed_node):
		embed_node.queue_free()
		await get_tree().process_frame


# --- setup with empty data ---

func test_setup_empty_hides() -> void:
	embed_node.setup({})
	assert_false(embed_node.visible)


# --- setup with title only ---

func test_setup_title_only() -> void:
	embed_node.setup({"title": "Hello"})
	assert_true(embed_node.visible)
	assert_true(embed_node.title_rtl.visible)
	assert_string_contains(embed_node.title_rtl.text, "Hello")
	assert_false(embed_node.author_row.visible)
	assert_false(embed_node.fields_container.visible)
	assert_false(embed_node.image_rect.visible)
	assert_false(embed_node.thumbnail_rect.visible)
	assert_false(embed_node.footer_label.visible)


# --- setup with title + URL ---

func test_setup_title_with_url() -> void:
	embed_node.setup({"title": "Click Me", "url": "https://example.com"})
	assert_true(embed_node.title_rtl.visible)
	assert_string_contains(embed_node.title_rtl.text, "url=https://example.com")
	assert_string_contains(embed_node.title_rtl.text, "Click Me")


# --- setup with description ---

func test_setup_description_only() -> void:
	embed_node.setup({"description": "Some text"})
	assert_true(embed_node.visible)
	assert_true(embed_node.description_rtl.visible)
	assert_false(embed_node.title_rtl.visible)


# --- setup with author ---

func test_setup_with_author() -> void:
	embed_node.setup({
		"title": "Test",
		"author": {"name": "Author", "url": "https://author.com", "icon_url": ""},
	})
	assert_true(embed_node.author_row.visible)
	assert_string_contains(embed_node.author_name_rtl.text, "Author")
	assert_string_contains(embed_node.author_name_rtl.text, "url=https://author.com")


func test_setup_author_no_url() -> void:
	embed_node.setup({
		"title": "Test",
		"author": {"name": "Plain Author", "url": "", "icon_url": ""},
	})
	assert_true(embed_node.author_row.visible)
	assert_string_contains(embed_node.author_name_rtl.text, "Plain Author")
	assert_false(embed_node.author_name_rtl.text.contains("url="))


# --- setup with fields ---

func test_setup_with_fields() -> void:
	embed_node.setup({
		"title": "Test",
		"fields": [
			{"name": "Field1", "value": "Value1", "inline": false},
			{"name": "Field2", "value": "Value2", "inline": true},
		],
	})
	assert_true(embed_node.fields_container.visible)


func test_setup_with_no_fields() -> void:
	embed_node.setup({"title": "Test"})
	assert_false(embed_node.fields_container.visible)


# --- footer ---

func test_setup_footer() -> void:
	embed_node.setup({"title": "Test", "footer": "Footer text"})
	assert_true(embed_node.footer_label.visible)
	assert_eq(embed_node.footer_label.text, "Footer text")


func test_setup_no_footer() -> void:
	embed_node.setup({"title": "Test"})
	assert_false(embed_node.footer_label.visible)


# --- color ---

func test_setup_custom_color() -> void:
	var custom_color := Color(1, 0, 0)
	embed_node.setup({"title": "Test", "color": custom_color})
	var style: StyleBoxFlat = embed_node.get_theme_stylebox("panel")
	assert_eq(style.border_color, custom_color)


# --- embed type ---

func test_setup_type_image_hides_text() -> void:
	embed_node.setup({
		"title": "Should hide",
		"type": "image",
		"image": "https://example.com/img.png",
	})
	assert_false(embed_node.title_rtl.visible)
	assert_false(embed_node.description_rtl.visible)
	assert_true(embed_node.image_rect.visible)
