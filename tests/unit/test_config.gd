extends GutTest

var config: Node


func before_each() -> void:
	config = load("res://scripts/autoload/config.gd").new()
	# Don't call _ready() — it loads from disk. We test in-memory behavior.


func after_each() -> void:
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
