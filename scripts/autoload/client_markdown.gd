class_name ClientMarkdown

## Markdown-to-BBCode conversion and BBCode sanitization.
## Extracted from ClientModels to keep that file focused on model conversion.

# Cached compiled regex objects (lazy-initialized)
static var _code_block_regex: RegEx
static var _inline_code_regex: RegEx
static var _strike_regex: RegEx
static var _underline_regex: RegEx
static var _bold_regex: RegEx
static var _italic_regex: RegEx
static var _spoiler_regex: RegEx
static var _link_regex: RegEx
static var _blockquote_regex: RegEx
static var _emoji_regex: RegEx
static var _code_splitter_regex: RegEx

static func _ensure_compiled() -> void:
	if _code_block_regex != null:
		return
	_code_block_regex = RegEx.new()
	_code_block_regex.compile("```(?:\\w+\\n)?([\\s\\S]*?)```")
	_inline_code_regex = RegEx.new()
	_inline_code_regex.compile("`([^`]+)`")
	_strike_regex = RegEx.new()
	_strike_regex.compile("~~(.+?)~~")
	_underline_regex = RegEx.new()
	_underline_regex.compile("__(.+?)__")
	_bold_regex = RegEx.new()
	_bold_regex.compile("\\*\\*(.+?)\\*\\*")
	_italic_regex = RegEx.new()
	_italic_regex.compile("\\*(.+?)\\*")
	_spoiler_regex = RegEx.new()
	_spoiler_regex.compile("\\|\\|(.+?)\\|\\|")
	_link_regex = RegEx.new()
	_link_regex.compile("\\[(.+?)\\]\\((.+?)\\)")
	_blockquote_regex = RegEx.new()
	_blockquote_regex.compile("(?m)^> (.+)$")
	_emoji_regex = RegEx.new()
	_emoji_regex.compile(":([a-z0-9_]+):")
	_code_splitter_regex = RegEx.new()
	_code_splitter_regex.compile("(?s)(\\[code\\].*?\\[/code\\])")

static func markdown_to_bbcode(text: String) -> String:
	_ensure_compiled()
	var result := text
	# Code blocks (``` ```)
	result = _code_block_regex.sub(result, "[code]$1[/code]", true)
	# Inline code
	result = _inline_code_regex.sub(result, "[code]$1[/code]", true)
	# Strikethrough ~~text~~
	result = _strike_regex.sub(result, "[s]$1[/s]", true)
	# Underline __text__ (must come before bold to avoid conflict)
	result = _underline_regex.sub(result, "[u]$1[/u]", true)
	# Bold
	result = _bold_regex.sub(result, "[b]$1[/b]", true)
	# Italic
	result = _italic_regex.sub(result, "[i]$1[/i]", true)
	# Spoilers ||text||
	result = _spoiler_regex.sub(
		result,
		"[url=spoiler][bgcolor=#1e1f22][color=#1e1f22]$1[/color][/bgcolor][/url]",
		true,
	)
	# Links — block dangerous URL schemes before converting
	var link_matches := _link_regex.search_all(result)
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
	result = _blockquote_regex.sub(
		result,
		"[indent][color=#8a8e94]$1[/color][/indent]",
		true,
	)
	# Emoji shortcodes :name: -> inline image
	var emoji_matches := _emoji_regex.search_all(result)
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
	_ensure_compiled()
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
	var parts: Array[String] = []
	var last_end: int = 0
	for cm in _code_splitter_regex.search_all(text):
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
