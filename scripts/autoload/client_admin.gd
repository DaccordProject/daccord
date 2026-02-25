class_name ClientAdmin
extends RefCounted

## Admin API wrappers for Client.
## Thin delegation layer that routes calls to the correct
## AccordClient and refreshes caches on success.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func update_space(
	space_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.spaces.update(space_id, data)
	if result.ok:
		await _c.fetch.fetch_spaces()
	return result

func delete_space(space_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.spaces.delete(space_id)

func create_channel(
	space_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.spaces.create_channel(
		space_id, data
	)
	if result.ok:
		await _c.fetch.fetch_channels(space_id)
	return result

func update_channel(
	channel_id: String, data: Dictionary
) -> RestResult:
	var space_id: String = _c._channel_to_space.get(
		channel_id, ""
	)
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", channel_id
		)
		return null
	var result: RestResult = await client.channels.update(channel_id, data)
	if result.ok and not space_id.is_empty():
		await _c.fetch.fetch_channels(space_id)
	return result

func delete_channel(channel_id: String) -> RestResult:
	var space_id: String = _c._channel_to_space.get(
		channel_id, ""
	)
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", channel_id
		)
		return null
	var result: RestResult = await client.channels.delete(channel_id)
	if result.ok and not space_id.is_empty():
		await _c.fetch.fetch_channels(space_id)
	return result

func create_role(
	space_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.roles.create(space_id, data)
	if result.ok:
		await _c.fetch.fetch_roles(space_id)
	return result

func update_role(
	space_id: String, role_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.roles.update(
		space_id, role_id, data
	)
	if result.ok:
		await _c.fetch.fetch_roles(space_id)
	return result

func delete_role(
	space_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.roles.delete(space_id, role_id)
	if result.ok:
		await _c.fetch.fetch_roles(space_id)
	return result

func kick_member(
	space_id: String, user_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.members.kick(space_id, user_id)
	if result.ok:
		await _c.fetch.fetch_members(space_id)
	return result

func ban_member(
	space_id: String, user_id: String,
	data: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.bans.create(
		space_id, user_id, data
	)
	if result.ok:
		await _c.fetch.fetch_members(space_id)
		AppState.bans_updated.emit(space_id)
	return result

func unban_member(
	space_id: String, user_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.bans.remove(space_id, user_id)
	if result.ok:
		AppState.bans_updated.emit(space_id)
	return result

func add_member_role(
	space_id: String, user_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.members.add_role(
		space_id, user_id, role_id
	)
	if result.ok:
		await _c.fetch.fetch_members(space_id)
	return result

func remove_member_role(
	space_id: String, user_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.members.remove_role(
		space_id, user_id, role_id
	)
	if result.ok:
		await _c.fetch.fetch_members(space_id)
	return result

func update_member(
	space_id: String, user_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.members.update(
		space_id, user_id, data
	)
	if result.ok:
		await _c.fetch.fetch_members(space_id)
	return result

func get_audit_log(
	space_id: String, query: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.audit_logs.list(space_id, query)

func get_bans(
	space_id: String, query: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.bans.list(space_id, query)

func get_invites(space_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.invites.list_space(space_id)

func create_invite(
	space_id: String, data: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.invites.create_space(
		space_id, data
	)
	if result.ok:
		AppState.invites_updated.emit(space_id)
	return result

func delete_invite(
	code: String, space_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.invites.delete(code)
	if result.ok:
		AppState.invites_updated.emit(space_id)
	return result

func get_emojis(space_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.emojis.list(space_id)

func create_emoji(
	space_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.emojis.create(space_id, data)
	if result.ok:
		AppState.emojis_updated.emit(space_id)
	return result

func update_emoji(
	space_id: String, emoji_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.emojis.update(
		space_id, emoji_id, data
	)
	if result.ok:
		AppState.emojis_updated.emit(space_id)
	return result

func delete_emoji(
	space_id: String, emoji_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.emojis.delete(
		space_id, emoji_id
	)
	if result.ok:
		AppState.emojis_updated.emit(space_id)
	return result

func get_emoji_url(
	space_id: String, emoji_id: String,
	animated: bool = false
) -> String:
	var cdn_url: String = _c._cdn_for_space(space_id)
	var fmt := "gif" if animated else "png"
	return AccordCDN.emoji(emoji_id, fmt, cdn_url)

func get_sounds(space_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.soundboard.list(space_id)

func create_sound(
	space_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.soundboard.create(space_id, data)
	if result.ok:
		AppState.soundboard_updated.emit(space_id)
	return result

func update_sound(
	space_id: String, sound_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.soundboard.update(
		space_id, sound_id, data
	)
	if result.ok:
		AppState.soundboard_updated.emit(space_id)
	return result

func delete_sound(
	space_id: String, sound_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.soundboard.delete(
		space_id, sound_id
	)
	if result.ok:
		AppState.soundboard_updated.emit(space_id)
	return result

func play_sound(
	space_id: String, sound_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	return await client.soundboard.play(space_id, sound_id)

func get_sound_url(
	space_id: String, audio_url: String
) -> String:
	var cdn_url: String = _c._cdn_for_space(space_id)
	return AccordCDN.sound(audio_url, cdn_url)

func reorder_channels(
	space_id: String, data: Array
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.spaces.reorder_channels(
		space_id, data
	)
	if result.ok:
		await _c.fetch.fetch_channels(space_id)
	return result

func reorder_roles(
	space_id: String, data: Array
) -> RestResult:
	var client: AccordClient = _c._client_for_space(space_id)
	if client == null:
		push_error("[Client] No connection for space:", space_id)
		return null
	var result: RestResult = await client.roles.reorder(space_id, data)
	if result.ok:
		await _c.fetch.fetch_roles(space_id)
	return result

func update_channel_overwrites(
	channel_id: String, overwrites: Array,
	deleted_ids: Array = [],
) -> RestResult:
	var space_id: String = _c._channel_to_space.get(
		channel_id, ""
	)
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", channel_id
		)
		return null

	# Delete overwrites that were reset to all-INHERIT
	for ow_id in deleted_ids:
		var del_result: RestResult = await client.channels \
			.delete_overwrite(channel_id, ow_id)
		if not del_result.ok:
			return del_result

	# Upsert each remaining overwrite individually
	var last_result: RestResult = null
	for ow in overwrites:
		var ow_id: String = ow.get("id", "")
		var data: Dictionary = {
			"type": ow.get("type", "role"),
			"allow": ow.get("allow", []),
			"deny": ow.get("deny", []),
		}
		last_result = await client.channels.upsert_overwrite(
			channel_id, ow_id, data
		)
		if not last_result.ok:
			return last_result

	if not space_id.is_empty():
		await _c.fetch.fetch_channels(space_id)

	# Return a successful result even if no operations ran
	if last_result == null:
		last_result = RestResult.success(200, null)
	return last_result
