extends ModalBase

const ReportRowScene := preload("res://scenes/admin/report_row.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

const PAGE_SIZE := 25

var _space_id: String = ""
var _all_space_ids: Array = []
var _all_reports: Array = []
var _last_report_id: String = ""
var _has_more: bool = false
var _is_server_wide: bool = false

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _filter_option: OptionButton = $CenterContainer/Panel/VBox/FilterRow/FilterOption
@onready var _report_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/ReportList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _load_more_btn: Button = $CenterContainer/Panel/VBox/LoadMoreButton

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 600, 0)
	_close_btn.pressed.connect(_close)
	_filter_option.item_selected.connect(_on_filter_changed)
	_load_more_btn.pressed.connect(_on_load_more)

	_filter_option.add_item("All", 0)
	_filter_option.add_item("Pending", 1)
	_filter_option.add_item("Actioned", 2)
	_filter_option.add_item("Dismissed", 3)

func setup(space_id: String) -> void:
	_space_id = space_id
	_is_server_wide = false
	_all_space_ids = [space_id]
	AppState.reports_updated.connect(_on_reports_updated)
	_load_reports()

func setup_server_wide() -> void:
	_is_server_wide = true
	_title_label.text = "All Reports (Server-wide)"
	_all_space_ids.clear()
	for space in Client.spaces:
		var sid: String = space.get("id", "")
		if not sid.is_empty():
			_all_space_ids.append(sid)
	if _all_space_ids.size() > 0:
		_space_id = _all_space_ids[0]
	AppState.reports_updated.connect(_on_reports_updated)
	_load_reports()

func _load_reports() -> void:
	for child in _report_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_reports.clear()
	_last_report_id = ""
	_has_more = false
	_load_more_btn.visible = false

	if _is_server_wide:
		await _fetch_all_spaces()
	else:
		await _fetch_page()

func _fetch_page() -> void:
	var query: Dictionary = {"limit": PAGE_SIZE}
	if not _last_report_id.is_empty():
		query["before"] = _last_report_id

	var status_filter: String = _get_selected_status()
	if not status_filter.is_empty():
		query["status"] = status_filter

	var result: RestResult = await Client.admin.get_reports(
		_space_id, query
	)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load reports"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var reports: Array = result.data if result.data is Array else []

	if reports.is_empty() and _all_reports.is_empty():
		_empty_label.visible = true
		return

	for report in reports:
		var report_dict: Dictionary = report if report is Dictionary else {}
		if report_dict.has("id"):
			report_dict["_space_id"] = _space_id
			_all_reports.append(report_dict)
			_last_report_id = str(report_dict.get("id", ""))

	_has_more = reports.size() >= PAGE_SIZE
	_load_more_btn.visible = _has_more
	_rebuild_list()

func _fetch_all_spaces() -> void:
	var status_filter: String = _get_selected_status()
	for sid in _all_space_ids:
		var query: Dictionary = {"limit": PAGE_SIZE}
		if not status_filter.is_empty():
			query["status"] = status_filter
		var result: RestResult = await Client.admin.get_reports(
			sid, query
		)
		if result == null or not result.ok:
			continue
		var reports: Array = result.data if result.data is Array else []
		for report in reports:
			var report_dict: Dictionary = report if report is Dictionary else {}
			if report_dict.has("id"):
				report_dict["_space_id"] = sid
				_all_reports.append(report_dict)

	if _all_reports.is_empty():
		_empty_label.visible = true
		return

	# Sort by created_at descending
	_all_reports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("created_at", "")) > str(b.get("created_at", ""))
	)
	_rebuild_list()

