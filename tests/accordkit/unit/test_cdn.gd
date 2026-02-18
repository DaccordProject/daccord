extends GutTest


func before_each() -> void:
	AccordCDN.base_url = "http://127.0.0.1:39099/cdn"


func test_avatar_url() -> void:
	var url := AccordCDN.avatar("123", "abc_hash")
	assert_eq(url, "http://127.0.0.1:39099/cdn/avatars/123/abc_hash.png")


func test_avatar_url_custom_format() -> void:
	var url := AccordCDN.avatar("123", "abc_hash", "webp")
	assert_eq(url, "http://127.0.0.1:39099/cdn/avatars/123/abc_hash.webp")


func test_default_avatar_url() -> void:
	var url := AccordCDN.default_avatar(3)
	assert_eq(url, "http://127.0.0.1:39099/cdn/embed/avatars/3.png")


func test_space_icon_url() -> void:
	var url := AccordCDN.space_icon("sp1", "icon_hash")
	assert_eq(url, "http://127.0.0.1:39099/cdn/space-icons/sp1/icon_hash.png")


func test_space_banner_url() -> void:
	var url := AccordCDN.space_banner("sp1", "banner_hash")
	assert_eq(url, "http://127.0.0.1:39099/cdn/banners/sp1/banner_hash.png")


func test_emoji_url() -> void:
	var url := AccordCDN.emoji("e1")
	assert_eq(url, "http://127.0.0.1:39099/cdn/emojis/e1.png")


func test_emoji_url_gif() -> void:
	var url := AccordCDN.emoji("e1", "gif")
	assert_eq(url, "http://127.0.0.1:39099/cdn/emojis/e1.gif")


func test_attachment_url() -> void:
	var url := AccordCDN.attachment("ch1", "att1", "image.png")
	assert_eq(url, "http://127.0.0.1:39099/cdn/attachments/ch1/att1/image.png")


func test_is_animated_true() -> void:
	assert_true(AccordCDN.is_animated("a_abc123"))


func test_is_animated_false() -> void:
	assert_false(AccordCDN.is_animated("abc123"))


func test_auto_format_animated() -> void:
	assert_eq(AccordCDN.auto_format("a_hash"), "gif")


func test_auto_format_static() -> void:
	assert_eq(AccordCDN.auto_format("hash"), "png")
