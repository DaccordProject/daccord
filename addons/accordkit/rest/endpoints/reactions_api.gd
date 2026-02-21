class_name ReactionsApi
extends RefCounted

## REST endpoint helpers for message reaction operations: adding, removing,
## and listing reactions on messages.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Adds a reaction to a message. The emoji string should be a Unicode emoji
## or a custom emoji in the format "name:id".
func add(channel_id: String, message_id: String, emoji: String) -> RestResult:
	var encoded_emoji := emoji.uri_encode()
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions/" + encoded_emoji + "/@me"
	)
	var result := await _rest.make_request("PUT", path)
	return result


## Removes the current user's reaction from a message.
func remove_own(channel_id: String, message_id: String, emoji: String) -> RestResult:
	var encoded_emoji := emoji.uri_encode()
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions/" + encoded_emoji + "/@me"
	)
	var result := await _rest.make_request("DELETE", path)
	return result


## Removes another user's reaction from a message. Requires MANAGE_MESSAGES
## permission.
func remove_user(
	channel_id: String, message_id: String,
	emoji: String, user_id: String,
) -> RestResult:
	var encoded_emoji := emoji.uri_encode()
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions/" + encoded_emoji + "/" + user_id
	)
	var result := await _rest.make_request("DELETE", path)
	return result


## Lists users who reacted with a specific emoji on a message. Supports
## pagination query parameters such as "after" and "limit".
func list_users(
	channel_id: String, message_id: String,
	emoji: String, query: Dictionary = {},
) -> RestResult:
	var encoded_emoji := emoji.uri_encode()
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions/" + encoded_emoji
	)
	var result := await _rest.make_request("GET", path, null, query)
	if result.ok and result.data is Array:
		var users := []
		for item in result.data:
			if item is Dictionary:
				users.append(AccordUser.from_dict(item))
		result.data = users
	return result


## Removes all reactions from a message. Requires MANAGE_MESSAGES permission.
func remove_all(channel_id: String, message_id: String) -> RestResult:
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions"
	)
	var result := await _rest.make_request("DELETE", path)
	return result


## Removes all reactions of a specific emoji from a message. Requires
## MANAGE_MESSAGES permission.
func remove_emoji(channel_id: String, message_id: String, emoji: String) -> RestResult:
	var encoded_emoji := emoji.uri_encode()
	var path := (
		"/channels/" + channel_id + "/messages/" + message_id
		+ "/reactions/" + encoded_emoji
	)
	var result := await _rest.make_request("DELETE", path)
	return result
