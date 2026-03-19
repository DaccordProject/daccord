extends PanelContainer

signal join_requested(server_url: String, space_id: String, space_slug: String)

const DiscoveryCardScene := preload("res://scenes/discovery/discovery_card.tscn")
const DiscoveryDetailScene := preload("res://scenes/discovery/discovery_detail.tscn")
const AuthDialogScene := preload("res://scenes/sidebar/guild_bar/auth_dialog.tscn")

var _all_spaces: Array = []
var _active_tag: String = ""
var _search_timer: Timer
var _detail_view: VBoxContainer = null
var _embedded := false
var _ping_cache: Dictionary = {}  # server_url -> int (ms)

@onready var _margin: MarginContainer = $Margin
@onready var _header: HBoxContainer = $Margin/VBox/Header
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

	if _embedded:
		_apply_embedded()
		activate()

func activate() -> void:
	_update_grid_columns()
	_fetch_directory()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_grid_columns()

func set_embedded(value: bool) -> void:
	_embedded = value
	if is_node_ready():
		_apply_embedded()
		if _embedded:
			activate()

func _apply_embedded() -> void:
	_header.visible = not _embedded
	if _embedded:
		ThemeManager.set_margins(_margin, 8, 8, 8, 8)
		_grid.columns = 1

func _update_grid_columns() -> void:
	if not is_instance_valid(_grid):
		return
	if _embedded:
		_grid.columns = 1
		return
	var w := size.x
	if w < 500:
		_grid.columns = 1
	elif w < 800:
		_grid.columns = 2
	else:
		_grid.columns = 3

func _apply_theme() -> void:
	add_theme_stylebox_override("panel", ThemeManager.make_flat_style("panel_bg"))

	_search_input.add_theme_color_override("font_color", ThemeManager.get_color("text_body"))
	var input_style := ThemeManager.make_flat_style("input_bg", 4, [12, 8, 12, 8])
	_search_input.add_theme_stylebox_override("normal", input_style)
	_search_input.add_theme_stylebox_override("focus", input_style)

func _fetch_directory(query: String = "", tag: String = "") -> void:
	_show_status(tr("Loading servers..."))
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
		var msg: String = result.error.message if result.error else tr("Failed to load directory")
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
		_show_status(tr("No servers found"))
		return

	_status_label.visible = false
	_populate_grid(spaces)
	_populate_tags(spaces)
	_ping_servers(spaces)


func _is_space_joined(space_data: Dictionary) -> bool:
	var space_id: String = space_data.get("space_id", space_data.get("id", ""))
	if space_id.is_empty():
		return false
	var server_url: String = space_data.get("server_url", "")
	var normalized := _normalize_url(server_url)
	for space in Client.spaces:
		if space.get("id", "") != space_id:
			continue
		# Match server URL to avoid false positives across servers
		var conn_idx: int = Client.get_conn_index_for_space(space_id)
		if conn_idx < 0:
			continue
		var base_url: String = Client.get_base_url_for_space(space_id)
		if _normalize_url(base_url) == normalized:
			return true
	return false

func _populate_grid(spaces: Array) -> void:
	_clear_grid()
	for space in spaces:
		var card: PanelContainer = DiscoveryCardScene.instantiate()
		_grid.add_child(card)
		card.setup(space, _is_space_joined(space))
		card.card_clicked.connect(_on_card_clicked)

func _clear_grid() -> void:
	NodeUtils.free_children(_grid)

func _populate_tags(spaces: Array) -> void:
	# Clear existing tags
	NodeUtils.free_children(_tag_bar)

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
	all_btn.text = tr("All")
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
	var margins := [12, 4, 12, 4]
	if active:
		btn.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
		btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style("accent", 12, margins))
		btn.add_theme_stylebox_override("hover",
			ThemeManager.make_flat_style("accent_hover", 12, margins))
	else:
		btn.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_body"))
		btn.add_theme_stylebox_override("normal",
			ThemeManager.make_flat_style("secondary_button", 12, margins))
		btn.add_theme_stylebox_override("hover",
			ThemeManager.make_flat_style(
				"secondary_button_hover", 12, margins))

func _ping_servers(spaces: Array) -> void:
	# Collect unique server URLs
	var urls: Dictionary = {}
	for space in spaces:
		var url: String = space.get("server_url", "")
		if not url.is_empty():
			urls[url] = true

	for url in urls:
		if _ping_cache.has(url):
			_apply_ping_to_cards(url, _ping_cache[url])
		else:
			_ping_server(url)

func _ping_server(server_url: String) -> void:
	# Parse host and port from URL for TCP-only latency measurement
	var stripped: String = server_url.rstrip("/")
	var host: String = stripped
	if host.begins_with("https://"):
		host = host.substr(8)
	elif host.begins_with("http://"):
		host = host.substr(7)

	var port: int = 443 if stripped.begins_with("https://") else 80
	var colon_idx: int = host.rfind(":")
	if colon_idx != -1:
		var port_str: String = host.substr(colon_idx + 1)
		if port_str.is_valid_int():
			port = port_str.to_int()
		host = host.substr(0, colon_idx)

	# Strip any path component
	var slash_idx: int = host.find("/")
	if slash_idx != -1:
		host = host.substr(0, slash_idx)

	var tcp := StreamPeerTCP.new()
	var start := Time.get_ticks_msec()
	var err := tcp.connect_to_host(host, port)
	if err != OK:
		return

	# Poll until connected or failed (timeout after 5 seconds)
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - start > 5000:
			tcp.disconnect_from_host()
			return
		tcp.poll()
		await get_tree().process_frame

	if not is_instance_valid(self):
		return

	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var ms: int = Time.get_ticks_msec() - start
	tcp.disconnect_from_host()
	_ping_cache[server_url] = ms
	_apply_ping_to_cards(server_url, ms)

