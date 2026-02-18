extends Node

const CONFIG_PATH := "user://config.cfg"

var _config := ConfigFile.new()

func _ready() -> void:
	_config.load(CONFIG_PATH)

func get_servers() -> Array:
	var count: int = _config.get_value("servers", "count", 0)
	var servers: Array = []
	for i in count:
		var section := "server_%d" % i
		servers.append({
			"base_url": _config.get_value(section, "base_url", ""),
			"token": _config.get_value(section, "token", ""),
			"guild_name": _config.get_value(section, "guild_name", ""),
		})
	return servers

func add_server(base_url: String, token: String, guild_name: String) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	var section := "server_%d" % count
	_config.set_value(section, "base_url", base_url)
	_config.set_value(section, "token", token)
	_config.set_value(section, "guild_name", guild_name)
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

func has_servers() -> bool:
	return _config.get_value("servers", "count", 0) > 0

func save() -> void:
	_config.save(CONFIG_PATH)

func clear() -> void:
	var count: int = _config.get_value("servers", "count", 0)
	for i in count:
		var section := "server_%d" % i
		if _config.has_section(section):
			_config.erase_section(section)
	_config.set_value("servers", "count", 0)
	save()
