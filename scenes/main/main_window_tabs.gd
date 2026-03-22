extends RefCounted

const AvatarScript := preload("res://scenes/common/avatar.gd")
const TAB_ICON_HEIGHT := 16

var tabs: Array[Dictionary] = []

var _tab_bar: TabBar
var _parent: Node
var _header_spacer: Control
var _space_icon_cache: Dictionary = {}


func _init(
	p_tab_bar: TabBar, parent: Node,
	p_header_spacer: Control = null,
) -> void:
	_tab_bar = p_tab_bar
	_parent = parent
	_header_spacer = p_header_spacer


func add_tab(
	tab_name: String, channel_id: String, space_id: String,
) -> void:
	tabs.append({
		"name": tab_name,
		"channel_id": channel_id,
		"space_id": space_id,
	})
	_tab_bar.add_tab(tab_name)
	_tab_bar.current_tab = tabs.size() - 1
	update_visibility()
	update_icons()


func find_tab(channel_id: String) -> int:
	for i in tabs.size():
		if tabs[i]["channel_id"] == channel_id:
			return i
	return -1


func on_tab_changed(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < tabs.size():
		var channel_id: String = tabs[tab_index]["channel_id"]
		var space_id: String = tabs[tab_index]["space_id"]
		AppState.select_channel(channel_id)
		Config.set_last_selection(space_id, channel_id)


func on_tab_close(tab_index: int) -> void:
	if tabs.size() <= 1:
		return
	tabs.remove_at(tab_index)
	_tab_bar.remove_tab(tab_index)
	if (
		_tab_bar.current_tab >= 0
		and _tab_bar.current_tab < tabs.size()
	):
		var tab: Dictionary = tabs[_tab_bar.current_tab]
		AppState.select_channel(tab["channel_id"])
		Config.set_last_selection(
			tab["space_id"], tab["channel_id"],
		)
	update_visibility()
	update_icons()


func on_tab_rearranged(idx_to: int) -> void:
	var active_channel_id: String = AppState.current_channel_id
	var idx_from: int = -1
	for i in tabs.size():
		if tabs[i]["channel_id"] == active_channel_id:
			idx_from = i
			break
	if idx_from == -1 or idx_from == idx_to:
		return
	var tab_data: Dictionary = tabs[idx_from]
	tabs.remove_at(idx_from)
	tabs.insert(idx_to, tab_data)
	update_icons()


func remove_tabs_for_space(space_id: String) -> void:
	var i: int = tabs.size() - 1
	while i >= 0:
		if tabs[i].get("space_id", "") == space_id:
			tabs.remove_at(i)
			_tab_bar.remove_tab(i)
		i -= 1


func update_visibility() -> void:
	var show_tabs: bool = tabs.size() > 1
	_tab_bar.visible = show_tabs
	if _header_spacer:
		_header_spacer.visible = not show_tabs


func update_icons() -> void:
	var name_count: Dictionary = {}
	for tab in tabs:
		var n: String = tab["name"]
		name_count[n] = name_count.get(n, 0) + 1
	for i in tabs.size():
		if name_count[tabs[i]["name"]] > 1:
			_set_space_icon_for_tab(i)
		else:
			_tab_bar.set_tab_icon(i, null)


func clear_all() -> void:
	tabs.clear()
	_tab_bar.clear_tabs()
	_space_icon_cache.clear()
	update_visibility()


func select_current() -> void:
	if (
		_tab_bar.current_tab >= 0
		and _tab_bar.current_tab < tabs.size()
	):
		var cid: String = (
			tabs[_tab_bar.current_tab]["channel_id"]
		)
		AppState.select_channel(cid)


func _set_space_icon_for_tab(tab_index: int) -> void:
	var space_id: String = tabs[tab_index].get(
		"space_id", "",
	)
	if space_id.is_empty():
		_tab_bar.set_tab_icon(tab_index, null)
		return
	if _space_icon_cache.has(space_id):
		_tab_bar.set_tab_icon(
			tab_index, _space_icon_cache[space_id],
		)
		return
	var space: Dictionary = Client.get_space_by_id(space_id)
	if space.is_empty():
		_tab_bar.set_tab_icon(tab_index, null)
		return
	var icon_url_value = space.get("icon", "")
	var icon_url: String = (
		icon_url_value if icon_url_value != null else ""
	)
	if icon_url.is_empty():
		var tex: ImageTexture = _create_color_swatch(
			space.get("icon_color", Color.GRAY),
		)
		_space_icon_cache[space_id] = tex
		_tab_bar.set_tab_icon(tab_index, tex)
		return
	if AvatarScript._image_cache.has(icon_url):
		var full_tex: ImageTexture = (
			AvatarScript._image_cache[icon_url]
		)
		var tex: ImageTexture = _resize_for_tab(
			full_tex.get_image(),
		)
		_space_icon_cache[space_id] = tex
		_tab_bar.set_tab_icon(tab_index, tex)
		return
	var http := HTTPRequest.new()
	_parent.add_child(http)
	http.request_completed.connect(
		_on_tab_icon_loaded.bind(space_id, http),
	)
	http.request(icon_url)


func _on_tab_icon_loaded(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray,
	space_id: String, http: HTTPRequest,
) -> void:
	http.queue_free()
	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code != 200
	):
		return
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		return
	var tex: ImageTexture = _resize_for_tab(image)
	_space_icon_cache[space_id] = tex
	update_icons()


func _resize_for_tab(image: Image) -> ImageTexture:
	var src_w: int = image.get_width()
	var src_h: int = image.get_height()
	if src_h <= 0:
		image.resize(TAB_ICON_HEIGHT, TAB_ICON_HEIGHT)
	else:
		var aspect: float = float(src_w) / float(src_h)
		var new_h: int = TAB_ICON_HEIGHT
		var new_w: int = maxi(1, int(round(new_h * aspect)))
		image.resize(new_w, new_h)
	return ImageTexture.create_from_image(image)


func handle_tab_bar_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var i: int = _tab_bar.current_tab
	if i < 0 or i >= _tab_bar.tab_count:
		return
	var close_icon: Texture2D = _tab_bar.get_theme_icon("close")
	if close_icon == null:
		return
	var icon_size: Vector2 = close_icon.get_size()
	var tab_rect: Rect2 = _tab_bar.get_tab_rect(i)
	var style: StyleBox = _tab_bar.get_theme_stylebox(
		"tab_selected",
	)
	var right_margin: float = (
		style.content_margin_right if style else 0.0
	)
	var close_rect := Rect2(
		Vector2(
			tab_rect.end.x - right_margin - icon_size.x,
			tab_rect.position.y
			+ (tab_rect.size.y - icon_size.y) / 2.0,
		),
		icon_size,
	)
	if close_rect.has_point(event.position):
		on_tab_close(i)
		_tab_bar.accept_event()


func _create_color_swatch(
	c: Color, px: int = TAB_ICON_HEIGHT,
) -> ImageTexture:
	var img: Image = Image.new()
	var data := PackedByteArray()
	data.resize(px * px * 4)
	img.set_data(px, px, false, Image.FORMAT_RGBA8, data)
	img.fill(c)
	return ImageTexture.create_from_image(img)
