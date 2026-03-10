class_name EmojiData

## Static emoji catalog for the emoji picker.
## Data is loaded from the EmojiCatalog resource (emoji_catalog.tres).
## Textures are lazy-loaded on first access to avoid loading ~340 SVGs at startup.

enum Category { SMILEYS, PEOPLE, NATURE, FOOD, ACTIVITIES, TRAVEL, OBJECTS, SYMBOLS, FLAGS }

static var _catalog_res: EmojiCatalog = preload("res://scripts/emoji_catalog.tres")

static var CATEGORY_NAMES: Dictionary:
	get:
		_ensure_initialized()
		return _category_names

static var CATEGORY_ICONS: Dictionary:
	get:
		_ensure_initialized()
		return _category_icons

static var CATALOG: Dictionary:
	get:
		_ensure_initialized()
		return _catalog

static var _category_names: Dictionary = {}
static var _category_icons: Dictionary = {}
static var _catalog: Dictionary = {}
static var _initialized := false
static var _name_lookup: Dictionary = {}
static var _texture_cache: Dictionary = {} # "emoji_name" -> Texture2D
static var _skin_tone_textures: Dictionary = {} # "codepoint" -> Texture2D

static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true

	# Build category metadata from packed arrays
	for i in range(_catalog_res.category_names.size()):
		_category_names[i] = _catalog_res.category_names[i]
		_category_icons[i] = _catalog_res.category_icons[i]

	# Build catalog dictionary from parallel arrays
	for cat in Category.values():
		_catalog[cat] = []
	for i in range(_catalog_res.names.size()):
		var cat_idx: int = _catalog_res.categories[i]
		_catalog[cat_idx].append({
			"name": _catalog_res.names[i],
			"codepoint": _catalog_res.codepoints[i],
		})

# Skin tone modifier codepoints (index matches Config value: 0=none, 1-5=tones)
static var SKIN_TONE_MODIFIERS: PackedStringArray:
	get: return _catalog_res.skin_tone_modifiers

# Emoji names that support skin tone modifiers
static var SKIN_TONE_EMOJI: PackedStringArray:
	get: return _catalog_res.skin_tone_emoji

static func _build_name_lookup() -> void:
	_ensure_initialized()
	if not _name_lookup.is_empty():
		return
	for cat_entries in _catalog.values():
		for entry in cat_entries:
			_name_lookup[entry["name"]] = entry

static func get_all_for_category(category: Category) -> Array:
	_ensure_initialized()
	return _catalog.get(category, [])

static func get_by_name(emoji_name: String) -> Dictionary:
	_build_name_lookup()
	return _name_lookup.get(emoji_name, {})

## Returns true if the emoji supports skin tone variants.
static func supports_skin_tone(emoji_name: String) -> bool:
	return emoji_name in _catalog_res.skin_tone_emoji

## Returns the codepoint for the emoji with the given skin tone applied.
## If tone is 0 (default) or emoji doesn't support tones, returns the base codepoint.
static func get_codepoint_with_tone(emoji_name: String, tone: int) -> String:
	var entry := get_by_name(emoji_name)
	if entry.is_empty():
		return ""
	var base_cp: String = entry["codepoint"]
	if tone <= 0 or tone > 5 or not supports_skin_tone(emoji_name):
		return base_cp
	return base_cp + "-" + _catalog_res.skin_tone_modifiers[tone]

## Returns the texture for the emoji, optionally with skin tone applied.
## Textures are lazily loaded on first access and cached.
static func get_texture(emoji_name: String, tone: int = 0) -> Texture2D:
	if tone > 0 and supports_skin_tone(emoji_name):
		var cp := get_codepoint_with_tone(emoji_name, tone)
		if _skin_tone_textures.has(cp):
			return _skin_tone_textures[cp]
		var path = "res://assets/theme/emoji/" + cp + ".svg"
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			_skin_tone_textures[cp] = tex
			return tex
		# Fall through to base texture

	if _texture_cache.has(emoji_name):
		return _texture_cache[emoji_name]
	var entry := get_by_name(emoji_name)
	if entry.is_empty():
		return null
	var path = "res://assets/theme/emoji/" + entry["codepoint"] + ".svg"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_texture_cache[emoji_name] = tex
		return tex
	return null

## Converts a hex codepoint (possibly multi-part like "1f1fa-1f1f8") to a
## Unicode character string.
static func codepoint_to_char(hex_codepoint: String) -> String:
	var result := ""
	for part in hex_codepoint.split("-"):
		result += char(part.hex_to_int())
	return result