func _rebuild_list() -> void:
	for child in _report_list.get_children():
		child.queue_free()

	if _all_reports.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false

	for report_dict in _all_reports:
		var row := ReportRowScene.instantiate()
		_report_list.add_child(row)
		row.setup(report_dict)
		row.actioned.connect(_on_action_report)
		row.dismissed.connect(_on_dismiss_report)

		# Show space name badge for server-wide view
		if _is_server_wide:
			var sid: String = report_dict.get("_space_id", "")
			var space: Dictionary = Client.get_space_by_id(sid)
			var sname: String = space.get("name", sid)
			row.tooltip_text = "Space: %s" % sname

func _get_selected_status() -> String:
	var idx: int = _filter_option.selected
	var statuses := ["", "pending", "actioned", "dismissed"]
	if idx >= 0 and idx < statuses.size():
		return statuses[idx]
	return ""

func _on_filter_changed(_idx: int) -> void:
	_load_reports()

func _on_load_more() -> void:
	_load_more_btn.disabled = true
	_load_more_btn.text = "Loading..."
	await _fetch_page()
	_load_more_btn.disabled = false
	_load_more_btn.text = "Load More"

func _on_action_report(report_id: String, action_type: String) -> void:
	var report: Dictionary = _find_report(report_id)
	var sid: String = report.get("_space_id", _space_id)

	match action_type:
		"reviewed":
			_resolve_and_reload(sid, report_id, "reviewed")
		"delete_message":
			var target_id: String = str(report.get("target_id", ""))
			if not target_id.is_empty():
				Client.remove_message(target_id)
			_resolve_and_reload(sid, report_id, "message deleted")
		"kick":
			var target_id: String = _resolve_user_id(report)
			if not target_id.is_empty():
				var dialog := ConfirmDialogScene.instantiate()
				get_tree().root.add_child(dialog)
				var user: Dictionary = Client.get_user_by_id(target_id)
				var dname: String = user.get("display_name", target_id)
				dialog.setup(
					"Kick User",
					"Kick %s from this space?" % dname,
					"Kick", true
				)
				dialog.confirmed.connect(func():
					await Client.admin.kick_member(sid, target_id)
					_resolve_and_reload(sid, report_id, "user kicked")
				)
		"ban":
			var target_id: String = _resolve_user_id(report)
			if not target_id.is_empty():
				var dialog := ConfirmDialogScene.instantiate()
				get_tree().root.add_child(dialog)
				var user: Dictionary = Client.get_user_by_id(target_id)
				var dname: String = user.get("display_name", target_id)
				dialog.setup(
					"Ban User",
					"Ban %s from this space?" % dname,
					"Ban", true
				)
				dialog.confirmed.connect(func():
					await Client.admin.ban_member(sid, target_id)
					_resolve_and_reload(sid, report_id, "user banned")
				)

func _resolve_and_reload(
	sid: String, report_id: String, action_taken: String,
) -> void:
	await Client.admin.resolve_report(
		sid, report_id,
		{"status": "actioned", "action_taken": action_taken}
	)

func _resolve_user_id(report: Dictionary) -> String:
	var target_type: String = str(report.get("target_type", ""))
	var target_id: String = str(report.get("target_id", ""))
	if target_type == "user":
		return target_id
	# For message reports, get the message author
	if target_type == "message":
		var msg: Dictionary = Client.get_message_by_id(target_id)
		var author: Dictionary = msg.get("author", {})
		return author.get("id", "")
	return ""

func _find_report(report_id: String) -> Dictionary:
	for r in _all_reports:
		if str(r.get("id", "")) == report_id:
			return r
	return {}

func _on_dismiss_report(report_id: String) -> void:
	var report: Dictionary = _find_report(report_id)
	var sid: String = report.get("_space_id", _space_id)
	await Client.admin.resolve_report(
		sid, report_id, {"status": "dismissed"}
	)

func _on_reports_updated(space_id: String) -> void:
	if _is_server_wide or space_id == _space_id:
		_load_reports()

func _exit_tree() -> void:
	if AppState.reports_updated.is_connected(_on_reports_updated):
		AppState.reports_updated.disconnect(_on_reports_updated)
	super._exit_tree()
