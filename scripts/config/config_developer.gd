extends RefCounted
## Developer mode configuration helper for Config.

var _parent: Node # Config singleton


func _init(parent: Node) -> void:
	_parent = parent


func has_cli_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_args()

func find_cli_arg(arg: String) -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		if args[i] == arg:
			return i
	return -1

func is_test_api_enabled() -> bool:
	if OS.has_feature("release"):
		return false
	if has_cli_flag("--test-api") \
			or OS.get_environment("DACCORD_TEST_API") == "true":
		return true
	return get_developer_mode() and get_test_api_enabled()

func is_mcp_enabled() -> bool:
	if OS.has_feature("release"):
		return false
	return get_developer_mode() and get_mcp_enabled()

func get_effective_test_api_port() -> int:
	var idx: int = find_cli_arg("--test-api-port")
	var args: PackedStringArray = OS.get_cmdline_args()
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1].to_int()
	var env: String = OS.get_environment("DACCORD_TEST_API_PORT")
	if not env.is_empty():
		return env.to_int()
	return get_test_api_port()

func get_developer_mode() -> bool:
	return _parent._config.get_value("developer", "enabled", false)

func set_developer_mode(enabled: bool) -> void:
	_parent._config.set_value("developer", "enabled", enabled)
	_parent._save()
	AppState.config_changed.emit("developer", "enabled")

func get_test_api_enabled() -> bool:
	return _parent._config.get_value(
		"developer", "test_api_enabled", false
	)

func set_test_api_enabled(enabled: bool) -> void:
	_parent._config.set_value(
		"developer", "test_api_enabled", enabled
	)
	_parent._save()
	AppState.config_changed.emit("developer", "test_api_enabled")

func get_test_api_port() -> int:
	return _parent._config.get_value(
		"developer", "test_api_port", 39100
	)

func set_test_api_port(port: int) -> void:
	_parent._config.set_value(
		"developer", "test_api_port", clampi(port, 1024, 65535)
	)
	_parent._save()
	AppState.config_changed.emit("developer", "test_api_port")

func get_test_api_token() -> String:
	return _parent._config.get_value(
		"developer", "test_api_token", ""
	)

func set_test_api_token(token: String) -> void:
	_parent._config.set_value(
		"developer", "test_api_token",
		token if not token.is_empty() else null
	)
	_parent._save()

func get_mcp_enabled() -> bool:
	return _parent._config.get_value(
		"developer", "mcp_enabled", false
	)

func set_mcp_enabled(enabled: bool) -> void:
	_parent._config.set_value("developer", "mcp_enabled", enabled)
	_parent._save()
	AppState.config_changed.emit("developer", "mcp_enabled")

func get_mcp_token() -> String:
	return _parent._config.get_value("developer", "mcp_token", "")

func set_mcp_token(token: String) -> void:
	_parent._config.set_value(
		"developer", "mcp_token",
		token if not token.is_empty() else null
	)
	_parent._save()

func get_mcp_port() -> int:
	return _parent._config.get_value(
		"developer", "mcp_port", 39101
	)

func set_mcp_port(port: int) -> void:
	_parent._config.set_value(
		"developer", "mcp_port", clampi(port, 1024, 65535)
	)
	_parent._save()
	AppState.config_changed.emit("developer", "mcp_port")

func get_mcp_allowed_groups() -> PackedStringArray:
	return _parent._config.get_value(
		"developer", "mcp_allowed_groups",
		PackedStringArray(["read", "navigate", "screenshot"])
	)

func set_mcp_allowed_groups(groups: PackedStringArray) -> void:
	_parent._config.set_value(
		"developer", "mcp_allowed_groups", groups
	)
	_parent._save()
	AppState.config_changed.emit(
		"developer", "mcp_allowed_groups"
	)
