class_name AccordRest
extends Node

## Central HTTP client for AccordKit. Manages authentication, request
## construction, response parsing, and automatic rate-limit retry. Must live
## in the scene tree so it can create HTTPRequest child nodes on demand.

const _MAX_RETRIES := 3
const _METHOD_MAP := {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH,
	"DELETE": HTTPClient.METHOD_DELETE,
}
const _RESULT_MESSAGES := {
	HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "Response body size mismatch",
	HTTPRequest.RESULT_CANT_CONNECT: "Could not connect to server",
	HTTPRequest.RESULT_CANT_RESOLVE: "Could not resolve hostname",
	HTTPRequest.RESULT_CONNECTION_ERROR: "Connection error",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS/SSL handshake failed",
	HTTPRequest.RESULT_NO_RESPONSE: "No response from server",
	HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "Response too large",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "Failed to decompress response",
	HTTPRequest.RESULT_REQUEST_FAILED: "Request failed",
	HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "Cannot open download file",
	HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "Download file write error",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "Too many redirects",
	HTTPRequest.RESULT_TIMEOUT: "Request timed out",
}

var token: String = ""
var token_type: String = "Bot"  # "Bot" or "Bearer"
var base_url: String = ""


func _init(base: String = "") -> void:
	base_url = base


## Performs an HTTP request against the API and returns a RestResult.
## The method string should be one of GET, POST, PUT, PATCH, DELETE.
## The path is appended to base_url. An optional body (Dictionary or Array)
## is serialized to JSON for non-GET requests. The query dictionary is
## URL-encoded and appended to the path.
func make_request(method: String, path: String, body = null, query: Dictionary = {}) -> RestResult:
	var url := base_url + path
	var query_string := _encode_query(query)
	if query_string != "":
		url += "?" + query_string

	var headers := _build_headers()
	var http_method: int = _METHOD_MAP.get(method, HTTPClient.METHOD_GET)
	var body_text := ""
	if body != null:
		body_text = JSON.stringify(body)

	var attempt := 0
	while attempt < _MAX_RETRIES:
		var http := HTTPRequest.new()
		add_child(http)

		var err: int
		if body_text != "":
			err = http.request(url, headers, http_method, body_text)
		else:
			err = http.request(url, headers, http_method)

		if err != OK:
			http.queue_free()
			return RestResult.failure(
				0, _internal_error("Failed to start request: " + error_string(err))
			)

		var response: Array = await http.request_completed
		http.queue_free()

		var result_code: int = response[0]
		var status_code: int = response[1]
		var response_headers: PackedStringArray = response[2]
		var response_body: PackedByteArray = response[3]

		if result_code != HTTPRequest.RESULT_SUCCESS:
			var msg: String = _RESULT_MESSAGES.get(result_code, "Unknown error (" + str(result_code) + ")")
			return RestResult.failure(0, _internal_error(msg))

		# Handle rate limiting
		if status_code == 429:
			var retry_after := _get_retry_after(response_headers, response_body)
			attempt += 1
			if attempt < _MAX_RETRIES:
				await get_tree().create_timer(retry_after).timeout
				continue
			else:
				return RestResult.failure(
					429, _internal_error("Rate limited after " + str(_MAX_RETRIES) + " retries")
				)

		var body_string := response_body.get_string_from_utf8()
		return _parse_response(status_code, body_string)

	# Should not reach here, but guard against it.
	return RestResult.failure(0, _internal_error("Request exhausted all retries"))


## Performs a multipart/form-data HTTP request. Used for file uploads.
## The form argument should be a MultipartForm instance with parts already added.
## The path is appended to base_url. The query dictionary is URL-encoded.
func make_multipart_request(method: String, path: String, form: MultipartForm, query: Dictionary = {}) -> RestResult:
	var url := base_url + path
	var query_string := _encode_query(query)
	if query_string != "":
		url += "?" + query_string

	var headers := _build_headers_for_content_type(form.get_content_type())
	var http_method: int = _METHOD_MAP.get(method, HTTPClient.METHOD_POST)
	var body_bytes := form.build()

	var attempt := 0
	while attempt < _MAX_RETRIES:
		var http := HTTPRequest.new()
		add_child(http)

		var err: int = http.request_raw(url, headers, http_method, body_bytes)

		if err != OK:
			http.queue_free()
			return RestResult.failure(
				0, _internal_error("Failed to start multipart request: " + error_string(err))
			)

		var response: Array = await http.request_completed
		http.queue_free()

		var result_code: int = response[0]
		var status_code: int = response[1]
		var response_headers: PackedStringArray = response[2]
		var response_body: PackedByteArray = response[3]

		if result_code != HTTPRequest.RESULT_SUCCESS:
			var msg: String = _RESULT_MESSAGES.get(result_code, "Unknown error (" + str(result_code) + ")")
			return RestResult.failure(0, _internal_error(msg))

		# Handle rate limiting
		if status_code == 429:
			var retry_after := _get_retry_after(response_headers, response_body)
			attempt += 1
			if attempt < _MAX_RETRIES:
				await get_tree().create_timer(retry_after).timeout
				continue
			else:
				return RestResult.failure(
					429, _internal_error("Rate limited after " + str(_MAX_RETRIES) + " retries")
				)

		var body_string := response_body.get_string_from_utf8()
		return _parse_response(status_code, body_string)

	# Should not reach here, but guard against it.
	return RestResult.failure(0, _internal_error("Multipart request exhausted all retries"))


