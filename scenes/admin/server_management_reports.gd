class_name ServerManagementReports
extends RefCounted

## Reports tab logic for server_management_panel.
## Extracted to keep the main panel under the 800-line limit.

const ConfirmDialogScene := preload(
	"res://scenes/admin/confirm_dialog.tscn"
)
const ReportRowScene := preload("res://scenes/admin/report_row.tscn")

var _panel: Control
var _reports_list: VBoxContainer
var _reports_filter: OptionButton
var _reports_error: Label
var _reports_empty: Label
var _reports_data: Array = []
var _reports_has_more: bool = false
var _reports_last_id: String = ""
var _reports_load_more_btn: Button


func _init(panel: Control) -> void:
	_panel = panel


func build_page(
	page_vbox: Callable,
	error_label: Callable,
	clear_children: Callable,
) -> VBoxContainer:
	var vbox: VBoxContainer = page_vbox.call(tr("Reports (All Spaces)"))

	# Filter row
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	var filter_lbl := Label.new()
	filter_lbl.text = tr("Status:")
	filter_lbl.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	filter_row.add_child(filter_lbl)

	_reports_filter = OptionButton.new()
	_reports_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reports_filter.add_item(tr("All"), 0)
	_reports_filter.add_item(tr("Pending"), 1)
	_reports_filter.add_item(tr("Actioned"), 2)
	_reports_filter.add_item(tr("Dismissed"), 3)
	_reports_filter.item_selected.connect(
		func(_idx: int) -> void: fetch_reports(clear_children)
	)
	filter_row.add_child(_reports_filter)
	vbox.add_child(filter_row)

	# Error label
	_reports_error = error_label.call()
	vbox.add_child(_reports_error)

	# Empty label
	_reports_empty = Label.new()
	_reports_empty.text = tr("No reports.")
	_reports_empty.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_reports_empty.visible = false
	vbox.add_child(_reports_empty)

	# Report list
	_reports_list = VBoxContainer.new()
	_reports_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_reports_list)

	# Load More button
	_reports_load_more_btn = SettingsBase.create_secondary_button(
		"Load More"
	)
	_reports_load_more_btn.visible = false
	_reports_load_more_btn.pressed.connect(
		func() -> void: _fetch_more_reports(clear_children)
	)
	vbox.add_child(_reports_load_more_btn)

	AppState.reports_updated.connect(
		func(_sid: String) -> void: fetch_reports(clear_children)
	)
	fetch_reports.call_deferred(clear_children)
	return vbox


func fetch_reports(
	clear_children: Callable, append: bool = false,
) -> void:
	_reports_error.visible = false
	if not append:
		clear_children.call(_reports_list)
		_reports_data = []
		_reports_last_id = ""
		_reports_has_more = false
		_reports_load_more_btn.visible = false
		_reports_empty.visible = false
		var loading := Label.new()
		loading.text = tr("Loading reports...")
		loading.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		_reports_list.add_child(loading)

	var statuses := ["", "pending", "actioned", "dismissed"]
	var status_filter: String = statuses[_reports_filter.selected]

	# Gather all space IDs
	var space_ids: Array = []
	for space in Client.spaces:
		var sid: String = space.get("id", "")
		if not sid.is_empty():
			space_ids.append(sid)

	if space_ids.is_empty():
		if not append:
			clear_children.call(_reports_list)
		_reports_empty.visible = true
		return

	# Fetch from all spaces
	var all_new: Array = []
	for sid in space_ids:
		var query: Dictionary = {"limit": 25}
		if not status_filter.is_empty():
			query["status"] = status_filter
		if append and not _reports_last_id.is_empty():
			query["before"] = _reports_last_id
		var result: RestResult = await Client.admin.get_reports(
			sid, query
		)
		if result == null or not result.ok:
			continue
		var reports: Array = (
			result.data if result.data is Array else []
		)
		for report in reports:
			var rd: Dictionary = (
				report if report is Dictionary else {}
			)
			if rd.has("id"):
				rd["_space_id"] = sid
				all_new.append(rd)

	if not append:
		clear_children.call(_reports_list)

	if all_new.is_empty() and _reports_data.is_empty():
		_reports_empty.visible = true
		return
	_reports_empty.visible = false

	# Sort by created_at descending
	all_new.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				str(a.get("created_at", ""))
				> str(b.get("created_at", ""))
			)
	)

	_reports_data.append_array(all_new)
	if all_new.size() > 0:
		_reports_last_id = str(all_new.back().get("id", ""))

	for report_dict in all_new:
		var row := ReportRowScene.instantiate()
		_reports_list.add_child(row)
		row.setup(report_dict)
		row.actioned.connect(_on_report_actioned)
		row.dismissed.connect(_on_report_dismissed)

		# Show space name for context
		var sid: String = report_dict.get("_space_id", "")
		var space: Dictionary = Client.get_space_by_id(sid)
		var sname: String = space.get("name", sid)
		row.tooltip_text = tr("Space: %s") % sname


