extends PanelContainer

const DiscoveryCardScene := preload("res://scenes/discovery/discovery_card.tscn")
const DiscoveryDetailScene := preload("res://scenes/discovery/discovery_detail.tscn")
const AuthDialogScene := preload("res://scenes/sidebar/guild_bar/auth_dialog.tscn")

var _all_spaces: Array = []
var _active_tag: String = ""
var _search_timer: Timer
var _detail_view: VBoxContainer = null

@onready var _close_button: Button = $Margin/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $Margin/VBox/SearchInput
@onready var _tag_bar: HFlowContainer = $Margin/VBox/TagBar
@onready var _scroll: ScrollContainer = $Margin/VBox/ScrollContainer
@onready var _grid: GridContainer = $Margin/VBox/ScrollContainer/Grid
@onready var _status_label: Label = $Margin/VBox/StatusLabel
@onready var _detail_container: PanelContainer = $Margin/VBox/DetailContainer

func _ready() -> void:
	_close_button.pressed.connect(_on_close)
	_search_input.text_changed.connect(_on_search_changed)
	add_to_group("themed")
	_apply_theme()

	# Debounce timer for search
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.4
	_search_timer.timeout.connect(_on_search_debounced)
	add_child(_search_timer)

func activate() -> void:
	_update_grid_columns()
	_fetch_directory()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_grid_columns()

func _update_grid_columns() -> void:
	if not is_instance_valid(_grid):
		return
	var w := size.x
	if w < 500:
		_grid.columns = 1
	elif w < 800:
		_grid.columns = 2
	else:
		_grid.columns = 3

func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("panel_bg")
	add_theme_stylebox_override("panel", style)

	_search_input.add_theme_color_override("font_color", ThemeManager.get_color("text_body"))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = ThemeManager.get_color("input_bg")
	input_style.set_corner_radius_all(4)
	input_style.content_margin_left = 12.0
	input_style.content_margin_right = 12.0
	input_style.content_margin_top = 8.0
	input_style.content_margin_bottom = 8.0
	_search_input.add_theme_stylebox_override("normal", input_style)
	_search_input.add_theme_stylebox_override("focus", input_style)

func _fetch_directory(query: String = "", tag: String = "") -> void:
	_show_status("Loading servers...")
	_clear_grid()

	var master_url: String = Config.get_master_server_url()
	var rest := AccordRest.new(master_url)
	add_child(rest)

	var api := DirectoryApi.new(rest)
	var result: RestResult = await api.browse(query, tag)
	rest.queue_free()

	if not is_instance_valid(self):
		return

	if not result.ok:
		var msg: String = result.error.message if result.error else "Failed to load directory"
		_show_status(msg)
		return

	# AccordRest unwraps the "data" envelope, so result.data is the array directly
	var data = result.data
	var spaces: Array = []
	if data is Array:
		spaces = data
	elif data is Dictionary:
		spaces = data.get("spaces", data.get("data", []))

	_all_spaces = spaces

	if spaces.is_empty():
		_show_status("No servers found")
		return

	_status_label.visible = false
	_populate_grid(spaces)
	_populate_tags(spaces)

func _populate_grid(spaces: Array) -> void:
	_clear_grid()
	for space in spaces:
		var card: PanelContainer = DiscoveryCardScene.instantiate()
		_grid.add_child(card)
		card.setup(space)
		card.card_clicked.connect(_on_card_clicked)

func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

func _populate_tags(spaces: Array) -> void:
	# Clear existing tags
	for child in _tag_bar.get_children():
		child.queue_free()

	# Collect unique tags
	var tags: Dictionary = {}
	for space in spaces:
		var space_tags: Array = space.get("tags", [])
		for tag in space_tags:
			var t: String = str(tag)
			if not t.is_empty():
				tags[t] = tags.get(t, 0) + 1

	if tags.is_empty():
		_tag_bar.visible = false
		return

	_tag_bar.visible = true

	# Add "All" button
	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.flat = true
	_style_tag_button(all_btn, _active_tag.is_empty())
	all_btn.pressed.connect(func():
		_active_tag = ""
		_fetch_directory(_search_input.text.strip_edges())
	)
	_tag_bar.add_child(all_btn)

	# Add tag buttons
	var sorted_tags: Array = tags.keys()
	sorted_tags.sort()
	for tag in sorted_tags:
		var btn := Button.new()
		btn.text = str(tag)
		btn.flat = true
		_style_tag_button(btn, _active_tag == tag)
		var captured_tag: String = tag
		btn.pressed.connect(func():
			_active_tag = captured_tag
			_fetch_directory(_search_input.text.strip_edges(), captured_tag)
		)
		_tag_bar.add_child(btn)

