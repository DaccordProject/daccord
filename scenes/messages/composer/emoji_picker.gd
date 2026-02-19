extends PanelContainer

signal emoji_picked(emoji_name: String)

const EmojiButtonCellScene := preload("res://scenes/messages/composer/emoji_button_cell.tscn")
const CUSTOM_CATEGORY_KEY := "custom"

# Can be EmojiData.Category or CUSTOM_CATEGORY_KEY
var _current_category = EmojiData.Category.SMILEYS
var _category_buttons: Dictionary = {}
var _recent_btn: Button = null
var _custom_btn: Button = null
var _custom_emoji_cache: Dictionary = {} # emoji_id -> { name, texture }
var _custom_emojis: Array = []
var _is_custom_selected: bool = false
var _is_recent_selected: bool = false

@onready var category_bar: HBoxContainer = $VBox/CategoryBar
@onready var search_input: LineEdit = $VBox/SearchInput
@onready var scroll: ScrollContainer = $VBox/Scroll
@onready var emoji_grid: GridContainer = $VBox/Scroll/EmojiGrid

func _ready() -> void:
	_build_category_bar()
	search_input.text_changed.connect(_on_search_changed)
	search_input.placeholder_text = "Search emoji..."
	# Default to recently used if any exist
	if Config.get_recent_emoji().size() > 0:
		_is_recent_selected = true
		_load_recent_category()
		_update_category_highlights()
	else:
		_load_category(_current_category)

func _build_category_bar() -> void:
	# Add Recently Used tab
	_recent_btn = Button.new()
	_recent_btn.flat = true
	_recent_btn.custom_minimum_size = Vector2(36, 36)
	_recent_btn.expand_icon = true
	_recent_btn.icon = EmojiData.TEXTURES.get("watch")
	_recent_btn.tooltip_text = "Recently Used"
	_recent_btn.pressed.connect(_on_recent_category_pressed)
	category_bar.add_child(_recent_btn)

	# Add Custom tab if a guild is selected
	if not AppState.current_guild_id.is_empty():
		_custom_btn = Button.new()
		_custom_btn.flat = true
		_custom_btn.custom_minimum_size = Vector2(36, 36)
		_custom_btn.expand_icon = true
		_custom_btn.icon = EmojiData.TEXTURES.get("star")
		_custom_btn.tooltip_text = "Custom"
		_custom_btn.pressed.connect(_on_custom_category_pressed)
		category_bar.add_child(_custom_btn)

	for cat in EmojiData.CATEGORY_ICONS:
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(36, 36)
		btn.expand_icon = true
		var icon_name: String = EmojiData.CATEGORY_ICONS[cat]
		# Find the emoji name for this codepoint to get its texture
		var tex: Texture2D = null
		for entry in EmojiData.CATALOG[cat]:
			if entry["codepoint"] == icon_name:
				tex = EmojiData.TEXTURES.get(entry["name"])
				break
		if tex:
			btn.icon = tex
		btn.tooltip_text = EmojiData.CATEGORY_NAMES[cat]
		btn.pressed.connect(_on_category_pressed.bind(cat))
		category_bar.add_child(btn)
		_category_buttons[cat] = btn
	_update_category_highlights()

func _update_category_highlights() -> void:
	var inactive := Color(0.58, 0.608, 0.643)
	for cat in _category_buttons:
		var btn: Button = _category_buttons[cat]
		if not _is_custom_selected and not _is_recent_selected and cat == _current_category:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = inactive
	if _custom_btn:
		_custom_btn.modulate = Color.WHITE if _is_custom_selected else inactive
	if _recent_btn:
		_recent_btn.modulate = Color.WHITE if _is_recent_selected else inactive

func _on_category_pressed(cat: EmojiData.Category) -> void:
	_current_category = cat
	_is_custom_selected = false
	_is_recent_selected = false
	search_input.text = ""
	_load_category(cat)
	_update_category_highlights()

func _on_custom_category_pressed() -> void:
	_is_custom_selected = true
	_is_recent_selected = false
	search_input.text = ""
	_load_custom_category()
	_update_category_highlights()

func _on_recent_category_pressed() -> void:
	_is_recent_selected = true
	_is_custom_selected = false
	search_input.text = ""
	_load_recent_category()
	_update_category_highlights()

func _load_category(cat: EmojiData.Category) -> void:
	_clear_grid()
	var entries: Array = EmojiData.get_all_for_category(cat)
	for entry in entries:
		_add_emoji_cell(entry)

func _load_custom_category() -> void:
	_clear_grid()
	var guild_id := AppState.current_guild_id
	if guild_id.is_empty():
		return
	var result: RestResult = await Client.admin.get_emojis(guild_id)
	if result == null or not result.ok:
		return
	_custom_emojis = result.data if result.data is Array else []
	for emoji in _custom_emojis:
		_add_custom_emoji_cell(emoji)

