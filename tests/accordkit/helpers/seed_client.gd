class_name SeedClient extends RefCounted

const _DEFAULT_SEED_URL := "http://127.0.0.1:39099/test/seed"

static func seed(parent: Node, base_url: String = "") -> Dictionary:
	var seed_url: String = _DEFAULT_SEED_URL
	if not base_url.is_empty():
		seed_url = base_url + "/test/seed"

	var http := HTTPRequest.new()
	parent.add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := http.request(seed_url, headers, HTTPClient.METHOD_POST, "{}")
	if error != OK:
		http.queue_free()
		push_error("SeedClient: request failed with error %d" % error)
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]

	if response_code != 200:
		push_error("SeedClient: seed returned %d" % response_code)
		return {}

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("SeedClient: failed to parse response JSON")
		return {}

	var envelope: Dictionary = json.data
	return envelope.get("data", {})
