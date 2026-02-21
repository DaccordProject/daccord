class_name ClientMutationsDm
extends RefCounted

## Handles DM channel mutation operations for ClientMutations.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func create_dm(user_id: String) -> void:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for create_dm"
		)
		return
	var cdn_url: String = _c._first_connected_cdn()
	var result: RestResult = await client.users.create_dm(
		{"recipient_id": user_id}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error("[Client] Failed to create DM: ", err)
		return
	var channel: AccordChannel = result.data
	# Cache the recipient
	if channel.recipients != null \
			and channel.recipients is Array:
		for recipient in channel.recipients:
			if not _c._user_cache.has(recipient.id):
				_c._user_cache[recipient.id] = \
					ClientModels.user_to_dict(
						recipient,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
	_c._dm_channel_cache[channel.id] = \
		ClientModels.dm_channel_to_dict(
			channel, _c._user_cache
		)
	AppState.dm_channels_updated.emit()
	AppState.enter_dm_mode()
	AppState.select_channel(channel.id)

func create_group_dm(user_ids: Array) -> void:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for create_group_dm"
		)
		return
	var cdn_url: String = _c._first_connected_cdn()
	var result: RestResult = await client.users.create_dm(
		{"recipients": user_ids}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to create group DM: ", err
		)
		return
	var channel: AccordChannel = result.data
	# Cache all recipients
	if channel.recipients != null \
			and channel.recipients is Array:
		for recipient in channel.recipients:
			if not _c._user_cache.has(recipient.id):
				_c._user_cache[recipient.id] = \
					ClientModels.user_to_dict(
						recipient,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
	_c._dm_channel_cache[channel.id] = \
		ClientModels.dm_channel_to_dict(
			channel, _c._user_cache
		)
	AppState.dm_channels_updated.emit()
	AppState.enter_dm_mode()
	AppState.select_channel(channel.id)


func add_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for add_dm_member"
		)
		return false
	var result: RestResult = \
		await client.channels.add_recipient(
			channel_id, user_id
		)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to add DM member: ", err
		)
		return false
	return true


func remove_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for remove_dm_member"
		)
		return false
	var result: RestResult = \
		await client.channels.remove_recipient(
			channel_id, user_id
		)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to remove DM member: ", err
		)
		return false
	# If removing self, clean up cache
	if user_id == _c.current_user.get("id", ""):
		_c._dm_channel_cache.erase(channel_id)
		_c._dm_to_conn.erase(channel_id)
		if AppState.current_channel_id == channel_id:
			AppState.current_channel_id = ""
		AppState.dm_channels_updated.emit()
	return true


func rename_group_dm(
	channel_id: String, new_name: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for rename_group_dm"
		)
		return false
	var result: RestResult = await client.channels.update(
		channel_id, {"name": new_name}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to rename group DM: ", err
		)
		return false
	return true


func close_dm(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for close_dm"
		)
		return
	var result: RestResult = await client.channels.delete(
		channel_id
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error("[Client] Failed to close DM: ", err)
		return
	_c._dm_channel_cache.erase(channel_id)
	_c._dm_to_conn.erase(channel_id)
	# If we were viewing this DM, clear selection
	if AppState.current_channel_id == channel_id:
		AppState.current_channel_id = ""
	AppState.dm_channels_updated.emit()
