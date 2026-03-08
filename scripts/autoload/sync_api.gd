class_name SyncAPI
extends Node

## HTTP client for the daccord-sync server.
## Mirrors the AccordKit RestResult pattern but with a simpler SyncResult.
##
## Base URL is read from Config under sync/base_url
## (default: https://sync.daccord.app).

const _DEFAULT_BASE_URL := "https://sync.daccord.app"


class SyncResult:
	var ok: bool = false
	var data: Dictionary = {}
	var error: String = ""

	static func success(d: Dictionary) -> SyncResult:
		var r := SyncResult.new()
		r.ok = true
		r.data = d
		return r

	static func failure(err: String) -> SyncResult:
		var r := SyncResult.new()
		r.ok = false
		r.error = err
		return r


func _base_url() -> String:
	return Config.get_sync_base_url()


## Register a new account. Returns SyncResult with { "token": String } on success.
func register(email: String, password: String) -> SyncResult:
	return await _post(
		"/api/auth/register",
		{"email": email, "password": password},
		""
	)


## Log in to an existing account. Returns SyncResult with { "token": String } on success.
func login(email: String, password: String) -> SyncResult:
	return await _post(
		"/api/auth/login",
		{"email": email, "password": password},
		""
	)


## Push an encrypted config blob. Returns SyncResult with { "version": int } on success.
func push(token: String, blob: String, version: int) -> SyncResult:
	return await _put(
		"/api/config",
		{"blob": blob, "version": version},
		token
	)


## Pull the current encrypted config blob.
## Returns SyncResult with { "blob": String, "version": int } on success.
func pull(token: String) -> SyncResult:
	return await _get("/api/config", token)


## Retrieve slot availability.
## Returns SyncResult with { "sold": int, "cap": int, "remaining": int } on success.
func get_slots() -> SyncResult:
	return await _get("/api/slots", "")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _get(path: String, token: String) -> SyncResult:
	return await _request("GET", path, null, token)


func _post(path: String, body: Dictionary, token: String) -> SyncResult:
	return await _request("POST", path, body, token)


func _put(path: String, body: Dictionary, token: String) -> SyncResult:
	return await _request("PUT", path, body, token)


func _request(method: String, path: String, body, token: String) -> SyncResult:
	var url: String = _base_url() + path
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Accept: application/json",
	]
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)

	var http := HTTPRequest.new()
	add_child(http)

	var method_int: int = HTTPClient.METHOD_GET
	match method:
		"POST": method_int = HTTPClient.METHOD_POST
		"PUT": method_int = HTTPClient.METHOD_PUT
		"PATCH": method_int = HTTPClient.METHOD_PATCH
		"DELETE": method_int = HTTPClient.METHOD_DELETE

	var body_text := ""
	if body != null:
		body_text = JSON.stringify(body)

	var err: int
	if body_text != "":
		err = http.request(url, headers, method_int, body_text)
	else:
		err = http.request(url, headers, method_int)

	if err != OK:
		http.queue_free()
		return SyncResult.failure("Request failed: " + error_string(err))

	var response: Array = await http.request_completed
	http.queue_free()

	var status_code: int = response[1]
	var body_bytes: PackedByteArray = response[3]
	var body_str: String = body_bytes.get_string_from_utf8()

	if status_code < 200 or status_code >= 300:
		var msg := body_str if not body_str.is_empty() else "HTTP %d" % status_code
		return SyncResult.failure(msg)

	var parsed = JSON.parse_string(body_str)
	if parsed == null:
		return SyncResult.failure("Invalid JSON response")
	if parsed is Dictionary:
		return SyncResult.success(parsed)
	return SyncResult.success({"data": parsed})
