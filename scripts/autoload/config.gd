extends Node

const REGISTRY_PATH := "user://profile_registry.cfg"
const _SALT := "daccord-config-v1"
const _PROFILE_SALT := "daccord-profile-v1"
const _RECENT_EMOJI_MAX := 16
const _BACKUP_THROTTLE_SEC := 60
## Keys that are never imported from external config files.
const _IMPORT_BLOCKED_KEYS: Array[String] = ["token", "password"]
const ConfigProfilesScript := preload(
	"res://scripts/autoload/config_profiles.gd"
)
const ConfigVoiceScript := preload(
	"res://scripts/autoload/config_voice.gd"
)

var profiles # ConfigProfiles
var voice # ConfigVoice

var _config := ConfigFile.new()
var _registry := ConfigFile.new()
var _profile_slug: String = "default"
var _cli_profile_override: String = ""
var _load_ok: bool = false
var _last_backup_time: int = 0

func _config_path() -> String:
	return "user://profiles/%s/config.cfg" % _profile_slug

func _profile_dir() -> String:
	return "user://profiles/%s" % _profile_slug

func _profile_emoji_cache_dir() -> String:
	return "user://profiles/%s/emoji_cache" % _profile_slug

func get_emoji_cache_path(emoji_id: String) -> String:
	return _profile_emoji_cache_dir() + "/" + emoji_id + ".png"

func _ready() -> void:
	profiles = ConfigProfilesScript.new(self, _PROFILE_SALT)
	voice = ConfigVoiceScript.new(self)
	# Parse --profile CLI arg
	for i in OS.get_cmdline_args().size():
		var arg: String = OS.get_cmdline_args()[i]
		if arg == "--profile" and i + 1 < OS.get_cmdline_args().size():
			_cli_profile_override = OS.get_cmdline_args()[i + 1]
			break

	if FileAccess.file_exists(REGISTRY_PATH):
		# Registry exists: load it
		_registry.load(REGISTRY_PATH)
		if not _cli_profile_override.is_empty():
			_profile_slug = _cli_profile_override
		else:
			_profile_slug = _registry.get_value(
				"state", "active", "default"
			)
		_load_profile_config()
	elif FileAccess.file_exists("user://config.cfg"):
		# Legacy config exists: migrate
		_migrate_legacy_config()
	else:
		# Fresh install
		_profile_slug = "default"
		_write_initial_registry("default", "Default")
		DirAccess.make_dir_recursive_absolute(_profile_dir())
		_load_ok = true
	# Apply saved audio device selection to AudioServer
	voice.apply_devices()

func _migrate_legacy_config() -> void:
	var dest_dir := "user://profiles/default"
	DirAccess.make_dir_recursive_absolute(dest_dir)
	# Move config file (only delete original after a verified copy)
	var src_global: String = ProjectSettings.globalize_path(
		"user://config.cfg"
	)
	var dst_global: String = ProjectSettings.globalize_path(
		dest_dir + "/config.cfg"
	)
	var copy_err := DirAccess.copy_absolute(src_global, dst_global)
	if copy_err != OK:
		push_error(
			"[Config] Migration copy failed (error %d), keeping original at %s"
			% [copy_err, src_global]
		)
		# Fall back to loading from the old path directly
		_profile_slug = "default"
		_write_initial_registry("default", "Default")
		var key := _derive_key()
		var err := _config.load_encrypted_pass("user://config.cfg", key)
		if err != OK:
			_config.load("user://config.cfg")
		_load_ok = true
		return
	DirAccess.remove_absolute(src_global)
	# Move emoji cache if exists
	if DirAccess.dir_exists_absolute("user://emoji_cache"):
		var emoji_dst := dest_dir + "/emoji_cache"
		DirAccess.make_dir_recursive_absolute(emoji_dst)
		_copy_directory("user://emoji_cache", emoji_dst)
		_remove_directory_recursive("user://emoji_cache")
	# Write registry
	_profile_slug = "default"
	_write_initial_registry("default", "Default")
	_load_profile_config()

