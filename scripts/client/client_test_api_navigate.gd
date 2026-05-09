class_name ClientTestApiNavigate
extends RefCounted

## Navigation helpers for the Client Test API.
## Surface catalog, dialog map, and viewport resize presets.

## Context menu target types for open_context_menu endpoint.
const CONTEXT_MENU_TARGETS: PackedStringArray = [
	"message", "channel", "member", "guild_icon", "category",
]

## Dialog name → scene path mapping for open_dialog endpoint.
const DIALOG_MAP: Dictionary = {
	"add_server": "res://scenes/connection/add_server_dialog.tscn",
	"create_channel": "res://scenes/admin/create_channel_dialog.tscn",
	"edit_channel": "res://scenes/admin/edit_channel_dialog.tscn",
	"delete_channel": "res://scenes/admin/delete_channel_dialog.tscn",
	"create_invite": "res://scenes/admin/invite_dialog.tscn",
	"create_role": "res://scenes/admin/role_dialog.tscn",
	"edit_role": "res://scenes/admin/role_dialog.tscn",
	"space_settings": "res://scenes/admin/space_settings.tscn",
	"profile_card": "res://scenes/user/profile_card.tscn",
	"app_settings": "res://scenes/user/app_settings.tscn",
	"user_settings": "res://scenes/user/user_settings.tscn",
	"update_download": "res://scenes/messages/update_download_dialog.tscn",
	"image_lightbox": "res://scenes/messages/image_lightbox.tscn",
	"emoji_picker": "res://scenes/messages/emoji_picker.tscn",
	"channel_permissions": "res://scenes/admin/channel_permission_dialog.tscn",
	"ban_list": "res://scenes/admin/ban_list_dialog.tscn",
	"server_management": "res://scenes/admin/server_management_panel.tscn",
	"screen_picker": "res://scenes/voice/screen_picker_dialog.tscn",
	"confirm": "res://scenes/common/confirm_dialog.tscn",
	"create_space": "res://scenes/admin/create_space_dialog.tscn",
	"edit_category": "res://scenes/admin/edit_category_dialog.tscn",
	"delete_category": "res://scenes/admin/delete_category_dialog.tscn",
	"report_user": "res://scenes/admin/report_user_dialog.tscn",
	"audit_log": "res://scenes/admin/audit_log_panel.tscn",
	"change_password": "res://scenes/user/change_password_dialog.tscn",
	"delete_account": "res://scenes/user/delete_account_dialog.tscn",
	"two_factor": "res://scenes/user/two_factor_dialog.tscn",
	"profile_export": "res://scenes/user/profile_export_dialog.tscn",
	"profile_import": "res://scenes/user/profile_import_dialog.tscn",
	"folder_color": "res://scenes/sidebar/folder_color_dialog.tscn",
}

## Surface catalog sections for list_surfaces filtering.
const SURFACE_SECTIONS: Dictionary = {
	"main": "Main Window & Navigation",
	"sidebar": "Sidebar",
	"channels": "Channel List & Topics",
	"messages": "Message View",
	"composer": "Message Composer",
	"members": "Member List",
	"voice": "Voice & Video",
	"admin": "Admin & Settings",
	"dialogs": "Dialogs & Overlays",
	"user": "User Profile & Settings",
}

## Section prereqs lookup via dictionary (avoids >6 returns).
const _PREREQS: Dictionary = {
	1: {},
	2: {"needs_server": true},
	3: {"needs_server": true, "needs_space": true},
	4: {"needs_server": true, "needs_space": true, "needs_channel": true},
	5: {"needs_server": true, "needs_space": true, "needs_channel": true},
	6: {"needs_server": true, "needs_space": true},
	7: {"needs_voice": true},
	8: {"needs_server": true, "needs_admin": true},
	9: {"needs_server": true, "needs_admin": true},
	10: {},
}

## Section number → navigation callable lookup.
## Built in _init to avoid match statements with >6 returns.
var _section_handlers: Dictionary = {}

var _c: Node # Client autoload


