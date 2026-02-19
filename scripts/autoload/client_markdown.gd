class_name ClientMarkdown

## Markdown-to-BBCode conversion and BBCode sanitization.
## Extracted from ClientModels to keep that file focused on model conversion.

static func markdown_to_bbcode(text: String) -> String:
	var result := text
	# Code blocks (``` ```)
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(?:\\w+\\n)?([\\s\\S]*?)```")
	result = code_block_regex.sub(result, "[code]$1[/code]", true)
	# Inline code
	var inline_code_regex := RegEx.new()
	inline_code_regex.compile("`([^`]+)`")
	result = inline_code_regex.sub(result, "[code]$1[/code]", true)
	# Strikethrough ~~text~~
	var strike_regex := RegEx.new()
	strike_regex.compile("~~(.+?)~~")
	result = strike_regex.sub(result, "[s]$1[/s]", true)
	# Underline __text__ (must come before bold to avoid conflict)
	var underline_regex := RegEx.new()
	underline_regex.compile("__(.+?)__")
	result = underline_regex.sub(result, "[u]$1[/u]", true)
	# Bold
	var bold_regex := RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	result = bold_regex.sub(result, "[b]$1[/b]", true)
	# Italic
	var italic_regex := RegEx.new()
	italic_regex.compile("\\*(.+?)\\*")
	result = italic_regex.sub(result, "[i]$1[/i]", true)
	# Spoilers ||text||
	var spoiler_regex := RegEx.new()
	spoiler_regex.compile("\\|\\|(.+?)\\|\\|")
	result = spoiler_regex.sub(
		result,
		"[url=spoiler][bgcolor=#1e1f22][color=#1e1f22]$1[/color][/bgcolor][/url]",
		true,
	)
	# Links — block dangerous URL schemes before converting
	var link_regex := RegEx.new()
	link_regex.compile("\\[(.+?)\\]\\((.+?)\\)")
	var link_matches := link_regex.search_all(result)
	for i in range(link_matches.size() - 1, -1, -1):
		var lm := link_matches[i]
		var link_text := lm.get_string(1)
		var link_url := lm.get_string(2)
		var lower_url := link_url.strip_edges().to_lower()
		if lower_url.begins_with("javascript:") \
				or lower_url.begins_with("data:") \
				or lower_url.begins_with("file:") \
				or lower_url.begins_with("vbscript:"):
			link_url = "#blocked"
		var replacement := "[url=%s]%s[/url]" % [link_url, link_text]
		result = result.substr(0, lm.get_start()) + replacement + result.substr(lm.get_end())
	# Blockquotes (line-level: > text)
	var blockquote_regex := RegEx.new()
	blockquote_regex.compile("(?m)^> (.+)$")
	result = blockquote_regex.sub(
		result,
		"[indent][color=#8a8e94]$1[/color][/indent]",
		true,
	)
	# Emoji shortcodes :name: -> inline image
	var emoji_regex := RegEx.new()
	emoji_regex.compile(":([a-z0-9_]+):")
	var emoji_matches := emoji_regex.search_all(result)
	for i in range(emoji_matches.size() - 1, -1, -1):
		var m := emoji_matches[i]
		var ename := m.get_string(1)
		var entry := EmojiData.get_by_name(ename)
		if not entry.is_empty():
			var cp: String = entry["codepoint"]
			var img_tag := "[img=20x20]res://theme/emoji/" + cp + ".svg[/img]"
			result = result.substr(0, m.get_start()) + img_tag + result.substr(m.get_end())
		elif ClientModels.custom_emoji_paths.has(ename):
			var path: String = ClientModels.custom_emoji_paths[ename]
			var img_tag := "[img=20x20]" + path + "[/img]"
			result = result.substr(0, m.get_start()) + img_tag + result.substr(m.get_end())
	# Sanitize raw BBCode tags that were NOT produced by the converter.
	# Tags inside [code]...[/code] are left alone (RichTextLabel ignores them).
	result = _sanitize_bbcode_tags(result)
	return result

static func _sanitize_bbcode_tags(text: String) -> String:
	# Allowed tag prefixes produced by the markdown converter above.
	var allowed_prefixes: Array[String] = [
		"b]", "/b]",
		"i]", "/i]",
		"s]", "/s]",
		"u]", "/u]",
		"code]", "/code]",
		"url=", "url]", "/url]",
		"bgcolor=", "/bgcolor]",
		"color=", "/color]",
		"indent]", "/indent]",
		"img=", "/img]",
		"font_size=", "/font_size]",
		"lb]",
	]

	# Split on [code]...[/code] blocks so we don't touch their content.
	var code_splitter := RegEx.new()
	code_splitter.compile("(?s)(\\[code\\].*?\\[/code\\])")
	var parts: Array[String] = []
	var last_end: int = 0
	for cm in code_splitter.search_all(text):
		if cm.get_start() > last_end:
			parts.append(text.substr(last_end, cm.get_start() - last_end))
		parts.append(cm.get_string(0))
		last_end = cm.get_end()
	if last_end < text.length():
		parts.append(text.substr(last_end))

	var output := ""
	for idx in parts.size():
		var part: String = parts[idx]
		if part.begins_with("[code]"):
			output += part
			continue
		# Escape any [ that doesn't start an allowed tag
		var sanitized := ""
		var pos: int = 0
		while pos < part.length():
			if part[pos] == "[":
				var after := part.substr(pos + 1)
				var is_allowed := false
				for prefix in allowed_prefixes:
					if after.begins_with(prefix):
						is_allowed = true
						break
				if is_allowed:
					sanitized += "["
				else:
					sanitized += "[lb]"
			else:
				sanitized += part[pos]
			pos += 1
		output += sanitized
	return output
