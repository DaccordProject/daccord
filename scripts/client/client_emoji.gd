class_name ClientEmoji
extends RefCounted

## Handles custom emoji downloading and caching for Client.

const EMOJI_CACHE_MAX_FILES := 500

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func register(
	space_id: String, emoji_id: String,
	emoji_name: String,
) -> void:
	if emoji_id.is_empty() or emoji_name.is_empty():
		return
	# Already cached on disk
	var cache_path := Config.get_emoji_cache_path(emoji_id)
	if FileAccess.file_exists(cache_path):
		ClientModels.custom_emoji_paths[emoji_name] = cache_path
		return
	# Already downloading
	if _c._emoji_download_pending.has(emoji_id):
		return
	_c._emoji_download_pending[emoji_id] = true
	# Ensure cache directory exists
	DirAccess.make_dir_recursive_absolute(Config._profile_emoji_cache_dir())
	var url: String = _c.admin.get_emoji_url(space_id, emoji_id)
	var http := HTTPRequest.new()
	_c.add_child(http)
	http.request_completed.connect(func(
		_result_code: int, response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray,
	) -> void:
		http.queue_free()
		_c._emoji_download_pending.erase(emoji_id)
		if response_code != 200:
			return
		var img := Image.new()
		var err := img.load_png_from_buffer(body)
		if err != OK:
			return
		img.save_png(cache_path)
		ClientModels.custom_emoji_paths[emoji_name] = cache_path
		var tex := ImageTexture.create_from_image(img)
		ClientModels.custom_emoji_textures[emoji_name] = tex
		_evict_cache_if_needed()
	)
	http.request(url)

func register_texture(
	emoji_name: String, texture: Texture2D,
) -> void:
	ClientModels.custom_emoji_textures[emoji_name] = texture

## Trims the user cache if it exceeds the cap.
## Preserves the current user and users referenced by current
## space members; evicts the rest.
func trim_user_cache() -> void:
	if _c._user_cache.size() <= _c.USER_CACHE_CAP:
		return
	var keep: Dictionary = {}
	var my_id: String = _c.current_user.get("id", "")
	if not my_id.is_empty():
		keep[my_id] = true
	var gid: String = AppState.current_space_id
	if _c._member_cache.has(gid):
		for m in _c._member_cache[gid]:
			keep[m.get("id", "")] = true
	var cid: String = AppState.current_channel_id
	if _c._message_cache.has(cid):
		for msg in _c._message_cache[cid]:
			var author: Dictionary = msg.get("author", {})
			keep[author.get("id", "")] = true
	var to_erase: Array = []
	for uid in _c._user_cache:
		if not keep.has(uid):
			to_erase.append(uid)
	for uid in to_erase:
		_c._user_cache.erase(uid)


## Evicts the oldest emoji files when the cache exceeds EMOJI_CACHE_MAX_FILES.
func _evict_cache_if_needed() -> void:
	var cache_dir: String = Config._profile_emoji_cache_dir()
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	# Collect all .png files with their modification times
	var files: Array = [] # [{path, mtime}]
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".png"):
			var full_path: String = cache_dir + "/" + fname
			var mtime: int = FileAccess.get_modified_time(full_path)
			if mtime >= 0:
				files.append({"path": full_path, "mtime": mtime})
		fname = dir.get_next()
	dir.list_dir_end()
	if files.size() <= EMOJI_CACHE_MAX_FILES:
		return
	# Sort oldest first
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.mtime < b.mtime
	)
	var to_remove: int = files.size() - EMOJI_CACHE_MAX_FILES
	for i in to_remove:
		var err := DirAccess.remove_absolute(files[i].path)
		if err != OK:
			push_warning(
				"emoji cache: failed to evict %s (err %d)"
				% [files[i].path, err]
			)
