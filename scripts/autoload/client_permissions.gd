extends RefCounted

var _c: Node # Client reference


func _init(client: Node) -> void:
	_c = client


func has_permission(gid: String, perm: String) -> bool:
	if AppState.is_imposter_mode and gid == AppState.imposter_guild_id:
		return AccordPermission.has(AppState.imposter_permissions, perm)
	var my_id: String = _c.current_user.get("id", "")
	if _c.current_user.get("is_admin", false):
		return true
	var guild: Dictionary = _c._guild_cache.get(gid, {})
	if guild.get("owner_id", "") == my_id:
		return true
	var my_roles: Array = []
	var mi: int = _c._member_index_for(gid, my_id)
	if mi != -1:
		my_roles = _c._member_cache.get(gid, [])[mi].get("roles", [])
	var roles: Array = _c._role_cache.get(gid, [])
	var all_perms: Array = []
	for role in roles:
		var in_role: bool = role.get("id", "") in my_roles
		if role.get("position", 0) == 0 or in_role:
			for p in role.get("permissions", []):
				if p not in all_perms:
					all_perms.append(p)
	return AccordPermission.has(all_perms, perm)


func has_channel_permission(
	gid: String, channel_id: String, perm: String,
) -> bool:
	# Imposter mode override
	if AppState.is_imposter_mode \
			and gid == AppState.imposter_guild_id:
		return AccordPermission.has(
			AppState.imposter_permissions, perm
		)
	var my_id: String = _c.current_user.get("id", "")
	# Instance admin / space owner bypass
	if _c.current_user.get("is_admin", false):
		return true
	var guild: Dictionary = _c._guild_cache.get(gid, {})
	if guild.get("owner_id", "") == my_id:
		return true

	# Gather user's role IDs
	var my_roles: Array = []
	var mi: int = _c._member_index_for(gid, my_id)
	if mi != -1:
		my_roles = _c._member_cache.get(
			gid, []
		)[mi].get("roles", [])

	# Compute base permissions from @everyone + assigned roles
	var roles: Array = _c._role_cache.get(gid, [])
	var base_perms: Array = []
	var everyone_role_id: String = ""
	for role in roles:
		var rid: String = role.get("id", "")
		if role.get("position", 0) == 0:
			everyone_role_id = rid
		if role.get("position", 0) == 0 or rid in my_roles:
			for p in role.get("permissions", []):
				if p not in base_perms:
					base_perms.append(p)

	# Administrator bypass
	if AccordPermission.ADMINISTRATOR in base_perms:
		return true

	# Get channel overwrites
	var ch: Dictionary = _c._channel_cache.get(channel_id, {})
	var overwrites: Array = ch.get(
		"permission_overwrites", []
	)
	if overwrites.is_empty():
		return perm in base_perms

	# Start with base
	var effective: Array = base_perms.duplicate()

	# Apply @everyone channel overwrite
	for ow in overwrites:
		if ow.get("id", "") == everyone_role_id:
			for d in ow.get("deny", []):
				effective.erase(d)
			for a in ow.get("allow", []):
				if a not in effective:
					effective.append(a)
			break

	# Union role overwrites (allow wins over deny)
	var role_allow: Array = []
	var role_deny: Array = []
	for ow in overwrites:
		if ow.get("type", "role") != "role":
			continue
		if ow.get("id", "") == everyone_role_id:
			continue
		if ow.get("id", "") not in my_roles:
			continue
		for a in ow.get("allow", []):
			if a not in role_allow:
				role_allow.append(a)
		for d in ow.get("deny", []):
			if d not in role_deny:
				role_deny.append(d)
	# Apply: deny first, then allow wins
	for d in role_deny:
		if d not in role_allow:
			effective.erase(d)
	for a in role_allow:
		if a not in effective:
			effective.append(a)

	# Apply member-specific overwrite (highest priority)
	for ow in overwrites:
		if ow.get("type", "") == "user" \
				and ow.get("id", "") == my_id:
			for d in ow.get("deny", []):
				effective.erase(d)
			for a in ow.get("allow", []):
				if a not in effective:
					effective.append(a)
			break

	return perm in effective


func is_space_owner(gid: String) -> bool:
	var guild: Dictionary = _c._guild_cache.get(gid, {})
	return guild.get("owner_id", "") == _c.current_user.get(
		"id", ""
	)


func get_my_highest_role_position(gid: String) -> int:
	if _c.current_user.get("is_admin", false):
		return 999999
	if is_space_owner(gid):
		return 999999
	var my_id: String = _c.current_user.get("id", "")
	var mi: int = _c._member_index_for(gid, my_id)
	if mi == -1:
		return 0
	var my_roles: Array = _c._member_cache.get(
		gid, []
	)[mi].get("roles", [])
	var roles: Array = _c._role_cache.get(gid, [])
	var highest: int = 0
	for role in roles:
		if role.get("id", "") in my_roles:
			var pos: int = role.get("position", 0)
			if pos > highest:
				highest = pos
	return highest