func _load_recent_category() -> void:
	_clear_grid()
	var recent: Array = Config.get_recent_emoji()
	for emoji_name in recent:
		# Check built-in emoji first
		var entry := EmojiData.get_by_name(emoji_name)
		if not entry.is_empty():
			_add_emoji_cell(entry)
			continue
		# Check custom emoji cache
		if ClientModels.custom_emoji_textures.has(emoji_name):
			var cell: Button = EmojiButtonCellScene.instantiate()
			emoji_grid.add_child(cell)
			cell.icon = ClientModels.custom_emoji_textures[emoji_name]
			cell.tooltip_text = emoji_name.replace("_", " ")
			var custom_key: String = "custom:" + emoji_name + ":"
			cell.pressed.connect(func() -> void:
				emoji_picked.emit(custom_key)
			)

func _add_custom_emoji_cell(emoji) -> void:
	var emoji_id: String = ""
	var emoji_name: String = ""
	if emoji is Dictionary:
		emoji_id = str(emoji.get("id", ""))
		emoji_name = str(emoji.get("name", ""))
	elif emoji is AccordEmoji:
		emoji_id = emoji.id
		emoji_name = emoji.name

	if emoji_id.is_empty():
		return

	var cell: Button = EmojiButtonCellScene.instantiate()
	emoji_grid.add_child(cell)
	cell.tooltip_text = emoji_name.replace("_", " ")

	# Check cache first
	if _custom_emoji_cache.has(emoji_id):
		cell.icon = _custom_emoji_cache[emoji_id]["texture"]
	else:
		# Load from CDN
		var url := Client.admin.get_emoji_url(AppState.current_guild_id, emoji_id)
		var http := HTTPRequest.new()
		cell.add_child(http)
		http.request_completed.connect(func(
			_result_code: int, response_code: int,
			_headers: PackedStringArray,
			body: PackedByteArray) -> void:
			http.queue_free()
			if response_code != 200:
				return
			var img := Image.new()
			var err := img.load_png_from_buffer(body)
			if err != OK:
				return
			var tex := ImageTexture.create_from_image(img)
			_custom_emoji_cache[emoji_id] = {"name": emoji_name, "texture": tex}
			Client.register_custom_emoji(AppState.current_guild_id, emoji_id, emoji_name)
			Client.register_custom_emoji_texture(emoji_name, tex)
			if is_instance_valid(cell):
				cell.icon = tex
		)
		http.request(url)

	# Use custom:name:id format for custom emoji
	var custom_key := "custom:" + emoji_name + ":" + emoji_id
	cell.pressed.connect(func() -> void:
		Config.add_recent_emoji(emoji_name)
		emoji_picked.emit(custom_key)
	)

func _on_search_changed(query: String) -> void:
	_clear_grid()
	var lower_query := query.strip_edges().to_lower()
	if lower_query.is_empty():
		if _is_recent_selected:
			_load_recent_category()
		elif _is_custom_selected:
			_load_custom_category()
		else:
			_load_category(_current_category)
		return
	# Search built-in emoji
	for cat in EmojiData.CATALOG:
		for entry in EmojiData.CATALOG[cat]:
			if entry["name"].to_lower().contains(lower_query):
				_add_emoji_cell(entry)
	# Also search cached custom emoji
	for emoji_id in _custom_emoji_cache:
		var cached: Dictionary = _custom_emoji_cache[emoji_id]
		if cached["name"].to_lower().contains(lower_query):
			var cell: Button = EmojiButtonCellScene.instantiate()
			emoji_grid.add_child(cell)
			cell.icon = cached["texture"]
			cell.tooltip_text = cached["name"].replace("_", " ")
			var custom_key: String = "custom:" + str(cached["name"]) + ":" + str(emoji_id)
			var cached_name: String = str(cached["name"])
			cell.pressed.connect(func() -> void:
				Config.add_recent_emoji(cached_name)
				emoji_picked.emit(custom_key)
			)

func _add_emoji_cell(entry: Dictionary) -> void:
	var cell: Button = EmojiButtonCellScene.instantiate()
	emoji_grid.add_child(cell)
	cell.setup(entry)
	cell.emoji_selected.connect(_on_emoji_selected)

func _on_emoji_selected(emoji_name: String) -> void:
	Config.add_recent_emoji(emoji_name)
	emoji_picked.emit(emoji_name)

func _clear_grid() -> void:
	for child in emoji_grid.get_children():
		child.queue_free()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var global_rect := get_global_rect()
		if not global_rect.has_point(event.global_position):
			visible = false
			get_viewport().set_input_as_handled()
