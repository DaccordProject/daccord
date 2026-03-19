class_name ClientTestApiNavigate
extends RefCounted

## Navigation helpers for the Client Test API.
## Surface catalog, dialog map, and viewport resize presets.

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