func _write_initial_registry(slug: String, pname: String) -> void:
	_registry = ConfigFile.new()
	_registry.set_value("state", "active", slug)
	_registry.set_value("order", "list", [slug])
	_registry.set_value("profile_" + slug, "name", pname)
	_registry.save(REGISTRY_PATH)

func _load_profile_config() -> void:
	var path := _config_path()
	DirAccess.make_dir_recursive_absolute(_profile_dir())
	var key := _derive_key()
	var err := _config.load_encrypted_pass(path, key)
	if err == OK:
		_load_ok = true
		_migrate_guild_to_space_keys()
		_migrate_clear_passwords()
		return
	var plain_err := _config.load(path)
	if plain_err == OK:
		_load_ok = true
		_migrate_guild_to_space_keys()
		_migrate_clear_passwords()
		# Re-encrypt the plain config file
		var enc_err := _config.save_encrypted_pass(path, key)
		if enc_err != OK:
			push_warning(
				"[Config] Re-encryption failed (error %d), keeping plain format" % enc_err
			)
		return
	if FileAccess.file_exists(path):
		_backup_corrupted_file()
		push_error(
			"[Config] Config at '%s' unreadable "
			% path
			+ "(encrypted err=%d, plain err=%d), "
			% [err, plain_err]
			+ "backed up and starting fresh"
		)
	_config = ConfigFile.new()
	_load_ok = true

func _migrate_clear_passwords() -> void:
	var count: int = _config.get_value("servers", "count", 0)
	var changed := false
	for i in count:
		var section := "server_%d" % i
		if _config.has_section_key(section, "password"):
			_config.set_value(section, "password", null)
			changed = true
	if changed:
		_save()

func _migrate_guild_to_space_keys() -> void:
	var changed := false
	# Migrate server_N/guild_name → server_N/space_name
	var count: int = _config.get_value("servers", "count", 0)
	for i in count:
		var section := "server_%d" % i
		if _config.has_section_key(section, "guild_name"):
			var val: String = _config.get_value(section, "guild_name", "")
			_config.set_value(section, "space_name", val)
			_config.set_value(section, "guild_name", null)
			changed = true
	# Migrate state/last_guild_id → state/last_space_id
	if _config.has_section_key("state", "last_guild_id"):
		var val: String = _config.get_value("state", "last_guild_id", "")
		_config.set_value("state", "last_space_id", val)
		_config.set_value("state", "last_guild_id", null)
		changed = true
	# Migrate guild_order section → space_order section
	if _config.has_section("guild_order"):
		var items: Array = _config.get_value("guild_order", "items", [])
		_config.set_value("space_order", "items", items)
		_config.erase_section("guild_order")
		changed = true
	if changed:
		_save()

func _backup_corrupted_file() -> void:
	var path := _config_path()
	var bak_path := path + ".bak"
	if not FileAccess.file_exists(bak_path):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(bak_path)
		)

func _throttled_backup() -> void:
	var path := _config_path()
	if not FileAccess.file_exists(path):
		return
	var now: int = int(Time.get_unix_time_from_system())
	if now - _last_backup_time < _BACKUP_THROTTLE_SEC:
		return
	_last_backup_time = now
	var bak_path := path + ".bak"
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(bak_path)
	)

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
			"space_name": _config.get_value(section, "space_name", ""),
			"username": _config.get_value(section, "username", ""),
			"display_name": _config.get_value(section, "display_name", ""),
		})
	return servers

func add_server(
	base_url: String, token: String, space_name: String,
	username: String = "",
	display_name: String = "",
) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	var section := "server_%d" % count
	_config.set_value(section, "base_url", base_url)
	_config.set_value(section, "token", token)
	_config.set_value(section, "space_name", space_name)
	_config.set_value(section, "username", username)
	_config.set_value(section, "display_name", display_name)
	_config.set_value("servers", "count", count + 1)
	_save()

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
		_config.set_value(dst, "space_name", _config.get_value(src, "space_name", ""))
		_config.set_value(dst, "username", _config.get_value(src, "username", ""))
		_config.set_value(dst, "display_name", _config.get_value(src, "display_name", ""))
	# Erase last section
	var last := "server_%d" % (count - 1)
	if _config.has_section(last):
		_config.erase_section(last)
	_config.set_value("servers", "count", count - 1)
	_save()

