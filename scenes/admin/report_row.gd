extends VBoxContainer

signal actioned(report_id: String, action_type: String)
signal dismissed(report_id: String)

const CATEGORY_LABELS := {
	"csam": "CSAM",
	"terrorism": "Terrorism",
	"fraud": "Fraud / Scam",
	"hate": "Hate Speech",
	"violence": "Violence",
	"self_harm": "Self-Harm",
	"other": "Other",
}

var _report_id: String = ""
var _report_data: Dictionary = {}
var _action_menu: PopupMenu

@onready var _category_label: Label = $TopRow/CategoryLabel
@onready var _target_label: Label = $TopRow/TargetLabel
@onready var _status_label: Label = $TopRow/StatusLabel
@onready var _time_label: Label = $TopRow/TimeLabel
@onready var _desc_label: Label = $DescriptionLabel
@onready var _reporter_label: Label = $ReporterLabel
@onready var _action_btn: Button = $ActionRow/ActionButton
@onready var _dismiss_btn: Button = $ActionRow/DismissButton
@onready var _action_row: HBoxContainer = $ActionRow

func _ready() -> void:
	_action_btn.pressed.connect(_show_action_menu)
	_dismiss_btn.pressed.connect(func(): dismissed.emit(_report_id))

	_action_menu = PopupMenu.new()
	_action_menu.id_pressed.connect(_on_action_menu_pressed)
	add_child(_action_menu)

func setup(data: Dictionary) -> void:
	_report_data = data
	_report_id = str(data.get("id", ""))
	var cat: String = str(data.get("category", "other"))
	_category_label.text = CATEGORY_LABELS.get(cat, cat)

	var target_type: String = str(data.get("target_type", ""))
	var target_id: String = str(data.get("target_id", ""))
	_resolve_target(target_type, target_id)

	var status: String = str(data.get("status", "pending"))
	_status_label.text = status.capitalize()
	if status == "pending":
		_status_label.add_theme_color_override(
			"font_color", Color(1.0, 0.8, 0.2)
		)
	elif status == "actioned":
		_status_label.add_theme_color_override(
			"font_color", Color(0.3, 0.8, 0.3)
		)
	else:
		_status_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6)
		)

	var created: String = str(data.get("created_at", ""))
	_time_label.text = _relative_time(created)
	_time_label.tooltip_text = created

	var desc = data.get("description", null)
	if desc is String and not desc.is_empty():
		_desc_label.text = desc
		_desc_label.visible = true

	_resolve_reporter(data)

	_action_row.visible = status == "pending"

func _resolve_target(target_type: String, target_id: String) -> void:
	if target_type == "message":
		var msg: Dictionary = Client.get_message_by_id(target_id)
		if not msg.is_empty():
			var preview: String = msg.get("content", "")
			if preview.length() > 60:
				preview = preview.substr(0, 60) + "..."
			var author: Dictionary = msg.get("author", {})
			var author_name: String = author.get("display_name", "")
			if not author_name.is_empty():
				_target_label.text = "%s: %s" % [author_name, preview]
			else:
				_target_label.text = "Message: %s" % preview
		else:
			_target_label.text = "Message %s" % target_id
		_target_label.tooltip_text = "Message ID: %s" % target_id
	else:
		var user: Dictionary = Client.get_user_by_id(target_id)
		if not user.is_empty():
			_target_label.text = "User: %s" % user.get(
				"display_name", target_id
			)
		else:
			_target_label.text = "User %s" % target_id
		_target_label.tooltip_text = "User ID: %s" % target_id

func _resolve_reporter(data: Dictionary) -> void:
	var reporter_id = data.get("reporter_id", null)
	if reporter_id == null or str(reporter_id).is_empty():
		_reporter_label.visible = false
		return
	var rid: String = str(reporter_id)
	var user: Dictionary = Client.get_user_by_id(rid)
	if not user.is_empty():
		_reporter_label.text = "Reported by %s" % user.get(
			"display_name", rid
		)
	else:
		_reporter_label.text = "Reported by %s" % rid
	_reporter_label.visible = true

func _show_action_menu() -> void:
	_action_menu.clear()
	var target_type: String = str(_report_data.get("target_type", ""))
	_action_menu.add_item("Mark Reviewed", 0)
	if target_type == "message":
		_action_menu.add_item("Delete Message", 1)
	var target_id: String = str(_report_data.get("target_id", ""))
	if not target_id.is_empty() and target_id != Client.current_user.get("id", ""):
		_action_menu.add_item("Kick User", 2)
		_action_menu.add_item("Ban User", 3)

	var pos := _action_btn.global_position + Vector2(0, _action_btn.size.y)
	_action_menu.hide()
	_action_menu.position = Vector2i(int(pos.x), int(pos.y))
	_action_menu.popup()

func _on_action_menu_pressed(id: int) -> void:
	match id:
		0:
			actioned.emit(_report_id, "reviewed")
		1:
			actioned.emit(_report_id, "delete_message")
		2:
			actioned.emit(_report_id, "kick")
		3:
			actioned.emit(_report_id, "ban")

func _relative_time(iso: String) -> String:
	if iso.is_empty():
		return ""
	var now: float = Time.get_unix_time_from_system()
	var dt := Time.get_datetime_dict_from_datetime_string(iso, false)
	if dt.is_empty():
		return iso
	var then: float = Time.get_unix_time_from_datetime_dict(dt)
	var diff: float = now - then
	if diff < 60:
		return "now"
	if diff < 3600:
		return "%dm ago" % int(diff / 60.0)
	if diff < 86400:
		return "%dh ago" % int(diff / 3600.0)
	return "%dd ago" % int(diff / 86400.0)
