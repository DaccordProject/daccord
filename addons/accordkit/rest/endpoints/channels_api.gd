class_name ChannelsApi
extends EndpointBase

## REST endpoint helpers for channel-level routes (get, update, delete).
## Message and reaction operations live in their own dedicated API classes.


## Fetches a channel by its snowflake ID.
func fetch(channel_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/channels/" + channel_id)
	return result.deserialize(AccordChannel.from_dict)


## Updates a channel's settings (name, topic, permissions, etc.).
func update(channel_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/channels/" + channel_id, data)
	return result.deserialize(AccordChannel.from_dict)


## Deletes or closes a channel. For DM channels this closes the channel
## rather than permanently deleting it.
func delete(channel_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/channels/" + channel_id)
	return result.deserialize(AccordChannel.from_dict)


## Lists all permission overwrites for a channel.
func list_overwrites(channel_id: String) -> RestResult:
	return await _rest.make_request(
		"GET", "/channels/" + channel_id + "/permissions"
	)


## Creates or updates a permission overwrite for a role or member.
func upsert_overwrite(
	channel_id: String, overwrite_id: String, data: Dictionary
) -> RestResult:
	return await _rest.make_request(
		"PUT",
		"/channels/" + channel_id + "/permissions/" + overwrite_id,
		data,
	)


## Deletes a permission overwrite from a channel.
func delete_overwrite(
	channel_id: String, overwrite_id: String
) -> RestResult:
	return await _rest.make_request(
		"DELETE",
		"/channels/" + channel_id + "/permissions/" + overwrite_id,
	)


## Adds a user to a group DM channel.
func add_recipient(channel_id: String, user_id: String) -> RestResult:
	return await _rest.make_request(
		"PUT",
		"/channels/" + channel_id + "/recipients/" + user_id,
	)


## Removes a user from a group DM channel.
func remove_recipient(channel_id: String, user_id: String) -> RestResult:
	return await _rest.make_request(
		"DELETE",
		"/channels/" + channel_id + "/recipients/" + user_id,
	)


## Mutes a channel or category for the current user.
func mute(channel_id: String) -> RestResult:
	return await _rest.make_request(
		"PUT", "/channels/" + channel_id + "/mute"
	)


## Unmutes a channel or category for the current user.
func unmute(channel_id: String) -> RestResult:
	return await _rest.make_request(
		"DELETE", "/channels/" + channel_id + "/mute"
	)


## Acknowledges (marks as read) a channel up to the given message ID.
func ack(channel_id: String, message_id: String) -> RestResult:
	return await _rest.make_request(
		"POST",
		"/channels/" + channel_id + "/ack",
		{"message_id": message_id},
	)
