extends RefCounted

const AvatarScript := preload("res://scenes/common/avatar.gd")

var tabs: Array[Dictionary] = []

var _tab_bar: TabBar
var _parent: Node
var _space_icon_cache: Dictionary = {}


func _init(p_tab_bar: TabBar, parent: Node) -> void:
	_tab_bar = p_tab_bar
	_parent = parent


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
		AppState.select_channel(channel_id)


func on_tab_close(tab_index: int) -> void:
	if tabs.size() <= 1:
		return
	tabs.remove_at(tab_index)
	_tab_bar.remove_tab(tab_index)
	if (
		_tab_bar.current_tab >= 0
		and _tab_bar.current_tab < tabs.size()
	):
		var channel_id: String = (
			tabs[_tab_bar.current_tab]["channel_id"]
		)
		AppState.select_channel(channel_id)
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
	_tab_bar.visible = tabs.size() > 1


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
		var tex: ImageTexture = (
			AvatarScript._image_cache[icon_url]
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
	image.resize(16, 16)
	var tex := ImageTexture.create_from_image(image)
	_space_icon_cache[space_id] = tex
	update_icons()


func _create_color_swatch(
	c: Color, px: int = 16,
) -> ImageTexture:
	var img: Image = Image.new()
	var data := PackedByteArray()
	data.resize(px * px * 4)
	img.set_data(px, px, false, Image.FORMAT_RGBA8, data)
	img.fill(c)
	return ImageTexture.create_from_image(img)