func _init(client_node: Node) -> void:
	_c = client_node
	_section_handlers = {
		1: _nav_main,
		2: _nav_sidebar,
		3: _nav_channels,
		4: _nav_messages,
		5: _nav_composer,
		6: _nav_members,
		7: _nav_voice,
		8: _nav_admin,
		9: _nav_admin,
		10: _nav_user,
	}


func navigate_to_surface(
	surface_id: String, state: String = "default"
) -> Dictionary:
	if surface_id.is_empty():
		return {"error": "surface_id is required"}

	var parts: PackedStringArray = surface_id.split(".")
	if parts.size() != 2:
		return {
			"error": "Invalid surface_id format, expected N.N: %s"
			% surface_id,
		}

	var section: int = parts[0].to_int()
	var item: int = parts[1].to_int()
	var handler: Callable = _section_handlers.get(
		section, Callable()
	)
	if not handler.is_valid():
		return {"error": "Unknown section: %d" % section}

	var result: Dictionary = await handler.call(item, state)
	if result.has("error"):
		return result

	await _c.get_tree().process_frame
	result["ok"] = true
	result["surface_id"] = surface_id
	return result


func open_dialog(
	dialog_name: String, args: Dictionary = {}
) -> Dictionary:
	if dialog_name.is_empty():
		return {"error": "dialog_name is required"}

	var scene_path: String = DIALOG_MAP.get(dialog_name, "")
	if scene_path.is_empty():
		return {
			"error": "Unknown dialog: %s" % dialog_name,
			"available": DIALOG_MAP.keys(),
		}

	if not ResourceLoader.exists(scene_path):
		return {
			"error": "Dialog scene not found: %s" % scene_path,
		}

	var scene: PackedScene = load(scene_path)
	var instance: Node = scene.instantiate()

	if instance.has_method("setup"):
		instance.call("setup", args)

	_c.get_tree().root.add_child(instance)
	await _c.get_tree().process_frame

	return {
		"ok": true,
		"dialog_name": dialog_name,
		"scene_path": scene_path,
	}


func open_context_menu(args: Dictionary) -> Dictionary:
	var target: String = args.get("target", "")
	if target.is_empty():
		return {
			"error": "target is required",
			"available": CONTEXT_MENU_TARGETS,
		}
	if not target in CONTEXT_MENU_TARGETS:
		return {
			"error": "Unknown target: %s" % target,
			"available": CONTEXT_MENU_TARGETS,
		}

	var tree: SceneTree = _c.get_tree()
	var node: Control = _find_context_target(tree, target, args)
	if node == null:
		return {"error": "No %s node found to right-click" % target}

	# Simulate a right-click at the center of the node
	var rect: Rect2 = node.get_global_rect()
	var pos: Vector2 = rect.position + rect.size / 2.0

	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame

	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	await tree.process_frame

	# Wait an extra frame for the popup to appear
	await tree.process_frame
	return {
		"ok": true,
		"target": target,
		"position": {"x": int(pos.x), "y": int(pos.y)},
	}


func _find_context_target(
	tree: SceneTree, target: String, args: Dictionary
) -> Control:
	var group_map: Dictionary = {
		"message": "cozy_messages",
		"channel": "channel_items",
		"member": "member_items",
		"guild_icon": "guild_icons",
		"category": "category_items",
	}
	var group: String = group_map.get(target, "")

	# Try group-based lookup first
	var nodes: Array[Node] = tree.get_nodes_in_group(group)
	if not nodes.is_empty():
		var index: int = args.get("index", 0)
		index = clampi(index, 0, nodes.size() - 1)
		if nodes[index] is Control:
			return nodes[index] as Control
		return null

	# Fallback: walk tree looking for class name patterns
	var class_hints: Dictionary = {
		"message": "cozy_message",
		"channel": "channel_item",
		"member": "member_item",
		"guild_icon": "guild_icon",
		"category": "category_item",
	}
	var hint: String = class_hints.get(target, "")
	return _find_node_by_script_hint(tree.root, hint)


func _find_node_by_script_hint(
	root: Node, hint: String
) -> Control:
	for child in root.get_children():
		if child is Control:
			var script: Script = child.get_script()
			if script != null:
				var path: String = script.resource_path
				if hint in path.get_file().to_lower():
					return child as Control
		var found: Control = _find_node_by_script_hint(
			child, hint
		)
		if found != null:
			return found
	return null


