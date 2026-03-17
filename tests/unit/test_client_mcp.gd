extends GutTest

## Unit tests for ClientMcp — JSON-RPC dispatch, tool group
## filtering, MCP content wrapping, and token validation.

var mcp: ClientMcp
var test_api: ClientTestApi


func before_each() -> void:
	var dummy := Node.new()
	add_child(dummy)
	test_api = ClientTestApi.new(dummy)
	mcp = ClientMcp.new(dummy, test_api)


func after_each() -> void:
	if mcp != null:
		mcp.stop()
	if test_api != null:
		test_api.stop()
	for child in get_children():
		remove_child(child)
		child.queue_free()


# =============================================================================
# Tool registration
# =============================================================================

func test_tool_count_is_34() -> void:
	assert_eq(
		mcp._tools.size(), 34,
		"Should have exactly 34 MCP tools registered"
	)


func test_all_tools_have_group() -> void:
	for tool_name in mcp._tools:
		var group: String = mcp._tool_to_group.get(
			tool_name, ""
		)
		assert_false(
			group.is_empty(),
			"Tool '%s' must have a group" % tool_name
		)
		assert_true(
			group in ClientMcp.ALL_GROUPS,
			"Tool '%s' group '%s' must be valid"
			% [tool_name, group]
		)


func test_all_tools_have_endpoint() -> void:
	for tool_name in mcp._tools:
		var endpoint: String = mcp._tool_to_endpoint.get(
			tool_name, ""
		)
		assert_false(
			endpoint.is_empty(),
			"Tool '%s' must map to an endpoint" % tool_name
		)


func test_all_endpoints_exist_in_test_api() -> void:
	for tool_name in mcp._tools:
		var endpoint: String = mcp._tool_to_endpoint[tool_name]
		assert_true(
			test_api._endpoints.has(endpoint),
			"Tool '%s' endpoint '%s' must exist in test API"
			% [tool_name, endpoint]
		)


# =============================================================================
# Tool group filtering
# =============================================================================

func test_tools_list_filters_by_group() -> void:
	mcp._allowed_groups = PackedStringArray(["read"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	for tool_def in tools:
		var group: String = mcp._tool_to_group[tool_def["name"]]
		assert_eq(
			group, "read",
			"Only read tools should appear: %s" % tool_def["name"]
		)


func test_tools_list_includes_all_default_groups() -> void:
	mcp._allowed_groups = PackedStringArray([
		"read", "navigate", "screenshot",
	])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	var groups_seen: Dictionary = {}
	for tool_def in tools:
		groups_seen[mcp._tool_to_group[tool_def["name"]]] = true
	assert_true(groups_seen.has("read"))
	assert_true(groups_seen.has("navigate"))
	assert_true(groups_seen.has("screenshot"))
	assert_false(groups_seen.has("message"))
	assert_false(groups_seen.has("moderate"))
	assert_false(groups_seen.has("voice"))


func test_tools_list_empty_groups_returns_nothing() -> void:
	mcp._allowed_groups = PackedStringArray([])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(tools.size(), 0, "No tools with empty groups")


func test_read_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["read"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(tools.size(), 8, "Read group should have 8 tools")


func test_navigate_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["navigate"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(
		tools.size(), 12, "Navigate group should have 12 tools"
	)


func test_message_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["message"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(
		tools.size(), 4, "Message group should have 4 tools"
	)


func test_moderate_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["moderate"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(
		tools.size(), 4, "Moderate group should have 4 tools"
	)


func test_voice_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["voice"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(tools.size(), 4, "Voice group should have 4 tools")


func test_screenshot_group_tool_count() -> void:
	mcp._allowed_groups = PackedStringArray(["screenshot"])
	var result: Dictionary = mcp._handle_tools_list(1)
	var tools: Array = result["result"]["tools"]
	assert_eq(
		tools.size(), 3, "Screenshot group should have 3 tools"
	)


# =============================================================================
# JSON-RPC dispatch
# =============================================================================

func test_dispatch_initialize() -> void:
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0", "method": "initialize", "id": 1,
	})
	assert_eq(result["jsonrpc"], "2.0")
	assert_eq(result["id"], 1)
	assert_true(result["result"].has("protocolVersion"))
	assert_eq(
		result["result"]["protocolVersion"],
		ClientMcp.MCP_PROTOCOL_VERSION,
	)
	assert_true(result["result"].has("serverInfo"))
	assert_eq(result["result"]["serverInfo"]["name"], "daccord")


func test_dispatch_tools_list() -> void:
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0", "method": "tools/list", "id": 2,
	})
	assert_eq(result["id"], 2)
	assert_true(result["result"].has("tools"))
	assert_true(result["result"]["tools"] is Array)


func test_dispatch_unknown_method() -> void:
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0", "method": "bogus/method", "id": 3,
	})
	assert_true(result.has("error"))
	assert_eq(result["error"]["code"], -32601)


func test_dispatch_missing_method() -> void:
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0", "id": 4,
	})
	assert_true(result.has("error"))
	assert_eq(result["error"]["code"], -32600)


