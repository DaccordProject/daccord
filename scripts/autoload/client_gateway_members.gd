class_name ClientGatewayMembers
extends RefCounted

## Handles member lifecycle gateway events for ClientGateway.
## Processes member chunks, joins, leaves, and updates.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func on_member_chunk(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var cdn_url: String = _c._connections[conn_index]["cdn_url"]
	var members_data: Array = data.get("members", [])
	if not _c._member_cache.has(space_id):
		_c._member_cache[space_id] = []
	var existing: Array = _c._member_cache[space_id]
	var existing_ids: Dictionary = {}
	for i in existing.size():
		existing_ids[existing[i].get("id", "")] = i
	for raw in members_data:
		if raw is Dictionary:
			var raw_user = raw.get("user", null)
			if raw_user is Dictionary:
				var uid: String = str(raw_user.get("id", ""))
				if not uid.is_empty() and not _c._user_cache.has(uid):
					var parsed_user: AccordUser = AccordUser.from_dict(raw_user)
					_c._user_cache[uid] = ClientModels.user_to_dict(
						parsed_user, ClientModels.UserStatus.OFFLINE, cdn_url
					)
		var member: AccordMember = AccordMember.from_dict(raw)
		var member_dict := ClientModels.member_to_dict(member, _c._user_cache, cdn_url)
		if existing_ids.has(member.user_id):
			existing[existing_ids[member.user_id]] = member_dict
		else:
			existing.append(member_dict)
			existing_ids[member.user_id] = existing.size() - 1
	_c._member_id_index[space_id] = existing_ids
	AppState.members_updated.emit(space_id)

func on_member_join(member: AccordMember, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	var space_id: String = conn["space_id"]
	var cdn_url: String = conn["cdn_url"]
	if not _c._user_cache.has(member.user_id):
		if member.user != null:
			_c._user_cache[member.user_id] = ClientModels.user_to_dict(
				member.user, ClientModels.UserStatus.OFFLINE, cdn_url
			)
		else:
			var client: AccordClient = conn["client"]
			if client != null:
				var user_result: RestResult = await client.users.fetch(member.user_id)
				if user_result.ok:
					_c._user_cache[member.user_id] = ClientModels.user_to_dict(
						user_result.data,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
	var member_dict := ClientModels.member_to_dict(member, _c._user_cache, cdn_url)
	if not _c._member_cache.has(space_id):
		_c._member_cache[space_id] = []
	_c._member_cache[space_id].append(member_dict)
	if not _c._member_id_index.has(space_id):
		_c._member_id_index[space_id] = {}
	_c._member_id_index[space_id][member.user_id] = _c._member_cache[space_id].size() - 1
	AppState.member_joined.emit(space_id, member_dict)
	AppState.members_updated.emit(space_id)

func on_member_leave(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var user_id: String = str(data.get("user_id", ""))
	if user_id.is_empty():
		var user_data = data.get("user", null)
		if user_data is Dictionary:
			user_id = str(user_data.get("id", ""))
	if user_id.is_empty():
		push_warning(
			"[Gateway] member.leave missing user_id, keys: ",
			data.keys()
		)
		return
	if _c._member_cache.has(space_id):
		var idx: int = _c._member_index_for(space_id, user_id)
		if idx != -1:
			_c._member_cache[space_id].remove_at(idx)
			_c._rebuild_member_index(space_id)
			AppState.member_left.emit(space_id, user_id)
			AppState.members_updated.emit(space_id)

func on_member_update(member: AccordMember, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var cdn_url: String = _c._connections[conn_index]["cdn_url"]
	if _c._member_cache.has(space_id):
		var member_dict := ClientModels.member_to_dict(member, _c._user_cache, cdn_url)
		var idx: int = _c._member_index_for(space_id, member.user_id)
		if idx != -1:
			_c._member_cache[space_id][idx] = member_dict
		else:
			_c._member_cache[space_id].append(member_dict)
			if not _c._member_id_index.has(space_id):
				_c._member_id_index[space_id] = {}
			_c._member_id_index[space_id][member.user_id] = _c._member_cache[space_id].size() - 1
		AppState.members_updated.emit(space_id)
