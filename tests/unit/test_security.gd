extends GutTest

var app_state: Node


func before_each() -> void:
	app_state = load("res://scripts/autoload/app_state.gd").new()
	add_child(app_state)
	watch_signals(app_state)


func after_each() -> void:
	remove_child(app_state)
	app_state.free()


# =============================================================================
# 1. BBCode Injection
# =============================================================================

func test_bbcode_url_tag_passes_through_unsanitized() -> void:
	var result = ClientModels.markdown_to_bbcode("[url=http://evil.com]click[/url]")
	# Raw BBCode URL tag is NOT neutralized — RichTextLabel will interpret it
	assert_eq(result, "[url=http://evil.com]click[/url]",
		"Raw BBCode url tag passes through and will be rendered")


func test_bbcode_img_tag_passes_through_unsanitized() -> void:
	var result = ClientModels.markdown_to_bbcode("[img]http://evil.com/tracker.png[/img]")
	assert_eq(result, "[img]http://evil.com/tracker.png[/img]",
		"Raw BBCode img tag passes through and will be rendered")


func test_bbcode_color_tag_passes_through_unsanitized() -> void:
	var result = ClientModels.markdown_to_bbcode("[color=red]styled[/color]")
	assert_eq(result, "[color=red]styled[/color]",
		"Raw BBCode color tag passes through and will be rendered")


func test_bbcode_font_size_tag_passes_through_unsanitized() -> void:
	var result = ClientModels.markdown_to_bbcode("[font_size=100]huge[/font_size]")
	assert_eq(result, "[font_size=100]huge[/font_size]",
		"Raw BBCode font_size tag passes through and will be rendered")


func test_bbcode_table_tags_pass_through_unsanitized() -> void:
	var result = ClientModels.markdown_to_bbcode("[table][cell]data[/cell][/table]")
	assert_eq(result, "[table][cell]data[/cell][/table]",
		"Raw BBCode table/cell tags pass through and will be rendered")


func test_bbcode_nested_in_markdown_bold_passes_through() -> void:
	var result = ClientModels.markdown_to_bbcode("**[url=http://evil.com]text[/url]**")
	assert_eq(result, "[b][url=http://evil.com]text[/url][/b]",
		"BBCode inside markdown bold is wrapped but not escaped")


func test_bbcode_inside_inline_code_is_contained() -> void:
	var result = ClientModels.markdown_to_bbcode("`[url=evil]click[/url]`")
	assert_eq(result, "[code][url=evil]click[/url][/code]",
		"BBCode inside inline code is wrapped in [code] (RichTextLabel won't interpret nested BBCode)")


func test_bbcode_inside_code_block_is_contained() -> void:
	var result = ClientModels.markdown_to_bbcode("```\n[url=evil]click[/url]\n```")
	assert_eq(result, "[code]\n[url=evil]click[/url]\n[/code]",
		"BBCode inside code block is wrapped in [code] (RichTextLabel won't interpret nested BBCode)")


# =============================================================================
# 2. Malicious URL Schemes
# =============================================================================

func test_javascript_scheme_converted_to_url_tag() -> void:
	# Parentheses in the URL confuse the lazy link regex — it closes at the first )
	var result = ClientModels.markdown_to_bbcode("[click](javascript:alert(1))")
	assert_eq(result, "[url=javascript:alert(1]click[/url])",
		"javascript: URL with parens is mangled by regex but still creates a url tag")


func test_data_scheme_converted_to_url_tag() -> void:
	var result = ClientModels.markdown_to_bbcode("[click](data:text/html,<script>)")
	assert_eq(result, "[url=data:text/html,<script>]click[/url]",
		"data: scheme is converted to a clickable URL tag without filtering")


func test_file_scheme_converted_to_url_tag() -> void:
	var result = ClientModels.markdown_to_bbcode("[click](file:///etc/passwd)")
	assert_eq(result, "[url=file:///etc/passwd]click[/url]",
		"file: scheme is converted to a clickable URL tag without filtering")


func test_vbscript_scheme_converted_to_url_tag() -> void:
	var result = ClientModels.markdown_to_bbcode("[click](vbscript:msgbox)")
	assert_eq(result, "[url=vbscript:msgbox]click[/url]",
		"vbscript: scheme is converted to a clickable URL tag without filtering")


# =============================================================================
# 3. Input Boundary Attacks
# =============================================================================

func test_empty_string_returns_empty() -> void:
	var result = ClientModels.markdown_to_bbcode("")
	assert_eq(result, "", "Empty string should return empty string")


