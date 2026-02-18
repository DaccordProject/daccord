class_name ClientAdmin
extends RefCounted

## Admin API wrappers for Client.
## Thin delegation layer that routes calls to the correct
## AccordClient and refreshes caches on success.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func update_space(
	guild_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.spaces.update(guild_id, data)
	if result.ok:
		await _c.fetch.fetch_guilds()
	return result

func delete_space(guild_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.spaces.delete(guild_id)

func create_channel(
	guild_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.spaces.create_channel(
		guild_id, data
	)
	if result.ok:
		await _c.fetch.fetch_channels(guild_id)
	return result

func update_channel(
	channel_id: String, data: Dictionary
) -> RestResult:
	var guild_id: String = _c._channel_to_guild.get(
		channel_id, ""
	)
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", channel_id
		)
		return null
	var result: RestResult = await client.channels.update(channel_id, data)
	if result.ok and not guild_id.is_empty():
		await _c.fetch.fetch_channels(guild_id)
	return result

func delete_channel(channel_id: String) -> RestResult:
	var guild_id: String = _c._channel_to_guild.get(
		channel_id, ""
	)
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", channel_id
		)
		return null
	var result: RestResult = await client.channels.delete(channel_id)
	if result.ok and not guild_id.is_empty():
		await _c.fetch.fetch_channels(guild_id)
	return result

func create_role(
	guild_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.roles.create(guild_id, data)
	if result.ok:
		await _c.fetch.fetch_roles(guild_id)
	return result

func update_role(
	guild_id: String, role_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.roles.update(
		guild_id, role_id, data
	)
	if result.ok:
		await _c.fetch.fetch_roles(guild_id)
	return result

func delete_role(
	guild_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.roles.delete(guild_id, role_id)
	if result.ok:
		await _c.fetch.fetch_roles(guild_id)
	return result

func kick_member(
	guild_id: String, user_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.members.kick(guild_id, user_id)
	if result.ok:
		await _c.fetch.fetch_members(guild_id)
	return result

func ban_member(
	guild_id: String, user_id: String,
	data: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.bans.create(
		guild_id, user_id, data
	)
	if result.ok:
		await _c.fetch.fetch_members(guild_id)
		AppState.bans_updated.emit(guild_id)
	return result

func unban_member(
	guild_id: String, user_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.bans.remove(guild_id, user_id)
	if result.ok:
		AppState.bans_updated.emit(guild_id)
	return result

func add_member_role(
	guild_id: String, user_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.members.add_role(
		guild_id, user_id, role_id
	)
	if result.ok:
		await _c.fetch.fetch_members(guild_id)
	return result

func remove_member_role(
	guild_id: String, user_id: String, role_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.members.remove_role(
		guild_id, user_id, role_id
	)
	if result.ok:
		await _c.fetch.fetch_members(guild_id)
	return result

func get_bans(guild_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.bans.list(guild_id)

func get_invites(guild_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.invites.list_space(guild_id)

func create_invite(
	guild_id: String, data: Dictionary = {}
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.invites.create_space(
		guild_id, data
	)
	if result.ok:
		AppState.invites_updated.emit(guild_id)
	return result

func delete_invite(
	code: String, guild_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.invites.delete(code)
	if result.ok:
		AppState.invites_updated.emit(guild_id)
	return result

func get_emojis(guild_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.emojis.list(guild_id)

func create_emoji(
	guild_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.emojis.create(guild_id, data)
	if result.ok:
		AppState.emojis_updated.emit(guild_id)
	return result

func update_emoji(
	guild_id: String, emoji_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.emojis.update(
		guild_id, emoji_id, data
	)
	if result.ok:
		AppState.emojis_updated.emit(guild_id)
	return result

func delete_emoji(
	guild_id: String, emoji_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.emojis.delete(
		guild_id, emoji_id
	)
	if result.ok:
		AppState.emojis_updated.emit(guild_id)
	return result

func get_emoji_url(
	guild_id: String, emoji_id: String,
	animated: bool = false
) -> String:
	var cdn_url: String = _c._cdn_for_guild(guild_id)
	var fmt := "gif" if animated else "png"
	return AccordCDN.emoji(emoji_id, fmt, cdn_url)

func get_sounds(guild_id: String) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.soundboard.list(guild_id)

func create_sound(
	guild_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.soundboard.create(guild_id, data)
	if result.ok:
		AppState.soundboard_updated.emit(guild_id)
	return result

func update_sound(
	guild_id: String, sound_id: String, data: Dictionary
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.soundboard.update(
		guild_id, sound_id, data
	)
	if result.ok:
		AppState.soundboard_updated.emit(guild_id)
	return result

func delete_sound(
	guild_id: String, sound_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.soundboard.delete(
		guild_id, sound_id
	)
	if result.ok:
		AppState.soundboard_updated.emit(guild_id)
	return result

func play_sound(
	guild_id: String, sound_id: String
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.soundboard.play(guild_id, sound_id)

func get_sound_url(
	guild_id: String, audio_url: String
) -> String:
	var cdn_url: String = _c._cdn_for_guild(guild_id)
	return AccordCDN.sound(audio_url, cdn_url)

func reorder_channels(
	guild_id: String, data: Array
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.spaces.reorder_channels(
		guild_id, data
	)
	if result.ok:
		await _c.fetch.fetch_channels(guild_id)
	return result

func reorder_roles(
	guild_id: String, data: Array
) -> RestResult:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	var result: RestResult = await client.roles.reorder(guild_id, data)
	if result.ok:
		await _c.fetch.fetch_roles(guild_id)
	return result

func update_channel_overwrites(
	channel_id: String, overwrites: Array,
	deleted_ids: Array = [],
) -> RestResult:
	var guild_id: String = _c._channel_to_guild.get(
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

	if not guild_id.is_empty():
		await _c.fetch.fetch_channels(guild_id)

	# Return a successful result even if no operations ran
	if last_result == null:
		last_result = RestResult.success(200, null)
	return last_result
