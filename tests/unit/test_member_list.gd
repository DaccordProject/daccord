extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var component: PanelContainer

const SPACE_ID := "g_1"


func _make_member(id: String, display_name: String, status: int = ClientModels.UserStatus.ONLINE, roles: Array = []) -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"username": display_name.to_lower(),
		"color": Color.WHITE,
		"status": status,
		"avatar": null,
		"roles": roles,
	}


func before_each() -> void:
	Client.current_user = TestDataFactory.user_data({"id": "me_1", "display_name": "Me"})
	Client._member_cache = {}
	Client._role_cache = {}
	component = load("res://scenes/members/member_list.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame
	Client._member_cache = {}
	Client._role_cache = {}


# --- initial state ---

func test_instantiates_without_error() -> void:
	assert_true(is_instance_valid(component))


func test_initial_row_data_is_empty() -> void:
	assert_eq(component._row_data.size(), 0)


func test_initial_space_id_is_empty() -> void:
	assert_eq(component._space_id, "")


# --- _rebuild_row_data: status groups ---

func test_rebuild_adds_online_header_and_member() -> void:
	Client._member_cache[SPACE_ID] = [
		_make_member("u_1", "Alice", ClientModels.UserStatus.ONLINE),
	]
	Client._role_cache[SPACE_ID] = []
	component._space_id = SPACE_ID
	component._rebuild_row_data()
	await get_tree().process_frame

	# Should have one header + one member row
	assert_eq(component._row_data.size(), 2)
	var header: Dictionary = component._row_data[0]
	assert_eq(header["type"], "header")
	assert_true(header["label"].begins_with("ONLINE"))
	var member_row: Dictionary = component._row_data[1]
	assert_eq(member_row["type"], "member")
	assert_eq(member_row["data"]["id"], "u_1")


func test_rebuild_groups_online_and_offline_separately() -> void:
	Client._member_cache[SPACE_ID] = [
		_make_member("u_1", "Alice", ClientModels.UserStatus.ONLINE),
		_make_member("u_2", "Bob", ClientModels.UserStatus.OFFLINE),
	]
	Client._role_cache[SPACE_ID] = []
	component._space_id = SPACE_ID
	component._rebuild_row_data()
	await get_tree().process_frame

	# Two headers + two member rows
	assert_eq(component._row_data.size(), 4)
	var types: Array = []
	for row in component._row_data:
		types.append(row["type"])
	assert_eq(types.count("header"), 2)
	assert_eq(types.count("member"), 2)


func test_rebuild_sorts_members_alphabetically_within_group() -> void:
	Client._member_cache[SPACE_ID] = [
		_make_member("u_2", "Zara", ClientModels.UserStatus.ONLINE),
		_make_member("u_1", "Alice", ClientModels.UserStatus.ONLINE),
	]
	Client._role_cache[SPACE_ID] = []
	component._space_id = SPACE_ID
	component._rebuild_row_data()
	await get_tree().process_frame

	var member_rows: Array = []
	for row in component._row_data:
		if row["type"] == "member":
			member_rows.append(row)
	assert_eq(member_rows[0]["data"]["display_name"], "Alice")
	assert_eq(member_rows[1]["data"]["display_name"], "Zara")


func test_rebuild_with_no_members_row_data_stays_empty() -> void:
	Client._member_cache[SPACE_ID] = []
	Client._role_cache[SPACE_ID] = []
	component._space_id = SPACE_ID
	component._rebuild_row_data()
	await get_tree().process_frame

	assert_eq(component._row_data.size(), 0)


# --- _rebuild_row_data: role groups ---

func test_role_group_mode_groups_by_highest_role() -> void:
	Client._member_cache[SPACE_ID] = [
		_make_member("u_1", "Alice", ClientModels.UserStatus.ONLINE, ["role_admin"]),
		_make_member("u_2", "Bob", ClientModels.UserStatus.OFFLINE, []),
	]
	Client._role_cache[SPACE_ID] = [
		{"id": "role_admin", "name": "Admin", "position": 10, "hoist": false, "color": null},
	]
	component._space_id = SPACE_ID
	component._group_by_role = true
	component._rebuild_row_data()
	await get_tree().process_frame

	# Alice under Admin group, Bob under No Role
	var header_labels: Array = []
	for row in component._row_data:
		if row["type"] == "header":
			header_labels.append(row["label"])
	assert_true(header_labels.any(func(l): return "Admin" in l))
	assert_true(header_labels.any(func(l): return "No Role" in l))


# --- _build_dm_participants ---

func test_dm_participants_creates_participant_header() -> void:
	var dm: Dictionary = {
		"id": "dm_1",
		"is_group": true,
		"owner_id": "u_1",
		"recipients": [
			_make_member("u_1", "Alice"),
			_make_member("u_2", "Bob"),
		],
	}
	component._build_dm_participants(dm)
	await get_tree().process_frame

	assert_true(component._row_data.size() > 0)
	var header: Dictionary = component._row_data[0]
	assert_eq(header["type"], "header")
	assert_true(header["label"].begins_with("PARTICIPANTS"))


func test_dm_participants_includes_self_if_not_in_recipients() -> void:
	# Client.current_user has id "me_1" and is not in recipients
	var dm: Dictionary = {
		"id": "dm_1",
		"is_group": true,
		"owner_id": "u_1",
		"recipients": [
			_make_member("u_1", "Alice"),
		],
	}
	component._build_dm_participants(dm)
	await get_tree().process_frame

	# Should include Alice + me = 2 participants
	var member_count: int = 0
	for row in component._row_data:
		if row["type"] == "member":
			member_count += 1
	assert_eq(member_count, 2)


func test_dm_participants_marks_owner() -> void:
	var dm: Dictionary = {
		"id": "dm_1",
		"is_group": true,
		"owner_id": "u_1",
		"recipients": [
			_make_member("u_1", "Alice"),
			_make_member("u_2", "Bob"),
		],
	}
	component._build_dm_participants(dm)
	await get_tree().process_frame

	var owner_marked: bool = false
	for row in component._row_data:
		if row["type"] == "member" and row["data"].get("id", "") == "u_1":
			owner_marked = row["data"].get("_is_owner", false)
	assert_true(owner_marked)


func test_dm_participants_hides_group_toggle() -> void:
	var dm: Dictionary = {
		"id": "dm_1",
		"is_group": true,
		"owner_id": "u_1",
		"recipients": [_make_member("u_1", "Alice")],
	}
	component._build_dm_participants(dm)
	await get_tree().process_frame

	assert_false(component.group_toggle.visible)


func test_dm_participants_clears_space_id() -> void:
	component._space_id = SPACE_ID
	var dm: Dictionary = {
		"id": "dm_1",
		"is_group": true,
		"owner_id": "u_1",
		"recipients": [_make_member("u_1", "Alice")],
	}
	component._build_dm_participants(dm)
	await get_tree().process_frame

	assert_eq(component._space_id, "")


# --- _on_space_selected clears state ---

func test_space_selected_clears_row_data() -> void:
	Client._member_cache[SPACE_ID] = [
		_make_member("u_1", "Alice", ClientModels.UserStatus.ONLINE),
	]
	Client._role_cache[SPACE_ID] = []
	component._space_id = SPACE_ID
	component._rebuild_row_data()
	await get_tree().process_frame

	AppState.space_selected.emit("other_space")
	await get_tree().process_frame

	assert_eq(component._row_data.size(), 0)
