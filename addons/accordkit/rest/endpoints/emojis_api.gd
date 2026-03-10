class_name EmojisApi
extends EndpointBase

## REST endpoint helpers for custom emoji management within a space:
## listing, fetching, creating, updating, and deleting emojis.


## Lists all custom emojis in a space.
func list(space_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/emojis")
	return result.deserialize_array(AccordEmoji.from_dict)


## Fetches a single custom emoji by its snowflake ID within a space.
func fetch(space_id: String, emoji_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/emojis/" + emoji_id)
	return result.deserialize(AccordEmoji.from_dict)


## Creates a new custom emoji in a space. The data dictionary should contain
## "name" and "image" (base64 data URI) keys, and optionally "roles".
func create(space_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/spaces/" + space_id + "/emojis", data)
	return result.deserialize(AccordEmoji.from_dict)


## Updates a custom emoji's name or role restrictions.
func update(space_id: String, emoji_id: String, data: Dictionary) -> RestResult:
	var path := "/spaces/" + space_id + "/emojis/" + emoji_id
	var result := await _rest.make_request("PATCH", path, data)
	return result.deserialize(AccordEmoji.from_dict)


## Deletes a custom emoji from a space.
func delete(space_id: String, emoji_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/emojis/" + emoji_id)
	return result