func set_mock_state(args: Dictionary) -> Dictionary:
	var mock_state: String = args.get("state", "")
	if mock_state.is_empty():
		return {
			"error": "state is required",
			"available": ["loading", "error", "empty", "reset"],
		}

	var tree: SceneTree = _c.get_tree()
	var target_dialog: String = args.get("dialog", "")

	# Find the topmost dialog (modal_base or popup)
	var dialog: Node = _find_open_dialog(tree, target_dialog)
	if dialog == null:
		return {"error": "No open dialog found"}

	match mock_state:
		"loading":
			_apply_loading_state(dialog)
		"error":
			var message: String = args.get(
				"message", "Something went wrong"
			)
			_apply_error_state(dialog, message)
		"empty":
			_apply_empty_state(dialog)
		"reset":
			_reset_mock_state(dialog)
		_:
			return {"error": "Unknown state: %s" % mock_state}

	await tree.process_frame
	return {
		"ok": true,
		"state": mock_state,
		"dialog": dialog.name,
	}


func _find_open_dialog(
	tree: SceneTree, name_hint: String
) -> Node:
	# Walk root children in reverse (topmost = last added)
	var root: Node = tree.root
	for i in range(root.get_child_count() - 1, -1, -1):
		var child: Node = root.get_child(i)
		if child.is_in_group("themed") and child is Control:
			# Check if it looks like a dialog/modal
			var script: Script = child.get_script()
			if script == null:
				continue
			var path: String = script.resource_path
			if (
				"modal" in path or "dialog" in path
				or "panel" in path or "settings" in path
			):
				if name_hint.is_empty():
					return child
				if name_hint in path.get_file().to_lower():
					return child
	return null


func _apply_loading_state(dialog: Node) -> void:
	# Find all buttons and disable them with "Loading..." text
	var buttons: Array[Node] = _find_nodes_of_type(
		dialog, "Button"
	)
	for btn in buttons:
		if btn is Button and btn.visible:
			btn.set_meta("_mock_original_text", btn.text)
			btn.set_meta("_mock_original_disabled", btn.disabled)
			btn.disabled = true
			if not btn.text.is_empty():
				btn.text = "Loading..."


func _apply_error_state(dialog: Node, message: String) -> void:
	# Find a label that looks like an error label
	var found: bool = false
	if "_error_label" in dialog:
		var label: Variant = dialog.get("_error_label")
		if label is Label:
			label.text = message
			label.visible = true
			found = true

	if not found:
		# Walk children for any Label named *error*
		var labels: Array[Node] = _find_nodes_of_type(
			dialog, "Label"
		)
		for lbl in labels:
			if "error" in lbl.name.to_lower() and lbl is Label:
				lbl.text = message
				lbl.visible = true
				found = true
				break

	if not found:
		# Create a temporary error label
		var err_label := Label.new()
		err_label.name = "MockErrorLabel"
		err_label.text = message
		err_label.add_theme_color_override(
			"font_color", Color.RED
		)
		err_label.set_meta("_mock_created", true)
		dialog.add_child(err_label)


func _apply_empty_state(dialog: Node) -> void:
	# Hide all content containers to simulate empty state
	for child in dialog.get_children():
		if child is ScrollContainer or child is ItemList:
			child.set_meta(
				"_mock_original_visible", child.visible
			)
			child.visible = false


func _reset_mock_state(dialog: Node) -> void:
	# Restore button states
	var buttons: Array[Node] = _find_nodes_of_type(
		dialog, "Button"
	)
	for btn in buttons:
		if btn is Button and btn.has_meta("_mock_original_text"):
			btn.text = btn.get_meta("_mock_original_text")
			btn.disabled = btn.get_meta(
				"_mock_original_disabled"
			)
			btn.remove_meta("_mock_original_text")
			btn.remove_meta("_mock_original_disabled")

	# Restore visibility
	for child in dialog.get_children():
		if child.has_meta("_mock_original_visible"):
			child.visible = child.get_meta(
				"_mock_original_visible"
			)
			child.remove_meta("_mock_original_visible")

	# Remove any mock-created labels
	var to_remove: Array[Node] = []
	for child in dialog.get_children():
		if child.has_meta("_mock_created"):
			to_remove.append(child)
	for node in to_remove:
		node.queue_free()


