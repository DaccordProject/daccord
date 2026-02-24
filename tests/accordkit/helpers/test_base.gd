class_name AccordTestBase extends GutTest

## Default server URLs (overridable via ACCORD_TEST_URL env var).
## Example: ACCORD_TEST_URL=http://192.168.1.144:39099 ./test.sh accordkit
const _DEFAULT_BASE_URL := "http://127.0.0.1:39099"

var BASE_URL: String = _DEFAULT_BASE_URL
var GATEWAY_URL: String = "ws://127.0.0.1:39099/ws"

var seed_data: Dictionary = {}

var user_id: String = ""
var user_token: String = ""
var bot_id: String = ""
var bot_token: String = ""
var bot_application_id: String = ""
var space_id: String = ""
var general_channel_id: String = ""
var testing_channel_id: String = ""

var bot_client: AccordClient
var user_client: AccordClient


func _resolve_server_url() -> void:
	var env_url: String = OS.get_environment("ACCORD_TEST_URL")
	if not env_url.is_empty():
		BASE_URL = env_url
		# Derive gateway URL: http(s) -> ws(s)
		GATEWAY_URL = env_url.replace(
			"https://", "wss://"
		).replace(
			"http://", "ws://"
		) + "/ws"
		gut.p("Using server from ACCORD_TEST_URL: %s" % BASE_URL)
	else:
		gut.p("Using default server: %s" % BASE_URL)


func before_all() -> void:
	_resolve_server_url()
	seed_data = await SeedClient.seed(self, BASE_URL)
	assert_false(seed_data.is_empty(), "Seed data should not be empty — is the server running?")

	var user_info: Dictionary = seed_data.get("user", {})
	user_id = str(user_info.get("id", ""))
	user_token = user_info.get("token", "")

	var bot_info: Dictionary = seed_data.get("bot", {})
	bot_id = str(bot_info.get("id", ""))
	bot_token = bot_info.get("token", "")
	bot_application_id = str(bot_info.get("application_id", ""))

	var space_info: Dictionary = seed_data.get("space", {})
	space_id = str(space_info.get("id", ""))

	var channels_info: Array = seed_data.get("channels", [])
	for ch in channels_info:
		var name: String = ch.get("name", "")
		var ch_id: String = str(ch.get("id", ""))
		if name == "general":
			general_channel_id = ch_id
		elif name == "testing":
			testing_channel_id = ch_id


func before_each() -> void:
	bot_client = _create_client(bot_token, "Bot")
	user_client = _create_client(user_token, "Bearer")


func after_each() -> void:
	if is_instance_valid(bot_client):
		bot_client.queue_free()
	if is_instance_valid(user_client):
		user_client.queue_free()


func _create_client(tkn: String, tkn_type: String) -> AccordClient:
	var client := AccordClient.new()
	client.token = tkn
	client.token_type = tkn_type
	client.base_url = BASE_URL
	client.gateway_url = GATEWAY_URL
	client.intents = GatewayIntents.all()
	add_child(client)
	return client