func _style_tag_button(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = ThemeManager.get_color("accent")
		btn.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
	else:
		style.bg_color = ThemeManager.get_color("secondary_button")
		btn.add_theme_color_override("font_color", ThemeManager.get_color("text_body"))
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = ThemeManager.get_color("secondary_button_hover") if not active else ThemeManager.get_color("accent_hover")
	btn.add_theme_stylebox_override("hover", hover)

func _show_status(msg: String) -> void:
	_status_label.text = msg
	_status_label.visible = true

func _on_search_changed(_text: String) -> void:
	_search_timer.stop()
	_search_timer.start()

func _on_search_debounced() -> void:
	var q := _search_input.text.strip_edges()
	_fetch_directory(q, _active_tag)

func _on_card_clicked(space_data: Dictionary) -> void:
	# Show detail view, hide grid
	_scroll.visible = false
	_tag_bar.visible = false
	_search_input.visible = false
	_detail_container.visible = true

	# Clear previous detail
	for child in _detail_container.get_children():
		child.queue_free()

	_detail_view = DiscoveryDetailScene.instantiate()
	_detail_container.add_child(_detail_view)
	_detail_view.setup(space_data)
	_detail_view.back_pressed.connect(_on_detail_back)
	_detail_view.join_pressed.connect(_on_detail_join)

func _on_detail_back() -> void:
	_detail_container.visible = false
	if _detail_view:
		_detail_view.queue_free()
		_detail_view = null
	_scroll.visible = true
	_tag_bar.visible = true
	_search_input.visible = true

func _on_detail_join(server_url: String, space_id: String) -> void:
	# Check if already connected to this server
	var servers := Config.get_servers()
	for i in servers.size():
		var server: Dictionary = servers[i]
		if server["base_url"] == server_url and Client.is_server_connected(i):
			# Already have credentials — join directly
			_join_and_connect(server_url, space_id, server.get("token", ""), server.get("username", ""), server.get("display_name", ""))
			return

	# No existing account — show auth dialog
	var auth_dialog := AuthDialogScene.instantiate()
	auth_dialog.setup(server_url)
	auth_dialog.auth_completed.connect(
		func(resolved_url: String, t: String, u: String, _p: String, dn: String):
			_join_and_connect(resolved_url, space_id, t, u, dn)
	)
	get_tree().root.add_child(auth_dialog)

func _join_and_connect(
	url: String, space_id: String,
	token: String,
	username: String = "",
	display_name: String = "",
) -> void:
	# Call POST /spaces/{space_id}/join on the target server
	var api_url := url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = token
	rest.token_type = "Bearer"
	add_child(rest)
	var result: RestResult = await rest.make_request("POST", "/spaces/%s/join" % space_id)
	rest.queue_free()

	if not is_instance_valid(self):
		return

	if not result.ok:
		var msg: String = result.error.message if result.error else "Failed to join space"
		if _detail_view and is_instance_valid(_detail_view):
			_detail_view.show_error(msg)
		return

	# Successfully joined — save config and connect
	Config.add_server(url, token, space_id, username, display_name)
	var server_index: int = Config.get_servers().size() - 1
	var connect_result: Dictionary = await Client.connect_server(server_index)

	if not is_instance_valid(self):
		return

	if connect_result.has("error"):
		if _detail_view and is_instance_valid(_detail_view):
			_detail_view.show_error(connect_result["error"])
		return

	# Success — close discovery
	var joined_space_id: String = connect_result.get("space_id", space_id)
	AppState.close_discovery()
	if not joined_space_id.is_empty():
		AppState.select_space(joined_space_id)

func _on_close() -> void:
	AppState.close_discovery()