func update_server_url(index: int, new_url: String) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "base_url", new_url)
	_save()

func update_server_token(index: int, new_token: String) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "token", new_token)
	_save()

func has_servers() -> bool:
	return _config.get_value("servers", "count", 0) > 0

func _save() -> void:
	if not _load_ok:
		push_warning("[Config] _save() blocked — config was not loaded successfully")
		return
	_throttled_backup()
	var path := _config_path()
	var err := _config.save_encrypted_pass(path, _derive_key())
	if err != OK:
		push_error(
			"[Config] Encrypted save failed (error %d). "
			% err
			+ "Data remains in memory — will retry on next save."
		)
		AppState.config_save_failed.emit(err)
		return

func set_last_selection(space_id: String, channel_id: String) -> void:
	_config.set_value("state", "last_space_id", space_id)
	_config.set_value("state", "last_channel_id", channel_id)
	_save()

func get_last_selection() -> Dictionary:
	return {
		"space_id": _config.get_value("state", "last_space_id", ""),
		"channel_id": _config.get_value("state", "last_channel_id", ""),
	}

func set_category_collapsed(space_id: String, category_id: String, collapsed: bool) -> void:
	var section := "collapsed_%s" % space_id
	_config.set_value(section, category_id, collapsed)
	_save()

func is_category_collapsed(space_id: String, category_id: String) -> bool:
	var section := "collapsed_%s" % space_id
	return _config.get_value(section, category_id, false)


func get_user_status() -> int:
	return _config.get_value("state", "user_status", 0)

func set_user_status(status: int) -> void:
	_config.set_value("state", "user_status", status)
	_save()

func get_custom_status() -> String:
	return _config.get_value("state", "custom_status", "")

func set_custom_status(text: String) -> void:
	_config.set_value("state", "custom_status", text)
	_save()

func get_error_reporting_enabled() -> bool:
	return _config.get_value("error_reporting", "enabled", false)

func set_error_reporting_enabled(value: bool) -> void:
	_config.set_value("error_reporting", "enabled", value)
	_save()
	AppState.config_changed.emit("error_reporting", "enabled")

func has_error_reporting_preference() -> bool:
	return _config.has_section_key("error_reporting", "consent_shown")

func set_error_reporting_consent_shown() -> void:
	_config.set_value("error_reporting", "consent_shown", true)
	_save()

func get_space_folder(space_id: String) -> String:
	return _config.get_value("folders", space_id, "")

func set_space_folder(space_id: String, folder_name: String) -> void:
	if folder_name.is_empty():
		_config.set_value("folders", space_id, null)
	else:
		_config.set_value("folders", space_id, folder_name)
	_save()

func get_space_folder_color(space_id: String) -> Color:
	return _config.get_value("folder_colors", space_id, Color(0.212, 0.224, 0.247))

func set_space_folder_color(space_id: String, color: Color) -> void:
	_config.set_value("folder_colors", space_id, color)
	_save()

func get_folder_color(fname: String) -> Color:
	return _config.get_value("folder_name_colors", fname, Color(0.212, 0.224, 0.247))

func set_folder_color(fname: String, color: Color) -> void:
	_config.set_value("folder_name_colors", fname, color)
	_save()

func rename_folder_color(old_name: String, new_name: String) -> void:
	var color: Color = _config.get_value("folder_name_colors", old_name, Color(0.212, 0.224, 0.247))
	_config.set_value("folder_name_colors", old_name, null)
	_config.set_value("folder_name_colors", new_name, color)
	_save()

func delete_folder_color(fname: String) -> void:
	_config.set_value("folder_name_colors", fname, null)
	_save()

func get_all_folder_names() -> Array:
	var names: Array = []
	if not _config.has_section("folders"):
		return names
	for key in _config.get_section_keys("folders"):
		var folder_name: String = _config.get_value("folders", key, "")
		if not folder_name.is_empty() and folder_name not in names:
			names.append(folder_name)
	return names

