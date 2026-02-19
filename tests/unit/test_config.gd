extends GutTest

var config: Node


func before_each() -> void:
	config = load("res://scripts/autoload/config.gd").new()
	# Don't call _ready() — it loads from disk. We test in-memory behavior.
	config._load_ok = true


func after_each() -> void:
	config._load_ok = true
	config.clear()
	config.free()


# --- has_servers ---

func test_has_servers_false_when_empty() -> void:
	assert_false(config.has_servers())


func test_has_servers_true_after_add() -> void:
	config.add_server("http://localhost:3000", "tok_abc", "my-guild")
	assert_true(config.has_servers())


# --- add_server / get_servers ---

func test_add_server_stores_entry() -> void:
	config.add_server("http://localhost:3000", "tok_abc", "my-guild")
	var servers = config.get_servers()
	assert_eq(servers.size(), 1)
	assert_eq(servers[0]["base_url"], "http://localhost:3000")
	assert_eq(servers[0]["token"], "tok_abc")
	assert_eq(servers[0]["guild_name"], "my-guild")


func test_add_multiple_servers() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.add_server("http://host2:4000", "tok_2", "guild-b")
	var servers = config.get_servers()
	assert_eq(servers.size(), 2)
	assert_eq(servers[0]["base_url"], "http://host1:3000")
	assert_eq(servers[1]["base_url"], "http://host2:4000")
	assert_eq(servers[0]["guild_name"], "guild-a")
	assert_eq(servers[1]["guild_name"], "guild-b")


func test_get_servers_empty_by_default() -> void:
	var servers = config.get_servers()
	assert_eq(servers.size(), 0)


# --- remove_server ---

func test_remove_server_by_index() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.add_server("http://host2:4000", "tok_2", "guild-b")
	config.remove_server(0)
	var servers = config.get_servers()
	assert_eq(servers.size(), 1)
	assert_eq(servers[0]["base_url"], "http://host2:4000")
	assert_eq(servers[0]["guild_name"], "guild-b")


func test_remove_last_server() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.remove_server(0)
	assert_false(config.has_servers())
	assert_eq(config.get_servers().size(), 0)


func test_remove_middle_server_shifts_remaining() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.add_server("http://host2:4000", "tok_2", "guild-b")
	config.add_server("http://host3:5000", "tok_3", "guild-c")
	config.remove_server(1)
	var servers = config.get_servers()
	assert_eq(servers.size(), 2)
	assert_eq(servers[0]["base_url"], "http://host1:3000")
	assert_eq(servers[1]["base_url"], "http://host3:5000")


func test_remove_server_invalid_index_no_op() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.remove_server(5)
	assert_eq(config.get_servers().size(), 1)


func test_remove_server_negative_index_no_op() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.remove_server(-1)
	assert_eq(config.get_servers().size(), 1)


# --- clear ---

func test_clear_removes_all_servers() -> void:
	config.add_server("http://host1:3000", "tok_1", "guild-a")
	config.add_server("http://host2:4000", "tok_2", "guild-b")
	config.clear()
	assert_false(config.has_servers())
	assert_eq(config.get_servers().size(), 0)


func test_clear_on_empty_is_no_op() -> void:
	config.clear()
	assert_false(config.has_servers())


# --- _load_ok guard ---

func test_load_ok_defaults_to_false() -> void:
	var fresh: Node = load("res://scripts/autoload/config.gd").new()
	assert_false(fresh._load_ok)
	fresh.free()

func test_save_allowed_when_load_ok_true() -> void:
	config._load_ok = true
	config._config.set_value("test", "key", "val")
	config.save()
	# Verify the value is still accessible (save didn't clear it)
	var val: String = config._config.get_value("test", "key", "")
	assert_eq(val, "val")

func test_add_server_works_when_load_ok_true() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "guild")
	assert_true(config.has_servers())


# --- update_server_credentials ---

func test_update_server_credentials() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "guild")
	config.update_server_credentials(0, "alice", "pass123")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "alice")
	assert_eq(servers[0]["password"], "pass123")

func test_update_server_credentials_invalid_index() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "guild")
	# Should be a no-op for out-of-range index
	config.update_server_credentials(5, "alice", "pass")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "")

func test_update_server_credentials_negative_index() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "guild")
	config.update_server_credentials(-1, "alice", "pass")
	var servers = config.get_servers()
	assert_eq(servers[0]["username"], "")


# --- export_config / import_config ---

func test_export_config_succeeds() -> void:
	config._load_ok = true
	config.add_server("http://host:3000", "tok", "guild")
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
	config.add_server("http://host:3000", "tok", "guild")
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
	config2.free()
	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
