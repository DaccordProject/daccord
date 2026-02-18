extends GutTest


# --- markdown_to_bbcode ---

func test_markdown_bold() -> void:
	var result = ClientModels.markdown_to_bbcode("**bold text**")
	assert_eq(result, "[b]bold text[/b]")


func test_markdown_italic() -> void:
	var result = ClientModels.markdown_to_bbcode("*italic text*")
	assert_eq(result, "[i]italic text[/i]")


func test_markdown_strikethrough() -> void:
	var result = ClientModels.markdown_to_bbcode("~~strike~~")
	assert_eq(result, "[s]strike[/s]")


func test_markdown_underline() -> void:
	var result = ClientModels.markdown_to_bbcode("__underlined__")
	assert_eq(result, "[u]underlined[/u]")


func test_markdown_inline_code() -> void:
	var result = ClientModels.markdown_to_bbcode("`some code`")
	assert_eq(result, "[code]some code[/code]")


func test_markdown_code_block() -> void:
	var result = ClientModels.markdown_to_bbcode("```\ncode here\n```")
	assert_eq(result, "[code]\ncode here\n[/code]")


func test_markdown_code_block_with_language() -> void:
	var result = ClientModels.markdown_to_bbcode("```gdscript\nvar x = 1\n```")
	assert_eq(result, "[code]var x = 1\n[/code]")


func test_markdown_spoiler() -> void:
	var result = ClientModels.markdown_to_bbcode("||spoiler text||")
	assert_eq(result, "[url=spoiler][bgcolor=#1e1f22][color=#1e1f22]spoiler text[/color][/bgcolor][/url]")


func test_markdown_link() -> void:
	var result = ClientModels.markdown_to_bbcode("[click here](https://example.com)")
	assert_eq(result, "[url=https://example.com]click here[/url]")


func test_markdown_blockquote() -> void:
	var result = ClientModels.markdown_to_bbcode("> quoted text")
	assert_eq(result, "[indent][color=#8a8e94]quoted text[/color][/indent]")


func test_markdown_plain_passthrough() -> void:
	var result = ClientModels.markdown_to_bbcode("just plain text")
	assert_eq(result, "just plain text")
