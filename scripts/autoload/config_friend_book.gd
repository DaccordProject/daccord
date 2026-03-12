class_name ConfigFriendBook
extends RefCounted

## Friend book persistence helpers extracted from Config.
## Manages local cross-server relationship entries in the config file.

var _host  # Config autoload (untyped for internal access)


func _init(host) -> void:
	_host = host


func get_entries() -> Array:
	var cfg: ConfigFile = _host._config
	var count: int = cfg.get_value("friend_book", "count", 0)
	var entries: Array = []
	for i in count:
		var section := "friend_book_%d" % i
		entries.append({
			"user_id": cfg.get_value(section, "user_id", ""),
			"display_name": cfg.get_value(
				section, "display_name", ""
			),
			"username": cfg.get_value(section, "username", ""),
			"avatar_hash": cfg.get_value(
				section, "avatar_hash", ""
			),
			"server_url": cfg.get_value(
				section, "server_url", ""
			),
			"space_name": cfg.get_value(
				section, "space_name", ""
			),
			"since": cfg.get_value(section, "since", ""),
			"type": cfg.get_value(section, "type", 1),
			"last_synced": cfg.get_value(
				section, "last_synced", ""
			),
		})
	return entries


func save_entries(entries: Array) -> void:
	var cfg: ConfigFile = _host._config
	# Erase existing sections
	var old_count: int = cfg.get_value("friend_book", "count", 0)
	for i in old_count:
		var section := "friend_book_%d" % i
		if cfg.has_section(section):
			cfg.erase_section(section)
	# Write new entries
	for i in entries.size():
		var section := "friend_book_%d" % i
		var entry: Dictionary = entries[i]
		cfg.set_value(section, "user_id", entry.get("user_id", ""))
		cfg.set_value(
			section, "display_name",
			entry.get("display_name", "")
		)
		cfg.set_value(
			section, "username", entry.get("username", "")
		)
		cfg.set_value(
			section, "avatar_hash",
			entry.get("avatar_hash", "")
		)
		cfg.set_value(
			section, "server_url",
			entry.get("server_url", "")
		)
		cfg.set_value(
			section, "space_name",
			entry.get("space_name", "")
		)
		cfg.set_value(section, "since", entry.get("since", ""))
		cfg.set_value(section, "type", entry.get("type", 1))
		cfg.set_value(
			section, "last_synced",
			entry.get("last_synced", "")
		)
	cfg.set_value("friend_book", "count", entries.size())
	_host._save()


func remove_entry(
	server_url: String, user_id: String,
) -> void:
	var entries: Array = get_entries()
	var filtered: Array = entries.filter(func(e):
		return (
			e["server_url"] != server_url
			or e["user_id"] != user_id
		)
	)
	if filtered.size() != entries.size():
		save_entries(filtered)


func get_for_server(server_url: String) -> Array:
	return get_entries().filter(func(e):
		return e["server_url"] == server_url
	)
