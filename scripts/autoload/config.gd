extends Node

const REGISTRY_PATH := "user://profile_registry.cfg"
const _SALT := "daccord-config-v1"
const _PROFILE_SALT := "daccord-profile-v1"
const _RECENT_EMOJI_MAX := 16
const _BACKUP_THROTTLE_SEC := 60
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
		return
	var plain_err := _config.load(path)
	if plain_err == OK:
		_load_ok = true
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
			"guild_name": _config.get_value(section, "guild_name", ""),
			"username": _config.get_value(section, "username", ""),
			"password": _config.get_value(section, "password", ""),
			"display_name": _config.get_value(section, "display_name", ""),
		})
	return servers

func add_server(
	base_url: String, token: String, guild_name: String,
	username: String = "", password: String = "",
	display_name: String = "",
) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	var section := "server_%d" % count
	_config.set_value(section, "base_url", base_url)
	_config.set_value(section, "token", token)
	_config.set_value(section, "guild_name", guild_name)
	_config.set_value(section, "username", username)
	_config.set_value(section, "password", password)
	_config.set_value(section, "display_name", display_name)
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
		_config.set_value(dst, "display_name", _config.get_value(src, "display_name", ""))
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
	if not _load_ok:
		push_warning("[Config] save() blocked — config was not loaded successfully")
		return
	_throttled_backup()
	var path := _config_path()
	var err := _config.save_encrypted_pass(path, _derive_key())
	if err != OK:
		push_warning(
			"[Config] Encrypted save failed (error %d), falling back to plain save" % err
		)
		var plain_err := _config.save(path)
		if plain_err != OK:
			push_error(
				"[Config] Plain save also failed (error %d) — data may be lost!" % plain_err
			)
		return

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


func get_user_status() -> int:
	return _config.get_value("state", "user_status", 0)

func set_user_status(status: int) -> void:
	_config.set_value("state", "user_status", status)
	save()

func get_custom_status() -> String:
	return _config.get_value("state", "custom_status", "")

func set_custom_status(text: String) -> void:
	_config.set_value("state", "custom_status", text)
	save()

func get_error_reporting_enabled() -> bool:
	return _config.get_value("error_reporting", "enabled", false)

func set_error_reporting_enabled(value: bool) -> void:
	_config.set_value("error_reporting", "enabled", value)
	save()

func has_error_reporting_preference() -> bool:
	return _config.has_section_key("error_reporting", "consent_shown")

func set_error_reporting_consent_shown() -> void:
	_config.set_value("error_reporting", "consent_shown", true)
	save()

func get_guild_folder(guild_id: String) -> String:
	return _config.get_value("folders", guild_id, "")

func set_guild_folder(guild_id: String, folder_name: String) -> void:
	if folder_name.is_empty():
		_config.set_value("folders", guild_id, null)
	else:
		_config.set_value("folders", guild_id, folder_name)
	save()

func get_guild_folder_color(guild_id: String) -> Color:
	return _config.get_value("folder_colors", guild_id, Color(0.212, 0.224, 0.247))

func set_guild_folder_color(guild_id: String, color: Color) -> void:
	_config.set_value("folder_colors", guild_id, color)
	save()

func get_folder_color(fname: String) -> Color:
	return _config.get_value("folder_name_colors", fname, Color(0.212, 0.224, 0.247))

func set_folder_color(fname: String, color: Color) -> void:
	_config.set_value("folder_name_colors", fname, color)
	save()

func rename_folder_color(old_name: String, new_name: String) -> void:
	var color: Color = _config.get_value("folder_name_colors", old_name, Color(0.212, 0.224, 0.247))
	_config.set_value("folder_name_colors", old_name, null)
	_config.set_value("folder_name_colors", new_name, color)
	save()

func delete_folder_color(fname: String) -> void:
	_config.set_value("folder_name_colors", fname, null)
	save()

func get_all_folder_names() -> Array:
	var names: Array = []
	if not _config.has_section("folders"):
		return names
	for key in _config.get_section_keys("folders"):
		var folder_name: String = _config.get_value("folders", key, "")
		if not folder_name.is_empty() and folder_name not in names:
			names.append(folder_name)
	return names

func get_guild_order() -> Array:
	return _config.get_value("guild_order", "items", [])

