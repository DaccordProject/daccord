extends RefCounted
## Profile management helper for Config.
## Handles CRUD operations on profiles stored in the profile registry.

const REGISTRY_PATH := "user://profile_registry.cfg"

var _parent # Config singleton
var _profile_salt: String


func _init(parent, profile_salt: String) -> void:
	_parent = parent
	_profile_salt = profile_salt


func get_profiles() -> Array:
	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	var result: Array = []
	for slug in order:
		var section: String = "profile_" + str(slug)
		var pname: String = reg.get_value(section, "name", slug)
		var has_pw: bool = reg.has_section_key(
			section, "password_hash"
		)
		result.append({
			"slug": slug,
			"name": pname,
			"has_password": has_pw,
		})
	return result


func get_active_slug() -> String:
	return _parent._profile_slug


func create(
	pname: String, pw: String = "",
	copy_current: bool = false,
) -> String:
	var slug := _slugify(pname)
	var new_dir := "user://profiles/" + slug
	DirAccess.make_dir_recursive_absolute(new_dir)

	if copy_current:
		var cur_cfg: String = _parent._config_path()
		if FileAccess.file_exists(cur_cfg):
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(cur_cfg),
				ProjectSettings.globalize_path(
					new_dir + "/config.cfg"
				)
			)
		var cur_emoji: String = _parent._profile_emoji_cache_dir()
		if DirAccess.dir_exists_absolute(cur_emoji):
			var emoji_dst := new_dir + "/emoji_cache"
			DirAccess.make_dir_recursive_absolute(emoji_dst)
			_parent._copy_directory(cur_emoji, emoji_dst)

	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	order.append(slug)
	reg.set_value("order", "list", order)
	var section := "profile_" + slug
	reg.set_value(section, "name", pname)
	if not pw.is_empty():
		reg.set_value(
			section, "password_hash",
			_hash_password(slug, pw)
		)
	reg.save(REGISTRY_PATH)
	return slug


func delete(slug: String) -> bool:
	if slug == "default":
		return false
	if slug == _parent._profile_slug:
		switch("default")
	var dir_path := "user://profiles/" + slug
	if DirAccess.dir_exists_absolute(dir_path):
		var emoji_dir := dir_path + "/emoji_cache"
		if DirAccess.dir_exists_absolute(emoji_dir):
			_parent._remove_directory_recursive(emoji_dir)
		_parent._remove_directory_recursive(dir_path)
	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	var idx := order.find(slug)
	if idx != -1:
		order.remove_at(idx)
	reg.set_value("order", "list", order)
	var section := "profile_" + slug
	if reg.has_section(section):
		reg.erase_section(section)
	reg.save(REGISTRY_PATH)
	return true


func switch(slug: String) -> void:
	_parent._profile_slug = slug
	if _parent._cli_profile_override.is_empty():
		_parent._registry.set_value("state", "active", slug)
		_parent._registry.save(REGISTRY_PATH)
	_parent._config = ConfigFile.new()
	_parent._load_ok = false
	_parent._last_backup_time = 0
	_parent._load_profile_config()
	AppState.profile_switched.emit()


func rename(slug: String, new_name: String) -> void:
	var section := "profile_" + slug
	_parent._registry.set_value(section, "name", new_name)
	_parent._registry.save(REGISTRY_PATH)


func set_password(
	slug: String, old_pw: String, new_pw: String,
) -> bool:
	var reg: ConfigFile = _parent._registry
	var section := "profile_" + slug
	if reg.has_section_key(section, "password_hash"):
		var stored: String = reg.get_value(
			section, "password_hash", ""
		)
		if _hash_password(slug, old_pw) != stored:
			return false
	if new_pw.is_empty():
		reg.set_value(section, "password_hash", null)
	else:
		reg.set_value(
			section, "password_hash",
			_hash_password(slug, new_pw),
		)
	reg.save(REGISTRY_PATH)
	return true


func verify_password(slug: String, pw: String) -> bool:
	var reg: ConfigFile = _parent._registry
	var section := "profile_" + slug
	if not reg.has_section_key(section, "password_hash"):
		return true
	var stored: String = reg.get_value(
		section, "password_hash", ""
	)
	return _hash_password(slug, pw) == stored


func move_up(slug: String) -> void:
	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	var idx := order.find(slug)
	if idx <= 0:
		return
	var temp = order[idx - 1]
	order[idx - 1] = order[idx]
	order[idx] = temp
	reg.set_value("order", "list", order)
	reg.save(REGISTRY_PATH)


func move_down(slug: String) -> void:
	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	var idx := order.find(slug)
	if idx == -1 or idx >= order.size() - 1:
		return
	var temp = order[idx + 1]
	order[idx + 1] = order[idx]
	order[idx] = temp
	reg.set_value("order", "list", order)
	reg.save(REGISTRY_PATH)


# --- Internal helpers ---

func _slugify(pname: String) -> String:
	var slug := pname.to_lower().strip_edges()
	slug = slug.replace(" ", "-").replace("_", "-")
	var clean := ""
	for ch in slug:
		if ch == "-" or (ch >= "a" and ch <= "z") \
				or (ch >= "0" and ch <= "9"):
			clean += ch
	slug = clean
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	slug = slug.trim_prefix("-").trim_suffix("-")
	if slug.is_empty():
		slug = "profile"
	if slug.length() > 32:
		slug = slug.substr(0, 32).trim_suffix("-")
	var reg: ConfigFile = _parent._registry
	var order: Array = reg.get_value("order", "list", [])
	if slug in order:
		var counter := 2
		while (slug + "-" + str(counter)) in order:
			counter += 1
		slug = slug + "-" + str(counter)
	return slug


func _hash_password(slug: String, pw: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var input := (
		_profile_salt + slug + pw
	).to_utf8_buffer()
	ctx.update(input)
	var digest := ctx.finish()
	return digest.hex_encode()
