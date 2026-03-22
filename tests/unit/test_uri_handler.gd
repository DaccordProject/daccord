extends GutTest

# Static method reference for convenience
var parse: Callable = UriHandler.parse_uri


# --- connect route ---

func test_connect_full() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com:8080/general?token=abc123&invite=XYZ")
	assert_eq(r["route"], "connect")
	assert_eq(r["host"], "chat.example.com")
	assert_eq(r["port"], 8080)
	assert_eq(r["space_slug"], "general")
	assert_eq(r["token"], "abc123")
	assert_eq(r["invite_code"], "XYZ")


func test_connect_host_only() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com/")
	assert_eq(r["route"], "connect")
	assert_eq(r["host"], "chat.example.com")
	assert_eq(r["port"], 443)
	assert_eq(r["space_slug"], "general")
	assert_eq(r["token"], "")


func test_connect_host_with_slug() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com/myspace")
	assert_eq(r["route"], "connect")
	assert_eq(r["host"], "chat.example.com")
	assert_eq(r["space_slug"], "myspace")


func test_connect_host_port_no_slug() -> void:
	var r: Dictionary = parse.call("daccord://connect/localhost:39099/")
	assert_eq(r["route"], "connect")
	assert_eq(r["host"], "localhost")
	assert_eq(r["port"], 39099)
	assert_eq(r["space_slug"], "general")


func test_connect_token_only() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com/general?token=mytoken")
	assert_eq(r["token"], "mytoken")
	assert_eq(r["invite_code"], "")


func test_connect_invite_only() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com/general?invite=CODE123")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "CODE123")


func test_connect_default_port() -> void:
	var r: Dictionary = parse.call("daccord://connect/example.com/test")
	assert_eq(r["port"], 443)


# --- invite route ---

func test_invite_full() -> void:
	var r: Dictionary = parse.call("daccord://invite/ABCDEF@chat.example.com:8080")
	assert_eq(r["route"], "invite")
	assert_eq(r["invite_code"], "ABCDEF")
	assert_eq(r["host"], "chat.example.com")
	assert_eq(r["port"], 8080)


func test_invite_default_port() -> void:
	var r: Dictionary = parse.call("daccord://invite/CODE123@example.com")
	assert_eq(r["route"], "invite")
	assert_eq(r["invite_code"], "CODE123")
	assert_eq(r["host"], "example.com")
	assert_eq(r["port"], 443)


func test_invite_rejects_non_alphanumeric_code() -> void:
	var r: Dictionary = parse.call("daccord://invite/BAD;CODE@example.com")
	assert_eq(r, {})


func test_invite_rejects_empty_code() -> void:
	var r: Dictionary = parse.call("daccord://invite/@example.com")
	assert_eq(r, {})


# --- navigate route ---

func test_navigate_space_and_channel() -> void:
	var r: Dictionary = parse.call("daccord://navigate/123456/789012")
	assert_eq(r["route"], "navigate")
	assert_eq(r["space_id"], "123456")
	assert_eq(r["channel_id"], "789012")


func test_navigate_space_only() -> void:
	var r: Dictionary = parse.call("daccord://navigate/123456")
	assert_eq(r["route"], "navigate")
	assert_eq(r["space_id"], "123456")
	assert_false(r.has("channel_id"))


# --- rejection cases ---

func test_reject_empty_uri() -> void:
	assert_eq(parse.call(""), {})


func test_reject_wrong_scheme() -> void:
	assert_eq(parse.call("http://connect/example.com"), {})


func test_reject_bare_scheme() -> void:
	assert_eq(parse.call("daccord://"), {})


func test_reject_scheme_with_slash() -> void:
	assert_eq(parse.call("daccord:///"), {})


func test_reject_unknown_route() -> void:
	assert_eq(parse.call("daccord://unknown/something"), {})


func test_reject_connect_empty_host() -> void:
	assert_eq(parse.call("daccord://connect/"), {})


func test_reject_navigate_empty() -> void:
	assert_eq(parse.call("daccord://navigate/"), {})


func test_reject_host_with_angle_brackets() -> void:
	assert_eq(parse.call("daccord://connect/<script>/space"), {})


func test_reject_host_with_semicolon() -> void:
	assert_eq(parse.call("daccord://connect/host;rm -rf/space"), {})


func test_reject_host_with_quotes() -> void:
	assert_eq(parse.call("daccord://connect/host\"injection/space"), {})


# --- build_base_url ---

func test_build_base_url_default_port() -> void:
	assert_eq(UriHandler.build_base_url("example.com", 443), "https://example.com")


func test_build_base_url_custom_port() -> void:
	assert_eq(UriHandler.build_base_url("localhost", 39099), "https://localhost:39099")


# --- build_connect_url ---

func test_build_connect_url_space_only() -> void:
	var url := UriHandler.build_connect_url("chat.example.com", 443, "general")
	assert_eq(url, "daccord://connect/chat.example.com/general")


func test_build_connect_url_with_port() -> void:
	var url := UriHandler.build_connect_url("localhost", 39099, "myspace")
	assert_eq(url, "daccord://connect/localhost:39099/myspace")


func test_build_connect_url_with_channel() -> void:
	var url := UriHandler.build_connect_url("chat.example.com", 443, "general", "announcements")
	assert_eq(url, "daccord://connect/chat.example.com/general?channel=announcements")


func test_build_connect_url_channel_with_spaces() -> void:
	var url := UriHandler.build_connect_url("example.com", 443, "general", "my channel")
	assert_true(url.contains("?channel=my%20channel"))


func test_build_connect_url_empty_slug() -> void:
	var url := UriHandler.build_connect_url("example.com", 443, "")
	assert_eq(url, "daccord://connect/example.com")


# --- build_navigate_url ---

func test_build_navigate_url_channel_only() -> void:
	var url := UriHandler.build_navigate_url("123456", "789012")
	assert_eq(url, "daccord://navigate/123456/789012")


func test_build_navigate_url_with_message() -> void:
	var url := UriHandler.build_navigate_url("123456", "789012", "345678")
	assert_eq(url, "daccord://navigate/123456/789012?msg=345678")


func test_build_navigate_url_space_only() -> void:
	var url := UriHandler.build_navigate_url("123456", "")
	assert_eq(url, "daccord://navigate/123456")


# --- connect route with channel query param ---

func test_connect_with_channel_param() -> void:
	var r: Dictionary = parse.call("daccord://connect/chat.example.com/general?channel=announcements")
	assert_eq(r["route"], "connect")
	assert_eq(r["host"], "chat.example.com")
	assert_eq(r["space_slug"], "general")
	assert_eq(r["channel"], "announcements")


func test_connect_channel_with_token() -> void:
	var r: Dictionary = parse.call("daccord://connect/example.com/space?token=abc&channel=chat")
	assert_eq(r["token"], "abc")
	assert_eq(r["channel"], "chat")


func test_connect_without_channel_has_no_key() -> void:
	var r: Dictionary = parse.call("daccord://connect/example.com/space")
	assert_false(r.has("channel"))


# --- navigate route with msg query param ---

func test_navigate_with_message_id() -> void:
	var r: Dictionary = parse.call("daccord://navigate/123456/789012?msg=345678")
	assert_eq(r["route"], "navigate")
	assert_eq(r["space_id"], "123456")
	assert_eq(r["channel_id"], "789012")
	assert_eq(r["message_id"], "345678")


func test_navigate_without_message_has_no_key() -> void:
	var r: Dictionary = parse.call("daccord://navigate/123456/789012")
	assert_false(r.has("message_id"))