func _find_nodes_of_type(
	root: Node, type_name: String
) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child.get_class() == type_name:
			result.append(child)
		result.append_array(
			_find_nodes_of_type(child, type_name)
		)
	return result


func set_viewport_size(args: Dictionary) -> Dictionary:
	var width: int = args.get("width", 0)
	var height: int = args.get("height", 0)
	var preset: String = args.get("preset", "")

	if not preset.is_empty():
		match preset:
			"compact":
				width = 480; height = 800
			"medium":
				width = 700; height = 600
			"full":
				width = 1280; height = 720
			"mobile":
				width = 360; height = 640
			"tablet":
				width = 768; height = 1024
			"1080p":
				width = 1920; height = 1080
			_:
				return {"error": "Unknown preset: %s" % preset}

	if width <= 0:
		return {"error": "width is required (or use preset)"}
	if height <= 0:
		height = 720

	DisplayServer.window_set_size(Vector2i(width, height))
	await _c.get_tree().process_frame
	return {"ok": true, "width": width, "height": height}


func list_surfaces(section_filter: String = "") -> Dictionary:
	var entries: Array = []
	for section_key in SURFACE_SECTIONS:
		if (
			not section_filter.is_empty()
			and section_key != section_filter
		):
			continue
		entries.append({
			"section": section_key,
			"name": SURFACE_SECTIONS[section_key],
		})
	return {"ok": true, "sections": entries}


func get_surface_info(surface_id: String) -> Dictionary:
	if surface_id.is_empty():
		return {"error": "surface_id is required"}

	var parts: PackedStringArray = surface_id.split(".")
	if parts.size() != 2:
		return {
			"error": "Invalid surface_id format: %s" % surface_id,
		}

	var section: int = parts[0].to_int()
	var prereqs: Dictionary = _prereqs_for_section(section)

	return {
		"ok": true,
		"surface_id": surface_id,
		"section": section,
		"prereqs": prereqs,
	}


# --- Internal navigation by section.item ---

func _nav_main(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			DisplayServer.window_set_size(Vector2i(1280, 720))
			return {"navigated": "main_window_full"}
		2:
			return {"navigated": "welcome_screen"}
		4:
			if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
				DisplayServer.window_set_size(Vector2i(480, 800))
				await _c.get_tree().process_frame
			AppState.toggle_sidebar_drawer()
			return {"navigated": "mobile_drawer"}
		_:
			return {"navigated": "main_%d" % item}


func _nav_sidebar(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			return {"navigated": "guild_bar"}
		10:
			return await open_dialog("add_server")
		_:
			return {"navigated": "sidebar_%d" % item}


func _nav_channels(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			if AppState.current_space_id.is_empty():
				var spaces: Array = _c._space_cache.keys()
				if not spaces.is_empty():
					AppState.select_space(spaces[0])
			return {"navigated": "channel_list"}
		_:
			return {"navigated": "channels_%d" % item}


func _nav_messages(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			return {"navigated": "message_view"}
		_:
			return {"navigated": "messages_%d" % item}


func _nav_composer(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			return {"navigated": "composer"}
		_:
			return {"navigated": "composer_%d" % item}


func _nav_members(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			if not AppState.member_list_visible:
				AppState.toggle_member_list()
			return {"navigated": "member_list"}
		_:
			return {"navigated": "members_%d" % item}


func _nav_voice(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			AppState.open_voice_view()
			return {"navigated": "voice_view"}
		_:
			return {"navigated": "voice_%d" % item}


func _nav_admin(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			return await open_dialog("space_settings")
		_:
			return {"navigated": "admin_%d" % item}


func _nav_user(
	item: int, _state: String
) -> Dictionary:
	match item:
		1:
			return await open_dialog("profile_card")
		2:
			AppState.settings_opened.emit("")
			return {"navigated": "app_settings"}
		_:
			return {"navigated": "user_%d" % item}


func _prereqs_for_section(section: int) -> Dictionary:
	return _PREREQS.get(section, {})
