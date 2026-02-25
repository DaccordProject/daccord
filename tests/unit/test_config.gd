extends GutTest

const _DEFAULT_CFG := "user://profiles/default/config.cfg"

var config: Node
var _saved_config := PackedByteArray()
var _had_config := false


func before_each() -> void:
	# Back up real config so tests don't destroy user data.
	# add_server() and _save() write to the real user:// path.
	_had_config = FileAccess.file_exists(_DEFAULT_CFG)
	if _had_config:
		_saved_config = FileAccess.get_file_as_bytes(
			_DEFAULT_CFG
		)
	config = load("res://scripts/autoload/config.gd").new()
	# Don't call _ready() — it loads from disk. We test in-memory behavior.
	config._load_ok = true


func after_each() -> void:
	config.free()
	# Restore backed-up config file
	if _had_config:
		var f := FileAccess.open(
			_DEFAULT_CFG, FileAccess.WRITE
		)
		if f:
			f.store_buffer(_saved_config)
			f.close()
	elif FileAccess.file_exists(_DEFAULT_CFG):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_DEFAULT_CFG)
		)
	# Clean up backup files the import test creates
	for suffix in [".bak", ".pre-import.bak"]:
		var p: String = _DEFAULT_CFG + str(suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(p)
			)


# --- has_servers ---

func test_has_servers_false_when_empty() -> void:
	assert_false(config.has_servers())


func test_has_servers_true_after_add() -> void:
	config.add_server("http://localhost:3000", "tok_abc", "my-space")
	assert_true(config.has_servers())


# --- add_server / get_servers ---

func test_add_server_stores_entry() -> void:
	config.add_server("http://localhost:3000", "tok_abc", "my-space")
	var servers = config.get_servers()
	assert_eq(servers.size(), 1)
	assert_eq(servers[0]["base_url"], "http://localhost:3000")
	assert_eq(servers[0]["token"], "tok_abc")
	assert_eq(servers[0]["space_name"], "my-space")


func test_add_multiple_servers() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.add_server("http://host2:4000", "tok_2", "space-b")
	var servers = config.get_servers()
	assert_eq(servers.size(), 2)
	assert_eq(servers[0]["base_url"], "http://host1:3000")
	assert_eq(servers[1]["base_url"], "http://host2:4000")
	assert_eq(servers[0]["space_name"], "space-a")
	assert_eq(servers[1]["space_name"], "space-b")


func test_get_servers_empty_by_default() -> void:
	var servers = config.get_servers()
	assert_eq(servers.size(), 0)


# --- remove_server ---

func test_remove_server_by_index() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.add_server("http://host2:4000", "tok_2", "space-b")
	config.remove_server(0)
	var servers = config.get_servers()
	assert_eq(servers.size(), 1)
	assert_eq(servers[0]["base_url"], "http://host2:4000")
	assert_eq(servers[0]["space_name"], "space-b")


func test_remove_last_server() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.remove_server(0)
	assert_false(config.has_servers())
	assert_eq(config.get_servers().size(), 0)


func test_remove_middle_server_shifts_remaining() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.add_server("http://host2:4000", "tok_2", "space-b")
	config.add_server("http://host3:5000", "tok_3", "space-c")
	config.remove_server(1)
	var servers = config.get_servers()
	assert_eq(servers.size(), 2)
	assert_eq(servers[0]["base_url"], "http://host1:3000")
	assert_eq(servers[1]["base_url"], "http://host3:5000")


func test_remove_server_invalid_index_no_op() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.remove_server(5)
	assert_eq(config.get_servers().size(), 1)


func test_remove_server_negative_index_no_op() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.remove_server(-1)
	assert_eq(config.get_servers().size(), 1)


# --- clear ---

func test_clear_removes_all_servers() -> void:
	config.add_server("http://host1:3000", "tok_1", "space-a")
	config.add_server("http://host2:4000", "tok_2", "space-b")
	config._clear()
	assert_false(config.has_servers())
	assert_eq(config.get_servers().size(), 0)


func test_clear_on_empty_is_no_op() -> void:
	config._clear()
	assert_false(config.has_servers())


