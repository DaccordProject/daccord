class_name AccordTestBase extends GutTest

const BASE_URL := "http://127.0.0.1:39099"
const GATEWAY_URL := "ws://127.0.0.1:39099/ws"

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


func before_all() -> void:
	seed_data = await SeedClient.seed(self)
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
