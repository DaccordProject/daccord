extends Node

const CONFIG_PATH := "user://config.cfg"
const _SALT := "daccord-config-v1"

var _config := ConfigFile.new()

func _ready() -> void:
	var key := _derive_key()
	var err := _config.load_encrypted_pass(CONFIG_PATH, key)
	if err != OK:
		# Fall back to plaintext (first run or migration from unencrypted)
		var plain_err := _config.load(CONFIG_PATH)
		if plain_err == OK:
			# Re-save encrypted to migrate
			_config.save_encrypted_pass(CONFIG_PATH, key)

func _derive_key() -> String:
	return _SALT + OS.get_user_data_dir()

func get_servers() -> Array:
	var count: int = _config.get_value("servers", "count", 0)
	var servers: Array = []
	for i in count:
		var section := "server_%d" % i
		servers.append({
			"base_url": _config.get_value(section, "base_url", ""),
			"token": _config.get_value(section, "token", ""),
			"guild_name": _config.get_value(section, "guild_name", ""),
			"username": _config.get_value(section, "username", ""),
			"password": _config.get_value(section, "password", ""),
		})
	return servers

func add_server(
	base_url: String, token: String, guild_name: String,
	username: String = "", password: String = "",
) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	var section := "server_%d" % count
	_config.set_value(section, "base_url", base_url)
	_config.set_value(section, "token", token)
	_config.set_value(section, "guild_name", guild_name)
	_config.set_value(section, "username", username)
	_config.set_value(section, "password", password)
	_config.set_value("servers", "count", count + 1)
	save()

func remove_server(index: int) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	# Shift entries down
	for i in range(index, count - 1):
		var src := "server_%d" % (i + 1)
		var dst := "server_%d" % i
		_config.set_value(dst, "base_url", _config.get_value(src, "base_url", ""))
		_config.set_value(dst, "token", _config.get_value(src, "token", ""))
		_config.set_value(dst, "guild_name", _config.get_value(src, "guild_name", ""))
		_config.set_value(dst, "username", _config.get_value(src, "username", ""))
		_config.set_value(dst, "password", _config.get_value(src, "password", ""))
	# Erase last section
	var last := "server_%d" % (count - 1)
	if _config.has_section(last):
		_config.erase_section(last)
	_config.set_value("servers", "count", count - 1)
	save()

func update_server_url(index: int, new_url: String) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "base_url", new_url)
	save()

func update_server_token(index: int, new_token: String) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "token", new_token)
	save()

func has_servers() -> bool:
	return _config.get_value("servers", "count", 0) > 0

func save() -> void:
	_config.save_encrypted_pass(CONFIG_PATH, _derive_key())

func set_last_selection(guild_id: String, channel_id: String) -> void:
	_config.set_value("state", "last_guild_id", guild_id)
	_config.set_value("state", "last_channel_id", channel_id)
	save()

func get_last_selection() -> Dictionary:
	return {
		"guild_id": _config.get_value("state", "last_guild_id", ""),
		"channel_id": _config.get_value("state", "last_channel_id", ""),
	}

func set_category_collapsed(guild_id: String, category_id: String, collapsed: bool) -> void:
	var section := "collapsed_%s" % guild_id
	_config.set_value(section, category_id, collapsed)
	save()

func is_category_collapsed(guild_id: String, category_id: String) -> bool:
	var section := "collapsed_%s" % guild_id
	return _config.get_value(section, category_id, false)

func get_voice_input_device() -> String:
	return _config.get_value("voice", "input_device", "")

func set_voice_input_device(device_id: String) -> void:
	_config.set_value("voice", "input_device", device_id)
	save()

func clear() -> void:
	var count: int = _config.get_value("servers", "count", 0)
	for i in count:
		var section := "server_%d" % i
		if _config.has_section(section):
			_config.erase_section(section)
	_config.set_value("servers", "count", 0)
	save()