func set_guild_order(order: Array) -> void:
	_config.set_value("guild_order", "items", order)
	save()

## Idle timeout

func get_idle_timeout() -> int:
	return _config.get_value("idle", "timeout", 300)

func set_idle_timeout(seconds: int) -> void:
	_config.set_value("idle", "timeout", seconds)
	save()

## Sound preferences

func get_sfx_volume() -> float:
	return _config.get_value("sounds", "volume", 1.0)

func set_sfx_volume(vol: float) -> void:
	_config.set_value("sounds", "volume", clampf(vol, 0.0, 1.0))
	save()

func is_sound_enabled(sound_name: String) -> bool:
	# message_sent defaults to off, everything else defaults to on
	var default: bool = sound_name != "message_sent"
	return _config.get_value("sounds", sound_name, default)

func set_sound_enabled(sound_name: String, enabled: bool) -> void:
	_config.set_value("sounds", sound_name, enabled)
	save()

## Notification preferences

func get_suppress_everyone() -> bool:
	return _config.get_value("notifications", "suppress_everyone", false)

func set_suppress_everyone(value: bool) -> void:
	_config.set_value("notifications", "suppress_everyone", value)
	save()

func is_server_muted(guild_id: String) -> bool:
	return _config.get_value("muted_servers", guild_id, false)

func set_server_muted(guild_id: String, muted: bool) -> void:
	if muted:
		_config.set_value("muted_servers", guild_id, true)
	else:
		# Remove the key entirely when unmuting
		_config.set_value("muted_servers", guild_id, null)
	save()

## Recently used emoji

func get_recent_emoji() -> Array:
	return _config.get_value("emoji", "recent", [])

func get_emoji_skin_tone() -> int:
	return _config.get_value("emoji", "skin_tone", 0)

func set_emoji_skin_tone(tone: int) -> void:
	_config.set_value("emoji", "skin_tone", clampi(tone, 0, 5))
	save()

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
	save()

## Accessibility

func get_reduced_motion() -> bool:
	return _config.get_value("accessibility", "reduced_motion", false)

func set_reduced_motion(enabled: bool) -> void:
	_config.set_value("accessibility", "reduced_motion", enabled)
	save()

## Update preferences

func get_auto_update_check() -> bool:
	return _config.get_value("updates", "auto_check", true)

func set_auto_update_check(enabled: bool) -> void:
	_config.set_value("updates", "auto_check", enabled)
	save()

func get_skipped_version() -> String:
	return _config.get_value("updates", "skipped_version", "")

func set_skipped_version(version: String) -> void:
	if version.is_empty():
		_config.set_value("updates", "skipped_version", null)
	else:
		_config.set_value("updates", "skipped_version", version)
	save()

func get_last_update_check() -> int:
	return _config.get_value("updates", "last_check_timestamp", 0)

func set_last_update_check(timestamp: int) -> void:
	_config.set_value("updates", "last_check_timestamp", timestamp)
	save()

## Master server URL

func get_master_server_url() -> String:
	return _config.get_value("master", "url", "https://master.daccord.chat")

func set_master_server_url(url: String) -> void:
	_config.set_value("master", "url", url)
	save()

## Draft text persistence

func set_draft_text(channel_id: String, text: String) -> void:
	_config.set_value("drafts", channel_id, text)
	save()

func get_draft_text(channel_id: String) -> String:
	return _config.get_value("drafts", channel_id, "")

func clear_draft_text(channel_id: String) -> void:
	_config.set_value("drafts", channel_id, null)
	save()

func _clear() -> void:
	var count: int = _config.get_value("servers", "count", 0)
	for i in count:
		var section := "server_%d" % i
		if _config.has_section(section):
			_config.erase_section(section)
	_config.set_value("servers", "count", 0)
	save()

func update_server_credentials(
	index: int, username: String, password: String
) -> void:
	var count: int = _config.get_value("servers", "count", 0)
	if index < 0 or index >= count:
		return
	var section := "server_%d" % index
	_config.set_value(section, "username", username)
	_config.set_value(section, "password", password)
	save()

## Config export/import

func export_config(path: String) -> Error:
	if not _load_ok:
		push_warning("[Config] export blocked — config was not loaded")
		return ERR_INVALID_DATA
	return _config.save(path)

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
	_config = new_cfg
	_load_ok = true
	save()
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