func get_space_order() -> Array:
	return _config.get_value("space_order", "items", [])

func set_space_order(order: Array) -> void:
	_config.set_value("space_order", "items", order)
	_save()

## Idle timeout

func get_idle_timeout() -> int:
	return _config.get_value("idle", "timeout", 300)

func set_idle_timeout(seconds: int) -> void:
	_config.set_value("idle", "timeout", seconds)
	_save()
	AppState.config_changed.emit("idle", "timeout")

## Sound preferences

func get_sfx_volume() -> float:
	return _config.get_value("sounds", "volume", 1.0)

func set_sfx_volume(vol: float) -> void:
	_config.set_value("sounds", "volume", clampf(vol, 0.0, 1.0))
	_save()
	AppState.config_changed.emit("sounds", "volume")

func is_sound_enabled(sound_name: String) -> bool:
	# message_sent defaults to off, everything else defaults to on
	var default: bool = sound_name != "message_sent"
	return _config.get_value("sounds", sound_name, default)

func set_sound_enabled(sound_name: String, enabled: bool) -> void:
	_config.set_value("sounds", sound_name, enabled)
	_save()
	AppState.config_changed.emit("sounds", sound_name)

## Notification preferences

func get_suppress_everyone() -> bool:
	return _config.get_value("notifications", "suppress_everyone", false)

func set_suppress_everyone(value: bool) -> void:
	_config.set_value("notifications", "suppress_everyone", value)
	_save()
	AppState.config_changed.emit("notifications", "suppress_everyone")

## Per-server suppress @everyone override
## Returns: -1 = use global default, 0 = don't suppress, 1 = suppress
func get_server_suppress_everyone(space_id: String) -> int:
	return _config.get_value("server_suppress", space_id, -1)

func set_server_suppress_everyone(space_id: String, value: int) -> void:
	if value == -1:
		_config.set_value("server_suppress", space_id, null)
	else:
		_config.set_value("server_suppress", space_id, clampi(value, 0, 1))
	_save()
	AppState.config_changed.emit("server_suppress", space_id)

func is_suppress_everyone_for_space(space_id: String) -> bool:
	var override: int = get_server_suppress_everyone(space_id)
	if override == -1:
		return get_suppress_everyone()
	return override == 1

func is_server_muted(space_id: String) -> bool:
	return _config.get_value("muted_servers", space_id, false)

func set_server_muted(space_id: String, muted: bool) -> void:
	if muted:
		_config.set_value("muted_servers", space_id, true)
	else:
		# Remove the key entirely when unmuting
		_config.set_value("muted_servers", space_id, null)
	_save()
	AppState.config_changed.emit("muted_servers", space_id)

## Recently used emoji

func get_recent_emoji() -> Array:
	return _config.get_value("emoji", "recent", [])

func get_emoji_skin_tone() -> int:
	return _config.get_value("emoji", "skin_tone", 0)

func set_emoji_skin_tone(tone: int) -> void:
	_config.set_value("emoji", "skin_tone", clampi(tone, 0, 5))
	_save()
	AppState.config_changed.emit("emoji", "skin_tone")

func add_recent_emoji(emoji_name: String) -> void:
	var recent: Array = get_recent_emoji()
	# Remove duplicate if already present
	var idx := recent.find(emoji_name)
	if idx != -1:
		recent.remove_at(idx)
	# Insert at front (most recent first)
	recent.insert(0, emoji_name)
	# Trim to max
	if recent.size() > _RECENT_EMOJI_MAX:
		recent.resize(_RECENT_EMOJI_MAX)
	_config.set_value("emoji", "recent", recent)
	_save()

## Accessibility

func get_reduced_motion() -> bool:
	return _config.get_value("accessibility", "reduced_motion", false)

func set_reduced_motion(enabled: bool) -> void:
	_config.set_value("accessibility", "reduced_motion", enabled)
	_save()
	AppState.config_changed.emit("accessibility", "reduced_motion")

