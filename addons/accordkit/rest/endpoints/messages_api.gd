class_name MessagesApi
extends RefCounted

## REST endpoint helpers for message operations within a channel: listing,
## creating, editing, deleting, pinning, and triggering the typing indicator.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists messages in a channel. Supports pagination query parameters such
## as "before", "after", "around", and "limit".
func list(channel_id: String, query: Dictionary = {}) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id + "/messages", null, query)
	if result.ok and result.data is Array:
		var msgs := []
		for item in result.data:
			if item is Dictionary:
				msgs.append(AccordMessage.from_dict(item))
		result.data = msgs
	return result


## Fetches a single message by its snowflake ID.
func fetch(channel_id: String, message_id: String) -> RestResult:
	var path := "/channels/" + channel_id + "/messages/" + message_id
	var result := await _rest.make_request("GET", path)
	if result.ok and result.data is Dictionary:
		result.data = AccordMessage.from_dict(result.data)
	return result


## Creates a new message in a channel. The data dictionary should contain
## at minimum a "content" key or "embeds" array.
func create(channel_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/channels/" + channel_id + "/messages", data)
	if result.ok and result.data is Dictionary:
		result.data = AccordMessage.from_dict(result.data)
	return result


## Creates a new message with file attachments using multipart/form-data.
## The data dictionary contains message metadata (content, reply_to, etc.).
## The files array contains dictionaries with keys: filename (String),
## content (PackedByteArray), content_type (String).
func create_with_attachments(channel_id: String, data: Dictionary, files: Array) -> RestResult:
	var form := MultipartForm.new()
	form.add_json("payload_json", data)
	for i in files.size():
		var file: Dictionary = files[i]
		var name := "files[" + str(i) + "]"
		var filename: String = file.get("filename", "attachment")
		var content: PackedByteArray = file.get("content", PackedByteArray())
		var ct: String = file.get("content_type", "application/octet-stream")
		form.add_file(name, filename, content, ct)
	var result := await _rest.make_multipart_request(
		"POST", "/channels/" + channel_id + "/messages/upload", form
	)
	if result.ok and result.data is Dictionary:
		result.data = AccordMessage.from_dict(result.data)
	return result


## Edits an existing message. Only the message author (or bot with
## appropriate permissions) may edit.
func edit(channel_id: String, message_id: String, data: Dictionary) -> RestResult:
	var path := "/channels/" + channel_id + "/messages/" + message_id
	var result := await _rest.make_request("PATCH", path, data)
	if result.ok and result.data is Dictionary:
		result.data = AccordMessage.from_dict(result.data)
	return result


## Deletes a single message by its snowflake ID.
func delete(channel_id: String, message_id: String) -> RestResult:
	var path := "/channels/" + channel_id + "/messages/" + message_id
	var result := await _rest.make_request("DELETE", path)
	return result


## Bulk-deletes messages (2-100) by their snowflake IDs. Messages older
## than 14 days cannot be bulk-deleted.
func bulk_delete(channel_id: String, message_ids: Array) -> RestResult:
	var path := "/channels/" + channel_id + "/messages/bulk-delete"
	var result := await _rest.make_request("POST", path, {"messages": message_ids})
	return result


## Lists all pinned messages in a channel.
func list_pins(channel_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id + "/pins")
	if result.ok and result.data is Array:
		var msgs := []
		for item in result.data:
			if item is Dictionary:
				msgs.append(AccordMessage.from_dict(item))
		result.data = msgs
	return result


## Pins a message in a channel. A channel may have at most 50 pinned messages.
func pin(channel_id: String, message_id: String) -> RestResult:
	var result := await _rest.make_request("PUT", "/channels/" + channel_id + "/pins/" + message_id)
	return result


## Unpins a message from a channel.
func unpin(channel_id: String, message_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/channels/" + channel_id + "/pins/" + message_id)
	return result


## Searches messages within a space. The query string is matched against
## message content. Additional query parameters like "limit" and "offset"
## are supported for pagination.
func search(
	space_id: String, query_str: String, query: Dictionary = {},
) -> RestResult:
	query["query"] = query_str
	var path := "/spaces/" + space_id + "/messages/search"
	var result := await _rest.make_request("GET", path, null, query)
	if result.ok and result.data is Array:
		var msgs := []
		for item in result.data:
			if item is Dictionary:
				msgs.append(AccordMessage.from_dict(item))
		result.data = msgs
	return result


## Lists thread replies for a parent message. Passes `thread_id` as a query
## parameter to the standard list endpoint.
func list_thread(channel_id: String, parent_message_id: String, query: Dictionary = {}) -> RestResult:
	query["thread_id"] = parent_message_id
	return await list(channel_id, query)


## Fetches thread metadata (reply count, last reply timestamp, participants)
## for a given parent message.
func get_thread_info(channel_id: String, message_id: String) -> RestResult:
	var path := "/channels/" + channel_id + "/messages/" + message_id + "/threads"
	return await _rest.make_request("GET", path)


## Lists all active threads (parent messages with replies) in a channel.
func list_active_threads(channel_id: String) -> RestResult:
	var path := "/channels/" + channel_id + "/threads"
	var result := await _rest.make_request("GET", path)
	if result.ok and result.data is Array:
		var msgs := []
		for item in result.data:
			if item is Dictionary:
				msgs.append(AccordMessage.from_dict(item))
		result.data = msgs
	return result


## Lists top-level posts in a forum channel. Passes `top_level=true`
## to the standard list endpoint so the server returns only root messages.
func list_posts(channel_id: String, query: Dictionary = {}) -> RestResult:
	query["top_level"] = "true"
	return await list(channel_id, query)


## Triggers the typing indicator in a channel. The indicator lasts for
## roughly 10 seconds or until the bot sends a message.
func typing(channel_id: String) -> RestResult:
	var result := await _rest.make_request("POST", "/channels/" + channel_id + "/typing")
	return result
