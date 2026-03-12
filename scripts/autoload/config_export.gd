class_name ConfigExport
extends RefCounted

## Config export/import helpers extracted from Config.

## Keys that are never imported from external config files.
const _IMPORT_BLOCKED_KEYS: Array[String] = ["token", "password"]

var _host  # Config autoload (untyped for internal access)


func _init(host) -> void:
	_host = host


func export_config(path: String) -> Error:
	if not _host._load_ok:
		push_warning(
			"[Config] export blocked — config was not loaded"
		)
		return ERR_INVALID_DATA
	# Create a sanitized copy that strips secrets
	var cfg: ConfigFile = _host._config
	var sanitized := ConfigFile.new()
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if (
				section.begins_with("server_")
				and key in ["token", "password"]
			):
				continue
			sanitized.set_value(
				section, key, cfg.get_value(section, key)
			)
	return sanitized.save(path)


func import_config(path: String) -> Error:
	var new_cfg := ConfigFile.new()
	var err := new_cfg.load(path)
	if err != OK:
		return err
	# Back up current config before replacing
	var cur_path: String = _host._config_path()
	if FileAccess.file_exists(cur_path):
		var pre_import := cur_path + ".pre-import.bak"
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(cur_path),
			ProjectSettings.globalize_path(pre_import)
		)
	# Selectively copy sections/keys, stripping sensitive keys
	var cfg: ConfigFile = _host._config
	var stripped_count := 0
	for section in new_cfg.get_sections():
		for key in new_cfg.get_section_keys(section):
			if key in _IMPORT_BLOCKED_KEYS:
				stripped_count += 1
				continue
			cfg.set_value(
				section, key,
				new_cfg.get_value(section, key)
			)
	if stripped_count > 0:
		push_warning(
			"[Config] Import: stripped %d blocked key(s)"
			+ " (token/password)" % stripped_count
		)
	_host._load_ok = true
	_host._save()
	return OK
