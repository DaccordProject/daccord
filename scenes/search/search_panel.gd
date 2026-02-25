extends PanelContainer

const SearchResultScene := preload(
	"res://scenes/search/search_result_item.tscn"
)
const DEBOUNCE_MS := 300.0
const PAGE_SIZE := 25

var _space_id: String = ""
var _query: String = ""
var _offset: int = 0
var _has_more: bool = false
var _searching: bool = false
var _debounce_timer: Timer

@onready var search_input: LineEdit = $VBox/Header/SearchInput
@onready var close_button: Button = $VBox/Header/CloseButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var results_vbox: VBoxContainer = $VBox/ScrollContainer/ResultsVBox
@onready var load_more_btn: Button = $VBox/LoadMoreButton


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.184, 0.192, 0.212)
	add_theme_stylebox_override("panel", style)

	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = DEBOUNCE_MS / 1000.0
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)

	search_input.placeholder_text = "Search messages..."
	search_input.text_changed.connect(_on_search_text_changed)
	close_button.pressed.connect(_on_close_pressed)
	load_more_btn.pressed.connect(_on_load_more_pressed)
	load_more_btn.visible = false
	status_label.visible = false

	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var more_style := StyleBoxFlat.new()
	more_style.bg_color = Color(0.24, 0.25, 0.27)
	more_style.corner_radius_top_left = 4
	more_style.corner_radius_top_right = 4
	more_style.corner_radius_bottom_left = 4
	more_style.corner_radius_bottom_right = 4
	more_style.content_margin_left = 8.0
	more_style.content_margin_top = 4.0
	more_style.content_margin_right = 8.0
	more_style.content_margin_bottom = 4.0
	load_more_btn.add_theme_stylebox_override(
		"normal", more_style
	)
	load_more_btn.add_theme_font_size_override("font_size", 12)

	AppState.space_selected.connect(_on_space_selected)
	AppState.dm_mode_entered.connect(_on_dm_mode_entered)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey \
			and event.pressed \
			and event.keycode == KEY_ESCAPE:
		AppState.close_search()
		get_viewport().set_input_as_handled()


func activate(space_id: String) -> void:
	_space_id = space_id
	search_input.grab_focus()


func _on_search_text_changed(new_text: String) -> void:
	_debounce_timer.stop()
	if new_text.strip_edges().is_empty():
		_clear_results()
		return
	_debounce_timer.start()


func _on_debounce_timeout() -> void:
	var text := search_input.text.strip_edges()
	if text.is_empty() or _space_id.is_empty():
		return
	_query = text
	_offset = 0
	_clear_results()
	_do_search()


func _on_close_pressed() -> void:
	AppState.close_search()


func _on_load_more_pressed() -> void:
	if not _has_more or _searching:
		return
	_do_search()


func _on_space_selected(_gid: String) -> void:
	_clear_results()
	search_input.text = ""
	_space_id = _gid


func _on_dm_mode_entered() -> void:
	_clear_results()
	search_input.text = ""
	_space_id = ""


func _clear_results() -> void:
	for child in results_vbox.get_children():
		child.queue_free()
	status_label.visible = false
	load_more_btn.visible = false
	_has_more = false
	_offset = 0


func _do_search() -> void:
	if _searching:
		return
	_searching = true
	status_label.text = "Searching..."
	status_label.visible = true
	load_more_btn.visible = false

	var filters := {"limit": PAGE_SIZE, "offset": _offset}
	var result: Dictionary = await Client.search_messages(
		_space_id, _query, filters
	)

	_searching = false
	var results: Array = result.get("results", [])
	_has_more = result.get("has_more", false)

	if results.is_empty() and _offset == 0:
		status_label.text = "No results found"
		status_label.visible = true
		load_more_btn.visible = false
		return

	status_label.visible = false

	for msg in results:
		var ch_id: String = msg.get("channel_id", "")
		var ch_name := _resolve_channel_name(ch_id)
		msg["channel_name"] = ch_name
		var item: PanelContainer = SearchResultScene.instantiate()
		results_vbox.add_child(item)
		item.setup(msg)
		item.clicked.connect(_on_result_clicked)

	_offset += results.size()
	load_more_btn.text = "Load More"
	load_more_btn.visible = _has_more


func _resolve_channel_name(channel_id: String) -> String:
	for ch in Client.channels:
		if ch.get("id", "") == channel_id:
			return ch.get("name", "unknown")
	return "unknown"


func _on_result_clicked(
	channel_id: String, _message_id: String
) -> void:
	AppState.select_channel(channel_id)