# --- _load_ok guard ---

func test_load_ok_defaults_to_false() -> void:
	var fresh: Node = load("res://scripts/autoload/config.gd").new()
	assert_false(fresh._load_ok)
	fresh.free()

func test_save_allowed_when_load_ok_true() -> void:
	config._load_ok = true
	config._config.set_value("test", "key", "val")
	config._save()
	# Verify the value is still accessible (save didn't clear it)
	var val: String = config._config.get_value("test", "key", "")
	assert_eq(val, "val")

func test_add_server_works_when_load_ok_true() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	assert_true(config.has_servers())


# --- update_server_username ---

func test_update_server_username() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	config.update_server_username(0, "alice")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "alice")

func test_update_server_username_invalid_index() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	# Should be a no-op for out-of-range index
	config.update_server_username(5, "alice")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "")

func test_update_server_username_negative_index() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	config.update_server_username(-1, "alice")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "")


# --- export_config / import_config ---

func test_export_config_succeeds() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	var path := "user://test_export_config.cfg"
	var err: int = config.export_config(path)
	assert_eq(err, OK)
	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)

func test_import_config_invalid_path() -> void:
	config._load_ok = true
	var err: int = config.import_config(
		"user://nonexistent_config.cfg"
	)
	assert_ne(err, OK)

func test_import_config_round_trip() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space")
	config._config.set_value("state", "user_status", 2)
	var path := "user://test_import_config.cfg"
	config.export_config(path)
	# Create a fresh config and import
	var config2: Node = load(
		"res://scripts/autoload/config.gd"
	).new()
	config2._load_ok = true
	var import_err: int = config2.import_config(path)
	assert_eq(import_err, OK)
	var servers = config2.get_servers()
	assert_eq(servers.size(), 1)
	assert_eq(servers[0]["base_url"], "http://host:3000")
	# Export strips secrets, so token should be empty after import
	assert_eq(servers[0]["token"], "")
	# Non-secret data should survive the round trip
	var status: int = config2._config.get_value("state", "user_status", 0)
	assert_eq(status, 2)
	config2.free()
	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)

func test_export_strips_secrets() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok_secret", "space", "alice")
	# Manually set a password key to simulate a pre-migration config
	config._config.set_value("server_0", "password", "hunter2")
	var path := "user://test_export_secrets.cfg"
	var err: int = config.export_config(path)
	assert_eq(err, OK)
	# Read the exported file and verify no secrets
	var exported := ConfigFile.new()
	exported.load(path)
	assert_false(exported.has_section_key("server_0", "token"))
	assert_false(exported.has_section_key("server_0", "password"))
	# Non-secret fields should be present
	assert_eq(exported.get_value("server_0", "base_url", ""), "http://host:3000")
	assert_eq(exported.get_value("server_0", "username", ""), "alice")
	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)

func test_migrate_clears_passwords() -> void:
	config._load_ok = true
	# Simulate a pre-migration config with password keys
	config._config.set_value("servers", "count", 2)
	config._config.set_value("server_0", "base_url", "http://host1:3000")
	config._config.set_value("server_0", "token", "tok1")
	config._config.set_value("server_0", "space_name", "space-a")
	config._config.set_value("server_0", "username", "alice")
	config._config.set_value("server_0", "password", "secret1")
	config._config.set_value("server_1", "base_url", "http://host2:3000")
	config._config.set_value("server_1", "token", "tok2")
	config._config.set_value("server_1", "space_name", "space-b")
	config._config.set_value("server_1", "username", "bob")
	config._config.set_value("server_1", "password", "secret2")
	# Run migration
	config._migrate_clear_passwords()
	# Passwords should be gone
	assert_false(config._config.has_section_key("server_0", "password"))
	assert_false(config._config.has_section_key("server_1", "password"))
	# Other fields should remain
	assert_eq(config._config.get_value("server_0", "username", ""), "alice")
	assert_eq(config._config.get_value("server_1", "username", ""), "bob")

func test_add_server_no_password_key() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "space", "alice")
	# Verify no password key is stored
	assert_false(config._config.has_section_key("server_0", "password"))
