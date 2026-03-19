class_name ClientTestApiState
extends RefCounted

## State, screenshot, and theme endpoint handlers for ClientTestApi.

var _c: Node


func _init(client_node: Node) -> void:
	_c = client_node


func endpoint_get_state(_args: Dictionary) -> Dictionary:
	var viewport: Viewport = _c.get_viewport()
	var vp_size: Vector2 = (
		viewport.get_visible_rect().size if viewport else Vector2.ZERO
	)
	return {
		"ok": true,
		"space_id": AppState.current_space_id,
		"channel_id": AppState.current_channel_id,
		"is_dm_mode": AppState.is_dm_mode,
		"layout_mode": layout_mode_str(),
		"viewport_size": {
			"width": int(vp_size.x), "height": int(vp_size.y)
		},
		"member_list_visible": AppState.member_list_visible,
		"search_open": AppState.search_open,
		"thread_open": AppState.thread_panel_visible,
		"thread_id": AppState.current_thread_id,
		"discovery_open": AppState.is_discovery_open,
		"voice_channel_id": AppState.voice_channel_id,
		"voice_view_open": AppState.is_voice_view_open,
		"connected_servers": count_connected(),
		"space_count": _c._space_cache.size(),
		"user_id": _c.current_user.get("id", ""),
		"username": _c.current_user.get("username", ""),
	}


func endpoint_list_spaces(_args: Dictionary) -> Dictionary:
	var spaces: Array = []
	for s in _c._space_cache.values():
		spaces.append({
			"id": s.get("id", ""),
			"name": s.get("name", ""),
			"icon": s.get("icon", ""),
			"owner_id": s.get("owner_id", ""),
			"member_count": s.get("member_count", 0),
		})
	return {"ok": true, "spaces": spaces}


func endpoint_get_space(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	var space: Dictionary = _c._space_cache.get(space_id, {})
	if space.is_empty():
		return {"error": "Space not found: %s" % space_id}
	return {"ok": true, "space": space}


func endpoint_list_channels(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	var channels: Array = _c.get_channels_for_space(space_id)
	var result: Array = []
	for ch in channels:
		result.append({
			"id": ch.get("id", ""),
			"name": ch.get("name", ""),
			"type": ch.get("type", ""),
			"parent_id": ch.get("parent_id", ""),
			"topic": ch.get("topic", ""),
			"position": ch.get("position", 0),
		})
	return {"ok": true, "channels": result}


func endpoint_list_members(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	var members: Array = _c.get_members_for_space(space_id)
	var result: Array = []
	for m in members:
		result.append({
			"id": m.get("id", ""),
			"username": m.get("username", ""),
			"display_name": m.get("display_name", ""),
			"status": m.get("status", 0),
			"roles": m.get("roles", []),
		})
	return {"ok": true, "members": result}


func endpoint_list_messages(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	var limit: int = args.get("limit", 50)
	var messages: Array = _c.get_messages_for_channel(channel_id)
	if messages.size() > limit:
		messages = messages.slice(messages.size() - limit)
	var result: Array = []
	for msg in messages:
		result.append({
			"id": msg.get("id", ""),
			"content": msg.get("content", ""),
			"author_id": msg.get("author_id", ""),
			"author_username": msg.get("author_username", ""),
			"timestamp": msg.get("timestamp", ""),
			"edited_timestamp": msg.get("edited_timestamp", ""),
			"reply_to": msg.get("reply_to", ""),
			"reactions": msg.get("reactions", []),
		})
	return {"ok": true, "messages": result}


func endpoint_search_messages(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	if query.is_empty():
		return {"error": "query is required"}
	var space_id: String = args.get(
		"space_id", AppState.current_space_id
	)
	if space_id.is_empty():
		return {"error": "No space context for search"}
	var result: Dictionary = await _c.search_messages(
		space_id, query, args
	)
	return {"ok": true, "results": result}


func endpoint_get_user(args: Dictionary) -> Dictionary:
	var user_id: String = args.get("user_id", "")
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var user: Dictionary = _c.get_user_by_id(user_id)
	if user.is_empty():
		return {"error": "User not found: %s" % user_id}
	return {
		"ok": true,
		"user": {
			"id": user.get("id", ""),
			"username": user.get("username", ""),
			"display_name": user.get("display_name", ""),
			"avatar": user.get("avatar", ""),
			"status": user.get("status", 0),
		},
	}


func endpoint_screenshot(args: Dictionary) -> Dictionary:
	var viewport: Viewport = _c.get_viewport()
	if viewport == null:
		return {"error": "No viewport available"}
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return {"error": "Failed to capture viewport"}
	var x: int = args.get("x", 0)
	var y: int = args.get("y", 0)
	var w: int = args.get("width", 0)
	var h: int = args.get("height", 0)
	if w > 0 and h > 0:
		image = image.get_region(Rect2i(x, y, w, h))
	var save_path: String = args.get("save_path", "")
	if not save_path.is_empty():
		var dir: String = save_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		image.save_png(save_path)
	var png_buf: PackedByteArray = image.save_png_to_buffer()
	return {
		"ok": true,
		"image_base64": Marshalls.raw_to_base64(png_buf),
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"size_bytes": png_buf.size(),
	}


func endpoint_get_design_tokens(
	_args: Dictionary,
) -> Dictionary:
	var palette: Dictionary = ThemeManager.get_palette()
	var tokens: Dictionary = {}
	for key in palette:
		tokens[key] = (palette[key] as Color).to_html(true)
	return {
		"ok": true,
		"tokens": tokens,
		"presets": ThemeManager.get_preset_names(),
		"current_preset": Config.get_theme_preset(),
	}


func endpoint_set_theme(args: Dictionary) -> Dictionary:
	var preset: String = args.get("preset", "")
	var theme_string: String = args.get("theme_string", "")
	if not preset.is_empty():
		var valid: Array = ThemeManager.get_preset_names()
		if not preset in valid:
			return {
				"error": "Unknown preset: %s. Valid: %s"
				% [preset, ", ".join(valid)],
			}
		ThemeManager.apply_preset(preset)
		await _c.get_tree().process_frame
		return {"ok": true, "preset": preset}
	if not theme_string.is_empty():
		var ok: bool = ThemeManager.import_theme_string(
			theme_string
		)
		if not ok:
			return {"error": "Invalid theme string"}
		await _c.get_tree().process_frame
		return {"ok": true, "preset": "custom"}
	return {"error": "preset or theme_string is required"}


func layout_mode_str() -> String:
	match AppState.current_layout_mode:
		AppState.LayoutMode.COMPACT: return "COMPACT"
		AppState.LayoutMode.MEDIUM: return "MEDIUM"
		AppState.LayoutMode.FULL: return "FULL"
		_: return "UNKNOWN"


func count_connected() -> int:
	var count: int = 0
	for conn in _c._connections:
		if conn != null and conn.get("status", "") == "connected":
			count += 1
	return count