func test_extremely_long_string_no_crash() -> void:
	var long_input := "A".repeat(100000)
	var result = ClientModels.markdown_to_bbcode(long_input)
	assert_eq(result.length(), 100000, "100K char plain text should pass through unchanged")


func test_whitespace_only_passes_through() -> void:
	var result = ClientModels.markdown_to_bbcode("   \t\n  ")
	assert_eq(result, "   \t\n  ", "Whitespace-only input should pass through unchanged")


func test_null_byte_in_string_no_crash() -> void:
	var input := "hello" + char(0) + "world"
	var result = ClientModels.markdown_to_bbcode(input)
	assert_not_null(result, "String with null byte should not crash")
	assert_true(result.length() > 0, "Result should have content")


func test_unicode_rtl_override_passes_through() -> void:
	# U+202E is Right-to-Left Override, U+200D is Zero-Width Joiner
	var input := "normal" + char(0x202E) + "reversed" + char(0x200D) + "joined"
	var result = ClientModels.markdown_to_bbcode(input)
	assert_not_null(result, "Unicode control chars should not crash")
	assert_true(result.length() > 0, "Result should have content")


func test_repeated_special_chars_no_crash() -> void:
	var stars = ClientModels.markdown_to_bbcode("****")
	assert_not_null(stars, "Repeated asterisks should not crash")
	var backticks = ClientModels.markdown_to_bbcode("````")
	assert_not_null(backticks, "Repeated backticks should not crash")
	var pipes = ClientModels.markdown_to_bbcode("||||")
	assert_not_null(pipes, "Repeated pipes should not crash")


# =============================================================================
# 4. Regex Abuse / Catastrophic Backtracking
# =============================================================================

func test_deeply_nested_markdown_no_hang() -> void:
	var input := "*".repeat(1000)
	var result = ClientModels.markdown_to_bbcode(input)
	assert_not_null(result, "1000 asterisks should not cause hang or crash")


func test_overlapping_delimiters_no_crash() -> void:
	var result = ClientModels.markdown_to_bbcode("**bold *italic** text*")
	assert_not_null(result, "Overlapping bold/italic delimiters should not crash")


func test_unclosed_markdown_delimiters_no_crash() -> void:
	var result = ClientModels.markdown_to_bbcode("**no closing bold")
	assert_eq(result, "**no closing bold",
		"Unclosed bold delimiters should pass through unchanged")


# =============================================================================
# 5. State Integrity
# =============================================================================

func test_send_empty_message_still_emits() -> void:
	app_state.send_message("")
	assert_signal_emitted(app_state, "message_sent",
		"Empty string is accepted without validation")


func test_send_whitespace_only_message_still_emits() -> void:
	app_state.send_message("   \t\n  ")
	assert_signal_emitted(app_state, "message_sent",
		"Whitespace-only message is accepted without validation")


func test_select_guild_empty_id_still_emits() -> void:
	app_state.select_guild("")
	assert_eq(app_state.current_guild_id, "",
		"Empty guild ID is accepted without validation")
	assert_signal_emitted(app_state, "guild_selected")


func test_select_channel_empty_id_still_emits() -> void:
	app_state.select_channel("")
	assert_eq(app_state.current_channel_id, "",
		"Empty channel ID is accepted without validation")
	assert_signal_emitted(app_state, "channel_selected")


func test_edit_message_empty_content_still_emits() -> void:
	app_state.editing_message_id = "msg_3"
	app_state.edit_message("msg_3", "")
	assert_signal_emitted(app_state, "message_edited",
		"Empty content edit is accepted without validation")
	assert_eq(app_state.editing_message_id, "",
		"Editing state cleared even with empty content")


func test_delete_message_empty_id_still_emits() -> void:
	app_state.delete_message("")
	assert_signal_emitted(app_state, "message_deleted",
		"Empty message ID delete is accepted without validation")


func test_rapid_state_transitions_no_crash() -> void:
	app_state.select_guild("guild_1")
	app_state.select_channel("chan_3")
	app_state.enter_dm_mode()
	app_state.select_guild("guild_2")
	app_state.enter_dm_mode()
	app_state.select_guild("guild_1")
	app_state.enter_dm_mode()
	assert_true(app_state.is_dm_mode, "Should end in DM mode after rapid transitions")
	assert_eq(app_state.current_guild_id, "", "Guild should be cleared after DM mode")