func _fetch_more_reports(clear_children: Callable) -> void:
	_reports_load_more_btn.disabled = true
	_reports_load_more_btn.text = tr("Loading...")
	await fetch_reports(clear_children, true)
	_reports_load_more_btn.disabled = false
	_reports_load_more_btn.text = tr("Load More")


func _on_report_actioned(
	report_id: String, action_type: String,
) -> void:
	var report: Dictionary = _find_report_by_id(report_id)
	var sid: String = report.get("_space_id", "")
	if sid.is_empty():
		return

	match action_type:
		"reviewed":
			await Client.admin.resolve_report(
				sid, report_id,
				{"status": "actioned", "action_taken": "reviewed"}
			)
		"delete_message":
			var target_id: String = str(
				report.get("target_id", "")
			)
			if not target_id.is_empty():
				Client.remove_message(target_id)
			await Client.admin.resolve_report(
				sid, report_id,
				{
					"status": "actioned",
					"action_taken": "message deleted",
				}
			)
		"kick":
			var target_id: String = _resolve_report_user_id(
				report
			)
			if not target_id.is_empty():
				var dialog := ConfirmDialogScene.instantiate()
				_panel.get_tree().root.add_child(dialog)
				var user: Dictionary = Client.get_user_by_id(
					target_id
				)
				var dname: String = user.get(
					"display_name", target_id
				)
				dialog.setup(
					tr("Kick User"),
					tr("Kick %s from this space?") % dname,
					tr("Kick"), true
				)
				dialog.confirmed.connect(func():
					await Client.admin.kick_member(
						sid, target_id
					)
					await Client.admin.resolve_report(
						sid, report_id,
						{
							"status": "actioned",
							"action_taken": "user kicked",
						}
					)
				)
		"ban":
			var target_id: String = _resolve_report_user_id(
				report
			)
			if not target_id.is_empty():
				var dialog := ConfirmDialogScene.instantiate()
				_panel.get_tree().root.add_child(dialog)
				var user: Dictionary = Client.get_user_by_id(
					target_id
				)
				var dname: String = user.get(
					"display_name", target_id
				)
				dialog.setup(
					tr("Ban User"),
					tr("Ban %s from this space?") % dname,
					tr("Ban"), true
				)
				dialog.confirmed.connect(func():
					await Client.admin.ban_member(
						sid, target_id
					)
					await Client.admin.resolve_report(
						sid, report_id,
						{
							"status": "actioned",
							"action_taken": "user banned",
						}
					)
				)


func _on_report_dismissed(report_id: String) -> void:
	var report: Dictionary = _find_report_by_id(report_id)
	var sid: String = report.get("_space_id", "")
	if sid.is_empty():
		return
	await Client.admin.resolve_report(
		sid, report_id, {"status": "dismissed"}
	)


func _find_report_by_id(report_id: String) -> Dictionary:
	for r in _reports_data:
		if str(r.get("id", "")) == report_id:
			return r
	return {}


func _resolve_report_user_id(report: Dictionary) -> String:
	var target_type: String = str(
		report.get("target_type", "")
	)
	var target_id: String = str(report.get("target_id", ""))
	if target_type == "user":
		return target_id
	if target_type == "message":
		var msg: Dictionary = Client.get_message_by_id(target_id)
		var author: Dictionary = msg.get("author", {})
		return author.get("id", "")
	return ""