func test_dispatch_tools_call_unknown_tool() -> void:
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0",
		"method": "tools/call",
		"id": 5,
		"params": {"name": "nonexistent_tool", "arguments": {}},
	})
	assert_true(result.has("error"))
	assert_eq(result["error"]["code"], -32601)


func test_dispatch_tools_call_blocked_group() -> void:
	mcp._allowed_groups = PackedStringArray(["read"])
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0",
		"method": "tools/call",
		"id": 6,
		"params": {"name": "send_message", "arguments": {}},
	})
	assert_true(result.has("error"))
	assert_eq(result["error"]["code"], -32600)
	assert_true(
		"not enabled" in result["error"]["message"],
		"Should mention group is not enabled"
	)


func test_dispatch_notifications_initialized() -> void:
	# Notification with id should return empty result
	var result: Dictionary = await mcp._dispatch({
		"jsonrpc": "2.0",
		"method": "notifications/initialized",
		"id": 7,
	})
	assert_eq(result["id"], 7)


# =============================================================================
# MCP content wrapping
# =============================================================================

func test_wrap_text_result() -> void:
	var wrapped: Dictionary = mcp._wrap_mcp_result(
		"list_spaces", {"ok": true, "spaces": []}
	)
	assert_true(wrapped.has("content"))
	assert_eq(wrapped["content"].size(), 1)
	assert_eq(wrapped["content"][0]["type"], "text")


func test_wrap_screenshot_result() -> void:
	var wrapped: Dictionary = mcp._wrap_mcp_result(
		"take_screenshot",
		{"ok": true, "image_base64": "abc123", "width": 100},
	)
	assert_eq(wrapped["content"].size(), 2)
	assert_eq(wrapped["content"][0]["type"], "image")
	assert_eq(wrapped["content"][0]["data"], "abc123")
	assert_eq(wrapped["content"][0]["mimeType"], "image/png")
	assert_eq(wrapped["content"][1]["type"], "text")
	# image_base64 should be removed from the text portion
	var text_data: String = wrapped["content"][1]["text"]
	assert_false("abc123" in text_data)


func test_wrap_non_screenshot_with_image_key() -> void:
	# A non-screenshot tool with image_base64 key should NOT
	# get image wrapping
	var wrapped: Dictionary = mcp._wrap_mcp_result(
		"list_spaces",
		{"ok": true, "image_base64": "should_not_split"},
	)
	assert_eq(wrapped["content"].size(), 1)
	assert_eq(wrapped["content"][0]["type"], "text")


# =============================================================================
# Auth validation
# =============================================================================

func test_auth_no_token_always_passes() -> void:
	mcp._token = ""
	assert_true(mcp._check_auth(""))


func test_auth_correct_token() -> void:
	mcp._token = "test_secret_123"
	assert_true(mcp._check_auth("Bearer test_secret_123"))


func test_auth_wrong_token() -> void:
	mcp._token = "test_secret_123"
	assert_false(mcp._check_auth("Bearer wrong_token"))


func test_auth_missing_bearer_prefix() -> void:
	mcp._token = "test_secret_123"
	assert_false(mcp._check_auth("test_secret_123"))


func test_auth_empty_token_with_bearer() -> void:
	mcp._token = "test_secret_123"
	assert_false(mcp._check_auth("Bearer "))


# =============================================================================
# Constant-time comparison
# =============================================================================

func test_constant_time_equal() -> void:
	assert_true(mcp._constant_time_compare("abc", "abc"))


func test_constant_time_different() -> void:
	assert_false(mcp._constant_time_compare("abc", "xyz"))


func test_constant_time_different_length() -> void:
	assert_false(mcp._constant_time_compare("short", "longer"))


func test_constant_time_empty() -> void:
	assert_true(mcp._constant_time_compare("", ""))


# =============================================================================
# HTTP validation
# =============================================================================