## Builds the standard headers array including authorization and content type.
func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	headers.append("User-Agent: " + AccordConfig.USER_AGENT)
	if token != "":
		headers.append("Authorization: " + token_type + " " + token)
	return headers


## Builds headers with a custom Content-Type (used for multipart requests).
func _build_headers_for_content_type(content_type: String) -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Content-Type: " + content_type)
	headers.append("User-Agent: " + AccordConfig.USER_AGENT)
	if token != "":
		headers.append("Authorization: " + token_type + " " + token)
	return headers


## URL-encodes a dictionary of query parameters into a query string.
func _encode_query(params: Dictionary) -> String:
	if params.is_empty():
		return ""
	var parts := PackedStringArray()
	for key in params:
		var value = params[key]
		if value == null:
			continue
		parts.append(str(key).uri_encode() + "=" + str(value).uri_encode())
	return "&".join(parts)


## Parses the raw HTTP response body into a RestResult. Expects a JSON
## envelope with either a "data" key (success) or an "error" key (failure).
## Responses that are not valid JSON are treated as internal errors.
func _parse_response(status: int, body: String) -> RestResult:
	var is_success := status >= 200 and status < 300

	if body.strip_edges() == "":
		# Some endpoints (DELETE, PUT with no content) return empty bodies.
		if is_success:
			return RestResult.success(status, null)
		return RestResult.failure(
			status, _internal_error("Empty response with status " + str(status))
		)

	var json := JSON.new()
	if json.parse(body) != OK:
		if is_success:
			return RestResult.success(status, null)
		return RestResult.failure(
			status, _internal_error("Failed to parse JSON response")
		)

	return _interpret_parsed(status, json.data, is_success)


## Interprets already-parsed JSON data into a RestResult.
func _interpret_parsed(status: int, parsed, is_success: bool) -> RestResult:
	if not parsed is Dictionary:
		if is_success:
			return RestResult.success(status, parsed)
		return RestResult.failure(
			status, _internal_error("Unexpected response format")
		)

	# Error envelope
	if parsed.has("error"):
		var error_data = parsed["error"]
		var accord_error: AccordError
		if error_data is Dictionary:
			accord_error = AccordError.from_dict(error_data)
		else:
			accord_error = AccordError.new()
			accord_error.message = str(error_data)
		return RestResult.failure(status, accord_error)

	# Success envelope with "data" key
	if parsed.has("data"):
		var cursor := {}
		if parsed.has("cursor") and parsed["cursor"] is Dictionary:
			cursor = parsed["cursor"]
		elif parsed.has("pagination") and parsed["pagination"] is Dictionary:
			cursor = parsed["pagination"]
		# Normalize cursor to always have has_more and after
		if not cursor.is_empty() and not cursor.has("has_more"):
			cursor["has_more"] = cursor.get("after", "") != ""
		return RestResult.success(status, parsed["data"], cursor)

	# Plain dictionary response (no envelope)
	if is_success:
		return RestResult.success(status, parsed)
	var accord_error := AccordError.new()
	accord_error.code = str(parsed.get("code", ""))
	accord_error.message = parsed.get("message", "Unknown error")
	return RestResult.failure(status, accord_error)


## Extracts the Retry-After value in seconds from rate-limit response headers
## or the JSON body. Falls back to 1.0 second if neither is present.
func _get_retry_after(headers: PackedStringArray, body: PackedByteArray) -> float:
	# Check headers first
	for header in headers:
		var lower := header.to_lower()
		if lower.begins_with("retry-after:"):
			var value := header.substr(header.find(":") + 1).strip_edges()
			if value.is_valid_float():
				return value.to_float()

	# Check body JSON
	var body_string := body.get_string_from_utf8()
	if body_string != "":
		var json := JSON.new()
		if json.parse(body_string) == OK and json.data is Dictionary:
			var retry_val = json.data.get("retry_after", null)
			if retry_val != null:
				return float(retry_val)

	return 1.0


## Creates an AccordError for internal client-side failures.
func _internal_error(msg: String) -> AccordError:
	var e := AccordError.new()
	e.code = "INTERNAL"
	e.message = msg
	return e
