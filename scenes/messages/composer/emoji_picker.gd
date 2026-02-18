extends PanelContainer

signal emoji_picked(emoji_name: String)

const EmojiButtonCellScene := preload("res://scenes/messages/composer/emoji_button_cell.tscn")

var _current_category: EmojiData.Category = EmojiData.Category.SMILEYS
var _category_buttons: Dictionary = {}

@onready var category_bar: HBoxContainer = $VBox/CategoryBar
@onready var search_input: LineEdit = $VBox/SearchInput
@onready var scroll: ScrollContainer = $VBox/Scroll
@onready var emoji_grid: GridContainer = $VBox/Scroll/EmojiGrid

func _ready() -> void:
	_build_category_bar()
	search_input.text_changed.connect(_on_search_changed)
	search_input.placeholder_text = "Search emoji..."
	_load_category(_current_category)

func _build_category_bar() -> void:
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
	for cat in _category_buttons:
		var btn: Button = _category_buttons[cat]
		if cat == _current_category:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.58, 0.608, 0.643)

func _on_category_pressed(cat: EmojiData.Category) -> void:
	_current_category = cat
	search_input.text = ""
	_load_category(cat)
	_update_category_highlights()

func _load_category(cat: EmojiData.Category) -> void:
	_clear_grid()
	var entries: Array = EmojiData.get_all_for_category(cat)
	for entry in entries:
		_add_emoji_cell(entry)

func _on_search_changed(query: String) -> void:
	_clear_grid()
	var lower_query := query.strip_edges().to_lower()
	if lower_query.is_empty():
		_load_category(_current_category)
		return
	for cat in EmojiData.CATALOG:
		for entry in EmojiData.CATALOG[cat]:
			if entry["name"].to_lower().contains(lower_query):
				_add_emoji_cell(entry)

func _add_emoji_cell(entry: Dictionary) -> void:
	var cell: Button = EmojiButtonCellScene.instantiate()
	emoji_grid.add_child(cell)
	cell.setup(entry)
	cell.emoji_selected.connect(_on_emoji_selected)

func _on_emoji_selected(emoji_name: String) -> void:
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