func _apply_ping_to_cards(server_url: String, ms: int) -> void:
	for card in _grid.get_children():
		if not is_instance_valid(card):
			continue
		if card.has_method("set_ping") and card._data.get("server_url", "") == server_url:
			card.set_ping(ms)
	if _detail_view and is_instance_valid(_detail_view) and _detail_view.has_method("set_ping"):
		if _detail_view._data.get("server_url", "") == server_url:
			_detail_view.set_ping(ms)

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
	NodeUtils.free_children(_detail_container)

	_detail_view = DiscoveryDetailScene.instantiate()
	_detail_container.add_child(_detail_view)
	_detail_view.setup(space_data, _is_space_joined(space_data))
	_detail_view.back_pressed.connect(_on_detail_back)
	_detail_view.join_pressed.connect(_on_detail_join_with_slug)
	_detail_view.preview_pressed.connect(_on_detail_preview)

	# Apply cached ping to detail view
	var server_url: String = space_data.get("server_url", "")
	if _ping_cache.has(server_url):
		_detail_view.set_ping(_ping_cache[server_url])
	else:
		_ping_server(server_url)

func _on_detail_back() -> void:
	_detail_container.visible = false
	if _detail_view:
		_detail_view.queue_free()
		_detail_view = null
	_scroll.visible = true
	_tag_bar.visible = true
	_search_input.visible = true

func _on_detail_join_with_slug(server_url: String, space_id: String, space_slug: String) -> void:
	if _embedded:
		join_requested.emit(server_url, space_id, space_slug)
		return

	# Check if already connected to this server (with URL normalization)
	var normalized_url := _normalize_url(server_url)
	var servers := Config.get_servers()
	for i in servers.size():
		var server: Dictionary = servers[i]
		if _normalize_url(server["base_url"]) == normalized_url \
				and Client.is_server_connected(i):
			# Already have credentials — join directly
			_join_and_connect(
				server_url, space_id, space_slug,
				server.get("token", ""),
				server.get("username", ""),
				server.get("display_name", ""),
			)
			return

	# No existing account — show auth dialog
	var auth_dialog := AuthDialogScene.instantiate()
	auth_dialog.setup(server_url)
	auth_dialog.auth_completed.connect(
		func(resolved_url: String, t: String, u: String, _p: String, dn: String):
			_join_and_connect(resolved_url, space_id, space_slug, t, u, dn)
	)
	get_tree().root.add_child(auth_dialog)

func _join_and_connect(
	url: String, space_id: String, space_slug: String,
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
		var msg: String = result.error.message if result.error else tr("Failed to join space")
		if _detail_view and is_instance_valid(_detail_view):
			_detail_view.show_error(msg)
		return

	# Successfully joined — save config with slug (used by connect_server to match)
	Config.add_server(url, token, space_slug, username, display_name)
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

func _on_detail_preview(server_url: String, space_id: String) -> void:
	# Connect as guest to preview the space without creating an account
	var api_url := server_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	add_child(rest)
	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.guest()
	rest.queue_free()

	if not is_instance_valid(self):
		return

	if not result.ok:
		var msg: String = (
			result.error.message if result.error else "Preview not available"
		)
		if _detail_view and is_instance_valid(_detail_view):
			_detail_view.show_error(msg)
		return

	var token: String = result.data.get("token", "")
	var expires_at: String = result.data.get("expires_at", "")
	if token.is_empty():
		if _detail_view and is_instance_valid(_detail_view):
			_detail_view.show_error("Failed to get guest token")
		return

	# Close discovery and connect as guest
	AppState.close_discovery()
	var connect_result: Dictionary = await Client.connect_guest(
		server_url, token, space_id, expires_at
	)

	if not is_instance_valid(self):
		return

	if connect_result.has("error"):
		push_warning("[Discovery] Guest preview failed: ", connect_result["error"])
		return

	if not connect_result.get("space_id", "").is_empty():
		AppState.select_space(connect_result["space_id"])

func _on_close() -> void:
	if not _embedded:
		AppState.close_discovery()


## Normalizes a server URL for comparison: lowercases scheme and host,
## strips trailing slashes, and removes default port for the scheme.
static func _normalize_url(url: String) -> String:
	var s := url.strip_edges().to_lower().rstrip("/")
	# Remove default ports
	s = s.replace(":443", "").replace(":80", "")
	# Normalize scheme — treat http/https as equivalent for matching
	if s.begins_with("http://"):
		s = s.substr(7)
	elif s.begins_with("https://"):
		s = s.substr(8)
	return s