func get_ui_scale() -> float:
	return _config.get_value("accessibility", "ui_scale", 0.0)

func _set_ui_scale(scale: float) -> void:
	if scale <= 0.0:
		_config.set_value("accessibility", "ui_scale", null)
	else:
		_config.set_value("accessibility", "ui_scale", clampf(scale, 0.5, 3.0))
	_save()
	AppState.config_changed.emit("accessibility", "ui_scale")

## Update preferences

func get_auto_update_check() -> bool:
	return _config.get_value("updates", "auto_check", true)

func _set_auto_update_check(enabled: bool) -> void:
	_config.set_value("updates", "auto_check", enabled)
	_save()
	AppState.config_changed.emit("updates", "auto_check")

func get_skipped_version() -> String:
	return _config.get_value("updates", "skipped_version", "")

func set_skipped_version(version: String) -> void:
	if version.is_empty():
		_config.set_value("updates", "skipped_version", null)
	else:
		_config.set_value("updates", "skipped_version", version)
	_save()

func get_last_update_check() -> int:
	return _config.get_value("updates", "last_check_timestamp", 0)

func set_last_update_check(timestamp: int) -> void:
	_config.set_value("updates", "last_check_timestamp", timestamp)
	_save()

## Master server URL

func get_master_server_url() -> String:
	return _config.get_value("master", "url", "https://master.daccord.chat")

func set_master_server_url(url: String) -> void:
	_config.set_value("master", "url", url)
	_save()

## Draft text persistence

func set_draft_text(channel_id: String, text: String) -> void:
	_config.set_value("drafts", channel_id, text)
	_save()

func get_draft_text(channel_id: String) -> String:
	return _config.get_value("drafts", channel_id, "")

func clear_draft_text(channel_id: String) -> void:
	_config.set_value("drafts", channel_id, null)
	_save()

func _clear() -> void:
	var count: int = _config.get_value("servers", "count", 0)
	for i in count:
		var section := "server_%d" % i
		if _config.has_section(section):
			_config.erase_section(section)
	_config.set_value("servers", "count", 0)
	_save()

func update_server_username(
	index: int, username: String
) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "username", username)
	_save()

## Config export/import

func export_config(path: String) -> Error:
	if not _load_ok:
		push_warning("[Config] export blocked — config was not loaded")
		return ERR_INVALID_DATA
	# Create a sanitized copy that strips secrets from server sections
	var sanitized := ConfigFile.new()
	for section in _config.get_sections():
		for key in _config.get_section_keys(section):
			# Strip token and password from server_N sections
			if section.begins_with("server_") and key in ["token", "password"]:
				continue
			sanitized.set_value(section, key, _config.get_value(section, key))
	return sanitized.save(path)

func import_config(path: String) -> Error:
	var new_cfg := ConfigFile.new()
	var err := new_cfg.load(path)
	if err != OK:
		return err
	# Back up current config before replacing
	var cur_path := _config_path()
	if FileAccess.file_exists(cur_path):
		var pre_import := cur_path + ".pre-import.bak"
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(cur_path),
			ProjectSettings.globalize_path(pre_import)
		)
	# Selectively copy sections/keys, stripping sensitive keys
	var stripped_count := 0
	for section in new_cfg.get_sections():
		for key in new_cfg.get_section_keys(section):
			if key in _IMPORT_BLOCKED_KEYS:
				stripped_count += 1
				continue
			_config.set_value(
				section, key,
				new_cfg.get_value(section, key)
			)
	if stripped_count > 0:
		push_warning(
			"[Config] Import: stripped %d blocked key(s) (token/password)"
			% stripped_count
		)
	_load_ok = true
	_save()
	return OK


## --- Directory helpers ---

func _copy_directory(src: String, dst: String) -> void:
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir():
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(src + "/" + fname),
				ProjectSettings.globalize_path(dst + "/" + fname)
			)
		fname = dir.get_next()
	dir.list_dir_end()

func _remove_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full := path + "/" + fname
		if dir.current_is_dir():
			_remove_directory_recursive(full)
		else:
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(full)
			)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