func test_validate_http_post_mcp() -> void:
	var result: Dictionary = mcp._validate_http(
		"POST /mcp HTTP/1.1\r\nHost: localhost"
	)
	assert_false(result.has("http_error"))
	assert_eq(result["path"], "/mcp")


func test_validate_http_rejects_get() -> void:
	var result: Dictionary = mcp._validate_http(
		"GET /mcp HTTP/1.1\r\n"
	)
	assert_true(result.has("http_error"))
	assert_eq(result["_status"], 405)


func test_validate_http_rejects_wrong_path() -> void:
	var result: Dictionary = mcp._validate_http(
		"POST /api/get_state HTTP/1.1\r\n"
	)
	assert_true(result.has("http_error"))
	assert_eq(result["_status"], 404)


func test_validate_http_accepts_trailing_slash() -> void:
	var result: Dictionary = mcp._validate_http(
		"POST /mcp/ HTTP/1.1\r\n"
	)
	assert_false(result.has("http_error"))


# =============================================================================
# Rate limiting
# =============================================================================

func test_rate_limit_allows_initial() -> void:
	mcp._request_timestamps.clear()
	assert_false(mcp._is_rate_limited())


func test_rate_limit_blocks_after_burst() -> void:
	mcp._request_timestamps.clear()
	var now: int = Time.get_ticks_msec()
	for i in ClientMcp.RATE_LIMIT_BURST:
		mcp._request_timestamps.append(now)
	assert_true(mcp._is_rate_limited())


# =============================================================================
# Activity log
# =============================================================================

func test_activity_log_records() -> void:
	mcp._log_activity("test_tool", true)
	assert_eq(mcp._activity_log.size(), 1)
	assert_eq(mcp._activity_log[0]["tool"], "test_tool")
	assert_true(mcp._activity_log[0]["ok"])


func test_activity_log_caps_at_max() -> void:
	for i in ClientMcp.MAX_LOG_ENTRIES + 10:
		mcp._log_activity("tool_%d" % i, true)
	assert_eq(
		mcp._activity_log.size(), ClientMcp.MAX_LOG_ENTRIES,
	)


# =============================================================================
# Server start/stop
# =============================================================================

func test_start_and_stop() -> void:
	var ok: bool = mcp.start(39198)
	assert_true(ok, "Should start on available port")
	assert_true(mcp.is_listening())
	mcp.stop()
	assert_false(mcp.is_listening())


# =============================================================================
# JSON-RPC helpers
# =============================================================================

func test_jsonrpc_result_format() -> void:
	var result: Dictionary = mcp._jsonrpc_result(
		42, {"ok": true}
	)
	assert_eq(result["jsonrpc"], "2.0")
	assert_eq(result["id"], 42)
	assert_eq(result["result"]["ok"], true)


func test_jsonrpc_error_format() -> void:
	var result: Dictionary = mcp._jsonrpc_error(
		-32600, "Bad request", 99
	)
	assert_eq(result["jsonrpc"], "2.0")
	assert_eq(result["id"], 99)
	assert_eq(result["error"]["code"], -32600)
	assert_eq(result["error"]["message"], "Bad request")


# =============================================================================
# Tool input schemas
# =============================================================================

func test_tools_have_input_schema() -> void:
	for tool_name in mcp._tools:
		var tool_def: Dictionary = mcp._tools[tool_name]
		assert_true(
			tool_def.has("inputSchema"),
			"Tool '%s' must have inputSchema" % tool_name
		)
		var schema: Dictionary = tool_def["inputSchema"]
		assert_eq(
			schema.get("type", ""),
			"object",
			"Tool '%s' schema type must be object" % tool_name
		)


func test_required_tools_have_required_params() -> void:
	# Tools that should require specific params
	var expected_required: Dictionary = {
		"list_channels": ["space_id"],
		"list_members": ["space_id"],
		"list_messages": ["channel_id"],
		"search_messages": ["query"],
		"get_user": ["user_id"],
		"get_space": ["space_id"],
		"select_space": ["space_id"],
		"select_channel": ["channel_id"],
		"send_message": ["channel_id", "content"],
		"kick_member": ["space_id", "user_id"],
	}
	for tool_name in expected_required:
		var schema: Dictionary = (
			mcp._tools[tool_name]["inputSchema"]
		)
		assert_true(
			schema.has("required"),
			"Tool '%s' should have required params" % tool_name
		)
		for param in expected_required[tool_name]:
			assert_true(
				param in schema["required"],
				"Tool '%s' should require '%s'"
				% [tool_name, param]
			)
